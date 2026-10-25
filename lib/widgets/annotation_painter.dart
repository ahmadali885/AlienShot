import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/annotation.dart';

/// Glyphs for each stamp. Referenced as const IconData so the icon font
/// keeps them when release builds tree-shake it.
const Map<StampKind, IconData> kStampIcons = {
  StampKind.check: Icons.check_rounded,
  StampKind.arrow: Icons.arrow_forward_rounded,
  StampKind.cross: Icons.close_rounded,
  StampKind.heart: Icons.favorite_rounded,
  StampKind.star: Icons.star_rounded,
  StampKind.question: Icons.question_mark_rounded,
};

class AnnotationPainter extends CustomPainter {
  AnnotationPainter({this.image, required this.annotations});

  /// Optional — when null, only the annotations are painted (used when the
  /// background is already rendered by a separate layer, e.g. the Lightshot
  /// capture screen's live overlay and final export).
  final ui.Image? image;
  final List<Annotation> annotations;

  @override
  void paint(Canvas canvas, Size size) {
    final img = image;
    if (img != null) {
      canvas.drawImage(img, Offset.zero, Paint());
    }
    paintShapesOnly(canvas);
  }

  void paintShapesOnly(Canvas canvas) {
    for (final annotation in annotations) {
      paintAnnotation(canvas, annotation);
    }
  }

  static void paintAnnotation(Canvas canvas, Annotation annotation) {
    if (annotation is ShapeAnnotation) {
      _paintShape(canvas, annotation);
    } else if (annotation is FreehandAnnotation) {
      _paintFreehand(canvas, annotation);
    } else if (annotation is TextAnnotation) {
      _paintText(canvas, annotation);
    } else if (annotation is StampAnnotation) {
      _paintStamp(canvas, annotation);
    }
  }

  static void _paintShape(Canvas canvas, ShapeAnnotation a) {
    final stroke = Paint()
      ..color = a.color
      ..strokeWidth = a.strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final rect = Rect.fromPoints(a.start, a.end);

    switch (a.kind) {
      case ShapeKind.line:
        canvas.drawLine(a.start, a.end, stroke);
      case ShapeKind.arrow:
        _drawArrow(canvas, a.start, a.end, a.color, a.strokeWidth, heads: 1);
      case ShapeKind.doubleArrow:
        _drawArrow(canvas, a.start, a.end, a.color, a.strokeWidth, heads: 2);
      case ShapeKind.rectangle:
      case ShapeKind.ellipse:
      case ShapeKind.diamond:
        final path = switch (a.kind) {
          ShapeKind.rectangle => Path()..addRect(rect),
          ShapeKind.ellipse => Path()..addOval(rect),
          _ => Path()
            ..moveTo(rect.center.dx, rect.top)
            ..lineTo(rect.right, rect.center.dy)
            ..lineTo(rect.center.dx, rect.bottom)
            ..lineTo(rect.left, rect.center.dy)
            ..close(),
        };
        if (a.fill != ShapeFill.none) {
          canvas.drawPath(
            path,
            Paint()..color = a.fill == ShapeFill.solid ? a.color : a.color.withValues(alpha: 0.28),
          );
        }
        canvas.drawPath(path, stroke);
    }
  }

  /// A shaft with solid triangular heads scaled to the stroke, so thick
  /// arrows don't end in a thin, spindly tip.
  static void _drawArrow(Canvas canvas, Offset start, Offset end, Color color, double width, {required int heads}) {
    final direction = end - start;
    if (direction.distance == 0) return;
    // Short arrows (and the toolbar's tiny previews) shrink their heads so
    // two of them never meet in the middle.
    final headLength = math.min(10 + width * 3, direction.distance * (heads == 2 ? 0.3 : 0.5));
    final unit = direction / direction.distance;

    // Stop the shaft inside the head so its round cap doesn't poke out.
    final shaftEnd = end - unit * headLength * 0.6;
    final shaftStart = heads == 2 ? start + unit * headLength * 0.6 : start;
    canvas.drawLine(
      shaftStart,
      shaftEnd,
      Paint()
        ..color = color
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );

    final fill = Paint()..color = color;
    void head(Offset tip, Offset dir) {
      final angle = dir.direction;
      const spread = 0.42;
      final path = Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(tip.dx - headLength * math.cos(angle - spread), tip.dy - headLength * math.sin(angle - spread))
        ..lineTo(tip.dx - headLength * math.cos(angle + spread), tip.dy - headLength * math.sin(angle + spread))
        ..close();
      canvas.drawPath(path, fill);
    }

    head(end, direction);
    if (heads == 2) head(start, -direction);
  }

  static void _paintFreehand(Canvas canvas, FreehandAnnotation annotation) {
    if (annotation.points.isEmpty) return;

    final paint = Paint()
      ..color = annotation.highlighter
          ? annotation.color.withValues(alpha: 0.35)
          : annotation.color
      ..strokeWidth =
          annotation.highlighter ? annotation.strokeWidth * 4 : annotation.strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()..moveTo(annotation.points.first.dx, annotation.points.first.dy);
    for (final point in annotation.points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, paint);
  }

  static TextPainter _textPainter(TextAnnotation annotation) {
    return TextPainter(
      text: TextSpan(
        text: annotation.text,
        style: TextStyle(
          color: annotation.color,
          fontSize: annotation.fontSize,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  static void _paintText(Canvas canvas, TextAnnotation annotation) {
    _textPainter(annotation).paint(canvas, annotation.position);
  }

  static void _paintStamp(Canvas canvas, StampAnnotation a) {
    final icon = kStampIcons[a.kind]!;
    final painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: a.size,
          color: a.color,
          // A soft dark edge keeps light stamps visible on light screenshots.
          shadows: [Shadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: a.size * 0.08)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, a.center - Offset(painter.width / 2, painter.height / 2));
  }

  @override
  bool shouldRepaint(covariant AnnotationPainter oldDelegate) => true;
}

/// Whether [point] (same coordinate space as [a]) lands on [a] — used by the
/// eraser. Generous by a few pixels so thin strokes are easy to hit.
bool annotationHitTest(Annotation a, Offset point) {
  const slop = 6.0;
  if (a is ShapeAnnotation) {
    final reach = a.strokeWidth / 2 + slop;
    if (!a.isClosed) return _distanceToSegment(point, a.start, a.end) <= reach;
    final rect = Rect.fromPoints(a.start, a.end);
    if (a.fill != ShapeFill.none) return rect.inflate(reach).contains(point);
    // An outline only counts near its edge, so erasing a box drawn around
    // something doesn't also need a click on that something.
    return rect.inflate(reach).contains(point) && !rect.deflate(reach).contains(point);
  }
  if (a is FreehandAnnotation) {
    final reach = (a.highlighter ? a.strokeWidth * 4 : a.strokeWidth) / 2 + slop;
    if (a.points.length == 1) return (a.points.first - point).distance <= reach;
    for (var i = 1; i < a.points.length; i++) {
      if (_distanceToSegment(point, a.points[i - 1], a.points[i]) <= reach) return true;
    }
    return false;
  }
  if (a is TextAnnotation) {
    final painter = AnnotationPainter._textPainter(a);
    return (a.position & painter.size).inflate(slop).contains(point);
  }
  if (a is StampAnnotation) {
    return (a.center - point).distance <= a.size / 2 + slop;
  }
  return false;
}

double _distanceToSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final lengthSquared = ab.distanceSquared;
  if (lengthSquared == 0) return (p - a).distance;
  final t = (((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / lengthSquared).clamp(0.0, 1.0);
  return (p - (a + ab * t)).distance;
}
