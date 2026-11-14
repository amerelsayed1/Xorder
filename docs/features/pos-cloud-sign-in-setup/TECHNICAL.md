# Cloud till setup by signing in — technical plan

Status: **built, uncommitted** (plan approved by the owner 2026-11-08) · 2026-11-08 · Scope: **cloud app only** (owner, 2026-11-08); the former stage 4 (licence server field debug-only in both apps) was dropped because that field now exists only on the Offline wizard · Specification: `FEATURE.md` (D2–D5) · Verified against: xorder-pos `development` `9f1b7d2` (clean tree), xorder-cloud `main`

Abbreviations: **SS** `packages/shared_module/lib/features/setup/domain/setup_state.dart` · **SC** `…/setup/application/setup_controller.dart` · **SP** `…/setup/presentation/setup_panes.dart` · **CPR** `apps/xorder_pos_cloud/lib/data/cloud/cloud_provisioning_repository.dart` · **W** `apps/xorder_pos_cloud/lib/wiring.dart` · **STR** `packages/shared_module/lib/core/l10n/app_strings.dart`

## Progress (2026-11-08)
| Stage | State | Notes |
|---|---|---|
| 1 Cloud path starts at sign-in | built | `cloudSteps` = account → branch → terminal → connecting → [hardware] → summary; first step chosen by `_firstStep`; fresh cloud draft gets `baseUrl = PlatformEndpoint.base`; `setTenantSlug` unlocked on cloud and names the database after the slug; `____.xorder.io` suffix field |
| 2 Owner only | built | CPR `_isOwner` reads `data.role == 'RESTAURANT_ADMIN'` in `connect`, `adoptTerminal`, `registerManually`; refusal `NOT_OWNER` → `refusalNotOwner` |
| 3 Licence before ready | built | `SetupController.receiveBundleLicence` (claim hook in W, and every bundle `_seedFromPlatform` pulls); `_cloudLicenceRefusal` at the end of `provisionTerminal` withholds `provisioned`; "Try again" re-pulls |
| 4 Pairing-code removal | built (done together with stage 1, to rewrite the tests once) | `SetupMethod`, `setMethod`, `setPairingCode`, `claimTerminal()`, `_PairingCodeFields`, `SetupMethodLabel` and 16 strings removed; `CloudApi.claimTerminal`/CPR `claimByCode` kept (adoption uses them) |
| 5 End-to-end driver | rewritten, **not run** | `till_driver.completeSetup` walks owner sign-in; the spent-code e2e test, `E2ePlatform.provisionTerminal` and `support/e2e_licence.dart` removed (the licence now comes from the platform) |

**Found while building (not in the plan):**
- The old pairing claim set the till's **language and sync policy** from the business. The sign-in road did not; `registerTerminal` now does it for a cloud main device, so that behaviour is kept.
- A cloud till **resumed after a restart** holds its licence in the draft (restored from progress) but had received no bundle on this run. The first version of the licence check refused it. It now judges the licence the draft holds, and the latest bundle's refusal still wins. Covered by `cloud_setup_collapsed_test.dart` "a restart between the claim and Open the till".
- The adopt list already offers only `provisioned` terminals (`PosTerminalSummary.isAdoptable`), so an owner cannot cut off a till in use. The §7 risk was already handled.

## 1. Specification re-checked against the code
| Claim in FEATURE.md | Holds? | Evidence |
|---|---|---|
| Sign-in road exists (login → branches → terminals → adopt / register) | Yes | SC `connectTenant` 1510-1554 → CPR `connect` 75-184; SC `registerTerminal` 1838-1952 → CPR `adoptTerminal` 216-256 / `registerManually` 286-330 |
| Password and JWT never persisted | Yes | JWT is a local per call (CPR 100, 231, 306); `operatorPassword` in memory only (SS 415-417); `SetupProgress.toJson` has neither (`setup_progress_store.dart:84-96`) |
| Login reply carries the role | Yes, **but nothing reads it** | Server: `AuthController@login` returns `UserResource` (`role`, `UserResource.php:20`). POS: no reader of `role` in `lib/` |
| Licence arrives in the claim's bundle and is installed | Yes, **but the result is dropped** | CPR 371-380 swallows errors; W 156-181 keeps only the file (`holdLicence`), dropping entitlement, claims and notice |
| Seat limit (§5 UNVERIFIED) | **Verified: server refuses** | `PosProvisioningService` `assertSeatAvailable` on provision (74), claim (198), register (277) → 422 `TERMINAL_SEAT_LIMIT` with counts |
| Retry idempotency (§9 UNVERIFIED) | **Verified** | register replays on `client_transaction_id` (255-261); claim replays for the same fingerprint inside the TTL (160-170) |
| Two tills adopting one slot (§9 UNVERIFIED) | **Verified: last one wins** | a new pairing code expires older unused ones (113-115); re-claiming an active terminal re-keys its device token (192-213), so the earlier till is cut off |

**Discrepancies found (they change the plan, not the description):**
1. The licence step is not only a gate. Through `_adopt(claims)` (SC 1365-1391) it is **the only place a cloud draft gets `baseUrl`** (SC 1377-1379), and it sets `databaseName` from the slug (1387-1389). Without `baseUrl`, `posCloudApiProvider` is null (`app/providers.dart:697-709`) and provisioning falls back to the unconfigured repository (W 139-140). Removing the step needs a new home for both.
2. `setTenantSlug` is locked once `claims != null` (SC 468). A licence restored from disk (`_restoreInstalledLicence`, SC 159-199) would lock the new address field.
3. The pairing-code road is the cloud **default** today (SS 124-129), and `SetupMethod` reaches labels (`app/labels.dart:51-59, 84-118`).
4. The `localhost:8080` in the screenshot is the **debug** default (`core/config/platform_endpoint.dart:45`, `kDebugMode ? devDefault : production`). Release builds show the production address, but the field is still visible (BR-8).

## 2. Reuse (do not rebuild)
- Sign-in, branch and terminal pulls, adopt-by-self-issued-code, register: all as they are (CPR).
- `slugFrom` (SC 443-449) already reduces `cafe-nile.xorder.io` or a URL to `cafe-nile`.
- `LicenseVerifier.evaluateClaims` (`licensing/domain/license_verifier.dart:224-253`) already produces `LicenceCoversBothModes` and `LicenceModeNotCovered` under `singleModeOnly` (`app/providers.dart:2122`). It also detects a tenant mismatch.
- `provisioningRefusal` codes → strings (`app/labels.dart:232-252`). The new `NOT_OWNER` goes here.
- `_restoreProgress` resumes at `visibleSteps.first` (SC 241, 290), so it follows the new first step without change.

## 3. Impact
| Area | Change |
|---|---|
| `packages/shared_module` setup (SS, SC, SP, `labels.dart`, STR) | Cloud-path only: cloud steps, slug field, pairing-code removal, licence check after connecting. Every shared edit is guarded by the cloud mode; offline and child paths keep today's behaviour |
| `apps/xorder_pos_cloud` (CPR, W) | Owner check on the login reply; installLicence reports its verdict |
| `apps/xorder_pos_offline` | **None.** Its wizard is untouched (AC-11) |
| Child tablet path | **None** (`childSteps`) |
| Cloud API, contracts, schema | **None.** No `POS-BE` item, no migration |
| Money, orders, outbox | Not touched |
| Tenant isolation | Unchanged: the business slug scopes login on the server (`AuthController.php:99-101`) |
| Deploy order | POS only. Production use needs xorder-cloud `feat/licence-one-mode` (`30b1529`) on `main` and a cloud-only licence for the business (D4) |

**Domain lens:** setup-only. It serves every cloud venue (café, restaurant, cloud kitchen, food truck on the cloud plan). It needs internet during setup only, which the cloud path already needs. No tables, addresses or counters are assumed.

## 4. Stages
Each stage ends with `flutter analyze` and the stage's tests green before the next starts.

### Stage 1 — the cloud path starts at sign-in (shared)
- **SS:**
  - `cloudSteps` drops `SetupStep.licence`. The path becomes `account → branch → terminal → connecting → [hardware] → summary`.
  - The cloud main device's `method` is always `manual` (sign-in).
  - Adjust `canAdvance` for `account` on cloud to require `connected` (today it requires only the slug, SS 580).
- **SC:**
  - `build()` opens a cloud draft on `visibleSteps.first` instead of the hard-coded licence step (SC 108, 133).
  - Give a cloud draft its `baseUrl` from `_platformFor` at build (moved out of `_adopt`).
  - Set `databaseName` from the slug when the slug is set.
  - `setTenantSlug` stops being locked by `claims` on the cloud path.
- **SP:**
  - The cloud `_AccountPane` shows the business address with a `.xorder.io` suffix (D5), plus username and password, then **Sign in**.
  - Remove the pairing-or-sign-in switch and link on cloud (SP 871-890).
  - The adopt list in `_TerminalPane` stays (SP 1297).
- **STR (en + ar):**
  - New: `businessAddress`, `businessAddressHelp`, `signInTitle`, `signInBlurb`.
  - Reword the account step title for cloud.
- **Tests:**
  - Rewrite `cloud_setup_collapsed_test.dart` 'the screens a cloud main device is shown' (347-401) to expect `account/branch/terminal/connecting/summary`.
  - `setup_wizard_test.dart` 'opens on the licence…' (526) and 'the licence is asked first, on either path' (565) become cloud = sign-in, offline = licence.
  - Same for `licence_decides_mode_test.dart` 167, 209.
  - New: the slug field strips `.xorder.io`; `baseUrl` is set without a licence.
- **Rollback:** revert the stage; no persisted format changes (`SetupProgress` keeps its fields).

### Stage 2 — owner only (cloud app)
- **CPR `connect`:**
  - After a 200 login, read `data.role`. If it is not `RESTAURANT_ADMIN`, return a refusal `NOT_OWNER` and drop the JWT. No branch or terminal call is made.
  - `adoptTerminal` and `registerManually` log in again (CPR 225, 300) and apply the same check.
  - Remove the fallback texts that say "or use a setup code instead" (CPR 237, 314).
- **Shared:**
  - `labels.dart` maps `NOT_OWNER` to `refusalNotOwner` ("Only the business owner can set up a till.", en + ar).
  - Also map `TERMINAL_SEAT_LIMIT` with its counts, if it is not already mapped (check while building).
- **Fakes:** `FakeProvisioningRepository.connect` gains a non-owner account.
- **Tests:**
  - A new cloud-app test, `apps/xorder_pos_cloud/test/data/cloud_provisioning_owner_test.dart`, with a stub `CloudApi`:
    - an owner continues;
    - `RESTAURANT_STAFF` gets `NOT_OWNER` with zero further calls;
    - a 401 still maps to credentials rejected;
    - `TERMINAL_SEAT_LIMIT` is shown.
  - `terminal_adoption_test.dart` (108-188) is updated for the owner account.
- **Rollback:** revert. The server is unchanged either way.

### Stage 3 — the licence is checked before "ready"
- **W `installLicence`:** return the verifier's result (entitlement, claims, notice) to the wizard instead of only the file (W 165). The exception at CPR 376-379 is reported, not swallowed.
- **SC `provisionTerminal`:**
  - After seeding (SC 1782), it requires a held licence that is `canSell`, names only `cloud`, and matches the signed-in tenant.
  - On refusal it does **not** set `provisioned` (SS 601), and shows a refusal on the connecting pane (no licence / both modes / offline licence / other business / expired) with **Try again**.
  - Try again re-runs `provisionTerminal`, whose `_seedFromPlatform` pulls a fresh bootstrap with the device token (SC 2023). That pull also installs the bundle's licence, so a licence fixed on the dashboard is picked up without a new claim.
- **Tests:**
  - Move `fixed_app_mode_test.dart` 83 and 106 (other-mode and both-mode licences) to the cloud post-bootstrap check.
  - New cases: no licence in the bundle; the licence fixed and retried; a tenant mismatch.
  - `setup_persistence_test.dart` 557 ('a licence from the bootstrap bundle waits with the rest') stays green.
- **Rollback:** revert. The start screen's licence gate still blocks an unlicensed till, as today.

### Stage 4 — remove what the cloud path no longer uses
"No unused code in the cloud" (the owner, pos-split-apps). After stages 1–3 nothing selects `SetupMethod.pairingCode`.
- **Delete:**
  - `SetupMethod`, `setMethod`, `setPairingCode`, `pairingCode`;
  - the controller's `claimTerminal()` (SC 1562-1615);
  - `_PairingCodeFields` (SP 898-970);
  - the `SetupMethodLabel` extension and the method arguments in `labels.dart`;
  - the strings `stepSetupCode*`, `setupCode*`, `claimThisTerminal`, `signInInstead`, `useASetupCodeInstead`, `methodPairingCode*`, `claimedFromDashboardHelp`, if no other reader remains.
- **Keep:** `CloudApi.claimTerminal` and CPR `claimByCode`. Adopting an existing till still claims through a self-issued code (CPR 216-256).
- **Tests:** delete the pairing-code tests (`setup_wizard_test.dart` 935, 954, 970, 996; `cloud_setup_collapsed_test.dart` 792-866), and update `localisation_test.dart` (886).
- **Rollback:** revert the stage alone. Stages 1–3 do not depend on it.

### Stage 5 — the cloud end-to-end driver
- `integration_test/support/till_driver.dart` `completeSetup` (110-189) is already stale (it walks a setup type, language and pairing code). Rewrite it to: sign in as owner → branch → terminal → connecting → summary.
- **Runs only against a local API and PostgreSQL.** If none is available, it is reported **not run**.

## 5. Verification
```
cd apps/xorder-pos/packages/shared_module && flutter analyze && flutter test test/features
cd apps/xorder-pos/apps/xorder_pos_cloud   && flutter analyze && flutter test
cd apps/xorder-pos/apps/xorder_pos_offline && flutter test       # AC-11: offline untouched
cd apps/xorder-pos && scripts/check.sh                            # every member, PostgreSQL included
```
Then a person runs the cloud app (`flutter run -d macos`) once in Arabic and once in English.

## 6. AC → stage → test
| AC | Stage | Test |
|---|---|---|
| AC-1 | 1, 4 | cloud wizard widget test: first screen fields; no licence or pairing field |
| AC-2 | 1 | sign-in controller test: tenant name and branches pulled |
| AC-3, AC-4 | 1 | `terminal_adoption_test.dart` (adopt; register) |
| AC-5, AC-6 | 3 | post-bootstrap licence check tests |
| AC-7 | 2 | `cloud_provisioning_owner_test.dart` |
| AC-8 | 1, 2 | refusal mapping tests (401, unknown business, offline) |
| AC-9 | 1 | persistence test: no password or JWT in `SetupProgress` or the config after a run |
| AC-10 | 1 | cloud wizard widget test: no licence or licence-server field on the cloud path (the field remains on the Offline wizard, unchanged) |
| AC-11 | all | offline app suite unchanged and green |
| AC-12 | 1, 2, 3 | `localisation_test.dart` keys in both languages; a person looks at the Arabic screen |

## 7. Approvals and risks
- **Approval needed:** this plan. D3 narrows what the **till** lets a staff account do (a permission narrowing, already decided by the owner on 2026-11-08). No migration, contract, payment or order-state change, and nothing reaches xorder-cloud `main`.
- **Risk:** until `feat/licence-one-mode` is on production `main` and a cloud-only licence is issued, a cloud till built from this cannot finish setup (by design, D4).
- **Risk:** the adopt list may offer a terminal that is already **active**. Adopting it re-keys that terminal and cuts off the till using it (§1). The plan keeps today's list filter. Whether it already hides active terminals is checked in stage 1, and if it does not, active terminals are listed as "in use" and cannot be picked.
- **Not done:** no server-side owner-only rule; no forgotten-password flow on the till; nothing in the Offline app.
