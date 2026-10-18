# AlienShot

by [AlienWave](https://alienwavegroup.com) — themed to match the AlienWave site (Outfit/Urbanist type, ink-and-teal palette, animated hero shader in `shaders/hero.frag`).

A lightweight Lightshot-style screenshot & annotation tool for Windows and macOS, built with Flutter desktop.

## Features

- Own drag-to-select capture overlay (not the OS Snipping Tool) — dims the screen, shows a
  live selection box with dimensions, `Esc` to cancel
- Global hotkey (`Ctrl+Shift+S` by default, or record your own in Settings)
- Runs from the system tray — no window until you open it or capture something
- Home screen + Settings screen (hotkey picker/recorder, auto-copy, auto-upload, default save folder)
- Annotate: rectangle, arrow, freehand pen, highlighter, text
- Copy the annotated image straight to the clipboard
- Save as PNG anywhere on disk
- "Upload link" — uploads to catbox.moe (no account needed) and copies a shareable link to your clipboard

## One-time setup (after installing the Flutter SDK)

```bash
cd D:\flutter\snapgrab
flutter create --platforms=windows,macos .
flutter pub get
```

`flutter create --platforms=...` on an existing project only adds the missing
`windows/` and `macos/` runner folders — it will not touch `lib/` or `pubspec.yaml`.

## Run it

```bash
flutter run -d windows
```

The app starts hidden with just a tray icon. Press the capture hotkey (or use the tray
menu → "Capture region") to drag-select an area of the screen; the editor window pops up
automatically once you release. Tray menu → "Open AlienShot" shows the Home/Settings window.

## Build the .exe (Windows)

Requires Visual Studio (or just "Build Tools for Visual Studio") with the "Desktop
development with C++" workload.

```bash
flutter build windows --release
```

Output: `build\windows\x64\runner\Release\AlienShot.exe` (+ the DLLs and `data\` folder
next to it — the whole `Release` folder is the distributable app).

## Build a proper installer (setup.exe)

Uses [Inno Setup](https://jrsoftware.org/isinfo.php) (free). After `flutter build windows --release`:

```bash
"%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe" installer\alienshot.iss
```

Output: `installer\output\AlienShot-Setup.exe` — a normal Windows installer (no admin rights
needed, optional desktop icon / launch-at-startup checkboxes, proper uninstaller). It keeps
the AppId of the old "Snaply" builds, so it upgrades an existing Snaply install in place and
removes its leftover folder and shortcuts.

## Build for macOS

Must be done on a Mac with Xcode — there is no cross-compiling from Windows.
Without a Mac, push to GitHub: `.github/workflows/macos.yml` builds the app on a
hosted Mac and uploads `AlienShot-macos.zip` as a workflow artifact.

```bash
flutter build macos --release
```

Output: `build/macos/Build/Products/Release/AlienShot.app`

The build is ad-hoc signed, not notarized, so on another Mac Gatekeeper blocks
the first launch: right-click the app → **Open**, or run
`xattr -cr AlienShot.app` once.

On first launch macOS will ask for **Screen Recording** permission (System
Settings → Privacy & Security → Screen Recording). Until it's granted the
capture silently returns nothing but the desktop wallpaper, so the app checks
for it before every capture and triggers the system prompt instead.

### macOS-specific decisions

- **App Sandbox is off** (`macos/Runner/*.entitlements`). `screen_capturer`
  shells out to the system's `/usr/sbin/screencapture`, and a sandboxed app
  cannot spawn it. That rules out Mac App Store distribution; direct download
  (ideally signed + notarized) is the path.
- **`LSUIElement` is set** so AlienShot lives only in the menu bar with no Dock
  icon — the counterpart of `skipTaskbar` on Windows.
- **`applicationShouldTerminateAfterLastWindowClosed` returns `false`.** The
  stock template returns `true`, which quits the whole app the moment the
  overlay closes, killing the hotkey after a single capture.
- **The overlay does not use native fullscreen on macOS.** `setFullScreen(true)`
  moves the window into its own Space with a ~0.5s animation. Instead
  `MainFlutterWindow.swift` (channel `alienshot/macos`, `setOverlayMode`) lifts
  the window to `.screenSaver` level and lets it cover the menu bar —
  AppKit otherwise constrains titled windows below it.
- **The menu-bar icon is a template image** (`assets/images/tray_icon_template.png`,
  black alpha silhouette), so macOS tints it for light and dark menu bars. A
  click opens the menu, per menu-bar convention; Windows captures on left click.
- **No single-instance code is needed**: LaunchServices already brings a
  running app forward instead of starting a second copy.

### Still to check on a Mac

None of the above has been run on macOS yet — it was prepared from Windows.
Known open item:

- **Capture is still slow on macOS.** Windows captures straight into memory via
  GDI; macOS still goes through `screen_capturer`, which writes a PNG to disk
  and decodes it again. The equivalent fast path is a Swift method channel
  using ScreenCaptureKit (`SCScreenshotManager`, macOS 14+).

## Notes / things you may want to change

- **Upload host**: `lib/services/upload_service.dart` uploads anonymously to catbox.moe
  (public, no API key, files are permanent). Swap the endpoint for your own backend,
  S3 bucket, or an Imgur client-id if you want private/expiring links.
- **App & tray icons**: `assets/images/tray_icon.ico` / `tray_icon.png` / `app_icon.ico`.
  Regenerate or replace with your own artwork; also update
  `windows/runner/resources/app_icon.ico` (created by `flutter create`) for the
  taskbar/window icon, since that one isn't sourced from `assets/`.
- **Hotkey presets**: curated in `lib/models/hotkey_preset.dart`. Users can also record
  their own combo from Settings (`lib/widgets/hotkey_recorder_dialog.dart`).
- **Do not add `LogicalKeyboardKey.printScreen` (or any non letter/digit/F-key) as a
  hotkey.** The `hotkey_manager` package (v0.2.3) has a bug in its Windows key-code
  lookup for keys it can't map to a VK code (PrintScreen, media keys, etc.): the native
  plugin's C++ side does `std::get<int>` on a null value with no null-check, which
  throws across a non-throwing callback boundary and hard-crashes the process
  (`STATUS_STACK_BUFFER_OVERRUN`, visible in Windows Event Viewer as a fault in
  `hotkey_manager_windows_plugin.dll`) a few seconds after registration. That's why both
  the curated presets and the custom recorder (`kAllowedHotKeyBodyKeys`) only allow
  letters, digits, and F1–F12.
- **Region capture**: `screen_capturer`'s `CaptureMode.region` shells out to Windows'
  own Snipping Tool (`ms-screenclip:`) — that's not what we want for a branded tool, so
  capture instead uses `CaptureMode.screen` (a real native full-screen grab) plus our own
  `lib/screens/capture_overlay_screen.dart` for the drag-select UI.
- **Native title bar during capture**: hidden dynamically via
  `windowManager.setTitleBarStyle(TitleBarStyle.hidden)` right before entering the
  full-screen overlay, and restored to `.normal` right after. Do **not** set
  `TitleBarStyle.hidden` in `main.dart`'s initial `WindowOptions` — combined with the
  window starting fully hidden, that causes a silent early exit (no crash dialog, no
  Event Viewer entry) a few seconds after launch. Toggling it at runtime on an
  already-shown window is fine.
