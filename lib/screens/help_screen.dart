import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/app_window_bar.dart';
import '../widgets/glass_container.dart';
import '../widgets/liquid_background.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key, required this.hotKeyLabel, required this.onBack});

  final String hotKeyLabel;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppWindowBar(
        title: 'Help',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, size: 18, color: AppColors.textSoft),
          onPressed: onBack,
        ),
      ),
      body: LiquidBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20 + AppWindowBar.height, 20, 20),
          children: [
            const _Section('CAPTURE'),
            _Card(children: [
              _Tip(Icons.keyboard_rounded, 'Press $hotKeyLabel, or left-click the tray icon'),
              const _Tip(Icons.highlight_alt_rounded, 'Drag to select an area — drag its handles to resize'),
              const _Tip(Icons.keyboard_return_rounded, 'Esc cancels at any time'),
            ]),
            const SizedBox(height: 20),
            const _Section('ANNOTATE'),
            const _Card(children: [
              _Tip(Icons.crop_square_rounded, 'Rectangle, arrow, pen, highlighter and text tools'),
              _Tip(Icons.palette_rounded, 'Pick a colour, or the rainbow swatch for any colour'),
              _Tip(Icons.undo_rounded, 'Undo removes the last mark'),
            ]),
            const SizedBox(height: 20),
            const _Section('SHARE'),
            const _Card(children: [
              _Tip(Icons.copy_rounded, 'Copy puts the image on the clipboard'),
              _Tip(Icons.save_alt_rounded, 'Save writes it to a PNG file'),
              _Tip(Icons.link_rounded, 'Upload creates a link and copies it'),
            ]),
            const SizedBox(height: 20),
            const _Section('TRAY ICON'),
            const _Card(children: [
              _Tip(Icons.mouse_rounded, 'Left-click takes a screenshot, right-click opens the menu'),
            ]),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(text, style: kEyebrowStyle),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(children: children),
    );
  }
}

class _Tip extends StatelessWidget {
  const _Tip(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Icon(icon, size: 17, color: AppColors.accent2),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 13, color: AppColors.text)),
          ),
        ],
      ),
    );
  }
}
