@TestOn('windows')
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:snapgrab/models/hotkey_preset.dart';
import 'package:uni_platform/uni_platform.dart';

void main() {
  test('non-letter keys map to a Windows key code, so they can be registered', () {
    final keys = [
      PhysicalKeyboardKey.printScreen,
      PhysicalKeyboardKey.arrowLeft,
      PhysicalKeyboardKey.arrowUp,
      PhysicalKeyboardKey.insert,
      PhysicalKeyboardKey.home,
      PhysicalKeyboardKey.pageDown,
      PhysicalKeyboardKey.pause,
      PhysicalKeyboardKey.space,
      PhysicalKeyboardKey.minus,
      PhysicalKeyboardKey.bracketLeft,
      PhysicalKeyboardKey.numpad5,
      PhysicalKeyboardKey.numpadAdd,
      PhysicalKeyboardKey.f13,
      PhysicalKeyboardKey.f24,
    ];
    final missing = [for (final k in keys) if (k.keyCode == null) k.debugName];
    expect(missing, isEmpty);
  });

  test('labels read the way Windows writes shortcuts', () {
    expect(formatHotKey(PhysicalKeyboardKey.keyS, [HotKeyModifier.shift, HotKeyModifier.control]), 'Ctrl + Shift + S');
    expect(formatHotKey(PhysicalKeyboardKey.printScreen, []), 'PrtSc');
    expect(formatHotKey(PhysicalKeyboardKey.arrowLeft, [HotKeyModifier.meta]), 'Win + ←');
    expect(formatHotKey(PhysicalKeyboardKey.digit1, [HotKeyModifier.alt]), 'Alt + 1');
  });
}
