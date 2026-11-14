# PIN entry from the physical keyboard — technical plan (approved 2026-10-28, with the hint; implemented, uncommitted; see TEST_REPORT.md)
Status: implemented, uncommitted · 2026-10-28 · Spec: `docs/harness/investigations/xorder-issues-readme-2026-10-28.md` section A (README XORDER-012; proposed id XORD-038) · Repo: `xorder-pos` only · Verified against `xorder-pos` `09b47ec` (branch `feat/day-order-number`, one unrelated uncommitted file `test/data/local_bootstrap_test.dart`). Work will go on a **new branch off `main`**, not on the order-number branch (the files do not overlap).

## 1. Root cause re-confirmed on the current tree
`PinPad` takes digits, numpad digits and Backspace through a `Focus(onKeyEvent)` (`lib/core/ui/widgets/pos_widgets.dart:401-451`) and only while it holds focus. The lock screen gives it focus only when a name was remembered (`autofocus: _prefilled`, `lock_screen.dart:330`), a tile is tapped (`_pick`, `:135`) or Enter is pressed in the name box (`:317`); otherwise the username `TextField` keeps it (`:315`).
Probe run today (throwaway test, deleted): after typing a name and **mouse-tapping an on-screen key, focus stays outside the pad**; after **Tab** from the name box focus moves into the pad and the four digits unlock. So Tab already works; the tap path does not.

## 2. Decision needed first (cannot be settled in code)
A username may itself contain digits (`^[a-z0-9._-]+$`, cloud `StoreStaffRequest`), so while the name box has focus a typed digit cannot be told from a PIN digit. The fix therefore **cannot make "type name, then type PIN" work without one handoff key** (Enter or Tab). Options: (a) recommended: fix what is wrong (taps claim focus), add a one-line hint under the name box ("Press Enter or Tab, then type the PIN"), keep Enter/Tab as the handoff; (b) also auto-hand-off when the typed text exactly matches a listed username: rejected, a username that is the prefix of another ("amer", "amer2") would be cut off; (c) focus the pad first when tiles are shown: rejected, a PIN with no name fails and counts against the attempt limiter.

## 3. Change (option a)
1. **`PinPad` key taps claim focus** (`pos_widgets.dart:470-486`, `_key`): in `onTap`, `Focus.of(context).requestFocus()` before `onDigit`/`onBackspace`. No new state, no signature change; every pad (lock, shift open, supervisor override) gets it.
2. **Hint** under the lock screen's and shift dialog's name box: one new string `pinTypeHint` (en, ar) in `app_strings.dart`. Wording needs the owner's read. (Skip if you choose no hint.)
3. **Nothing else**: auto-submit at four digits, the attempt limiter, masking and "PIN never logged" are untouched; Enter-to-submit is moot (the PIN submits itself).
4. Shift-open dialog (`shift_dialogs.dart:294`): same widget, so step 1 fixes it; Enter already calls `nextFocus()` (`:287`); covered by a new test.
5. Supervisor override (`supervisor_override.dart:631`): autofocus true, no name box; **probe only**, fix only if the test fails.

## 4. Tests (all `flutter test`, no database)
In `test/features/sign_in_test.dart` (harness `pumpLock`): (T1) no remembered name, name typed, tap one key, then keyboard digits finish the PIN and unlock (fails today); (T2) Tab then top-row digits unlock; (T3) Tab then numpad digits unlock; (T4) Backspace removes the last digit; (T5) a fifth digit is ignored; (T6) letters are ignored by the pad once it has focus; (T7) the hint is shown in en and ar. For the shift dialog: same T1 and Enter-handoff cases in its existing test file (`test/features/` shift dialog tests, to locate). Supervisor override: one keyboard-digit case. Mutation check: remove the `requestFocus` and confirm T1 fails.
Commands: `cd apps/xorder-pos && flutter analyze && flutter test test/features/sign_in_test.dart test/features/manager_approval_test.dart test/features/management_gate_test.dart`, then the whole `flutter test`.

## 5. Impact, risk, rollback
Venue models: every desktop till (café, restaurant, truck, cloud kitchen); cashier speed at shift start and on a lock. No server, schema, contract or permission change; nothing for `xorder-cloud`. Risk: a tap now moves focus off the name box, so a cashier who tapped a key and then kept typing their *name* would type into the pad (letters are ignored): acceptable, they had started the PIN. Rollback: revert one commit.

## 6. Approvals needed
None of the gated kinds (no migration, order state, contract or permission change). **Your go is needed on this plan**, and answers to: hint yes/no and its wording; confirm that the name box still needs Enter/Tab before the PIN.

## 7. Not in scope
Dark-mode toggle (XORDER-013, skipped by your choice), the other README items, any change to the PIN length or the sign-in rules.

## 8. As built (2026-10-28)
Branch `fix/pos-pin-keyboard` (off `main`). Tracker id: **XORD-037** (the report proposed 038; 037 was free because the unrelated "merge identical items across rounds" item was never filed). Changes: `lib/core/ui/widgets/pos_widgets.dart` (a key tap calls `Focus.of(keyContext).requestFocus()`, inside a `Builder` because the pad's own context sits *above* its `Focus`: my first attempt used the wrong context and the new test caught it; `UsernameField.pinHint`), `lock_screen.dart` and `shift_dialogs.dart` (`pinHint: true`), `app_strings.dart` (`pinTypeHint`, en and ar; the Arabic wording is mine and needs the owner's read). The supervisor dialog needed no change: `manager_approval_test.dart` "digits type the PIN" already covers it. Admin sign-in and force-reset use `UsernameField` too, with passwords, so they do **not** show the hint (default off).
