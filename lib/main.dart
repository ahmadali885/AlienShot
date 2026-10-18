import 'package:flutter/material.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await hotKeyManager.unregisterAll();
  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    // Matches the size _openHome() sets; 360 was too short for the home
    // screen's column and overflowed it by ~97px.
    size: Size(480, 460),
    center: true,
    skipTaskbar: true,
    titleBarStyle: TitleBarStyle.normal,
    title: 'AlienShot',
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    // Window stays hidden here; SnapGrabHome shows it once there's a
    // screenshot to edit and hides it again afterwards.
  });

  runApp(const SnapGrabApp());
}
