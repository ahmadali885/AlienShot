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

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.settings,
    required this.onSave,
    required this.onBack,
  });

  final AppSettings settings;
  final ValueChanged<AppSettings> onSave;
  final VoidCallback onBack;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late AppSettings _draft = widget.settings;

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
        customHotKeyKeyId: recorded.key.keyId,
        customHotKeyModifiers: recorded.modifiers.map((m) => m.name).toList(),
        customHotKeyLabel: recorded.label,
      );
    });
  }

  void _save() {
    widget.onSave(_draft);
    widget.onBack();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppWindowBar(
        title: 'Settings',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, size: 18, color: AppColors.textSoft),
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
          children: [
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
                          _draft.hotKeyPresetId == kCustomHotKeyPresetId
                              ? (_draft.customHotKeyLabel ?? 'Custom')
                              : 'Custom…',
                          style: const TextStyle(fontSize: 13),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: _recordCustomHotKey,
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.accent2,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            minimumSize: Size.zero,
                            visualDensity: VisualDensity.compact,
                          ),
                          child: Text(
                            _draft.customHotKeyKeyId == null ? 'Record' : 'Change',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    onChanged: _draft.customHotKeyKeyId == null
                        ? null
                        : (value) {
                            setState(() => _draft = _draft.copyWith(hotKeyPresetId: value));
                          },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
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
            const SizedBox(height: 24),
            const _SectionLabel('DEFAULT SAVE FOLDER', Icons.folder_outlined),
            const SizedBox(height: 8),
            GlassContainer(
              child: ListTile(
                dense: true,
                title: Text(
                  _draft.saveDirectory ?? 'Ask me every time',
                  style: const TextStyle(fontSize: 13, color: AppColors.text),
                ),
                trailing: const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textSoft),
                onTap: _pickSaveDirectory,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, this.icon);

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.accent2),
          const SizedBox(width: 8),
          Text(text, style: kEyebrowStyle),
        ],
      ),
    );
  }
}
