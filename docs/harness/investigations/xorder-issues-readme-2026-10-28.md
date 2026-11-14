# XORDER_ISSUES_README (2026-10-28) — root causes for the reported POS/Back Office defects

Status: investigated · 2026-10-28 · Confidence: per item below · Verified against: `xorder-pos` `c67c754` (+ one uncommitted test file, `test/data/local_bootstrap_test.dart`, not mine) · `xorder-cloud` `775bf0f` (read only; its tree also has uncommitted financial-account edits, not touched).

## 0. ID collision (read first)

The README's `XORDER-007…014` are "conversation-local" and **collide with different, existing findings** in `docs/qa/XORDER_QA_FINDINGS.md` (for example XORD-008 there is "Back Office permission", XORD-012 is "deleted menu items remain visible", XORD-011 is "owners create roles"). That file currently ends at **XORD-035**. This report uses the README titles. Proposed new ids (not added to the QA file; investigation only): 008 → **XORD-036** (order number) and **XORD-037** (merge across rounds), 012 → **XORD-038**, 013 → **XORD-039**, 007 → **XORD-040**, 011 → **XORD-041**. Needs the owner's OK. Related existing items: XORD-015 (accounts), XORD-022-D/E (menus, dropdowns), XORD-027/028 (tax).

Scope covered: 008, 012, 013, 007, 011 (bugs/validation) and the current state of 009, 010, 014 (features). Nothing was fixed.

---

## A. XORDER-012 — physical keyboard does not enter the PIN  · Confidence: **confirmed** mechanism, **unproven** that it is the reporter's exact screen

### 1. Symptom
Staff login screen (four dots plus on-screen keypad): digit keys on a physical keyboard do not fill the PIN.

### 2. How it was reproduced
A throwaway widget test (copy of the `test/features/sign_in_test.dart` harness, 1440×900, fake repositories) was run and then **deleted**; `git status` afterwards shows only the pre-existing `local_bootstrap_test.dart` change. Command: `flutter test test/zz_probe_pin_test.dart`. Real output:

```
A: fresh lock, no remembered name, digits typed at once  -> unlocked=false
B: name typed, Enter, then digits                        -> unlocked=true
C: name typed (no Enter), mouse tap one key, then keys   -> unlocked=false
D: tile tapped, then NUMPAD digits                       -> unlocked=true
```

### 3. Root cause
The key handling **exists**: `PinPad` wraps its grid in a `Focus(onKeyEvent: …)` that accepts top-row digits, numpad digits and Backspace/Delete (`lib/core/ui/widgets/pos_widgets.dart:401-451`). It only receives keys when it holds keyboard focus. The lock screen gives focus to the pad **only** when a name was remembered (`autofocus: _prefilled`, `lock_screen.dart:330`), when a name tile is tapped (`_pick`, `:135`), or when Enter is pressed in the name field (`onSubmitted: _pad.requestFocus`, `:317`). In every other case focus stays in the username `TextField` (`autofocus: !_prefilled`, `:315`), which is a sibling, not a descendant, of the pad's `Focus`, so digits go to the name box and not the PIN. Tapping an on-screen key does not move focus to the pad (case C: one tap, then the keyboard, never completes).

So: first lock after a fresh start (no remembered name), or a roster with no tile tapped, or a name typed and a PIN started without pressing Enter. Cause = focus ownership; symptom = "keyboard does nothing" (digits actually land in the name field). Contributing: the existing tests cover only the prefilled and tile paths (`sign_in_test.dart:250-262`), never A or C, and the pad's mouse taps never claim focus.

### 4. Evidence and alternatives ruled out
- Not a missing key map: B and D pass with top-row and numpad digits.
- Not `KeyDownEvent`/held-key handling (comment at `pos_widgets.dart:433-437`; B/D show one digit per press).
- A test cannot show the digits in the text field (test key events do not drive text input), so "digits land in the name box" is inferred from the focus tree, not observed. Cheap confirmation: run the app, first lock, type 1234.
- **Not examined:** the other two pads. `shift_dialogs.dart:294` (`autofocus: false`, Enter in name field calls `nextFocus()`) has the same shape and is **likely** the same problem; `supervisor_override.dart:631` (autofocus true, no name field) was not probed. The README does not say which dialog; it says "staff login", which I read as the lock screen.

### 5. Impact
POS on Windows/macOS desktop, every venue model; cashier speed at shift start. No security effect: the PIN is not logged and a miss does not count as an attempt.

### 6. Fix options
1. Narrowest: on the lock screen move focus to the pad as soon as the name is non-empty and the user leaves the field (Tab/Enter/tile/tap on a key), and make pad key taps call `focusNode.requestFocus()`. Trade-off: a user who types the name and then digits without Enter still types digits into the name; also add a small "Enter to continue" cue.
2. Alternative: one `Focus` ancestor over name field + pad that routes digits to the pad only when the name field is empty-or-not-focused. More logic, riskier for names that contain digits (usernames allow `0-9`).
Must not change: auto-submit at 4 digits, attempt limiter, PIN never logged.

### 7. Tests the fix needs
In `test/features/sign_in_test.dart`: cases A and C above (no remembered name; name typed then Tab/Enter then top-row and numpad digits; mouse tap then keyboard; Backspace; 5th digit ignored); equivalent for `shift_dialogs`. Run `flutter test test/features/sign_in_test.dart test/features/manager_approval_test.dart test/features/management_gate_test.dart`.

### 8. Approvals
None (UI only).

### 9. Open
Which dialog the reporter used; whether Arabic-layout keyboards deliver `digitN` logical keys (Arabic-Indic digits come as the same physical keys, **UNVERIFIED**); the README's "Enter submits a complete PIN" is moot because the PIN submits itself at 4 digits.

---

## B. XORDER-008 — order numbers and cross-round lines  · Confidence: **confirmed** (by reading; no run needed)

### B1. Order number `MAIN-2026-000001`
- **Cause (by design, not a defect of the code):** `formatInvoiceNumber` returns `'$prefix-$period-${value.padLeft(6,'0')}'` (`lib/data/postgres/postgres_orders_repository.dart:455-460`). Numbers come from `pos_invoice_sequences` keyed `(restaurant_id, branch_id, period=year)`, row-locked with `FOR UPDATE` (`:402-450`, `migrations.dart:36`). The prefix is the branch code (`local_bootstrap.dart:382`). `invoice_number` is `text`, `UNIQUE (restaurant_id, branch_id, invoice_number)` (`migrations.dart:52,68`). The cloud also returns a `server_invoice_number`, which order history prefers over the local one (`postgres_order_history_repository.dart:81`).
- **Consequence for the ask:** this string is the **legal invoice number** a tax authority may read (the code's own comment). A bare `1,2,3` customer number is a *second* number, not a reformat; the sequence resets each year and per branch, so a plain integer would restart at 1 every January. Decision needed (README open decision 1): scope and reset. Recommend a separate per-branch, per-business-day or per-shift display number kept beside the invoice number, not replacing it.
- **Open:** whether Egypt e-invoicing (ETA, in the inventory) constrains the invoice-number format — **UNVERIFIED**, ask the owner/accountant.

### B2. Identical items in later rounds are separate lines
- **Cause (deliberate rule):** `TicketEngine.addLine` merges only into **draft** lines; lines already sent keep their own line "so the printed round and the bill stop agreeing" otherwise (`lib/domain/services/ticket_engine.dart:293-327`). The line key is `productId:sorted-modifier-ids` (`ticket.dart:239-244`); round is a per-line `roundNumber`. The receipt builders then list lines one-for-one: `receipt_data.dart:134-143` (live) and `:214-223` (reprint), with no grouping.
- **Symptom:** Mango Juice ×1 (round 1) + ×1 (round 2) prints as two lines.
- Mapping to the ask: merge **at presentation only** (receipt, invoice preview, summary), grouping by product, modifiers, unit price and discount, summing quantity and line total; keep stored lines/rounds untouched for kitchen and audit. The kitchen already prints per round, so "send only new quantities" is the current behaviour (not re-verified by test; check `roundsSent`, `ticket.dart:621,660`).
- Money risk: grouping must sum **line totals** (not qty × price) so per-line rounding and line discounts stay identical to `Ticket.totals`; totals must be unchanged by the change. A voided or repriced line (`isVoided`, `wasRepriced`) must not merge into a live one.

### Impact
Restaurants (rounds) mainly; cafés rarely. Receipts, reprints, and anything built on `ReceiptData`. No stored data is wrong.

### Fix options / tests / approvals
Merge in a pure function used by both `ReceiptData` factories (narrowest, no schema change). Test in `test/features/receipt/` (rounds 1+1+2, different modifiers, different price, voided line, totals unchanged, reprint equals live). Number change: **needs approval** (invoice numbering = order integrity; migration for a new column if a separate display number is chosen; cloud contract `server_invoice_number` must not change shape).

---

## C. XORDER-013 — dark-mode shortcut in the Settings dropdown  · Confidence: **confirmed**

- **Where:** `lib/app/app.dart:~447-465`, a `MenuButton` showing `strings.switchToDark/switchToLight` with a moon/sun icon that calls `brightnessProvider.notifier.toggle(showing)`. The Appearance pane exists (`ManagementPane.appearance`, `management_screen.dart:353,396`).
- **This is not a defect, it is a deliberate choice** recorded in the code (language/theme are reachable without Admin Mode; QA §XORD-018 notes "deliberate: reachable without Admin Mode") and XORD-022-D lists "toggles … not done" as still open.
- **Trade-off:** removing the row means a cashier (no Admin Mode, so no Settings → Appearance) **cannot change the theme at all**. Decide: remove for everyone, remove only for people who can reach Appearance, or move to the account menu. Also remove the now-unused `dark/showing` locals and check the divider after the language row (`app.dart:~440-470`).
- Test: `test/features/settings_bar_test.dart` (pins the current menu; will need a deliberate edit). Approvals: none.

---

## D. XORDER-007 — dropdown padding  · Confidence: **likely** (static survey only; not seen in a running app)

- **Cause:** there is **no shared dropdown component** in the POS: about 27 raw `DropdownButton`/`DropdownMenu`-family uses across `management_staff_pane.dart` (10), `order_history_screen.dart` (4), `shift_history_bits.dart` (4), `management_terminal_pane.dart` (4), `management_combos_pane.dart` (4), plus theme (`theme.dart` has no dropdown theme beyond the no-hover rule). Each instance sets its own padding. The cloud web app uses native `<select>` in many places (`RestaurantForm.vue` 6, `LicencesList.vue` 4, `PurchaseOrderForm.vue` 4, `SupplierPaymentForm.vue` 4, `ReportFilters.vue` 4, …) with `packages/ui` offering no select/dropdown component (`ls web/src/components` shows none).
- Same as XORD-022-E (dropdown design), which is "Not looked at in a running app". Which instances are actually off was **not measured**.
- Fix: one POS `PosDropdown` wrapper + a Vue select style token; migrate by area. Tests: golden/widget measurement at 1440×900 in en and ar. Approvals: none. Risk: large surface, do it per screen.

---

## E. XORDER-011 — "Code" max length in Add/Edit User  · Confidence: **unproven** which field

- No field named **Code** exists in the staff forms I found. The login identifier is **`username`**: cloud `StoreStaffRequest`/`UpdateStaffRequest` allow `min:3 max:150 regex:/^[a-z0-9._-]+$/` (`apps/api/app/Http/Requests/Dashboard/`), the POS add-user dialog (`management_staff_pane.dart:1437-1484`) has a plain `TextField` with **no length limit** (only trim/lowercase and non-empty), and the PIN is fixed at 4 digits (`StaffView.vue:288,296`, `maxlength="4"`). If "Code" means username: POS has no limit and cloud allows 150. If it means the PIN, it is already exactly 4.
- Proposed 10 is **not** confirmed. Existing usernames may exceed 10 (cannot check data); enforce on new input first, never truncate silently. Needs the owner's answer to: which field, which max, which characters.
- Tests when decided: cloud `Feature` request test (reject 11 chars, accept 10, existing longer value on update unchanged unless the field is edited); POS widget test for `LengthLimitingTextInputFormatter` incl. paste. Cloud change is additive validation, but any push to `xorder-cloud` `main` auto-deploys: `/release-check`.

---

## F. State of the feature items (no root cause; for planning)

- **XORDER-009 financial account at payment:** cloud/POS stage 1 only (accounts and default per payment method/branch, XORD-015). `payment_screen.dart` does not mention an account (only `TenderKind.account` "on account" is refused at `:114,:142`). Stage 2 (account on each payment, override, split) is not started.
- **XORDER-010 Main/Sub device:** partly present. `lib/core/config/deployment.dart:120-130` defines a device role (`main_device`, read from `install-role.json` by `deviceRoleProvider`), and setup strings exist (`stepMainDevice`, `mainDeviceHelp`). Whether the wizard offers the choice end to end and what a Sub Device does was **not verified**; run `/develop-feature`.
- **XORDER-014 tax/service:** exclusive per-group tax works; VAT=0 bug fixed (XORD-027); inclusive pricing exists in the engine/codec/reports but **no screen sets it** and cloud never sends `tax_mode` (XORD-028). The README's worked example (114 → 100 + 14; exclusive 114 → 15.96) matches the stated formulas, but the tax base, service-in-VAT and rounding rules are the open accounting decisions.

## Blast radius summary
Only A and B2 have a code path to change soon (focus handling; receipt grouping). B1, C, E need an owner decision first. D is a survey, not yet a defect list. No data is wrongly stored by any of these.

## Docs gaps
`docs/FEATURE_INVENTORY.md` has `pos-pin` (drafted) and `pos-receipts-printing` (UNVERIFIED); neither mentions the focus rule or round grouping. `pricing-tax-tenders` and `pos-sales` modules are "pending".

## Next action
Owner decisions: (1) accept the new ids; (2) order-number scope and whether it is a separate display number; (3) dark-toggle for cashiers; (4) which field "Code" is and its max. Then `/implement` for A (this report) and B2.
