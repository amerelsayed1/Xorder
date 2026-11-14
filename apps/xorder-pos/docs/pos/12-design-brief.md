# Design Brief — XOrder POS gap-closure screens

**For:** the design team / Claude design.
**From:** XOrder POS engineering.
**Companion documents:** `07-design-system.md` (the existing system — read first),
`11-gap-closure-plan.md` (what is being built and in what order).

---

## 1. What this product is

A **desktop-first point of sale** for restaurants in Egypt and the wider Arab
world, running on Windows and macOS, built in Flutter, working **fully offline**
against a PostgreSQL server in the branch. Cashiers use it standing up, at speed,
under time pressure, often with a queue in front of them. Managers use the same
binary for back-office work.

Two audiences, one app:

| | Cashier / waiter | Manager / owner |
|---|---|---|
| Session length | all shift | minutes |
| Input | keyboard + touch, one hand | keyboard + mouse |
| Tolerance for a wrong tap | zero — it is someone's money | low |
| Screens | selling, floor, payment, shift | settings, reports, staff, catalogue |

The product is bilingual **Arabic / English with full RTL**, and ships **light and
dark** palettes.

---

## 2. The two laws (non-negotiable)

1. **Border radius is 0. Everywhere.** Buttons, tiles, sheets, badges, inputs,
   dialogs, chips — nothing is rounded.
2. **There are no shadows.** Elevation is a border: `1px` at rest, `2px`
   emphasised or selected.

A third rule follows from the product: **every number is monospaced.** Prices,
totals, quantities, codes, times, SKUs, keypad digits, percentages. This is not
decoration — a column of prices that does not align is a column a cashier
misreads.

Anything that arrives with a rounded corner, a drop shadow, or a proportional
figure in a price column will be rejected regardless of how good it looks.

---

## 3. The system you are designing inside

Everything below already exists and is implemented in
`lib/core/ui/tokens.dart`. **Design with these tokens. Do not introduce new
colours.** The only tenant-overridable colour is `accent`.

### Colour (light theme; a dark counterpart exists for every token)

| Token | Hex | Use |
|---|---|---|
| `accent` / `accentPressed` / `accentSoft` | `#f89a06` / `#d9850a` / `#fef0d9` | primary action, selection, totals |
| `page` / `surface` | `#f8f5ef` / `#ffffff` | app ground / panels and tiles |
| `ink` / `inkWarm` / `body` / `muted` | `#201e1d` / `#2a1e14` / `#5a4d3d` / `#8a7c68` | heading / dark ink / secondary / tertiary |
| `line` / `lineStrong` | `#ece5d9` / `#ddd6c9` | hairline / tile border |
| `shell` / `shellCard` / `shellLine` / `shellRow` | `#1c1712` / `#2a2118` / `#2e271e` / `#241d15` | dark band: top bar, cart, start, lock |
| `shellText` / `shellMuted` | `#d9d2c6` / `#8a7f6c` | text on shell |
| `ok` / `warn` / `danger` | `#1f7a3d` / `#a9711a` / `#c0392b` | free/synced · offline/86'd · void/refund/bill-asked |
| `okSoft` / `warnSoft` / `dangerSoft` | `#e6f3ea` / `#fbeee0` / `#fdeeec` | badge grounds |

### Type

**Archivo** for UI · **IBM Plex Mono** for every number and every all-caps
micro-label · **Tajawal** for Arabic.

| Role | Size / weight |
|---|---|
| Display total | 32 / 600 mono |
| Big numeric (amount due) | 46 / 600 mono |
| Screen title | 22 / 800 |
| Panel / sheet title | 19–20 / 800 |
| Section title, dialog title | 15–17 / 800 |
| Tile title | 15 / 600 |
| Body | 13.5–14.5 / 400–600 |
| Meta | 12–12.5 / 400 |
| Micro-label | 10 / 600 mono, UPPERCASE, +0.10em |
| Mono meta (codes, SKU) | 11–11.5 / 400 mono |
| Keypad digit | 20–22 / 600 mono |

### Spacing and sizing

Scale **4 · 8 · 10 · 12 · 14 · 16 · 18 · 20 · 24 · 28**. Minimum touch target
**44**. Primary CTA **72–76** tall. Keypad key **≥42** (PIN pad **62**).
Top bar **56**. Category rail **186**. Cart panel **378**. Search row **48**.

### Shells

| Width | Layout |
|---|---|
| **≥ 1100** | rail + grid + persistent panel — **the design driver** |
| **700–1099** | tabs + grid + panel |
| **< 700** | pushed routes |

Every new screen must be specified at **≥1100 first**. Give the 700–1099 behaviour
as a note; <700 only where a cashier would genuinely use it on a handheld.

### Keyboard

`F2` search · `F3` repeat line · `F4` park / send round · `F6` discount ·
`F7` split · `F9` pay · `F10` drawer · `Esc` void or close · `Enter` confirm.
`Ctrl/⌘+Shift+S` opens setup. **Every new action needs a key.** Propose one and
flag conflicts.

---

## 4. What already exists (do not redesign)

Selling screen (rail + product grid + cart) · floor screen with table tiles ·
payment screen with keypad and split tender · receipt dialog · lock screen ·
start screen · setup wizard (10 steps) · licence screen · Management shell with
six panes (Staff · Menu · Floor · Money · Roles · Activity) · modifier sheet ·
supervisor-override PIN dialog.

**Reuse these patterns rather than inventing parallel ones.** In particular the
supervisor-override dialog and the shift open/close dialogs are the established
language for "a privileged act, witnessed".

---

## 5. Cross-cutting patterns needed first

These are used by many screens below. Design them once, properly; everything else
gets cheaper.

### 5.1 Manager-approval modal (extension of an existing dialog)
Shown when a cashier attempts something above their permission or their limit.
Must show: **the act in plain words** ("Discount this line by 30%"), not the
permission key · who is requesting · what limit was exceeded (e.g. "your limit is
10%") · a PIN pad · a **reason** field where the reason is required · and, after
approval, a confirmation naming both people. AR + EN.

### 5.2 Reason picker
A list of configured reasons (8–12 items), keyboard-selectable by number, with an
optional free-text note. Three configurations: required · optional · disabled.
Used by void, refund, pay-out, price override, force-close, inventory adjustment.

### 5.3 Destructive-act confirmation
For void, refund, restore, force-close. Must state **what will happen and what it
cannot undo**, name the amount where money is involved, and require a deliberate
action (not a default-focused OK button).

### 5.4 Blind-entry pattern
Counting cash without seeing the expected figure (§25). The same dialog in two
modes — informed and blind — where the blind one must not leak the answer through
layout, spacing or a suspiciously pre-sized field. Show the reveal state after
commit for those permitted to see it.

### 5.5 Report frame
Filter bar (business day / date range · branch · terminal · employee · order type)
+ a dense monospaced table + totals row + export actions. One frame, ~25 reports
inside it. Must handle: no data · a range too large · a report the user may run but
not export.

### 5.6 Settings frame
Nine sections, roughly forty screens. Needs: a left navigation that survives at
1100 px, a consistent form layout (label · control · help · validation), an
explicit save/discard model with a dirty state, an indicator for
**"this setting is authored by the platform and will be overwritten"** (cloud
mode), and a scope badge — restaurant · branch · terminal · employee.

### 5.7 Permission affordance
Three behaviours, visually distinct and consistently applied:

| Behaviour | When | Appearance |
|---|---|---|
| **Hidden** | no access, no override possible (CRITICAL) | absent — not greyed |
| **Disabled** | access exists but not for this person, no override | visible, muted, with a reason on hover/long-press |
| **Manager approval** | override is possible | **fully enabled**, opens 5.1 on activation |

The distinction is a speed-of-service decision: a cashier must be able to tell at a
glance whether a manager can fix this.

### 5.8 Failure & queue states
Kitchen print failed (retry / choose printer / mark handled) · database
unreachable · server unreachable but internet fine · licence expiring · terminal
rejected. **Rule: an offline till is a healthy till.** Do not use the error colour
for the absence of internet.

---

## 6. Screens needed, by wave

Each entry: **purpose · who · fields/data · states**. Priority `P0` = blocks the
v1 release.

### Wave A — Discount, void, refund `P0`

| # | Screen | Notes |
|---|---|---|
| A1 | **Discount sheet** (`F6`) | Order-level and line-level in one sheet. Preset discounts (from a configured list) + custom % + custom amount. Shows the resulting total live. States: within limit · above limit → 5.1 · requires a customer · not applicable to this item. |
| A2 | **Price override** on a cart line | Inline on the cart line, mono numeric entry, old price struck through, reason required, override-gated. |
| A3 | **Cancel / void dialog** | The dialog must make the *distinction* legible: cancelling an unsent line is routine; voiding a line already cooking is not. Different weight, different confirmation, reason required for the second. |
| A4 | **Void order** | From the cart and from an order in history. Shows what is being voided and its value. |
| A5 | **Refund flow** | Multi-step: find the order (by invoice, by table, recent list) → choose full or partial → select lines and quantities, or enter an amount → reason → choose how money goes back (per tender, respecting `refund_allowed`) → confirm → refund receipt. Show remaining refundable value at every step. |
| A6 | **Order history / open orders** | Dense list: invoice, time, type, table, staff, total, status. Filters. Row actions: view · reprint receipt · void · refund. This is a **new top-level destination** the product currently lacks. |
| A7 | **Reprint receipt** | Confirmation + the `REPRINT` marking on the output + a note that it is recorded. |
| A8 | Cart panel additions | A discount line, a voided-line treatment, and a per-line note affordance, inside the existing 378 px panel. |

### Wave B — Cash & business day `P0`

| # | Screen | Notes |
|---|---|---|
| B1 | **Pay In / Pay Out dialog** | Amount (mono keypad) · reason · note · who · approval when above threshold. Two variants, visually distinguishable at a glance — money entering and money leaving must never be confusable. |
| B2 | **Open drawer (no sale)** | Confirmation stating that this is recorded, with the override path when the cashier lacks the permission. |
| B3 | **Cash-up, expanded** | The existing close dialog grows to the §27 totals: gross, net, tax, service, discounts, refunds, voids, cash, card, other, cash in, cash out, expected, counted, variance. It must stay readable standing at a drawer at 1 a.m. — grouping and hierarchy matter more here than anywhere else in the product. |
| B4 | **Blind cash-up** | Pattern 5.4 applied to B3. |
| B5 | **X report** | The same figures, taken mid-shift, without closing. Clearly marked as a snapshot. |
| B6 | **Business day close** | A blocker list (open shifts / tables / orders / unpaid orders / unclosed drawers) with a route to resolve each, a totals summary, and a force-close path requiring reason + manager PIN. |
| B7 | **Cash movements list** | Per shift and per day, with running totals. |

### Wave C — Permissions `P0`

| # | Screen | Notes |
|---|---|---|
| C1 | **Role editor, rebuilt** | ~120 permissions across 16 categories, with risk level shown. Needs grouping, search, bulk select per category, a diff-from-template indicator, and refusal states ("the owner role keeps everything", "a cashier role may not hold back-office permissions"). The current 16-checkbox pane does not scale to this. |
| C2 | **Permission limits** | Max manual discount (% and amount), max refund value, approval thresholds — per role and per person. |
| C3 | **Staff permission overrides** | ALLOW and **DENY** per person on top of their roles, with DENY visually dominant since it wins. |
| C4 | **Multiple roles per person** | Assignment UI showing the effective union, and where a permission comes from. |
| C5 | **"Why can't I?" explainer** | Given a denied action, show which permission is missing and who in the building holds it. Optional but high value at 8 p.m. on a Friday. |

### Wave D — Settings `P0`

The nine-section shell (5.6) plus these screens: Restaurant general (18 fields) ·
Localization · Taxes · Service charges · Order types (with per-type rules) ·
POS behaviour (11 toggles) · Checkout · Payments / tender types · Discounts
(definition editor, 17 fields) · Receipts (18 fields, with a live preview of the
slip) · Tables & floors · Menu sections · Kitchen · Printers · Devices/terminals ·
People · Cash & shifts · Business day · Inventory · Reports · System.

Plus **two new setup-wizard steps** matching the existing wizard's visual
language: **Restaurant Information** and **Operation Mode** (QSR · FSR · Cafe ·
Takeaway · Delivery · Mixed, with an explanation of what each *shows* — it must
not read as a feature lock).

### Wave E — Floors & tables `P0`

| # | Screen | Notes |
|---|---|---|
| E1 | **Floor plan editor** | Drag-place tables on a grid, per floor, with shape (rect/round/square), size, seats and label. Manager tool, mouse-driven, radius 0 applies to *chrome*; a round table may be round. |
| E2 | **Floor tabs** on the selling floor | Ground / First / Outdoor / VIP. |
| E3 | **Five table states** | available · occupied · reserved · bill requested · needs cleaning. Currently three exist; the two new ones need colour and border treatments that stay distinguishable at 118 px and in both themes. |
| E4 | **Table transfer / merge** | Pick source and target, show what moves. |
| E5 | **Split bill** | Four modes — equal · by item · by seat · custom amount — in one sheet. By-item is the hard one: two or more columns, drag or tap to assign, running totals per split, and a clear "unassigned" bucket. |
| E6 | **Reservation** | Minimal: name, phone, time, party size, on a table. |

### Wave F — Kitchen, printing, hardware `P0`

| # | Screen | Notes |
|---|---|---|
| F1 | **Kitchen stations** | List/edit, with which categories and items route to each. |
| F2 | **Printer management** | Fields per §78. Test print. Status indicator. |
| F3 | **Routing matrix** | Station × printer/KDS/both. Must make "this item prints in two places" visible. |
| F4 | **Kitchen print settings** | 13 toggles (§44) with a preview of the resulting ticket. |
| F5 | **Print failure dialog** | Pattern 5.8. This must never look dismissible-and-forgotten. |
| F6 | **Kitchen ticket layouts** | Receipt-width (80 mm / 48 char) specimens: new round · added items only · void ticket · REPRINT · transferred order. |
| F7 | **Combo builder** | Combo → groups → choices, with surcharges. |
| F8 | **Product editor, expanded** | The current editor gains description, image, cost price, tax, open price, station, prep time, course, per-channel availability. Needs restructuring into tabs or sections. |
| F9 | **Expanded hardware wizard step** | Receipt printer · kitchen printers · drawer · customer display · scanner · KDS · label printer, all skippable. |

### Wave G — Reports `P0`

The report frame (5.5) plus specimens for the six families, an export dialog
(CSV · XLSX · PDF, with the permission caveat), and the import flow
(upload → preview with per-row validation → error report → commit).

### Wave H — Customers `P1`

Customer list · create/edit (with the full delivery address: area, building,
floor, apartment, landmark) · quick-pick from the sale screen by phone ·
customer order history.

### Wave I — Auth & security `P0`

| # | Screen | Notes |
|---|---|---|
| I1 | **Sign-in screen** | Dedicated, replacing the current implicit session. PIN pad primary; username + password as a secondary path for owner/admin/accountant. |
| I2 | **Auto-lock** | The transition into the existing lock screen, plus its setting. |
| I3 | **Lockout state** | "Too many attempts — try again in 4:32." Must not reveal whether the username exists. |
| I4 | **Reauthentication prompt** | For sensitive settings (§84). |
| I5 | **Expanded staff editor** | Identity, authentication, employment and security sections. |

### Wave J — System `P1`

Backup settings & history · restore flow (validation → pre-restore backup →
confirm → progress → result) · **diagnostics screen** (§76, 13 readouts + 5 test
actions) · log viewer/export.

### Wave K — Local server & terminals `P1`

Terminal registration approve/reject · terminal list with type, IP, last seen,
app version, enabled · connection-status states (Connected · Connecting ·
Server unreachable) distinct from internet status.

---

## 7. What we need back

**Per screen:**
1. Layout at **≥1100** with dimensions in **logical pixels**, on the 4–28 spacing scale.
2. **Both themes** — light and dark — using the existing token names, not new hexes.
3. **Arabic RTL mirror** for anything non-trivial. Numbers stay LTR inside RTL text.
4. **Every state**: empty · loading · error · refused-by-permission · needs-override · success. Not just the happy path.
5. **Copy in English and Arabic.** Copy is design here — "Void this item?" and "Remove this item?" are different products.
6. **Keyboard**: which key, what `Tab` order, what `Esc` and `Enter` do.
7. Behaviour note for **700–1099**.

**Global:**
* Any **new token** you need, argued: why the existing set cannot express it.
* A **component inventory** of anything new, so it can be built once in
  `lib/core/ui/widgets/`.

**Do not deliver:** production code · anything with a border radius · anything
with a shadow · new colours outside the token set · icon sets requiring a new
dependency · animations (the product is deliberately instant; the only motion is
none).

---

## 8. Priority for design

1. **5.1–5.8 cross-cutting patterns** — everything else depends on them.
2. **Wave A** (discount, void, refund, order history) — the largest product gap.
3. **Wave B** (cash-up expanded, blind close, business day).
4. **5.6 settings frame + C1 role editor** — the two that do not scale from what exists.
5. **Wave E** floor editor and split bill.
6. **Wave F** kitchen and printing.
7. **Wave G** report frame.
8. Everything else.

---

## 9. Open questions for design

1. **The cart panel is 378 px and gaining a discount line, a voided-line state and
   per-line notes.** Does it hold, or does the ticket need a second density mode?
2. **Split bill by item** at 1100 px, next to a product grid — sheet, full-screen
   takeover, or a mode of the cart?
3. **Forty settings screens** in a product whose Management section is currently
   six tabs. Does the settings shell live inside Management, or become a peer
   destination?
4. **Reports on a 1366×768 till.** Dense mono table, or a card summary with a
   drill-down?
5. **Reserved vs Needs-cleaning table states** — two more colours on a floor that
   already uses accent, danger and surface. Colour, border pattern, or badge?
6. **The blind-close reveal.** After committing, does the cashier see the variance
   they just created, or only the manager?
