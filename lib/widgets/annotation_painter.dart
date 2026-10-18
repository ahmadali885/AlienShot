import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/annotation.dart';

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
      _paintAnnotation(canvas, annotation);
    }
  }

  void _paintAnnotation(Canvas canvas, Annotation annotation) {
    if (annotation is ShapeAnnotation) {
      _paintShape(canvas, annotation);
    } else if (annotation is FreehandAnnotation) {
      _paintFreehand(canvas, annotation);
    } else if (annotation is TextAnnotation) {
      _paintText(canvas, annotation);
    }
  }

  void _paintShape(Canvas canvas, ShapeAnnotation annotation) {
    final paint = Paint()
      ..color = annotation.color
      ..strokeWidth = annotation.strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    if (annotation.tool == AnnotationTool.rectangle) {
      canvas.drawRect(Rect.fromPoints(annotation.start, annotation.end), paint);
    } else if (annotation.tool == AnnotationTool.arrow) {
      _drawArrow(canvas, annotation.start, annotation.end, paint);
    }
  }

  void _drawArrow(Canvas canvas, Offset start, Offset end, Paint paint) {
    canvas.drawLine(start, end, paint);
    final direction = end - start;
    if (direction.distance == 0) return;
    final angle = direction.direction;
    const arrowLength = 18.0;
    const arrowAngle = 0.5;

    final leftWing = Offset(
      end.dx - arrowLength * math.cos(angle - arrowAngle),
      end.dy - arrowLength * math.sin(angle - arrowAngle),
    );
    final rightWing = Offset(
      end.dx - arrowLength * math.cos(angle + arrowAngle),
      end.dy - arrowLength * math.sin(angle + arrowAngle),
    );

    canvas.drawLine(end, leftWing, paint);
    canvas.drawLine(end, rightWing, paint);
  }

  void _paintFreehand(Canvas canvas, FreehandAnnotation annotation) {
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

  void _paintText(Canvas canvas, TextAnnotation annotation) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: annotation.text,
        style: TextStyle(
          color: annotation.color,
          fontSize: annotation.fontSize,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, annotation.position);
  }

  @override
  bool shouldRepaint(covariant AnnotationPainter oldDelegate) => true;
}
