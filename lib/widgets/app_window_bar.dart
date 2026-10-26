import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A slim branded header for the content area. Window controls
/// (minimize/close) are provided by the native OS title bar, so this widget
/// intentionally does not duplicate them or touch window state.
///
/// Frosted-glass: blurs whatever scrolls/renders behind it. Pair with
/// `Scaffold(extendBodyBehindAppBar: true)` so there's actually something
/// behind it to blur.
class AppWindowBar extends StatelessWidget implements PreferredSizeWidget {
  const AppWindowBar({
    super.key,
    required this.title,
    this.leading,
    this.actions = const [],
    this.brand = false,
    this.titleWidget,
  });

  final String title;

  /// Shown in place of the plain [title] text, e.g. a row of tabs.
  final Widget? titleWidget;
  final Widget? leading;
  final List<Widget> actions;

  /// Shows the two-tone product wordmark instead of [title] as plain text.
  final bool brand;

  static const double height = 48;

  @override
  Size get preferredSize => const Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final palette = AlienPalette.of(context);
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: palette.glassFill,
            border: Border(bottom: BorderSide(color: palette.glassBorder)),
          ),
          child: Row(
            children: [
              if (leading != null) leading!,
              SizedBox(width: leading == null ? 18 : 4),
              if (brand) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.asset(
                    'assets/images/app_logo.png',
                    width: 24,
                    height: 24,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
                const SizedBox(width: 9),
                const BrandWordmark(),
              ] else if (titleWidget != null)
                // Takes the free width and scrolls rather than pushing the
                // actions off the bar when the window is narrow.
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: titleWidget!,
                  ),
                )
              else
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: AppFonts.display,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: palette.text,
                  ),
                ),
              if (titleWidget == null || brand) const Spacer(),
              ...actions,
              const SizedBox(width: 6),
            ],
          ),
        ),
      ),
    );
  }
}

/// The "ALIENSHOT" logotype, set like the site's "ALIENWAVE" mark: the shared
/// "ALIEN" in the page's text colour, the product half in the accent teal.
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({super.key, this.fontSize = 15});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final palette = AlienPalette.of(context);
    return Text.rich(
      TextSpan(
        style: TextStyle(
          fontFamily: AppFonts.display,
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          letterSpacing: fontSize * 0.08,
          color: palette.isLight ? palette.text : Colors.white,
        ),
        children: [
          const TextSpan(text: 'ALIEN'),
          TextSpan(text: 'SHOT', style: TextStyle(color: palette.accentText)),
        ],
      ),
    );
  }
}
