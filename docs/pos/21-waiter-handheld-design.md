# 21 — XOrder Waiter: handheld design (WA2 design pass)

**Written 2026-11-09.** For `apps/xorder_pos_waiter` (the handheld built in WA1, commit
`b525d1e`). Companion: `07-design-system.md` (the till's tokens — this document applies them to
a phone), `12-design-brief.md` §2 (the two laws). The wire it renders is
`packages/xorder_waiter_link/lib/src/wire.dart`; nothing here asks the wire for a field it
does not carry.

WA1 made the handheld *work*: pair, PIN, floor, check, options, send. It was built from the
till's theme file with Material defaults for everything else, so a waiter gets a functional
screen that does not yet read like the till it serves. This document is the design the WA2
pass implements, and the standard every later waiter screen is held to.

---

## 1. Who holds it, and how

A waiter, standing, walking between tables, **one hand**, often mid-conversation with a guest,
in a noisy room, on a phone they also use for everything else. A table is open for an hour;
the handheld is looked at for seconds at a time. Arabic is the working language of the floor;
English must be one tap away because the staff mix is not predictable.

That gives five principles, in priority order:

1. **Thumb first.** The action a waiter is most likely to take next sits at the bottom of the
   screen, full width, 56 px tall. Nothing a waiter needs during service lives only in a
   top-corner icon.
2. **Glance, then act.** The floor answers *where am I needed* without reading: state is
   colour **and** a word, never colour alone. The check answers *what have I not sent yet*
   before anything else.
3. **The till prices; the handheld shows.** Every amount on screen came from the till. The one
   estimate the handheld makes (the Add button on the options sheet) is marked as an estimate
   and is replaced by the till's figure the moment the line exists.
4. **The two laws, and mono numbers.** Radius 0, no shadows, elevation is a border. Every
   number — price, total, quantity, round number, keypad digit, table label — is IBM Plex Mono.
5. **Mirrored, not translated.** Arabic is the default and the layout mirrors with it
   (`EdgeInsetsDirectional`, `start`/`end`). Digits, addresses and the keypad stay LTR in both
   languages, as on every keypad.

## 2. Shells by width

| Width | Shell |
|---|---|
| **< 700** (phones) | One column. Pushed routes: floor → table. On a table, **Menu / Check** as two tabs with a **sticky check bar** under the menu (total · unsent count · "Check (n)"). |
| **≥ 700** (tablets) | On a table: menu on the start side, the check as a fixed 360 px pane on the end side, no tabs, no check bar. |

Portrait phones are the design driver. The tablet shell exists because a cheap Android tablet
on the pass is a common second device; it is the same widgets in a `Row`.

## 3. Tokens on a handheld

### 3.1 Colour

The handheld copies the till's **light** palette (`PosPalette.light`) — the parity test in
`packages/shared_module/test/features/waiter_link/waiter_theme_parity_test.dart` fails the
moment a copied value drifts. WA2 adds the **shell** family to the copy (the pairing and PIN
screens are shell screens, like the till's start and lock screens).

| Where | Ground | Edge | Text |
|---|---|---|---|
| App ground | `page` | — | `ink` / `body` / `muted` |
| Tile, card, sheet | `surface` | `lineStrong` 1 px | — |
| Selected / open table | `accentSoft` | `accent` 2 px | `ink` |
| Bill asked | `dangerSoft` | `danger` 2 px | `danger` for the state word |
| Unsent line marker | — | `accent` 4 px on the start edge | state word in `warn` |
| Error note | `dangerSoft` | `danger` 1 px | `danger` |
| Shell screens (pair, PIN) | `shell` | `shellLine` | `shellText` / `shellMuted` |
| Primary CTA | `accent` | — | `onAccent` |
| Disabled CTA | `line` | — | `muted` |

Only `accent` is tenant-overridable, as on the till; the handheld has no second accent.

### 3.2 Type

The till ships IBM Plex Sans Arabic (UI, both languages) and IBM Plex Mono (numbers). The
handheld ships the **same files** in its own `assets/fonts/` (fonts are assets, not till code;
D-WA4 holds) so Arabic and Latin render identically on both devices.

| Role | Style |
|---|---|
| Screen title (app bar) | 18 / 700 |
| Table label on a tile | 20 / 800 **mono** |
| Section header (area, round, "Not sent") | 11 / 600 UI face, UPPERCASE, +0.08 em; the count beside it in mono |
| Tile / line title | 14.5 / 600 |
| Body | 14 / 400 |
| Meta (modifiers, status word, area) | 12.5 / 400 |
| State badge | 11 / 700 |
| Price on a tile or line | 14 / 600 mono |
| Check total | 22 / 700 mono |
| Check bar total | 18 / 700 mono |
| Keypad digit | 24 / 600 mono |
| Pairing code field | 24 / 600 mono, letter-spaced |

### 3.3 Size and space

Spacing scale as the till: 4 · 8 · 12 · 16 · 20 · 24.

| Element | Size |
|---|---|
| Smallest touch target | **48** |
| Primary CTA | 56, full width |
| Check bar | 64 |
| App bar | 56, 1 px `line` under it |
| Table tile | 112 tall, min 156 wide, auto-fill, 10 gutter |
| Product tile | 96 tall, min 160 wide, 8 gutter |
| Category chip row | 48 |
| Search row | 48 |
| Option row | 48 |
| Keypad key | 64 |
| Section header | 32 |

## 4. Components

Every component lives in `lib/screens/widgets.dart`; screens compose them and add no
one-off styling.

- **`SectionHeader`** — the mono micro-label with an optional count on the end side. Used for
  dining areas on the floor, for "Not sent" and "Round n" on the check, for option groups.
- **`StateBadge`** — soft ground + 1 px edge + 11/700 word. Three variants: free (`surface` /
  `lineStrong` / `muted`), open (`accentSoft` / `accent` / `ink`), bill asked (`dangerSoft` /
  `danger` / `danger`).
- **`MoneyText`** — an amount from the till: the number in mono, the currency label in the UI
  face (the mono face has no Arabic glyphs; "ج.م" must read as the pound). Never computes,
  only formats; takes a prefix for "+" (an option's price change) and "≈" (the estimate).
- **`BottomBar`** — `surface` ground, 1 px `line` on top, safe-area aware, holds the CTA or the
  check bar. Replaces a Material `BottomAppBar` so there is no shadow.
- **`PrimaryCta`** — `FilledButton` at 56, label 15/700, spinner while busy.
- **`ErrorNote`**, **`EmptyState`** (muted text, optional action), **`SmallSpinner`**.
- **`Stepper`** — minus · mono value · plus, 48-tall buttons.
- **`OptionRow`** — 48-tall row: square indicator (radio for single-choice groups, check for
  multi), name, price delta in mono on the end side; disabled when unavailable.
- **`LanguageButton`** — on every screen, as WA1.

## 5. Screens

### 5.1 Two flavors, one door each
XOrder Waiter ships as **two apps** — *XOrder Waiter – Cloud* and *XOrder Waiter – Offline* —
built from one codebase with the mode fixed by the entry point (`lib/main_cloud.dart`,
`lib/main_offline.dart`; Android product flavors `cloud` / `offline`, their own application
ids and names). A waiter never chooses a mode; the restaurant is given the app that fits it
(a restaurant with a till gets Offline, one without gets Cloud — POS-BE-033). There is no
pairing code (owner decision, 2026-11-09).

### 5.2 Sign in
Shell screen, the same in both flavors but for the first field. A `shellCard` panel, max 440
wide, centred: the XOrder mark, the title, one line of guidance (or, once remembered, the
server's name), then three fields and the CTA:

| | Offline | Cloud |
|---|---|---|
| Field 1 | **Till address** (`192.168.1.20`, port assumed; LTR, URL keyboard, mono) | **Restaurant** (`demo`, suffixed `.xorder.io`; LTR, mono) |
| Field 2 | **Your name** — the username on the till | **Your name** — the username in the dashboard |
| Field 3 | **PIN** — obscured, digits only, 4–8, mono, letter-spaced | same |
| Talks to | the till on the LAN | `https://{slug}.xorder.io/api/pos/waiter` |

Field 1 and the name are remembered on the phone; the PIN is never. The first sign-in from a
phone registers it with the server under "{name} · {phone kind}" and the token that comes back
is kept; a phone the server revoked is told so and simply signs in again, as a new device. An
overflow menu offers *Forget this till / restaurant*. One error note in a fixed slot: a wrong
name or PIN is one message ("That name and PIN were not accepted"), never which of the two.

**The till's certificate (offline flavor, WA4).** The link is TLS only; the till serves it with
a certificate it made itself and shows under Settings › Waiter devices. The very first sign-in
to a till stops before any name or PIN leaves the phone: a dialog shows the fingerprint the
till presented (`AB:CD:…`, mono, LTR, selectable, with its expiry) and asks *Is this the till?*
— **They match** / Cancel. A confirmed fingerprint is kept with the connection and is the only
certificate the phone will then accept for that address. A till that later answers with a
different one is refused with "the till answered with a different certificate…"; the only way
on is *Forget this till* and a fresh comparison. The cloud flavor never shows this dialog: the
platform's certificate is verified by the phone's trust store.

### 5.3 Floor
App bar: **Tables** · staff name (end side) · overflow (language, sign out). Under it a
one-line **summary strip**: "{open} open · {paying} paying · {free} free" in meta type — the
glance before the grid.

Body: tables **grouped by dining area** in the till's order, each under a `SectionHeader` with
its count; tables with no area under the header "Tables". Tiles in an auto-fill grid. Pull to
refresh; a 5 s silent poll while on screen (WA1). A failed poll shows an `ErrorNote` above the
grid and keeps the last floor: a stale floor beats an empty one.

**Table tile** (112 tall): label mono 20/800 at the top start; `StateBadge` at the top end;
area in meta under the label (only when the floor is *not* grouped, i.e. one area); bottom
row: items count (meta) and total (mono 14/600) for an open table; seats in `muted` for a free
one; guests when set — count on one line, total on the next, so neither is ever cut. Bill-asked tiles carry the 2 px `danger` edge and the state word in
`danger`: the only red on the floor, so it means one thing.

Empty: "The till has no tables. Add them in the back office." (WA1 wording.)

### 5.4 Table (check) — phone
App bar: table label (mono) · "{area} · {n} guests" subtitle · guests button · refresh.
Two tabs at 48: **Menu** · **Check (n)** where n counts live lines; indicator 2 px `accent`.

**Menu tab:** search row (48; filters by name in either language, no network), category chip
row (48; square chips, selected = `accentSoft` + `accent` edge), product grid (96-tall tiles:
name 14.5/600 two lines, price mono 14/600; unavailable = `page` ground, `muted` text,
"Unavailable" instead of a price; one tap adds a product with no option groups, otherwise opens
the options sheet). **Sticky check bar** (64) at the bottom while there is a check: total in
mono 18/700 and "{n} not sent" in `warn` meta on the start side; **Check (n)** outlined button
on the end side, which switches to the Check tab. The bar never sends: sending is a decision
taken while looking at the lines.

**Check tab:** lines grouped, **"Not sent" first** (`SectionHeader` with count, every line
marked with the 4 px `accent` start edge, tappable → line sheet), then **"Round n"** groups
newest first (sent lines in `body`/`muted`, not editable; a tap explains "already sent, ask the
cashier"), voided lines struck through in `muted`. Totals block (subtotal, discount, service,
tax, **Total** mono 22/700). `PrimaryCta` **Send to kitchen (n)** at 56, disabled with no draft.
Empty: "Nothing on this table yet. Tap an item to add it." with an **Open the menu** action.

### 5.5 Table — tablet
Same panes in a `Row`: menu (flexible) · 1 px divider · check pane (360). No tabs, no check
bar; the CTA is in the pane.

### 5.6 Options sheet
Bottom sheet, `surface`, max 85 % tall. Header: product name 20/800 and base price mono. One
`SectionHeader` per group ("Required" in `warn` or "Choose up to n" in `muted` on the end side),
then `OptionRow`s. Note field (140 chars). Footer: `Stepper` · **Add ≈ {estimate}** CTA; the ≈
says the till will price it. Disabled until every required group is satisfied.

### 5.7 Line sheet (an unsent line)
Name 20/800, `Stepper` for quantity, note field, **Remove** (outlined, `danger` text) on the
start side, **Save** CTA on the end side.

### 5.8 Feedback
- Snackbar: floating, square, `ink` ground for confirmations ("Sent to the kitchen."), `danger`
  for refusals; the till's refusal codes are worded in `strings.dart` (WA1).
- "Changed on another device": the latest check replaces the screen and a `danger` snackbar
  says so; nothing is merged silently (XORD-044).
- Loading: `CircularProgressIndicator` in `ink`, stroke 2; never a skeleton on a 5 s poll.

## 6. Accessibility and input

- Every tappable ≥ 48 × 48; tiles and rows are the whole surface, not the text.
- State is never colour-only (badge word + colour); draft lines are marked by an edge **and** a
  status word.
- Text scales with the system setting up to 1.3× without clipping: tiles use `maxLines` and
  ellipsis, bars use `Flexible`.
- Keypad and code fields are LTR with `textDirection` forced; `FilteringTextInputFormatter`
  keeps codes digits-only.

## 7. What WA2 changes from WA1 (the implementation list)

| # | Change | Where |
|---|---|---|
| D1 | Ship IBM Plex Sans Arabic + IBM Plex Mono in the app; theme and `waiterMono` use them | `assets/fonts/`, `pubspec.yaml`, `theme.dart` |
| D2 | Shell tokens copied (`shell`, `shellCard`, `shellLine`, `shellText`, `shellMuted`); parity test extended | `theme.dart`, `waiter_theme_parity_test.dart` |
| D3 | Handheld type scale (`WaiterText`), chip/tab/snackbar/app-bar theming per §3 | `theme.dart` |
| D4 | Components of §4 | `screens/widgets.dart` |
| D5 | Floor: summary strip, area sections, tile per §5.3 | `screens/floor_screen.dart` |
| D6 | Check: search, sticky check bar, rounds grouping, CTA with count, empty-state action | `screens/check_screen.dart` |
| D7 | Options sheet with `OptionRow`s and the ≈ estimate; line sheet per §5.7 | `screens/item_sheet.dart` |
| D8 | One sign-in shell screen per flavor (address or slug · name · PIN); the pairing code is gone | `screens/sign_in_screen.dart`, `mode.dart`, `main_cloud.dart`, `main_offline.dart` |
| D9 | New strings: summary strip, "Not sent", "Round n", "Open the menu", "Search", "Tables" (no area) | `strings.dart` |

Out of the design pass, unchanged from WA1 and tracked there: keystore token storage, kitchen dockets,
an offline queue on the handheld, voiding sent lines, payment. The cloud flavor waits on
POS-BE-033 and runs against a fake until it is READY.
