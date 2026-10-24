import 'package:flutter/material.dart';

/// Brand colours mirrored from alienwavegroup.com's `:root` custom properties.
/// These stay the same in light and dark; everything that does change lives
/// in [AlienPalette].
class AppColors {
  AppColors._();

  static const ink = Color(0xFF04141A); // --ink
  static const ink2 = Color(0xFF071F27); // --ink-2
  static const deep = Color(0xFF004858); // --deep
  static const teal = Color(0xFF005568); // --teal
  static const accent = Color(0xFF1F97B0); // --accent
  static const accent2 = Color(0xFF3FBCC9); // --accent-2
  static const paper = Color(0xFFF3F8F9); // --paper
  static const onAccent = Color(0xFF001122); // label colour on the gradient CTA

  /// `--grad`: linear-gradient(120deg, accent, accent-2).
  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment(-0.87, -0.5),
    end: Alignment(0.87, 0.5),
    colors: [accent, accent2],
  );
}

class AppFonts {
  AppFonts._();

  /// Headings, numbers and small-caps labels (Outfit on the site).
  static const display = 'Outfit';

  /// Body and control text (Urbanist on the site).
  static const body = 'Urbanist';
}

/// The colours that differ between the light and dark themes. The dark set is
/// the site's ink hero; the light set is its paper sections ("Nothing worth
/// building is built alone").
@immutable
class AlienPalette extends ThemeExtension<AlienPalette> {
  const AlienPalette({
    required this.isLight,
    required this.background,
    required this.background2,
    required this.surface,
    required this.text,
    required this.textSoft,
    required this.accentText,
    required this.glassFill,
    required this.glassBorder,
    required this.ghostFill,
    required this.ghostBorder,
    required this.activeFill,
  });

  final bool isLight;
  final Color background;
  final Color background2;

  /// Dialogs and the capture hint — solid, unlike the glass panels.
  final Color surface;
  final Color text;
  final Color textSoft;

  /// Accent for small text and icons. `--accent-2` is too pale to read on
  /// paper, so the light theme uses a deeper teal there.
  final Color accentText;
  final Color glassFill;
  final Color glassBorder;
  final Color ghostFill;
  final Color ghostBorder;
  final Color activeFill;

  static const dark = AlienPalette(
    isLight: false,
    background: AppColors.ink,
    background2: AppColors.ink2,
    surface: Color(0xFF08161C), // cookie bar fill
    text: Color(0xFFE2F2F6), // --text-invert
    textSoft: Color(0xFF8FB3BC), // --text-invert-soft
    accentText: AppColors.accent2,
    glassFill: Color(0x9E06161C), // nav pill: rgba(6,22,28,.62)
    glassBorder: Color(0x1AFFFFFF), // rgba(255,255,255,.10)
    ghostFill: Color(0x0DFFFFFF), // ghost button: rgba(255,255,255,.05)
    ghostBorder: Color(0x42FFFFFF), // rgba(255,255,255,.26)
    activeFill: Color(0x21FFFFFF), // active nav item: rgba(255,255,255,.13)
  );

  static const light = AlienPalette(
    isLight: true,
    background: AppColors.paper,
    background2: Color(0xFFE6F1F3),
    surface: Colors.white,
    text: Color(0xFF0D2A31), // --text
    textSoft: Color(0xFF47606A), // --text-soft
    accentText: Color(0xFF0F7A90),
    // Lighter than the dark glass so the animated background reads through.
    glassFill: Color(0x8CFFFFFF),
    glassBorder: Color(0x1F0D2A31),
    ghostFill: Color(0x0A0D2A31),
    ghostBorder: Color(0x330D2A31),
    activeFill: Color(0x140D2A31),
  );

  static AlienPalette of(BuildContext context) => Theme.of(context).extension<AlienPalette>()!;

  /// The site's small uppercase eyebrow labels ("ALIENWAVE · SINCE 2018").
  TextStyle get eyebrow => TextStyle(
        fontFamily: AppFonts.display,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.6,
        color: accentText,
      );

  @override
  AlienPalette copyWith() => this;

  @override
  AlienPalette lerp(AlienPalette? other, double t) => t < 0.5 || other == null ? this : other;
}

/// The glow under the site's gradient "Get in Touch" pill.
const List<BoxShadow> kAccentGlow = [
  BoxShadow(color: Color(0x991F97B0), blurRadius: 34, spreadRadius: -10, offset: Offset(0, 14)),
];

List<BoxShadow> glow(Color color, {double blur = 26, double alpha = 0.35, double spread = 0}) {
  return [
    BoxShadow(color: color.withValues(alpha: alpha), blurRadius: blur, spreadRadius: spread),
  ];
}

ThemeData buildAppTheme(Brightness brightness) {
  final palette = brightness == Brightness.light ? AlienPalette.light : AlienPalette.dark;
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: AppFonts.body,
    scaffoldBackgroundColor: palette.background,
  );

  const pill = StadiumBorder();

  return base.copyWith(
    extensions: [palette],
    colorScheme: base.colorScheme.copyWith(
      primary: AppColors.accent,
      secondary: AppColors.accent2,
      surface: palette.surface,
      onSurface: palette.text,
      onPrimary: AppColors.onAccent,
    ),
    textTheme: base.textTheme
        .apply(bodyColor: palette.text, displayColor: palette.text)
        .copyWith(
          titleLarge: const TextStyle(fontFamily: AppFonts.display, fontWeight: FontWeight.w700),
          titleMedium: const TextStyle(fontFamily: AppFonts.display, fontWeight: FontWeight.w600),
        ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: palette.isLight ? Colors.white : AppColors.onAccent,
        elevation: 0,
        shape: pill,
        textStyle: const TextStyle(fontFamily: AppFonts.body, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: palette.accentText,
        shape: pill,
        textStyle: const TextStyle(fontFamily: AppFonts.body, fontWeight: FontWeight.w600),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: palette.glassBorder),
      ),
      titleTextStyle: TextStyle(
        fontFamily: AppFonts.display,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: palette.text,
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? AppColors.accent2 : palette.textSoft,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.accent.withValues(alpha: 0.4)
            : palette.ghostFill,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? Colors.transparent : palette.ghostBorder,
      ),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? palette.accentText : palette.textSoft,
      ),
    ),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: AppColors.accent2,
      thumbColor: AppColors.accent2,
      overlayColor: AppColors.accent2.withValues(alpha: 0.15),
      inactiveTrackColor: palette.ghostFill,
    ),
    dividerTheme: DividerThemeData(color: palette.glassBorder, space: 1),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: palette.accentText),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: palette.glassBorder),
      ),
      textStyle: TextStyle(fontFamily: AppFonts.body, fontSize: 12, color: palette.text),
    ),
  );
}
