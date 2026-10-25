import 'dart:io';

import 'package:flutter/services.dart' show MethodChannel, PhysicalKeyboardKey;
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:uni_platform/uni_platform.dart';

/// The tray icon and its right-click menu, laid out like Lightshot's on each
/// platform. A plain left click goes straight to a capture on Windows; that
/// part is wired up in app.dart.
class TrayService {
  Future<void> init({
    required VoidCallback onSignIn,
    required VoidCallback onCapture,
    required VoidCallback onOptions,
    required VoidCallback onAbout,
    required VoidCallback onHelp,
    required VoidCallback onExit,
  }) async {
    if (Platform.isMacOS) {
      // A template image: macOS tints the black alien silhouette itself to
      // suit a light or dark menu bar, as native menu-bar icons do.
      await trayManager.setIcon('assets/images/tray_icon_template.png', isTemplate: true);
    } else {
      await trayManager.setIcon('assets/images/tray_icon.ico');
    }
    await trayManager.setToolTip('AlienShot');

    await trayManager.setContextMenu(
      Menu(
        items: Platform.isMacOS
            // Lightshot's menu-bar menu on the Mac.
            ? [
                MenuItem(key: 'capture', label: kMacCaptureItemLabel),
                MenuItem(key: 'sign_in', label: 'Sign In…'),
                MenuItem(key: 'options', label: 'Preferences…'),
                MenuItem(key: 'about', label: 'About AlienShot…'),
                MenuItem(key: 'exit', label: 'Quit AlienShot'),
              ]
            : [
                MenuItem(key: 'sign_in', label: 'Sign In…'),
                MenuItem.separator(),
                MenuItem(key: 'capture', label: 'Take a screenshot'),
                MenuItem(key: 'options', label: 'Options…'),
                MenuItem(key: 'about', label: 'About…'),
                MenuItem(key: 'help', label: 'Help'),
                MenuItem(key: 'exit', label: 'Exit'),
              ],
      ),
    );

    _actions = {
      'sign_in': onSignIn,
      'capture': onCapture,
      'options': onOptions,
      'about': onAbout,
      'help': onHelp,
      'exit': onExit,
    };
  }

  Map<String, VoidCallback> _actions = const {};

  void handleMenuClick(MenuItem menuItem) => _actions[menuItem.key]?.call();

  /// Shows the menu at the cursor. On Windows the app must own the foreground
  /// first, otherwise the menu doesn't close when the user clicks elsewhere —
  /// tray_manager only does that when asked via [bringAppToFront].
  Future<void> showMenu() => trayManager.popUpContextMenu(bringAppToFront: true);

  static const _macosChannel = MethodChannel('alienshot/macos');

  /// macOS: shows [hotKey] at the right of "Take screenshot", as Lightshot's
  /// menu does. tray_manager can't set key equivalents, so the runner fills
  /// it in (macos/Runner/MainFlutterWindow.swift).
  Future<void> setShortcutHint(HotKey? hotKey) async {
    if (!Platform.isMacOS) return;
    final key = hotKey == null ? null : _keyEquivalent(hotKey.physicalKey);
    await _macosChannel.invokeMethod<void>('setTrayShortcut', {
      'key': key ?? '',
      'modifiers': key == null ? <String>[] : [for (final m in hotKey!.modifiers ?? []) m.name],
    });
  }
}

/// Title of the macOS capture item; the runner finds the item by it.
const String kMacCaptureItemLabel = 'Take screenshot';

final List<PhysicalKeyboardKey> _functionKeys = [
  PhysicalKeyboardKey.f1, PhysicalKeyboardKey.f2, PhysicalKeyboardKey.f3,
  PhysicalKeyboardKey.f4, PhysicalKeyboardKey.f5, PhysicalKeyboardKey.f6,
  PhysicalKeyboardKey.f7, PhysicalKeyboardKey.f8, PhysicalKeyboardKey.f9,
  PhysicalKeyboardKey.f10, PhysicalKeyboardKey.f11, PhysicalKeyboardKey.f12,
  PhysicalKeyboardKey.f13, PhysicalKeyboardKey.f14, PhysicalKeyboardKey.f15,
  PhysicalKeyboardKey.f16, PhysicalKeyboardKey.f17, PhysicalKeyboardKey.f18,
  PhysicalKeyboardKey.f19, PhysicalKeyboardKey.f20, PhysicalKeyboardKey.f21,
  PhysicalKeyboardKey.f22, PhysicalKeyboardKey.f23, PhysicalKeyboardKey.f24,
];

/// An NSMenuItem key equivalent: the key's character, or "@name" for keys
/// AppKit represents with a function-key code (the runner translates those).
String? _keyEquivalent(PhysicalKeyboardKey key) {
  final fn = _functionKeys.indexOf(key);
  if (fn >= 0) return '@f${fn + 1}';
  final named = {
    PhysicalKeyboardKey.arrowLeft: '@left',
    PhysicalKeyboardKey.arrowRight: '@right',
    PhysicalKeyboardKey.arrowUp: '@up',
    PhysicalKeyboardKey.arrowDown: '@down',
    PhysicalKeyboardKey.home: '@home',
    PhysicalKeyboardKey.end: '@end',
    PhysicalKeyboardKey.pageUp: '@pageup',
    PhysicalKeyboardKey.pageDown: '@pagedown',
    PhysicalKeyboardKey.delete: '@fwddelete',
    PhysicalKeyboardKey.enter: '\r',
    PhysicalKeyboardKey.tab: '\t',
    PhysicalKeyboardKey.backspace: '\b',
    PhysicalKeyboardKey.escape: '\u001b',
    PhysicalKeyboardKey.space: ' ',
  }[key];
  if (named != null) return named;
  final label = key.logicalKey?.keyLabel ?? '';
  return label.length == 1 ? label.toLowerCase() : null;
}

typedef VoidCallback = void Function();

final trayService = TrayService();
