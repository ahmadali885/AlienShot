import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:uni_platform/uni_platform.dart';

import '../models/hotkey_preset.dart';
import '../theme/app_theme.dart';

/// Keys that may be a shortcut on their own. Anything else types text or
/// moves the caret, so claiming it system-wide without a modifier would break
/// normal typing everywhere.
final Set<PhysicalKeyboardKey> _kStandaloneKeys = {
  PhysicalKeyboardKey.f1, PhysicalKeyboardKey.f2, PhysicalKeyboardKey.f3,
  PhysicalKeyboardKey.f4, PhysicalKeyboardKey.f5, PhysicalKeyboardKey.f6,
  PhysicalKeyboardKey.f7, PhysicalKeyboardKey.f8, PhysicalKeyboardKey.f9,
  PhysicalKeyboardKey.f10, PhysicalKeyboardKey.f11, PhysicalKeyboardKey.f12,
  PhysicalKeyboardKey.f13, PhysicalKeyboardKey.f14, PhysicalKeyboardKey.f15,
  PhysicalKeyboardKey.f16, PhysicalKeyboardKey.f17, PhysicalKeyboardKey.f18,
  PhysicalKeyboardKey.f19, PhysicalKeyboardKey.f20, PhysicalKeyboardKey.f21,
  PhysicalKeyboardKey.f22, PhysicalKeyboardKey.f23, PhysicalKeyboardKey.f24,
  PhysicalKeyboardKey.printScreen, PhysicalKeyboardKey.pause,
  PhysicalKeyboardKey.scrollLock, PhysicalKeyboardKey.insert,
};

/// Keys that only ever act as modifiers (or toggles) and can't be the
/// shortcut's main key.
final Set<PhysicalKeyboardKey> _kModifierKeys = {
  PhysicalKeyboardKey.controlLeft, PhysicalKeyboardKey.controlRight,
  PhysicalKeyboardKey.shiftLeft, PhysicalKeyboardKey.shiftRight,
  PhysicalKeyboardKey.altLeft, PhysicalKeyboardKey.altRight,
  PhysicalKeyboardKey.metaLeft, PhysicalKeyboardKey.metaRight,
  PhysicalKeyboardKey.fn, PhysicalKeyboardKey.capsLock,
};

class RecordedHotKey {
  RecordedHotKey({required this.key, required this.modifiers});

  final PhysicalKeyboardKey key;
  final List<HotKeyModifier> modifiers;

  String get label => formatHotKey(key, modifiers);
}

Future<RecordedHotKey?> showHotKeyRecorderDialog(BuildContext context) {
  return showDialog<RecordedHotKey>(
    context: context,
    builder: (context) => const _HotKeyRecorderDialog(),
  );
}

class _HotKeyRecorderDialog extends StatefulWidget {
  const _HotKeyRecorderDialog();

  @override
  State<_HotKeyRecorderDialog> createState() => _HotKeyRecorderDialogState();
}

class _HotKeyRecorderDialogState extends State<_HotKeyRecorderDialog> {
  final FocusNode _focusNode = FocusNode();
  String? _error;
  List<HotKeyModifier> _liveModifiers = [];

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  List<HotKeyModifier> _currentModifiers() {
    final pressed = HardwareKeyboard.instance.physicalKeysPressed;
    return [
      for (final m in [HotKeyModifier.control, HotKeyModifier.shift, HotKeyModifier.alt, HotKeyModifier.meta])
        if (m.physicalKeys.any(pressed.contains)) m,
    ];
  }

  String get _modifierHint => Platform.isMacOS ? '⌘, ⌥, ⌃ or ⇧' : 'Ctrl, Alt, Shift or Win';

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    final key = event.physicalKey;
    // Windows reports Print Screen with a key-up only, no key-down.
    final isPress = event is KeyDownEvent ||
        (event is KeyUpEvent && key == PhysicalKeyboardKey.printScreen);
    if (!isPress) {
      setState(() => _liveModifiers = _currentModifiers());
      return KeyEventResult.handled;
    }

    if (key == PhysicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }

    if (_kModifierKeys.contains(key)) {
      setState(() {
        _error = null;
        _liveModifiers = _currentModifiers();
      });
      return KeyEventResult.handled;
    }

    // hotkey_manager hands the native side this platform key code; a key
    // without one (some media/OEM keys) can't be registered at all.
    if (key.keyCode == null) {
      setState(() => _error = "That key can't be used as a shortcut");
      return KeyEventResult.handled;
    }

    final modifiers = _currentModifiers();
    if (modifiers.isEmpty && !_kStandaloneKeys.contains(key)) {
      setState(() => _error = 'Add $_modifierHint to ${keyLabel(key)}');
      return KeyEventResult.handled;
    }

    Navigator.of(context).pop(RecordedHotKey(key: key, modifiers: modifiers));
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AlienPalette.of(context);
    final mods = formatModifiers(_liveModifiers);
    return AlertDialog(
      title: const Text('Record a shortcut'),
      content: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _handleKey,
        child: Container(
          width: 320,
          padding: const EdgeInsets.symmetric(vertical: 24),
          decoration: BoxDecoration(
            color: palette.ghostFill,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.glassBorder),
          ),
          child: Column(
            children: [
              Icon(Icons.keyboard_rounded, color: palette.accentText, size: 28),
              const SizedBox(height: 14),
              Text(
                mods.isEmpty ? '…' : (Platform.isMacOS ? '$mods…' : '$mods + …'),
                style: TextStyle(
                  fontFamily: AppFonts.display,
                  color: palette.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Press your new shortcut now',
                style: TextStyle(color: palette.textSoft, fontSize: 12),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
