import 'dart:io';

import 'package:win32/win32.dart';

/// Hands AlienShot's idle memory back to Windows while it sits in the tray.
///
/// The engine keeps its pages resident after the window is hidden (Dart heap,
/// raster caches, the last capture's textures), so the app went on occupying
/// a few hundred MB while doing nothing. Emptying the working set moves those
/// pages to the standby list: Task Manager then shows only what is actually
/// being touched, and the pages fault back in cheaply when the next capture
/// needs them.
void trimWorkingSet() {
  if (!Platform.isWindows) return;
  EmptyWorkingSet(GetCurrentProcess());
}
