import 'dart:ui';

/// What a drag or click inside the selection does. With none picked, a drag
/// moves the selection (as in Lightshot).
enum AnnotationTool { pen, highlighter, shape, text, stamp, eraser }

/// The shapes in the toolbar's Draw menu.
enum ShapeKind { line, arrow, doubleArrow, rectangle, ellipse, diamond }

/// How a closed shape is filled: outline only, solid, or a see-through tint
/// that highlights what's underneath.
enum ShapeFill { none, solid, tint }

enum StampKind { check, arrow, cross, heart, star, question }

/// The four line widths offered in the Draw menu.
const List<double> kStrokeWidths = [2, 4, 6, 9];

/// The Draw menu's palette, laid out in rows of five: vivid tones first,
/// then deeper ones — annotations must stay readable on busy screenshots.
const List<Color> kAnnotationColors = [
  Color(0xFFFFFFFF), // white
  Color(0xFFFF1F1F), // red
  Color(0xFFFFDD33), // yellow
  Color(0xFF7FC97F), // light green
  Color(0xFF2E8BFF), // blue
  Color(0xFFB57CFF), // purple
  Color(0xFFFF3FD1), // pink
  Color(0xFFFF8C00), // orange
  Color(0xFF3FD42B), // green
  Color(0xFF4FD8E8), // cyan
  Color(0xFF3A3A3A), // dark grey
  Color(0xFF7A0000), // dark red
  Color(0xFF7A4A0F), // brown
  Color(0xFF0E6E2E), // dark green
  Color(0xFF1748C2), // dark blue
];

abstract class Annotation {
  Annotation({required this.color, required this.strokeWidth});

  final Color color;
  final double strokeWidth;
}

class ShapeAnnotation extends Annotation {
  ShapeAnnotation({
    required this.kind,
    required this.start,
    required this.end,
    required super.color,
    required super.strokeWidth,
    this.fill = ShapeFill.none,
  });

  final ShapeKind kind;
  final ShapeFill fill;
  Offset start;
  Offset end;

  /// Lines and arrows have no inside to fill.
  bool get isClosed => kind == ShapeKind.rectangle || kind == ShapeKind.ellipse || kind == ShapeKind.diamond;
}

class FreehandAnnotation extends Annotation {
  FreehandAnnotation({
    required this.points,
    required super.color,
    required super.strokeWidth,
    this.highlighter = false,
  });

  final List<Offset> points;
  final bool highlighter;
}

class TextAnnotation extends Annotation {
  TextAnnotation({
    required this.position,
    required this.text,
    required super.color,
    required this.fontSize,
  }) : super(strokeWidth: 0);

  final Offset position;
  final String text;
  final double fontSize;
}

/// A ✓ ✕ ★ … mark dropped with a click, centred on [center].
class StampAnnotation extends Annotation {
  StampAnnotation({
    required this.kind,
    required this.center,
    required this.size,
    required super.color,
  }) : super(strokeWidth: 0);

  final StampKind kind;
  final Offset center;
  final double size;
}
