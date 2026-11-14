import 'package:flutter/material.dart';

/// The till's design language, on a handheld (waiter-app, WA1; design pass
/// WA2 — `docs/pos/21-waiter-handheld-design.md`).
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

  // The shell family: the ground of the pairing and PIN screens, as the
  // till's start and lock screens are shell screens (design §3.1).
  static const shell = Color(0xFFEFE9DE);
  static const shellCard = Color(0xFFFFFFFF);
  static const shellLine = Color(0xFFDDD6C9);
  static const shellText = Color(0xFF201E1D);
  static const shellMuted = Color(0xFF6B6053);
}

abstract final class WaiterSpace {
  static const xs = 4.0;
  static const sm = 8.0;
  static const s10 = 10.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;

  /// The smallest thing a thumb is asked to hit.
  static const touch = 48.0;

  /// The one action a waiter is most likely to take next (design §1).
  static const cta = 56.0;

  /// The sticky bar under the menu: total · unsent · "Check (n)".
  static const checkBar = 64.0;

  /// A keypad key.
  static const key = 64.0;

  static const tableTile = 112.0;
  static const tableTileMaxExtent = 200.0;
  static const tableGutter = 10.0;
  static const productTile = 96.0;
  static const productTileMaxExtent = 200.0;
  static const productGutter = 8.0;
  static const sectionHeader = 32.0;

  /// From here up the check sits beside the menu instead of under it.
  static const tabletMin = 700.0;

  /// The check pane beside the menu on a tablet.
  static const checkPane = 360.0;
}

/// The till's faces, shipped by this app (`assets/fonts/`, declared in
/// pubspec.yaml): one family for every word in either language, one for
/// every number.
abstract final class WaiterFonts {
  static const ui = 'IBM Plex Sans Arabic';
  static const mono = 'IBM Plex Mono';
  static const uiFallback = <String>['Segoe UI', 'Helvetica Neue', 'Roboto'];
  static const monoFallback = <String>['Menlo', 'Consolas', 'monospace'];
}

/// Kept for the WA1 call sites; the family is [WaiterFonts.mono].
const waiterMonoFamily = WaiterFonts.mono;

/// The handheld's type scale (design §3.2). Every number goes through [mono].
abstract final class WaiterText {
  static TextStyle ui({
    double size = 14,
    FontWeight weight = FontWeight.w400,
    Color color = WaiterColors.ink,
    double? height,
    TextDecoration? decoration,
  }) => TextStyle(
    fontFamily: WaiterFonts.ui,
    fontFamilyFallback: WaiterFonts.uiFallback,
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: height,
    decoration: decoration,
    decorationColor: color,
  );

  static TextStyle mono({
    double size = 14,
    FontWeight weight = FontWeight.w600,
    Color color = WaiterColors.ink,
    double? height,
    double? letterSpacing,
    TextDecoration? decoration,
  }) => TextStyle(
    fontFamily: WaiterFonts.mono,
    fontFamilyFallback: WaiterFonts.monoFallback,
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: height,
    letterSpacing: letterSpacing,
    decoration: decoration,
    decorationColor: color,
  );

  /// Screen title in the app bar.
  static TextStyle title({Color color = WaiterColors.ink}) => ui(size: 18, weight: FontWeight.w700, color: color);

  /// A sheet's or card's heading.
  static TextStyle heading({Color color = WaiterColors.ink}) => ui(size: 20, weight: FontWeight.w700, color: color);

  /// The micro-label over a section: 11 / 600, uppercase, tracked. In the UI
  /// face, not mono — the headers are words ("Terrace", "بانتظار الإرسال") and
  /// the mono face has no Arabic; only the count beside it is mono.
  static TextStyle sectionLabel({Color color = WaiterColors.muted}) => TextStyle(
    fontFamily: WaiterFonts.ui,
    fontFamilyFallback: WaiterFonts.uiFallback,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: color,
    letterSpacing: 0.8,
  );

  /// A tile's or line's name.
  static TextStyle itemTitle({Color color = WaiterColors.ink, TextDecoration? decoration}) =>
      ui(size: 14.5, weight: FontWeight.w600, color: color, decoration: decoration);

  static TextStyle body({Color color = WaiterColors.body}) => ui(size: 14, color: color, height: 1.4);

  /// Modifiers, status words, areas.
  static TextStyle meta({Color color = WaiterColors.muted}) => ui(size: 12.5, color: color);

  static TextStyle badge({Color color = WaiterColors.ink}) => ui(size: 11, weight: FontWeight.w700, color: color);

  /// A price on a tile or line.
  static TextStyle price({Color color = WaiterColors.ink, TextDecoration? decoration}) =>
      mono(size: 14, weight: FontWeight.w600, color: color, decoration: decoration);

  /// The check's total.
  static TextStyle total({Color color = WaiterColors.ink}) => mono(size: 22, weight: FontWeight.w700, color: color);

  /// The total in the sticky check bar.
  static TextStyle barTotal({Color color = WaiterColors.ink}) => mono(size: 18, weight: FontWeight.w700, color: color);

  /// A keypad digit, a table label on a tile.
  static TextStyle keypad({Color color = WaiterColors.ink}) => mono(size: 24, weight: FontWeight.w600, color: color);

  static TextStyle tableLabel({Color color = WaiterColors.ink}) => mono(size: 20, weight: FontWeight.w800, color: color);
}

/// Numbers render in mono, as on the till. WA1 helper, kept; see [WaiterText.mono].
TextStyle waiterMono({double size = 14, FontWeight weight = FontWeight.w600, Color color = WaiterColors.ink}) =>
    WaiterText.mono(size: size, weight: weight, color: color);

ThemeData buildWaiterTheme() {
  const shape = RoundedRectangleBorder(borderRadius: BorderRadius.zero);
  const border = OutlineInputBorder(
    borderRadius: BorderRadius.zero,
    borderSide: BorderSide(color: WaiterColors.lineStrong),
  );
  final base = ThemeData(useMaterial3: true, brightness: Brightness.light);
  return base.copyWith(
    scaffoldBackgroundColor: WaiterColors.page,
    colorScheme: const ColorScheme.light(
      primary: WaiterColors.accent,
      onPrimary: WaiterColors.onAccent,
      surface: WaiterColors.surface,
      onSurface: WaiterColors.ink,
      error: WaiterColors.danger,
    ),
    textTheme: base.textTheme.apply(
      fontFamily: WaiterFonts.ui,
      fontFamilyFallback: WaiterFonts.uiFallback,
      bodyColor: WaiterColors.ink,
      displayColor: WaiterColors.ink,
    ),
    splashFactory: NoSplash.splashFactory,
    highlightColor: WaiterColors.accentSoft,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    appBarTheme: AppBarTheme(
      backgroundColor: WaiterColors.surface,
      foregroundColor: WaiterColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: WaiterText.title(),
      shape: const Border(bottom: BorderSide(color: WaiterColors.line)),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: WaiterColors.ink,
      unselectedLabelColor: WaiterColors.body,
      labelStyle: WaiterText.ui(size: 14, weight: FontWeight.w700),
      unselectedLabelStyle: WaiterText.ui(size: 14, weight: FontWeight.w600, color: WaiterColors.body),
      indicatorSize: TabBarIndicatorSize.tab,
      indicator: const UnderlineTabIndicator(borderSide: BorderSide(color: WaiterColors.accent, width: 2)),
      dividerColor: WaiterColors.line,
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    chipTheme: ChipThemeData(
      shape: shape,
      backgroundColor: WaiterColors.surface,
      selectedColor: WaiterColors.accentSoft,
      side: const BorderSide(color: WaiterColors.lineStrong),
      labelStyle: WaiterText.ui(size: 13.5, weight: FontWeight.w600),
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: WaiterSpace.md, vertical: WaiterSpace.sm),
    ),
    cardTheme: const CardThemeData(elevation: 0, shape: shape, margin: EdgeInsets.zero),
    dialogTheme: DialogThemeData(
      shape: shape,
      elevation: 0,
      backgroundColor: WaiterColors.surface,
      titleTextStyle: WaiterText.heading(),
      contentTextStyle: WaiterText.body(),
    ),
    bottomSheetTheme: const BottomSheetThemeData(shape: shape, elevation: 0, backgroundColor: WaiterColors.surface),
    snackBarTheme: SnackBarThemeData(
      shape: shape,
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      contentTextStyle: WaiterText.ui(size: 14, weight: FontWeight.w600, color: WaiterColors.surface),
    ),
    popupMenuTheme: PopupMenuThemeData(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: WaiterColors.lineStrong),
      ),
      color: WaiterColors.surface,
      elevation: 0,
      textStyle: WaiterText.ui(),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: WaiterColors.ink),
    inputDecorationTheme: InputDecorationTheme(
      border: border,
      enabledBorder: border,
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: WaiterColors.ink, width: 2),
      ),
      errorBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: WaiterColors.danger),
      ),
      filled: true,
      fillColor: WaiterColors.surface,
      labelStyle: WaiterText.ui(color: WaiterColors.body),
      hintStyle: WaiterText.ui(color: WaiterColors.muted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: shape,
        elevation: 0,
        minimumSize: const Size(WaiterSpace.touch, WaiterSpace.touch),
        backgroundColor: WaiterColors.accent,
        foregroundColor: WaiterColors.onAccent,
        disabledBackgroundColor: WaiterColors.line,
        disabledForegroundColor: WaiterColors.muted,
        textStyle: WaiterText.ui(size: 15, weight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: shape,
        minimumSize: const Size(WaiterSpace.touch, WaiterSpace.touch),
        foregroundColor: WaiterColors.ink,
        backgroundColor: WaiterColors.surface,
        side: const BorderSide(color: WaiterColors.lineStrong),
        textStyle: WaiterText.ui(size: 14, weight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: shape,
        foregroundColor: WaiterColors.ink,
        minimumSize: const Size(WaiterSpace.touch, WaiterSpace.touch),
        textStyle: WaiterText.ui(size: 14, weight: FontWeight.w600),
      ),
    ),
    dividerTheme: const DividerThemeData(color: WaiterColors.line, space: 1, thickness: 1),
  );
}
