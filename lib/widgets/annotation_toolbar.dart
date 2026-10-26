import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/annotation.dart';
import '../theme/app_theme.dart';
import 'annotation_painter.dart';
import 'color_picker_popup.dart';
import 'glass_container.dart';

/// Which flyout is open beside the toolbar.
enum ToolbarPanel { none, draw, stamp, color }

/// The vertical tool strip beside a locked selection, with Draw / Stamp /
/// Colour flyouts — modelled on screen-annotation apps rather than a single
/// row of icons, so each group can offer more without crowding the bar.
class AnnotationToolbar extends StatelessWidget {
  const AnnotationToolbar({
    super.key,
    required this.selection,
    required this.screenSize,
    required this.tool,
    required this.drawTool,
    required this.shapeKind,
    required this.shapeFill,
    required this.stampKind,
    required this.color,
    required this.strokeWidth,
    required this.panel,
    required this.canUndo,
    required this.canRedo,
    required this.canClear,
    required this.uploading,
    required this.onToolChanged,
    required this.onPenPicked,
    required this.onShapePicked,
    required this.onStampPicked,
    required this.onColorChanged,
    required this.onStrokeWidthChanged,
    required this.onPanelChanged,
    required this.onUndo,
    required this.onRedo,
    required this.onClear,
    this.onCopy,
    this.onSave,
    this.onUpload,
    this.onClose,
    this.recording = false,
    this.barKey,
    this.panelKey,
  });

  final Rect selection;
  final Size screenSize;

  /// The active tool; null means dragging moves the selection.
  final AnnotationTool? tool;

  /// The Draw button's current pick (pen, highlighter or shape), shown on it
  /// and re-armed when it's pressed.
  final AnnotationTool drawTool;
  final ShapeKind shapeKind;
  final ShapeFill shapeFill;
  final StampKind stampKind;
  final Color color;
  final double strokeWidth;
  final ToolbarPanel panel;
  final bool canUndo;
  final bool canRedo;
  final bool canClear;
  final bool uploading;

  final ValueChanged<AnnotationTool?> onToolChanged;
  final ValueChanged<bool> onPenPicked; // true = highlighter
  final void Function(ShapeKind kind, ShapeFill fill) onShapePicked;
  final ValueChanged<StampKind> onStampPicked;
  final ValueChanged<Color> onColorChanged;
  final ValueChanged<double> onStrokeWidthChanged;
  final ValueChanged<ToolbarPanel> onPanelChanged;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onClear;
  final VoidCallback? onCopy;
  final VoidCallback? onSave;
  final VoidCallback? onUpload;
  final VoidCallback? onClose;

  /// During a screen recording: no Copy/Save/Link/Close, and the first
  /// button (no tool) means "click through to your apps" rather than
  /// "move the selection".
  final bool recording;

  /// Attached to the bar and the open flyout, so the recording overlay can
  /// find where they are and keep clicks there for itself.
  final GlobalKey? barKey;
  final GlobalKey? panelKey;

  static const double barWidth = 48;
  static const double _gap = 10;
  static const double _pad = 6;
  static const double _slot = 38; // button + its vertical margin
  static const double _divider = 13;

  /// Button rows, top to bottom; null marks a divider.
  static const List<String?> _editRows = [
    'move', 'text', 'draw', 'stamp', 'eraser', 'color', null,
    'undo', 'redo', 'clear',
  ];

  List<String?> get _rows => recording ? _editRows : [..._editRows, null, 'copy', 'save', 'upload', 'close'];

  double get barHeight => _pad * 2 + _rows.fold<double>(0, (h, r) => h + (r == null ? _divider : _slot));

  double _rowTop(String id) {
    var y = _pad;
    for (final r in _rows) {
      if (r == id) return y;
      y += r == null ? _divider : _slot;
    }
    return y;
  }

  bool get _drawing => tool == AnnotationTool.pen || tool == AnnotationTool.highlighter || tool == AnnotationTool.shape;

  @override
  Widget build(BuildContext context) {
    // Beside the selection: right if there's room, else left, else tucked
    // inside the right edge.
    final double left;
    final bool outsideRight;
    if (selection.right + _gap + barWidth + 8 <= screenSize.width) {
      left = selection.right + _gap;
      outsideRight = true;
    } else if (selection.left - _gap - barWidth >= 8) {
      left = selection.left - _gap - barWidth;
      outsideRight = false;
    } else {
      left = selection.right - barWidth - 8;
      outsideRight = true;
    }
    final top = selection.top.clamp(8.0, math.max(8.0, screenSize.height - barHeight - 8)).toDouble();

    final panelWidth = switch (panel) {
      ToolbarPanel.draw => _DrawPanel.width,
      ToolbarPanel.stamp => _StampPanel.width,
      ToolbarPanel.color => _ColorPanel.width,
      ToolbarPanel.none => 0.0,
    };
    final panelHeight = switch (panel) {
      ToolbarPanel.draw => _DrawPanel.height,
      ToolbarPanel.stamp => _StampPanel.height,
      ToolbarPanel.color => _ColorPanel.height,
      ToolbarPanel.none => 0.0,
    };
    // Flyouts open away from the selection when they fit, so they don't
    // cover what is being annotated.
    final rightOfBar = left + barWidth + 8;
    final leftOfBar = left - 8 - panelWidth;
    final panelLeft = outsideRight
        ? (rightOfBar + panelWidth <= screenSize.width - 8 ? rightOfBar : leftOfBar)
        : (leftOfBar >= 8 ? leftOfBar : rightOfBar);
    final anchor = switch (panel) {
      ToolbarPanel.draw => 'draw',
      ToolbarPanel.stamp => 'stamp',
      _ => 'color',
    };
    final panelTop = (top + _rowTop(anchor) - 6).clamp(8.0, math.max(8.0, screenSize.height - panelHeight - 8)).toDouble();

    return Positioned.fill(
      child: Stack(
        children: [
          Positioned(left: left, top: top, child: KeyedSubtree(key: barKey, child: _bar(context))),
          if (panel != ToolbarPanel.none)
            Positioned(
              left: panelLeft,
              top: panelTop,
              child: KeyedSubtree(
                key: panelKey,
                child: switch (panel) {
                ToolbarPanel.draw => _DrawPanel(
                    tool: tool,
                    shapeKind: shapeKind,
                    shapeFill: shapeFill,
                    strokeWidth: strokeWidth,
                    onPenPicked: onPenPicked,
                    onShapePicked: onShapePicked,
                    onStrokeWidthChanged: onStrokeWidthChanged,
                  ),
                ToolbarPanel.stamp => _StampPanel(
                    selected: tool == AnnotationTool.stamp ? stampKind : null,
                    onPicked: onStampPicked,
                  ),
                _ => _ColorPanel(color: color, onPicked: onColorChanged),
                },
              ),
            ),
        ],
      ),
    );
  }

  void _togglePanel(ToolbarPanel p) => onPanelChanged(panel == p ? ToolbarPanel.none : p);

  Widget _bar(BuildContext context) {
    final palette = AlienPalette.of(context);
    Widget button(String id) {
      switch (id) {
        case 'move':
          return _BarButton(
            tooltip: recording ? 'Pointer (use your apps)' : 'Move selection',
            selected: tool == null,
            onTap: () => onToolChanged(null),
            child: Icon(recording ? Icons.near_me_rounded : Icons.open_with_rounded),
          );
        case 'text':
          return _BarButton(
            tooltip: 'Text',
            selected: tool == AnnotationTool.text,
            onTap: () => onToolChanged(tool == AnnotationTool.text ? null : AnnotationTool.text),
            child: const Icon(Icons.title_rounded),
          );
        case 'draw':
          return _BarButton(
            tooltip: 'Draw',
            selected: _drawing,
            onTap: () {
              // Re-arm the last drawing tool and show its options.
              if (!_drawing) onToolChanged(drawTool);
              _togglePanel(ToolbarPanel.draw);
            },
            child: switch (drawTool) {
              AnnotationTool.highlighter => const Icon(Icons.border_color_rounded),
              AnnotationTool.shape => _ShapeGlyph(kind: shapeKind, fill: shapeFill),
              _ => const Icon(Icons.edit_rounded),
            },
          );
        case 'stamp':
          return _BarButton(
            tooltip: 'Stamps',
            selected: tool == AnnotationTool.stamp,
            onTap: () {
              if (tool != AnnotationTool.stamp) onToolChanged(AnnotationTool.stamp);
              _togglePanel(ToolbarPanel.stamp);
            },
            child: Icon(kStampIcons[stampKind]),
          );
        case 'eraser':
          return _BarButton(
            tooltip: 'Eraser',
            selected: tool == AnnotationTool.eraser,
            onTap: () => onToolChanged(tool == AnnotationTool.eraser ? null : AnnotationTool.eraser),
            child: const Icon(Icons.auto_fix_normal_rounded),
          );
        case 'color':
          return _BarButton(
            tooltip: 'Colour',
            selected: panel == ToolbarPanel.color,
            onTap: () => _togglePanel(ToolbarPanel.color),
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: palette.isLight ? palette.text : Colors.white, width: 2),
              ),
            ),
          );
        case 'undo':
          return _BarButton(tooltip: 'Undo', enabled: canUndo, onTap: onUndo, child: const Icon(Icons.undo_rounded));
        case 'redo':
          return _BarButton(tooltip: 'Redo', enabled: canRedo, onTap: onRedo, child: const Icon(Icons.redo_rounded));
        case 'clear':
          return _BarButton(
            tooltip: 'Delete all',
            enabled: canClear,
            onTap: onClear,
            child: const Icon(Icons.delete_outline_rounded),
          );
        case 'copy':
          return _BarButton(tooltip: 'Copy', onTap: onCopy ?? () {}, child: const Icon(Icons.copy_rounded));
        case 'save':
          return _BarButton(tooltip: 'Save', onTap: onSave ?? () {}, child: const Icon(Icons.download_rounded));
        case 'upload':
          return _BarButton(
            tooltip: 'Upload link',
            enabled: !uploading,
            onTap: onUpload ?? () {},
            child: uploading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(Icons.link_rounded, color: palette.accentText),
          );
        default:
          return _BarButton(
            tooltip: 'Close',
            onTap: onClose ?? () {},
            danger: true,
            child: const Icon(Icons.close_rounded),
          );
      }
    }

    return GlassContainer(
      borderRadius: 16,
      padding: const EdgeInsets.symmetric(vertical: _pad),
      child: SizedBox(
        width: barWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final r in _rows)
              r == null
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Container(width: 24, height: 1, color: palette.glassBorder),
                    )
                  : Padding(padding: const EdgeInsets.symmetric(vertical: 1), child: button(r)),
          ],
        ),
      ),
    );
  }
}

/// A 36px tool button: accent-gradient fill when selected, red for Close.
class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.tooltip,
    required this.onTap,
    required this.child,
    this.selected = false,
    this.enabled = true,
    this.danger = false,
  });

  final String tooltip;
  final VoidCallback onTap;
  final Widget child;
  final bool selected;
  final bool enabled;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final palette = AlienPalette.of(context);
    final fg = selected
        ? AppColors.onAccent
        : danger
            ? Colors.white
            : palette.text.withValues(alpha: enabled ? 1 : 0.35);
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: enabled ? onTap : null,
          child: Ink(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: selected ? AppColors.accentGradient : null,
              color: danger ? const Color(0xFFE5484D) : null,
            ),
            child: IconTheme(
              data: IconThemeData(size: 19, color: fg),
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small preview of a shape and its fill, drawn with the real painter.
class _ShapeGlyph extends StatelessWidget {
  const _ShapeGlyph({required this.kind, required this.fill, this.size = 18});

  final ShapeKind kind;
  final ShapeFill fill;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color ?? AlienPalette.of(context).text;
    return CustomPaint(
      size: Size.square(size),
      painter: _ShapeGlyphPainter(kind: kind, fill: fill, color: color),
    );
  }
}

class _ShapeGlyphPainter extends CustomPainter {
  _ShapeGlyphPainter({required this.kind, required this.fill, required this.color});

  final ShapeKind kind;
  final ShapeFill fill;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = size.width * 0.12;
    final closed = kind == ShapeKind.rectangle || kind == ShapeKind.ellipse || kind == ShapeKind.diamond;
    // Lines and arrows run corner to corner; closed shapes fill the box.
    final start = closed ? Offset(inset, inset + size.height * 0.08) : Offset(inset, size.height - inset);
    final end = closed ? Offset(size.width - inset, size.height - inset - size.height * 0.08) : Offset(size.width - inset, inset);
    AnnotationPainter.paintAnnotation(
      canvas,
      ShapeAnnotation(kind: kind, start: start, end: end, color: color, strokeWidth: 1.8, fill: fill),
    );
  }

  @override
  bool shouldRepaint(covariant _ShapeGlyphPainter old) =>
      old.kind != kind || old.fill != fill || old.color != color;
}

class _PanelLabel extends StatelessWidget {
  const _PanelLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, left: 2),
      child: Text(text, style: AlienPalette.of(context).eyebrow.copyWith(fontSize: 10)),
    );
  }
}

/// A 38px square choice inside a flyout.
class _PanelButton extends StatelessWidget {
  const _PanelButton({required this.selected, required this.onTap, required this.child, this.tooltip});

  final bool selected;
  final VoidCallback onTap;
  final Widget child;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final palette = AlienPalette.of(context);
    final button = Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Ink(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: selected ? AppColors.accentGradient : null,
          ),
          child: IconTheme(
            data: IconThemeData(size: 20, color: selected ? AppColors.onAccent : palette.text),
            child: Center(child: child),
          ),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, waitDuration: const Duration(milliseconds: 400), child: button);
  }
}

class _DrawPanel extends StatelessWidget {
  const _DrawPanel({
    required this.tool,
    required this.shapeKind,
    required this.shapeFill,
    required this.strokeWidth,
    required this.onPenPicked,
    required this.onShapePicked,
    required this.onStrokeWidthChanged,
  });

  final AnnotationTool? tool;
  final ShapeKind shapeKind;
  final ShapeFill shapeFill;
  final double strokeWidth;
  final ValueChanged<bool> onPenPicked;
  final void Function(ShapeKind kind, ShapeFill fill) onShapePicked;
  final ValueChanged<double> onStrokeWidthChanged;

  static const double width = 4 * 38 + 3 * 6 + 2 * 14;
  static const double height = 300;

  /// Rows of the shape grid, as in the reference: outline, solid, tint —
  /// with the open shapes (line, arrow, double arrow) leading each row.
  static const _grid = [
    [(ShapeKind.line, ShapeFill.none), (ShapeKind.rectangle, ShapeFill.none), (ShapeKind.ellipse, ShapeFill.none), (ShapeKind.diamond, ShapeFill.none)],
    [(ShapeKind.arrow, ShapeFill.none), (ShapeKind.rectangle, ShapeFill.solid), (ShapeKind.ellipse, ShapeFill.solid), (ShapeKind.diamond, ShapeFill.solid)],
    [(ShapeKind.doubleArrow, ShapeFill.none), (ShapeKind.rectangle, ShapeFill.tint), (ShapeKind.ellipse, ShapeFill.tint), (ShapeKind.diamond, ShapeFill.tint)],
  ];

  static const _shapeNames = {
    ShapeKind.line: 'Line',
    ShapeKind.arrow: 'Arrow',
    ShapeKind.doubleArrow: 'Double arrow',
    ShapeKind.rectangle: 'Rectangle',
    ShapeKind.ellipse: 'Ellipse',
    ShapeKind.diamond: 'Diamond',
  };

  static const _fillNames = {ShapeFill.none: '', ShapeFill.solid: ' (filled)', ShapeFill.tint: ' (highlight)'};

  @override
  Widget build(BuildContext context) {
    final palette = AlienPalette.of(context);
    Widget row(List<Widget> children) => Row(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              children[i],
            ],
          ],
        );
    return GlassContainer(
      borderRadius: 18,
      padding: const EdgeInsets.all(14),
      child: SizedBox(
        width: width - 28,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _PanelLabel('DRAW'),
            row([
              _PanelButton(
                tooltip: 'Pen',
                selected: tool == AnnotationTool.pen,
                onTap: () => onPenPicked(false),
                child: const Icon(Icons.edit_rounded),
              ),
              _PanelButton(
                tooltip: 'Highlighter',
                selected: tool == AnnotationTool.highlighter,
                onTap: () => onPenPicked(true),
                child: const Icon(Icons.border_color_rounded),
              ),
            ]),
            const SizedBox(height: 12),
            const _PanelLabel('LINE WIDTH'),
            row([
              for (final w in kStrokeWidths)
                _PanelButton(
                  tooltip: '${w.round()} px',
                  selected: strokeWidth == w,
                  onTap: () => onStrokeWidthChanged(w),
                  child: Builder(
                    builder: (context) => Container(
                      width: 20,
                      height: w,
                      decoration: BoxDecoration(
                        color: IconTheme.of(context).color ?? palette.text,
                        borderRadius: BorderRadius.circular(w),
                      ),
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 12),
            const _PanelLabel('SHAPES'),
            for (final (i, cells) in _grid.indexed) ...[
              if (i > 0) const SizedBox(height: 6),
              row([
                for (final (kind, fill) in cells)
                  _PanelButton(
                    tooltip: '${_shapeNames[kind]}${_fillNames[fill]}',
                    selected: tool == AnnotationTool.shape && shapeKind == kind && shapeFill == fill,
                    onTap: () => onShapePicked(kind, fill),
                    child: Builder(
                      builder: (context) => _ShapeGlyph(kind: kind, fill: fill, size: 20),
                    ),
                  ),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}

class _StampPanel extends StatelessWidget {
  const _StampPanel({required this.selected, required this.onPicked});

  final StampKind? selected;
  final ValueChanged<StampKind> onPicked;

  static const double width = 38 + 2 * 7;
  static const double height = 6 * 38 + 5 * 4 + 2 * 7;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      borderRadius: 16,
      padding: const EdgeInsets.all(7),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, kind) in StampKind.values.indexed) ...[
            if (i > 0) const SizedBox(height: 4),
            _PanelButton(
              selected: selected == kind,
              onTap: () => onPicked(kind),
              child: Icon(kStampIcons[kind]),
            ),
          ],
        ],
      ),
    );
  }
}

class _ColorPanel extends StatelessWidget {
  const _ColorPanel({required this.color, required this.onPicked});

  final Color color;
  final ValueChanged<Color> onPicked;

  static const double _swatch = 26;
  static const double _spacing = 10;
  static const double width = 5 * _swatch + 4 * _spacing + 2 * 14;
  static const double height = 3 * _swatch + 2 * _spacing + 2 * 14 + 44;

  @override
  Widget build(BuildContext context) {
    final palette = AlienPalette.of(context);
    final ring = palette.isLight ? palette.text : Colors.white;
    final isCustom = !kAnnotationColors.contains(color);
    return GlassContainer(
      borderRadius: 18,
      padding: const EdgeInsets.all(14),
      child: SizedBox(
        width: width - 28,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: _spacing,
              runSpacing: _spacing,
              children: [
                for (final c in kAnnotationColors)
                  GestureDetector(
                    onTap: () => onPicked(c),
                    child: Container(
                      width: _swatch,
                      height: _swatch,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: c == color ? ring : palette.ghostBorder,
                          width: c == color ? 2.5 : 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: () async {
                final picked = await ColorPickerPopup.show(context, color);
                if (picked != null) onPicked(picked);
              },
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                minimumSize: Size.zero,
                foregroundColor: palette.text,
              ),
              icon: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const SweepGradient(
                    colors: [
                      Color(0xFFFF1744), Color(0xFFFFEA00), Color(0xFF00E676),
                      Color(0xFF00E5FF), Color(0xFF2979FF), Color(0xFFD500F9), Color(0xFFFF1744),
                    ],
                  ),
                  border: isCustom ? Border.all(color: ring, width: 2) : null,
                ),
              ),
              label: const Text('Custom…', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}
