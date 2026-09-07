import 'package:flutter/material.dart';

import 'tokens.dart';

/// Material wiring for the POS design language, in one theme.
///
/// Most of this file exists to *undo* Material defaults. The design has border
/// radius 0 everywhere and no shadows at all, so every component that would
/// round a corner or drop a shadow is overridden here rather than being fought
/// widget by widget.
///
/// Called twice — once per [PosPalette] — and the result handed to
/// `MaterialApp.theme` and `.darkTheme`. The palette rides along on the
/// [PosPaletteExtension] so a widget can read a colour Material has no slot
/// for, which in this design is most of them.
ThemeData buildPosTheme([PosPalette palette = PosPalette.light]) {
  final scheme = ColorScheme(
    brightness: palette.brightness,
    primary: palette.accent,
    onPrimary: Colors.white,
    secondary: palette.inkWarm,
    onSecondary: palette.isDark ? palette.page : Colors.white,
    surface: palette.surface,
    onSurface: palette.ink,
    error: palette.danger,
    onError: Colors.white,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: palette.brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: palette.page,
    fontFamily: PosFonts.ui,
    fontFamilyFallback: PosFonts.uiFallback,
    splashFactory: NoSplash.splashFactory,
    // A POS is used at speed and often on a touch terminal; ripple animations
    // read as lag rather than feedback.
    highlightColor: Colors.transparent,
    hoverColor: palette.accentSoft,
    extensions: [PosPaletteExtension(palette)],
  );

  return base.copyWith(
    textTheme: _textTheme(base.textTheme, palette),
    dividerTheme: DividerThemeData(
      color: palette.line,
      thickness: 1,
      space: 1,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(borderRadius: PosBorders.radius),
      color: palette.surface,
    ),
    dialogTheme: DialogThemeData(
      elevation: 0,
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(borderRadius: PosBorders.radius),
      barrierColor: palette.scrim,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: palette.accent,
        foregroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: PosBorders.radius),
        minimumSize: const Size(0, PosSize.minTouchTarget),
        textStyle: const TextStyle(
          fontFamily: PosFonts.ui,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.inkWarm,
        side: BorderSide(color: palette.inkWarm),
        shape: const RoundedRectangleBorder(borderRadius: PosBorders.radius),
        minimumSize: const Size(0, PosSize.minTouchTarget),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: palette.inkWarm,
        shape: const RoundedRectangleBorder(borderRadius: PosBorders.radius),
        minimumSize: const Size(0, PosSize.minTouchTarget),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.page,
      border: OutlineInputBorder(
        borderRadius: PosBorders.radius,
        borderSide: BorderSide(color: palette.ink, width: 2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: PosBorders.radius,
        borderSide: BorderSide(color: palette.ink, width: 2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: PosBorders.radius,
        borderSide: BorderSide(color: palette.accent, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: PosSpace.md,
        vertical: PosSpace.md,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      // The snack bar is a shell surface wherever it appears, so it takes the
      // shell's own pairing rather than the body's.
      backgroundColor: palette.isDark ? palette.shellCard : palette.ink,
      contentTextStyle: TextStyle(
        fontFamily: PosFonts.ui,
        fontSize: 13.5,
        color: palette.isDark ? palette.shellText : PosPalette.dark.shellText,
      ),
      shape: const RoundedRectangleBorder(borderRadius: PosBorders.radius),
      behavior: SnackBarBehavior.floating,
      elevation: 0,
    ),
  );
}

TextTheme _textTheme(TextTheme base, PosPalette palette) => base.apply(
  bodyColor: palette.inkWarm,
  displayColor: palette.ink,
  fontFamily: PosFonts.ui,
  fontFamilyFallback: PosFonts.uiFallback,
);

/// Named text styles from the handoff's type scale.
///
/// Every number in this product is mono — prices, totals, codes, times, SKUs,
/// keypad digits — so [mono] is used far more than it would be in a normal app.
///
/// **[color] is required on every one of these.** It used to default to a fixed
/// token, which is exactly how a screen ended up with ink-on-ink the moment a
/// second theme existed: the default was invisible at the call site, so nobody
/// reading the widget could see that it had opted out of the palette. Requiring
/// it means a colour is always a decision somebody made against `context.pos`.
abstract final class PosText {
  static const _mono = PosFonts.mono;

  static TextStyle mono({
    required Color color,
    double size = 13,
    FontWeight weight = FontWeight.w400,
    double? height,
    double? letterSpacing,
  }) => TextStyle(
    fontFamily: _mono,
    fontFamilyFallback: PosFonts.monoFallback,
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: height,
    letterSpacing: letterSpacing,
  );

  static TextStyle ui({
    required Color color,
    double size = 14,
    FontWeight weight = FontWeight.w400,
    double? height,
  }) => TextStyle(
    fontFamily: PosFonts.ui,
    fontFamilyFallback: PosFonts.uiFallback,
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: height,
  );

  static TextStyle arabic({
    required Color color,
    double size = 12.5,
    FontWeight weight = FontWeight.w400,
  }) => TextStyle(
    fontFamily: PosFonts.arabic,
    fontSize: size,
    fontWeight: weight,
    color: color,
  );

  /// 10px / 600 mono, +0.10em tracking, uppercase. "CATEGORIES", "AMOUNT DUE".
  static TextStyle microLabel({required Color color}) =>
      mono(size: 10, weight: FontWeight.w600, color: color, letterSpacing: 1.0);

  /// The cart TOTAL — 32px / 600 / 1.0.
  static TextStyle displayTotal({required Color color}) =>
      mono(size: 32, weight: FontWeight.w600, color: color, height: 1);

  /// Payment amount due — 46px / 600 / 1.0.
  static TextStyle bigNumeric({required Color color}) =>
      mono(size: 46, weight: FontWeight.w600, color: color, height: 1);

  static TextStyle screenTitle({required Color color}) =>
      ui(size: 22, weight: FontWeight.w800, color: color);

  static TextStyle panelTitle({required Color color}) =>
      ui(size: 19, weight: FontWeight.w800, color: color);
}
