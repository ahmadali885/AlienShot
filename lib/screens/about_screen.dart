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
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppWindowBar(
        title: 'About',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, size: 18, color: AppColors.textSoft),
          onPressed: onBack,
        ),
      ),
      body: LiquidBackground(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, AppWindowBar.height + 12, 28, 12),
            child: GlassContainer(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: kAccentGlow,
                    ),
                    child: Image.asset('assets/images/app_logo.png', filterQuality: FilterQuality.medium),
                  ),
                  const SizedBox(height: 18),
                  const BrandWordmark(fontSize: 22),
                  const SizedBox(height: 6),
                  const Text(
                    'Version $kAppVersion',
                    style: TextStyle(fontSize: 12, color: AppColors.textSoft),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Instant screenshots, quick annotations\nand shareable links.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, height: 1.4, color: AppColors.text),
                  ),
                  const SizedBox(height: 18),
                  const Text('BY ALIENWAVE · TECH SOLUTIONS', style: kEyebrowStyle),
                  const SizedBox(height: 14),
                  PillButton.ghost(
                    label: 'alienwavegroup.com',
                    icon: Icons.open_in_new_rounded,
                    compact: true,
                    onPressed: () => launchUrl(Uri.parse('https://alienwavegroup.com')),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    '© 2026 AlienWave. All rights reserved.',
                    style: TextStyle(fontSize: 11, color: AppColors.textSoft),
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
