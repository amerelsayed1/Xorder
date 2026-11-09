import 'package:flutter/material.dart';

/// The till's design language, on a handheld (waiter-app, WA1).
///
/// The values are the till's light palette (`packages/shared_module`
/// `lib/core/ui/tokens.dart`), copied rather than imported so this app does not
/// depend on the whole till; the till's `test/features/waiter_link/
/// waiter_theme_parity_test.dart` fails the moment the
/// two disagree. The two rules hold here too: **radius 0 everywhere, no
/// shadows** — elevation is a border.
abstract final class WaiterColors {
  static const accent = Color(0xFFF89A06);
  static const accentSoft = Color(0xFFFEF0D9);
  static const onAccent = Color(0xFF201E1D);
  static const page = Color(0xFFF8F5EF);
  static const surface = Color(0xFFFFFFFF);
  static const ink = Color(0xFF201E1D);
  static const body = Color(0xFF5A4D3D);
  static const muted = Color(0xFF8A7C68);
  static const line = Color(0xFFECE5D9);
  static const lineStrong = Color(0xFFDDD6C9);
  static const ok = Color(0xFF1F7A3D);
  static const okSoft = Color(0xFFE6F3EA);
  static const warn = Color(0xFFA9711A);
  static const warnSoft = Color(0xFFFBEEE0);
  static const danger = Color(0xFFC0392B);
  static const dangerSoft = Color(0xFFFDEEEC);
}

abstract final class WaiterSpace {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;

  /// The smallest thing a thumb is asked to hit.
  static const touch = 48.0;

  /// From here up the check sits beside the menu instead of under it.
  static const tabletMin = 700.0;
}

/// Numbers render in mono, as on the till.
const waiterMonoFamily = 'monospace';

ThemeData buildWaiterTheme() {
  const shape = RoundedRectangleBorder(borderRadius: BorderRadius.zero);
  const border = OutlineInputBorder(
    borderRadius: BorderRadius.zero,
    borderSide: BorderSide(color: WaiterColors.lineStrong),
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: WaiterColors.page,
    colorScheme: const ColorScheme.light(
      primary: WaiterColors.accent,
      onPrimary: WaiterColors.onAccent,
      surface: WaiterColors.surface,
      onSurface: WaiterColors.ink,
      error: WaiterColors.danger,
    ),
    splashFactory: NoSplash.splashFactory,
    appBarTheme: const AppBarTheme(
      backgroundColor: WaiterColors.surface,
      foregroundColor: WaiterColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      shape: Border(bottom: BorderSide(color: WaiterColors.line)),
    ),
    cardTheme: const CardThemeData(elevation: 0, shape: shape, margin: EdgeInsets.zero),
    dialogTheme: const DialogThemeData(shape: shape, elevation: 0),
    bottomSheetTheme: const BottomSheetThemeData(shape: shape, elevation: 0),
    snackBarTheme: const SnackBarThemeData(shape: shape, behavior: SnackBarBehavior.floating, elevation: 0),
    inputDecorationTheme: const InputDecorationTheme(
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: WaiterColors.ink, width: 2),
      ),
      filled: true,
      fillColor: WaiterColors.surface,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: shape,
        elevation: 0,
        minimumSize: const Size(WaiterSpace.touch, WaiterSpace.touch),
        backgroundColor: WaiterColors.accent,
        foregroundColor: WaiterColors.onAccent,
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: shape,
        minimumSize: const Size(WaiterSpace.touch, WaiterSpace.touch),
        foregroundColor: WaiterColors.ink,
        side: const BorderSide(color: WaiterColors.lineStrong),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: shape, foregroundColor: WaiterColors.ink),
    ),
    dividerTheme: const DividerThemeData(color: WaiterColors.line, space: 1, thickness: 1),
  );
}

TextStyle waiterMono({double size = 14, FontWeight weight = FontWeight.w600, Color color = WaiterColors.ink}) =>
    TextStyle(fontFamily: waiterMonoFamily, fontSize: size, fontWeight: weight, color: color);
