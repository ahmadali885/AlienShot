import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapgrab/models/app_settings.dart';
import 'package:snapgrab/models/recording_settings.dart';
import 'package:snapgrab/screens/quick_overlay_screen.dart';
import 'package:snapgrab/screens/settings_screen.dart';
import 'package:snapgrab/theme/app_theme.dart';

void main() {
  const channel = MethodChannel('alienshot/recorder');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'listAudioDevices') {
        return [
          {'id': 'spk', 'name': 'Speakers (Realtek)', 'output': true, 'default': true},
          {'id': 'mic', 'name': 'USB Microphone', 'output': false, 'default': true},
        ];
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  void sizeView(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('Recording tab fits the settings window and saves a resolution', variant: _windows, (tester) async {
    // The settings window is 720x640; the client area is a little smaller.
    sizeView(tester, const Size(704, 601));
    AppSettings? saved;
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(Brightness.dark),
      home: SettingsScreen(
        settings: AppSettings.defaults(),
        initialTab: 'recording',
        showRecordingTab: true,
        onSave: (s) => saved = s,
        onBack: () {},
        onPreviewTheme: (_) {},
      ),
    ));
    await tester.pump();

    expect(find.text('Original (area size)'), findsOneWidget);
    expect(find.text('Default (Speakers (Realtek))'), findsOneWidget);
    expect(find.text('Alt + X'), findsOneWidget);
    expect(find.text('Ctrl + Alt + R'), findsOneWidget);

    await tester.tap(find.text('Original (area size)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('8K (4320p)').last);
    await tester.pumpAndSettle();

    // Everything further down the list is reachable by scrolling.
    await tester.scrollUntilVisible(find.text('Pause / resume'), 200,
        scrollable: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down));
    expect(find.text('Pause / resume'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(saved?.recording.outputHeight, 4320);
  });

  for (final size in [const Size(1920, 1080), const Size(1366, 768)]) {
    testWidgets('overlay panel fits a ${size.width.toInt()}x${size.height.toInt()} screen', variant: _windows,
        (tester) async {
      sizeView(tester, size);
      var recorded = false;
      RecordingSettings? changed;
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(Brightness.dark),
        home: QuickOverlayScreen(
          backdrop: null,
          settings: const RecordingSettings(),
          overlayHotKeyLabel: 'Alt + X',
          recordHotKeyLabel: 'Ctrl + Alt + R',
          onScreenshot: () {},
          onRecordFullScreen: () => recorded = true,
          onRecordArea: () {},
          onOpenRecordings: () {},
          onOpenSettings: () {},
          onSettingsChanged: (s) => changed = s,
          onClose: () {},
        ),
      ));
      await tester.pump();

      await tester.tap(find.text('Record screen'));
      expect(recorded, isTrue);
      await tester.tap(find.text('Microphone: off'));
      expect(changed?.microphone, isTrue);
    });
  }
}

final _windows = TargetPlatformVariant.only(TargetPlatform.windows);
