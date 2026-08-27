import 'package:flutter/material.dart';

/// Design tokens transcribed from `design_handoff_xorder_pos/README.md`.
///
/// The handoff states that every hex, size and dimension in it is authoritative.
/// This file is therefore a transcription, not an interpretation: nothing here
/// is derived, averaged or "close enough". If a value needs to change, it
/// changes in the handoff first.
///
/// See `docs/pos/07-design-system.md` for provenance of each token.
abstract final class PosColors {
  /// The only tenant-overridable colour (white-label accent).
  static const accent = Color(0xFFF89A06);
  static const accentPressed = Color(0xFFD9850A);
  static const accentSoft = Color(0xFFFEF0D9);

  static const page = Color(0xFFF8F5EF);
  static const surface = Color(0xFFFFFFFF);

  /// Dashboard body ink; also the border colour for outline buttons on light ground.
  static const inkWarm = Color(0xFF2A1E14);

  /// POS heading ink, 2px rules, dark buttons.
  static const ink = Color(0xFF201E1D);

  static const body = Color(0xFF5A4D3D);
  static const muted = Color(0xFF8A7C68);

  static const line = Color(0xFFECE5D9);
  static const lineStrong = Color(0xFFDDD6C9);

  // Dark shell — top bar, cart panel, start and lock screens.
  static const shell = Color(0xFF1C1712);
  static const shellCard = Color(0xFF2A2118);
  static const shellLine = Color(0xFF2E271E);
  static const shellRow = Color(0xFF241D15);
  static const shellText = Color(0xFFD9D2C6);
  static const shellMuted = Color(0xFF8A7F6C);

  static const ok = Color(0xFF1F7A3D);
  static const warn = Color(0xFFA9711A);
  static const danger = Color(0xFFC0392B);
  static const okSoft = Color(0xFFE6F3EA);
  static const warnSoft = Color(0xFFFBEEE0);
  static const dangerSoft = Color(0xFFFDEEEC);

  /// Modifier line text inside the dark cart panel.
  static const shellLineMeta = Color(0xFFA9A29A);

  /// Neutral chip — source badges (POS · PARKED), the CLR key.
  static const chipBg = Color(0xFFEEF0F2);
  static const chipText = Color(0xFF6B748C);

  static const scrim = Color(0x8C14120F); // rgba(20,18,15,.55)
  static const scrimHeavy = Color(0x9914120F); // .6 for receipt and lock

  // Offline / online pills on the dark shell.
  static const offlinePillBg = Color(0xFF3A2A12);
  static const offlinePillText = Color(0xFFF2C078);
  static const onlinePillBg = Color(0xFF16301F);
  static const onlinePillBorder = Color(0xFF2E5C3A);
  static const onlinePillText = Color(0xFF8FD6A5);

  /// The 4×36px bar at the top of a product tile, keyed by category slug.
  /// Unknown categories fall back to the accent rather than throwing — a new
  /// category on the server must never crash a till.
  static Color categoryBar(String? slug) => switch (slug) {
        'grills' => const Color(0xFFC0392B),
        'sandwiches' => const Color(0xFF1F7A3D),
        'pizza' => const Color(0xFFA9711A),
        'sides' => const Color(0xFF6B748C),
        'drinks' => const Color(0xFF3D4A7A),
        _ => accent, // desserts, combos, and anything new
      };
}

/// Font families.
///
/// The web repo vendors these as `.woff2`, which Flutter cannot load. Until
/// `.ttf`/`.otf` files are added to `assets/fonts/` and declared in
/// `pubspec.yaml`, these names resolve to a platform substitute. Layout metrics
/// are specified in logical pixels and do not depend on the substitution.
abstract final class PosFonts {
  static const ui = 'Archivo';

  /// Every number in the product renders in mono — prices, totals, codes,
  /// times, SKUs, keypad digits — plus all-caps micro-labels.
  static const mono = 'IBM Plex Mono';
  static const arabic = 'Tajawal';

  /// Fallbacks used until the real files land, so the app looks deliberate
  /// rather than broken on a machine without them.
  static const uiFallback = <String>['Helvetica Neue', 'Segoe UI', 'Roboto'];
  static const monoFallback = <String>['SF Mono', 'Consolas', 'Menlo', 'monospace'];
}

/// The spacing scale. Anything not on it is a mistake.
abstract final class PosSpace {
  static const xs = 4.0;
  static const sm = 8.0;
  static const s10 = 10.0;
  static const md = 12.0;
  static const s14 = 14.0;
  static const lg = 16.0;
  static const s18 = 18.0;
  static const xl = 20.0;
  static const s24 = 24.0;
  static const s28 = 28.0;
}

/// Fixed dimensions from the handoff. These are not suggestions — the layouts
/// are specified at these exact sizes.
abstract final class PosSize {
  static const minTouchTarget = 44.0;
  static const topBar = 56.0;
  static const categoryRail = 186.0;
  static const cartPanel = 378.0;
  static const searchRow = 48.0;
  static const productTile = 132.0;
  static const productTileMinWidth = 150.0;

  /// The Flutter build sheet specifies MaxCrossAxisExtent(190), which yields the
  /// same auto-fill behaviour as the CSS `minmax(150px, 1fr)`.
  static const productGridMaxExtent = 190.0;
  static const tableTile = 118.0;
  static const categoryRow = 46.0;
  static const primaryCta = 76.0;
  static const secondaryAction = 52.0;
  static const keypadKey = 42.0;
  static const pinKey = 62.0;
  static const productGridGutter = 10.0;
  static const tableGridGutter = 12.0;

  /// Breakpoints for the three shells (Flutter build sheet §2).
  static const wideShellMin = 1100.0;
  static const mediumShellMin = 700.0;
}

/// Borders. Elevation in this design is a border, never a shadow.
abstract final class PosBorders {
  static const hairline = BorderSide(color: PosColors.line);
  static const resting = BorderSide(color: PosColors.lineStrong);
  static const emphasis = BorderSide(color: PosColors.ink, width: 2);
  static const accent = BorderSide(color: PosColors.accent, width: 2);
  static const shell = BorderSide(color: PosColors.shellLine);

  /// Radius is 0 everywhere in this design. No exceptions.
  static const radius = BorderRadius.zero;
}
