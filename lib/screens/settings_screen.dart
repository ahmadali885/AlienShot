import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../models/hotkey_preset.dart';
import '../theme/app_theme.dart';
import '../widgets/app_window_bar.dart';
import '../widgets/glass_container.dart';
import '../widgets/hotkey_recorder_dialog.dart';
import '../widgets/liquid_background.dart';
import '../widgets/pill_button.dart';
import '../widgets/recording_settings_panel.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.settings,
    required this.onSave,
    required this.onBack,
    required this.onPreviewTheme,
    this.initialTab,
  });

  final AppSettings settings;

  /// The tab to open on: 'recording' opens the Recording tab.
  final String? initialTab;
  final ValueChanged<AppSettings> onSave;

  /// Leaving without saving; the app also drops any theme preview.
  final VoidCallback onBack;

  /// Applies a theme immediately so it can be judged before saving.
  final ValueChanged<ThemeMode> onPreviewTheme;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

/// The pages of Settings, switched from the title bar.
enum _SettingsTab {
  general('Settings'),
  afterCapture('After capture'),
  saveFolder('Save folder'),
  recording('Recording');

  const _SettingsTab(this.label);
  final String label;
}

class _SettingsScreenState extends State<SettingsScreen> {
  late AppSettings _draft = widget.settings;
  late _SettingsTab _tab = widget.initialTab == 'recording' ? _SettingsTab.recording : _SettingsTab.general;

  Future<void> _pickSaveDirectory() async {
    final path = await getDirectoryPath();
    if (path == null) return;
    setState(() => _draft = _draft.copyWith(saveDirectory: path));
  }

  Future<void> _recordCustomHotKey() async {
    final recorded = await showHotKeyRecorderDialog(context);
    if (recorded == null) return;
    setState(() {
      _draft = _draft.copyWith(
        hotKeyPresetId: kCustomHotKeyPresetId,
        customHotKeyUsage: recorded.key.usbHidUsage,
        customHotKeyModifiers: recorded.modifiers.map((m) => m.name).toList(),
      );
    });
  }

  void _save() {
    widget.onSave(_draft);
    widget.onBack();
  }

  void _pickTheme(ThemeMode mode) {
    setState(() => _draft = _draft.copyWith(themeMode: mode));
    widget.onPreviewTheme(mode);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AlienPalette.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppWindowBar(
        title: 'Settings',
        titleWidget: _TabBar(value: _tab, onChanged: (tab) => setState(() => _tab = tab)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, size: 18, color: palette.textSoft),
          onPressed: widget.onBack,
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: PillButton(label: 'Save', onPressed: _save, compact: true),
          ),
        ],
      ),
      body: LiquidBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20 + AppWindowBar.height, 20, 20),
          children: switch (_tab) {
            _SettingsTab.general => _generalTab(palette),
            _SettingsTab.afterCapture => _afterCaptureTab(),
            _SettingsTab.saveFolder => _saveFolderTab(palette),
            _SettingsTab.recording => [
                RecordingSettingsPanel(
                  settings: _draft.recording,
                  onChanged: (recording) => setState(() => _draft = _draft.copyWith(recording: recording)),
                ),
              ],
          },
        ),
      ),
    );
  }

  List<Widget> _generalTab(AlienPalette palette) {
    return [
      const _SectionLabel('APPEARANCE', Icons.contrast_rounded),
      const SizedBox(height: 8),
      _ThemeSelector(value: _draft.themeMode, onChanged: _pickTheme),
      const SizedBox(height: 24),
      const _SectionLabel('CAPTURE HOTKEY', Icons.keyboard_outlined),
      const SizedBox(height: 8),
      GlassContainer(
        child: Column(
          children: [
            ...HotKeyPreset.all.map((preset) {
              return RadioListTile<String>(
                value: preset.id,
                groupValue: _draft.hotKeyPresetId,
                title: Text(preset.label, style: const TextStyle(fontSize: 13)),
                dense: true,
                onChanged: (value) {
                  setState(() => _draft = _draft.copyWith(hotKeyPresetId: value));
                },
              );
            }),
            const Divider(height: 1),
            RadioListTile<String>(
              value: kCustomHotKeyPresetId,
              groupValue: _draft.hotKeyPresetId,
              dense: true,
              title: Row(
                children: [
                  Text(
                    recordedHotKeyLabel(_draft) ?? 'Custom…',
                    style: const TextStyle(fontSize: 13),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _recordCustomHotKey,
                    style: TextButton.styleFrom(
                      foregroundColor: palette.accentText,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      minimumSize: Size.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: Text(
                      hasCustomHotKey(_draft) ? 'Change' : 'Record',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
              onChanged: !hasCustomHotKey(_draft)
                  ? null
                  : (value) {
                      setState(() => _draft = _draft.copyWith(hotKeyPresetId: value));
                    },
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _afterCaptureTab() {
    return [
      const _SectionLabel('AFTER CAPTURE', Icons.tune),
      const SizedBox(height: 8),
      GlassContainer(
        child: Column(
          children: [
            SwitchListTile(
              title: const Text('Auto-copy to clipboard', style: TextStyle(fontSize: 13)),
              dense: true,
              value: _draft.autoCopyOnCapture,
              onChanged: (value) {
                setState(() => _draft = _draft.copyWith(autoCopyOnCapture: value));
              },
            ),
            SwitchListTile(
              title: const Text('Auto-upload and copy link', style: TextStyle(fontSize: 13)),
              dense: true,
              value: _draft.autoUploadOnCapture,
              onChanged: (value) {
                setState(() => _draft = _draft.copyWith(autoUploadOnCapture: value));
              },
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _saveFolderTab(AlienPalette palette) {
    return [
      const _SectionLabel('DEFAULT SAVE FOLDER', Icons.folder_outlined),
      const SizedBox(height: 8),
      GlassContainer(
        child: ListTile(
          dense: true,
          title: Text(
            _draft.saveDirectory ?? 'Ask me every time',
            style: TextStyle(fontSize: 13, color: palette.text),
          ),
          trailing: Icon(Icons.chevron_right_rounded, size: 18, color: palette.textSoft),
          onTap: _pickSaveDirectory,
        ),
      ),
    ];
  }
}

/// "Settings · After capture · Save folder" in the title bar; the active page
/// sits on a filled pill like the site's nav group.
class _TabBar extends StatelessWidget {
  const _TabBar({required this.value, required this.onChanged});

  final _SettingsTab value;
  final ValueChanged<_SettingsTab> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AlienPalette.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final tab in _SettingsTab.values)
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: () => onChanged(tab),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                  decoration: ShapeDecoration(
                    shape: const StadiumBorder(),
                    color: tab == value ? palette.activeFill : Colors.transparent,
                  ),
                  child: Text(
                    tab.label,
                    style: TextStyle(
                      fontFamily: AppFonts.display,
                      fontSize: 13,
                      fontWeight: tab == value ? FontWeight.w600 : FontWeight.w500,
                      color: tab == value ? palette.text : palette.textSoft,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, this.icon);

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = AlienPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4),
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

/// System / Light / Dark as one segmented pill, styled like the site's nav
/// group with the active option filled by the accent gradient.
class _ThemeSelector extends StatelessWidget {
  const _ThemeSelector({required this.value, required this.onChanged});

  final ThemeMode value;
  final ValueChanged<ThemeMode> onChanged;

  static const _options = [
    (ThemeMode.system, 'System', Icons.desktop_windows_rounded),
    (ThemeMode.light, 'Light', Icons.light_mode_rounded),
    (ThemeMode.dark, 'Dark', Icons.dark_mode_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = AlienPalette.of(context);
    return GlassContainer(
      borderRadius: 100,
      padding: const EdgeInsets.all(5),
      child: Row(
        children: [
          for (final (mode, label, icon) in _options)
            Expanded(
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () => onChanged(mode),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: ShapeDecoration(
                      shape: const StadiumBorder(),
                      gradient: mode == value ? AppColors.accentGradient : null,
                      shadows: mode == value ? kAccentGlow : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          icon,
                          size: 15,
                          color: mode == value ? AppColors.onAccent : palette.textSoft,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: mode == value ? AppColors.onAccent : palette.text,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
