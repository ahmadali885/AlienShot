import 'dart:io';

import 'package:flutter/services.dart';

import '../models/recording_settings.dart';

/// What the recorder actually set up: the video's size and codec.
class RecordingInfo {
  const RecordingInfo(this.width, this.height, this.codec);

  final int width;
  final int height;
  final String codec;
}

class AudioDevice {
  const AudioDevice({required this.id, required this.name, required this.output, required this.isDefault});

  final String id;
  final String name;

  /// Speakers/headphones (recorded in loopback) rather than a microphone.
  final bool output;
  final bool isDefault;
}

/// Dart side of the native screen recorder (windows/runner/screen_recorder.cpp,
/// reached through windows/runner/recorder_channel.cpp).
///
/// Rects are logical pixels in the AlienShot window's coordinates; the
/// runner converts them to screen pixels.
class RecorderService {
  static const _channel = MethodChannel('alienshot/recorder');

  bool get isSupported => Platform.isWindows;

  /// Starts recording [region] to [path] (an .mp4) — or, with
  /// [monitorAtCursor], the whole monitor under the mouse, needing no window.
  /// Throws a [PlatformException] with a readable message if it can't start.
  Future<RecordingInfo> start({
    required Rect region,
    required String path,
    required RecordingSettings settings,
    bool monitorAtCursor = false,
  }) async {
    final info = await _channel.invokeMethod<Map<Object?, Object?>>('start', {
      'monitorAtCursor': monitorAtCursor,
      'left': region.left,
      'top': region.top,
      'width': region.width,
      'height': region.height,
      'path': path,
      'outputHeight': settings.outputHeight,
      'fps': settings.fps,
      'codec': settings.codec,
      'rateControl': settings.rateControl,
      'bitrateKbps': settings.bitrateKbps,
      'quality': settings.quality,
      'keyframeSeconds': settings.keyframeSeconds,
      'cursor': settings.cursor,
      'systemAudio': settings.systemAudio,
      'systemAudioDevice': settings.systemAudioDevice ?? '',
      'microphone': settings.microphone,
      'microphoneDevice': settings.microphoneDevice ?? '',
    });
    return RecordingInfo(
      info?['width'] as int? ?? 0,
      info?['height'] as int? ?? 0,
      info?['codec'] as String? ?? '',
    );
  }

  Future<void> pause() => _channel.invokeMethod('pause');
  Future<void> resume() => _channel.invokeMethod('resume');

  /// Finishes the file.
  Future<void> stop() => _channel.invokeMethod('stop');

  /// The annotation layer burned into the video: premultiplied RGBA, scaled
  /// by the runner to the recorded area. Null clears it.
  Future<void> setOverlay(Uint8List? rgba, int width, int height) {
    return _channel.invokeMethod('setOverlay', {
      'rgba': rgba,
      'width': width,
      'height': height,
    });
  }

  /// Lets clicks through the window everywhere except [rects] (the
  /// controls) — or nowhere, while [captureAll] (a drawing tool is active).
  Future<void> setClickThrough({required bool enabled, bool captureAll = false, List<Rect> rects = const []}) {
    return _channel.invokeMethod('setClickThrough', {
      'enabled': enabled,
      'captureAll': captureAll,
      'rects': [for (final r in rects) ...[r.left, r.top, r.width, r.height]],
    });
  }

  /// Active speakers and microphones, defaults first.
  Future<List<AudioDevice>> listAudioDevices() async {
    if (!isSupported) return const [];
    final list = await _channel.invokeMethod<List<Object?>>('listAudioDevices') ?? const [];
    final devices = [
      for (final item in list.cast<Map<Object?, Object?>>())
        AudioDevice(
          id: item['id'] as String? ?? '',
          name: item['name'] as String? ?? 'Unknown device',
          output: item['output'] as bool? ?? false,
          isDefault: item['default'] as bool? ?? false,
        ),
    ];
    devices.sort((a, b) => (b.isDefault ? 1 : 0) - (a.isDefault ? 1 : 0));
    return devices;
  }

  /// Videos\AlienShot unless the settings name another folder.
  String folderFor(RecordingSettings settings) {
    final home = Platform.environment['USERPROFILE'] ?? Directory.systemTemp.path;
    return settings.folder ?? '$home\\Videos\\AlienShot';
  }

  /// Where a new recording goes, e.g. "AlienShot 2026-10-26 14-58-07.mp4".
  Future<String> newRecordingPath(RecordingSettings settings) async {
    final folder = Directory(folderFor(settings));
    await folder.create(recursive: true);
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp = '${now.year}-${two(now.month)}-${two(now.day)} ${two(now.hour)}-${two(now.minute)}-${two(now.second)}';
    return '${folder.path}\\AlienShot $stamp.mp4';
  }
}

final recorderService = RecorderService();
