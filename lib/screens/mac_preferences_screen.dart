import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../models/hotkey_preset.dart';
import '../theme/app_theme.dart';
import '../widgets/app_window_bar.dart';
import '../widgets/glass_container.dart';
import '../widgets/hotkey_recorder_dialog.dart';
import '../widgets/liquid_background.dart';

/// macOS "Preferences…", modelled on Lightshot's: just the capture shortcut
/// and Retina downscaling. Changes apply as soon as they're made, the way Mac
/// preference windows work, so there's no Save button.
class MacPreferencesScreen extends StatelessWidget {
  const MacPreferencesScreen({
    super.key,
    required this.settings,
    required this.onChanged,
    required this.onBack,
  });

  final AppSettings settings;
  final ValueChanged<AppSettings> onChanged;
  final VoidCallback onBack;

  Future<void> _record(BuildContext context) async {
    final recorded = await showHotKeyRecorderDialog(context);
    if (recorded == null) return;
    onChanged(settings.copyWith(
      hotKeyPresetId: kCustomHotKeyPresetId,
      customHotKeyUsage: recorded.key.usbHidUsage,
      customHotKeyModifiers: recorded.modifiers.map((m) => m.name).toList(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final palette = AlienPalette.of(context);
    final hasHotKey = settings.hotKeyPresetId != kNoHotKeyPresetId;
    final labelStyle = TextStyle(fontSize: 13, color: palette.text);
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppWindowBar(
        title: 'Preferences',
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, size: 18, color: palette.textSoft),
          onPressed: onBack,
        ),
      ),
      body: LiquidBackground(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, AppWindowBar.height + 16, 20, 16),
          child: Align(
            alignment: Alignment.topCenter,
            child: GlassContainer(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 48,
                    child: Row(
                      children: [
                        Text('Capture screenshot', style: labelStyle),
                        const Spacer(),
                        _ShortcutField(
                          label: hasHotKey ? resolveHotKeyLabel(settings) : 'Click to record',
                          empty: !hasHotKey,
                          onTap: () => _record(context),
                        ),
                        IconButton(
                          tooltip: 'Clear shortcut',
                          iconSize: 18,
                          visualDensity: VisualDensity.compact,
                          icon: Icon(Icons.backspace_outlined, color: palette.textSoft),
                          onPressed: hasHotKey
                              ? () => onChanged(settings.copyWith(hotKeyPresetId: kNoHotKeyPresetId))
                              : null,
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  SizedBox(
                    height: 48,
                    child: Row(
                      children: [
                        Text('Downscale Retina screens', style: labelStyle),
                        const Spacer(),
                        Switch(
                          value: settings.downscaleRetina,
                          onChanged: (value) => onChanged(settings.copyWith(downscaleRetina: value)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The recorder "text field": shows the shortcut, click to record a new one.
class _ShortcutField extends StatelessWidget {
  const _ShortcutField({required this.label, required this.empty, required this.onTap});

  final String label;
  final bool empty;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AlienPalette.of(context);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minWidth: 132),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: palette.ghostFill,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: palette.ghostBorder),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppFonts.display,
              fontSize: 13,
              fontWeight: empty ? FontWeight.w500 : FontWeight.w600,
              letterSpacing: 0.3,
              color: empty ? palette.textSoft : palette.accentText,
            ),
          ),
        ),
      ),
    );
  }
}
