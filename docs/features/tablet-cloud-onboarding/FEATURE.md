# Tablet support and one-time cloud onboarding — tablet-cloud-onboarding

Status: proposed · 2026-11-19 · Source: the owner's spec `README7.md` ("XOrder — Tablet Support & Cloud Onboarding": "First time = Slug + Admin Username + Password. After that = restore the session or sign in with Username + Password only."), and "it should be able to run on tablet normally, cloud should work" · Scope chosen by the owner: **full spec** (2026-11-19) · Verified against: monorepo `b9f14e7d` (branch `fix/waiter-floor-null-bill-request`; the Android platform folder of `apps/xorder_pos_cloud` is new and uncommitted; `docs/features/dynamic-qr/` is unrelated and untracked). Paths below are relative to `apps/xorder-pos/` unless they start with `docs/`; `S:` = `packages/shared_module/lib/`.

## 1. Summary
Make **XOrder POS - Cloud** and **XOrder POS - Offline** run properly on an Android tablet, each as its own app (flavor), chosen by which one is installed. The cloud tablet is the focus of the onboarding rules below; the offline tablet is a child of a desktop main till.

The rest of this section describes the cloud tablet. The owner sets the tablet up once with business address (slug), admin username and password. After that the business is remembered: every later start restores the till or shows the normal sign-in, and **never asks for the slug again**. Only an authorized admin can move the tablet to another business, and doing so leaves no data of the old business behind.

## 2. Why
- The cloud app was desktop only (Windows and macOS). On 2026-11-19 an Android platform folder was added and the app builds and opens on a Xiaomi tablet (23043RP34G) on the "this device has not been set up yet" screen. Nothing after that screen has been tried.
- The README says only the wide desktop shell is finished (`README.md` "Not built yet"). A cashier on a tablet needs layouts, touch targets and keyboards that work.
- Venue models: **helps** cafés and food trucks (a tablet is the whole till; unreliable power and signal), and restaurants and cloud kitchens that want a tablet at a station. **Assumes** internet at setup, and a sale must still be committed locally when the signal drops (existing outbox, `pos-cloud-sync`). **Does not touch** tables, delivery addresses or kitchen flow.

## 3. Goal and success
- A clean Android tablet is set up once and sells without further setup prompts.
- After logout, restart, force-stop and app update the business is still remembered and the slug is not requested.
- No secret (database key, device token, password) is stored in plaintext on the tablet.
- Every critical POS screen is usable on the supported tablet sizes and orientations.
- Desktop (Windows, macOS) cloud and offline behavior is unchanged.

## 4. Users, roles and permissions
| Who | May do it | Source |
|---|---|---|
| Business owner (`RESTAURANT_ADMIN`) | First-time setup of a cloud till (owner only, decision D3 of `pos-cloud-sign-in-setup`) | `docs/features/pos-cloud-sign-in-setup/FEATURE.md` §4, D3 |
| Staff and cashiers | Daily sign-in only; cannot set up or change business | same |
| Holder of `terminal.manage` | Candidate for the **Change business** action (UNVERIFIED which permission is right; see Q4) | `S:domain/models/permissions.dart:70` |

No new permission identifier is assumed. Any decision to add or narrow one is Q4.

## 5. Today (verified in source, `b9f14e7d`)
**Already built and reusable (desktop):**
- Cloud setup by sign-in: `cloudSteps` = `account → branch → terminal → connecting → [hardware] → summary` (`S:features/setup/domain/setup_state.dart:306-316`). The account step signs in with business slug, username and password (`S:data/cloud/cloud_api.dart:111-123`, `POST /api/auth/login`); the JWT is held in memory for the setup calls and never stored (`cloud_api.dart:111-112`; BR-2 of `pos-cloud-sign-in-setup`).
- The business slug is saved in the deployment config: `tenantSlug` in `S:core/config/deployment.dart:169,214,465,494` (terminal config file, `S:data/config/terminal_config_store.dart`).
- The device keeps a **device token** from pairing, in the secret store (`DeviceTokenVault`, `S:pos_main.dart:80-85`); selling and sync use that token. There is **no user JWT or refresh token on the till** to "restore".
- Daily sign-in is **username + 4-digit PIN**, checked on the till against a cached salted verifier (PBKDF2) that arrives in the bootstrap; wrong PINs are limited (five per name) and unknown names answer like wrong PINs (`S:features/lock/lock_screen.dart:25-40`; `docs/features/pos-pin/FEATURE.md`). Works offline.
- The wizard's "wrong app", force reset (Ctrl/Cmd+Shift+R, asks for a staff sign-in on a set-up till) and hard reset dialogs exist (`S:features/setup/presentation/force_reset_dialog.dart`, `hard_reset_dialog.dart`, `S:app/app.dart:753`). They delete local setup only, never platform data. The back-office "Reset terminal" refuses while a shift is open.
- `pos-cloud-sign-in-setup` (this spec's desktop parent) is built, uncommitted and **not validated** (`docs/FEATURE_INVENTORY.md` row `pos-cloud-sign-in-setup`).
- A one-terminal cloud licence keeps data in an encrypted SQLite file (`pos-cloud-single-till-sqlite`); its key lives in the secret store under `cloudDataKeyName` (`apps/xorder_pos_cloud/lib/main.dart:14-15`).

**Missing or different from the owner's spec:**
1. **Android secret storage.** `SecretPlatform.host` returns `development` for everything except Windows and macOS (`S:data/config/secret_store.dart:84-88`), i.e. the plaintext `DevelopmentFileSecretStore`. On Android that would hold the device token and the SQLite key in plaintext, against ADR-006 ("no plaintext fallback", `secret_store.dart:17-21`).
2. **Setup asks more than three things.** After sign-in the owner still picks the branch, adopts or names a terminal, and may pick a printer (`setup_state.dart:306-316`). The owner's spec says exactly three inputs.
3. **Daily sign-in is a PIN, not a password.** The owner's spec says Username + Password.
4. **Tablet layouts.** Breakpoints for three shells exist (`S:core/ui/tokens.dart:460`) but only the wide shell is finished (`README.md`). Phone and tablet shells are not built for the till. Nothing was checked on the tablet beyond the first screen.
5. **Terminal role on Android.** The Windows installer writes the role (`S:data/config/installed_role.dart`); with no installer, `installedRoleProvider` falls back to `TerminalRole.main` (`S:app/providers.dart:2225,2243`). Whether a tablet should be a main device or a child of a desktop main is undecided (Q3).
6. **Plain "change business".** No action named for it exists. Closest: back-office "Reset terminal" and the two reset dialogs; whether they leave tenant data (SQLite file, outbox, caches, printer settings) behind is **UNVERIFIED**.
7. **Hardware on Android.** Printing uses `win32`/winspool and macOS paths (`S:data/hardware/winspool.dart`); Android printer and scanner support is **UNVERIFIED** and probably absent. `window_manager` is already guarded to desktop (`S:pos_main.dart:53`, `:181`).
8. **Desktop-only packages** (`menu_bar`, `win32`, `screen_retriever`) built for Android (debug APK built) but runtime behavior on Android is **UNVERIFIED**.
9. First start on the tablet sat on the Flutter splash for about 20 seconds in a debug build before the first screen; cause **UNVERIFIED**.

## 6. Scope
**In**
- Android secret store using the platform keystore (blocker for everything below).
- Tablet layouts and touch behavior for the critical cloud POS screens: setup, sign-in, home/start, sale, payment, orders and history, shift, settings, receipt/printing hand-off.
- First-time setup per the owner's wording (see D1 and Q2), business remembered after it.
- Daily sign-in per Q1.
- Restart, force-stop, update, network-loss behavior (Scenarios A-E of the README).
- Authorized, confirmed **Change business** with full local cleanup (Scenario F).
- Android app identity, icon, orientation and manifest settings needed to run on tablets.
- Regression: desktop cloud and offline, Waiter app untouched.

**Out (unless the owner adds them)**
- Backend changes: no new endpoint, no response-shape change (README: do not assume new endpoints).
- ~~Offline-mode app on Android~~ — moved **in** on 2026-11-19 (Q3): the Offline app runs on a tablet as a child of a desktop main till. A tablet that is its own offline main (local PostgreSQL) stays out: Android cannot host it.
- Phone layouts for the till (tablets only), iOS/iPadOS.
- Full offline POS beyond what the existing outbox already gives.
- Card terminals, USB printer/scanner on Android (listed as a known gap, not built here, unless Q5 adds it).
- Publishing to Google Play, release signing, auto-update.

## 7. Behavior and business rules
Business rules that already hold are kept; new ones are marked **new**.
- **BR-1 (kept)** The cloud app is set up by the owner signing in; slug, username and password are typed once on the setup screen (`pos-cloud-sign-in-setup` BR-1, BR-3).
- **BR-2 (kept)** The password and the sign-in JWT live in memory only and never reach disk, logs or analytics.
- **BR-3 (new)** The business (slug) is saved only after sign-in succeeded and setup completed; a failed or interrupted setup saves nothing partial that would make the tablet look set up (see AC-3).
- **BR-4 (new)** Logout, restart, force-stop, update, a revoked or expired staff session and a network failure never clear the saved business or the device token, and never send the user to the slug screen.
- **BR-5 (new)** On Android the device token and the SQLite database key are stored only in the Android Keystore-backed store. There is no plaintext fallback: if the store cannot answer, the till says so and refuses to continue, as the desktop stores do (`SecretStoreUnavailable`).
- **BR-6 (new)** **Change business** is offered only to an authorized person, asks for confirmation that states what will be lost, and, once confirmed, deletes this tablet's business-specific local data (device token, database file or schema, outbox, caches, printer and terminal settings, remembered usernames) before showing the first-time setup. It never deletes platform data. If a shift is open or unsynced sales exist, it refuses or warns first (final rule: Q4).
- **BR-7 (new)** The wizard never reaches the slug screen on its own after setup. Navigation is driven by saved state, not by "first launch".
- **BR-8 (Q1)** Daily sign-in uses either PIN (today) or password; the rules for each are in Q1. Under no option is a password stored on the tablet.
- **BR-9 (kept)** The backend stays authoritative for prices, totals, taxes, permissions and order state; the tablet never recomputes them differently from desktop.

## 8. Acceptance criteria
Test kinds: **U** unit, **W** widget, **I** integration on a device or emulator, **P** a person looks.
- **AC-1** Given a clean Android tablet, when the app opens, then the cloud setup screen asks for business address, username and password and nothing about a licence key or licence server. (W, I)
- **AC-2** Given correct owner details, when the owner submits, then setup proceeds to the first sale screen and the saved configuration contains the slug. (U, I; the exact extra steps depend on Q2)
- **AC-3** Given a wrong slug, a wrong password, a staff (non-owner) account, or no internet during setup, then a specific message is shown and **no business is saved** (the app reopens on setup). (U, W)
- **AC-4** Given a set-up tablet, when it is restarted, force-stopped or the app is updated, then it opens on sign-in (or the start screen if still unlocked) and **never on the setup screen**. (I, P for the update case)
- **AC-5** Given a set-up tablet, when a user logs out and another signs in, then the second sign-in needs no slug. (W, I)
- **AC-6** Given no connectivity at launch or at sign-in, then a clear connection message and a retry are shown, the saved business is intact, and sales already committed are kept. (U, I)
- **AC-7** Given Android, when the device token and the database key are saved, then they are written through the Keystore-backed store and a plaintext `secrets.json` is never created; given the store is unavailable, then the till refuses to continue and says why. (U with a fake store, I)
- **AC-8** Given a person without the Change business permission, when they try to open it, then the control is hidden **and** the action is refused when invoked directly. (U, W)
- **AC-9** Given an authorized person confirms Change business, then every item in BR-6 is gone from the tablet, the previous business's name, staff, menu and sales are not visible, and the first-time setup opens. (U, I)
- **AC-10** Given each critical screen listed in section 6, when shown in landscape and portrait on the tablet (and a second tablet size), then there is no clipped, overlapping or unreachable control, the on-screen keyboard never hides the primary button, and touch targets meet the tokens in `S:core/ui/tokens.dart`. (W at the sizes, P on the device)
- **AC-11** Given Arabic, then the screens lay out right-to-left and all new strings exist in Arabic and English. (W, P)
- **AC-12** Windows and macOS builds of the cloud and offline apps pass their existing test suites and behave as before. (U, I)
- **AC-13** The password and tokens appear in no log, crash report, analytics event or file on the tablet. (U)

## 9. Edge cases and failure modes
- **Offline setup:** sign-in needs the platform; a drop after the terminal is claimed but before the bootstrap is saved must not create a second terminal on retry (idempotency of register by `client_transaction_id`, `cloud_api.dart:172`; retry behavior on this path **UNVERIFIED**).
- **Cached PIN verifier is stale** after the owner changes someone's PIN: handled by the next bootstrap pull; whether the tablet pulls it at restart is **UNVERIFIED**.
- **Revoked terminal:** the platform no longer accepts the device token; the till must say so and offer the authorized reset, not the slug screen (the existing force-reset exists because of this case, `force_reset_dialog.dart:21-28`).
- **Tenant boundary:** after Change business a previous tenant's rows must not be readable (local file removal, outbox emptied or refused if unsynced).
- **Unsynced sales on Change business:** never silently discarded (BR-6, Q4).
- **Screen rotation mid-sale and while typing a PIN:** state is kept.
- **Two taps or double submit:** the setup submit is disabled while in flight (README Phase 2).
- **Low-end tablet and slow first start** (about 20 s seen in debug, cause unknown): measured on a release build before it is called acceptable.
- **Arabic-Indic digits** in PIN and slug fields are folded as today (`FoldDigitsFormatter`).
- **Licence limits:** a one-terminal licence blocks a second terminal (`setup_controller.dart:1989-1992`); a tablet added to a business at its limit is refused by the platform (server enforcement **UNVERIFIED**, from `pos-cloud-sign-in-setup` §5).
- **Plan or feature off:** business without the POS feature is refused at setup with the existing message.

## 10. Impact
| Area | Change |
|---|---|
| `S:data/config/secret_store.dart` and a new Android store | New `SecretPlatform.android` using the platform keystore (needs a package or a platform channel; a new dependency, so needs approval) |
| `apps/xorder_pos_cloud/android/` | Android manifest, orientation, app name, icon, min SDK, signing config for debug only; currently generated and uncommitted |
| `S:features/setup/*` | Setup flow trimmed or defaulted per Q2; Change business entry (BR-6) |
| `S:features/lock/*` | Daily sign-in per Q1 |
| `S:core/ui/*`, screens under `S:features/{start,home,sale,payment,history,shift,settings}` | Tablet shell and breakpoints |
| `S:data/hardware/*` | Android printing/scanner: **not in scope** unless Q5 |
| Terminal role | Tablet role per Q3 |
| Cloud API | **None** expected. If Q1 picks password sign-in, a way to verify a username and password per user from the till is needed; the existing `POST /api/auth/login` is the only candidate and returns a JWT the till would have to hold (UNVERIFIED, would be a contract decision) |
| Contracts | Uses existing `POS-BE-*` items only; no new item unless Q1 changes it |
| Data / migrations | None on the platform. Local: a way to wipe a tenant's SQLite file for BR-6 |
| Permissions | None new unless Q4 says so |
| Localization | New strings (Arabic and English): setup errors, Change business, keystore-unavailable, connection retry |
| Documentation | `pos-cloud-sign-in-setup`, `pos-split-apps`, `pos-setup-installer` updates; new feature folder for this slug; README "Not built yet" |
| Deploy order | POS only. Nothing deploys on the cloud side first |

## 11. Dependencies, known gaps, risks
- **Hard dependency:** `pos-cloud-sign-in-setup` must be validated and committed first; this builds on code that is built but not validated.
- **Dependency:** `pos-cloud-single-till-sqlite` (encrypted SQLite) for the one-terminal cloud till; its key store is the one that is plaintext on Android today.
- **Risk (security):** until BR-5 lands, a tablet build holds the SQLite key and device token in plaintext. Treat any Android build before it as development only.
- **Risk (scope):** the README says the tablet shell is unfinished; "all critical screens usable" is a large UI task that is likely the biggest part of this feature.
- **Gap (hardware):** printers, cash drawer and scanner on Android are unknown and likely missing (`docs/domain/FOOD_SERVICE_DOMAIN.md` §3 lists card terminals as a gap too). A café till without a receipt printer may not be viable.
- **Gap (domain):** a food truck on a tablet depends on unreliable power and signal; the outbox covers sales, but cash-up and shift close while offline were not verified on Android.
- **Risk:** changing sign-in from PIN to password changes the speed of the counter workflow (typing a password at every lock) and the offline guarantee.

## 12. How it will be tested
| AC | Test |
|---|---|
| AC-1, AC-3, AC-5 | Widget tests of the cloud wizard and lock screen at tablet sizes with fake `CloudApi` and fake repositories (`xorder_pos_test_support`) |
| AC-2, AC-4, AC-6 | Unit tests of the startup state machine and config store; integration test on a device or emulator (`integration_test/`) for restart and force-stop |
| AC-7 | Unit tests of the Android store with a fake platform channel; on-device check that no plaintext secrets file exists |
| AC-8, AC-9 | Unit tests of the authorization rule and of the wipe (every BR-6 item); integration test on device |
| AC-10, AC-11 | Widget tests at two or three tablet sizes in both orientations, `ar` and `en`; a person walks every critical screen on the real tablet |
| AC-12 | Existing POS suites on desktop (`flutter test` in each app and `packages/shared_module`), run before and after |
| AC-13 | Unit test scanning logs, config and database after a full fake run |
| Not testable by machine | Print, scan, camera, real power and signal loss: a person on the tablet |

## 13. Decisions and open questions
**Decided**
- 2026-11-19: scope is the **full** spec (owner).
- 2026-11-19: the target is the cloud app (`apps/xorder_pos_cloud`) on Android tablets.
- D1 (carried from `pos-cloud-sign-in-setup` D2/D3/D5, 2026-11-08): sign-in only, owner only, business address typed as `____.xorder.io`. The owner's "Slug" field is this field.

**Open (each changes the build; asked in chat, answers recorded below)**
- **Q1** Daily sign-in on the tablet: keep the 4-digit PIN (works offline, no password stored), or Username + Password as the spec says (needs the network or a cached verifier, and a decision about how the till verifies a password).
- **Q2** Setup length: keep branch and terminal steps (as built), or reduce to the three fields and decide branch and terminal automatically (when there is one branch and one free terminal) and ask only when ambiguous.
- **Q3** Terminal role of a tablet: its own main till (SQLite, cloud), or a child that uses a desktop main over the LAN.
- **Q4** Who may Change business, and what happens to unsynced sales or an open shift. (Suggested: `terminal.manage` plus the owner's password re-entered; refuse while a shift is open or sales are unsynced.)
- **Q5** (suggestion, not asked of the owner yet) Should receipt printing on Android (network or Bluetooth printer) be part of this feature or a follow-up?

**Answers**
- **Q1** (2026-11-19, owner): daily sign-in is **Username + Password**, not the PIN. Consequences to settle in `/implement`'s plan (**Q1b, open**): the till has no password verifier today (the bootstrap carries only PIN verifiers, `docs/features/pos-pin/FEATURE.md`), so a password can only be checked by calling the platform (`POST /api/auth/login`, throttled, needs internet) or by a new cached verifier (a contract change). Until decided, the offline guarantee at the counter is **lost for sign-in**, and the PIN lock, the manager-PIN approvals and the idle lock (`S:features/lock/idle_lock.dart`) that use the PIN are unchanged unless the owner says otherwise.
- **Q2** (2026-11-19, owner): **auto when unambiguous**. Branch and terminal screens are skipped when the business has exactly one branch and one free terminal; asked otherwise.
- **Q4** (2026-11-19, owner): Change business needs `terminal.manage` plus the person's password re-entered, and is **refused** while a shift is open or any sale is unsynced.
- **Q3** (2026-11-19, owner): the tablet may be **either flavor, chosen at setup by which app is installed**: XOrder POS - Cloud or XOrder POS - Offline (the same idea as the Waiter app's two flavors). Consequences, verified in source: `apps/xorder_pos_offline/` has only `macos/` and `windows/` today, so it needs its own Android platform folder like the cloud app got. The offline app's data is PostgreSQL on a branch server (`S:core/config/deployment.dart:12-29`), and a tablet cannot run PostgreSQL, so an **offline tablet can only be a child** that connects to a desktop main till over the LAN (`TerminalRole.child`, `deployment.dart:276`; wizard path `childSteps`, `setup_state.dart:~330-349`). A **cloud tablet** can be its own main till (SQLite for a one-terminal licence) or a child.
- **Q6** (2026-11-19, owner): the offline tablet gets **its own short form** instead of the current child path. The fields are not yet decided. **Suggestion, not decided:** (1) the desktop till's address on the LAN (found by scan or typed), (2) a staff username, (3) that person's PIN; branch and terminal taken from the main till, asked only when ambiguous (the same rule as Q2). Needs the owner's OK in `/implement`'s plan, and the main till must expose what the form needs over the existing waiter-style LAN link (UNVERIFIED which call). Original question, kept for the record: what the **offline tablet's first-time setup** asks. The three-field rule (slug, admin username, password) is cloud-only; the offline child path today asks the main till's address, then account, branch and terminal. Should the offline tablet keep that path (address of the main till + staff sign-in) or get its own short form? And does Username + Password (Q1) apply to the offline tablet too? The offline platform has no cloud login to check a password against, so offline sign-in would stay a PIN unless the main till gains a password check.

Next: `/implement tablet-cloud-onboarding`. That will need approved: a new Android secret-store dependency, the Q1 and Q2 behavior changes (they alter existing sign-in and setup), and the Change business wipe. No migration, cloud deploy or contract change is expected unless Q1 chooses password sign-in.
