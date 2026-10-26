import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/app_window_bar.dart';
import '../widgets/glass_container.dart';
import '../widgets/liquid_background.dart';
import '../widgets/pill_button.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.hotKeyLabel,
    this.hotKeyActive = true,
    required this.onCapture,
    this.onRecord,
    required this.onOpenSettings,
    required this.onOpenAbout,
    required this.onOpenProfile,
    required this.onQuit,
    required this.onMinimize,
  });

  final String hotKeyLabel;

  /// False when another program owns the shortcut, so pressing it does nothing.
  final bool hotKeyActive;
  final VoidCallback onCapture;

  /// Starts a screen recording; null where recording isn't available.
  final VoidCallback? onRecord;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenAbout;
  final VoidCallback onOpenProfile;
  final VoidCallback onQuit;
  final VoidCallback onMinimize;

  @override
  Widget build(BuildContext context) {
    final palette = AlienPalette.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      // Settings is reached from the gear beside the shortcut chip.
      appBar: AppWindowBar(
        title: 'AlienShot',
        brand: true,
        actions: [
          IconButton(
            tooltip: 'About',
            icon: Icon(Icons.info_outline_rounded, size: 20, color: palette.textSoft),
            onPressed: onOpenAbout,
          ),
          IconButton(
            tooltip: 'Profile',
            icon: Icon(Icons.account_circle_rounded, size: 22, color: palette.accentText),
            onPressed: onOpenProfile,
          ),
        ],
      ),
      body: LiquidBackground(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, AppWindowBar.height + 12, 28, 12),
            // Vertical padding is tight on purpose: the window is 460px tall
            // and at 30px the column overflowed its card by ~9px.
            child: GlassContainer(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Same artwork as the app/taskbar icon: the AlienWave alien
                  // inside capture-frame corners.
                  Image.asset(
                    'assets/images/app_logo.png',
                    width: 64,
                    height: 64,
                    filterQuality: FilterQuality.medium,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: palette.accentText,
                          shape: BoxShape.circle,
                          boxShadow: glow(palette.accentText, blur: 8, alpha: 0.8),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('RUNNING IN BACKGROUND', style: palette.eyebrow),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const _Headline(),
                  const SizedBox(height: 22),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PillButton(
                        icon: Icons.crop_rounded,
                        label: 'Capture region',
                        onPressed: onCapture,
                      ),
                      if (onRecord != null) ...[
                        const SizedBox(width: 10),
                        _RecordButton(onPressed: onRecord!),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ShortcutChip(label: hotKeyLabel, active: hotKeyActive),
                      const SizedBox(width: 8),
                      _RoundIconButton(
                        icon: Icons.settings_rounded,
                        tooltip: 'Change shortcut',
                        onPressed: onOpenSettings,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _QuietLink('Minimize to tray', onMinimize),
                      Text('·', style: TextStyle(color: palette.textSoft)),
                      _QuietLink('Quit AlienShot', onQuit),
                    ],
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

/// Mirrors the site's hero heading: bold Outfit with tight tracking, the
/// closing phrase painted with the accent gradient.
class _Headline extends StatelessWidget {
  const _Headline();

  @override
  Widget build(BuildContext context) {
    final palette = AlienPalette.of(context);
    return Text.rich(
      TextSpan(
        style: TextStyle(
          fontFamily: AppFonts.display,
          fontSize: 26,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          height: 1.15,
          color: palette.isLight ? palette.text : Colors.white,
        ),
        children: [
          const TextSpan(text: 'Ready to '),
          TextSpan(
            text: 'capture.',
            style: TextStyle(
              foreground: Paint()
                ..shader = AppColors.accentGradient.createShader(const Rect.fromLTWH(0, 0, 110, 30)),
            ),
          ),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}

class _ShortcutChip extends StatelessWidget {
  const _ShortcutChip({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final palette = AlienPalette.of(context);
    // Light amber is unreadable on paper; the light theme needs a deeper one.
    final warning = palette.isLight ? const Color(0xFFA35F00) : const Color(0xFFFFB454);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: ShapeDecoration(
        color: active ? palette.ghostFill : warning.withValues(alpha: 0.08),
        shape: StadiumBorder(
          side: BorderSide(color: active ? palette.ghostBorder : warning.withValues(alpha: 0.5)),
        ),
      ),
      child: Text.rich(
        TextSpan(
          style: TextStyle(fontSize: 12, color: palette.textSoft),
          children: [
            if (!active)
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(Icons.warning_amber_rounded, size: 14, color: warning),
                ),
              ),
            TextSpan(text: active ? 'Shortcut  ' : 'In use by another app  '),
            TextSpan(
              text: label,
              style: TextStyle(
                fontFamily: AppFonts.display,
                color: active ? palette.accentText : warning,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
                decoration: active ? null : TextDecoration.lineThrough,
                decorationColor: warning,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A circular ghost button sized to sit beside the shortcut chip.
class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.tooltip, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = AlienPalette.of(context);
    return Tooltip(
      message: tooltip,
      child: Material(
        type: MaterialType.transparency,
        shape: CircleBorder(side: BorderSide(color: palette.ghostBorder)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Ink(
            width: 32,
            height: 32,
            color: palette.ghostFill,
            child: Icon(icon, size: 16, color: palette.accentText),
          ),
        ),
      ),
    );
  }
}

class _QuietLink extends StatelessWidget {
  const _QuietLink(this.label, this.onPressed);

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: AlienPalette.of(context).textSoft,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size.zero,
        textStyle: const TextStyle(fontFamily: AppFonts.body, fontSize: 12, fontWeight: FontWeight.w500),
      ),
      child: Text(label),
    );
  }
}

/// A ghost pill with a red dot, beside "Capture region".
class _RecordButton extends StatelessWidget {
  const _RecordButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = AlienPalette.of(context);
    return Tooltip(
      message: 'Record screen',
      child: Material(
        type: MaterialType.transparency,
        shape: StadiumBorder(side: BorderSide(color: palette.ghostBorder)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Ink(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            color: palette.ghostFill,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: const BoxDecoration(color: Color(0xFFE5484D), shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text(
                  'Record',
                  style: TextStyle(
                    fontFamily: AppFonts.body,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: palette.text,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
