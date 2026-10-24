import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/annotation.dart';
import '../services/clipboard_service.dart';
import '../services/upload_service.dart';
import '../theme/app_theme.dart';
import '../widgets/annotation_painter.dart';
import '../widgets/color_picker_popup.dart';
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
  });

  /// Already-decoded frame — the capture service hands over a [ui.Image]
  /// directly so the overlay can paint on its very first frame.
  final ui.Image screenImage;
  final VoidCallback onClose;

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
  AnnotationTool _tool = AnnotationTool.rectangle;
  Color _color = Colors.red;
  double _strokeWidth = 4;
  bool _uploading = false;

  @override
  void dispose() {
    _focusNode.dispose();
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
  void _handleSelectPanCancel() {
    setState(() {
      _dragStart = null;
      _dragCurrent = null;
    });
  }

  // --- Phase 2: annotating inside the locked selection ---

  void _handleAnnotatePanStart(DragStartDetails details) {
    if (_tool == AnnotationTool.text) return;
    final point = _localToAbsolute(details.localPosition);
    setState(() {
      switch (_tool) {
        case AnnotationTool.rectangle:
        case AnnotationTool.arrow:
          _draft = ShapeAnnotation(
            tool: _tool,
            start: point,
            end: point,
            color: _color,
            strokeWidth: _strokeWidth,
          );
          break;
        case AnnotationTool.pen:
          _draft = FreehandAnnotation(points: [point], color: _color, strokeWidth: _strokeWidth);
          break;
        case AnnotationTool.highlighter:
          _draft = FreehandAnnotation(
            points: [point],
            color: _color,
            strokeWidth: _strokeWidth,
            highlighter: true,
          );
          break;
        case AnnotationTool.text:
          break;
      }
    });
  }

  void _handleAnnotatePanUpdate(DragUpdateDetails details) {
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
    if (_draft == null) return;
    setState(() {
      _annotations.add(_draft!);
      _draft = null;
    });
  }

  Future<void> _handleAnnotateTapUp(TapUpDetails details) async {
    if (_tool != AnnotationTool.text) return;
    final point = _localToAbsolute(details.localPosition);
    final text = await _promptForText();
    if (text == null || text.trim().isEmpty) return;
    setState(() {
      _annotations.add(
        TextAnnotation(
          position: point,
          text: text.trim(),
          color: _color,
          fontSize: 14 + _strokeWidth * 2,
        ),
      );
    });
  }

  Future<String?> _promptForText() {
    final controller = TextEditingController();
    return showDialog<String>(
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
  }

  void _undo() {
    if (_annotations.isEmpty) return;
    setState(() => _annotations.removeLast());
  }

  void _clearAll() {
    if (_annotations.isEmpty) return;
    setState(() => _annotations.clear());
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Renders the locked selection (background crop + annotations) at native
  /// physical-pixel resolution, regardless of the display's DPI scale.
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

    final outW = physicalRect.width.round();
    final outH = physicalRect.height.round();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Background crop.
    canvas.drawImageRect(
      image,
      physicalRect,
      Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()),
      Paint(),
    );

    // Annotations are recorded in absolute logical screen space — shift
    // back to selection-local before scaling up to the final physical-pixel
    // crop resolution.
    Offset map(Offset p) => Offset(
          (p.dx - selection.left) * scaleX,
          (p.dy - selection.top) * scaleY,
        );
    final remapped = _annotations.map((a) => _remapAnnotation(a, map, scaleX)).toList();

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
        tool: a.tool,
        start: map(a.start),
        end: map(a.end),
        color: a.color,
        strokeWidth: a.strokeWidth * scale,
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
                child: GestureDetector(
                  // Required: without it the detector defers to its child, and
                  // a childless SizedBox isn't hit-testable — every drag fell
                  // through to the annotation CustomPaint below, which absorbs
                  // hits by default, so no annotation could ever be drawn.
                  behavior: HitTestBehavior.opaque,
                  onPanStart: _handleAnnotatePanStart,
                  onPanUpdate: _handleAnnotatePanUpdate,
                  onPanEnd: _handleAnnotatePanEnd,
                  onTapUp: _handleAnnotateTapUp,
                  child: const SizedBox.expand(),
                ),
              ),
            if (selection == null)
              const Positioned(
                top: 24,
                left: 0,
                right: 0,
                child: Center(
                  child: _Hint(text: 'Drag to select an area  ·  Esc to cancel'),
                ),
              ),
            if (_phase == _Phase.annotating && selection != null)
              _SelectionHandles(
                selection: selection,
                onResize: (handle, delta) =>
                    _resizeSelection(handle, delta, MediaQuery.of(context).size),
              ),
            if (_phase == _Phase.annotating && selection != null)
              _FloatingToolbar(
                selection: selection,
                screenSize: MediaQuery.of(context).size,
                tool: _tool,
                color: _color,
                strokeWidth: _strokeWidth,
                uploading: _uploading,
                onToolChanged: (t) => setState(() => _tool = t),
                onColorChanged: (c) => setState(() => _color = c),
                onStrokeWidthChanged: (w) => setState(() => _strokeWidth = w),
                onUndo: _undo,
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

    final borderPaint = Paint()
      ..color = AppColors.accent2
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(selection!, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _ScrimPainter oldDelegate) => oldDelegate.selection != selection;
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = AlienPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
      decoration: ShapeDecoration(
        color: palette.surface,
        shape: StadiumBorder(side: BorderSide(color: palette.glassBorder)),
      ),
      child: Text(
        text,
        style: TextStyle(color: palette.textSoft, fontSize: 13, fontWeight: FontWeight.w500),
      ),
    );
  }
}

class _FloatingToolbar extends StatelessWidget {
  const _FloatingToolbar({
    required this.selection,
    required this.screenSize,
    required this.tool,
    required this.color,
    required this.strokeWidth,
    required this.uploading,
    required this.onToolChanged,
    required this.onColorChanged,
    required this.onStrokeWidthChanged,
    required this.onUndo,
    required this.onClear,
    required this.onCopy,
    required this.onSave,
    required this.onUpload,
    required this.onClose,
  });

  final Rect selection;
  final Size screenSize;
  final AnnotationTool tool;
  final Color color;
  final double strokeWidth;
  final bool uploading;
  final ValueChanged<AnnotationTool> onToolChanged;
  final ValueChanged<Color> onColorChanged;
  final ValueChanged<double> onStrokeWidthChanged;
  final VoidCallback onUndo;
  final VoidCallback onClear;
  final VoidCallback onCopy;
  final VoidCallback onSave;
  final VoidCallback onUpload;
  final VoidCallback onClose;

  static const double _barHeight = 48;
  static const double _barWidth = 560;

  @override
  Widget build(BuildContext context) {
    final palette = AlienPalette.of(context);
    // A white ring vanishes on the light glass; use the text colour there.
    final selectedRing = palette.isLight ? palette.text : Colors.white;
    final fitsBelow = selection.bottom + _barHeight + 12 < screenSize.height;
    final top = fitsBelow ? selection.bottom + 8 : selection.top - _barHeight - 8;
    var left = selection.right - _barWidth;
    left = left.clamp(8.0, (screenSize.width - _barWidth - 8).clamp(8.0, double.infinity));

    return Positioned(
      left: left,
      top: top.clamp(8.0, screenSize.height - _barHeight - 8),
      // Pill-shaped like the site's nav group: radius = half the bar height.
      child: GlassContainer(
        borderRadius: _barHeight / 2,
        child: SizedBox(
          width: _barWidth,
          height: _barHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9),
            child: Row(
              children: [
                _ToolIcon(Icons.crop_square_rounded, tool == AnnotationTool.rectangle, () => onToolChanged(AnnotationTool.rectangle)),
                _ToolIcon(Icons.north_east_rounded, tool == AnnotationTool.arrow, () => onToolChanged(AnnotationTool.arrow)),
                _ToolIcon(Icons.edit_rounded, tool == AnnotationTool.pen, () => onToolChanged(AnnotationTool.pen)),
                _ToolIcon(Icons.border_color_rounded, tool == AnnotationTool.highlighter, () => onToolChanged(AnnotationTool.highlighter)),
                _ToolIcon(Icons.text_fields_rounded, tool == AnnotationTool.text, () => onToolChanged(AnnotationTool.text)),
                const SizedBox(width: 6),
                const _BarDivider(),
                const SizedBox(width: 6),
                ...kAnnotationColors.take(6).map(
                  (c) => GestureDetector(
                    onTap: () => onColorChanged(c),
                    child: Container(
                      width: 16,
                      height: 16,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: color == c ? selectedRing : palette.ghostBorder,
                          width: color == c ? 2 : 1,
                        ),
                        boxShadow: color == c ? glow(c, alpha: 0.6, blur: 10) : null,
                      ),
                    ),
                  ),
                ),
                _CustomColorButton(color: color, onPicked: onColorChanged),
                const SizedBox(width: 6),
                const _BarDivider(),
                IconButton(
                  tooltip: 'Undo',
                  iconSize: 18,
                  icon: Icon(Icons.undo_rounded, color: palette.textSoft),
                  onPressed: onUndo,
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Copy',
                  iconSize: 18,
                  icon: Icon(Icons.copy_rounded, color: palette.text),
                  onPressed: onCopy,
                ),
                IconButton(
                  tooltip: 'Save',
                  iconSize: 18,
                  icon: Icon(Icons.save_alt_rounded, color: palette.text),
                  onPressed: onSave,
                ),
                IconButton(
                  tooltip: 'Upload link',
                  iconSize: 18,
                  icon: uploading
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(Icons.link_rounded, color: palette.accentText),
                  onPressed: uploading ? null : onUpload,
                ),
                IconButton(
                  tooltip: 'Close',
                  iconSize: 18,
                  icon: Icon(Icons.close_rounded, color: palette.textSoft),
                  onPressed: onClose,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens the HSV picker. Shows the active colour when it isn't one of the
/// preset swatches, so a custom pick stays visible on the toolbar.
class _CustomColorButton extends StatelessWidget {
  const _CustomColorButton({required this.color, required this.onPicked});

  final Color color;
  final ValueChanged<Color> onPicked;

  @override
  Widget build(BuildContext context) {
    final palette = AlienPalette.of(context);
    final isCustom = !kAnnotationColors.take(6).contains(color);
    return GestureDetector(
      onTap: () async {
        final picked = await ColorPickerPopup.show(context, color);
        if (picked != null) onPicked(picked);
      },
      child: Container(
        width: 18,
        height: 18,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const SweepGradient(
            colors: [
              Color(0xFFFF1744),
              Color(0xFFFFEA00),
              Color(0xFF00E676),
              Color(0xFF00E5FF),
              Color(0xFF2979FF),
              Color(0xFFD500F9),
              Color(0xFFFF1744),
            ],
          ),
          border: Border.all(
            color: isCustom ? (palette.isLight ? palette.text : Colors.white) : palette.ghostBorder,
            width: isCustom ? 2 : 1,
          ),
        ),
        child: isCustom
            ? Center(
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
              )
            : null,
      ),
    );
  }
}

class _ToolIcon extends StatelessWidget {
  const _ToolIcon(this.icon, this.selected, this.onPressed);

  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.all(7),
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          gradient: selected ? AppColors.accentGradient : null,
          shape: BoxShape.circle,
          boxShadow: selected ? glow(AppColors.accent, blur: 12, alpha: 0.5) : null,
        ),
        child: Icon(icon, size: 17, color: selected ? AppColors.onAccent : AlienPalette.of(context).text),
      ),
    );
  }
}

class _BarDivider extends StatelessWidget {
  const _BarDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 22, color: AlienPalette.of(context).glassBorder);
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
