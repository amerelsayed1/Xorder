# Test report — pos-signin-first-home

Date 2026-10-27 · Environment: macOS, Flutter widget and unit tests with fake repositories (no database), xorder-pos `5cf13cc` + uncommitted work (this feature's and unrelated, see TECHNICAL §8). Planned tests: `TEST_PLAN.md`.

## Commands and results (real output, abridged)
| Command | Result |
|---|---|
| `flutter test` (baseline, before stage S2; overlapped the S1 edit, so not a clean baseline) | `+3406 ~81: All other tests passed!`, exit 0 |
| `flutter test` after S6 (first run, with the old tests) | 29 failures, all tests that drove the old Start button (start_gate 7, home_flow 17, home_screen 3, sign_in 1, idle_lock 1) — fixed one file at a time |
| `flutter test` after S6 (second run) | `+3427 ~81 -5`: arabic_screens_test 2, business_day_opening_ui_test 3 — fixed |
| `flutter test` after the first fixes | `+3433 ~81: All other tests passed!`, exit 0 |
| independent review (read-only code-reviewer), then fixes | 1 HIGH, 2 MEDIUM, others; fixed: Lock/Switch user from Home unlocks to the sale with no drawer; `shift.open` re-checked in `by:` mode; Home forwarding under the open dialog; last name offered; sync nudge on a wrong PIN |
| **`flutter analyze`** (final) | `No issues found!` |
| **`flutter test`** (final, whole suite) | **`+3438 ~81: All other tests passed!`, exit 0** (0 failures; the 81 skipped are the `integration`-tagged PostgreSQL suites, which self-skip without `POS_PG_HOST`) |

## Tests added or changed by this feature
New: `sign_in_only_test` (10), `signin_first_flow_test` (8), `home_close_day_test` (4); `cash_dialogs_test` +2 (closer); `home_screen_test` +8 (no-shift state, Arabic, sign out); `start_gate_test` rewritten (8 about sign-in and the licence); `home_flow_test`, `idle_lock_test`, `sign_in_test`, `arabic_screens_test`, `business_day_opening_ui_test` updated for the new door.
Mutation checks (the test fails without the fix, passes with it): the closer fix in `day_close_dialog.dart`; the lock-route unlock-to-Home rule; the `shift.open` re-check in `OpenShiftDialog(by:)`.

## Not run, or not provable here (said plainly)
- **`scripts/check.sh` and every PostgreSQL-tagged suite**: not run (no local PostgreSQL was used). Day close with no shift and the closer's `closed_by` are proved with fakes only.
- **`integration_test/` (the assembled app)**: `till_driver.dart` was edited to the two-step flow but **not run**; it also types no user name, as before.
- **A person on a real till**: layout, Arabic RTL, the feel of the extra tap, the account menu (Lock, Switch user) on the real window bar.
- **Arabic wording** of the four new strings needs a native reader.
- **Cloud**: not touched and not tested.
- The baseline was taken while an edit was in progress; the comparison that matters is the final run, which is a full pass.
