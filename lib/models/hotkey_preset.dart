import 'dart:io';

import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:uni_platform/uni_platform.dart';

import 'app_settings.dart';

const String kCustomHotKeyPresetId = 'custom';

/// The shortcut was cleared (macOS Preferences' ⌫): capture from the menu
/// bar only.
const String kNoHotKeyPresetId = 'none';

/// The ready-made shortcuts offered in Settings. Keys are physical keys, so
/// they stay put whatever the keyboard layout.
class HotKeyPreset {
  const HotKeyPreset({
    required this.id,
    required this.key,
    required this.modifiers,
  });

  final String id;
  final PhysicalKeyboardKey key;
  final List<HotKeyModifier> modifiers;

  String get label => formatHotKey(key, modifiers);

  HotKey toHotKey() {
    return HotKey(key: key, modifiers: modifiers, scope: HotKeyScope.system);
  }

  static const List<HotKeyPreset> all = [
    HotKeyPreset(
      id: 'ctrl_shift_s',
      key: PhysicalKeyboardKey.keyS,
      modifiers: [HotKeyModifier.control, HotKeyModifier.shift],
    ),
    HotKeyPreset(
      id: 'ctrl_shift_a',
      key: PhysicalKeyboardKey.keyA,
      modifiers: [HotKeyModifier.control, HotKeyModifier.shift],
    ),
    HotKeyPreset(
      id: 'ctrl_alt_s',
      key: PhysicalKeyboardKey.keyS,
      modifiers: [HotKeyModifier.control, HotKeyModifier.alt],
    ),
    HotKeyPreset(id: 'f9', key: PhysicalKeyboardKey.f9, modifiers: []),
    HotKeyPreset(id: 'f10', key: PhysicalKeyboardKey.f10, modifiers: []),
  ];

  static HotKeyPreset byId(String id) {
    return all.firstWhere((p) => p.id == id, orElse: () => all.first);
  }
}

/// Order modifiers are written in on each platform.
const _modifierOrder = [
  HotKeyModifier.control,
  HotKeyModifier.alt,
  HotKeyModifier.shift,
  HotKeyModifier.meta,
];

/// A modifier's name as the platform prints it: ⌃ ⌥ ⇧ ⌘ on macOS, words on
/// Windows (where "meta" is the Windows key).
String modifierLabel(HotKeyModifier m) {
  if (Platform.isMacOS) {
    return switch (m) {
      HotKeyModifier.control => '⌃',
      HotKeyModifier.alt => '⌥',
      HotKeyModifier.shift => '⇧',
      HotKeyModifier.meta => '⌘',
      _ => m.name,
    };
  }
  return switch (m) {
    HotKeyModifier.control => 'Ctrl',
    HotKeyModifier.alt => 'Alt',
    HotKeyModifier.shift => 'Shift',
    HotKeyModifier.meta => 'Win',
    _ => m.name,
  };
}

/// Modifiers in platform order, joined the platform's way ("⌃⇧" / "Ctrl + Shift").
String formatModifiers(Iterable<HotKeyModifier> modifiers) {
  final labels = [
    for (final m in _modifierOrder)
      if (modifiers.contains(m)) modifierLabel(m),
  ];
  return labels.join(Platform.isMacOS ? '' : ' + ');
}

/// Short names for keys whose Flutter label is long or blank. Each entry is
/// (Windows, macOS).
final Map<PhysicalKeyboardKey, (String, String)> _keyNames = {
  PhysicalKeyboardKey.arrowLeft: ('←', '←'),
  PhysicalKeyboardKey.arrowRight: ('→', '→'),
  PhysicalKeyboardKey.arrowUp: ('↑', '↑'),
  PhysicalKeyboardKey.arrowDown: ('↓', '↓'),
  PhysicalKeyboardKey.space: ('Space', 'Space'),
  PhysicalKeyboardKey.enter: ('Enter', '↩'),
  PhysicalKeyboardKey.numpadEnter: ('Num Enter', '⌤'),
  PhysicalKeyboardKey.backspace: ('Backspace', '⌫'),
  PhysicalKeyboardKey.delete: ('Delete', '⌦'),
  PhysicalKeyboardKey.tab: ('Tab', '⇥'),
  PhysicalKeyboardKey.escape: ('Esc', '⎋'),
  PhysicalKeyboardKey.printScreen: ('PrtSc', 'PrtSc'),
  PhysicalKeyboardKey.pause: ('Pause', 'Pause'),
  PhysicalKeyboardKey.scrollLock: ('ScrLk', 'ScrLk'),
  PhysicalKeyboardKey.insert: ('Insert', 'Insert'),
  PhysicalKeyboardKey.home: ('Home', '↖'),
  PhysicalKeyboardKey.end: ('End', '↘'),
  PhysicalKeyboardKey.pageUp: ('PgUp', '⇞'),
  PhysicalKeyboardKey.pageDown: ('PgDn', '⇟'),
  PhysicalKeyboardKey.numLock: ('NumLk', 'Clear'),
};

String keyLabel(PhysicalKeyboardKey key) {
  final named = _keyNames[key];
  if (named != null) return Platform.isMacOS ? named.$2 : named.$1;
  // uni_platform maps the physical key back to its US-layout logical key.
  final label = key.logicalKey?.keyLabel ?? '';
  if (label.isNotEmpty) return label.length == 1 ? label.toUpperCase() : label;
  return key.debugName ?? 'Key';
}

/// "⌃⇧S" on macOS, "Ctrl + Shift + S" on Windows.
String formatHotKey(PhysicalKeyboardKey key, List<HotKeyModifier> modifiers) {
  final mods = formatModifiers(modifiers);
  if (mods.isEmpty) return keyLabel(key);
  return Platform.isMacOS ? '$mods${keyLabel(key)}' : '$mods + ${keyLabel(key)}';
}

HotKeyModifier _modifierFromName(String name) {
  return HotKeyModifier.values.firstWhere(
    (m) => m.name == name,
    orElse: () => HotKeyModifier.control,
  );
}

PhysicalKeyboardKey? _customKey(AppSettings settings) {
  final usage = settings.customHotKeyUsage;
  if (usage != null) return PhysicalKeyboardKey.findKeyByCode(usage) ?? PhysicalKeyboardKey(usage);
  // Shortcuts recorded before physical keys were stored kept a logical key id.
  final keyId = settings.customHotKeyKeyId;
  if (keyId != null) return LogicalKeyboardKey.findKeyByKeyId(keyId)?.physicalKey;
  return null;
}

/// Whether a custom shortcut has been recorded at all.
bool hasCustomHotKey(AppSettings settings) => _customKey(settings) != null;

/// Builds the active [HotKey] from settings, whether it's one of the
/// curated presets or a user-recorded custom combo; null when cleared.
HotKey? resolveHotKey(AppSettings settings) {
  if (settings.hotKeyPresetId == kNoHotKeyPresetId) return null;
  final custom = _customKey(settings);
  if (settings.hotKeyPresetId == kCustomHotKeyPresetId && custom != null) {
    return HotKey(
      key: custom,
      modifiers: settings.customHotKeyModifiers.map(_modifierFromName).toList(),
      scope: HotKeyScope.system,
    );
  }
  return HotKeyPreset.byId(settings.hotKeyPresetId).toHotKey();
}

/// The recorded custom shortcut's label, or null if none was recorded.
String? recordedHotKeyLabel(AppSettings settings) {
  final custom = _customKey(settings);
  if (custom == null) return null;
  return formatHotKey(custom, settings.customHotKeyModifiers.map(_modifierFromName).toList());
}

String resolveHotKeyLabel(AppSettings settings) {
  if (settings.hotKeyPresetId == kNoHotKeyPresetId) return 'None';
  if (settings.hotKeyPresetId == kCustomHotKeyPresetId) {
    return recordedHotKeyLabel(settings) ?? HotKeyPreset.all.first.label;
  }
  return HotKeyPreset.byId(settings.hotKeyPresetId).label;
}

/// A shortcut stored by physical key and modifiers, for the recording
/// hotkeys (overlay, start/stop, pause).
class HotKeyBinding {
  const HotKeyBinding(this.key, this.modifiers);

  final PhysicalKeyboardKey key;
  final List<HotKeyModifier> modifiers;

  String get label => formatHotKey(key, modifiers);

  HotKey toHotKey() => HotKey(key: key, modifiers: modifiers, scope: HotKeyScope.system);

  Map<String, Object> toJson() => {
        'usage': key.usbHidUsage,
        'modifiers': [for (final m in modifiers) m.name],
      };

  static HotKeyBinding? fromJson(Object? json) {
    if (json is! Map) return null;
    final usage = json['usage'];
    if (usage is! int) return null;
    return HotKeyBinding(
      PhysicalKeyboardKey.findKeyByCode(usage) ?? PhysicalKeyboardKey(usage),
      [for (final name in (json['modifiers'] as List? ?? const [])) _modifierFromName(name as String)],
    );
  }

  @override
  bool operator ==(Object other) =>
      other is HotKeyBinding && other.key == key && other.modifiers.toSet().containsAll(modifiers) &&
      modifiers.toSet().containsAll(other.modifiers);

  @override
  int get hashCode => Object.hash(key, Object.hashAllUnordered(modifiers));
}
