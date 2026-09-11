import 'package:flutter/material.dart';

/// Design tokens transcribed from `design_handoff_xorder_pos/README.md`.
///
/// The handoff states that every hex, size and dimension in it is authoritative.
/// The [PosPalette.light] values are therefore a transcription, not an
/// interpretation: nothing there is derived, averaged or "close enough". If a
/// value needs to change, it changes in the handoff first.
///
/// [PosPalette.dark] is the exception, and is marked as such at each token that
/// has no counterpart in the handoff. The product now ships two themes rather
/// than one fixed palette, and the handoff only ever specified one.
///
/// See `docs/pos/07-design-system.md` for provenance of each token.

/// The whole colour system, in both themes.
///
/// **An enum rather than a class of statics.** The old shape — `PosColors.ink`
/// and the rest as `static const` — could not be anything but one palette,
/// because a compile-time constant cannot ask which theme is running. Every
/// screen read those constants directly, so the till had exactly one look no
/// matter what the operator or the machine asked for.
///
/// Two members, and every colour a field on them, means a screen holds a
/// *palette* and reads colours off it. Which palette it holds is decided once,
/// above the whole tree, by [PosPaletteExtension] on the [ThemeData].
///
/// Reach it with `context.pos`.
enum PosPalette {
  /// The handoff's palette, plus a light shell.
  ///
  /// The shell family — the top bar, cart, start and lock screens — was
  /// specified only as a dark band. Under a light theme it has to be a light
  /// one, so these are new: a warmer, deeper tone than [page] so the shell
  /// still reads as its own region rather than dissolving into the body.
  light(
    brightness: Brightness.light,
    accent: Color(0xFFF89A06),
    accentPressed: Color(0xFFD9850A),
    accentSoft: Color(0xFFFEF0D9),
    page: Color(0xFFF8F5EF),
    surface: Color(0xFFFFFFFF),
    inkWarm: Color(0xFF2A1E14),
    ink: Color(0xFF201E1D),
    // White, which is what every dark-button call site already passed.
    onInk: Color(0xFFFFFFFF),
    onOk: Color(0xFFFFFFFF),
    onAccent: Color(0xFF201E1D),
    body: Color(0xFF5A4D3D),
    muted: Color(0xFF8A7C68),
    line: Color(0xFFECE5D9),
    lineStrong: Color(0xFFDDD6C9),
    shell: Color(0xFFEFE9DE),
    shellCard: Color(0xFFFFFFFF),
    shellLine: Color(0xFFDDD6C9),
    shellRow: Color(0xFFF8F5EF),
    shellText: Color(0xFF201E1D),
    // Darker than the body's `muted`, because the light shell it sits on is
    // darker than the page: reusing #8A7C68 here measured 3.37:1, which is
    // under the 4.5 every other caption in this palette clears.
    shellMuted: Color(0xFF6B6053),
    shellLineMeta: Color(0xFF6F6559),
    ok: Color(0xFF1F7A3D),
    warn: Color(0xFFA9711A),
    danger: Color(0xFFC0392B),
    dangerPressed: Color(0xFFA5301F),
    okSoft: Color(0xFFE6F3EA),
    warnSoft: Color(0xFFFBEEE0),
    dangerSoft: Color(0xFFFDEEEC),
    chipBg: Color(0xFFEEF0F2),
    chipText: Color(0xFF6B748C),
    scrim: Color(0x8C14120F),
    scrimHeavy: Color(0x9914120F),
    offlinePillBg: Color(0xFFFBEEE0),
    offlinePillText: Color(0xFF8A5A10),
    onlinePillBg: Color(0xFFE6F3EA),
    onlinePillBorder: Color(0xFF9ED0B0),
    onlinePillText: Color(0xFF1B6A35),
    shellDangerBg: Color(0xFFFDEEEC),
    shellDangerText: Color(0xFFC0392B),
    ctaDisabled: Color(0xFF6B6053),
  ),

  /// The body flipped dark, and the shell taken deeper than it.
  ///
  /// None of this is in the handoff. Two rules shaped it:
  ///
  /// * the shell must stay DARKER than the body it borders, because that
  ///   contrast is the whole reason the shell is a separate region — a dark
  ///   theme that made them the same tone would erase the layout;
  /// * the status colours are lifted, not reused. `ok`, `warn` and `danger` at
  ///   their light-theme values are close to unreadable on a dark ground, and
  ///   these three are the ones a cashier reads under time pressure.
  dark(
    brightness: Brightness.dark,
    accent: Color(0xFFF89A06),
    accentPressed: Color(0xFFD9850A),
    // Lighter and more chromatic than [warnSoft], deliberately and by rule.
    // These two were the same brown (#3A2A12) until the patterns handoff put
    // them adjacent — a warn limit strip directly above a selected reason row,
    // a dirty bar under a platform note — and two grounds that mean *selected*
    // and *caution* cannot be the same colour. Selection goes toward the
    // accent; caution goes toward the page. Revision 2 of the handoff states
    // the rule: they must never be within one visible step of each other.
    accentSoft: Color(0xFF4A3110),
    page: Color(0xFF14110E),
    surface: Color(0xFF1C1712),
    inkWarm: Color(0xFFEAE3D7),
    ink: Color(0xFFF2EDE4),
    // The page, so a cream fill carries the darkest thing in the palette.
    onInk: Color(0xFF14110E),
    onOk: Color(0xFF14110E),
    onAccent: Color(0xFF14110E),
    body: Color(0xFFC6BCAD),
    muted: Color(0xFF978B79),
    line: Color(0xFF2A231B),
    lineStrong: Color(0xFF3A3229),
    shell: Color(0xFF0E0C0A),
    shellCard: Color(0xFF1F1913),
    shellLine: Color(0xFF2E271E),
    shellRow: Color(0xFF171310),
    shellText: Color(0xFFD9D2C6),
    shellMuted: Color(0xFF8A7F6C),
    shellLineMeta: Color(0xFFA9A29A),
    ok: Color(0xFF4FB477),
    warn: Color(0xFFD9A03F),
    danger: Color(0xFFE4695C),
    dangerPressed: Color(0xFFC9564A),
    okSoft: Color(0xFF16301F),
    // Darker and near-neutral — see [accentSoft] above for why these parted.
    warnSoft: Color(0xFF2A2418),
    dangerSoft: Color(0xFF3A1C18),
    chipBg: Color(0xFF262B33),
    chipText: Color(0xFFA8B0C2),
    scrim: Color(0xB3000000),
    scrimHeavy: Color(0xCC000000),
    offlinePillBg: Color(0xFF3A2A12),
    offlinePillText: Color(0xFFF2C078),
    onlinePillBg: Color(0xFF16301F),
    onlinePillBorder: Color(0xFF2E5C3A),
    onlinePillText: Color(0xFF8FD6A5),
    shellDangerBg: Color(0xFF3A1512),
    shellDangerText: Color(0xFFF2A79E),
    ctaDisabled: Color(0xFF4A3F31),
  );

  const PosPalette({
    required this.brightness,
    required this.accent,
    required this.accentPressed,
    required this.accentSoft,
    required this.page,
    required this.surface,
    required this.inkWarm,
    required this.ink,
    required this.onInk,
    required this.onOk,
    required this.onAccent,
    required this.body,
    required this.muted,
    required this.line,
    required this.lineStrong,
    required this.shell,
    required this.shellCard,
    required this.shellLine,
    required this.shellRow,
    required this.shellText,
    required this.shellMuted,
    required this.shellLineMeta,
    required this.ok,
    required this.warn,
    required this.danger,
    required this.dangerPressed,
    required this.okSoft,
    required this.warnSoft,
    required this.dangerSoft,
    required this.chipBg,
    required this.chipText,
    required this.scrim,
    required this.scrimHeavy,
    required this.offlinePillBg,
    required this.offlinePillText,
    required this.onlinePillBg,
    required this.onlinePillBorder,
    required this.onlinePillText,
    required this.shellDangerBg,
    required this.shellDangerText,
    required this.ctaDisabled,
  });

  /// Which theme this is. Handed to Material so its own defaults agree.
  final Brightness brightness;

  /// The only tenant-overridable colour (white-label accent), and so the only
  /// one that is deliberately identical in both themes.
  final Color accent;
  final Color accentPressed;
  final Color accentSoft;

  final Color page;
  final Color surface;

  /// Dashboard body ink; also the border colour for outline buttons.
  final Color inkWarm;

  /// POS heading ink, 2px rules, dark buttons.
  final Color ink;

  /// What goes ON an [accent] fill, where the text is small enough to need it.
  ///
  /// [accent] is the one colour that does NOT move between the palettes, so
  /// this does not either. It is dark because white on #F89A06 measures 2.2:1,
  /// which the handoff accepts on a large-format CTA and which nothing should
  /// accept on a 16px initial in an avatar the size of a thumbnail.
  final Color onAccent;

  /// What goes ON an [ok] fill — the label of a confirm button.
  ///
  /// Same trap as [onInk], one colour along. The dark palette LIFTS its status
  /// colours so they can be read *on* a dark ground, which makes `ok` a pale
  /// green there — and a pale green filled behind white text is the payment
  /// screen's Take payment button at 2.1:1, the largest and most-pressed
  /// control in the product.
  final Color onOk;

  /// What goes ON an [ink] fill — the label of a primary button.
  ///
  /// It exists because "dark buttons" stops being true in the dark theme, where
  /// [ink] is a near-white cream. Every such button was written as an ink fill
  /// beneath `Colors.white`, which is right in the light palette and, in the
  /// dark one, white on cream at 1.06:1 — the primary action on a screen
  /// rendering as a pale blank slab that reads as disabled. A literal cannot
  /// follow the theme; a token can, and the contrast table in `theme_test.dart`
  /// holds this pair to AA in both.
  final Color onInk;

  final Color body;
  final Color muted;

  final Color line;
  final Color lineStrong;

  // The shell — top bar, cart panel, start and lock screens.
  final Color shell;
  final Color shellCard;
  final Color shellLine;
  final Color shellRow;
  final Color shellText;
  final Color shellMuted;

  /// Modifier line text inside the cart panel.
  final Color shellLineMeta;

  final Color ok;
  final Color warn;
  final Color danger;

  /// Hover and pressed state of a destructive fill.
  ///
  /// [accent] has had [accentPressed] since the first build; [danger] never did,
  /// because nothing in the product used it as a *fill* — it was a border, a
  /// badge ground and a text colour. Void, refund and force-close all put a
  /// solid danger button on screen, and a destructive CTA with no pressed state
  /// is the one control in the product that gives no feedback that it took the
  /// press. Requested by the patterns handoff (5.3) rather than invented here.
  final Color dangerPressed;
  final Color okSoft;
  final Color warnSoft;
  final Color dangerSoft;

  /// Neutral chip — source badges (POS · PARKED), the CLR key.
  final Color chipBg;
  final Color chipText;

  final Color scrim;

  /// Heavier, for the receipt and lock screens.
  final Color scrimHeavy;

  // Offline / online pills on the shell.
  final Color offlinePillBg;
  final Color offlinePillText;
  final Color onlinePillBg;
  final Color onlinePillBorder;
  final Color onlinePillText;

  /// A refusal shown ON the shell — the rejected-terminal banner.
  ///
  /// Not [danger] on [dangerSoft]: that pair is tuned for the body, and the
  /// banner sits on the shell, which is the darker band in either theme.
  final Color shellDangerBg;
  final Color shellDangerText;

  /// The primary CTA with nothing to press it for — an empty ticket's charge
  /// button. Dark enough to carry white in both themes, because the label
  /// stays white while the fill goes grey.
  final Color ctaDisabled;

  bool get isDark => brightness == Brightness.dark;

  /// The 4×36px bar at the top of a product tile, keyed by category slug.
  ///
  /// Unknown categories fall back to the accent rather than throwing — a new
  /// category on the server must never crash a till. The dark theme lifts each
  /// hue rather than reusing it: these are small bars on a dark ground, and the
  /// light-theme values sink into it.
  Color categoryBar(String? slug) => switch (slug) {
    'grills' => isDark ? const Color(0xFFE05C4E) : const Color(0xFFC0392B),
    'sandwiches' => isDark ? const Color(0xFF4FB477) : const Color(0xFF1F7A3D),
    'pizza' => isDark ? const Color(0xFFD9A03F) : const Color(0xFFA9711A),
    'sides' => isDark ? const Color(0xFF98A0B5) : const Color(0xFF6B748C),
    'drinks' => isDark ? const Color(0xFF7C8AC4) : const Color(0xFF3D4A7A),
    _ => accent, // desserts, combos, and anything new
  };

  // ── Borders ───────────────────────────────────────────────────────────────
  //
  // Elevation in this design is a border, never a shadow, so these are as much
  // a part of the palette as the fills are.

  BorderSide get hairline => BorderSide(color: line);
  BorderSide get resting => BorderSide(color: lineStrong);
  BorderSide get emphasis => BorderSide(color: ink, width: 2);
  BorderSide get accentBorder => BorderSide(color: accent, width: 2);
  BorderSide get shellBorder => BorderSide(color: shellLine);
}

/// Carries the palette on the [ThemeData], so `MaterialApp`'s own
/// theme/darkTheme/themeMode switching is what changes it.
///
/// [lerp] snaps rather than blends. Everything else in this design is instant —
/// no shadows, no ripples, radius 0 — and a palette cross-fading through muddy
/// intermediate browns for 200ms would be the one animated thing in the
/// product, on every surface at once.
@immutable
class PosPaletteExtension extends ThemeExtension<PosPaletteExtension> {
  const PosPaletteExtension(this.palette);

  final PosPalette palette;

  @override
  PosPaletteExtension copyWith({PosPalette? palette}) =>
      PosPaletteExtension(palette ?? this.palette);

  @override
  PosPaletteExtension lerp(
    covariant ThemeExtension<PosPaletteExtension>? other,
    double t,
  ) => t < 0.5 ? this : (other as PosPaletteExtension? ?? this);
}

extension PosPaletteContext on BuildContext {
  /// The palette this screen is being drawn in.
  ///
  /// Falls back to [PosPalette.light] rather than throwing when no POS theme is
  /// installed above this context — a dialog pushed onto a bare test harness
  /// should still render. This mirrors `context.strings`.
  PosPalette get pos =>
      Theme.of(this).extension<PosPaletteExtension>()?.palette ??
      PosPalette.light;
}

/// Font families.
///
/// The web repo vendors these as `.woff2`, which Flutter cannot load. Until
/// `.ttf`/`.otf` files are added to `assets/fonts/` and declared in
/// `pubspec.yaml`, these names resolve to a platform substitute. Layout metrics
/// are specified in logical pixels and do not depend on the substitution.
abstract final class PosFonts {
  /// IBM Plex Sans Arabic, bundled in `assets/fonts/` — for Arabic AND
  /// English. It carries a Latin set drawn to match its Arabic, so a line that
  /// mixes the two (a dish name, then "EGP") is one voice rather than two
  /// fonts taking turns. Chosen by the owner, 2026-09-11.
  ///
  /// Bundled, not assumed: the faces this replaced were named here and never
  /// shipped, so every till drew itself in whatever the machine had — Segoe UI
  /// on Windows, Helvetica on a Mac — and no two looked alike.
  static const ui = 'IBM Plex Sans Arabic';

  /// Every number in the product renders in mono — prices, totals, codes,
  /// times, SKUs, keypad digits — plus all-caps micro-labels. Same family as
  /// [ui], so the figures and the words beside them belong together.
  static const mono = 'IBM Plex Mono';

  /// The same face as [ui]: there is one family for both scripts now.
  static const arabic = ui;

  /// Only for a glyph the bundled faces lack.
  static const uiFallback = <String>['Segoe UI', 'Helvetica Neue', 'Roboto'];
  static const monoFallback = <String>[
    'SF Mono',
    'Consolas',
    'Menlo',
    'monospace',
  ];
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

  // ── Cross-cutting patterns (patterns handoff §5.1–5.8) ────────────────────
  // Dialog chrome and back-office density, which the original handoff never
  // specified because the product had neither. See
  // `docs/pos/13-pattern-handoff-review.md` for what was reconciled and what
  // deliberately kept its original value.

  /// Fixed dialog widths. Not a scale — each is the width its content needs,
  /// and a dialog that resizes itself to its state is a dialog that moves the
  /// button under somebody's finger.
  static const dialogApproval = 620.0;
  static const dialogReason = 520.0;
  static const dialogDestructive = 560.0;
  static const dialogCount = 640.0;

  /// The refund sheet. Wider than the others because it carries a line list, a
  /// totals block, the tender choice and a reason picker in one dialog — the
  /// alternative being a four-step wizard for a task done with a customer
  /// waiting.
  static const dialogRefund = 720.0;

  /// A filter chip in the report frame, and the settings navigation row.
  static const filterChip = 40.0;
  static const settingsNavRow = 40.0;

  /// The report table's body row. Nine of these plus the header, filter bar and
  /// totals row fit above the fold on a 1366×768 till — which is the argument
  /// for keeping a dense mono table there rather than a card summary.
  static const reportRow = 38.0;

  /// The settings navigation rail. 232 leaves 868 for content at the 1100
  /// breakpoint, which the form's 220 label column plus a fluid control column
  /// still fits inside.
  static const settingsNav = 232.0;

  /// The unsaved-changes bar pinned to the bottom of a settings section.
  static const settingsDirtyBar = 64.0;

  /// A settings control, and the denomination field in a drawer count.
  static const formControl = 44.0;

  /// The order-detail pane beside the history list.
  ///
  /// Wider than the 378 cart panel because it carries a totals block and a
  /// payments block the cart never shows, and narrower than half the screen
  /// because the list beside it is what somebody is scanning. At the 1366
  /// breakpoint this leaves 946 for the list, which the seven columns fit
  /// inside without the staff name having to truncate.
  static const historyDetail = 420.0;
}

/// The one border token that does not depend on the theme.
abstract final class PosBorders {
  /// Radius is 0 everywhere in this design. No exceptions.
  static const radius = BorderRadius.zero;
}
