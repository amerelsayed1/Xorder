# Patterns Handoff — reconciliation and build order

**Handoff:** `design_handoff_pos_patterns/` — cross-cutting patterns 5.1–5.8 plus
§9.1 cart density, from `12-design-brief.md` §5.
**Revision reviewed:** **2** (2026-09-07). Revision 1 reviewed the same day.
**Fidelity claimed:** high — geometry, tokens, states and copy final; copy is
production EN + AR.
**Status of this document:** the handoff verified against the shipped code. Where
the two disagree, this says which wins and why.

> **Revision 2 closes all four items this document sent back.** CTA heights
> corrected to 76/52 · the dark `warnSoft`/`accentSoft` collision separated ·
> the active-nav border confirmed at 2px · §9.1 cart density designed, which
> unblocks Wave A8. §5 below is the new send-back list, and it is one item long.

> The `.dc.html` prototype and `support.js` are **design references, not
> production code**, and are deliberately not vendored into the repository —
> the same rule `07-design-system.md` already applies to the original handoff.
> The harness (left rail, pattern header, STATE chips, SPEC strip) is not
> product UI.

---

## 1. Verdict

**Accept the handoff. It is buildable as delivered.** Every pattern is
expressible in the shipped token set, the copy is usable verbatim, and the four
design questions it answers (§9.1, §9.3, §9.4, §9.6) are answered with reasons
rather than preferences.

Revision 2 resolved every blocking item. What remains is one naming
reconciliation this document owns (§4.2), one small token collision **in the
light theme** that revision 2's own rule now forbids (§5), and two brief
questions design has not reached yet (§4.4).

---

## 2. Tokens — verified against `tokens.dart`

### 2.1 The dark palette is not proposed; it exists

The handoff derives a dark set and marks it **PROPOSED, needs confirming**, with
the rule *"if the real dark set differs, the real one wins — no design change is
implied."* It does differ, at every token. **`PosPalette.dark` wins**; the
handoff's table is superseded and should not be transcribed anywhere.

| Token | Handoff proposed | Shipped `PosPalette.dark` |
|---|---|---|
| page / surface | `#14100c` / `#1e1811` | `#14110E` / `#1C1712` |
| ink / inkWarm | `#f4efe6` / `#f7f2e9` | `#F2EDE4` / `#EAE3D7` |
| body / muted | `#c2b6a3` / `#8a7f6c` | `#C6BCAD` / `#978B79` |
| line / lineStrong | `#2b2419` / `#3b3225` | `#2A231B` / `#3A3229` |
| accentSoft | `#3a2a0d` | `#3A2A12` |
| ok / warn / danger | `#57b878` / `#e0a545` / `#e8705f` | `#4FB477` / `#D9A03F` / `#E4695C` |
| okSoft / warnSoft / dangerSoft | `#14291c` / `#2f2413` / `#341a17` | `#16301F` / `#3A2A12` / `#3A1C18` |
| shell / shellCard / shellLine / shellRow | `#100d09` / `#1e1811` / `#2b2419` / `#191309` | `#0E0C0A` / `#1F1913` / `#2E271E` / `#171310` |

The differences are small and the intent matches — same hue family, `accent`
unchanged across themes, status colours lifted. Nothing in the designs changes.

**The dark `warnSoft` / `accentSoft` collision — fixed** ✅

Revision 1 could not have known that the shipped dark palette had
`warnSoft` and `accentSoft` at the *same* value (`#3A2A12`), which collapsed
5.1's limit strip into the selected reason row directly beneath it and made
5.6's dirty bar indistinguishable from the platform note above it.

Revision 2 states the rule, and it is a good one: **`accentSoft` means
*selected*, `warnSoft` means *caution*, and they may never be within one visible
step of each other in either theme.** Selection moves toward the accent; caution
moves toward the page.

Applied to the shipped dark palette in [tokens.dart](../../lib/core/ui/tokens.dart):

| Token | Was | Now | Direction |
|---|---|---|---|
| dark `accentSoft` | `#3A2A12` | `#4A3110` | lighter, more chromatic — reads orange |
| dark `warnSoft` | `#3A2A12` | `#2A2418` | darker, desaturated — reads near-neutral |

All ten `warnSoft` call sites are cautions paired with `warn` text (licence
expiry, grace, setup notices, a shift closing out of balance), so the change is
in the right direction at every one of them.

**One token was left alone deliberately:** dark `offlinePillBg` is also
`#3A2A12`. It is a pill with its own paired text colour (`offlinePillText`), it
never sits beside a selection, and the handoff does not cover pills. Moving it
on inference would be a change nobody asked for.

### 2.2 `dangerPressed` — added ✅

The handoff requests it rather than using a one-off, and is right to: void,
refund and force-close all put a solid `danger` fill on screen, and a
destructive CTA with no pressed state is the one control in the product that
gives no feedback that it took the press.

Added to [tokens.dart](../../lib/core/ui/tokens.dart):

| Theme | Value | Derivation |
|---|---|---|
| light | `#A5301F` | the prototype's value, verbatim |
| dark | `#C9564A` | `danger` darkened by the same ratio `accent`→`accentPressed` uses |

### 2.3 Size tokens — added ✅

The original handoff never specified dialog chrome or back-office density
because the product had neither. Added to `PosSize`: `dialogApproval` 620 ·
`dialogReason` 520 · `dialogDestructive` 560 · `dialogCount` 640 ·
`filterChip` 40 · `settingsNavRow` 40 · `reportRow` 38 · `settingsNav` 232 ·
`settingsDirtyBar` 64 · `formControl` 44.

### 2.4 Values the handoff restates — all reconciled

| | Shipped `PosSize` | Rev 1 | Rev 2 | Resolution |
|---|---|---|---|---|
| Primary CTA | `primaryCta = 76` | 72 | **76** | Handoff corrected itself. No code change. |
| Secondary button | `secondaryAction = 52` | 48 | **52** | Same. |
| Settings dirty-bar buttons | — | 44 | 44 | Toolbar controls, not a CTA. Use `minTouchTarget`. |
| Keypad key | `keypadKey = 42`, `pinKey = 62` | 62 in 5.1 | 62 | No conflict — 5.1's pad is a PIN pad; use `pinKey`. |

### 2.5 Off-system values in the specs

* **`3px accent`** inline-start border on the active settings-nav row —
  **corrected to `2px` in revision 2** ✅, for the reason this document gave: the
  system has exactly two border weights, and selection must read the same on a
  nav row as it does on a selected reason row or a selected table tile.
* **`9/12` padding** on compact `ReasonPicker` rows. `9` is not on the spacing
  scale (4 · 8 · 10 · 12 · 14 · 16 · 18 · 20 · 24 · 28). **Use `10/12`.**
* **`1px dashed lineStrong`** for the disabled permission affordance. Dashed is
  new but is a border *style*, not a new token, and it carries real meaning here
  (this control exists and is not available to you). **Accept.**

---

## 3. Component inventory — reconciled against what is already built

The handoff proposes 13 widgets. **Three already exist**, and one of the
"new" patterns is an extension of a dialog that is already the single entry
point for every gated action in the app.

| Handoff widget | Status | Notes |
|---|---|---|
| `MicroLabel` | **exists** — [pos_widgets.dart:44](../../lib/core/ui/widgets/pos_widgets.dart:44) | Already 10/600 mono, uppercase, 0.10em. Do not rebuild. |
| `PinPad` | **exists** — [pos_widgets.dart:285](../../lib/core/ui/widgets/pos_widgets.dart:285) | Shipped signature is `onDigit` / `onBackspace`; the handoff proposes `length` / `onChanged` / `keySize`. **Keep the shipped one** — it is shared by the lock screen and shift open, and two keypads that drift apart is exactly the failure its doc comment warns about. `PinDots` beside it covers the masked display. |
| `ManagerApprovalDialog` | **extend** — [supervisor_override.dart](../../lib/features/admin/presentation/supervisor_override.dart) | `requestPermission()` is already the one entry point, already records both identities to the audit ledger, already refuses non-overridable capabilities. What 5.1 adds: the two-cell fact grid, the **limit strip**, the reason picker, `attemptsLeft`, and the approved confirmation naming both people. Extend it; do not write a parallel dialog. |
| `MonoAmount` | **new** | Highest-value small widget in the list: forces `Directionality.ltr` **by construction**, so "numbers stay LTR inside RTL" cannot be forgotten at a call site. Build this first. |
| `ReasonPicker` | **new** | Config (`required`/`optional`/`disabled`) comes from `pos_reason_codes` (Wave A migration 9), not from local state. |
| `DestructiveConfirmDialog` | **new** | The deliberate-action rule — *Keep* holds focus, Enter does nothing, no shortcut fires a void — is behaviour, not styling. Assert it in a widget test. |
| `BlindCountDialog` | **new** | See §4.2 on the permission name. |
| `ReportFrame` | **new** | Wave G. |
| `SettingsScaffold` / `SettingsFieldRow` / `ScopeBadge` | **new** | Wave D. |
| `PermissionGate` | **new** | Consumes a `PermissionDecision` from `Authorization`; pairs with the existing `requestPermission()` for the approval path. |
| `FailureCard` | **new** | `SyncPill` already exists for the top bar and is *not* superseded — the pill is status, the card is an event. |
| `CartPanel` | **exists — extend** | [cart_panel.dart](../../lib/features/sale/widgets/cart_panel.dart), 366 lines. Revision 2 adds a density mode and three line treatments (§3.1), not a rewrite. |

### 3.1 §9.1 — cart density (revision 2, unblocks A8)

**Verdict: 378 holds; a second density mode is required rather than optional.**
The argument is structural and correct — a discount line and a void reason are
extra *rows inside a line*, not extra columns, so width was never the
constraint. Comfortable density shows 7 lines in the 420 list height and a
mid-sized full-service check runs 9–14.

| | Comfortable | Compact |
|---|---|---|
| Plain line block | 44 | 32 |
| Line with note or discount | 62 | 48 |
| Lines visible in 420 | 7 | 11 |
| `SENT 19:42` timestamp | shown | **dropped — the only thing compact drops** |
| Notes · discounts · void reasons | shown | **shown, never dropped** |

The rule that makes this safe: compact drops the sent timestamp and nothing
else. Everything a cashier or a customer needs in order to *dispute* the ticket
survives at both densities.

**The switch is automatic above 7 lines and then sticky for the rest of that
order.** This matters more than it looks: rows that resize under a finger
mid-sale are how a cashier taps the wrong line. Per-terminal default lives in
Settings › POS behaviour (Wave D) — full-service compact, quick-service
comfortable — and there is deliberately **no manual toggle on the sale screen**.

**Three A8 treatments, all inside the existing 378:**

* **Discount line** — a child row of its line, `2px accent` inline-start,
  **naming the approver** ("Discount 30% · approved by Hana M."). Order-level
  discounts do not appear here; they belong in the totals block. That split
  matches the schema exactly: `pos_order_discounts.order_line_id` is null for an
  order-level discount (Wave A, migration 10).
* **Voided line** — struck through, a `1px danger` `VOID` chip, reason on the
  meta row. **The line stays in place and is never removed** — the cashier has
  to be able to show a customer what happened and what it cost. This is also
  what the ledger does, so the screen and the record agree.
* **Note** — meta row behind a 6px accent square, no empty state, added from the
  line's action row. **No F-key: the map is full**, which is an honest answer
  rather than a squeezed-in binding.

**Keyboard:** F3 repeats the focused line · Esc voids it via 5.3 · F6 discounts
it via 5.7 → 5.1 · arrow keys walk lines with a `2px accent` focus marker. All
three F-keys are in the documented map and none is currently bound (§4.3), so
Wave A binds them for the first time.

**Implementation note.** The panel is `shell`-family in both themes, and the
existing [cart_panel.dart](../../lib/features/sale/widgets/cart_panel.dart)
already draws it that way. The density mode is a parameter on the existing
widget plus two line sub-rows — not a second panel. The one thing to resist is
letting `density` be read from a provider inside the widget: it is per-terminal
settings state, and the panel should take it, so the sticky-per-order rule lives
in the sale screen where the order does.

**Status: the discount half and the voided-line treatment are built.** Line
selection, the line discount child row (naming its approver), the order
discount row in the totals block, and the struck-through voided line with its
`VOID` chip and reason — 15 tests. **Not built: the two density modes** and the
per-line note affordance. Neither is blocked on another feature.

---

## 4. Open items

### 4.1 CTA heights — **resolved in revision 2** ✅

Revision 1 said 72/48 against the shipped `primaryCta = 76` /
`secondaryAction = 52`. Revision 2 corrects itself to **76/52 throughout** and
states the rule: there is one primary CTA height and one secondary height in
this product.

No code change — the shipped tokens were already right. Revision 2 also
clarifies a case revision 1 left ambiguous: the settings dirty bar's buttons are
**44**, because they are toolbar controls rather than a CTA. 76/52 applies to
dialog and panel CTAs only.

### 4.2 `cash.variance.view` (naming reconciliation)

5.4 gates the blind-close reveal on `cash.variance.view`. The gap-closure plan
(Wave B) names the same idea twice already: `shift.view_expected_cash` (§24) and
`cash.view_expected` (§22), both straight from the SRS.

These are **two questions, not three**:

| Question | Capability | Used by |
|---|---|---|
| May you see the expected figure *before* counting? | `shift.view_expected_cash` | 5.4 informed vs blind mode |
| May you see the variance *after* committing? | `cash.variance.view` | 5.4 reveal |

**Adopt `cash.variance.view` as a real, distinct capability** — the design is
right that these are separable, and separating them is what makes blind close
meaningful. Drop the SRS's `cash.view_expected` as a duplicate of
`shift.view_expected_cash`, via `PosCapability.canonical`.

### 4.3 Keyboard additions

Proposed: `Ctrl+E` export (5.5) · `Ctrl+S` save settings (5.6) · `F5` retry
failure (5.8). The handoff flags `Ctrl+S` as the one risk.

**Checked: `Ctrl+S` is not bound anywhere.** The only chord in the app is
`Ctrl/⌘+Shift+S` (setup), registered in [app.dart:62](../../lib/app/app.dart:62)
and [welcome_screen.dart:63](../../lib/features/setup/presentation/welcome_screen.dart:63).
`Ctrl+E` and `F5` are also free — the selling screen registers only F2, F4, F9,
F10 and Esc. **All three additions are clear.**

> Worth noting separately: the design system documents `F3` (repeat line),
> `F6` (discount) and `F7` (split) as part of the keyboard map, and **none of
> the three is registered** — they document features that do not exist yet.
> Wave A and Wave E are where they get bound.

### 4.4 Still not designed

Answered: **§9.1** cart density (revision 2, §3.1) · **§9.3** settings is a peer
destination · **§9.4** keep the mono table at 1366 · **§9.6** reveal gated on
`cash.variance.view`.

Still open, and neither blocks the next thing to build:

* **§9.2** — split-bill-by-item placement at 1100. **Blocks Wave E5.**
* **§9.5** — the two new table states. **Blocks Wave E3.**

Both are Wave E. Waves A and B are unblocked in full.

---

## 5. Send back to design

Revision 2 closed all four of revision 1's items. One new thing, and it is
revision 2's own rule turned back on the light theme:

1. **`accentSoft` and `warnSoft` collide in the LIGHT theme too.**
   `#FEF0D9` and `#FBEEE0` differ by (3, 2, −7) — two pale warm creams that are
   effectively the same colour on a screen. Revision 2's rule says they must
   never be within one visible step of each other **in either theme**, and the
   light pair fails it more clearly than the dark pair did.

   I did **not** change these. Unlike the dark values — which were invented for
   this app and are marked as such in `tokens.dart` — both light values come
   from the shared design system's `.theme-warm` and are used by the web repo.
   Moving one is a cross-repo decision, not a POS one.

   Suggested direction, matching what revision 2 did in dark: hold `accentSoft`
   at `#FEF0D9` (selection, chromatic) and take `warnSoft` toward a
   desaturated sand — the same "caution moves toward the page" move, in the
   other direction of lightness.

---

## 6. Build order

Nothing here is blocked by §5 — all four are refinements, not gates.

| # | Item | Depends on | Wave it unblocks |
|---|---|---|---|
| 1 | `MonoAmount` · `MonoCode` | — | **built** ✅ — [mono_amount.dart](../../lib/core/ui/widgets/mono_amount.dart) |
| 2 | `PermissionGate` | `Authorization` (exists) | **built** ✅ — [permission_gate.dart](../../lib/core/ui/widgets/permission_gate.dart) |
| 3 | `ReasonPicker` · `ReasonSheet` | `pos_reason_codes` (migration 9) | **built** ✅ — [reason_picker.dart](../../lib/core/ui/widgets/reason_picker.dart) |
| 4 | `DestructiveConfirmDialog` | 3 | **built** ✅ — [destructive_confirm_dialog.dart](../../lib/core/ui/widgets/destructive_confirm_dialog.dart) |
| 5 | `ManagerApprovalDialog` (extended `SupervisorOverrideDialog`) | 3 | **built** ✅ — [supervisor_override.dart](../../lib/features/admin/presentation/supervisor_override.dart) |
| 6 | `FailureCard` | — | **built** ✅ — [failure_card.dart](../../lib/core/ui/widgets/failure_card.dart) |
| 6a | `CartPanel` density + A8 line treatments | 4, 5 (for the actions the rows display) | A8 |
| 7 | `BlindCountDialog` | `cash.variance.view` (§4.2) | B3, B4 |
| 8 | `SettingsScaffold` · `SettingsFieldRow` · `ScopeBadge` | `pos_settings` (migration 14) | D, and B's blind-close toggle |
| 9 | `ReportFrame` | `ReportsRepository` | G |

**1, 2, 3, 4 and 6 are built** (69 tests), and **migration 9 has landed** with
the `pos_reason_codes` and `pos_order_line_events` tables the picker reads.
**5 is built too** (18 tests). Its limit strip did not need Wave C after all:
the caller composes the sentence from the figures it already holds, so the
dialog stays generic and the interim `pos_roles.max_discount_bp` columns from
migration 10 are enough to feed it.

Remaining: **7** (`BlindCountDialog`), which wants the `cash.variance.view`
capability of §4.2, and **8**/**9**, which are Waves D and G.

Two deviations from the handoff, both deliberate:

* **The PIN is one masked field, not `PinDots`.** The handoff specifies a
  masked field 48 tall in a 218px column; `PinDots` is four 52px boxes built
  for the full-width lock screen and overflows that column by 22px. Squeezing
  the shared widget would have changed the lock screen too.
* **The approved strip needs a `Done` press.** The handoff designs a state
  naming both people; showing it and closing on a timer would be worse, and
  closing instantly would skip it. `Done` is autofocused so Enter dismisses.
  If that extra keypress proves slow during service it is a design
  conversation, not something to quietly drop.

Two things the built widgets deliberately do *not* do yet, both waiting on a
wave rather than on a decision:

* `PermissionGate.forDecision` takes `deniedBehaviour` as a required argument
  because `pos_permissions.risk_level` does not exist yet (Wave C). When it
  does, the factory reads it and the argument becomes a default.
* `FailureCard` carries no copy of its own. The handoff's five cards are
  production EN + AR strings, and they go into `AppStrings` when their call
  sites land in Waves A and F — adding them now would be five sets of strings
  nothing renders.

**Where they live:** `lib/core/ui/widgets/` for 1, 2, 6 and the settings and
report frames; `lib/features/admin/presentation/` for 5, beside the dialog it
extends. Nothing in `lib/core/ui/` may import a repository — the frames take
data, they do not fetch it.

## 7. Copy

The handoff's EN and AR copy is production copy and should be used **verbatim**,
including the ten reason strings. It goes into `AppStrings`, not into
`admin_messages.dart` — these patterns are used by the selling screen, not only
by Management, and `admin_messages.dart` is already scheduled to fold into
`AppStrings` as one pass.

Arabic-Indic digits in prose (٣٠٪, ٦ أيام) with **Western digits in mono data
fields** is a rule the codebase does not currently express anywhere. It belongs
in `MonoAmount` and in the `AppStrings` number formatters, not at call sites.
