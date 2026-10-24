import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import '../widgets/app_window_bar.dart';
import '../widgets/glass_container.dart';
import '../widgets/liquid_background.dart';
import '../widgets/pill_button.dart';

/// Keep in step with `version:` in pubspec.yaml and the installer script.
const String kAppVersion = '1.0.0';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final palette = AlienPalette.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppWindowBar(
        title: 'About',
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, size: 18, color: palette.textSoft),
          onPressed: onBack,
        ),
      ),
      body: LiquidBackground(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, AppWindowBar.height + 12, 28, 12),
            child: GlassContainer(
              // 28px overflowed the 460px window by 8px.
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/images/app_logo.png',
                    width: 64,
                    height: 64,
                    filterQuality: FilterQuality.medium,
                  ),
                  const SizedBox(height: 18),
                  const BrandWordmark(fontSize: 22),
                  const SizedBox(height: 6),
                  Text(
                    'Version $kAppVersion',
                    style: TextStyle(fontSize: 12, color: palette.textSoft),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Instant screenshots, quick annotations\nand shareable links.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, height: 1.4, color: palette.text),
                  ),
                  const SizedBox(height: 18),
                  Text('BY ALIENWAVE · TECH SOLUTIONS', style: palette.eyebrow),
                  const SizedBox(height: 14),
                  PillButton.ghost(
                    label: 'alienwavegroup.com',
                    icon: Icons.open_in_new_rounded,
                    compact: true,
                    onPressed: () => launchUrl(Uri.parse('https://alienwavegroup.com')),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '© 2026 AlienWave. All rights reserved.',
                    style: TextStyle(fontSize: 11, color: palette.textSoft),
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
