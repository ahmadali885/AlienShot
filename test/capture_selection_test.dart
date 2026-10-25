import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapgrab/screens/lightshot_capture_screen.dart';
import 'package:snapgrab/theme/app_theme.dart';

void main() {
  late ui.Image screen;

  setUp(() {
    screen = _solidImage(1920, 1080);
  });

  Future<void> pumpOverlay(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.dark),
        home: LightshotCaptureScreen(screenImage: screen, onClose: () {}),
      ),
    );
  }

  Future<void> drag(WidgetTester tester, Offset from, Offset to) async {
    final gesture = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
    await tester.pump();
    await gesture.moveTo(Offset.lerp(from, to, 0.5)!);
    await tester.pump();
    await gesture.moveTo(to);
    await tester.pump();
    await gesture.up();
    await tester.pump();
  }

  testWidgets('the very first drag selects a region', variant: _windows, (tester) async {
    await pumpOverlay(tester);
    expect(find.byTooltip('Copy'), findsNothing);

    await drag(tester, const Offset(100, 100), const Offset(400, 300));

    // The toolbar only appears once a region is locked in.
    expect(find.byTooltip('Copy'), findsOneWidget);
  });

  testWidgets('with no tool picked, dragging inside the selection moves it', variant: _windows, (tester) async {
    await pumpOverlay(tester);
    await drag(tester, const Offset(100, 100), const Offset(900, 500));
    // The toolbar is anchored to the selection's bottom-right corner.
    final before = tester.getCenter(find.byTooltip('Copy'));

    await drag(tester, const Offset(400, 300), const Offset(500, 360));

    expect(tester.getCenter(find.byTooltip('Copy')) - before, const Offset(100, 60));
  });

  testWidgets('a click without a drag leaves no stuck selection', variant: _windows, (tester) async {
    await pumpOverlay(tester);
    final gesture = await tester.startGesture(const Offset(200, 200), kind: PointerDeviceKind.mouse);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(find.byTooltip('Copy'), findsNothing);
    // The hint only shows while nothing is selected.
    expect(find.textContaining('Drag to select'), findsOneWidget);
  });
}

ui.Image _solidImage(int width, int height) {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF336699),
  );
  return recorder.endRecording().toImageSync(width, height);
}

/// Desktop density: the default (Android) test platform makes the toolbar's
/// icon buttons larger than they are on Windows, overflowing its fixed width.
final _windows = TargetPlatformVariant.only(TargetPlatform.windows);
