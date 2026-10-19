import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The two button styles from alienwavegroup.com: the gradient "Get in Touch"
/// pill ([PillButton.new]) and the translucent outlined one ([PillButton.ghost]).
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.compact = false,
  }) : ghost = false;

  const PillButton.ghost({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.compact = false,
  }) : ghost = true;

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool ghost;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = AlienPalette.of(context);
    final foreground = ghost ? palette.text : AppColors.onAccent;
    final padding = compact
        ? const EdgeInsets.symmetric(horizontal: 16, vertical: 8)
        : const EdgeInsets.symmetric(horizontal: 28, vertical: 15);

    final content = Padding(
      padding: padding,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: compact ? 15 : 18, color: foreground),
            const SizedBox(width: 8),
          ],
          Text(
            label,
            style: TextStyle(
              fontFamily: AppFonts.body,
              fontSize: compact ? 13 : 15,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
              color: foreground,
            ),
          ),
        ],
      ),
    );

    final button = Material(
      type: MaterialType.transparency,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onPressed, child: content),
    );

    if (ghost) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(100),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: palette.ghostFill,
              shape: StadiumBorder(side: BorderSide(color: palette.ghostBorder)),
            ),
            child: button,
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: const ShapeDecoration(
        gradient: AppColors.accentGradient,
        shape: StadiumBorder(),
        shadows: kAccentGlow,
      ),
      child: button,
    );
  }
}
