# Test plan — pos-signin-first-home

Updated 2026-10-27 · Framework: `flutter test` (widget and router tests with fake repositories, 1440×900; no database). PostgreSQL-tagged suites self-skip without `POS_PG_*`. Executed results are in `TEST_REPORT.md`, not here.

## Criterion → test
| Criterion | Test (file: name) | Status |
|---|---|---|
| AC-1 sign in with no shift row | `sign_in_only_test`: a right name and PIN signs in and opens no shift · `signin_first_flow_test`: signing in with no shift open lands on Home… · `start_gate_test`: a valid licence lets somebody sign in | automated |
| AC-2 Start shift only for `shift.open`; float-only dialog | `home_screen_test`: Start shift is offered… · somebody who may not open a shift is told so… · Start shift asks for the float only… · `sign_in_only_test`: open shift for somebody already signed in | automated |
| AC-3 Close the day by permission and open day | `home_close_day_test` (4 cases) · `signin_first_flow_test`: a cashier is never offered Close the day | automated |
| AC-4 manager closes with no shift; closer recorded | `signin_first_flow_test`: a manager closes the day without ever opening a shift · `cash_dialogs_test`: the closer is the person at the till / …the administrator is the closer, not nobody (fails without the fix, checked) | automated; real PostgreSQL close with no shift: **not run** |
| AC-5 open shift is a blocker, force needs reason | `cash_dialogs_test`: the day close group (existing, unchanged) | automated (existing) |
| AC-6 Home with nobody signed in → Start; selling screens with a shift open → lock | `home_flow_test`: Home with nobody signed in is Start… · `sign_in_test`: an unattended till is sent to sign in (sale, floor; Home is not one) | automated |
| AC-7 lockout parity | `sign_in_only_test`: five wrong PINs shut it… · `sign_in_lockout_test` (existing, the shared limiter) | automated |
| AC-8 Arabic / small window | `home_screen_test`: in Arabic… (shift open) · before a shift, in Arabic… · `arabic_screens_test`: the start screen… | automated; **a person must look at RTL on a real till** |
| AC-9 lapsed licence: sign in and close the day still possible | `start_gate_test`: an expired licence blocks the next shift, not signing in… · `home_screen_test`: a lapsed licence blocks the shift… | automated |
| AC-10 existing flows | `home_flow_test` (resume helper now signs in; restart path; floor/sale Escape; one-type skip) · `idle_lock_test` · `business_day_opening_ui_test` (day opens before the shift; lock-screen resume) · full suite | automated |
| Restart with shift open: business day ensured on sign-in | `sign_in_only_test`: with a shift already open, the business day is made sure of · …with no shift open, no day is opened | automated |
| Idle lock on Home | `idle_lock_test`: five idle minutes on the home screen sign the till out and return to Start | automated |
| Sign out | `home_screen_test`: Sign out… / Escape does the same · `signin_first_flow_test`: Sign out on Home returns to Start | automated |

## Gaps (said, not hidden)
- **Integration driver** `integration_test/support/till_driver.dart` was updated to the two-step flow but **not run** (needs a real PostgreSQL and the platform). It also types no user name, as before this change.
- **Real PostgreSQL**: day close with no shift, and `closed_by` for an Admin Mode closer, are exercised with fakes only.
- **Layout, RTL and the feel of the extra tap** need a person on a real till.
- **Admin Mode path** (closing from the back office) is not built by this feature; only the dialog's actor fix is tested.
- `Authorization.check(null)` / `requestPermission` with nobody signed in (the old Start button) was never exercised and the button is gone.
