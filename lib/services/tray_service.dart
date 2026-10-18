import 'dart:io';

import 'package:tray_manager/tray_manager.dart';

/// The tray icon and its right-click menu, laid out like Lightshot's. A plain
/// left click goes straight to a capture; that part is wired up in app.dart.
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
        items: [
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
}

typedef VoidCallback = void Function();

final trayService = TrayService();
