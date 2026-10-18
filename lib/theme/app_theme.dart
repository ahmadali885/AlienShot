import 'package:flutter/material.dart';

/// Design tokens mirrored from alienwavegroup.com's `:root` custom properties,
/// so AlienShot reads as part of the same product family.
class AppColors {
  AppColors._();

  static const ink = Color(0xFF04141A); // --ink (page background)
  static const ink2 = Color(0xFF071F27); // --ink-2
  static const deep = Color(0xFF004858); // --deep
  static const teal = Color(0xFF005568); // --teal
  static const accent = Color(0xFF1F97B0); // --accent
  static const accent2 = Color(0xFF3FBCC9); // --accent-2
  static const text = Color(0xFFE2F2F6); // --text-invert
  static const textSoft = Color(0xFF8FB3BC); // --text-invert-soft
  static const onAccent = Color(0xFF001122); // label colour on the gradient CTA

  static const surface = Color(0xFF08161C); // cookie bar / dialog fill
  static const glassFill = Color(0x9E06161C); // nav pill: rgba(6,22,28,.62)
  static const glassBorder = Color(0x1AFFFFFF); // rgba(255,255,255,.10)
  static const ghostFill = Color(0x0DFFFFFF); // ghost button: rgba(255,255,255,.05)
  static const ghostBorder = Color(0x42FFFFFF); // rgba(255,255,255,.26)
  static const activeFill = Color(0x21FFFFFF); // active nav item: rgba(255,255,255,.13)

  /// `--grad`: linear-gradient(120deg, accent, accent-2).
  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment(-0.87, -0.5),
    end: Alignment(0.87, 0.5),
    colors: [accent, accent2],
  );

  /// `--grad-deep`: linear-gradient(150deg, #004858, #006078 55%, #00323d).
  static const LinearGradient deepGradient = LinearGradient(
    begin: Alignment(-0.5, -0.87),
    end: Alignment(0.5, 0.87),
    colors: [deep, Color(0xFF006078), Color(0xFF00323D)],
    stops: [0.0, 0.55, 1.0],
  );

  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [ink, ink2],
  );
}

class AppFonts {
  AppFonts._();

  /// Headings, numbers and small-caps labels (Outfit on the site).
  static const display = 'Outfit';

  /// Body and control text (Urbanist on the site).
  static const body = 'Urbanist';
}

/// `--shadow`: the long, teal-tinted drop shadow the site puts under cards.
const List<BoxShadow> kCardShadow = [
  BoxShadow(color: Color(0x8000404E), blurRadius: 70, spreadRadius: -28, offset: Offset(0, 30)),
];

/// The glow under the site's gradient "Get in Touch" pill.
const List<BoxShadow> kAccentGlow = [
  BoxShadow(color: Color(0x991F97B0), blurRadius: 34, spreadRadius: -10, offset: Offset(0, 14)),
];

List<BoxShadow> glow(Color color, {double blur = 26, double alpha = 0.35, double spread = 0}) {
  return [
    BoxShadow(color: color.withValues(alpha: alpha), blurRadius: blur, spreadRadius: spread),
  ];
}

/// The site's small uppercase eyebrow labels ("ALIENWAVE · SINCE 2018").
const TextStyle kEyebrowStyle = TextStyle(
  fontFamily: AppFonts.display,
  fontSize: 11,
  fontWeight: FontWeight.w600,
  letterSpacing: 1.6,
  color: AppColors.accent2,
);

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: AppFonts.body,
    scaffoldBackgroundColor: AppColors.ink,
  );

  const pill = StadiumBorder();

  return base.copyWith(
    colorScheme: base.colorScheme.copyWith(
      primary: AppColors.accent,
      secondary: AppColors.accent2,
      surface: AppColors.surface,
      onPrimary: AppColors.onAccent,
    ),
    textTheme: base.textTheme
        .apply(bodyColor: AppColors.text, displayColor: AppColors.text)
        .copyWith(
          titleLarge: const TextStyle(fontFamily: AppFonts.display, fontWeight: FontWeight.w700),
          titleMedium: const TextStyle(fontFamily: AppFonts.display, fontWeight: FontWeight.w600),
        ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.onAccent,
        elevation: 0,
        shape: pill,
        textStyle: const TextStyle(fontFamily: AppFonts.body, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.accent2,
        shape: pill,
        textStyle: const TextStyle(fontFamily: AppFonts.body, fontWeight: FontWeight.w600),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0x24FFFFFF)),
      ),
      titleTextStyle: const TextStyle(
        fontFamily: AppFonts.display,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: AppColors.text,
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? AppColors.accent2 : AppColors.textSoft,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.accent.withValues(alpha: 0.4)
            : AppColors.ghostFill,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? Colors.transparent : AppColors.ghostBorder,
      ),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? AppColors.accent2 : AppColors.textSoft,
      ),
    ),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: AppColors.accent2,
      thumbColor: AppColors.accent2,
      overlayColor: AppColors.accent2.withValues(alpha: 0.15),
      inactiveTrackColor: AppColors.ghostFill,
    ),
    dividerTheme: const DividerThemeData(color: AppColors.glassBorder, space: 1),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.accent2),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: AppColors.glassBorder),
      ),
      textStyle: const TextStyle(fontFamily: AppFonts.body, fontSize: 12, color: AppColors.text),
    ),
  );
}
