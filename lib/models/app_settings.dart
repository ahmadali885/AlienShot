import 'package:flutter/material.dart' show ThemeMode;

class AppSettings {
  AppSettings({
    required this.hotKeyPresetId,
    required this.autoCopyOnCapture,
    required this.autoUploadOnCapture,
    this.saveDirectory,
    this.customHotKeyKeyId,
    this.customHotKeyUsage,
    this.customHotKeyModifiers = const [],
    this.themeMode = ThemeMode.system,
    this.displayName = '',
    this.downscaleRetina = true,
  });

  /// Light, dark, or follow the Windows/macOS app theme.
  final ThemeMode themeMode;

  /// Shown on the profile page; empty means "Guest".
  final String displayName;

  /// macOS: export captures at point size instead of Retina pixel size.
  /// On by default, as in Lightshot.
  final bool downscaleRetina;

  final String hotKeyPresetId;
  final bool autoCopyOnCapture;
  final bool autoUploadOnCapture;
  final String? saveDirectory;

  /// Used when [hotKeyPresetId] == 'custom'. [customHotKeyUsage] is the
  /// recorded key's PhysicalKeyboardKey.usbHidUsage; [customHotKeyKeyId] is
  /// the LogicalKeyboardKey.keyId that older versions stored instead.
  /// [customHotKeyModifiers] holds HotKeyModifier names ('control', 'shift',
  /// 'alt', 'meta').
  final int? customHotKeyKeyId;
  final int? customHotKeyUsage;
  final List<String> customHotKeyModifiers;

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
    customHotKeyUsage: json['customHotKeyUsage'] as int?,
    customHotKeyModifiers:
        (json['customHotKeyModifiers'] as List<dynamic>?)?.cast<String>() ?? const [],
    themeMode: ThemeMode.values.asNameMap()[json['themeMode']] ?? ThemeMode.system,
    displayName: json['displayName'] as String? ?? '',
    downscaleRetina: json['downscaleRetina'] as bool? ?? true,
  );

  Map<String, dynamic> toJson() => {
    'themeMode': themeMode.name,
    'displayName': displayName,
    'downscaleRetina': downscaleRetina,
    'hotKeyPresetId': hotKeyPresetId,
    'autoCopyOnCapture': autoCopyOnCapture,
    'autoUploadOnCapture': autoUploadOnCapture,
    'saveDirectory': saveDirectory,
    'customHotKeyKeyId': customHotKeyKeyId,
    'customHotKeyUsage': customHotKeyUsage,
    'customHotKeyModifiers': customHotKeyModifiers,
  };

  AppSettings copyWith({
    String? hotKeyPresetId,
    bool? autoCopyOnCapture,
    bool? autoUploadOnCapture,
    String? saveDirectory,
    int? customHotKeyUsage,
    List<String>? customHotKeyModifiers,
    ThemeMode? themeMode,
    String? displayName,
    bool? downscaleRetina,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      displayName: displayName ?? this.displayName,
      downscaleRetina: downscaleRetina ?? this.downscaleRetina,
      hotKeyPresetId: hotKeyPresetId ?? this.hotKeyPresetId,
      autoCopyOnCapture: autoCopyOnCapture ?? this.autoCopyOnCapture,
      autoUploadOnCapture: autoUploadOnCapture ?? this.autoUploadOnCapture,
      saveDirectory: saveDirectory ?? this.saveDirectory,
      customHotKeyKeyId: customHotKeyKeyId,
      customHotKeyUsage: customHotKeyUsage ?? this.customHotKeyUsage,
      customHotKeyModifiers: customHotKeyModifiers ?? this.customHotKeyModifiers,
    );
  }
}
