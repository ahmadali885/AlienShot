import 'dart:ui';

enum AnnotationTool { rectangle, arrow, pen, highlighter, text }

/// Deliberately vivid: annotations have to stay readable on top of whatever
/// was on screen, and the muted Material defaults disappeared against busy
/// screenshots.
const List<Color> kAnnotationColors = [
  Color(0xFFFF1744), // red
  Color(0xFFFF9100), // orange
  Color(0xFFFFEA00), // yellow
  Color(0xFF00E676), // green
  Color(0xFF00E5FF), // cyan
  Color(0xFF2979FF), // blue
  Color(0xFFD500F9), // magenta
  Color(0xFFFFFFFF), // white
];

abstract class Annotation {
  Annotation({required this.color, required this.strokeWidth});

  final Color color;
  final double strokeWidth;
}

class ShapeAnnotation extends Annotation {
  ShapeAnnotation({
    required this.tool,
    required this.start,
    required this.end,
    required super.color,
    required super.strokeWidth,
  });

  final AnnotationTool tool;
  Offset start;
  Offset end;
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
