import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import '../theme/app_theme.dart';

/// Keys we allow as the "body" of a custom shortcut. Deliberately excludes
/// PrintScreen, media keys, arrows, etc. — hotkey_manager's Windows plugin
/// crashes on keys it can't map to a VK code, and letters/digits/F-keys are
/// always safe (see README).
final List<LogicalKeyboardKey> kAllowedHotKeyBodyKeys = [
  for (final k in [
    LogicalKeyboardKey.keyA, LogicalKeyboardKey.keyB, LogicalKeyboardKey.keyC,
    LogicalKeyboardKey.keyD, LogicalKeyboardKey.keyE, LogicalKeyboardKey.keyF,
    LogicalKeyboardKey.keyG, LogicalKeyboardKey.keyH, LogicalKeyboardKey.keyI,
    LogicalKeyboardKey.keyJ, LogicalKeyboardKey.keyK, LogicalKeyboardKey.keyL,
    LogicalKeyboardKey.keyM, LogicalKeyboardKey.keyN, LogicalKeyboardKey.keyO,
    LogicalKeyboardKey.keyP, LogicalKeyboardKey.keyQ, LogicalKeyboardKey.keyR,
    LogicalKeyboardKey.keyS, LogicalKeyboardKey.keyT, LogicalKeyboardKey.keyU,
    LogicalKeyboardKey.keyV, LogicalKeyboardKey.keyW, LogicalKeyboardKey.keyX,
    LogicalKeyboardKey.keyY, LogicalKeyboardKey.keyZ,
    LogicalKeyboardKey.digit0, LogicalKeyboardKey.digit1, LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3, LogicalKeyboardKey.digit4, LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6, LogicalKeyboardKey.digit7, LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
    LogicalKeyboardKey.f1, LogicalKeyboardKey.f2, LogicalKeyboardKey.f3,
    LogicalKeyboardKey.f4, LogicalKeyboardKey.f5, LogicalKeyboardKey.f6,
    LogicalKeyboardKey.f7, LogicalKeyboardKey.f8, LogicalKeyboardKey.f9,
    LogicalKeyboardKey.f10, LogicalKeyboardKey.f11, LogicalKeyboardKey.f12,
  ])
    k,
];

final Set<LogicalKeyboardKey> _kFunctionKeys = {
  LogicalKeyboardKey.f1, LogicalKeyboardKey.f2, LogicalKeyboardKey.f3,
  LogicalKeyboardKey.f4, LogicalKeyboardKey.f5, LogicalKeyboardKey.f6,
  LogicalKeyboardKey.f7, LogicalKeyboardKey.f8, LogicalKeyboardKey.f9,
  LogicalKeyboardKey.f10, LogicalKeyboardKey.f11, LogicalKeyboardKey.f12,
};

class RecordedHotKey {
  RecordedHotKey({required this.key, required this.modifiers, required this.label});

  final LogicalKeyboardKey key;
  final List<HotKeyModifier> modifiers;
  final String label;
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
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    return [
      if (pressed.contains(LogicalKeyboardKey.controlLeft) ||
          pressed.contains(LogicalKeyboardKey.controlRight))
        HotKeyModifier.control,
      if (pressed.contains(LogicalKeyboardKey.shiftLeft) ||
          pressed.contains(LogicalKeyboardKey.shiftRight))
        HotKeyModifier.shift,
      if (pressed.contains(LogicalKeyboardKey.altLeft) ||
          pressed.contains(LogicalKeyboardKey.altRight))
        HotKeyModifier.alt,
      if (pressed.contains(LogicalKeyboardKey.metaLeft) ||
          pressed.contains(LogicalKeyboardKey.metaRight))
        HotKeyModifier.meta,
    ];
  }

  String _modifierLabel(List<HotKeyModifier> modifiers) {
    return modifiers.map((m) {
      switch (m) {
        case HotKeyModifier.control:
          return 'Ctrl';
        case HotKeyModifier.shift:
          return 'Shift';
        case HotKeyModifier.alt:
          return 'Alt';
        case HotKeyModifier.meta:
          return 'Win';
        default:
          return m.name;
      }
    }).join(' + ');
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      setState(() => _liveModifiers = _currentModifiers());
      return KeyEventResult.handled;
    }

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }

    final isModifierKey = key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight ||
        key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight ||
        key == LogicalKeyboardKey.altLeft ||
        key == LogicalKeyboardKey.altRight ||
        key == LogicalKeyboardKey.metaLeft ||
        key == LogicalKeyboardKey.metaRight;

    if (isModifierKey) {
      setState(() {
        _error = null;
        _liveModifiers = _currentModifiers();
      });
      return KeyEventResult.handled;
    }

    if (!kAllowedHotKeyBodyKeys.contains(key)) {
      setState(() => _error = 'Use a letter, number, or F-key');
      return KeyEventResult.handled;
    }

    final modifiers = _currentModifiers();
    if (modifiers.isEmpty && !_kFunctionKeys.contains(key)) {
      setState(() => _error = 'Add Ctrl, Alt, Shift, or Win as well');
      return KeyEventResult.handled;
    }

    final label = [
      ..._modifierLabel(modifiers).split(' + ').where((s) => s.isNotEmpty),
      key.keyLabel,
    ].join(' + ');

    Navigator.of(context).pop(RecordedHotKey(key: key, modifiers: modifiers, label: label));
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AlienPalette.of(context);
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
                _liveModifiers.isEmpty
                    ? '…'
                    : '${_modifierLabel(_liveModifiers)} + …',
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
                Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
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
