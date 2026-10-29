import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapgrab/models/recording_settings.dart';
import 'package:snapgrab/screens/recording_screen.dart';
import 'package:snapgrab/theme/app_theme.dart';

/// The recording overlay against a fake "alienshot/recorder" channel.
void main() {
  const channel = MethodChannel('alienshot/recorder');
  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  Future<String?> pumpRecording(WidgetTester tester, {required void Function(String) onFinished}) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(Brightness.dark),
      home: RecordingScreen(
        region: const Rect.fromLTWH(200, 150, 1000, 600),
        settings: const RecordingSettings(fps: 60, systemAudio: true, microphone: true, outputHeight: 1440),
        onFinished: onFinished,
        onError: (e) => fail('unexpected error: $e'),
      ),
    ));
    return null;
  }

  /// Runs the 3-2-1 on the test clock, then lets the real file-system work
  /// (creating the Videos folder) and the fake channel finish.
  Future<void> finishCountdown(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
  }

  Map<String, dynamic> argsOf(String method) =>
      Map<String, dynamic>.from(calls.lastWhere((c) => c.method == method).arguments as Map);

  testWidgets('counts down, records the area, and stops into the file', variant: _windows, (tester) async {
    String? saved;
    await pumpRecording(tester, onFinished: (p) => saved = p);

    expect(find.text('3'), findsOneWidget);
    expect(calls.where((c) => c.method == 'start'), isEmpty);

    await finishCountdown(tester);

    final start = argsOf('start');
    expect([start['left'], start['top'], start['width'], start['height']], [200.0, 150.0, 1000.0, 600.0]);
    expect(start['fps'], 60);
    expect(start['systemAudio'], isTrue);
    expect(start['microphone'], isTrue);
    expect(start['outputHeight'], 1440);
    expect(start['path'], endsWith('.mp4'));

    // Clicks pass through except over the controls while no tool is active.
    final clickThrough = argsOf('setClickThrough');
    expect(clickThrough['enabled'], isTrue);
    expect(clickThrough['captureAll'], isFalse);
    expect((clickThrough['rects'] as List).length, greaterThanOrEqualTo(8)); // bar + controls

    await tester.tap(find.byTooltip('Stop and save'));
    await tester.pump();
    await tester.pump();
    expect(calls.where((c) => c.method == 'stop'), hasLength(1));
    expect(saved, start['path']);

    // The window shrinking back to normal rebuilds the screen once more; that
    // must not switch click-through on again (it left the next window
    // unclickable).
    final sent = calls.where((c) => c.method == 'setClickThrough').length;
    tester.view.physicalSize = const Size(480, 460);
    await tester.pump();
    await tester.pump();
    expect(calls.where((c) => c.method == 'setClickThrough'), hasLength(sent));
  });

  testWidgets('drawing takes the mouse and sends the marks to the recorder', variant: _windows, (tester) async {
    await pumpRecording(tester, onFinished: (_) {});
    await finishCountdown(tester);

    await tester.tap(find.byTooltip('Draw'));
    await tester.pump();
    await tester.tap(find.byTooltip('Pen'));
    await tester.pump();
    await tester.pump();
    expect(argsOf('setClickThrough')['captureAll'], isTrue);

    final gesture = await tester.startGesture(const Offset(300, 300), kind: PointerDeviceKind.mouse);
    await gesture.moveTo(const Offset(500, 400));
    await gesture.moveTo(const Offset(700, 450));
    await gesture.up();
    await tester.pump();
    // Fires the 80 ms overlay timer.
    await tester.pump(const Duration(milliseconds: 100));

    // The overlay goes out on a short timer, rendered off the UI thread.
    await tester.runAsync(() async {
      await Future.delayed(const Duration(milliseconds: 150));
      for (var i = 0; i < 20 && !calls.any((c) => c.method == 'setOverlay'); i++) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
    });
    final overlay = argsOf('setOverlay');
    expect(overlay['width'], 1000);
    expect(overlay['height'], 600);
    expect((overlay['rgba'] as Uint8List).length, 1000 * 600 * 4);

    // Back to the pointer: clicks go through to apps again.
    await tester.tap(find.byTooltip('Pointer (use your apps)'));
    await tester.pump();
    await tester.pump();
    expect(argsOf('setClickThrough')['captureAll'], isFalse);
  });
}

final _windows = TargetPlatformVariant.only(TargetPlatform.windows);
