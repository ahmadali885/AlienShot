import 'dart:io';

import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:uni_platform/uni_platform.dart';
import 'package:win32/win32.dart';

/// Whether [hotKey] can be claimed system-wide right now.
///
/// Windows gives a global hotkey to one program only, and hotkey_manager
/// ignores RegisterHotKey's result — so a combination another app already owns
/// "registers" without error and then simply never fires. Probe it directly.
/// Call this after unregistering our own hotkeys, or our own claim reads as
/// taken.
bool isHotKeyFree(HotKey hotKey) {
  if (!Platform.isWindows) return true;

  // Same key-code mapping hotkey_manager sends to the native side.
  final vk = hotKey.physicalKey.keyCode;
  if (vk == null) return false;

  var modifiers = 0;
  for (final m in hotKey.modifiers ?? const <HotKeyModifier>[]) {
    modifiers |= switch (m) {
      HotKeyModifier.alt => MOD_ALT,
      HotKeyModifier.control => MOD_CONTROL,
      HotKeyModifier.shift => MOD_SHIFT,
      HotKeyModifier.meta => MOD_WIN,
      _ => 0,
    };
  }

  const probeId = 0x5A11;
  if (RegisterHotKey(NULL, probeId, modifiers, vk) == 0) return false;
  UnregisterHotKey(NULL, probeId);
  return true;
}
