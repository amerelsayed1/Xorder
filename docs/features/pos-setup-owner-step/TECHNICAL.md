# Technical plan: setup wizard step 4, clear for any user — pos-setup-owner-step

Status: **BUILT 2026-10-27** (plan approved with the defaults) · written 2026-10-27 · Spec: `FEATURE.md` (same folder) · Repo: `apps/xorder-pos` only · Verified against xorder-pos `5cf13cc` + uncommitted work (§8) · Cloud untouched.

## 1. What the re-read of the code changed in the plan
| # | Finding | Effect |
|---|---|---|
| D1 | The wizard footer is one shared widget for every step: Back → `controller.back`, primary → `controller.next()` and enabled only by `draft.canAdvance` (`setup_wizard.dart:340-400`). For step 4 offline `canAdvance` is `bootstrapped` (`setup_state.dart:498-501`). | One primary button per screen means the footer's button must change **label and action** on step 4 (go to B, create the database, continue). I will **not** change `canAdvance`/`next()` (every existing test and step depends on them); I add a separate footer action rule. |
| D2 | `bootstrapDatabase` calls the static `LocalBootstrap.createDatabase/ensureTillRole/...` and builds its own `PosDatabase` (`setup_controller.dart:685-860`); it cannot be faked without a refactor. | The **success** of the real build stays covered by the PostgreSQL-tagged `installer_owner_test` (not run here). The UI is tested with `bootstrapped` set on the draft; the **failure → back to Screen A** path is tested hermetically by pointing the admin connection at a closed local port (a real `tcp` failure, no database needed). No refactor. |
| D3 | The setup progress store persists only the step and the `bootstrapped` flag; not the owner name, username, PIN or the admin password (`setup_progress_store.dart:50-120`, grep). | The new fields (confirm PIN, which screen) are in memory only. Nothing sensitive is newly persisted; the admin password stays unwritten. |
| D4 | `_PasswordField` is shared by other panes (connection password, manual sign-in) with `obscureText: true` and no reveal (`setup_panes.dart:1102-1184`). | Reveal is an **opt-in parameter, default off**: only this step's three secret fields get it; no other screen changes. |
| D5 | PIN: exactly 4 digits (`PinRules.length`), typed extras are dropped (`setup_controller.dart:658-668`), help says "four to twelve" (`app_strings.dart:4725`). | Fixed as FEATURE BR-4 says: the sentence and a live `n / 4` counter; the rule is not touched (Q5). |

## 2. Design (smallest change that meets FEATURE.md)
**State (`setup_state.dart`, `SetupDraft`)** — two in-memory fields, not persisted:
- `ownerPage` : `OwnerPage { databaseAccess, ownerAccount }`, default `databaseAccess`.
- `ownerPinConfirm` : `String`, default `''`.
- A computed `FooterAction { next, toOwnerPage, createDatabase, finish }` and `bool footerEnabled`:
  - step ≠ account, or not offline-first-install, or already `bootstrapped` → today's behaviour exactly (`next`/`finish`, enabled by `canAdvance`);
  - offline, not bootstrapped, `databaseAccess` → `toOwnerPage`, enabled when `adminDatabasePassword.isNotEmpty`;
  - offline, not bootstrapped, `ownerAccount` → `createDatabase`, enabled when name, username, PIN and confirm are all non-empty (the specific problems — mismatch, short PIN — are said on press, as `bootstrapDatabase` already does for the others).
- `canAdvance`, `next()`, `visibleSteps`, the step enum and the persisted progress are **unchanged**.

**Controller (`setup_controller.dart`)**
- `setOwnerPinConfirm(String)` (digits only, capped at `pinLength`, same as `setOwnerPin`).
- `showOwnerPage(OwnerPage)`; `back()` on step 4 offline, not bootstrapped, page B → page A (otherwise as today); `next()` entering step 4 resets to page A unless already bootstrapped.
- `bootstrapDatabase`: before connecting, a mismatch (`ownerPin != ownerPinConfirm`) sets `pinsDoNotMatch` and builds nothing (BR-5). On failure, errors about the **administrator account or connection** — `TillRoleRefused`, `PosDbException` with `auth`, `missingRole`, `permissionDenied`, `dns`, `tcp`, `tls` — also set `ownerPage = databaseAccess` so the error is where the field is (BR-7); all other failures stay on page B. Typed values are kept (they are in the draft).

**Panes (`setup_panes.dart`)**
- `_FirstInstallFields` renders page A or B (or the existing "machine now has a database" card once `bootstrapped`, restyled in plain words, BR-6).
- Page A: heading, the plain explanation, the administrator password with reveal, the account name as a small secondary line.
- Page B: owner name, username (prefilled `owner`, mono, left-to-right), sign-in PIN with reveal and `n / 4`, confirm PIN with reveal and an inline mismatch line.
- `_PasswordField` gets `revealable` (default false) with a toggle that has an accessible label (`Show` / `Hide`) and a stable key `'<field>:toggle'`.
- The separate "Build the database" button is removed.

**Footer (`setup_wizard.dart`)** — label and action by `draft.footerAction`; the spinner, Back and the rest are untouched. Labels: "Continue" (page A and after the build), "Create database and continue" on page B (AR equivalents), "Open the till" on the last step as today.

**Strings (`app_strings.dart`, EN + AR)** — new: screen A/B headings, the plain "used once, not saved" explanation, owner name / username / sign-in PIN / confirm PIN labels, exactly-N-digits help, mismatch message, Show / Hide, create-database label, "Database created." Old step-4 strings no longer used are removed in the same change if nothing else references them (checked before deleting). Arabic needs a native read.

## 3. Stages, tests and rollback
| Stage | Change | Files | Proof | Rollback |
|---|---|---|---|---|
| S1 | State + controller (page, confirm, footer rule, back, mismatch, error routing) | `setup_state.dart`, `setup_controller.dart` | new `setup_owner_step_test.dart` controller tests: footer rule table, back/next, mismatch builds nothing, closed-port failure returns to page A with values kept; `setup_wizard_test`, `setup_persistence_test` unchanged and green | revert 2 files |
| S2 | Strings EN/AR | `app_strings.dart` | `localisation_test` (parity), a new test that no step-4 string contains "PBKDF2" or "four to twelve" | revert hunks |
| S3 | Panes: two pages, reveal, counter, inline mismatch | `setup_panes.dart` | widget tests AC-1,2,3,8 and RTL/overflow AC-7 at 1024×700 | revert file |
| S4 | Footer | `setup_wizard.dart` | widget tests AC-5 (with `bootstrapped` set), AC-8; existing wizard widget tests | revert file |
| S5 | Update tests that drove the old single screen | `setup_wizard_test.dart` and any other found | full suite | n/a |
| S6 | Docs | `docs/features/pos-setup-owner-step/*`, inventory row | `verify.sh` | n/a |

Order S1, S2, then S3 and S4 together (the pane and the footer must land together or the step has no way forward), then S5.

## 4. Regressions to protect
- Cloud, child-tablet and pairing-code step 4; every other step's Back/Continue; the licence-first order; `canAdvance` semantics (existing tests assert them).
- Persisted progress: no new persisted field; a restart on step 4 comes back on page A with empty password fields, as it does today.
- The admin password is never written: the draft holds it in memory only; clearing on success/leaving step 4 is **UNVERIFIED** today and the plan keeps behaviour as is (not widened).
- The bootstrap is untouched: same order, same upserts, same refusals.

## 5. Domain lens
| Model | Effect |
|---|---|
| Café, food truck (owner installs alone, one till, offline) | The main beneficiary: plain words, a PIN they can type back. |
| Restaurant (technician installs) | Screen A is for the technician (database password); screen B can be handed to the owner. |
| Cloud kitchen | Not applicable: cloud setup skips this step. |
No dependency on tips, aggregators, KDS, recipes, loyalty or multi-brand.

## 6. Verification commands
```
cd apps/xorder-pos && flutter analyze
flutter test test/features/setup_owner_step_test.dart test/features/setup_wizard_test.dart test/features/setup_persistence_test.dart test/features/cloud_setup_collapsed_test.dart test/core/localisation_test.dart
flutter test                      # whole suite
scripts/check.sh                  # PostgreSQL suites: NOT run unless you say a local PostgreSQL may be used
```
Not provable without a person: the whole step in Arabic on a real till, and the Arabic wording.

## 7. Approvals needed (nothing is built until you say go)
- **A1** The shape of `SetupDraft`: two new in-memory fields and a computed footer rule (the only "state shape" change; nothing persisted).
- **A2** The shared wizard footer now chooses its label and action by `footerAction` (default behaviour unchanged for every other step).
- **A3** `_PasswordField` gets an opt-in reveal control used only on this step.
- **A4** The defaults for the open questions: **Q1** two screens inside step 4 · **Q2** no "test connection" button · **Q3** labels "Owner name", "Username", "Sign-in PIN" · **Q4** a live `n / 4` counter plus the exactly-4 sentence (no change to the rule) · **Q5** the PIN stays exactly 4 digits.
- **A5** Editing `app_strings.dart`, which already carries other uncommitted work (mine from the sign-in feature and others'); my hunks will sit beside them.
- No migration, no contract change, no database change, no commit, no push.

## 8. Tree state (rule 5)
`git -C apps/xorder-pos status --short`: about 53 entries, mostly the earlier sign-in work (`router.dart`, `home_screen.dart`, `start_screen.dart`, `shift_dialogs.dart`, `idle_lock.dart`, `day_close_dialog.dart`, `app_strings.dart`, many tests, `scripts/check.sh`, `tool/`) plus others' tender/financial-account work and a stale-day banner removal. **At planning time none of `lib/features/setup/` or `lib/data/config/` was modified; they now carry this feature's changes (see `CHANGELOG.md`).** `app_strings.dart` is shared with the earlier work. xorder-cloud has unrelated uncommitted work and is not touched.

## 9. Baseline
Last full run before this change: `+3438 ~81: All other tests passed!`, exit 0 (2026-10-27, after the sign-in work). The run after the change is in `TEST_REPORT.md`.

## 10. Follow-ups, not in this change
- A "test connection" check on screen A (Q2).
- The `XOrder_Setup_Wizard_README.md` redesign (its own description and decisions).
- Making the same plain-words pass on the other wizard steps (connection password, licence).
