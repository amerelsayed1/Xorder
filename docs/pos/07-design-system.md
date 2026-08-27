# POS Design System — extracted from the design handoff

**Source:** `design_handoff_xorder_pos/` (README + `XOrder POS - Flutter Handoff.dc.html`)
**Fidelity:** the handoff states colours, typography, spacing, states and copy are
**final and exact**. Where this document and the handoff disagree, **the handoff wins**.
**Implemented by:** `lib/core/ui/tokens.dart` (values) and `lib/core/ui/theme.dart` (Material wiring).

> The `.dc.html` files are design references, not production code. Their markup,
> inline styles and DC runtime are deliberately **not** ported.

---

## 1. Two laws that shape everything

1. **Border radius is 0. Everywhere.** Not on buttons, tiles, sheets, badges or inputs.
2. **There are no shadows.** Elevation is expressed as a border: `1px lineStrong`
   for a resting surface, `2px ink` for the emphasised or selected one.

A Material widget that rounds a corner or drops a shadow is wrong, which is why
`theme.dart` overrides the shape and elevation of every component it touches
rather than relying on defaults.

## 2. Colour

Provenance: **DS** = the web repo's `packages/ui/src/theme.css` (`.theme-warm`);
**POS** = introduced by this chrome. **`accent` is the only tenant-overridable colour.**

| Token | Hex | Source | Use |
|---|---|---|---|
| `accent` | `#f89a06` | DS | primary action, selected tab/category, totals, active tile border |
| `accentPressed` | `#d9850a` | DS | hover/pressed on accent fills; product tile price |
| `accentSoft` | `#fef0d9` | DS | selected/hover tint, occupied table, "in cart" |
| `page` | `#f8f5ef` | DS | app ground |
| `surface` | `#ffffff` | DS | tiles, rail, panels, sheets |
| `inkWarm` | `#2a1e14` | DS | dashboard body ink, button borders on light ground |
| `ink` | `#201e1d` | POS | headings, 2px rules, dark buttons |
| `body` / `muted` | `#5a4d3d` / `#8a7c68` | DS | secondary / tertiary text |
| `line` / `lineStrong` | `#ece5d9` / `#ddd6c9` | DS / POS | hairline dividers / tile borders |
| `shell` | `#1c1712` | DS | top bar, cart panel, start & lock screens |
| `shellCard` / `shellLine` / `shellRow` | `#2a2118` / `#2e271e` / `#241d15` | DS / POS | dark-shell surfaces |
| `shellText` / `shellMuted` | `#d9d2c6` / `#8a7f6c` | DS | text on shell |
| `ok` / `warn` / `danger` | `#1f7a3d` / `#a9711a` / `#c0392b` | DS | free/synced · offline/occupied/86'd · bill asked/void/refund |
| `okSoft` / `warnSoft` / `dangerSoft` | `#e6f3ea` / `#fbeee0` / `#fdeeec` | DS | badge grounds |
| scrim | `rgba(20,18,15,.55)` | POS | `.6` for receipt and lock |

**Category bars** (4×36px at the top of each product tile): Grills `#c0392b` ·
Sandwiches `#1f7a3d` · Pizza `#a9711a` · Sides `#6b748c` · Drinks `#3d4a7a` ·
Desserts/Combos `#f89a06`.

**Dark-shell pills:** offline bg `#3a2a12` / border `#a9711a` / text `#f2c078`;
online bg `#16301f` / border `#2e5c3a` / text `#8fd6a5`.

## 3. Typography

| Family | Role | Weights |
|---|---|---|
| **Archivo** | all UI | 400 · 500 · 600 · 800 |
| **IBM Plex Mono** | **every number** — prices, totals, codes, times, SKUs, keypad digits — and all-caps micro-labels | 400 · 500 · 600 |
| **Tajawal** | Arabic | 400 · 500 · 700 |

> **Known gap.** The web repo vendors these as `.woff2`, which Flutter cannot
> load. Until `.ttf`/`.otf` files are dropped into `assets/fonts/` and declared in
> `pubspec.yaml`, the app names the families and the platform substitutes. Layout
> metrics are specified in logical pixels and do not depend on the substitution,
> so this is a fidelity gap, not a layout gap. `PosFonts` in `tokens.dart` is the
> single place to wire them up.

Scale as used:

| Token | Value | Where |
|---|---|---|
| Display total | 32 / 600 / 1.0 mono | cart TOTAL |
| Big numeric | 46 / 600 / 1.0 mono | payment amount due |
| Screen title | 22 / 800 Archivo | "Pick a table" |
| Panel title | 19–20 / 800 | ticket header, sheet header |
| Section title | 15–17 / 800 | TOTAL label, dialog titles |
| Tile title | 15 / 600 / 1.25 | product name |
| Body | 13.5–14.5 / 400–600 | rows, buttons, list items |
| Meta | 12–12.5 / 400 | line modifiers, sub-labels |
| Micro-label | 10 / 600 mono, +0.10em tracking, UPPERCASE | "CATEGORIES", "AMOUNT DUE" |
| Mono meta | 11–11.5 / 400 mono | ticket code, shift, SKU |
| Keypad digit | 20–22 / 600 mono | payment + PIN pads |

## 4. Spacing, sizing, grids

Spacing scale: **4 · 8 · 10 · 12 · 14 · 16 · 18 · 20 · 24 · 28**.

| Element | Size |
|---|---|
| Minimum touch target | **44** |
| Primary CTA height | 72–76 |
| Keypad key / PIN key | ≥42 / 62 |
| Product tile | 132 tall, min width 150, auto-fill |
| Table tile | 118 tall, min width 150 |
| Top bar | 56 |
| Category rail | 186 |
| Cart panel | 378 |
| Search row | 48 |
| Grid gutters | 10 products · 12 tables · 1px hairline for keypads |

The Flutter build sheet specifies the product grid as
`SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 190)`, which
satisfies the CSS `minmax(150px, 1fr)` auto-fill behaviour.

## 5. Responsive shells

One feature set, three shells, chosen by width — from the Flutter build sheet §2:

| Width | Shell |
|---|---|
| **≥ 1100** | category rail + product grid + persistent cart panel |
| **700–1099** | tabs + grid + cart |
| **< 700** | pushed routes: products → cart → payment |

Desktop is the primary target; the narrow shell exists for Android POS handhelds
and is not the design driver.

## 6. Keyboard map

Registered once at the shell via `Shortcuts`/`Actions`, never per-screen:

| Key | Action |
|---|---|
| `F2` | focus search |
| `F3` | repeat last line |
| `F4` | park ticket / send round |
| `F6` | discount |
| `F7` | split payment |
| `F9` | pay |
| `F10` | open cash drawer |
| `Esc` | void / close dialog |
| `Enter` | confirm |

## 7. Money and tax presentation

- **Money is integer minor units end to end.** Never a `double`.
- Rounding is **half-up, applied once at the tax line**, to match the Laravel
  `Order::total` `decimal:2` cast.
- Service **12%**, dine-in only. VAT **14%**, applied to `subtotal + service`.
  These are **placeholder device config** until `POS-BE-013` is `READY` — the
  server must become the author of tax. See `docs/coordination/BACKEND_TO_POS.md` §A7.
- Every number renders in IBM Plex Mono. Arabic locales render Arabic-Indic
  digits via the existing digit-folding helper.

## 8. What is placeholder

The handoff is explicit: sample data — menu items, prices, table numbers, the
staff name "Rana A.", the tenant "Mahsoub Grill" — is **placeholder and must come
from the API**. It lives only in `FakeCatalogRepository` and friends, never in a
widget. The prototype also fakes the printer, drawer, card terminal and the
network; those are real integrations behind the ports in §8 of the build sheet.
