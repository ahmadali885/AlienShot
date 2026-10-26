import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import 'hotkey_preset.dart';

/// Screen recording options, laid out like OBS's Output / Video / Audio /
/// Hotkeys settings.
class RecordingSettings {
  const RecordingSettings({
    this.outputHeight = 0,
    this.fps = 30,
    this.codec = 'auto',
    this.rateControl = 'vbr',
    this.bitrateKbps = 0,
    this.quality = 70,
    this.keyframeSeconds = 2,
    this.cursor = true,
    this.countdown = 3,
    this.systemAudio = true,
    this.systemAudioDevice,
    this.microphone = false,
    this.microphoneDevice,
    this.folder,
    this.hotKeyStartsFullScreen = true,
    this.hotKeyShowsControls = false,
    this.overlayHotKey = defaultOverlayHotKey,
    this.recordHotKey = defaultRecordHotKey,
    this.pauseHotKey = defaultPauseHotKey,
  });

  /// 0 = the recorded area's own size; else 1080, 1440, 2160 or 4320 (the
  /// width follows the area's aspect ratio).
  final int outputHeight;
  final int fps;

  /// 'auto' (H.264, or H.265 above 4K), 'h264' or 'hevc'.
  final String codec;

  /// 'vbr', 'cbr' or 'quality'.
  final String rateControl;

  /// 0 = automatic, from resolution and frame rate.
  final int bitrateKbps;

  /// 1-100, used by the 'quality' rate control.
  final int quality;
  final int keyframeSeconds;
  final bool cursor;

  /// Seconds of 3-2-1 before recording starts; 0 = none.
  final int countdown;
  final bool systemAudio;

  /// Endpoint id; null = the Windows default device.
  final String? systemAudioDevice;
  final bool microphone;
  final String? microphoneDevice;

  /// Where videos go; null = Videos\AlienShot.
  final String? folder;

  /// The record hotkey records the whole screen straight away (like
  /// NVIDIA's); otherwise it asks for an area first.
  final bool hotKeyStartsFullScreen;

  /// A full-screen recording from the hotkey shows the controls and drawing
  /// tools; by default nothing is on screen (the tray icon turns red), which
  /// keeps the load on games as low as it gets.
  final bool hotKeyShowsControls;

  /// Null = no shortcut.
  final HotKeyBinding? overlayHotKey;
  final HotKeyBinding? recordHotKey;
  final HotKeyBinding? pauseHotKey;

  static const defaultOverlayHotKey = HotKeyBinding(PhysicalKeyboardKey.keyX, [HotKeyModifier.alt]);
  static const defaultRecordHotKey =
      HotKeyBinding(PhysicalKeyboardKey.keyR, [HotKeyModifier.control, HotKeyModifier.alt]);
  static const defaultPauseHotKey =
      HotKeyBinding(PhysicalKeyboardKey.keyP, [HotKeyModifier.control, HotKeyModifier.alt]);

  static const outputHeights = [0, 1080, 1440, 2160, 4320];
  static const frameRates = [24, 30, 60, 120];

  static String outputHeightLabel(int height) => switch (height) {
        0 => 'Original',
        2160 => '4K (2160p)',
        4320 => '8K (4320p)',
        _ => '${height}p',
      };

  factory RecordingSettings.fromJson(Map<String, dynamic> json) {
    HotKeyBinding? hotKey(String key, HotKeyBinding fallback) =>
        json.containsKey(key) ? HotKeyBinding.fromJson(json[key]) : fallback;
    return RecordingSettings(
      outputHeight: json['outputHeight'] as int? ?? 0,
      fps: json['fps'] as int? ?? 30,
      codec: json['codec'] as String? ?? 'auto',
      rateControl: json['rateControl'] as String? ?? 'vbr',
      bitrateKbps: json['bitrateKbps'] as int? ?? 0,
      quality: json['quality'] as int? ?? 70,
      keyframeSeconds: json['keyframeSeconds'] as int? ?? 2,
      cursor: json['cursor'] as bool? ?? true,
      countdown: json['countdown'] as int? ?? 3,
      systemAudio: json['systemAudio'] as bool? ?? true,
      systemAudioDevice: json['systemAudioDevice'] as String?,
      microphone: json['microphone'] as bool? ?? false,
      microphoneDevice: json['microphoneDevice'] as String?,
      folder: json['folder'] as String?,
      hotKeyStartsFullScreen: json['hotKeyStartsFullScreen'] as bool? ?? true,
      hotKeyShowsControls: json['hotKeyShowsControls'] as bool? ?? false,
      overlayHotKey: hotKey('overlayHotKey', defaultOverlayHotKey),
      recordHotKey: hotKey('recordHotKey', defaultRecordHotKey),
      pauseHotKey: hotKey('pauseHotKey', defaultPauseHotKey),
    );
  }

  Map<String, dynamic> toJson() => {
        'outputHeight': outputHeight,
        'fps': fps,
        'codec': codec,
        'rateControl': rateControl,
        'bitrateKbps': bitrateKbps,
        'quality': quality,
        'keyframeSeconds': keyframeSeconds,
        'cursor': cursor,
        'countdown': countdown,
        'systemAudio': systemAudio,
        'systemAudioDevice': systemAudioDevice,
        'microphone': microphone,
        'microphoneDevice': microphoneDevice,
        'folder': folder,
        'hotKeyStartsFullScreen': hotKeyStartsFullScreen,
        'hotKeyShowsControls': hotKeyShowsControls,
        // A cleared shortcut is stored as null, so it isn't reset to the
        // default on the next load.
        'overlayHotKey': overlayHotKey?.toJson(),
        'recordHotKey': recordHotKey?.toJson(),
        'pauseHotKey': pauseHotKey?.toJson(),
      };

  /// Nullable fields take a function so they can be set back to null.
  RecordingSettings copyWith({
    int? outputHeight,
    int? fps,
    String? codec,
    String? rateControl,
    int? bitrateKbps,
    int? quality,
    int? keyframeSeconds,
    bool? cursor,
    int? countdown,
    bool? systemAudio,
    String? Function()? systemAudioDevice,
    bool? microphone,
    String? Function()? microphoneDevice,
    String? Function()? folder,
    bool? hotKeyStartsFullScreen,
    bool? hotKeyShowsControls,
    HotKeyBinding? Function()? overlayHotKey,
    HotKeyBinding? Function()? recordHotKey,
    HotKeyBinding? Function()? pauseHotKey,
  }) {
    return RecordingSettings(
      outputHeight: outputHeight ?? this.outputHeight,
      fps: fps ?? this.fps,
      codec: codec ?? this.codec,
      rateControl: rateControl ?? this.rateControl,
      bitrateKbps: bitrateKbps ?? this.bitrateKbps,
      quality: quality ?? this.quality,
      keyframeSeconds: keyframeSeconds ?? this.keyframeSeconds,
      cursor: cursor ?? this.cursor,
      countdown: countdown ?? this.countdown,
      systemAudio: systemAudio ?? this.systemAudio,
      systemAudioDevice: systemAudioDevice != null ? systemAudioDevice() : this.systemAudioDevice,
      microphone: microphone ?? this.microphone,
      microphoneDevice: microphoneDevice != null ? microphoneDevice() : this.microphoneDevice,
      folder: folder != null ? folder() : this.folder,
      hotKeyStartsFullScreen: hotKeyStartsFullScreen ?? this.hotKeyStartsFullScreen,
      hotKeyShowsControls: hotKeyShowsControls ?? this.hotKeyShowsControls,
      overlayHotKey: overlayHotKey != null ? overlayHotKey() : this.overlayHotKey,
      recordHotKey: recordHotKey != null ? recordHotKey() : this.recordHotKey,
      pauseHotKey: pauseHotKey != null ? pauseHotKey() : this.pauseHotKey,
    );
  }
}
