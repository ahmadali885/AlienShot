import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/annotation.dart';
import '../models/recording_settings.dart';
import '../services/recorder_service.dart';
import '../theme/app_theme.dart';
import '../widgets/annotation_painter.dart';
import '../widgets/annotation_session.dart';
import '../widgets/annotation_toolbar.dart';
import '../widgets/glass_container.dart';

/// The see-through overlay while recording: a countdown, an outline around
/// the recorded area, the timer/pause/stop bar and the annotation toolbar.
///
/// The window is excluded from capture, so none of this reaches the video
/// except the annotations, which are rendered separately and handed to the
/// recorder. Clicks pass through to other apps except over the controls —
/// or everywhere while a drawing tool is active.
class RecordingScreen extends StatefulWidget {
  const RecordingScreen({
    super.key,
    this.region,
    required this.settings,
    required this.onFinished,
    required this.onError,
  });

  /// The area being recorded, in this window's logical coordinates; null
  /// records the whole window (the full screen).
  final Rect? region;
  final RecordingSettings settings;
  final ValueChanged<String> onFinished;
  final ValueChanged<String> onError;

  @override
  State<RecordingScreen> createState() => RecordingScreenState();
}

enum _Stage { countdown, recording, stopping }

/// Public so the app's recording hotkeys can pause and stop it.
class RecordingScreenState extends State<RecordingScreen> {
  final AnnotationSession _session = AnnotationSession();
  final GlobalKey _barKey = GlobalKey();
  final GlobalKey _panelKey = GlobalKey();
  final GlobalKey _controlsKey = GlobalKey();
  final FocusNode _focusNode = FocusNode();

  _Stage _stage = _Stage.countdown;
  int _countdown = 3;
  String? _path;
  RecordingInfo? _info;
  bool _paused = false;
  final Stopwatch _elapsed = Stopwatch();
  Timer? _ticker;

  // Click-through areas last sent to the runner.
  List<Rect> _sentRects = const [];
  bool? _sentCaptureAll;

  // Annotation layer pushed to the recorder, at most every 80 ms.
  Timer? _overlayTimer;
  bool _overlayBusy = false;
  bool _overlayDirty = false;

  @override
  void initState() {
    super.initState();
    _session.addListener(_onSessionChanged);
    _runCountdown();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _overlayTimer?.cancel();
    _session.removeListener(_onSessionChanged);
    _session.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _runCountdown() async {
    for (var i = widget.settings.countdown; i > 0; i--) {
      if (!mounted) return;
      setState(() => _countdown = i);
      await Future.delayed(const Duration(seconds: 1));
    }
    if (!mounted) return;
    try {
      final path = await recorderService.newRecordingPath(widget.settings);
      _info = await recorderService.start(region: _region, path: path, settings: widget.settings);
      _path = path;
    } on PlatformException catch (e) {
      widget.onError(e.message ?? 'The recording could not start.');
      return;
    }
    if (!mounted) return;
    _elapsed.start();
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) => setState(() {}));
    setState(() => _stage = _Stage.recording);
  }

  Rect get _region => widget.region ?? Offset.zero & MediaQuery.of(context).size;

  bool get isRecording => _stage == _Stage.recording;

  Future<void> togglePause() async {
    if (_stage != _Stage.recording) return;
    if (_paused) {
      await recorderService.resume();
      _elapsed.start();
    } else {
      await recorderService.pause();
      _elapsed.stop();
    }
    setState(() => _paused = !_paused);
  }

  Future<void> stop() async {
    if (_stage == _Stage.stopping) return;
    if (_stage == _Stage.countdown) {
      // Nothing recorded yet: just leave.
      setState(() => _stage = _Stage.stopping);
      widget.onError('');
      return;
    }
    setState(() => _stage = _Stage.stopping);
    _elapsed.stop();
    try {
      await recorderService.stop();
      widget.onFinished(_path!);
    } on PlatformException catch (e) {
      widget.onError(e.message ?? 'The recording could not be saved.');
    }
  }

  void _onSessionChanged() {
    setState(() {});
    _overlayDirty = true;
    _overlayTimer ??= Timer(const Duration(milliseconds: 80), _pushOverlay);
  }

  /// Renders the marks (and the one being drawn) at up to the screen's pixel
  /// density — capped so a full 4K frame isn't re-sent on every stroke — and
  /// hands them to the recorder, which scales them onto each frame.
  Future<void> _pushOverlay() async {
    _overlayTimer = null;
    if (_overlayBusy || !mounted) return;
    _overlayBusy = true;
    _overlayDirty = false;
    try {
      final region = _region;
      if (_session.isEmpty) {
        await recorderService.setOverlay(null, 0, 0);
      } else {
        final ratio = View.of(context).devicePixelRatio;
        final scale = math.min(ratio, 2560 / region.width);
        final width = (region.width * scale).round();
        final height = (region.height * scale).round();
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder)
          ..scale(scale)
          ..translate(-region.left, -region.top);
        for (final a in _session.annotations) {
          AnnotationPainter.paintAnnotation(canvas, a);
        }
        final draft = _session.draft;
        if (draft != null) AnnotationPainter.paintAnnotation(canvas, draft);
        final image = await recorder.endRecording().toImage(width, height);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        image.dispose();
        if (bytes != null) await recorderService.setOverlay(bytes.buffer.asUint8List(), width, height);
      }
    } finally {
      _overlayBusy = false;
      if (_overlayDirty && mounted) _overlayTimer ??= Timer(const Duration(milliseconds: 80), _pushOverlay);
    }
  }

  /// Keeps clicks for us over the controls (and everywhere while drawing);
  /// everything else goes through to the apps being recorded.
  void _syncHitAreas() {
    // Once stopping, the app turns click-through off as the window goes back
    // to normal; a last rebuild here must not switch it on again, or the
    // next window would let every click fall through to the desktop.
    if (!mounted || _stage == _Stage.stopping) return;
    Rect? rectOf(GlobalKey key) {
      final box = key.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return null;
      return box.localToGlobal(Offset.zero) & box.size;
    }

    final rects = [
      for (final key in [_barKey, _panelKey, _controlsKey])
        if (rectOf(key) case final r?) r,
    ];
    final captureAll = _session.tool != null;
    final same = captureAll == _sentCaptureAll &&
        rects.length == _sentRects.length &&
        [for (var i = 0; i < rects.length; i++) rects[i] == _sentRects[i]].every((x) => x);
    if (same) return;
    _sentRects = rects;
    _sentCaptureAll = captureAll;
    recorderService.setClickThrough(enabled: true, captureAll: captureAll, rects: rects);
  }

  Future<void> _addText(Offset point) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add text'),
        content: TextField(controller: controller, autofocus: true, onSubmitted: (v) => Navigator.of(context).pop(v)),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(controller.text), child: const Text('Add')),
        ],
      ),
    );
    if (text != null && text.trim().isNotEmpty) _session.addText(point, text.trim());
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      // Back to the pointer, so clicks reach the apps again.
      _session.panel == ToolbarPanel.none ? _session.setTool(null) : _session.closePanel();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  String get _time {
    final s = _elapsed.elapsed.inSeconds;
    String two(int n) => n.toString().padLeft(2, '0');
    return s >= 3600 ? '${s ~/ 3600}:${two(s ~/ 60 % 60)}:${two(s % 60)}' : '${two(s ~/ 60)}:${two(s % 60)}';
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncHitAreas());
    final region = _region;
    final screen = MediaQuery.of(context).size;
    final drawing = _session.tool != null && _stage == _Stage.recording;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Outline just outside the recorded area (the window itself is
            // never captured, so it can't end up in the video).
            Positioned.fromRect(
              rect: region.inflate(3),
              child: IgnorePointer(
                child: CustomPaint(painter: _DashedOutlinePainter(paused: _paused)),
              ),
            ),
            // The marks, as the user sees them.
            Positioned.fromRect(
              rect: region,
              child: IgnorePointer(
                child: ClipRect(
                  child: CustomPaint(
                    painter: _ShiftedAnnotationPainter(
                      annotations: _session.annotations,
                      draft: _session.draft,
                      origin: region.topLeft,
                    ),
                  ),
                ),
              ),
            ),
            if (drawing)
              Positioned.fromRect(
                rect: region,
                child: MouseRegion(
                  cursor: switch (_session.tool) {
                    AnnotationTool.text => SystemMouseCursors.text,
                    AnnotationTool.stamp || AnnotationTool.eraser => SystemMouseCursors.click,
                    _ => SystemMouseCursors.precise,
                  },
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    dragStartBehavior: DragStartBehavior.down,
                    onPanStart: (d) => _session.dragStart(d.localPosition + region.topLeft),
                    onPanUpdate: (d) => _session.dragUpdate(d.localPosition + region.topLeft),
                    onPanEnd: (_) => _session.dragEnd(),
                    onTapUp: (d) {
                      final point = d.localPosition + region.topLeft;
                      if (_session.tool == AnnotationTool.text) {
                        _addText(point);
                      } else {
                        _session.tap(point);
                      }
                    },
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            if (_stage == _Stage.countdown)
              Positioned.fromRect(
                rect: region,
                child: IgnorePointer(child: Center(child: _Countdown(value: _countdown))),
              ),
            _ControlsBar(
              key: _controlsKey,
              region: region,
              screenSize: screen,
              time: _time,
              details: _info == null
                  ? null
                  : '${_info!.width}×${_info!.height} · ${_info!.codec} · ${widget.settings.fps} fps',
              recording: _stage == _Stage.recording,
              paused: _paused,
              onPause: togglePause,
              onStop: stop,
            ),
            if (_stage == _Stage.recording)
              AnnotationToolbar(
                recording: true,
                barKey: _barKey,
                panelKey: _panelKey,
                selection: region,
                screenSize: screen,
                tool: _session.tool,
                drawTool: _session.drawTool,
                shapeKind: _session.shapeKind,
                shapeFill: _session.shapeFill,
                stampKind: _session.stampKind,
                color: _session.color,
                strokeWidth: _session.strokeWidth,
                panel: _session.panel,
                canUndo: _session.canUndo,
                canRedo: _session.canRedo,
                canClear: _session.annotations.isNotEmpty,
                uploading: false,
                onToolChanged: _session.setTool,
                onPenPicked: _session.pickPen,
                onShapePicked: _session.pickShape,
                onStampPicked: _session.pickStamp,
                onColorChanged: _session.setColor,
                onStrokeWidthChanged: _session.setStrokeWidth,
                onPanelChanged: _session.setPanel,
                onUndo: _session.undo,
                onRedo: _session.redo,
                onClear: _session.clearAll,
              ),
          ],
        ),
      ),
    );
  }
}

class _ShiftedAnnotationPainter extends CustomPainter {
  _ShiftedAnnotationPainter({required this.annotations, required this.draft, required this.origin});

  final List<Annotation> annotations;
  final Annotation? draft;
  final Offset origin;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(-origin.dx, -origin.dy);
    for (final a in annotations) {
      AnnotationPainter.paintAnnotation(canvas, a);
    }
    if (draft != null) AnnotationPainter.paintAnnotation(canvas, draft!);
  }

  @override
  bool shouldRepaint(covariant _ShiftedAnnotationPainter oldDelegate) => true;
}

/// A dashed teal frame (amber while paused) around the recorded area.
class _DashedOutlinePainter extends CustomPainter {
  _DashedOutlinePainter({required this.paused});

  final bool paused;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = paused ? const Color(0xFFFFB454) : AppColors.accent2
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final path = Path()..addRect(Offset.zero & size);
    for (final metric in path.computeMetrics()) {
      for (double d = 0; d < metric.length; d += 14) {
        canvas.drawPath(metric.extractPath(d, math.min(d + 8, metric.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedOutlinePainter oldDelegate) => oldDelegate.paused != paused;
}

class _Countdown extends StatelessWidget {
  const _Countdown({required this.value});

  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      height: 120,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.ink.withValues(alpha: 0.72),
        border: Border.all(color: AppColors.accent2, width: 3),
      ),
      child: Text(
        '$value',
        style: const TextStyle(
          fontFamily: AppFonts.display,
          fontSize: 56,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// Timer, pause/resume and stop — below the recorded area when there's
/// room, else above it, else inside its bottom edge.
class _ControlsBar extends StatelessWidget {
  const _ControlsBar({
    super.key,
    required this.region,
    required this.screenSize,
    required this.time,
    required this.recording,
    required this.paused,
    required this.onPause,
    required this.onStop,
    this.details,
  });

  final Rect region;
  final Size screenSize;
  final String time;
  final bool recording;
  final bool paused;
  final VoidCallback onPause;
  final VoidCallback onStop;

  /// What is being written, e.g. "2560×1440 · H.264 · 60 fps".
  final String? details;

  static const double _height = 48;
  static const double _width = 236;

  @override
  Widget build(BuildContext context) {
    final palette = AlienPalette.of(context);
    final below = region.bottom + 12 + _height + 8 <= screenSize.height;
    final above = region.top - 12 - _height >= 8;
    final top = below
        ? region.bottom + 12
        : above
            ? region.top - 12 - _height
            : region.bottom - _height - 16;
    final left = (region.center.dx - _width / 2).clamp(8.0, math.max(8.0, screenSize.width - _width - 8)).toDouble();

    return Positioned(
      left: left,
      top: top,
      child: GlassContainer(
        borderRadius: _height / 2,
        child: SizedBox(
          width: _width,
          height: _height,
          child: Row(
            children: [
              const SizedBox(width: 16),
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: !recording
                      ? palette.textSoft
                      : paused
                          ? const Color(0xFFFFB454)
                          : const Color(0xFFE5484D),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Tooltip(
                  message: details ?? '',
                  child: Text(
                    recording ? time : 'Starting…',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppFonts.display,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: palette.text,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: paused ? 'Resume' : 'Pause',
                onPressed: recording ? onPause : null,
                icon: Icon(paused ? Icons.play_arrow_rounded : Icons.pause_rounded, color: palette.text),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: IconButton(
                  tooltip: 'Stop and save',
                  onPressed: onStop,
                  style: IconButton.styleFrom(backgroundColor: const Color(0xFFE5484D)),
                  icon: const Icon(Icons.stop_rounded, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
