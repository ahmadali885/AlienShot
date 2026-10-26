import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/recording_settings.dart';
import '../theme/app_theme.dart';
import '../widgets/app_window_bar.dart' show BrandWordmark;
import '../widgets/glass_container.dart';

/// The in-game style overlay (like NVIDIA's Alt+Z): big tiles for screenshot
/// and recording plus quick recording settings, over a dimmed, blurred
/// freeze of the screen. Esc, a click outside the panel or the overlay
/// hotkey closes it.
class QuickOverlayScreen extends StatefulWidget {
  const QuickOverlayScreen({
    super.key,
    required this.backdrop,
    required this.settings,
    required this.overlayHotKeyLabel,
    required this.recordHotKeyLabel,
    required this.onScreenshot,
    required this.onRecordFullScreen,
    required this.onRecordArea,
    required this.onOpenRecordings,
    required this.onOpenSettings,
    required this.onSettingsChanged,
    required this.onClose,
  });

  /// The screen as it was when the overlay opened.
  final ui.Image? backdrop;
  final RecordingSettings settings;
  final String? overlayHotKeyLabel;
  final String? recordHotKeyLabel;
  final VoidCallback onScreenshot;
  final VoidCallback onRecordFullScreen;
  final VoidCallback onRecordArea;
  final VoidCallback onOpenRecordings;
  final VoidCallback onOpenSettings;
  final ValueChanged<RecordingSettings> onSettingsChanged;
  final VoidCallback onClose;

  @override
  State<QuickOverlayScreen> createState() => _QuickOverlayScreenState();
}

class _QuickOverlayScreenState extends State<QuickOverlayScreen> {
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AlienPalette.of(context);
    final settings = widget.settings;
    final backdrop = widget.backdrop;
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (backdrop != null)
              ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18, tileMode: TileMode.clamp),
                child: RawImage(image: backdrop, fit: BoxFit.fill),
              ),
            // Clicking the dimmed screen closes the overlay.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onClose,
              child: ColoredBox(color: AppColors.ink.withValues(alpha: 0.55)),
            ),
            Align(
              alignment: const Alignment(0, -0.55),
              child: GlassContainer(
                borderRadius: 28,
                padding: const EdgeInsets.fromLTRB(28, 22, 28, 22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(7),
                          child: Image.asset('assets/images/app_logo.png', width: 28, height: 28),
                        ),
                        const SizedBox(width: 10),
                        const BrandWordmark(fontSize: 18),
                        const SizedBox(width: 18),
                        if (widget.overlayHotKeyLabel != null)
                          Text('${widget.overlayHotKeyLabel} or Esc to close', style: palette.eyebrow.copyWith(color: palette.textSoft)),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _Tile(icon: Icons.crop_rounded, label: 'Screenshot', onTap: widget.onScreenshot),
                        _Tile(
                          icon: Icons.fiber_manual_record_rounded,
                          iconColor: const Color(0xFFE5484D),
                          label: 'Record screen',
                          hint: widget.recordHotKeyLabel,
                          onTap: widget.onRecordFullScreen,
                        ),
                        _Tile(icon: Icons.highlight_alt_rounded, label: 'Record area', onTap: widget.onRecordArea),
                        _Tile(icon: Icons.video_library_rounded, label: 'Recordings', onTap: widget.onOpenRecordings),
                        _Tile(icon: Icons.settings_rounded, label: 'Settings', onTap: widget.onOpenSettings),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Container(height: 1, width: 5 * 128, color: palette.glassBorder),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _QuickMenu<int>(
                          icon: Icons.high_quality_rounded,
                          label: RecordingSettings.outputHeightLabel(settings.outputHeight),
                          tooltip: 'Resolution',
                          values: RecordingSettings.outputHeights,
                          name: RecordingSettings.outputHeightLabel,
                          onPick: (h) => widget.onSettingsChanged(settings.copyWith(outputHeight: h)),
                        ),
                        _QuickMenu<int>(
                          icon: Icons.speed_rounded,
                          label: '${settings.fps} fps',
                          tooltip: 'Frame rate',
                          values: RecordingSettings.frameRates,
                          name: (f) => '$f fps',
                          onPick: (f) => widget.onSettingsChanged(settings.copyWith(fps: f)),
                        ),
                        _QuickToggle(
                          on: Icons.volume_up_rounded,
                          off: Icons.volume_off_rounded,
                          label: 'Computer audio',
                          value: settings.systemAudio,
                          onChanged: (v) => widget.onSettingsChanged(settings.copyWith(systemAudio: v)),
                        ),
                        _QuickToggle(
                          on: Icons.mic_rounded,
                          off: Icons.mic_off_rounded,
                          label: 'Microphone',
                          value: settings.microphone,
                          onChanged: (v) => widget.onSettingsChanged(settings.copyWith(microphone: v)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A big square action, like the overlay tiles in GeForce Experience.
class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.label, required this.onTap, this.iconColor, this.hint});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final palette = AlienPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Ink(
            width: 116,
            height: 124,
            decoration: BoxDecoration(
              color: palette.ghostFill,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: palette.ghostBorder),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 34, color: iconColor ?? palette.accentText),
                const SizedBox(height: 10),
                Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: palette.text)),
                if (hint != null) ...[
                  const SizedBox(height: 3),
                  Text(hint!, style: TextStyle(fontSize: 10.5, color: palette.textSoft)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickMenu<T> extends StatelessWidget {
  const _QuickMenu({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.values,
    required this.name,
    required this.onPick,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final List<T> values;
  final String Function(T) name;
  final ValueChanged<T> onPick;

  @override
  Widget build(BuildContext context) {
    final palette = AlienPalette.of(context);
    return PopupMenuButton<T>(
      tooltip: tooltip,
      onSelected: onPick,
      itemBuilder: (_) => [for (final v in values) PopupMenuItem(value: v, child: Text(name(v)))],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: palette.accentText),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: palette.text)),
            Icon(Icons.arrow_drop_down_rounded, size: 18, color: palette.textSoft),
          ],
        ),
      ),
    );
  }
}

class _QuickToggle extends StatelessWidget {
  const _QuickToggle({required this.on, required this.off, required this.label, required this.value, required this.onChanged});

  final IconData on;
  final IconData off;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AlienPalette.of(context);
    return TextButton.icon(
      onPressed: () => onChanged(!value),
      style: TextButton.styleFrom(
        foregroundColor: value ? palette.text : palette.textSoft,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      icon: Icon(value ? on : off, size: 18, color: value ? palette.accentText : palette.textSoft),
      label: Text('$label: ${value ? 'on' : 'off'}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
    );
  }
}
