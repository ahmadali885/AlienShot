import 'package:flutter/material.dart' show ThemeMode;

class AppSettings {
  AppSettings({
    required this.hotKeyPresetId,
    required this.autoCopyOnCapture,
    required this.autoUploadOnCapture,
    this.saveDirectory,
    this.customHotKeyKeyId,
    this.customHotKeyModifiers = const [],
    this.customHotKeyLabel,
    this.themeMode = ThemeMode.system,
  });

  /// Light, dark, or follow the Windows/macOS app theme.
  final ThemeMode themeMode;

  final String hotKeyPresetId;
  final bool autoCopyOnCapture;
  final bool autoUploadOnCapture;
  final String? saveDirectory;

  /// Used when [hotKeyPresetId] == 'custom'. [customHotKeyKeyId] is a
  /// LogicalKeyboardKey.keyId; [customHotKeyModifiers] holds HotKeyModifier
  /// names ('control', 'shift', 'alt', 'meta').
  final int? customHotKeyKeyId;
  final List<String> customHotKeyModifiers;
  final String? customHotKeyLabel;

  factory AppSettings.defaults() => AppSettings(
    hotKeyPresetId: 'ctrl_shift_s',
    autoCopyOnCapture: true,
    autoUploadOnCapture: false,
  );

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
    hotKeyPresetId: json['hotKeyPresetId'] as String? ?? 'ctrl_shift_s',
    autoCopyOnCapture: json['autoCopyOnCapture'] as bool? ?? true,
    autoUploadOnCapture: json['autoUploadOnCapture'] as bool? ?? false,
    saveDirectory: json['saveDirectory'] as String?,
    customHotKeyKeyId: json['customHotKeyKeyId'] as int?,
    customHotKeyModifiers:
        (json['customHotKeyModifiers'] as List<dynamic>?)?.cast<String>() ?? const [],
    customHotKeyLabel: json['customHotKeyLabel'] as String?,
    themeMode: ThemeMode.values.asNameMap()[json['themeMode']] ?? ThemeMode.system,
  );

  Map<String, dynamic> toJson() => {
    'themeMode': themeMode.name,
    'hotKeyPresetId': hotKeyPresetId,
    'autoCopyOnCapture': autoCopyOnCapture,
    'autoUploadOnCapture': autoUploadOnCapture,
    'saveDirectory': saveDirectory,
    'customHotKeyKeyId': customHotKeyKeyId,
    'customHotKeyModifiers': customHotKeyModifiers,
    'customHotKeyLabel': customHotKeyLabel,
  };

  AppSettings copyWith({
    String? hotKeyPresetId,
    bool? autoCopyOnCapture,
    bool? autoUploadOnCapture,
    String? saveDirectory,
    int? customHotKeyKeyId,
    List<String>? customHotKeyModifiers,
    String? customHotKeyLabel,
    ThemeMode? themeMode,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      hotKeyPresetId: hotKeyPresetId ?? this.hotKeyPresetId,
      autoCopyOnCapture: autoCopyOnCapture ?? this.autoCopyOnCapture,
      autoUploadOnCapture: autoUploadOnCapture ?? this.autoUploadOnCapture,
      saveDirectory: saveDirectory ?? this.saveDirectory,
      customHotKeyKeyId: customHotKeyKeyId ?? this.customHotKeyKeyId,
      customHotKeyModifiers: customHotKeyModifiers ?? this.customHotKeyModifiers,
      customHotKeyLabel: customHotKeyLabel ?? this.customHotKeyLabel,
    );
  }
}
