import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/annotation.dart';
import '../models/recording_settings.dart';
import '../services/clipboard_service.dart';
import '../services/upload_service.dart';
import '../theme/app_theme.dart';
import '../widgets/annotation_painter.dart';
import '../widgets/annotation_toolbar.dart';
import '../widgets/glass_container.dart';

enum _Phase { selecting, annotating }

enum _ResizeHandlePosition { topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left }

/// A single full-screen surface that combines drag-to-select with inline
/// annotation — like Lightshot: no separate editor window ever appears, the
/// toolbar floats right next to the selection.
class LightshotCaptureScreen extends StatefulWidget {
  const LightshotCaptureScreen({
    super.key,
    required this.screenImage,
    required this.onClose,
    this.downscaleRetina = false,
    this.onRecord,
    this.recordSettings = const RecordingSettings(),
    this.onRecordSettingsChanged,
  });

  /// Already-decoded frame — the capture service hands over a [ui.Image]
  /// directly so the overlay can paint on its very first frame.
  final ui.Image screenImage;
  final VoidCallback onClose;

  /// Set when picking an area to *record*: the selection then gets the
  /// record setup bar (audio, frame rate, Record) instead of the annotation
  /// toolbar, and Record hands the area back here.
  final ValueChanged<Rect>? onRecord;
  final RecordingSettings recordSettings;
  final ValueChanged<RecordingSettings>? onRecordSettingsChanged;

  bool get recordMode => onRecord != null;

  /// Export at the screen's point size rather than its pixel size, so a 2x
  /// Retina capture isn't twice as big as what was on screen (Lightshot's
  /// "Downscale Retina screens").
  final bool downscaleRetina;

  @override
  State<LightshotCaptureScreen> createState() => _LightshotCaptureScreenState();
}

class _LightshotCaptureScreenState extends State<LightshotCaptureScreen> {
  final FocusNode _focusNode = FocusNode();

  _Phase _phase = _Phase.selecting;
  Offset? _dragStart;
  Offset? _dragCurrent;
  Rect? _selection;

  final List<Annotation> _annotations = [];
  Annotation? _draft;

  /// Earlier states of [_annotations], for undo/redo. Each change (a new
  /// mark, an erase, Delete all) pushes the state it replaced.
  final List<List<Annotation>> _undoStack = [];
  final List<List<Annotation>> _redoStack = [];

  /// Nothing is picked at first, as in Lightshot: until a tool is chosen,
  /// dragging inside the selection moves it instead of drawing.
  AnnotationTool? _tool;
  bool _movingSelection = false;
  bool _erasing = false;

  /// The Draw button's last pick, re-armed when it's pressed again.
  AnnotationTool _drawTool = AnnotationTool.pen;
  ShapeKind _shapeKind = ShapeKind.rectangle;
  ShapeFill _shapeFill = ShapeFill.none;
  StampKind _stampKind = StampKind.check;
  ToolbarPanel _panel = ToolbarPanel.none;
  Color _color = kAnnotationColors[1]; // red
  double _strokeWidth = kStrokeWidths[1];
  bool _uploading = false;

  /// Inline text tool: set to the tap point while the user is typing.
  Offset? _textEditPosition;
  final TextEditingController _textController = TextEditingController();
  final FocusNode _textFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Commit text when the inline field loses focus (e.g. user clicks elsewhere).
    _textFocusNode.addListener(() {
      if (!_textFocusNode.hasFocus && _textEditPosition != null) {
        _commitTextEdit();
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _textController.dispose();
    _textFocusNode.dispose();
    super.dispose();
  }

  Rect? get _liveSelectionRect {
    if (_dragStart == null || _dragCurrent == null) return null;
    return Rect.fromPoints(_dragStart!, _dragCurrent!);
  }

  // The annotate GestureDetector is exactly positioned/sized to the
  // selection, so its localPosition is already selection-relative
  // (0,0 == selection's top-left) — clamp against that, not screen space.
  Offset _clampToSelection(Offset point) {
    final sel = _selection!;
    return Offset(
      point.dx.clamp(0, sel.width),
      point.dy.clamp(0, sel.height),
    );
  }

  // Annotations are stored in absolute screen coordinates (not relative to
  // the selection) so that resizing the selection after drawing on it
  // doesn't shift already-drawn strokes — only what the crop shows changes.
  Offset _localToAbsolute(Offset local) => _clampToSelection(local) + _selection!.topLeft;

  /// Grows/shrinks `_selection` from one of its 8 handles, clamped to the
  /// screen and to a sane minimum size so it can never invert.
  void _resizeSelection(_ResizeHandlePosition handle, Offset delta, Size screenSize) {
    final current = _selection;
    if (current == null) return;

    double left = current.left;
    double top = current.top;
    double right = current.right;
    double bottom = current.bottom;

    const leftHandles = {
      _ResizeHandlePosition.topLeft,
      _ResizeHandlePosition.left,
      _ResizeHandlePosition.bottomLeft,
    };
    const rightHandles = {
      _ResizeHandlePosition.topRight,
      _ResizeHandlePosition.right,
      _ResizeHandlePosition.bottomRight,
    };
    const topHandles = {
      _ResizeHandlePosition.topLeft,
      _ResizeHandlePosition.top,
      _ResizeHandlePosition.topRight,
    };
    const bottomHandles = {
      _ResizeHandlePosition.bottomLeft,
      _ResizeHandlePosition.bottom,
      _ResizeHandlePosition.bottomRight,
    };

    if (leftHandles.contains(handle)) left += delta.dx;
    if (rightHandles.contains(handle)) right += delta.dx;
    if (topHandles.contains(handle)) top += delta.dy;
    if (bottomHandles.contains(handle)) bottom += delta.dy;

    left = left.clamp(0, screenSize.width);
    top = top.clamp(0, screenSize.height);
    right = right.clamp(0, screenSize.width);
    bottom = bottom.clamp(0, screenSize.height);

    const minSize = 24.0;
    if (right - left < minSize) {
      if (leftHandles.contains(handle)) {
        left = right - minSize;
      } else if (rightHandles.contains(handle)) {
        right = left + minSize;
      }
    }
    if (bottom - top < minSize) {
      if (topHandles.contains(handle)) {
        top = bottom - minSize;
      } else if (bottomHandles.contains(handle)) {
        bottom = top + minSize;
      }
    }

    setState(() => _selection = Rect.fromLTRB(left, top, right, bottom));
  }

  // --- Phase 1: dragging to pick the region ---

  void _handleSelectPanStart(DragStartDetails details) {
    setState(() {
      _dragStart = details.localPosition;
      _dragCurrent = details.localPosition;
    });
  }

  void _handleSelectPanUpdate(DragUpdateDetails details) {
    setState(() => _dragCurrent = details.localPosition);
  }

  void _handleSelectPanEnd(DragEndDetails details) {
    final rect = _liveSelectionRect;
    if (rect == null || rect.width < 12 || rect.height < 12) {
      setState(() {
        _dragStart = null;
        _dragCurrent = null;
      });
      return;
    }
    setState(() {
      _selection = rect;
      _phase = _Phase.annotating;
    });
  }

  /// A drag the system took away (e.g. the window lost the mouse) must not
  /// leave its zero-size start behind as a stuck dot.
  /// Record mode's "Full screen": the whole display, straight to setup.
  void _selectFullScreen() {
    setState(() {
      _selection = Offset.zero & MediaQuery.of(context).size;
      _dragStart = null;
      _dragCurrent = null;
      _phase = _Phase.annotating;
    });
  }

  void _handleSelectPanCancel() {
    setState(() {
      _dragStart = null;
      _dragCurrent = null;
    });
  }

  // --- Phase 2: annotating inside the locked selection ---

  void _handleAnnotatePanStart(DragStartDetails details) {
    _closePanel();
    final tool = _tool;
    if (tool == null) {
      _movingSelection = true;
      return;
    }
    final point = _localToAbsolute(details.localPosition);
    switch (tool) {
      case AnnotationTool.shape:
        setState(() => _draft = ShapeAnnotation(
              kind: _shapeKind,
              fill: _shapeFill,
              start: point,
              end: point,
              color: _color,
              strokeWidth: _strokeWidth,
            ));
      case AnnotationTool.pen:
      case AnnotationTool.highlighter:
        setState(() => _draft = FreehandAnnotation(
              points: [point],
              color: _color,
              strokeWidth: _strokeWidth,
              highlighter: tool == AnnotationTool.highlighter,
            ));
      case AnnotationTool.eraser:
        _erasing = true;
        _eraseAt(point);
      // Text and stamps go where the user clicks (see the tap handler).
      case AnnotationTool.text:
      case AnnotationTool.stamp:
        break;
    }
  }

  void _handleAnnotatePanUpdate(DragUpdateDetails details) {
    if (_movingSelection) {
      _moveSelection(details.delta, MediaQuery.of(context).size);
      return;
    }
    if (_erasing) {
      _eraseAt(_localToAbsolute(details.localPosition));
      return;
    }
    if (_draft == null) return;
    final point = _localToAbsolute(details.localPosition);
    setState(() {
      final draft = _draft;
      if (draft is ShapeAnnotation) {
        draft.end = point;
      } else if (draft is FreehandAnnotation) {
        draft.points.add(point);
      }
    });
  }

  void _handleAnnotatePanEnd(DragEndDetails details) {
    if (_movingSelection) {
      _movingSelection = false;
      return;
    }
    if (_erasing) {
      _erasing = false;
      return;
    }
    final draft = _draft;
    if (draft == null) return;
    _draft = null;
    _commit(() => _annotations.add(draft));
  }

  /// Records the current marks for undo, then applies [change].
  void _commit(VoidCallback change) {
    _undoStack.add(List.of(_annotations));
    _redoStack.clear();
    setState(change);
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(List.of(_annotations));
    setState(() => _annotations
      ..clear()
      ..addAll(_undoStack.removeLast()));
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(List.of(_annotations));
    setState(() => _annotations
      ..clear()
      ..addAll(_redoStack.removeLast()));
  }

  void _clearAll() {
    if (_annotations.isEmpty) return;
    _commit(_annotations.clear);
  }

  /// Removes the topmost mark under [point], if any.
  void _eraseAt(Offset point) {
    for (var i = _annotations.length - 1; i >= 0; i--) {
      if (annotationHitTest(_annotations[i], point)) {
        _commit(() => _annotations.removeAt(i));
        return;
      }
    }
  }

  void _closePanel() {
    if (_panel != ToolbarPanel.none) setState(() => _panel = ToolbarPanel.none);
  }

  /// Stamps scale with the chosen line width: 28px at the thinnest.
  double get _stampSize => 20 + _strokeWidth * 4;

  /// Slides the whole selection, kept on screen. Annotations stay where they
  /// were drawn (they're in screen space), as they do when resizing.
  void _moveSelection(Offset delta, Size screenSize) {
    final current = _selection;
    if (current == null) return;
    final dx = delta.dx.clamp(-current.left, screenSize.width - current.right);
    final dy = delta.dy.clamp(-current.top, screenSize.height - current.bottom);
    setState(() => _selection = current.shift(Offset(dx, dy)));
  }

  Future<void> _handleAnnotateTapUp(TapUpDetails details) async {
    _closePanel();
    final point = _localToAbsolute(details.localPosition);
    switch (_tool) {
      case AnnotationTool.stamp:
        _commit(() => _annotations.add(
              StampAnnotation(kind: _stampKind, center: point, size: _stampSize, color: _color),
            ));
      case AnnotationTool.eraser:
        _eraseAt(point);
      case AnnotationTool.text:
        // Show the inline field directly on the canvas — no dialog.
        setState(() {
          _textEditPosition = point;
          _textController.clear();
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => _textFocusNode.requestFocus());
      default:
        break;
    }
  }

  /// Commits whatever is in [_textController] as a [TextAnnotation] and
  /// hides the inline editor.
  void _commitTextEdit() {
    final pos = _textEditPosition;
    final text = _textController.text.trim();
    if (pos != null && text.isNotEmpty) {
      _commit(() => _annotations.add(TextAnnotation(
            position: pos,
            text: text,
            color: _color,
            fontSize: 14 + _strokeWidth * 2,
          )));
    }
    setState(() => _textEditPosition = null);
    _textController.clear();
    // Return keyboard focus to the shortcut handler.
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  void _cancelTextEdit() {
    setState(() => _textEditPosition = null);
    _textController.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      if (_textEditPosition != null) {
        _cancelTextEdit();
      } else if (_panel != ToolbarPanel.none) {
        // An open flyout closes first; a second Esc cancels the capture.
        _closePanel();
      } else {
        widget.onClose();
      }
      return KeyEventResult.handled;
    }
    final keyboard = HardwareKeyboard.instance;
    // ⌘ on macOS, Ctrl elsewhere.
    final command = Platform.isMacOS ? keyboard.isMetaPressed : keyboard.isControlPressed;
    if (command && key == LogicalKeyboardKey.keyZ) {
      keyboard.isShiftPressed ? _redo() : _undo();
      return KeyEventResult.handled;
    }
    if (command && key == LogicalKeyboardKey.keyY) {
      _redo();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Renders the locked selection (background crop + annotations) at native
  /// physical-pixel resolution, regardless of the display's DPI scale —
  /// unless [LightshotCaptureScreen.downscaleRetina] asks for point size.
  Future<Uint8List> _renderFinal() async {
    final image = widget.screenImage;
    final selection = _selection!;
    final screenLogicalSize = MediaQuery.of(context).size;

    final scaleX = image.width / screenLogicalSize.width;
    final scaleY = image.height / screenLogicalSize.height;

    final physicalRect = Rect.fromLTWH(
      selection.left * scaleX,
      selection.top * scaleY,
      selection.width * scaleX,
      selection.height * scaleY,
    ).intersect(Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()));

    // Output pixels per logical pixel: the capture's own density, or 1 when
    // downscaling a Retina capture to what was seen on screen.
    final outScaleX = widget.downscaleRetina ? 1.0 : scaleX;
    final outScaleY = widget.downscaleRetina ? 1.0 : scaleY;
    final outW = (physicalRect.width / scaleX * outScaleX).round();
    final outH = (physicalRect.height / scaleY * outScaleY).round();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Background crop.
    canvas.drawImageRect(
      image,
      physicalRect,
      Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()),
      Paint()..filterQuality = FilterQuality.medium,
    );

    // Annotations are recorded in absolute logical screen space — shift
    // back to selection-local before scaling to the output resolution.
    Offset map(Offset p) => Offset(
          (p.dx - selection.left) * outScaleX,
          (p.dy - selection.top) * outScaleY,
        );
    final remapped = _annotations.map((a) => _remapAnnotation(a, map, outScaleX)).toList();

    final painter = AnnotationPainter(annotations: remapped);
    painter.paintShapesOnly(canvas);

    final picture = recorder.endRecording();
    final finalImage = await picture.toImage(outW, outH);
    final byteData = await finalImage.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  Annotation _remapAnnotation(Annotation a, Offset Function(Offset) map, double scale) {
    if (a is ShapeAnnotation) {
      return ShapeAnnotation(
        kind: a.kind,
        fill: a.fill,
        start: map(a.start),
        end: map(a.end),
        color: a.color,
        strokeWidth: a.strokeWidth * scale,
      );
    } else if (a is StampAnnotation) {
      return StampAnnotation(
        kind: a.kind,
        center: map(a.center),
        size: a.size * scale,
        color: a.color,
      );
    } else if (a is FreehandAnnotation) {
      return FreehandAnnotation(
        points: a.points.map(map).toList(),
        color: a.color,
        strokeWidth: a.strokeWidth * scale,
        highlighter: a.highlighter,
      );
    } else if (a is TextAnnotation) {
      return TextAnnotation(
        position: map(a.position),
        text: a.text,
        color: a.color,
        fontSize: a.fontSize * scale,
      );
    }
    return a;
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _handleCopy() async {
    final bytes = await _renderFinal();
    final ok = await clipboardService.copyPng(bytes);
    _showSnack(ok ? 'Copied to clipboard' : 'Clipboard copy is not supported here');
  }

  Future<void> _handleSave() async {
    final bytes = await _renderFinal();
    final location = await getSaveLocation(
      suggestedName: 'alienshot_${DateTime.now().millisecondsSinceEpoch}.png',
      acceptedTypeGroups: const [XTypeGroup(label: 'PNG image', extensions: ['png'])],
    );
    if (location == null) return;
    final file = XFile.fromData(bytes, mimeType: 'image/png');
    await file.saveTo(location.path);
    _showSnack('Saved to ${location.path}');
  }

  Future<void> _handleUpload() async {
    setState(() => _uploading = true);
    try {
      final bytes = await _renderFinal();
      final url = await uploadService.uploadPng(bytes);
      await clipboardService.copyPng(bytes);
      await Clipboard.setData(ClipboardData(text: url));
      _showSnack('Link copied: $url');
    } catch (e) {
      _showSnack('Upload failed: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _finishAndClose(Future<void> Function() action) async {
    await action();
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final image = widget.screenImage;
    final selection = _phase == _Phase.selecting ? _liveSelectionRect : _selection;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            RawImage(image: image, fit: BoxFit.fill),
            CustomPaint(
              painter: _ScrimPainter(selection: selection),
              size: Size.infinite,
            ),
            if (selection != null)
              Positioned(
                left: selection.left,
                top: selection.top,
                width: selection.width,
                height: selection.height,
                child: ClipRect(
                  child: CustomPaint(
                    painter: AnnotationPainter(
                      annotations: [
                        ..._annotations.map(
                          (a) => _remapAnnotation(a, (p) => p - selection.topLeft, 1),
                        ),
                        if (_draft != null)
                          _remapAnnotation(_draft!, (p) => p - selection.topLeft, 1),
                      ],
                    ),
                  ),
                ),
              ),
            // Gesture surface: selecting drags the region; annotating draws
            // inside it.
            //
            // Keyed because starting a drag makes the selection non-null, which
            // inserts the annotation layer just before this one. Unkeyed, the
            // Stack matched children by position, so
            // this slot was rebuilt as that layer and a new detector created
            // mid-drag — the drag in progress was dropped and the selection
            // stuck at a dot until the user dragged a second time.
            if (_phase == _Phase.selecting)
              Positioned.fill(
                key: const ValueKey('select-surface'),
                child: MouseRegion(
                  cursor: SystemMouseCursors.precise,
                  child: GestureDetector(
                    onPanStart: _handleSelectPanStart,
                    onPanUpdate: _handleSelectPanUpdate,
                    onPanEnd: _handleSelectPanEnd,
                    onPanCancel: _handleSelectPanCancel,
                  ),
                ),
              )
            else if (selection != null)
              Positioned(
                left: selection.left,
                top: selection.top,
                width: selection.width,
                height: selection.height,
                child: MouseRegion(
                  cursor: switch (_tool) {
                    null => SystemMouseCursors.move,
                    AnnotationTool.text => SystemMouseCursors.text,
                    AnnotationTool.stamp || AnnotationTool.eraser => SystemMouseCursors.click,
                    _ => SystemMouseCursors.precise,
                  },
                  child: GestureDetector(
                    // Required: without it the detector defers to its child, and
                    // a childless SizedBox isn't hit-testable — every drag fell
                    // through to the annotation CustomPaint below, which absorbs
                    // hits by default, so no annotation could ever be drawn.
                    behavior: HitTestBehavior.opaque,
                    // Start at the press point: a shape begins exactly where
                    // the user clicked, and a moved selection keeps up with
                    // the mouse from the first pixel.
                    dragStartBehavior: DragStartBehavior.down,
                    onPanStart: _handleAnnotatePanStart,
                    onPanUpdate: _handleAnnotatePanUpdate,
                    onPanEnd: _handleAnnotatePanEnd,
                    onTapUp: _handleAnnotateTapUp,
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            if (selection == null)
              Positioned(
                top: 24,
                left: 0,
                right: 0,
                child: Center(
                  child: widget.recordMode
                      ? _Hint(
                          text: 'Drag to select the area to record  ·  Esc to cancel',
                          action: 'Full screen',
                          onAction: _selectFullScreen,
                        )
                      : const _Hint(text: 'Drag to select an area  ·  Esc to cancel'),
                ),
              ),
            if (_phase == _Phase.annotating && selection != null)
              _SelectionHandles(
                selection: selection,
                onResize: (handle, delta) =>
                    _resizeSelection(handle, delta, MediaQuery.of(context).size),
              ),
            if (_phase == _Phase.annotating && selection != null && widget.recordMode)
              _RecordSetupBar(
                selection: selection,
                screenSize: MediaQuery.of(context).size,
                settings: widget.recordSettings,
                onChanged: widget.onRecordSettingsChanged ?? (_) {},
                onRecord: () => widget.onRecord!(selection),
                onClose: widget.onClose,
              ),
            // Inline text field: floats at the exact tap point, no dialog.
            if (_textEditPosition != null && selection != null)
              Positioned(
                left: _textEditPosition!.dx,
                top: _textEditPosition!.dy,
                child: _InlineTextField(
                  controller: _textController,
                  focusNode: _textFocusNode,
                  color: _color,
                  fontSize: 14 + _strokeWidth * 2,
                  onSubmit: _commitTextEdit,
                  onCancel: _cancelTextEdit,
                ),
              ),
            if (_phase == _Phase.annotating && selection != null && !widget.recordMode)
              AnnotationToolbar(
                selection: selection,
                screenSize: MediaQuery.of(context).size,
                tool: _tool,
                drawTool: _drawTool,
                shapeKind: _shapeKind,
                shapeFill: _shapeFill,
                stampKind: _stampKind,
                color: _color,
                strokeWidth: _strokeWidth,
                panel: _panel,
                canUndo: _undoStack.isNotEmpty,
                canRedo: _redoStack.isNotEmpty,
                canClear: _annotations.isNotEmpty,
                uploading: _uploading,
                onToolChanged: (t) => setState(() {
                  _tool = t;
                  _panel = ToolbarPanel.none;
                }),
                onPenPicked: (highlighter) => setState(() {
                  _tool = _drawTool = highlighter ? AnnotationTool.highlighter : AnnotationTool.pen;
                  _panel = ToolbarPanel.none;
                }),
                onShapePicked: (kind, fill) => setState(() {
                  _tool = _drawTool = AnnotationTool.shape;
                  _shapeKind = kind;
                  _shapeFill = fill;
                  _panel = ToolbarPanel.none;
                }),
                onStampPicked: (kind) => setState(() {
                  _tool = AnnotationTool.stamp;
                  _stampKind = kind;
                  _panel = ToolbarPanel.none;
                }),
                onColorChanged: (c) => setState(() {
                  _color = c;
                  _panel = ToolbarPanel.none;
                }),
                // Kept open: the width is usually chosen before a pen/shape.
                onStrokeWidthChanged: (w) => setState(() => _strokeWidth = w),
                onPanelChanged: (p) => setState(() => _panel = p),
                onUndo: _undo,
                onRedo: _redo,
                onClear: _clearAll,
                onCopy: () => _finishAndClose(_handleCopy),
                onSave: () => _finishAndClose(_handleSave),
                onUpload: () => _finishAndClose(_handleUpload),
                onClose: widget.onClose,
              ),
          ],
        ),
      ),
    );
  }
}

/// A transparent in-place text entry that appears right where the user tapped.
/// Enter commits; Escape discards. Grows with content via [IntrinsicWidth].
class _InlineTextField extends StatelessWidget {
  const _InlineTextField({
    required this.controller,
    required this.focusNode,
    required this.color,
    required this.fontSize,
    required this.onSubmit,
    required this.onCancel,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final Color color;
  final double fontSize;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          onCancel();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: IntrinsicWidth(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 60, maxWidth: 600),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            style: TextStyle(
              color: color,
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              shadows: [
                Shadow(color: Colors.black.withValues(alpha: 0.7), blurRadius: 4),
              ],
            ),
            decoration: const InputDecoration(
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
            cursorColor: color,
            cursorWidth: 2,
            maxLines: null, // allow newlines with Shift+Enter
            onSubmitted: (_) => onSubmit(),
          ),
        ),
      ),
    );
  }
}

class _ScrimPainter extends CustomPainter {
  _ScrimPainter({required this.selection});

  final Rect? selection;

  @override
  void paint(Canvas canvas, Size size) {
    final fullScreen = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    // Ink-tinted rather than pure black, so the dimmed screen carries the
    // same teal cast as the rest of the brand.
    final scrimPaint = Paint()..color = AppColors.ink.withValues(alpha: 0.55);

    if (selection == null) {
      canvas.drawPath(fullScreen, scrimPaint);
      return;
    }

    final hole = Path()..addRect(selection!);
    final dimmed = Path.combine(PathOperation.difference, fullScreen, hole);
    canvas.drawPath(dimmed, scrimPaint);

    final glowPaint = Paint()
      ..color = AppColors.accent.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawRect(selection!, glowPaint);

    // Dotted border — same look as Lightshot's marching-ants selection.
    final borderPaint = Paint()
      ..color = AppColors.accent2
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // White background dots so the dashes read on any screen content.
    final whiteDots = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    const dash = 4.0;
    const gap = 4.0;

    void drawDashedRect(Paint p) {
      final r = selection!;
      for (final seg in [
        [r.topLeft, r.topRight],
        [r.topRight, r.bottomRight],
        [r.bottomRight, r.bottomLeft],
        [r.bottomLeft, r.topLeft],
      ]) {
        final start = seg[0];
        final end = seg[1];
        final total = (end - start).distance;
        final dir = (end - start) / total;
        double pos = 0;
        bool drawing = true;
        while (pos < total) {
          final segLen = (drawing ? dash : gap).clamp(0, total - pos);
          if (drawing) {
            canvas.drawLine(start + dir * pos, start + dir * (pos + segLen), p);
          }
          pos += segLen;
          drawing = !drawing;
        }
      }
    }

    drawDashedRect(whiteDots);
    drawDashedRect(borderPaint);
  }

  @override
  bool shouldRepaint(covariant _ScrimPainter oldDelegate) => oldDelegate.selection != selection;
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text, this.action, this.onAction});

  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final palette = AlienPalette.of(context);
    return Container(
      padding: EdgeInsets.fromLTRB(18, action == null ? 9 : 5, action == null ? 18 : 6, action == null ? 9 : 5),
      decoration: ShapeDecoration(
        color: palette.surface,
        shape: StadiumBorder(side: BorderSide(color: palette.glassBorder)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            style: TextStyle(color: palette.textSoft, fontSize: 13, fontWeight: FontWeight.w500),
          ),
          if (action != null) ...[
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: onAction,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                minimumSize: Size.zero,
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              icon: const Icon(Icons.fullscreen_rounded, size: 16),
              label: Text(action!),
            ),
          ],
        ],
      ),
    );
  }
}

/// Before a screen recording: audio sources, frame rate and the Record
/// button, beside the chosen area (below it when there's room).
class _RecordSetupBar extends StatelessWidget {
  const _RecordSetupBar({
    required this.selection,
    required this.screenSize,
    required this.settings,
    required this.onChanged,
    required this.onRecord,
    required this.onClose,
  });

  final Rect selection;
  final Size screenSize;
  final RecordingSettings settings;
  final ValueChanged<RecordingSettings> onChanged;
  final VoidCallback onRecord;
  final VoidCallback onClose;

  static const double _height = 52;
  static const double _width = 476;

  @override
  Widget build(BuildContext context) {
    final palette = AlienPalette.of(context);
    final below = selection.bottom + 10 + _height + 8 <= screenSize.height;
    final above = selection.top - 10 - _height >= 8;
    final top = below
        ? selection.bottom + 10
        : above
            ? selection.top - 10 - _height
            : selection.bottom - _height - 12;
    final left = (selection.center.dx - _width / 2).clamp(8.0, math.max(8.0, screenSize.width - _width - 8)).toDouble();

    Widget toggle(IconData on, IconData off, String tip, bool value, VoidCallback onTap) => Tooltip(
          message: tip,
          child: IconButton(
            onPressed: onTap,
            isSelected: value,
            icon: Icon(value ? on : off, size: 20, color: value ? palette.accentText : palette.textSoft),
          ),
        );

    Widget menu<T>(String tip, String label, List<T> values, String Function(T) name, ValueChanged<T> onPick) =>
        PopupMenuButton<T>(
          tooltip: tip,
          onSelected: onPick,
          itemBuilder: (_) => [for (final v in values) PopupMenuItem(value: v, child: Text(name(v)))],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: palette.text)),
                Icon(Icons.arrow_drop_down_rounded, size: 18, color: palette.textSoft),
              ],
            ),
          ),
        );

    return Positioned(
      left: left,
      top: top,
      child: GlassContainer(
        borderRadius: _height / 2,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: SizedBox(
          width: _width - 16,
          height: _height,
          child: Row(
            children: [
              toggle(Icons.volume_up_rounded, Icons.volume_off_rounded,
                  settings.systemAudio ? 'Computer audio: on' : 'Computer audio: off', settings.systemAudio,
                  () => onChanged(settings.copyWith(systemAudio: !settings.systemAudio))),
              toggle(Icons.mic_rounded, Icons.mic_off_rounded,
                  settings.microphone ? 'Microphone: on' : 'Microphone: off', settings.microphone,
                  () => onChanged(settings.copyWith(microphone: !settings.microphone))),
              menu<int>('Resolution', RecordingSettings.outputHeightLabel(settings.outputHeight),
                  RecordingSettings.outputHeights, RecordingSettings.outputHeightLabel,
                  (h) => onChanged(settings.copyWith(outputHeight: h))),
              menu<int>('Frames per second', '${settings.fps} fps', RecordingSettings.frameRates,
                  (f) => '$f fps', (f) => onChanged(settings.copyWith(fps: f))),
              const Spacer(),
              FilledButton.icon(
                onPressed: onRecord,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE5484D),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                ),
                icon: const Icon(Icons.fiber_manual_record_rounded, size: 16),
                label: const Text('Record'),
              ),
              IconButton(
                tooltip: 'Cancel',
                onPressed: onClose,
                icon: Icon(Icons.close_rounded, size: 20, color: palette.textSoft),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lightshot-style resize handles: 8 small grips around the selection border
/// (corners + edge midpoints) that let the user keep adjusting the crop
/// after it's locked, instead of only being able to redo the drag.
class _SelectionHandles extends StatelessWidget {
  const _SelectionHandles({required this.selection, required this.onResize});

  final Rect selection;
  final void Function(_ResizeHandlePosition handle, Offset delta) onResize;

  static const double _visualSize = 9;
  static const double _hitSize = 11;

  @override
  Widget build(BuildContext context) {
    final points = <_ResizeHandlePosition, Offset>{
      _ResizeHandlePosition.topLeft: selection.topLeft,
      _ResizeHandlePosition.top: Offset(selection.center.dx, selection.top),
      _ResizeHandlePosition.topRight: selection.topRight,
      _ResizeHandlePosition.right: Offset(selection.right, selection.center.dy),
      _ResizeHandlePosition.bottomRight: selection.bottomRight,
      _ResizeHandlePosition.bottom: Offset(selection.center.dx, selection.bottom),
      _ResizeHandlePosition.bottomLeft: selection.bottomLeft,
      _ResizeHandlePosition.left: Offset(selection.left, selection.center.dy),
    };

    return Stack(
      children: [
        for (final entry in points.entries)
          Positioned(
            left: entry.value.dx - _hitSize / 2,
            top: entry.value.dy - _hitSize / 2,
            width: _hitSize,
            height: _hitSize,
            child: MouseRegion(
              cursor: _cursorFor(entry.key),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (details) => onResize(entry.key, details.delta),
                child: Center(
                  child: Container(
                    width: _visualSize,
                    height: _visualSize,
                    decoration: BoxDecoration(
                      color: AppColors.accent2,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  MouseCursor _cursorFor(_ResizeHandlePosition handle) {
    switch (handle) {
      case _ResizeHandlePosition.topLeft:
      case _ResizeHandlePosition.bottomRight:
        return SystemMouseCursors.resizeUpLeftDownRight;
      case _ResizeHandlePosition.topRight:
      case _ResizeHandlePosition.bottomLeft:
        return SystemMouseCursors.resizeUpRightDownLeft;
      case _ResizeHandlePosition.top:
      case _ResizeHandlePosition.bottom:
        return SystemMouseCursors.resizeUpDown;
      case _ResizeHandlePosition.left:
      case _ResizeHandlePosition.right:
        return SystemMouseCursors.resizeLeftRight;
    }
  }
}
