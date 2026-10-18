import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import 'app_settings.dart';

const String kCustomHotKeyPresetId = 'custom';

/// Curated list of hotkey combos known to be safe with hotkey_manager's
/// Windows implementation (plain modifier + letter/function keys only).
///
/// Do NOT add PrintScreen here — see README for why it crashes on Windows.
class HotKeyPreset {
  const HotKeyPreset({
    required this.id,
    required this.label,
    required this.key,
    required this.modifiers,
  });

  final String id;
  final String label;
  final LogicalKeyboardKey key;
  final List<HotKeyModifier> modifiers;

  HotKey toHotKey() {
    return HotKey(key: key, modifiers: modifiers, scope: HotKeyScope.system);
  }

  static const List<HotKeyPreset> all = [
    HotKeyPreset(
      id: 'ctrl_shift_s',
      label: 'Ctrl + Shift + S',
      key: LogicalKeyboardKey.keyS,
      modifiers: [HotKeyModifier.control, HotKeyModifier.shift],
    ),
    HotKeyPreset(
      id: 'ctrl_shift_a',
      label: 'Ctrl + Shift + A',
      key: LogicalKeyboardKey.keyA,
      modifiers: [HotKeyModifier.control, HotKeyModifier.shift],
    ),
    HotKeyPreset(
      id: 'ctrl_alt_s',
      label: 'Ctrl + Alt + S',
      key: LogicalKeyboardKey.keyS,
      modifiers: [HotKeyModifier.control, HotKeyModifier.alt],
    ),
    HotKeyPreset(
      id: 'f9',
      label: 'F9',
      key: LogicalKeyboardKey.f9,
      modifiers: [],
    ),
    HotKeyPreset(
      id: 'f10',
      label: 'F10',
      key: LogicalKeyboardKey.f10,
      modifiers: [],
    ),
  ];

  static HotKeyPreset byId(String id) {
    return all.firstWhere((p) => p.id == id, orElse: () => all.first);
  }
}

HotKeyModifier _modifierFromName(String name) {
  return HotKeyModifier.values.firstWhere(
    (m) => m.name == name,
    orElse: () => HotKeyModifier.control,
  );
}

/// Builds the active [HotKey] from settings, whether it's one of the
/// curated presets or a user-recorded custom combo.
HotKey resolveHotKey(AppSettings settings) {
  if (settings.hotKeyPresetId == kCustomHotKeyPresetId && settings.customHotKeyKeyId != null) {
    final key = LogicalKeyboardKey.findKeyByKeyId(settings.customHotKeyKeyId!) ??
        LogicalKeyboardKey.keyS;
    return HotKey(
      key: key,
      modifiers: settings.customHotKeyModifiers.map(_modifierFromName).toList(),
      scope: HotKeyScope.system,
    );
  }
  return HotKeyPreset.byId(settings.hotKeyPresetId).toHotKey();
}

String resolveHotKeyLabel(AppSettings settings) {
  if (settings.hotKeyPresetId == kCustomHotKeyPresetId) {
    return settings.customHotKeyLabel ?? 'Custom';
  }
  return HotKeyPreset.byId(settings.hotKeyPresetId).label;
}
