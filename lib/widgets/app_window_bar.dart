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
  });

  final String title;
  final Widget? leading;
  final List<Widget> actions;

  /// Shows the two-tone product wordmark instead of [title] as plain text.
  final bool brand;

  static const double height = 48;

  @override
  Size get preferredSize => const Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          height: height,
          decoration: const BoxDecoration(
            color: AppColors.glassFill,
            border: Border(bottom: BorderSide(color: AppColors.glassBorder)),
          ),
          child: Row(
            children: [
              if (leading != null) leading!,
              SizedBox(width: leading == null ? 18 : 4),
              if (brand)
                const BrandWordmark()
              else
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: AppFonts.display,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
              const Spacer(),
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
/// "ALIEN" in white, the product half in the accent teal.
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({super.key, this.fontSize = 15});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        style: TextStyle(
          fontFamily: AppFonts.display,
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          letterSpacing: fontSize * 0.08,
          color: Colors.white,
        ),
        children: const [
          TextSpan(text: 'ALIEN'),
          TextSpan(text: 'SHOT', style: TextStyle(color: AppColors.accent2)),
        ],
      ),
    );
  }
}
