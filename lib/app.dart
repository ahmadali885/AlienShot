import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'models/app_settings.dart';
import 'models/hotkey_preset.dart';
import 'screens/about_screen.dart';
import 'screens/help_screen.dart';
import 'screens/home_screen.dart';
import 'screens/lightshot_capture_screen.dart';
import 'screens/settings_screen.dart';
import 'services/capture_service.dart';
import 'services/hotkey_availability.dart';
import 'services/settings_service.dart';
import 'services/tray_service.dart';
import 'services/window_focus.dart';
import 'theme/app_theme.dart';

enum _View { home, settings, capture, about, help }

/// The active theme choice. Lives above [MaterialApp] so the home state below
/// it can switch themes, including a live preview from Settings.
final ValueNotifier<ThemeMode> _themeMode = ValueNotifier(ThemeMode.system);

class SnapGrabApp extends StatelessWidget {
  const SnapGrabApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: _themeMode,
      builder: (context, mode, _) => MaterialApp(
        title: 'AlienShot',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(Brightness.light),
        darkTheme: buildAppTheme(Brightness.dark),
        themeMode: mode,
        home: const SnapGrabHome(),
      ),
    );
  }
}

class SnapGrabHome extends StatefulWidget {
  const SnapGrabHome({super.key});

  @override
  State<SnapGrabHome> createState() => _SnapGrabHomeState();
}

class _SnapGrabHomeState extends State<SnapGrabHome>
    with WindowListener, TrayListener, WidgetsBindingObserver {
  ui.Image? _fullScreenImage;
  bool _capturing = false;

  /// Drives [TickerMode] around the screens. The animated background would
  /// otherwise keep rendering at full frame rate while AlienShot sits hidden in
  /// the tray — the engine doesn't stop producing frames for a hidden window
  /// (measured ~27% of a core with nothing on screen).
  bool _windowVisible = false;
  _View _view = _View.home;
  AppSettings _settings = AppSettings.defaults();

  /// False when another program already owns the configured shortcut.
  bool _hotKeyActive = true;

  /// Windows runner channel: a second launch of AlienShot exits straight away
  /// and asks this copy to come forward instead (windows/runner/main.cpp).
  static const _instanceChannel = MethodChannel('alienshot/instance');

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    trayManager.addListener(this);
    WidgetsBinding.instance.addObserver(this);
    _instanceChannel.setMethodCallHandler(_onInstanceCall);
    _bootstrap();
  }

  /// Applies [mode] to the app and to the native title bar, which otherwise
  /// keeps following the Windows theme and clashes with an explicit choice.
  void _applyTheme(ThemeMode mode) {
    _themeMode.value = mode;
    if (!Platform.isWindows) return; // window_manager implements this on Windows only
    final brightness = switch (mode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => WidgetsBinding.instance.platformDispatcher.platformBrightness,
    };
    windowManager.setBrightness(brightness);
  }

  @override
  void didChangePlatformBrightness() {
    if (_themeMode.value == ThemeMode.system) _applyTheme(ThemeMode.system);
  }

  Future<void> _onInstanceCall(MethodCall call) async {
    if (call.method != 'activate') return;
    if (_windowVisible) {
      // Already on screen (home, settings, or a capture in progress).
      await windowManager.focus();
    } else {
      await _openWindow(_View.home);
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    WidgetsBinding.instance.removeObserver(this);
    hotKeyManager.unregisterAll();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await windowManager.setPreventClose(true);
    _settings = await settingsService.load();
    _applyTheme(_settings.themeMode);

    await trayService.init(
      onSignIn: _showSignInComingSoon,
      onCapture: _captureRegion,
      onOptions: () => _openWindow(_View.settings),
      onAbout: () => _openWindow(_View.about),
      onHelp: () => _openWindow(_View.help),
      onExit: _quit,
    );

    final hotKeyOk = await _registerHotKey();

    // Start hidden in the tray; the window only appears once the user opens
    // it from the tray menu or there's a screenshot to annotate.
    await _hideWindow();

    // Otherwise the shortcut would just silently do nothing.
    if (!hotKeyOk) await _warnHotKeyUnavailable();
  }

  Future<void> _showWindow() async {
    setState(() => _windowVisible = true);
    await windowManager.show();
  }

  Future<void> _hideWindow() async {
    if (mounted) setState(() => _windowVisible = false);
    await windowManager.hide();
  }

  /// Returns false when the shortcut is already owned by another program.
  Future<bool> _registerHotKey() async {
    await hotKeyManager.unregisterAll();
    final hotKey = resolveHotKey(_settings);
    final free = isHotKeyFree(hotKey);
    if (free) {
      await hotKeyManager.register(hotKey, keyDownHandler: (_) => _captureRegion());
    }
    if (mounted) setState(() => _hotKeyActive = free);
    return free;
  }

  Future<void> _warnHotKeyUnavailable() async {
    if (!_windowVisible) await _openWindow(_View.home);
    if (!mounted) return;
    final change = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Shortcut unavailable'),
        content: Text(
          '${resolveHotKeyLabel(_settings)} is already used by another program, '
          'so AlienShot can\'t respond to it. Pick a different shortcut — '
          'you can still capture from the tray icon meanwhile.',
          style: TextStyle(color: AlienPalette.of(context).textSoft, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Later')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Change shortcut')),
        ],
      ),
    );
    if (change == true && mounted) setState(() => _view = _View.settings);
  }

  /// Grabs a full-screen snapshot, then shows our own single-surface
  /// select-and-annotate screen on top of it — like Lightshot, never the
  /// OS Snipping Tool and never a separate editor window.
  Future<void> _captureRegion() async {
    if (_capturing) return;
    _capturing = true;
    try {
      // On macOS a capture without Screen Recording permission silently
      // returns the bare desktop, so bail out and let the OS ask first.
      if (!await captureService.ensureScreenCaptureAccess()) return;

      // Hide our own window first so it never ends up inside the capture —
      // but only when it's actually on screen. Triggered from the tray
      // hotkey (the common case), the window was never shown, so there's
      // nothing to wait for; skip straight to capturing instead of eating a
      // fixed delay on every single press.
      if (await windowManager.isVisible()) {
        await _hideWindow();
        // A fixed delay isn't reliable on its own (DWM can take longer to
        // actually drop our window from the composited frame), so poll
        // isVisible() with a short ceiling, then add a small
        // compositor-settle buffer.
        for (var i = 0; i < 6; i++) {
          if (!(await windowManager.isVisible())) break;
          await Future.delayed(const Duration(milliseconds: 25));
        }
        await Future.delayed(const Duration(milliseconds: 80));
      }

      final image = await captureService.captureScreen();
      if (image == null) return;

      setState(() {
        _fullScreenImage = image;
        _view = _View.capture;
      });

      // show()/focus() before toggling fullscreen+titlebar: applying those
      // to a still-hidden window is unreliable and can leave a normal-sized
      // bordered window on screen instead of a proper fullscreen overlay.
      await windowManager.setSkipTaskbar(false);
      await _showWindow();
      await windowManager.focus();
      await windowManager.setTitleBarStyle(
        TitleBarStyle.hidden,
        windowButtonVisibility: false,
      );
      await _coverScreen();
    } finally {
      _capturing = false;
    }
  }

  /// macOS runner channel (macos/Runner/MainFlutterWindow.swift).
  static const _macosChannel = MethodChannel('alienshot/macos');

  /// Stretches the window over the whole screen for the overlay.
  ///
  /// macOS deliberately skips native fullscreen: there it moves the window to
  /// its own Space with a half-second animation, which is exactly the lag an
  /// instant capture overlay must not have. The runner instead lifts the
  /// window above the menu bar and sizes it to the display, which is
  /// immediate.
  Future<void> _coverScreen() async {
    if (Platform.isMacOS) {
      await _macosChannel.invokeMethod<void>('setOverlayMode', true);
    } else {
      await windowManager.setFullScreen(true);
    }
  }

  /// Drops the captured frame — a full-screen [ui.Image] pins tens of MB of
  /// native memory, so it has to be released once the overlay is gone.
  void _discardCapture() {
    _fullScreenImage?.dispose();
    _fullScreenImage = null;
  }

  Future<void> _closeCapture() async {
    setState(() {
      _discardCapture();
      _view = _View.home;
    });
    await _restoreNormalWindowChrome();
    await windowManager.setSkipTaskbar(true);
    await _hideWindow();
  }

  /// Unconditionally resets fullscreen/titlebar state — safe to call even if
  /// the window is already in that state, and guards against getting stuck
  /// on screen if any single call fails.
  Future<void> _restoreNormalWindowChrome() async {
    try {
      if (Platform.isMacOS) {
        await _macosChannel.invokeMethod<void>('setOverlayMode', false);
      } else {
        await windowManager.setFullScreen(false);
      }
      await windowManager.setTitleBarStyle(
        TitleBarStyle.normal,
        windowButtonVisibility: true,
      );
    } catch (_) {
      // Fall through — hide() below still needs to run either way.
    }
  }

  /// Brings the window up on [view] from the tray, wherever it was before —
  /// including mid-capture, whose fullscreen chrome has to be undone first or
  /// the resize below has no effect.
  Future<void> _openWindow(_View view) async {
    if (_view == _View.capture) await _restoreNormalWindowChrome();
    setState(() {
      _view = view;
      _discardCapture();
    });
    await windowManager.setSize(const Size(480, 460));
    await windowManager.center();
    await windowManager.setSkipTaskbar(false);
    await _showWindow();
    await windowManager.focus();
  }

  void _openSettings() {
    setState(() => _view = _View.settings);
  }

  Future<void> _saveSettings(AppSettings settings) async {
    setState(() => _settings = settings);
    _applyTheme(settings.themeMode);
    await settingsService.save(settings);
    if (!await _registerHotKey()) await _warnHotKeyUnavailable();
  }

  Future<void> _minimizeToTray() async {
    await windowManager.setSkipTaskbar(true);
    await _hideWindow();
  }

  Future<void> _showSignInComingSoon() async {
    await _openWindow(_View.home);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign in'),
        content: Text(
          'AlienWave accounts are coming soon — you\'ll be able to sign in '
          'and keep every upload in one place.',
          style: TextStyle(color: AlienPalette.of(context).textSoft, height: 1.4),
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
        ],
      ),
    );
  }

  /// A left click on the tray icon: dismiss the taskbar's hidden-icons flyout
  /// first (the icon usually lives there) and give its close animation a
  /// moment, so the flyout isn't in the screenshot.
  Future<void> _captureFromTray() async {
    dismissTrayFlyout();
    await Future.delayed(const Duration(milliseconds: 180));
    await _captureRegion();
  }

  void _quit() {
    exit(0);
  }

  @override
  void onWindowClose() async {
    // Keep running in the tray instead of quitting when the window is closed.
    setState(() {
      _discardCapture();
      _view = _View.home;
    });
    await _restoreNormalWindowChrome();
    await windowManager.setSkipTaskbar(true);
    await _hideWindow();
  }

  // On Windows tray_manager reports both of these on button *release*.
  // A left click captures straight away, like Lightshot; on macOS menu-bar
  // icons conventionally open their menu on any click.
  @override
  void onTrayIconMouseDown() {
    if (Platform.isWindows) {
      _captureFromTray();
    } else {
      trayService.showMenu();
    }
  }

  @override
  void onTrayIconRightMouseDown() {
    trayService.showMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    trayService.handleMenuClick(menuItem);
  }

  @override
  Widget build(BuildContext context) {
    return TickerMode(enabled: _windowVisible, child: _buildView());
  }

  Widget _buildView() {
    switch (_view) {
      case _View.capture:
        final image = _fullScreenImage;
        if (image == null) {
          return const Scaffold(backgroundColor: Colors.black, body: SizedBox.shrink());
        }
        return LightshotCaptureScreen(
          screenImage: image,
          onClose: _closeCapture,
        );
      case _View.settings:
        return SettingsScreen(
          settings: _settings,
          onSave: _saveSettings,
          onPreviewTheme: _applyTheme,
          onBack: () {
            // Drops an unsaved theme preview; after Save this is a no-op.
            _applyTheme(_settings.themeMode);
            setState(() => _view = _View.home);
          },
        );
      case _View.about:
        return AboutScreen(onBack: () => setState(() => _view = _View.home));
      case _View.help:
        return HelpScreen(
          hotKeyLabel: resolveHotKeyLabel(_settings),
          onBack: () => setState(() => _view = _View.home),
        );
      case _View.home:
        return HomeScreen(
          hotKeyLabel: resolveHotKeyLabel(_settings),
          hotKeyActive: _hotKeyActive,
          onCapture: _captureRegion,
          onOpenSettings: _openSettings,
          onQuit: _quit,
          onMinimize: _minimizeToTray,
        );
    }
  }
}
