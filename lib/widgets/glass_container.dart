import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The glass surface used across alienwavegroup.com (its nav pill and cookie
/// bar): a translucent fill over `blur(14px) saturate(1.3)`, a hairline
/// border and the site's teal drop shadow — tinted per [AlienPalette].
class GlassContainer extends StatelessWidget {
  const GlassContainer({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius = 20,
    this.withGlow = false,
    this.blurSigma = 14,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;
  final bool withGlow;
  final double blurSigma;

  @override
  Widget build(BuildContext context) {
    final palette = AlienPalette.of(context);
    final radius = BorderRadius.circular(borderRadius);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          ...palette.cardShadow,
          if (withGlow)
            BoxShadow(
              color: AppColors.accent.withValues(alpha: palette.isLight ? 0.14 : 0.22),
              blurRadius: 32,
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.compose(
            outer: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
            inner: ColorFilter.matrix(_saturationMatrix(1.3)),
          ),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: palette.glassFill,
              borderRadius: radius,
              border: Border.all(color: palette.glassBorder),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Luminance-preserving saturation matrix, the equivalent of CSS `saturate()`.
List<double> _saturationMatrix(double s) {
  const r = 0.2126, g = 0.7152, b = 0.0722;
  final inv = 1 - s;
  return <double>[
    inv * r + s, inv * g, inv * b, 0, 0,
    inv * r, inv * g + s, inv * b, 0, 0,
    inv * r, inv * g, inv * b + s, 0, 0,
    0, 0, 0, 1, 0,
  ];
}
