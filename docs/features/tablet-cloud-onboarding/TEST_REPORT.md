# Test report — tablet-cloud-onboarding

Executed results only (planned tests are in `TECHNICAL.md`). Source: monorepo `b9f14e7d` plus uncommitted work.

## Stage 0 and 1 — 2026-11-19

**Baseline (before any Dart change)**, from `apps/xorder-pos`:
- `flutter analyze` → `No issues found!`
- `flutter test packages/shared_module apps/xorder_pos_cloud` → `+2667 ~88 -24` (2667 passed, 88 skipped, 24 failed). **The 24 failures exist without this feature** (named in the scratchpad file `baseline_fail.txt`: `grants_cover_usage_test`, `package_boundaries_test` ×3, `home_flow_test`, `home_close_day_test`, `order_history_test`, `receipt_previews_test`, `sqlite_database_test`, `migration_cli_test`, `installer_consistency_test`, `cloud_datastore_test` day-close backup, `till_status_bar_test`, the Arabic 1100-breakpoint setUpAll, the waiter-colours test). Not investigated here; not caused by this change.

**After Stage 1** (Android Keystore secret store: `lib/data/config/android_keystore_secret_store.dart`, `secret_store.dart`, `test/data/secret_store_test.dart`, native `KeystoreSecrets.kt` + `MainActivity.kt`, manifest):
- `flutter test test/data/secret_store_test.dart` (in `packages/shared_module`) → `All tests passed!` (55).
- Same two-package run → `+2677 ~88 -24`: ten more passes than baseline, **the same 22 named failing entries** (`diff` of the two failure lists: identical).
- `flutter analyze` → `No issues found!`.
- `flutter build apk --debug` (cloud app) → `Built build/app/outputs/flutter-apk/app-debug.apk` (compiles the Kotlin).

**Covered by the new tests:** the Android store keeps the shared `SecretStore` contract (write/read round trip with Arabic and symbols, replace, independent keys, delete, deleteAll); every refusing call is a typed `SecretStoreUnavailable` naming "Android Keystore"; the refusal never contains the secret; nothing is kept when the store refuses (no fallback); with no native side the real channel refuses instead of crashing; the factory returns the Android store for `SecretPlatform.android` and plaintext only for `development`.

**NOT verified (needs the tablet, which was not connected when Stage 1 finished):**
- That the Kotlin Keystore code actually seals and opens values on a real device (`KeystoreSecrets.kt` has no unit test; it is proved on the device).
- That no plaintext secrets file exists on the tablet after setup (`adb shell run-as io.xorder.xorder_pos_cloud ls files shared_prefs`).
- AC-7 is therefore **not ticked**; only its Dart half is proved.

Windows and macOS builds were not run (no change to their code paths: the new enum member is selected only on Android; no dependency was added).

## Stage 2 — Persistence and startup — 2026-11-19

Source: monorepo `b9f14e7d` plus uncommitted work. From `apps/xorder-pos`.

**Found already covered (read, not re-written):** `setup_persistence_test.dart` proves the saved configuration survives the round trip a restart makes, a saved terminal opens straight into the till, a keystore write failure leaves setup incomplete, a claim made on an earlier run resumes, and reset clears everything (BR-3, AC-4 in-process). `cloud_provisioning_owner_test.dart` already refused staff accounts and wrong passwords.

**Added:**
- `apps/xorder_pos_cloud/test/data/cloud_provisioning_owner_test.dart`: no internet → `PLATFORM_UNREACHABLE`; wrong password, staff account and a 429 each fail with a specific code and **keep no device token** (AC-3).
- `packages/shared_module/test/features/wrong_app_boot_test.dart`: a set-up cloud tablet keeps its business slug on repeated launches and `setupCompleteProvider` stays true; a refusing keystore still reports the saved config (BR-4, BR-7, AC-4, AC-6 launch decision).

**Results:**
- `flutter test apps/xorder_pos_cloud/test/data/cloud_provisioning_owner_test.dart` → `All tests passed!` (11).
- `flutter test test/features/wrong_app_boot_test.dart` (shared_module) → `All tests passed!` (14).
- Full run `flutter test packages/shared_module apps/xorder_pos_cloud` → `+2683 ~88 -24`: six more passes than after Stage 1, **the same failing set** (normalised diff: identical).
- `flutter analyze` → `No issues found!`.

**No code fix was needed:** no test exposed a gap in `setup_controller.dart` or `bootFor`.

**NOT verified (needs the tablet):** force-stop, reboot and `adb install -r` keeping the business (AC-4), and the retry screen when the network is down at launch (AC-6 UI). The tablet could not complete sign-in: the debug build talks to the local stack (`localhost:8080`, reached through `adb reverse`), which rejected the typed credentials with a 401. AC-3 "the app reopens on setup" and AC-5 (second user needs no slug) are covered only at the unit level here; the widget and device runs are open.

## Stage 3 — Setup trimmed — 2026-11-19

Source: monorepo `b9f14e7d` plus uncommitted work. From `apps/xorder-pos`.

**Changed:**
- `setup_controller.dart` (`connectTenant` → `_placeWhenUnambiguous`): the cloud main device registers itself when the business has exactly one branch and **no till waiting to be adopted**; the name is "Tablet" on Android, "Till" elsewhere. Several branches, or any waiting till, leaves the existing screens untouched. A refused or unreachable registration falls back to the screens with its message.
- `setup_state.dart`: new `autoPlaced`; `cloudSteps` omits the branch and terminal steps when `autoPlaced && claimed`.
- `cloud_provisioning_repository.dart` (`registerManually`): **fix** — it sent a fresh `client_transaction_id` on every call, so a register whose reply was lost and retried could create a second terminal (the server replays a known id, `TerminalController::register`, 200 vs 201). One id is now kept per slug+branch+name until the platform answers.

**Tests added:** `test/features/auto_placement_test.dart` (7: one branch registers itself and skips both screens; an in-service till does not block it; a waiting till is asked about, never adopted or registered over; several branches are asked; a refusal falls back with the reason; Next goes to connecting and Back returns to account; the offline app never places itself); `cloud_provisioning_owner_test.dart` (1: a lost reply is retried with the same id, and a later registration gets a new one).

**Results:**
- `flutter test test/features/auto_placement_test.dart` → `All tests passed!` (7).
- `flutter test test/data/cloud_provisioning_owner_test.dart` (cloud app) → `All tests passed!` (12).
- Full run `flutter test packages/shared_module apps/xorder_pos_cloud` → `+2691 ~88 -24` (eight more than Stage 2), **the same 24 failures** (normalised diff identical). `flutter analyze` → `No issues found!`.

**NOT verified:** the wizard on a screen (widget level) and on the tablet; that the real server replays the id (read from the controller's `replay` flag only; not run, no PHP test run here); the server-side terminal-limit message in the fallback (faked). The hardware step still appears on Android because no printer scan exists there (Stage 8).

## Stage 4 — Password sign-in on the lock screen — 2026-11-19

Source: monorepo `b9f14e7d` plus uncommitted work. From `apps/xorder-pos`. **Behavior change approved by the owner ("Start Stage 4"); built with the proposed mitigation: the PIN stays as the offline fallback and for manager approvals.**

**Built:**
- `shared_module/lib/app/password_sign_in.dart`: the seam (`PlatformPasswordCheck`, null by default so the offline app and every other test are unchanged), `PasswordSignIn` (platform verifies, then the till signs in that person from its **own active staff list**; a verified name the till does not have is not signed in), and its five results.
- `apps/xorder_pos_cloud/lib/data/cloud/cloud_password_check.dart` + `wiring.dart`: the real check over the existing `POST /api/auth/login` with the saved slug; 200 with a token → verified, 401/403/422 → rejected, 429 → throttled, anything else (no network, 5xx, wrong server, 200 without a token) → unreachable, never "wrong password". The token is discarded. **No new endpoint, no contract change.**
- `lock_screen.dart`: a "Use password / Use PIN" toggle, shown only when a platform check is bound (cloud app). Password mode: field + Sign in; the field is cleared after every attempt; the same `signInLimiter` counts wrong passwords as wrong PINs and a shut door asks nobody; one message for a wrong name or password.
- `app_strings.dart`: six strings, English and Arabic.

**Tests added (16):** `test/features/lock_password_test.dart` (12: the service's results; no toggle without a platform; verified password unlocks and the field is empty; wrong password, one message, field cleared; five wrong passwords shut the door and a right one is not even asked; no connection says so and the PIN still unlocks; throttle is not a wrong password; unknown-to-till account) and `apps/xorder_pos_cloud/test/data/cloud_password_check_test.dart` (4: the verdict mapping and the call made).

**Results:**
- New files → `All tests passed!` (12 and 4).
- Full run `flutter test packages/shared_module apps/xorder_pos_cloud` → `+2707 ~88 -24` (sixteen more than Stage 3), **the same 24 failures** (normalised diff identical). `flutter analyze` → `No issues found!`.

**NOT verified / open:**
- **Not run on a screen or on the tablet**; the real platform's reply (shape of `/api/auth/login` for a non-owner staff account, whether every till staff member has a dashboard password) was **not exercised**. A PIN-only staff member (no platform password) can only use the PIN.
- The "password never stored" claim rests on the code (the field is cleared; the check keeps nothing; no secret-store write) and the cleared-field test; there is no test that scans the tablet's files.
- Idle-lock unlock, manager-PIN approvals (`checkStaffPin`), shift open and the supervisor override still use the PIN, unchanged.
- Server throttle (10 logins/min per IP, shared by tablets on one router) is read from the plan, not tested here.

## Stage 5 — Change business — 2026-11-19

Source: monorepo `b9f14e7d` plus uncommitted work. From `apps/xorder-pos`. **A new destructive action, approved by the owner ("Start Stage 5") as planned.**

**Built:**
- `TerminalReset.changeBusiness({password})` in `providers.dart`. **The guards are in the action, not in a button**, checked in this order before anything is touched: the signed-in person holds `terminal.manage` (`PosCapability.terminalManage`); this app has a platform to check against; **no shift is open**; **no sale is waiting** (`pendingSyncCount`, read fresh) **and no record is held**; and the person's own password, typed again, is accepted by the platform (a password that cannot be checked is a refusal, never a pass). Only then: `runHard()` (config, progress, licence and check caches, every saved secret, the signed-in person), the device token forgotten, then the app's data-file hook.
- `SqliteDatabase.deleteFile()` (closes, deletes the file and its `-wal`/`-shm`/`-journal`); the cloud app binds `changeBusinessWipeProvider` to delete the data file and clear its key (the one thing a hard reset keeps on purpose).
- `CloudBackOfficeScreen` (the Management screen on a cloud till): a "Change business" section, shown only to someone holding `terminal.manage`, with the warning text, a password field and Confirm/Cancel; the refusal is shown in words and the field is cleared after every attempt. Six English/Arabic refusal strings plus five labels.
- **Placement differs from the plan:** the plan said "System › Terminal beside Reset terminal", but that pane belongs to the offline app; the cloud till's Management screen is a signpost and is where this lives.
- **Not deleted, by design:** anything on the platform. The old terminal stays claimed in the old business until removed on the dashboard (the confirmation text says so).

**Tests added (17):** `shared_module/test/features/change_business_test.dart` (13: nobody signed in, a cashier, no platform, open shift (and the password is not even asked), unsent sales, held records, wrong password, unreachable, throttled — each leaves the wipe un-run and the token in place; the signed-in person's own username and password are what is checked; when every guard is met the wipe runs once, the token, session and setup are cleared and the deployment forgets the last tenant; the data file is deleted with its journal files and nothing else; a missing file is not an error) and `apps/xorder_pos_cloud/test/features/cloud_change_business_test.dart` (4: not offered to a cashier; offered to an owner behind a password; a wrong password is said and the field cleared; Cancel forgets what was typed).

**Results:**
- New files → `All tests passed!` (13 and 4).
- Full run `flutter test packages/shared_module apps/xorder_pos_cloud` → `+2724 ~88 -24` (seventeen more than Stage 4), **the same 24 failures** (normalised diff identical). `flutter analyze` → `No issues found!`.

**NOT verified:**
- **Not run on a screen or a tablet.** The encrypted SQLite file's real deletion with a key is not exercised (the repository's SQLite suite is among the 24 baseline failures; `deleteFile` is tested on plain files). The return to the setup wizard after the wipe is read from the router's reaction to `setupComplete`, not driven.
- Tenant isolation (the new business sees none of the old rows) rests on the file being deleted and the key cleared, then a fresh key being minted at setup (`CloudDatastore.prepare`); not driven end to end.
- A hard-kill between the hard reset and the data-file delete would leave the file without a key; the next setup mints a new key and the old file becomes unreadable, but the file itself would remain until deleted. Not tested.
- Sales not yet synced block the action; there is no "export first" path.

**Housekeeping:** earlier in this work I ran the formatter over whole existing files, which reformatted lines I had not changed. I removed that noise by rebuilding each edited file as the original plus only my own changes (formatting verified identical); the diff is now only intended changes (13 files, +957 −19).

## Stage 6 — Tablet layouts — 2026-11-19

Source: monorepo `b9f14e7d` plus uncommitted work.

### Correction to the numbers in Stages 0–5 (important)
Every earlier "full run" used `flutter test packages/shared_module apps/xorder_pos_cloud` **from the workspace root**. That is not how the repository runs its tests (`scripts/check.sh` and `CLAUDE.md` run each member from its own folder), and from the root the package's font assets do not resolve, so every suite whose `setUpAll` calls `loadPosFonts` fails there. Most of the "24 failures present at baseline" are that artefact of my method, not defects of the product. Run the way the repo intends:
- `cd packages/shared_module && flutter test` → `+2798 ~79: All tests passed!`
- `cd apps/xorder_pos_cloud && flutter test` → `+152 ~9: All tests passed!`

So: **no test fails with all of Stages 0–6 in place**, and every test added in Stages 1–6 is inside those totals. (The skipped tests are the PostgreSQL-tagged ones, not run here; `scripts/check.sh` with a PostgreSQL was **not** run.) The root-run comparisons in earlier sections remain true as before/after comparisons (identical failure sets) but their absolute "24 failures" claim should be disregarded. I did not investigate what else differs between the two methods.

### What was audited
`packages/shared_module/test/features/tablet_layout_audit_test.dart` (80 cases) pumps, with the bundled fonts, at six logical sizes (1280×800, 800×1280, 1200×750, 750×1200, 1024×600, 600×1024) in `en` and `ar`: the setup wizard, the start screen, home, the sale screen, the lock screen (PIN), the lock screen in password mode with the keyboard up, and the setup sign-in with the keyboard up. `apps/xorder_pos_cloud/test/features/cloud_tablet_layout_test.dart` (12 cases): the cloud Management screen with Change business open and the keyboard up. A case fails on any overflow, and the keyboard cases fail if the primary button cannot be scrolled above the keyboard.

### Defects found and fixed
| Where | Found | Fix |
|---|---|---|
| Lock screen | Overflowed the bottom at 1024×600 (both languages) and at every size with the keyboard up for the password; the Sign in button was 44 px, below the 52 px secondary-action target | Body is scrollable (centred when there is room); Sign in uses `PosSize.secondaryAction` |
| Sale screen, held upright (750 and 800 wide) | The footer strip's keyboard-shortcut hint overflowed by 8–101 px | The hint is `Expanded` with an ellipsis; the count stays at the far end. No change when it fits |
| Cloud Management screen | Change business (keyboard up) overflowed at five sizes | Body is scrollable |
| Launcher | The cloud app had Flutter's default icon | `ic_launcher.png` at the five densities, resized with `sips` from `packages/shared_module/assets/icons/xorder_app_icon_1024.png` (non-adaptive; no new tool or dependency) |

Desktop layouts: the changes are no-ops when the content fits (scrolling and ellipsis only act on overflow). The desktop suites pass unchanged.

### NOT verified / not done
- **Not walked on the tablet** (it was not connected). A finger, the real keyboard, and how it feels are untested. AC-10 and AC-11 are therefore **not ticked**; the widget half only.
- **Screens not audited:** payment, shift open/close and cash, order history, settings dialogs, receipt hand-off, tables/floor. The harness is there to add them.
- **Touch targets** are asserted only for the lock screen's Sign in; the others were not measured.
- **First-start time on a release build** was not measured (debug showed ~20 s on the splash).
- The launcher icon has not been seen on a device; an adaptive icon was not made.
- Arabic strings for Stages 4–5 exist, but I am not a native reviewer; their wording wants an Arabic speaker's read.

### Stage 6, second pass — more screens — 2026-11-19

`tablet_layout_audit_test.dart` now also covers, at the same six sizes in `en` and `ar`: the open-shift, close-shift, cash pay-in, day-close, printer-settings and about dialogs (the ones with a text field also with the keyboard up), the floor (tables) screen, the order-history screen and the payment screen (reached through a line on the ticket, then Charge; the case asserts the payment screen is really on screen, and scrolls to the product on short screens).

**Defect found and fixed:** the payment dialog's keypad column was a fixed 400 px, leaving the amounts 152 px at 600 wide (a tablet held upright) and overflowing by 106 px. It now keeps 400 px from 700 px of dialog width up (so every landscape tablet and desktop is unchanged) and shares the dialog half and half below that. Nothing else overflowed.

**Results (each member run from its own folder, as the repo does):**
- `cd packages/shared_module && flutter test` → `+2942 ~79: All tests passed!`
- `cd apps/xorder_pos_cloud && flutter test` → `+152 ~9: All tests passed!`
- `flutter analyze` → `No issues found!`

**Still NOT covered:** the receipt dialog (needs a settled sale to open; not built into the harness), the refund sheet, the back-office panes, the customer dialog, held-tickets and modifier sheets, the sale screen with a populated cart and a long ticket, and every state with data (long names, many lines). Touch-target sizes are asserted only for the lock screen's Sign in. **Nothing has been walked on the tablet**, so AC-10 and AC-11 stay unticked. At 600 wide the payment dialog is cramped rather than redesigned: a stacked layout was not attempted.

## Stage 7 — Offline app on an Android tablet — 2026-11-19

Source: monorepo `b9f14e7d` plus uncommitted work.

**Done (the mechanical part):**
- `apps/xorder_pos_offline/android/` created with `flutter create --platforms=android` (stray `README.md` and `test/widget_test.dart` removed), with the Cloud app's hardening (internet permission declared, cleartext off, backup off, name "XOrder POS"), the same Android Keystore code (copied, package renamed to `io.xorder.xorder_pos_offline`, so the native code now exists in two apps) and the same launcher icons.
- `FileInstalledRole` returns **child on Android**: there is no installer marker on a tablet and an absent one used to read as main device, which would have opened the offline app's database-building wizard on a machine that cannot host PostgreSQL. Desktop behavior is unchanged (`installed_role.dart`).
- `flutter build apk --debug` (offline app) → `Built build/app/outputs/flutter-apk/app-debug.apk`.
- Tests: 2 new (`test/data/installed_role_test.dart`: Android reads as child with no file; off Android the marker file still decides). `cd packages/shared_module && flutter test` → `+2944 ~79: All tests passed!`; `cd apps/xorder_pos_offline && flutter test` → `+861 ~1: All tests passed!`; `flutter analyze` → `No issues found!`.

**Designed, not built:** the short form (Q6) needs a **pairing handshake** and is a new LAN contract and a security design. It is written up in `OFFLINE_TABLET_PAIRING.md`, reviewed by an independent `security-reviewer` (eight findings, one of which — the admin credential cannot create roles — overturned the first draft; two claims re-checked in source by me), and revised. **It needs the owner's four decisions (section 6 of that file) and a second review before any code.**

**NOT verified:** the offline app has not been installed or run on a tablet; whether the child wizard (today's path: address, database password, manager sign-in) works end to end on Android is untested, including PostgreSQL over TLS to a real main till; no hardware (printing) on Android (Stage 8).

## Sign-in lockout survives restart (security audit F1) — 2026-11-20
Change: `AttemptLimiter` saves its count through an `AttemptStore` (the secret store in the app) and loads it at start; each PIN door calls `reserve` (counted and saved **before** the PIN is compared), then `succeed`/`fail`/`release`; until loaded, doors wait on `limiter.ready`. Files: `core/security/attempt_limiter.dart`, `attempt_store.dart`, `app/providers.dart` (`signInLimiterProvider`), lock screen, shift dialog, supervisor keypad, force-reset dialog.

| Command (from the member's own folder) | Result |
|---|---|
| `packages/shared_module`: `flutter test` | +2957 ~79, all passed (13 new in `test/core/attempt_limiter_persistence_test.dart`) |
| `apps/xorder_pos_cloud`: `flutter test` | +152 ~9, all passed |
| `apps/xorder_pos_offline`: `flutter test` | +861 ~1, all passed |
| `flutter analyze` (shared_module) | no issues |

Found on the way: three widget tests (`manager_approval`, `discount_sheet`, `sign_in_lockout`) built their own provider scope without a secret store, so on macOS they wrote a real lockout into the developer's login Keychain (service `io.xorder.pos`, account `sign_in_attempts`). Fixed with an in-memory store override; the item I created was deleted; the Keychain was checked clean after the full runs. A new test that reaches a PIN door must override `secretStoreProvider`.

**Not verified:** on a device (Keystore write cost per attempt, restart of the real app); Admin Mode's own limiter is still in memory only; moving the clock forward still shortens a lockout; an interrupted `release` after a lockout already rolled over is not undone.
