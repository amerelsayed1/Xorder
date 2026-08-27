import 'package:flutter/material.dart';

import 'tokens.dart';

/// Material wiring for the POS design language.
///
/// Most of this file exists to *undo* Material defaults. The design has border
/// radius 0 everywhere and no shadows at all, so every component that would
/// round a corner or drop a shadow is overridden here rather than being fought
/// widget by widget.
ThemeData buildPosTheme() {
  const scheme = ColorScheme.light(
    primary: PosColors.accent,
    onPrimary: Colors.white,
    secondary: PosColors.inkWarm,
    onSecondary: Colors.white,
    surface: PosColors.surface,
    onSurface: PosColors.ink,
    error: PosColors.danger,
    onError: Colors.white,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: PosColors.page,
    fontFamily: PosFonts.ui,
    fontFamilyFallback: PosFonts.uiFallback,
    splashFactory: NoSplash.splashFactory,
    // A POS is used at speed and often on a touch terminal; ripple animations
    // read as lag rather than feedback.
    highlightColor: Colors.transparent,
    hoverColor: PosColors.accentSoft,
  );

  return base.copyWith(
    textTheme: _textTheme(base.textTheme),
    dividerTheme: const DividerThemeData(
      color: PosColors.line,
      thickness: 1,
      space: 1,
    ),
    cardTheme: const CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: PosBorders.radius),
      color: PosColors.surface,
    ),
    dialogTheme: const DialogThemeData(
      elevation: 0,
      backgroundColor: PosColors.surface,
      shape: RoundedRectangleBorder(borderRadius: PosBorders.radius),
      barrierColor: PosColors.scrim,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: PosColors.accent,
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
        foregroundColor: PosColors.inkWarm,
        side: const BorderSide(color: PosColors.inkWarm),
        shape: const RoundedRectangleBorder(borderRadius: PosBorders.radius),
        minimumSize: const Size(0, PosSize.minTouchTarget),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: PosColors.inkWarm,
        shape: const RoundedRectangleBorder(borderRadius: PosBorders.radius),
        minimumSize: const Size(0, PosSize.minTouchTarget),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: PosColors.page,
      border: OutlineInputBorder(
        borderRadius: PosBorders.radius,
        borderSide: BorderSide(color: PosColors.ink, width: 2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: PosBorders.radius,
        borderSide: BorderSide(color: PosColors.ink, width: 2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: PosBorders.radius,
        borderSide: BorderSide(color: PosColors.accent, width: 2),
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: PosSpace.md, vertical: PosSpace.md),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: PosColors.ink,
      contentTextStyle: TextStyle(
        fontFamily: PosFonts.ui,
        fontSize: 13.5,
        color: PosColors.shellText,
      ),
      shape: RoundedRectangleBorder(borderRadius: PosBorders.radius),
      behavior: SnackBarBehavior.floating,
      elevation: 0,
    ),
  );
}

TextTheme _textTheme(TextTheme base) => base.apply(
      bodyColor: PosColors.inkWarm,
      displayColor: PosColors.ink,
      fontFamily: PosFonts.ui,
      fontFamilyFallback: PosFonts.uiFallback,
    );

/// Named text styles from the handoff's type scale.
///
/// Every number in this product is mono — prices, totals, codes, times, SKUs,
/// keypad digits — so [mono] is used far more than it would be in a normal app.
abstract final class PosText {
  static const _mono = PosFonts.mono;

  static TextStyle mono({
    double size = 13,
    FontWeight weight = FontWeight.w400,
    Color color = PosColors.inkWarm,
    double? height,
    double? letterSpacing,
  }) =>
      TextStyle(
        fontFamily: _mono,
        fontFamilyFallback: PosFonts.monoFallback,
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
        letterSpacing: letterSpacing,
      );

  static TextStyle ui({
    double size = 14,
    FontWeight weight = FontWeight.w400,
    Color color = PosColors.inkWarm,
    double? height,
  }) =>
      TextStyle(
        fontFamily: PosFonts.ui,
        fontFamilyFallback: PosFonts.uiFallback,
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
      );

  static TextStyle arabic({
    double size = 12.5,
    FontWeight weight = FontWeight.w400,
    Color color = PosColors.muted,
  }) =>
      TextStyle(
        fontFamily: PosFonts.arabic,
        fontSize: size,
        fontWeight: weight,
        color: color,
      );

  /// 10px / 600 mono, +0.10em tracking, uppercase. "CATEGORIES", "AMOUNT DUE".
  static TextStyle microLabel({Color color = PosColors.muted}) =>
      mono(size: 10, weight: FontWeight.w600, color: color, letterSpacing: 1.0);

  /// The cart TOTAL — 32px / 600 / 1.0.
  static TextStyle displayTotal({Color color = PosColors.accent}) =>
      mono(size: 32, weight: FontWeight.w600, color: color, height: 1);

  /// Payment amount due — 46px / 600 / 1.0.
  static TextStyle bigNumeric({Color color = PosColors.ink}) =>
      mono(size: 46, weight: FontWeight.w600, color: color, height: 1);

  static TextStyle screenTitle({Color color = PosColors.ink}) =>
      ui(size: 22, weight: FontWeight.w800, color: color);

  static TextStyle panelTitle({Color color = PosColors.ink}) =>
      ui(size: 19, weight: FontWeight.w800, color: color);
}
