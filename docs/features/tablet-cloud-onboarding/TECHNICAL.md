# Technical plan — tablet-cloud-onboarding

Status: **approved 2026-11-19 (Stages 0–1 started)** · 2026-11-19 · Spec: `FEATURE.md` (same folder) · Source revision: monorepo `b9f14e7d`. Paths are relative to `apps/xorder-pos/` unless noted; `S:` = `packages/shared_module/lib/`.
Tree check: uncommitted and unrelated to the plan's code: `apps/xorder_pos_cloud/{.gitignore,.metadata,android/}` (created 2026-11-19 by `flutter create`, this feature's Stage 0), `docs/features/dynamic-qr/` (unrelated, untouched). No edits of mine will mix with other people's code changes.

## 1. What I re-checked in source (and what changed from the spec)
| Claim | Result |
|---|---|
| Android falls back to the plaintext store | **Confirmed.** `S:data/config/secret_store.dart:84-88`. |
| A cloud tablet is always a main till | **Already decided in code.** `apps/xorder_pos_cloud/lib/wiring.dart:80-82`: "Every cloud till is a till of its own (owner decision Q8): no tablet or extra desktop hangs off another's database". So the cloud tablet is its own till; no child mode exists for the cloud app. FEATURE.md Q3 for the cloud app needs no new decision. |
| Daily sign-in is name + PIN against a local verifier | **Confirmed.** `S:features/lock/lock_screen.dart:148-176` calls `sessionRepositoryProvider.signInAs(username, pin)`, rate-limited by `signInLimiterProvider`. |
| No password verifier on the till | **Confirmed** (pos-pin: the bootstrap carries only PIN verifiers). A password can only be checked by the platform: `POST /api/auth/login`, throttled to **10 per minute per IP** (`apps/xorder-cloud/apps/api/app/Providers/*` rate limiter `login`, and per username). |
| Hard reset keeps tenant data on purpose | **Confirmed, and it matters.** `TerminalReset.runHard` (`S:app/providers.dart:2592-2668`) keeps the cloud app's data-file key (`hardResetSurvivorsProvider`, `wiring.dart:69-72`) so sales are never lost. It is **not** a "Change business" wipe. Change business needs a new reset that also deletes the data file and key. |
| Outbox backlog is readable | `pendingSyncCountProvider` → `ordersRepositoryProvider.pendingSyncCount()` (`S:app/providers.dart:1180-1195`); held records via `heldSyncCountProvider`. Open shift via `shiftProvider`. Both usable for the Change-business refusal. |
| An offline child tablet joins with a short form | **Not true; this is a finding that changes Stage 7.** An offline child connects **straight to the main till's PostgreSQL** and the wizard demands the database password on the tablet (`S:features/setup/domain/setup_state.dart:488-492`, `databasePassword.isNotEmpty`). Address + staff + PIN cannot produce a database credential. See Stage 7. |

## 2. Reuse (do not rebuild)
- Cloud setup by sign-in (`pos-cloud-sign-in-setup`), `CloudApi` login/branches/terminals/register/claim (`S:data/cloud/cloud_api.dart`), `TerminalConfigStore`, `DeviceTokenVault`, `SecretStore` interface, `AttemptLimiter`, `terminalResetProvider`, `ForceResetDialog` sign-in check, `PinRules`, Waiter app's TLS/pairing code for any future offline pairing.
- Do not touch the Waiter app, the cloud API, or the Postgres layer.

## 3. Domain lens
Helps: **café** and **food truck** (a tablet is the whole till). **Restaurant / cloud kitchen**: a station tablet works only as its own cloud till (cloud app), not as a child. **Breaks / risks:** password sign-in at every lock slows a café counter and needs signal, which a food truck often lacks (Stage 4 risk). No printer on Android is a café blocker (listed gap). No venue-type assumption is added.

## 4. Stages
Order: foundation and security first, behavior next, UI last. Each stage ends with its tests run. Cloud API: **no change in any stage**.

### Stage 0 — Android project baseline (additive, already partly done)
- Keep `apps/xorder_pos_cloud/android/`, `.gitignore`, `.metadata`. Set in the manifest: app label "XOrder POS", `INTERNET`, no cleartext traffic, orientation unlocked (portrait + landscape), `resizeableActivity`, adaptive icon from `flutter_launcher_icons.yaml` (Android block added).
- Record a **baseline**: `cd apps/xorder-pos && flutter analyze && flutter test` (unit suites; PostgreSQL-tagged suites skip without `POS_PG_*`, reported as not run). Needed to prove AC-12.
- Tests: none new; baseline output saved in `TEST_REPORT.md`.
- Rollback: delete the folder.

### Stage 1 — Android secret store (BR-5, AC-7, AC-13). **Needs approval: new dependency.**
- Add `SecretPlatform.android` and an `AndroidKeystoreSecretStore` implementing `SecretStore` (`read/write/delete/deleteAll`, `protectedByOperatingSystem == true`, throws `SecretStoreUnavailable` when the keystore refuses; never falls back to a file). `SecretPlatform.host` returns it on Android (`secret_store.dart:84-88`).
- Implementation choice (recommend **A**): **A** `flutter_secure_storage` (Android Keystore, encrypted prefs): one new package, standard, small code. **B** a small Kotlin `MethodChannel` using Android Keystore AES-GCM: no new dependency but more native code to own and test.
- The legacy `secrets.json` migration and Windows/macOS-only paths are skipped on Android (nothing to migrate).
- Tests: factory test selects the Android store for the Android platform value and never `development` (pattern of the existing secret-store tests); fake-platform-channel unit tests for read/write/delete/unavailable; on-device check that no plaintext secrets file exists (`adb shell run-as … ls`) — a person/`adb` step.
- Rollback: revert the commit; the desktop stores are untouched.

### Stage 2 — Persistence and startup (BR-3, BR-4, BR-7; AC-3, AC-4, AC-5, AC-6)
- Mostly **tests of existing behavior**, with fixes where a test proves a gap: boot with a saved config → lock/start, never setup; interrupted or failed setup leaves no saved config (the wizard saves progress separately from the config; verify `setupProgressStore` vs `terminalConfigStore`); logout/update/restart keep the config; network failure at launch shows retry, not setup.
- Files: `S:features/setup/application/setup_controller.dart` (only if a gap is found), `S:pos_main.dart` (`bootFor`), tests under `S:` `test/features/setup`, `test/app`.
- On-device: force-stop, reboot, `adb install -r` (update) keep the business (AC-4, a person/`adb`).

### Stage 3 — Setup trimmed (Q2): three fields, then automatic when unambiguous (AC-1, AC-2)
- After sign-in: **one branch** → auto-pick it; **no unclaimed tills in it** → register a new till automatically with a default name (e.g. "Tablet"); otherwise show the existing branch/terminal screens. Printer step is already skipped unless the scan found none or several (`setup_state.dart:306-316`; on Android no scan exists, so the hardware step must be skipped or shown as "no printer", Stage 8).
- **Deviation from your wording, needs approval:** you said "when the business has one branch and one free terminal". Adopting a *free* (unclaimed) till silently could take a till created for a desktop. The plan auto-**registers** a new till when none is free, and **asks** whenever any free till exists. If you do want silent adoption when exactly one is free, say so.
- Files: `S:features/setup/domain/setup_state.dart`, `application/setup_controller.dart`, `presentation/setup_panes.dart`; tests: controller unit tests with fake `CloudApi` (one branch/none free → auto; many → ask; staff refused; wrong password), widget tests.
- Idempotency: register uses `client_transaction_id` (`cloud_api.dart:172`); add a test that a retry after a dropped reply does not create a second terminal (currently UNVERIFIED).

### Stage 4 — Password sign-in (Q1) (BR-8, AC-5, AC-6, AC-13). **Needs approval: behavior change, new use of an existing endpoint.**
- Cloud app only. The lock screen asks **username + password**. The till calls `POST /api/auth/login` with the saved slug (`cloud_api.dart:111-123`), **discards the JWT**, checks the returned account matches an active local staff row, then signs that staff in locally (`signedInStaffProvider.signIn`) with the permissions already cached from the bootstrap. The password is never stored or logged (BR-2).
- **No contract change:** the call exists today. It is a new use by the till for every sign-in instead of once at setup.
- Risks to accept or change: (1) **needs internet** at every sign-in (food trucks, power/signal drops); (2) server throttle **10 logins/min per IP** — several tablets behind one shop router share it; (3) every idle-lock unlock becomes a password; (4) manager-PIN approvals (refunds, discounts) and `checkStaffPin` use the PIN today.
- Proposed mitigations (need your OK): keep the PIN as the **offline fallback** and for manager approvals and idle-lock unlock of the same user; the password is required for a fresh sign-in or a user switch while online. If you want password-only with no fallback, say so; it makes the till unusable offline at the sign-in screen.
- Files: `S:features/lock/lock_screen.dart`, `S:app/providers.dart` (a new `PlatformPasswordCheck` seam), `S:data/cloud/cloud_api.dart` (reuse), strings (ar/en). Tests: unit with fake `CloudApi` (correct, wrong, unknown user, inactive staff, no network → fallback message, 429), widget (ar/en), a test that the password is in no stored file/log.

### Stage 5 — Change business (Q4, BR-6; AC-8, AC-9). **Needs approval: new destructive action.**
- New `TerminalReset.runChangeBusiness` in `S:app/providers.dart`: `run()` plus deletion of the cloud data file and its key (`cloudDataKeyStoreProvider`, which hard reset deliberately keeps), the device token, licence caches, remembered usernames, printer and terminal settings, and any cached tenant data, then back to setup.
- Guard (server cannot enforce a local wipe, so enforcement is **local**, inside the action, not just a hidden button): signed-in staff holds `terminal.manage` (`S:domain/models/permissions.dart:70`), **password re-entered** and verified through the Stage 4 check (needs internet), **refuse** while a shift is open (`shiftProvider`) or `pendingSyncCount() > 0` or held records exist.
- Placement: back office System › Terminal beside "Reset terminal". The hard reset and force reset stay as they are (technician tools).
- Not done by this action: platform data is untouched; the old terminal stays claimed in the old business until someone deletes it on the dashboard (stated in the confirmation text).
- Tests: unit tests per BR-6 item, refusal tests (no permission, wrong password, open shift, unsynced sales), tenant-isolation test that the new business sees none of the old rows; on-device run.

### Stage 6 — Tablet layouts (AC-10, AC-11). **The largest stage; may be split into sessions per screen group.**
- Screens to audit and fix, in this order: setup/sign-in, lock, start/home, sale (product grid, cart), payment, shift/cash, order history, settings/back office, receipt hand-off.
- Method: widget tests at 3 sizes in both orientations (tablet portrait ≈ 800×1280, Xiaomi Pad 6 ≈ 1800×2880 px; sizes taken from the tokens' breakpoints, `S:core/ui/tokens.dart:460`), `en` and `ar`; fix overflow, keyboard obscuring the primary button (`resizeToAvoidBottomInset`, scroll), touch targets, dialogs; **a person walks each screen on the real tablet** for what tests cannot see.
- Do not change desktop layouts: changes are gated by width/breakpoint; phone layouts are out of scope.
- Measure first-start time on a **release** build (debug showed about 20 s on the splash).

### Stage 7 — Offline app on an Android tablet (Q3, Q6). **Not plannable as a "short form" yet; recommend deferring.**
- Android folder for `apps/xorder_pos_offline` is mechanical (like Stage 0).
- The hard part: the offline child connects straight to PostgreSQL with a database password (`setup_state.dart:488-492`), over the LAN with TLS pin (`waiter_link_tls.dart` shows the pattern). A form of address + staff + PIN has nothing to authenticate a database connection with. To get that short form the main till would need a **pairing handshake** (a code shown on the desktop, exchanged over the existing LAN TLS link, handing the tablet a scoped credential). That is a new LAN contract and a security design, not a UI change, and `security-reviewer` must review it.
- Options: (a) ship the cloud tablet first and design the pairing in a separate feature; (b) offline tablet keeps today's child path (typing the database password) in an Android build. **Recommendation: (a).** FEATURE.md Q6 stays open until then.

### Stage 8 — Hardware on Android (listed gap, out unless approved)
- Receipts: `win32`/winspool is desktop only (`S:data/hardware/winspool.dart`). On Android the till needs a network/Bluetooth printer path or "no printer" mode. Without it a café cannot print receipts. Proposal: Stage 8 = "no printer" is handled cleanly (receipt shown/shared, wizard skips the printer step); real printer support is a separate feature.

## 5. Verification commands
- Baseline and after each stage: `cd apps/xorder-pos && flutter analyze && flutter test` (shared and both apps; PostgreSQL suites: `scripts/check.sh` with `POS_PG_*` — reported as **not run** if not set).
- Cloud app only: `cd apps/xorder-pos/apps/xorder_pos_cloud && flutter test`.
- Device: `flutter build apk --debug`, `flutter run -d <tablet>` (a person confirms what the device shows).
- The cloud API is not touched, so `php artisan test` is not part of this feature.
- Not provable by tests: printing, real keyboard behavior, rotation, signal and power loss, reboot/update persistence — listed for a person on the tablet.

## 6. Compatibility and rollout
POS only, additive. Old POS builds on Windows/macOS are unaffected (the new Android store is selected only on Android; setup/sign-in changes are cloud-app only, so the Offline app's desktop behavior is unchanged). No contract, no migration, no cloud deploy. Rollout: build the Android APK for the tablet (debug now; release signing and distribution are out of scope).

## 7. Approvals needed before building
1. **New dependency** `flutter_secure_storage` (Stage 1), or the Kotlin keystore alternative.
2. **Stage 3 behavior:** auto-register a new till and ask when any free till exists (differs slightly from your wording).
3. **Stage 4 behavior:** password sign-in with PIN kept as the offline fallback and for manager approvals/idle unlock (or password-only, with the consequences above).
4. **Stage 5:** a destructive Change business action with the guard described.
5. **Stage 7:** defer the offline tablet (recommended) or choose option (b).
6. **Stage 8:** receipts on Android are out of this feature.

## 8. Open questions
- Does a staff member without a dashboard password exist (PIN-only staff)? If so they cannot sign in with a password at all (UNVERIFIED; Stage 4 must handle it).
- Is the server login throttle acceptable for a shop with several tablets, or should the throttle be raised for POS use (a cloud change we are not planning)?
- Which tablets and Android versions are officially supported (spec section 12)? Only the Xiaomi tablet (Android 14) was seen.
- Should Stage 6 be done as one change or split into several sessions? Recommend split by screen group.

## 9. Progress
- **Stage 0 done (2026-11-19):** manifest: `INTERNET`, label "XOrder POS", no cleartext, no Android backup of app data. Baseline recorded in `TEST_REPORT.md`. Not done: Android launcher icons (the icon config only generates Windows/macOS; to do with Stage 6).
- **Stage 1 done in code, device proof pending:** chose **option B** (native Kotlin over a method channel), not `flutter_secure_storage`. Reason found while building: a package is compiled into every platform the app supports, so adding it to `shared_module` would put a new plugin into the **Windows and macOS** builds that customers run, and the Windows build cannot be checked from this Mac. Option B adds nothing to the desktop builds. It was the plan's listed alternative; the approved dependency was therefore not added. See `TEST_REPORT.md` for what is and is not verified.

### Progress — Stage 2 (2026-11-19)
Tests added (failed sign-in keeps no token; boot keeps the business); no production code changed. Device checks for AC-4, AC-6 and AC-3's reopen-on-setup are still open (see TEST_REPORT). Debug builds reach the platform at `http://localhost:8080` (`platform_endpoint.dart:24`); on the tablet this needs `adb reverse tcp:8080 tcp:8080` and a local owner account.

### Progress — Stage 3 (2026-11-19)
Built as planned, with the approved rule (register when one branch and nothing waiting; ask otherwise; never adopt silently). Found and fixed an idempotency gap in `registerManually` (fresh transaction id per call). Applies to the Cloud app on every platform, not only Android. See TEST_REPORT. Still open: widget and tablet runs; the hardware step on Android.

### Progress — Stage 4 (2026-11-19)
Built with the PIN kept as fallback (see TEST_REPORT). No contract change. Open: device run; confirm staff other than the owner can sign in at the platform and have passwords; whether the idle-lock unlock should offer the password too (it does, via the same screen).

### Progress — Stage 5 (2026-11-19)
Built as planned; placement moved to the cloud Management screen. See TEST_REPORT. Open: device run; the full return-to-setup path; decide whether "export unsent sales first" is wanted.

### Progress — Stage 6 (2026-11-19)
Audit harness, three fixes (lock screen scroll and target, sale footer hint, Management scroll) and launcher icons. Remaining screens, the device walk and the release-build start time are open. **Correction:** earlier "24 baseline failures" came from running tests from the workspace root; per member, everything passes (see TEST_REPORT).

### Progress — Stage 6, second pass (2026-11-19)
Dialogs, floor, history and payment audited; the payment keypad column now shares width when narrow. Receipt, refund, back-office panes and the device walk remain.

### Progress — Stage 7 (2026-11-19)
Android platform for the offline app, Android = child role, APK builds. The short form is **designed and reviewed, not built**: see `OFFLINE_TABLET_PAIRING.md` for the revised handshake, the review's findings and the four owner decisions. FEATURE.md Q6 stays open.
