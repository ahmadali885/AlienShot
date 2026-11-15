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
import 'models/recording_settings.dart';
import 'screens/about_screen.dart';
import 'screens/help_screen.dart';
import 'screens/home_screen.dart';
import 'screens/lightshot_capture_screen.dart';
import 'screens/mac_preferences_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/quick_overlay_screen.dart';
import 'screens/recording_screen.dart';
import 'screens/settings_screen.dart';
import 'services/capture_service.dart';
import 'services/hotkey_availability.dart';
import 'services/memory_trim.dart';
import 'services/recorder_service.dart';
import 'services/settings_service.dart';
import 'services/tray_service.dart';
import 'services/window_focus.dart';
import 'theme/app_theme.dart';
import 'widgets/sign_in_dialog.dart';

enum _View { home, settings, preferences, capture, overlay, recording, about, help, profile }

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

  /// The capture overlay is picking an area to record, not to screenshot.
  bool _recordMode = false;

  /// The area being recorded while [_View.recording] is up; null = the
  /// whole screen.
  Rect? _recordRegion;

  /// A full-screen recording waiting for the window to finish going full
  /// screen before its overlay is built.
  bool _recordingPending = false;

  /// The Settings tab to open on next, e.g. 'recording' from the overlay.
  String? _settingsTab;

  /// Lets the record/pause hotkeys reach the recording overlay.
  final GlobalKey<RecordingScreenState> _recordingKey = GlobalKey();

  /// Drives [TickerMode] around the screens. The animated background would
  /// otherwise keep rendering at full frame rate while AlienShot sits hidden in
  /// the tray — the engine doesn't stop producing frames for a hidden window
  /// (measured ~27% of a core with nothing on screen).
  bool _windowVisible = false;
  _View _view = _View.home;
  AppSettings _settings = AppSettings.defaults();

  /// True once the window has been set to fullscreen + hidden-titlebar while
  /// hidden in the tray, so the next capture can skip those steps entirely and
  /// just show the already-positioned window. Reset whenever we open a normal
  /// (home / settings) window.
  bool _overlayPrewarmed = false;

  /// The monitor (physical-pixel, virtual-screen rect) the prewarmed overlay
  /// is currently fullscreen on. Compared against the monitor under the
  /// cursor on the next capture — on a mismatch the window has to be moved,
  /// so the prewarm fast path is skipped and a full setup runs instead.
  Rect? _prewarmedMonitor;

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
    _trimTimer?.cancel();
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
      onRecord: recorderService.isSupported ? _recordScreen : null,
      onOptions: () => _openWindow(_settingsView),
      onAbout: () => _openWindow(_View.about),
      onHelp: () => _openWindow(_View.help),
      onExit: _quit,
      onStopRecording: recorderService.isSupported ? _stopAnyRecording : null,
      onPauseRecording: recorderService.isSupported ? _togglePauseRecording : null,
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
    _scheduleTrim();
  }

  Timer? _trimTimer;

  /// Gives the engine a moment to drop the hidden window's frames and the
  /// capture image first, so there's memory to give back; skipped if the
  /// window came back meanwhile (a capture hides it only briefly).
  void _scheduleTrim() {
    _trimTimer?.cancel();
    _trimTimer = Timer(const Duration(seconds: 2), () {
      if (!_windowVisible) trimWorkingSet();
    });
  }

  /// Shortcuts another program already owned at the last registration,
  /// e.g. "Alt + X (overlay)", for the warning.
  List<String> _takenHotKeys = const [];

  /// Registers the capture shortcut and, where recording is available, the
  /// overlay / record / pause ones. Returns false if any is already owned by
  /// another program.
  Future<bool> _registerHotKey() async {
    await hotKeyManager.unregisterAll();
    final taken = <String>[];
    final hotKey = resolveHotKey(_settings);
    // A cleared shortcut (macOS Preferences) leaves nothing to claim.
    final free = hotKey == null || isHotKeyFree(hotKey);
    if (hotKey != null && free) {
      await hotKeyManager.register(hotKey, keyDownHandler: (_) => _captureRegion());
    } else if (!free) {
      taken.add('${resolveHotKeyLabel(_settings)} (screenshot)');
    }
    await trayService.setShortcutHint(free ? hotKey : null);

    if (recorderService.isSupported) {
      final recording = _settings.recording;
      for (final (binding, name, action) in [
        (recording.overlayHotKey, 'overlay', _toggleOverlay),
        (recording.recordHotKey, 'start/stop recording', _toggleRecording),
        (recording.pauseHotKey, 'pause recording', _togglePauseRecording),
      ]) {
        if (binding == null) continue;
        final recordingHotKey = binding.toHotKey();
        // Probed after ours are registered, so two of our own shortcuts on
        // the same keys show up as a clash too.
        if (isHotKeyFree(recordingHotKey)) {
          await hotKeyManager.register(recordingHotKey, keyDownHandler: (_) => action());
        } else {
          taken.add('${binding.label} ($name)');
        }
      }
    }
    _takenHotKeys = taken;
    if (mounted) setState(() => _hotKeyActive = free);
    return taken.isEmpty;
  }

  /// Where "Options…"/"Preferences…" and the gear lead: the Mac gets
  /// Lightshot's short preferences window, Windows the full settings.
  _View get _settingsView => Platform.isMacOS ? _View.preferences : _View.settings;

  Future<void> _warnHotKeyUnavailable() async {
    if (!_windowVisible) await _openWindow(_View.home);
    if (!mounted) return;
    final change = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Shortcut unavailable'),
        content: Text(
          '${_takenHotKeys.join(', ')} ${_takenHotKeys.length == 1 ? 'is' : 'are'} already used by another '
          'program, so AlienShot can\'t respond to ${_takenHotKeys.length == 1 ? 'it' : 'them'}. Pick a '
          'different shortcut — the tray icon still works meanwhile.',
          style: TextStyle(color: AlienPalette.of(context).textSoft, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Later')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Change shortcut')),
        ],
      ),
    );
    if (change == true && mounted) await _openWindow(_settingsView);
  }

  /// Starts picking an area to record (Windows only for now).
  Future<void> _recordScreen() => _captureRegion(record: true);

  /// The record hotkey: stops a running recording, else starts one — of
  /// the whole screen straight away (like NVIDIA's), or by picking an area,
  /// as the settings say.
  void _toggleRecording() {
    if (_hiddenRecording) {
      _stopHiddenRecording();
    } else if (_view == _View.recording) {
      _recordingKey.currentState?.stop();
    } else if (!_settings.recording.hotKeyStartsFullScreen) {
      _recordScreen();
    } else if (_settings.recording.hotKeyShowsControls) {
      _recordFullScreen();
    } else {
      _startHiddenRecording();
    }
  }

  void _togglePauseRecording() {
    if (_hiddenRecording) {
      _toggleHiddenPause();
    } else if (_view == _View.recording) {
      _recordingKey.currentState?.togglePause();
    }
  }

  /// Stop from the tray menu, whichever kind of recording is running.
  void _stopAnyRecording() {
    if (_hiddenRecording) {
      _stopHiddenRecording();
    } else if (_view == _View.recording) {
      _recordingKey.currentState?.stop();
    }
  }

  // --- Recording with nothing on screen (the record hotkey, NVIDIA-style) ---
  //
  // No window, no overlay: the native recorder grabs the monitor under the
  // cursor by itself, and the tray icon turning red is the only sign. With
  // no window over a game, Windows can keep presenting it the fast way.

  bool _hiddenRecording = false;
  bool _hiddenPaused = false;
  String? _hiddenPath;

  Future<void> _startHiddenRecording() async {
    if (_hiddenRecording || _capturing || _view == _View.capture || _view == _View.recording) return;
    if (_view == _View.overlay) await _closeCapture();
    final settings = _settings.recording;
    try {
      final path = await recorderService.newRecordingPath(settings);
      await recorderService.start(region: Rect.zero, monitorAtCursor: true, path: path, settings: settings);
      _hiddenPath = path;
      _hiddenRecording = true;
      _hiddenPaused = false;
      await trayService.setRecording(recording: true, stopHint: settings.recordHotKey?.label);
    } on PlatformException catch (e) {
      // Nothing is recording, so this is worth a window.
      await _showRecordingError(e.message ?? 'The recording could not start.');
    }
  }

  Future<void> _toggleHiddenPause() async {
    if (!_hiddenRecording) return;
    _hiddenPaused ? await recorderService.resume() : await recorderService.pause();
    _hiddenPaused = !_hiddenPaused;
    await trayService.setRecording(
      recording: true,
      paused: _hiddenPaused,
      stopHint: _settings.recording.recordHotKey?.label,
    );
  }

  Future<void> _stopHiddenRecording() async {
    if (!_hiddenRecording) return;
    _hiddenRecording = false;
    await trayService.setRecording(recording: false);
    try {
      await recorderService.stop();
      // Still nothing on screen (the user may be mid-game): the tray says
      // where the video went, and the overlay's Recordings tile opens it.
      final name = _hiddenPath!.split(Platform.pathSeparator).last;
      await trayService.setTooltip('AlienShot — saved $name');
    } on PlatformException catch (e) {
      await _showRecordingError(e.message ?? 'The recording could not be saved.');
    }
  }

  Future<void> _showRecordingError(String message) async {
    await _openWindow(_View.home);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Couldn't record"),
        content: Text(message, style: TextStyle(color: AlienPalette.of(context).textSoft, height: 1.4)),
        actions: [FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
      ),
    );
  }

  /// Records the whole screen without picking an area: the window goes
  /// full screen and see-through first, and only then is the recording
  /// overlay built, so it measures the real screen size.
  Future<void> _recordFullScreen() async {
    if (_capturing || _view == _View.capture || _view == _View.recording || _hiddenRecording) return;
    if (!recorderService.isSupported) return;
    final fromOverlay = _view == _View.overlay;
    setState(() {
      _discardCapture();
      _recordRegion = null;
      _recordingPending = true;
      _view = _View.recording;
    });
    await windowManager.setBackgroundColor(Colors.transparent);
    if (!fromOverlay) {
      await windowManager.setSkipTaskbar(false);
      await _showWindow();
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
      await _coverScreen();
    }
    await windowManager.setAlwaysOnTop(true);
    // Let the full-screen size reach Flutter before the overlay reads it.
    await Future.delayed(const Duration(milliseconds: 150));
    if (mounted) setState(() => _recordingPending = false);
  }

  /// Grabs a full-screen snapshot, then shows our own single-surface
  /// select-and-annotate screen on top of it — like Lightshot, never the
  /// OS Snipping Tool and never a separate editor window.
  /// With [overlay], the frozen screen becomes the backdrop of the NVIDIA-
  /// style overlay instead of the selection screen.
  Future<void> _captureRegion({bool record = false, bool overlay = false}) async {
    // From the overlay, its frozen frame (taken before it appeared) is reused:
    // screenshot and area selection open instantly.
    if (_view == _View.overlay && _fullScreenImage != null && !overlay) {
      if (record && (!recorderService.isSupported || _hiddenRecording)) return;
      setState(() {
        _recordMode = record;
        _view = _View.capture;
      });
      return;
    }
    // Also ignore the shortcut while the overlay is up: the hotkey isn't
    // registered with MOD_NOREPEAT, so holding the key a moment too long fires
    // it again, which hid the overlay mid-drag to take a fresh capture.
    if (_capturing || _view == _View.capture || _view == _View.recording || _view == _View.overlay) return;
    if ((record || overlay) && (!recorderService.isSupported || _hiddenRecording)) return;
    _capturing = true;
    try {
      // On macOS a capture without Screen Recording permission silently
      // returns the bare desktop, so bail out and let the OS ask first.
      if (!await captureService.ensureScreenCaptureAccess()) return;

      // Which monitor to capture and show the overlay on — the one the mouse
      // is actually on, not whatever monitor the (hidden) window happens to
      // still be sitting on from last time.
      final targetMonitor = Platform.isWindows ? captureService.monitorRectAtCursor() : null;

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

      final image = await captureService.captureScreen(monitor: targetMonitor);
      if (image == null) return;

      setState(() {
        _fullScreenImage = image;
        _recordMode = record;
        _view = overlay ? _View.overlay : _View.capture;
      });

      await windowManager.setSkipTaskbar(false);
      // The fast path only helps if the window is already sitting fullscreen
      // on the SAME monitor we need this time — otherwise it has to be moved,
      // so fall back to the full setup below.
      final canUseFastPath =
          _overlayPrewarmed && (targetMonitor == null || targetMonitor == _prewarmedMonitor);
      if (canUseFastPath) {
        // Window is already fullscreen + titlebar-hidden from the previous
        // capture. Just show and focus — no DWM animation, ~instant.
        _overlayPrewarmed = false;
        await _showWindow();
        await windowManager.focus();
      } else {
        _overlayPrewarmed = false;
        // First capture, after settings were opened, or the cursor has moved
        // to a different monitor: full setup required. show()/focus() before
        // toggling fullscreen+titlebar: applying those to a still-hidden
        // window is unreliable and can leave a normal-sized bordered window
        // on screen instead of a proper fullscreen overlay.
        await _showWindow();
        await windowManager.focus();
        await windowManager.setTitleBarStyle(
          TitleBarStyle.hidden,
          windowButtonVisibility: false,
        );
        if (targetMonitor != null) {
          // Move the window onto the target monitor first — setFullScreen()
          // below always fullscreens onto whichever monitor the window is
          // currently nearest to, so it has to already be there.
          final ratio = WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
          await windowManager.setBounds(
            Rect.fromLTWH(
              targetMonitor.left / ratio,
              targetMonitor.top / ratio,
              targetMonitor.width / ratio,
              targetMonitor.height / ratio,
            ),
          );
        }
        await _coverScreen();
        _prewarmedMonitor = targetMonitor;
      }
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
    // Keep the window in fullscreen + hidden-titlebar state so the next
    // capture can appear instantly (no DWM animation on show). Chrome is
    // restored lazily in _openWindow if the user opens settings instead.
    await windowManager.setSkipTaskbar(true);
    await _hideWindow();
    _overlayPrewarmed = true;
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
    // The recording overlay must stay put until the user stops it.
    if (_view == _View.recording) return;
    if (_view == _View.capture || _view == _View.overlay || _overlayPrewarmed) {
      await _restoreNormalWindowChrome();
      _overlayPrewarmed = false;
    }
    setState(() {
      _view = view;
      _discardCapture();
    });
    // The Mac preferences hold two rows; a compact window suits them, as
    // Lightshot's does. Settings (with the OBS-style Recording tab) needs room.
    await windowManager.setSize(switch (view) {
      _View.preferences => const Size(460, 250),
      _View.settings => const Size(720, 640),
      _ => const Size(480, 460),
    });
    await windowManager.center();
    await windowManager.setSkipTaskbar(false);
    // A window that's open for use must take clicks, whatever a recording
    // left behind.
    if (recorderService.isSupported) await recorderService.setClickThrough(enabled: false);
    await _showWindow();
    await windowManager.focus();
  }

  /// [tab] opens Settings on that tab, e.g. 'recording' from the overlay.
  void _openSettings({String? tab}) {
    if (Platform.isMacOS) {
      _openWindow(_View.preferences);
    } else {
      _settingsTab = tab;
      _openWindow(_View.settings);
    }
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
    // Pre-warm the overlay so the first hotkey press is also instant.
    await _prewarmOverlay();
  }

  /// Sets the window to fullscreen + hidden-titlebar while it is hidden, so
  /// the next capture can skip those steps and appear instantly.
  /// Works on both Windows (avoids DWM animation) and macOS (setOverlayMode
  /// is already immediate, but skipping it entirely is even faster).
  Future<void> _prewarmOverlay() async {
    if (_overlayPrewarmed) return;
    await windowManager.setTitleBarStyle(
      TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
    await _coverScreen();
    _overlayPrewarmed = true;
  }

  /// Tray "Sign In…": lands on the profile page, where signing in will live.
  Future<void> _showSignInComingSoon() async {
    await _openWindow(_View.profile);
    if (!mounted) return;
    await showSignInComingSoon(context);
  }

  /// Saves only the name: going through [_saveSettings] would re-register
  /// the hotkey and could pop its warning for an unrelated change.
  Future<void> _renameProfile(String name) async {
    final settings = _settings.copyWith(displayName: name);
    setState(() => _settings = settings);
    await settingsService.save(settings);
  }

  /// A left click on the tray icon: dismiss the taskbar's hidden-icons flyout
  /// first (the icon usually lives there) and give its close animation a
  /// moment, so the flyout isn't in the screenshot.
  Future<void> _captureFromTray() async {
    dismissTrayFlyout();
    await Future.delayed(const Duration(milliseconds: 180));
    await _captureRegion();
  }

  Future<void> _quit() async {
    // A recording that isn't finished is an unplayable file; save it first.
    if (_hiddenRecording) await _stopHiddenRecording();
    if (_view == _View.recording) await _recordingKey.currentState?.stop();
    exit(0);
  }

  /// Record pressed: the frozen frame goes and the window turns into the
  /// see-through, always-on-top recording overlay (still full screen).
  Future<void> _beginRecording(Rect region) async {
    setState(() {
      _discardCapture();
      _recordRegion = region;
      _view = _View.recording;
    });
    await windowManager.setBackgroundColor(Colors.transparent);
    await windowManager.setAlwaysOnTop(true);
  }

  /// The recording overlay is done: [path] when a file was saved, else
  /// [error] (empty when the user just backed out during the countdown).
  Future<void> _endRecording({String? path, String error = ''}) async {
    await recorderService.setClickThrough(enabled: false);
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setBackgroundColor(AppColors.ink);
    await _restoreNormalWindowChrome();
    setState(() {
      _recordRegion = null;
      _recordMode = false;
      _view = _View.home;
    });
    // Again, now the recording screen is gone: nothing can turn it back on.
    await WidgetsBinding.instance.endOfFrame;
    await recorderService.setClickThrough(enabled: false);
    if (error.isEmpty) {
      // No popup: back to the tray, which says where the video went (the
      // overlay's Recordings tile opens the folder), as hotkey recording does.
      await windowManager.setSkipTaskbar(true);
      await _hideWindow();
      if (path != null) {
        await trayService.setTooltip('AlienShot — saved ${path.split(Platform.pathSeparator).last}');
      }
      return;
    }
    await _openWindow(_View.home);
    if (!mounted) return;
    {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Couldn't record"),
          content: Text(error, style: TextStyle(color: AlienPalette.of(context).textSoft, height: 1.4)),
          actions: [FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
        ),
      );
    }
  }

  /// Quick changes from the record bar and overlay; saved straight away.
  Future<void> _saveRecordingSettings(RecordingSettings recording) async {
    final settings = _settings.copyWith(recording: recording);
    setState(() => _settings = settings);
    await settingsService.save(settings);
  }

  /// The overlay hotkey: opens the NVIDIA-style overlay, or closes it.
  Future<void> _toggleOverlay() async {
    if (_view == _View.overlay) {
      await _closeCapture();
    } else if (_view != _View.recording && _view != _View.capture) {
      await _captureRegion(overlay: true);
    }
  }

  Future<void> _openRecordingsFolder() async {
    final folder = Directory(recorderService.folderFor(_settings.recording));
    await folder.create(recursive: true);
    await Process.start('explorer.exe', [folder.path]);
  }

  @override
  void onWindowClose() async {
    // Closing the overlay mid-recording would lose the file; Stop saves it.
    if (_view == _View.recording) return;
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
    if (_hiddenRecording) {
      // The red tray icon is the recording's stop button.
      _stopHiddenRecording();
    } else if (Platform.isWindows) {
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
          downscaleRetina: Platform.isMacOS && _settings.downscaleRetina,
          onRecord: _recordMode ? _beginRecording : null,
          recordSettings: _settings.recording,
          onRecordSettingsChanged: _saveRecordingSettings,
        );
      case _View.overlay:
        return QuickOverlayScreen(
          backdrop: _fullScreenImage,
          settings: _settings.recording,
          overlayHotKeyLabel: _settings.recording.overlayHotKey?.label,
          recordHotKeyLabel: _settings.recording.recordHotKey?.label,
          onScreenshot: () => _captureRegion(),
          onRecordFullScreen: _recordFullScreen,
          onRecordArea: _recordScreen,
          onOpenRecordings: () {
            _openRecordingsFolder();
            _closeCapture();
          },
          onOpenSettings: () => _openSettings(tab: 'recording'),
          onSettingsChanged: _saveRecordingSettings,
          onClose: _closeCapture,
        );
      case _View.recording:
        // See-through and empty until a full-screen window is in place.
        if (_recordingPending) return const SizedBox.shrink();
        return RecordingScreen(
          key: _recordingKey,
          region: _recordRegion,
          settings: _settings.recording,
          onFinished: (path) => _endRecording(path: path),
          onError: (error) => _endRecording(error: error),
        );
      case _View.preferences:
        return MacPreferencesScreen(
          settings: _settings,
          onChanged: _saveSettings,
          onBack: () => _openWindow(_View.home),
        );
      case _View.settings:
        return SettingsScreen(
          settings: _settings,
          initialTab: _settingsTab,
          showRecordingTab: recorderService.isSupported,
          onSave: _saveSettings,
          onPreviewTheme: _applyTheme,
          onBack: () {
            // Drops an unsaved theme preview; after Save this is a no-op.
            _applyTheme(_settings.themeMode);
            // Back to the home window's own (smaller) size.
            _openWindow(_View.home);
          },
        );
      case _View.about:
        return AboutScreen(onBack: () => setState(() => _view = _View.home));
      case _View.help:
        return HelpScreen(
          hotKeyLabel: resolveHotKeyLabel(_settings),
          onBack: () => setState(() => _view = _View.home),
        );
      case _View.profile:
        return ProfileScreen(
          displayName: _settings.displayName,
          onRename: _renameProfile,
          onBack: () => setState(() => _view = _View.home),
        );
      case _View.home:
        return HomeScreen(
          hotKeyLabel: resolveHotKeyLabel(_settings),
          hotKeyActive: _hotKeyActive,
          onCapture: _captureRegion,
          onRecord: recorderService.isSupported ? _recordScreen : null,
          onOpenSettings: _openSettings,
          onOpenAbout: () => setState(() => _view = _View.about),
          onOpenProfile: () => setState(() => _view = _View.profile),
          onQuit: _quit,
          onMinimize: _minimizeToTray,
        );
    }
  }
}
