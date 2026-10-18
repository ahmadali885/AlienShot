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
    required this.onOpenSettings,
    required this.onQuit,
    required this.onMinimize,
  });

  final String hotKeyLabel;

  /// False when another program owns the shortcut, so pressing it does nothing.
  final bool hotKeyActive;
  final VoidCallback onCapture;
  final VoidCallback onOpenSettings;
  final VoidCallback onQuit;
  final VoidCallback onMinimize;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppWindowBar(
        title: 'AlienShot',
        brand: true,
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.tune_rounded, size: 18, color: AppColors.textSoft),
            onPressed: onOpenSettings,
          ),
        ],
      ),
      body: LiquidBackground(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, AppWindowBar.height + 12, 28, 12),
            child: GlassContainer(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 30),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Same artwork as the app/taskbar icon: the AlienWave alien
                  // inside capture-frame corners.
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: kAccentGlow,
                    ),
                    child: Image.asset('assets/images/app_logo.png', filterQuality: FilterQuality.medium),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: AppColors.accent2,
                          shape: BoxShape.circle,
                          boxShadow: glow(AppColors.accent2, blur: 8, alpha: 0.8),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text('RUNNING IN BACKGROUND', style: kEyebrowStyle),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const _Headline(),
                  const SizedBox(height: 22),
                  PillButton(
                    icon: Icons.crop_rounded,
                    label: 'Capture region',
                    onPressed: onCapture,
                  ),
                  const SizedBox(height: 12),
                  _ShortcutChip(label: hotKeyLabel, active: hotKeyActive),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _QuietLink('Minimize to tray', onMinimize),
                      const Text('·', style: TextStyle(color: AppColors.textSoft)),
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
    const base = TextStyle(
      fontFamily: AppFonts.display,
      fontSize: 26,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.3,
      height: 1.15,
      color: Colors.white,
    );
    return Text.rich(
      TextSpan(
        style: base,
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

  static const Color _warning = Color(0xFFFFB454);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: ShapeDecoration(
        color: active ? AppColors.ghostFill : _warning.withValues(alpha: 0.08),
        shape: StadiumBorder(
          side: BorderSide(color: active ? AppColors.ghostBorder : _warning.withValues(alpha: 0.5)),
        ),
      ),
      child: Text.rich(
        TextSpan(
          style: const TextStyle(fontSize: 12, color: AppColors.textSoft),
          children: [
            if (!active)
              const WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(Icons.warning_amber_rounded, size: 14, color: _warning),
                ),
              ),
            TextSpan(text: active ? 'Shortcut  ' : 'In use by another app  '),
            TextSpan(
              text: label,
              style: TextStyle(
                fontFamily: AppFonts.display,
                color: active ? AppColors.accent2 : _warning,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
                decoration: active ? null : TextDecoration.lineThrough,
                decorationColor: _warning,
              ),
            ),
          ],
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
        foregroundColor: AppColors.textSoft,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size.zero,
        textStyle: const TextStyle(fontFamily: AppFonts.body, fontSize: 12, fontWeight: FontWeight.w500),
      ),
      child: Text(label),
    );
  }
}
