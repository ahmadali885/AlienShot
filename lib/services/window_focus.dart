import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Gives the foreground to this process's own (hidden) main window.
///
/// Clicking an icon inside the taskbar's "hidden icons" flyout leaves that
/// flyout open until something else takes focus, so a capture started from a
/// tray click would photograph it. Taking the foreground dismisses it — the
/// same thing Windows relies on before showing a tray context menu. A tray
/// click grants this process the right to do so.
void dismissTrayFlyout() {
  if (!Platform.isWindows) return;

  final className = 'FLUTTER_RUNNER_WIN32_WINDOW'.toNativeUtf16();
  final owner = calloc<Uint32>();
  try {
    final pid = GetCurrentProcessId();
    var hwnd = 0;
    // Match on process id as well: another AlienShot instance would use the
    // same window class.
    while ((hwnd = FindWindowEx(0, hwnd, className, nullptr)) != 0) {
      GetWindowThreadProcessId(hwnd, owner);
      if (owner.value == pid) {
        SetForegroundWindow(hwnd);
        return;
      }
    }
  } finally {
    calloc.free(className);
    calloc.free(owner);
  }
}
