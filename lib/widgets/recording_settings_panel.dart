import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../models/hotkey_preset.dart';
import '../models/recording_settings.dart';
import '../services/recorder_service.dart';
import '../theme/app_theme.dart';
import 'glass_container.dart';
import 'hotkey_recorder_dialog.dart';

/// Settings › Recording, grouped the way OBS groups its output settings:
/// Output, Video, Audio and Hotkeys.
class RecordingSettingsPanel extends StatefulWidget {
  const RecordingSettingsPanel({super.key, required this.settings, required this.onChanged});

  final RecordingSettings settings;
  final ValueChanged<RecordingSettings> onChanged;

  @override
  State<RecordingSettingsPanel> createState() => _RecordingSettingsPanelState();
}

class _RecordingSettingsPanelState extends State<RecordingSettingsPanel> {
  List<AudioDevice> _devices = const [];

  static const _bitrates = [0, 2500, 5000, 8000, 12000, 20000, 35000, 50000, 80000];

  @override
  void initState() {
    super.initState();
    recorderService.listAudioDevices().then((devices) {
      if (mounted) setState(() => _devices = devices);
    }, onError: (Object _) {});
  }

  RecordingSettings get _s => widget.settings;
  void _set(RecordingSettings value) => widget.onChanged(value);

  Future<void> _pickFolder() async {
    final path = await getDirectoryPath(initialDirectory: recorderService.folderFor(_s));
    if (path != null) _set(_s.copyWith(folder: () => path));
  }

  Future<void> _recordHotKey(void Function(HotKeyBinding) apply) async {
    final recorded = await showHotKeyRecorderDialog(context);
    if (recorded != null) apply(HotKeyBinding(recorded.key, recorded.modifiers));
  }

  @override
  Widget build(BuildContext context) {
    final palette = AlienPalette.of(context);
    final outputs = [for (final d in _devices) if (d.output) d];
    final inputs = [for (final d in _devices) if (!d.output) d];
    String defaultName(List<AudioDevice> list) {
      final match = list.where((d) => d.isDefault);
      return match.isEmpty ? 'Default' : 'Default (${match.first.name})';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Label('OUTPUT', Icons.folder_outlined),
        _Card(children: [
          _Row(
            label: 'Recording folder',
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    recorderService.folderFor(_s),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: palette.textSoft),
                  ),
                ),
                TextButton(onPressed: _pickFolder, child: const Text('Change…')),
                TextButton(
                  onPressed: () async {
                    final folder = Directory(recorderService.folderFor(_s));
                    await folder.create(recursive: true);
                    await Process.start('explorer.exe', [folder.path]);
                  },
                  child: const Text('Open'),
                ),
              ],
            ),
          ),
          _Row(
            label: 'Format',
            child: Text('MP4 (H.264 / H.265 video, AAC audio)', style: TextStyle(fontSize: 13, color: palette.text)),
          ),
        ]),
        const SizedBox(height: 20),
        const _Label('VIDEO', Icons.movie_outlined),
        _Card(children: [
          _Row(
            label: 'Resolution',
            child: _Dropdown<int>(
              value: _s.outputHeight,
              items: {
                for (final h in RecordingSettings.outputHeights)
                  h: h == 0 ? 'Original (area size)' : RecordingSettings.outputHeightLabel(h),
              },
              onChanged: (h) => _set(_s.copyWith(outputHeight: h)),
            ),
          ),
          _Row(
            label: 'Frame rate',
            child: _Dropdown<int>(
              value: _s.fps,
              items: {for (final f in RecordingSettings.frameRates) f: '$f fps'},
              onChanged: (f) => _set(_s.copyWith(fps: f)),
            ),
          ),
          _Row(
            label: 'Encoder',
            child: _Dropdown<String>(
              value: _s.codec,
              items: const {
                'auto': 'Auto — H.264, or H.265 above 4K (recommended)',
                'h264': 'H.264 (plays everywhere, up to 4K)',
                'hevc': 'H.265 / HEVC (smaller files, up to 8K)',
              },
              onChanged: (c) => _set(_s.copyWith(codec: c)),
            ),
          ),
          _Row(
            label: 'Rate control',
            child: _Dropdown<String>(
              value: _s.rateControl,
              items: const {
                'vbr': 'VBR — variable bitrate',
                'cbr': 'CBR — constant bitrate',
                'quality': 'Quality — constant quality',
              },
              onChanged: (r) => _set(_s.copyWith(rateControl: r)),
            ),
          ),
          if (_s.rateControl == 'quality')
            _Row(
              label: 'Quality',
              child: Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: _s.quality.toDouble(),
                      min: 1,
                      max: 100,
                      divisions: 99,
                      onChanged: (q) => _set(_s.copyWith(quality: q.round())),
                    ),
                  ),
                  SizedBox(
                    width: 36,
                    child: Text('${_s.quality}', style: TextStyle(fontSize: 13, color: palette.text)),
                  ),
                ],
              ),
            )
          else
            _Row(
              label: 'Bitrate',
              child: _Dropdown<int>(
                value: _bitrates.contains(_s.bitrateKbps) ? _s.bitrateKbps : 0,
                items: {
                  for (final b in _bitrates) b: b == 0 ? 'Auto (from resolution and fps)' : '${b / 1000} Mbps',
                },
                onChanged: (b) => _set(_s.copyWith(bitrateKbps: b)),
              ),
            ),
          _Row(
            label: 'Keyframe interval',
            child: _Dropdown<int>(
              value: _s.keyframeSeconds,
              items: const {1: '1 s', 2: '2 s (recommended)', 5: '5 s'},
              onChanged: (k) => _set(_s.copyWith(keyframeSeconds: k)),
            ),
          ),
          _Row(
            label: 'Record the cursor',
            child: Align(
              alignment: Alignment.centerLeft,
              child: Switch(value: _s.cursor, onChanged: (v) => _set(_s.copyWith(cursor: v))),
            ),
          ),
          _Row(
            label: 'Countdown',
            child: _Dropdown<int>(
              value: _s.countdown,
              items: const {0: 'Off', 3: '3 seconds', 5: '5 seconds'},
              onChanged: (c) => _set(_s.copyWith(countdown: c)),
            ),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
          child: Text(
            '8K and H.265 depend on your graphics card; if it can\'t encode them, recording says so when it starts.',
            style: TextStyle(fontSize: 11.5, color: palette.textSoft),
          ),
        ),
        const SizedBox(height: 20),
        const _Label('AUDIO', Icons.graphic_eq_rounded),
        _Card(children: [
          _Row(
            label: 'Computer audio',
            child: Row(
              children: [
                Switch(value: _s.systemAudio, onChanged: (v) => _set(_s.copyWith(systemAudio: v))),
                const SizedBox(width: 8),
                Expanded(
                  child: _Dropdown<String?>(
                    value: outputs.any((d) => d.id == _s.systemAudioDevice) ? _s.systemAudioDevice : null,
                    items: {null: defaultName(outputs), for (final d in outputs) d.id: d.name},
                    onChanged: _s.systemAudio ? (id) => _set(_s.copyWith(systemAudioDevice: () => id)) : null,
                  ),
                ),
              ],
            ),
          ),
          _Row(
            label: 'Microphone',
            child: Row(
              children: [
                Switch(value: _s.microphone, onChanged: (v) => _set(_s.copyWith(microphone: v))),
                const SizedBox(width: 8),
                Expanded(
                  child: inputs.isEmpty
                      ? Text('No microphone found', style: TextStyle(fontSize: 13, color: palette.textSoft))
                      : _Dropdown<String?>(
                          value: inputs.any((d) => d.id == _s.microphoneDevice) ? _s.microphoneDevice : null,
                          items: {null: defaultName(inputs), for (final d in inputs) d.id: d.name},
                          onChanged: _s.microphone ? (id) => _set(_s.copyWith(microphoneDevice: () => id)) : null,
                        ),
                ),
              ],
            ),
          ),
        ]),
        const SizedBox(height: 20),
        const _Label('HOTKEYS', Icons.keyboard_outlined),
        _Card(children: [
          _HotKeyRow(
            label: 'Open overlay',
            binding: _s.overlayHotKey,
            onRecord: () => _recordHotKey((b) => _set(_s.copyWith(overlayHotKey: () => b))),
            onClear: () => _set(_s.copyWith(overlayHotKey: () => null)),
          ),
          _HotKeyRow(
            label: 'Start / stop recording',
            binding: _s.recordHotKey,
            onRecord: () => _recordHotKey((b) => _set(_s.copyWith(recordHotKey: () => b))),
            onClear: () => _set(_s.copyWith(recordHotKey: () => null)),
          ),
          _HotKeyRow(
            label: 'Pause / resume',
            binding: _s.pauseHotKey,
            onRecord: () => _recordHotKey((b) => _set(_s.copyWith(pauseHotKey: () => b))),
            onClear: () => _set(_s.copyWith(pauseHotKey: () => null)),
          ),
          _Row(
            label: 'Record hotkey starts',
            child: _Dropdown<bool>(
              value: _s.hotKeyStartsFullScreen,
              items: const {true: 'Full screen, right away', false: 'Area selection first'},
              onChanged: (v) => _set(_s.copyWith(hotKeyStartsFullScreen: v)),
            ),
          ),
          if (_s.hotKeyStartsFullScreen)
            _Row(
              label: 'While it records',
              child: _Dropdown<bool>(
                value: _s.hotKeyShowsControls,
                items: const {
                  false: 'Nothing on screen, lowest load (like NVIDIA)',
                  true: 'Show controls and drawing tools',
                },
                onChanged: (v) => _set(_s.copyWith(hotKeyShowsControls: v)),
              ),
            ),
        ]),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text, this.icon);

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = AlienPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 14, color: palette.accentText),
          const SizedBox(width: 8),
          Text(text, style: palette.eyebrow),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// A setting: its name on the left, the control on the right.
class _Row extends StatelessWidget {
  const _Row({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = AlienPalette.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(
        children: [
          SizedBox(
            width: 170,
            child: Text(label, style: TextStyle(fontSize: 13, color: palette.text)),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({required this.value, required this.items, required this.onChanged});

  final T value;
  final Map<T, String> items;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AlienPalette.of(context);
    return DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: value,
        isExpanded: true,
        isDense: true,
        borderRadius: BorderRadius.circular(12),
        dropdownColor: palette.surface,
        style: TextStyle(fontSize: 13, color: palette.text, fontFamily: AppFonts.body),
        items: [
          for (final entry in items.entries)
            DropdownMenuItem<T>(
              value: entry.key,
              child: Text(entry.value, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: onChanged == null ? null : (v) => onChanged!(v as T),
      ),
    );
  }
}

class _HotKeyRow extends StatelessWidget {
  const _HotKeyRow({required this.label, required this.binding, required this.onRecord, required this.onClear});

  final String label;
  final HotKeyBinding? binding;
  final VoidCallback onRecord;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final palette = AlienPalette.of(context);
    return _Row(
      label: label,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: ShapeDecoration(
              color: palette.ghostFill,
              shape: StadiumBorder(side: BorderSide(color: palette.ghostBorder)),
            ),
            child: Text(
              binding?.label ?? 'None',
              style: TextStyle(
                fontFamily: AppFonts.display,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: binding == null ? palette.textSoft : palette.accentText,
              ),
            ),
          ),
          const Spacer(),
          TextButton(onPressed: onRecord, child: Text(binding == null ? 'Set' : 'Change')),
          IconButton(
            tooltip: 'No shortcut',
            iconSize: 18,
            onPressed: binding == null ? null : onClear,
            icon: Icon(Icons.close_rounded, color: palette.textSoft),
          ),
        ],
      ),
    );
  }
}
