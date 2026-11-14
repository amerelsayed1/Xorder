# Test plan — pos-setup-owner-step

Updated 2026-10-27 · Framework: `flutter test` (controller and widget tests, fakes, no database). Executed results are in `TEST_REPORT.md`.

## Criterion → test
| Criterion | Test (file: name) | Status |
|---|---|---|
| AC-1 screen A: one password, plain "used once, not saved" | `setup_owner_step_ui_test`: asks for one password, and says in plain words why | automated |
| AC-2 Continue → screen B inside the same step | `setup_owner_step_ui_test`: Continue goes to the owner's screen, in the same step · `setup_owner_step_test`: pressing it on page one moves on, in the same step | automated |
| AC-3 two different PINs build nothing | `setup_owner_step_test`: two different PINs build nothing, and say so · `…_ui_test`: a PIN typed differently the second time is said at once… (fails without the rule, checked) | automated |
| AC-4 no "PBKDF2" / "four to twelve" / old labels; "exactly 4" sentence, both languages | `…_ui_test`: neither screen mentions a hash, a role or "four to twelve" (en, ar) · the PIN sentence says exactly four, in Arabic too · `localisation_test` parity | automated |
| AC-5 create → "Database created." → Continue | `…_ui_test`: once the database exists, it says so, and the same button is Continue again (state preset) · the real build: `test/data/installer_owner_test.dart` | UI automated; **real build not run** (PostgreSQL) |
| AC-6 wrong administrator password / connection → back to screen A, typed values kept | `…_test`: it is the first page again, with the error there and nothing typed lost · `…_ui_test`: the first screen comes back with the error… (real refused connection, closed port; fails without the routing, checked) · `…_test`: which failures send the person back (every `PosDbFailure`) | automated for `tcp`; `auth` by the routing table only |
| AC-7 Arabic at 1024×700, no overflow, technical values left to right | `…_ui_test`: the smallest window, in Arabic (both screens) | automated; **a person on a real till** |
| AC-8 one primary button per screen | `…_ui_test`: one primary button, and no "Build the database" beside it · `setup_wizard_test`: an offline till creates its first administrator, not a login | automated |
| AC-9 other step-4 variants, step order, saved progress unchanged | `setup_wizard_test`, `setup_persistence_test`, `cloud_setup_collapsed_test`, `setup_typing_test` (starts on the owner's screen) · `…_test`: other steps and other modes are exactly what they were | automated (existing suites green) |
| AC-10 the real build still creates the database and owner | `test/data/installer_owner_test.dart` (supplies the confirmation now) | **not run** (needs `POS_PG_HOST`) |
| Show/Hide on the password and both PIN fields | `…_ui_test`: the password can be shown and hidden again · the PIN fields can be shown too | automated |
| Back keeps what was typed; Back from screen A is the previous step | `…_test`: Back (both cases) · `…_ui_test`: Back goes to the first screen with everything still typed | automated |
| Arriving at the step starts on screen A | `…_test`: Continue from the connection step starts on the first page | automated |
| Empty administrator password allowed | `…_test`: page one: on to the owner, even with no password · `…_ui_test`: one primary button… (enabled when empty) | automated |
| A second press while the build runs starts nothing | `…_test`: a second press while the build runs starts nothing | automated |

## Gaps (said, not hidden)
- The real database build, and so the success path and `OwnerCreated` / `OwnerAlreadyHere` / `ownerAlreadyExists`, are PostgreSQL-only and **not run**.
- A real `auth` failure and `TillRoleRefused` are covered by the routing table, not by a live refusal.
- A non-admin failure staying on screen B is covered by the routing table only.
- Real-till layout and feel, Arabic wording by a native reader.
