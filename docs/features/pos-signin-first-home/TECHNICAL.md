# Technical plan: sign in first, then Home — pos-signin-first-home

Status: **BUILT 2026-10-27** (plan approved 2026-10-26 with the defaults) · written 2026-10-26 · Spec: `FEATURE.md` (same folder) · Repo: `apps/xorder-pos` only · Verified against xorder-pos `5cf13cc` + 28 uncommitted files (§8) · Cloud untouched.

## 1. Discrepancies found while re-reading the code
| # | Spec said | Source says | Effect on the plan |
|---|---|---|---|
| D1 | AC-10 "the one-type branch skipping Home keeps working" | Home must now exist for a one-type branch with **no shift open** (it carries Start shift and Close the day). | Rule: after sign-in, skip Home **only when a shift is open and the branch sells one way**. A one-type branch with no shift sees Home with one action. |
| D2 | "idle lock" (Q4) | `idle_lock.dart:_lock` already signs the till out on **any** route (not welcome/setup/management) but only navigates to Lock when `needsSignIn` (a selling screen with a shift open). | Home with no shift needs an explicit `go(start)` after sign-out; otherwise the idle lock leaves an empty signed-out Home. |
| D3 | "resume after a restart goes lock → Home" (`pos-home-screen` BR-9) | Resume skips the PIN today; the lock screen supplies it. New Start sign-in supplies the PIN first, so the restart path no longer needs the lock screen. | `pos-home-screen` BR-6 and BR-9 change (documented). The business day must still open on a restart sign-in (`pos-business-day`, `lock_screen.dart:183`). |
| D4 | "supervisor can approve" a close-day | Today a **cashier** can press Start's "Close the day" and a manager can approve it with a PIN (`requestPermission`). With the button hidden from cashiers that route disappears: the manager must sign in. | **Narrows an access path**: needs your explicit OK (A3). |

## 2. Design (smallest change that meets FEATURE.md)
1. **One dialog, two modes.** `OpenShiftDialog` already contains everything sign-in needs (name + PIN pad, `signInLimiterProvider`, `signInAs`, the same error text, the same lockout). Add a parameter instead of a second copy:
   - `OpenShiftDialog.show(context)` (unchanged): name + PIN, then float. Kept so `sign_in_lockout_test` and the integration driver still compile; **no product code path uses it after this change** (listed under follow-ups).
   - `OpenShiftDialog.show(context, by: staff)`: the person is already signed in; shows only the float step.
   - `SignInDialog.show(context)`: the same PIN pane, then closes. It does **not** check `shift.open`, writes no shift, and calls `signedInStaffProvider.signIn`. If a shift is open it also runs `ensureBusinessDayProvider(staff)` (unawaited, as `lock_screen.dart:183` does).
2. **Start** becomes the signed-out door: logo, tenant, identity grid and banners stay; the primary button is **Sign in** (Enter works) and is **never** blocked by the licence. The "Close the day" button is removed. The licence banner and "Manage licence" stay.
3. **Router**
   - `afterSignIn(context)` (new): wait for order-type config as `afterShift` does; if a shift is open and the branch sells one way → `openType(single)`; otherwise → Home.
   - `afterShift` unchanged; Home calls it after a shift is opened.
   - Redirect: Home with nobody signed in → Start (all cases). `needsSignIn` keeps sale/floor (+ shift open) → Lock and **drops Home** from its set.
4. **Home** gets two states.
   - Always: tenant, "Point of sale", "Signed in as <name>", **Sign out** (signs out, goes to Start; Escape does the same).
   - Shift not open: **Start shift** (needs `shift.open`; licence-blocked → disabled "Licence required" + the existing "Cash-up and reprint … still available" help); the order-type buttons are **disabled** with the line "Start a shift to sell" (Q2); a one-type branch shows no type button, only Start shift.
   - Shift open: order-type buttons as today (keys 1–4); a one-type branch is not shown Home at all (D1).
   - **Close the day** per FEATURE BR-4 (already written and tested in the working tree).
   - The self-forward "one type → go" in `HomeScreen.build` runs only when a shift is open.
5. **Idle lock** (`idle_lock.dart`): after `signOut()`, if the till is on Home (shift open or not) → `router.go(start)`. (Corrected after review: the plan said "no shift open"; the code and Q4's default, "signs out and returns to Start", are the wider rule.)
5a. **Added after review.** The lock route unlocks to Home when no shift is open, whatever `next` says, so Lock or Switch user from Home cannot land on a sale with no drawer. `OpenShiftDialog(by:)` re-checks `shift.open`. Home does not forward while the float dialog is open.
6. **Day close dialog**: record the closer from `actingStaffProvider` (not `signedInStaffProvider`) at `day_close_dialog.dart:329`.
7. **Strings** (EN + AR, `app_strings.dart`): `signedInAs(name)`, `signOut`, `startShiftToSell`. Arabic needs a native-reader check (I will say so in the report).
8. **Close shift** is unchanged: it still signs out and goes to Start; the closer signs in again to close the day.

## 3. Stages, tests and rollback
| Stage | Change | Files | Proof | Rollback |
|---|---|---|---|---|
| S1 | Day-close actor fix | `day_close_dialog.dart` | `cash_dialogs_test`: close with `signedInStaffProvider == null` and an Admin Mode person records that person; existing cases green | revert 1 line |
| S2 | `SignInDialog`, `by:` mode, strings | `shift_dialogs.dart`, `app_strings.dart` | new `sign_in_only_test` (AC-1, AC-7 lockout parity, no shift row written, business day opened when a shift is open); `sign_in_lockout_test` still green | revert file |
| S3 | Start: Sign in button, remove Close the day, licence moves off Start | `start_screen.dart` | rewritten `start_gate_test` (sign-in not licence-gated, AC-9), `arabic_screens_test` | revert file |
| S4 | Router: `afterSignIn`, Home redirect, `needsSignIn` | `router.dart` | router tests in `home_flow_test`/`sign_in_test` (AC-6, AC-10, D1) | revert file |
| S5 | Home: two states, Sign out, Close the day | `home_screen.dart` | `home_screen_test`, `home_close_day_test`, new Home start-shift cases (AC-2, AC-3, AC-9) | revert file |
| S6 | Idle lock | `idle_lock.dart` | `idle_lock_test` new Home case | revert file |
| S7 | Fix tests that drove the old Start button | `business_day_opening_ui_test`, `theme_screens_test`, `start_database_unavailable_test`, `settings_bar_test`, `integration_test/support/till_driver.dart` | whole suite | n/a |
| S8 | Docs | `docs/features/{pos-signin-first-home,pos-home-screen,pos-business-day,pos-shifts}` + inventory | `/project-documentation update` then `validate` | n/a |

Order: S1, S2, then S3–S6 together (the Start button and the router must land at the same time, or the till has no way in), then S7.

## 4. Regressions to protect (checked by the existing suites after every stage)
- Wrong-PIN lockout shared across the three PIN doors (`signInLimiterProvider`) and no username enumeration.
- Resume after a restart: PIN asked, **same shift** (no second float), business day ensured.
- Lock at the till and idle lock with a shift open: still the lock screen, unlock returns to the sale/floor/Home as before.
- Licence: expired blocks **opening** a shift only; cash-up, reprint, Close shift and Close the day are never licence-gated.
- Seated ticket parked when leaving the sale for Home (`leaveSaleTo`), unchanged.
- Admin Mode stays separate from the till operator.

## 5. Domain lens
| Model | Effect |
|---|---|
| Café | Cashier: Sign in → Start shift → sells. One extra tap compared with today (sign in and open were one dialog), mitigated by remembering the last user name (Q3). |
| Restaurant | Manager closes the night without opening a drawer; cashiers no longer see Close the day. |
| Food truck | One person, one-type menu: same extra tap; no tables assumed; works offline (PIN verifies against the cached hash). |
| Cloud kitchen | No till? Not a POS flow; unchanged. |
No dependency on tips, aggregators, KDS, recipes, loyalty or multi-brand.

## 6. Verification commands
```
cd apps/xorder-pos && dart analyze lib test
flutter test test/features/<each file above>      # after each stage
flutter test                                       # full suite after S7
scripts/check.sh                                   # PostgreSQL suites: needs a local PostgreSQL; NOT run unless you say one is available
```
Not provable without a person: the layout on a real till and in Arabic, and an admin closing the day with no shift ever opened on a real PostgreSQL.

## 7. Approvals needed (nothing is built until you say go)
- **A1** The split of sign-in from shift-opening (shift/cash integrity).
- **A2** Changing `pos-home-screen` BR-1, BR-6, BR-9 before it ships.
- **A3** Narrowing: a cashier can no longer reach Close the day (no more "manager approves with a PIN" from the Start screen) (D4).
- **A4** The defaults for the open questions: Q2 disabled with a reason · Q3 remember the last name · Q4 idle lock signs out and returns to Start · Q5 Home with nothing permitted shows the name and Sign out · Q6 the business day still opens with the first shift.
- **A5** Editing `start_screen.dart` and `shift_dialogs.dart`, which already carry **someone else's uncommitted edits** (§8); my changes will be mixed with theirs in the working tree.
- No migration, no contract change, no commit, no push.

## 8. Tree state (rule 5)
`git -C apps/xorder-pos status --short`: 28 modified/untracked files. Unrelated to this feature and left alone: tender/financial-account work (`providers.dart`, `till_status_bar.dart`, `app_strings.dart` partly, `postgres_catalog_admin_repository.dart`, `postgres_financial_accounts_admin_repository.dart`, `catalog.dart`, `financial_account.dart`, `tender_method.dart`, `admin_repositories.dart`, `admin_messages.dart`), the stale-day banner removed from `start_screen.dart`, Esc-to-cancel in `shift_dialogs.dart`, and `business_day_opening_ui_test.dart`, `close_shift_dialog_test.dart`. `app_strings.dart` is also in that list, so my string additions will sit beside theirs. Mine, from this session and uncommitted: `home_screen.dart`, `test/features/home_close_day_test.dart`. xorder-cloud has unrelated uncommitted tender work and is not touched.

## 9. Baseline
Recorded in `TEST_REPORT.md` (the baseline run overlapped stage S1, so it is not a clean one; the final run is).

## 10. Follow-ups, not in this change
- Delete the old name+PIN+float path of `OpenShiftDialog` once its tests are ported.
- Optional auto-close of the day at a configured hour.
- Showing "Shift SHIFT-n opened by X" on Home.
