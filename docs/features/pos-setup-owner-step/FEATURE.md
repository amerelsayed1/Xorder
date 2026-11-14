# Setup wizard, step 4 "First manager": clear for any user — pos-setup-owner-step

Status: **built, uncommitted** (2026-10-27) · written 2026-10-27 · Source: the owner, this session, shown the step 4 screen (offline first install): "I don't like this. It's not good and clear for any user"; then `/develop-feature for the above version`, meaning the two-screen redesign proposed in the previous message · Verified against: xorder-pos `5cf13cc` + uncommitted work (not this feature's), xorder-cloud `775bf0f` (not touched)

> "The above version" is taken to be the proposal in my previous message: split the screen into **Database access** and **Create the owner account**, plain words, one primary button per screen, a show/hide control, a confirm-PIN field, no jargon. If you meant something else, say so before `/implement`.

## 1. Summary
Step 4 of the offline setup mixes three jobs on one screen in technician words: a database administrator password (`pos_admin`), the owner's account, and a separate "Build the database" button beside a disabled "Continue". This feature rewrites that step as two clear screens in plain Arabic and English, so a restaurant owner can complete it without knowing what PostgreSQL, a role or PBKDF2 is. What the step does (creates the database and the first owner) does not change.

## 2. Why
- **Who is hurt:** a café or food-truck owner installing the till alone (offline main device) meets "`pos_admin` password", "PostgreSQL account that may create databases", "PBKDF2" and "Their PIN", and cannot tell what to type or in what order. Restaurants with a technician are less hurt, but the same words are shown to them.
- **When:** first install of an offline main device, once, but a wrong guess here (a typo in a PIN that cannot be read back) locks the owner out.
- **Venue models:** café and food truck (self-installed, one till, offline) benefit most; restaurant (technician) benefits; cloud kitchen: not applicable (cloud setup skips this step, see §5).

## 3. Goal and success
An owner who has never seen PostgreSQL finishes step 4 on the first try: knows which password is being asked and why, picks a PIN they can type back, presses one obvious button per screen, and ends on a clear "database created" result. Success is checked by the acceptance criteria and by one person who is not a developer doing it in Arabic.

## 4. Users, roles and permissions
No signed-in user exists yet (it is first-run setup) and no permission identifier applies. The people are the installer (technician or owner) and the owner being created. Roles are created by the existing bootstrap (`firstInstallHelp` says "the four staff roles"); this feature does not change them. The owner's PIN rule stays the till's (`PinRules`).

## 5. Today (verified in source, `apps/xorder-pos`)
| Fact | Where |
|---|---|
| Step 4 is `SetupStep.account`. For an offline terminal its content is `_FirstInstallFields`; a cloud terminal sees pairing-code or sign-in fields and a child tablet signs in to its main device. This feature touches only the offline branch. | `lib/features/setup/presentation/setup_panes.dart:835-873`, `:2106-2216` |
| The screen shows, in order: a small heading and a help paragraph; the administrator password (label "`pos_admin` password" = `adminPasswordFor(adminDatabaseUser)`); "First person"; "Their username" (placeholder `owner`); "Their PIN"; a dark "Build the database" button. "Continue" (the wizard's own button, bottom) stays disabled until the database is built. | `setup_panes.dart:2152-2216`; `lib/features/setup/domain/setup_state.dart:478-522` (`canAdvance`, `bootstrapped`) |
| The wording: `firstInstallHeading` "FIRST INSTALL ON THIS MACHINE", `adminPasswordHelp` "The PostgreSQL account that may create databases — not the till's. Used once, here, and never written to this machine.", `firstPersonHelp` "The owner. Without somebody to sign in as, the next step has nobody to authenticate.", `theirPin`/`theirPinHelp` "…four to twelve digits. Stored as a PBKDF2 hash — it cannot be read back, only replaced.", `buildTheDatabase`. Arabic equivalents exist. | `lib/core/l10n/app_strings.dart:4642-4731` (EN), `:10199-10283` (AR) |
| Both password fields are `obscureText: true` with **no show/hide control**; there is **no confirm-PIN field**. | `setup_panes.dart:1102-1184` |
| **The help text contradicts the code on the PIN.** Help says "four to twelve digits"; the rule is **exactly 4** (`PinRules.length = 4`, `isWellFormed` requires equality) and the field **silently drops digits beyond 4 as they are typed**, so someone who types a 6-digit PIN believes it is 6 digits and cannot sign in. | `lib/core/security/pin_hash.dart:25-33`; `setup_controller.dart:658-668`; `app_strings.dart:4725-4727` |
| "Build the database" runs `bootstrapDatabase`: needs the licence (`installLicenceFirst`), a well-formed PIN, name/username present, a valid database name; uses the administrator password once and does not keep it (doc comment); every step is an upsert, so it can be run again; errors such as `ownerAlreadyExists` come back as one error message. | `setup_controller.dart:674-830` |
| Existing tests that cover the wizard and strings: `test/features/setup_wizard_test.dart`, `setup_persistence_test.dart`, `cloud_setup_collapsed_test.dart`, `test/core/localisation_test.dart`; the database build itself is `test/data/installer_owner_test.dart` (PostgreSQL-tagged, self-skips without `POS_PG_HOST`). | `test/` |
| The wizard's wider flow (licence first, 10 steps in the UI) is an earlier owner decision and is **not** changed here. The `XOrder_Setup_Wizard_README.md` the owner shared (Cloud-only Phase 1, language first) conflicts with it and is a **separate feature**. | `setup_state.dart:27-60`; README |
| No row for the setup wizard in `docs/FEATURE_INVENTORY.md` was found by the greps I ran; **missing documentation** to report. | UNVERIFIED |

## 6. Scope
**In**
- The offline first-install step only: its layout, wording (Arabic and English), the two screens, the single primary button per screen, show/hide on the two secret fields, the confirm-PIN field, and the PIN help text being true.
- Clear progress and a clear success or failure result for creating the database.

**Out**
- What the bootstrap does: roles, tables, the licence-supplied restaurant name, idempotency (`PosMigrator`, `bootstrapDatabase` logic).
- The PIN rule itself (still exactly 4 digits; making it 4 to 12 would also change every keypad, `lock_screen.dart` and `pin_hash.dart`, and is **not** asked for).
- Cloud, child-tablet and pairing-code panes; the step order, the licence-first rule, the number of steps in the left list.
- The shared README's wizard redesign.

## 7. Behavior and business rules
- **BR-1** Step 4 (offline first install) is two screens, in this order: **A. Database access**, **B. Create the owner account**. Back and Continue move between them and between the neighbouring steps.
- **BR-2 (Screen A)** Asks for one thing: the password of the account that creates the database. Plain explanation, no product jargon: it is **used once to create the XOrder database and is not saved**; ask whoever installed PostgreSQL. A show/hide control. The account name (`pos_admin` by default) may be shown as a small secondary line, not as the label.
- **BR-3 (Screen B)** Asks for: the owner's name, a username (prefilled `owner`), a PIN and the PIN again. Plain sentence: "You will use this to sign in at the till."
- **BR-4** The PIN rule is the till's: **exactly 4 digits** (`PinRules`). Every sentence on the screen says so; none says "four to twelve" or mentions a hash or PBKDF2.
- **BR-5** The two PIN entries must match before the database is built; a mismatch says so beside the field and builds nothing.
- **BR-6** **One primary button per screen.** Screen A: Continue. Screen B: the button that creates the database (e.g. "Create database and continue"); there is no separate "Build the database" button next to a disabled Continue. While it runs it shows progress; on success it shows a plain "Database created" result and then lets the person continue.
- **BR-7** If creating the database fails because of the administrator password or the connection, the person is taken back to **Screen A** with the error shown there (the field is on Screen A, the action on Screen B); other errors stay on Screen B beside what to fix. The typed values are kept.
- **BR-8** Running it again is still safe (upserts); nothing about the bootstrap's idempotency changes.
- **BR-9** Arabic and English both read right to left or left to right correctly; technical values (`pos_admin`, `owner`) are set left-to-right inside Arabic text.

## 8. Acceptance criteria
- **AC-1** Given an offline first install at step 4, then Screen A shows only the administrator password, a show/hide control, and the plain "used once, not saved" explanation, in Arabic and English. *Widget test.*
- **AC-2** Given Screen A with a password typed, when Continue is pressed, then Screen B shows the owner name, username (prefilled `owner`), PIN and confirm-PIN. *Widget test.*
- **AC-3** Given two different PINs, when the person presses the create button, then nothing is built and a mismatch message is shown. *Widget test; the fake bootstrap is not called.*
- **AC-4** Given any text on either screen, then it contains neither "PBKDF2" nor "four to twelve", and the PIN sentence says exactly 4 digits. *Widget test on the strings, both languages (`localisation_test` style).*
- **AC-5** Given a 4-digit PIN entered twice and valid fields, when the create button is pressed, then the bootstrap runs once with the owner's values and, on success, a "database created" result is shown and the wizard can continue. *Widget test with the setup controller faked.*
- **AC-6** Given a wrong administrator password (the fake bootstrap fails with an authentication error), then the person lands on Screen A with the error and nothing typed is lost. *Widget test.*
- **AC-7** Given the screen at 1024×700 in Arabic, then it lays out right to left with no overflow, and `pos_admin`/`owner` read left to right. *Widget test; a person checks it on a real till.*
- **AC-8** There is exactly one visible primary action per screen and no "Build the database" button beside a disabled Continue. *Widget test.*
- **AC-9** Cloud, child-tablet and pairing-code step-4 screens, the step order and the persisted setup progress are unchanged. *Existing `setup_wizard_test`, `setup_persistence_test`, `cloud_setup_collapsed_test` stay green.*
- **AC-10** The bootstrap against a real PostgreSQL still creates the database and the first owner. *`installer_owner_test` (PostgreSQL-tagged); not run unless a local PostgreSQL is available.*

## 9. Edge cases and failure modes
- **Offline:** none of this needs the platform; it talks to the local PostgreSQL only.
- **Retry / idempotency:** the bootstrap is an upsert; pressing the button twice, or going back and forward, must not create two owners (`ownerAlreadyExists` stays the answer if the owner exists).
- **Back from B to A and forward:** typed values survive (the draft already holds them: `adminDatabasePassword`, `ownerName`, `ownerUsername`, `ownerPin`, `setup_state.dart:105-109`). Whether the PIN and the admin password may be kept in the persisted progress is **UNVERIFIED** and must stay "never written to disk" for the admin password.
- **A PIN of other lengths:** the field should not let someone believe a longer PIN was accepted (today digits beyond 4 are dropped silently). See open question Q4.
- **Arabic digits:** a PIN typed with Arabic-Indic digits: today non-ASCII digits are stripped (`setOwnerPin` keeps `[0-9]` only), so they vanish silently. **UNVERIFIED** whether the keypad ever produces them; the wizard's own `foldDigits` exists in `core/text/digits.dart` (used elsewhere).
- **Tenant boundary, plan and licence limits:** the restaurant name comes from the licence; unchanged. An unlicensed terminal still gets `installLicenceFirst`.
- **Empty and very long names:** the owner name must be non-empty (existing `firstPersonIncomplete`); a very long name must not overflow the screen.

## 10. Impact
| Area | Impact |
|---|---|
| Apps and repos | `xorder-pos` only. `xorder-cloud` is not touched. |
| API and contract | none; no READY item involved. |
| Data and migrations | none. |
| Permissions | none. |
| Localization | rewritten and new strings in `app_strings.dart` (EN and AR): screen titles, explanations, confirm-PIN label and mismatch message, show/hide labels, the create button, the success message. Arabic needs a native read. |
| Code (expected) | `setup_panes.dart` (`_FirstInstallFields`, `_PasswordField`), `setup_controller.dart` (a confirm-PIN draft value and which sub-screen), `setup_state.dart` only if the sub-screen or confirm value lives in the draft; tests above. |
| Documentation | a feature folder for the setup wizard; `docs/FEATURE_INVENTORY.md` row (none found). |
| Deploy order | POS only; nothing to order with the cloud. |
| Needs approval in `/implement` | none of the usual (no migration, contract, payment or order-state change); touching the setup state shape is the one to show in the plan. |

## 11. Dependencies, known gaps, risks
- **Risk:** persisted setup progress (`setup_progress_store.dart`) stores the wizard's position; adding a new step enum value would affect saved progress. The plan in §13 Q1 avoids that by keeping both screens inside step 4.
- **Risk:** the working tree has unrelated uncommitted POS work, including mine from the sign-in feature (`app_strings.dart`, `router.dart`, etc.). New strings will sit beside them in `app_strings.dart`.
- **Known gaps leaned on:** none of tips, aggregators, KDS, recipes, loyalty or multi-brand.
- **Related but separate:** the `XOrder_Setup_Wizard_README.md` (Cloud-only Phase 1, language first) conflicts with built behaviour; it should be its own description and needs the owner's decisions first.
- **Missing documentation:** no feature folder or inventory row for the setup wizard (UNVERIFIED by grep).

## 12. How it will be tested
Flutter widget tests with the setup controller and bootstrap faked, in the style of `test/features/setup_wizard_test.dart` (AC-1 to AC-9); string checks in both languages (AC-4); the existing wizard suites stay green (AC-9); the real database build stays covered by the PostgreSQL-tagged `installer_owner_test` (AC-10). **Needs a person:** the whole step in Arabic on a real till at 1024×700, done by someone who is not a developer, and a read of the Arabic wording.

## 13. Decisions and open questions
**Decided (2026-10-27, owner)**
- **Plan approved with the defaults for Q1 to Q5** (two screens inside step 4; no test-connection button; labels Owner name / Username / Sign-in PIN; a live `n / 4` counter plus the exactly-4 sentence; the PIN stays exactly 4 digits).
- The step must be clear to any user (the owner's words above) and the design is the two-screen version from my previous message, one primary button per screen, plain words, show/hide, confirm PIN, no jargon.

**Still open, with a recommendation each**
- **Q1 Two screens inside step 4, or two steps?** *Recommend inside step 4* (a small sub-screen state; the left list stays at 10 steps and the persisted progress is untouched).
- **Q2 "Test connection" on Screen A** before moving on, so a wrong password is found where it is typed, instead of BR-7's return trip. This is a **suggestion, not asked for**; it needs a new check that does not create anything. *Recommend not now; BR-7 gives the same safety with no new behaviour.*
- **Q3 Labels.** "Owner name" and "Username" instead of "First person" and "Their username"; "Sign-in PIN" instead of "Their PIN". *Recommend yes.* Arabic wording to be reviewed by the owner.
- **Q4 Extra digits.** Keep dropping digits beyond 4 as typed (but say "4 digits" under the field and show a counter), or stop accepting input at 4 with a visible limit. *Recommend a counter and the sentence; no behaviour change to the rule.*
- **Q5 PIN rule.** Is exactly 4 digits what the owner wants? The old help said "four to twelve". Changing it is outside this feature and touches the keypads and the lock screen. *Recommend keeping 4.*

Next: `/implement pos-setup-owner-step` once Q1 to Q5 are answered or you accept the recommendations. It will need approved in the plan: the shape of the setup state if a confirm value or sub-screen is added to it. No migration, contract change or push is expected.


## 14. As built (2026-10-27)
Built as planned in `TECHNICAL.md` (stages S1 to S5); see `CHANGELOG.md`, `TEST_PLAN.md`, `TEST_REPORT.md`.
- **Deviation from the spec after review: the administrator password may be empty.** The first screen's Continue is enabled with an empty field, as the old screen allowed: a local PostgreSQL that trusts this machine's account has no password to give. The help line now says "If PostgreSQL here has no password, leave it empty." (AC-8's "dimmed until a password" is replaced by "always enabled".)
- **Also changed after review:** the PostgreSQL-tagged `installer_owner_test` now supplies the PIN confirmation (it would otherwise be stopped by the new mismatch rule, only visible against a real PostgreSQL); two error sentences that still said "first person", "at least four digits", "build the database" and "الكود" now use the new words (`firstPersonIncomplete`, `ownerAlreadyExists`); a second press while the build runs starts nothing.
- **Known and left alone.** (1) The "Database created." card still prints the technical report under it (migrations applied, grants), useful to a technician; say if you want it hidden. (2) For `dns`, `tcp`, `tls`, `missingRole` and the till-role refusal the person is sent back to screen A, but the host or role name is set on the earlier Connection step: the error says so, the screen does not offer a shortcut. (3) The wizard still mixes three Arabic words for PIN (الرقم السري, رمز, الكود) outside this step; needs a native pass. (4) The Show/Hide buttons are keyboard tab stops between the two PIN fields.
- **Not done / not proven.** The real database build and the success path end to end (the build is not fakeable without a refactor, plan D2) need a PostgreSQL: `installer_owner_test` and `scripts/check.sh` were **not run**. The whole step in Arabic on a real till, and the Arabic wording, need a person.

## 15. Amendment, 2026-10-27: the owner's Admin Mode password is chosen in the wizard
Source: the owner, after finding `password_hash` empty in `pos_staff` and learning that the password is only chosen at the first Admin Mode entry: "It should be setup during setup wizard". **Status: proposed amendment, built nothing.**

**Summary.** The first owner is created with a PIN only today, so the back-office password does not exist until somebody enters Admin Mode once on the PIN and is held at a "choose a password" screen. Instead, step 4 asks for the owner's Admin Mode password (typed twice) and stores it with the owner row, so Admin Mode needs a username and password from the very first entry.

**Today (verified).**
| Fact | Where |
|---|---|
| The owner row is inserted with name, username, PIN salt and hash and the owner role; no password columns. `ON CONFLICT (restaurant_id, username) DO NOTHING` leaves an existing owner untouched. | `lib/data/postgres/local_bootstrap.dart:585-646` |
| A person with no password gets into Admin Mode once on their PIN and is then held at `AdminMustSetPassword` until they choose one. | `lib/features/admin/application/admin_session.dart:30`, `:115`, `:529` |
| Policy: at least **10** characters (the owner's figure, 25 Oct 2026), at most 128, not equal to the PIN or the username. | `lib/core/security/pin_hash.dart:117-147` |
| The stored form is `pbkdf2-sha256$<iterations>$<salt>$<key>`; the column has a shape CHECK; the normal "set password" writes `password_hash` and `password_set_at = now()`. | `pin_hash.dart:167-193`; `lib/data/postgres/migrations.dart:4531-4543`; `postgres_admin_repositories.dart:900` |
| How the Admin Mode door decides between PIN and password by the staff-auth policy setting: **UNVERIFIED** (the ADR says password applies once the policy is `pinOrPassword` or higher and the person has one). | `docs/pos/adr/ADR-006b-staff-auth-and-db-roles-design.md:164` |

**New rules.**
- **BR-10** Step 4 asks for the owner's **Admin Mode password** and its confirmation; the bootstrap hashes it (`PasswordHash`) and writes `password_hash` and `password_set_at` in the same insert as the owner.
- **BR-11** The password follows the existing policy (10 to 128 characters, not the PIN, not the username); every refusal says why in plain Arabic and English before anything is built.
- **BR-12** It is typed twice, with Show/Hide, like the PIN; a mismatch builds nothing.
- **BR-13** The PIN is unchanged and still signs the owner in at the till; the password is for Admin Mode (the back office) only.
- **BR-14** If the owner already exists (`OwnerAlreadyHere`), an existing password is **not** overwritten and the wizard says so.
- **BR-15** Both secrets are dropped from the wizard's in-memory draft once the database is built.
- **BR-16** An install made before this change is unaffected: it keeps the PIN-first-entry route.

**Acceptance criteria.**
- **AC-11** Given a valid password typed twice, when the database is created, then the owner row has a `password_hash` that verifies against that password, a `password_set_at`, and the PIN hash is unchanged. *`installer_owner_test` (PostgreSQL-tagged, not run here) and a unit test of the seeding statement with a fake.*
- **AC-12** Given a password shorter than 10 characters, equal to the PIN or equal to the username, then it is refused with its own sentence and nothing is built. *Controller and widget tests.*
- **AC-13** Given two different passwords, then nothing is built and a mismatch is said. *Controller and widget tests.*
- **AC-14** Given an owner created this way, when they enter Admin Mode, then the door asks for the password and the PIN-only first entry is not offered. *`admin_session_test` with the fake.*
- **AC-15** Given the owner already exists, then no password is changed and the report says so. *PostgreSQL-tagged.*
- **AC-16** After the build, neither the PIN nor the password remains in the draft. *Controller test.*

**Impact.** POS only. `LocalBootstrap.seedOwner` gains an optional password; `SetupDraft`, the controller, the owner's screen, strings (EN and AR) and the tests change. **No migration** (the columns and the shape CHECK exist). No cloud change. Needs: the answers below, `/security-audit` on the seeding path, and the PostgreSQL-tagged tests run by someone with a local PostgreSQL.

**Risks.** A 10-character minimum on a setup screen is a heavier ask than a 4-digit PIN: wording and Show/Hide matter. The staff-auth policy default must be confirmed so that a seeded password is actually required at the Admin Mode door (**UNVERIFIED** above).

**Open questions, each with my recommendation.**
- **Q8 Required or optional?** *Recommend required*: the owner wants it set in the wizard, and an owner with no password keeps the PIN-only entry.
- **Q9 Where on the screen?** On the owner's screen (six fields), or a **third screen** "Back-office password". *Recommend a third screen*, so no screen asks for more than three things; the flow becomes A (database), B (owner and PIN), C (back-office password) with "Create database and continue" on C.
- **Q10 Wording of the rule.** "At least 10 characters" shown under the field. *Recommend yes.*

**Decided (2026-10-27, owner, asked and answered)**
- **Q9** The owner's Admin Mode password gets its **own third screen**, "Back-office password". The step is three screens in one step: A database access, B owner name, username and PIN, C back-office password; "Create database and continue" is on C, and Continue on A and B.
- **Q8** It is **required**: step 4 cannot finish without it, and a new install has no PIN-only first Admin Mode entry.
- **Q10** (recommended, not yet answered) The rule "at least 10 characters" is shown under the field in plain words.
Consequences for the earlier plan (`TECHNICAL.md`): `OwnerPage` gains a third value, `FooterAction` gains a "to the password screen" step, the create button moves from B to C, Back from C goes to B; `LocalBootstrap.seedOwner` takes the password; the two-screen tests and AC-2, AC-3, AC-5 and AC-8 above change accordingly. This needs a **new plan and your approval** before anything is built.
