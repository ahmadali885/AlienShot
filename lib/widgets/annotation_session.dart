import 'package:flutter/material.dart';

import '../models/annotation.dart';
import 'annotation_painter.dart';
import 'annotation_toolbar.dart';

/// The marks on screen and everything the annotation toolbar controls: the
/// tool, its options, the open flyout, and undo/redo history. Points are in
/// the coordinates of whatever surface hosts the session.
class AnnotationSession extends ChangeNotifier {
  final List<Annotation> annotations = [];

  /// The shape or stroke being drawn right now, not yet in [annotations].
  Annotation? draft;

  final List<List<Annotation>> _undoStack = [];
  final List<List<Annotation>> _redoStack = [];

  /// Null: no annotation tool (the host decides what that means — move the
  /// selection, or let clicks through to other apps).
  AnnotationTool? tool;

  /// The Draw button's last pick, re-armed when it's pressed again.
  AnnotationTool drawTool = AnnotationTool.pen;
  ShapeKind shapeKind = ShapeKind.rectangle;
  ShapeFill shapeFill = ShapeFill.none;
  StampKind stampKind = StampKind.check;
  ToolbarPanel panel = ToolbarPanel.none;
  Color color = kAnnotationColors[1]; // red
  double strokeWidth = kStrokeWidths[1];
  bool _erasing = false;

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  bool get isEmpty => annotations.isEmpty && draft == null;

  /// Stamps scale with the chosen line width: 28px at the thinnest.
  double get stampSize => 20 + strokeWidth * 4;

  // --- Toolbar choices ---

  void setTool(AnnotationTool? value) {
    tool = value;
    panel = ToolbarPanel.none;
    notifyListeners();
  }

  void pickPen(bool highlighter) {
    tool = drawTool = highlighter ? AnnotationTool.highlighter : AnnotationTool.pen;
    panel = ToolbarPanel.none;
    notifyListeners();
  }

  void pickShape(ShapeKind kind, ShapeFill fill) {
    tool = drawTool = AnnotationTool.shape;
    shapeKind = kind;
    shapeFill = fill;
    panel = ToolbarPanel.none;
    notifyListeners();
  }

  void pickStamp(StampKind kind) {
    tool = AnnotationTool.stamp;
    stampKind = kind;
    panel = ToolbarPanel.none;
    notifyListeners();
  }

  void setColor(Color value) {
    color = value;
    panel = ToolbarPanel.none;
    notifyListeners();
  }

  void setStrokeWidth(double value) {
    strokeWidth = value;
    notifyListeners();
  }

  void setPanel(ToolbarPanel value) {
    panel = value;
    notifyListeners();
  }

  void closePanel() {
    if (panel == ToolbarPanel.none) return;
    panel = ToolbarPanel.none;
    notifyListeners();
  }

  // --- Pointer input on the drawing surface ---

  void dragStart(Offset point) {
    panel = ToolbarPanel.none;
    switch (tool) {
      case AnnotationTool.shape:
        draft = ShapeAnnotation(
          kind: shapeKind,
          fill: shapeFill,
          start: point,
          end: point,
          color: color,
          strokeWidth: strokeWidth,
        );
      case AnnotationTool.pen:
      case AnnotationTool.highlighter:
        draft = FreehandAnnotation(
          points: [point],
          color: color,
          strokeWidth: strokeWidth,
          highlighter: tool == AnnotationTool.highlighter,
        );
      case AnnotationTool.eraser:
        _erasing = true;
        eraseAt(point);
      default:
        break;
    }
    notifyListeners();
  }

  void dragUpdate(Offset point) {
    if (_erasing) {
      eraseAt(point);
      return;
    }
    final current = draft;
    if (current is ShapeAnnotation) {
      current.end = point;
    } else if (current is FreehandAnnotation) {
      current.points.add(point);
    } else {
      return;
    }
    notifyListeners();
  }

  void dragEnd() {
    _erasing = false;
    final finished = draft;
    if (finished == null) return;
    draft = null;
    _commit(() => annotations.add(finished));
  }

  /// A click: drops a stamp or erases, depending on the tool. Text needs a
  /// prompt, so the host asks for it and calls [addText].
  void tap(Offset point) {
    panel = ToolbarPanel.none;
    switch (tool) {
      case AnnotationTool.stamp:
        _commit(() => annotations.add(
              StampAnnotation(kind: stampKind, center: point, size: stampSize, color: color),
            ));
      case AnnotationTool.eraser:
        eraseAt(point);
      default:
        notifyListeners();
    }
  }

  void addText(Offset point, String text) {
    _commit(() => annotations.add(
          TextAnnotation(position: point, text: text, color: color, fontSize: 14 + strokeWidth * 2),
        ));
  }

  /// Removes the topmost mark under [point], if any.
  void eraseAt(Offset point) {
    for (var i = annotations.length - 1; i >= 0; i--) {
      if (annotationHitTest(annotations[i], point)) {
        _commit(() => annotations.removeAt(i));
        return;
      }
    }
  }

  // --- History ---

  void undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(List.of(annotations));
    annotations
      ..clear()
      ..addAll(_undoStack.removeLast());
    notifyListeners();
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(List.of(annotations));
    annotations
      ..clear()
      ..addAll(_redoStack.removeLast());
    notifyListeners();
  }

  void clearAll() {
    if (annotations.isEmpty) return;
    _commit(annotations.clear);
  }

  /// Records the current marks for undo, then applies [change].
  void _commit(VoidCallback change) {
    _undoStack.add(List.of(annotations));
    _redoStack.clear();
    change();
    notifyListeners();
  }
}
