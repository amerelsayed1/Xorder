# Feature specification: Cashier PIN for the POS

Status: implemented (cloud API sets/clears the PIN verifier; the till verifies it locally)
Slug: `pos-pin` · Module: `roles-and-staff` · Footprint: shared (bootstrap download carries the verifier; the POS verifies and, in offline mode, sets PINs locally)
Verified against: 2026-10-20 · cloud `main 06bc8e3` · POS `main d592db8` (uncommitted files in both repos are documentation, agent/script files and two POS files outside this feature; none is cited as evidence unless stated). Core state: `drafted` (author self-check, mechanical citation check; no independent validation pass). Path prefixes: `C:` = `apps/xorder-cloud/apps/api/`, `P:` = `apps/xorder-pos/`, `W:` = `apps/xorder-cloud/apps/web/`, `K:` = `apps/xorder-cloud/packages/`, `A:` = `apps/xorder-cloud/apps/`.

## Summary
A staff member's four-digit POS PIN is set or cleared from the cloud dashboard. The cloud stores only a salted PBKDF2-SHA256 verifier and delivers it to tills in the bootstrap bundle; the till verifies a typed PIN against it locally. Setting or clearing a PIN bumps the restaurant's POS configuration version.

## Scope and exclusions
Implemented: `PUT/DELETE /api/dashboard/staff/{staff}/pin`, the hashing helper, bootstrap delivery, POS verification and lock screen, POS-side PIN rules and local set paths.
Not found: any cloud endpoint that reads a PIN; a PIN-set test that asserts the stored hash; a DELETE test; a cross-implementation hash-compatibility test.

## Actors and permissions
| Actor | Rule | Enforced by | Evidence |
| --- | --- | --- | --- |
| Any tenant user | may set or clear **their own** PIN (even without staff capabilities) | `PosPinController::guard` | `C:app/Http/Controllers/Dashboard/PosPinController.php:88-92` |
| Holder of `staff.update` | may set or clear another staff member's PIN | same | `:90-92` |
| Anyone but the owner | may not touch the owner's PIN (404) | same | `:95-97` |
| Cross-tenant or non-tenant account targets | 404 | same | `:80-86` |
The routes require the `pos` feature, an active subscription and `throttle:10,1`, with no `can:` middleware (`C:routes/api.php:709-710`; group comment `:703-705`).

## Current implemented behavior
1. `PUT`: `SetPosPinRequest` requires `pin` matching `^[0-9]{4}$` (exactly four ASCII digits) (`C:app/Http/Requests/Dashboard/SetPosPinRequest.php:19-29`); the controller guards, creates a salted verifier with `PosPin::make`, stores `pos_pin_salt` and `pos_pin_hash` by `forceFill`, bumps `restaurants.pos_config_version`, records audit `staff.pos_pin_set` (action and name, never the PIN) and returns `{pin_set: true, message}` (`PosPinController.php:29-54`).
2. `DELETE`: guards, nulls both columns, bumps the config version, records `staff.pos_pin_cleared`, returns `{pin_set: false, message}` (`:57-74`).
3. Hash: PBKDF2-HMAC-SHA256, 120000 iterations, 16-byte random salt per set, 32-byte key, both base64 (`C:app/Support/PosPin.php:19-36`). The bootstrap emits `{algorithm, iterations, salt, hash}` or null (`:39-51`, `C:app/Services/PosBootstrapService.php:333`).
4. POS side: `PinRules.length = 4` with ASCII-digit check; `PinHash` uses PBKDF2-HMAC-SHA256 with 120000 iterations, 16-byte salt, 256-bit key, base64; `verify` compares in constant time (`P:lib/core/security/pin_hash.dart:24-74`). The bootstrap `iterations` value is parsed but not stored; `verify` always uses the constant (`P:lib/data/cloud/bootstrap_bundle.dart:432-452`, `bootstrap_seeder.dart:465-483`, `pin_hash.dart:38`).
5. POS stores `pin_salt`/`pin_hash` (`''` when there is no PIN) in `pos_staff` and verifies where `is_active` (`P:lib/data/postgres/postgres_directory_repositories.dart:164,244,447`); the lock screen unlocks at four digits (`P:lib/features/lock/lock_screen.dart:94-100`).
6. On a cloud till `resetPin` is refused with `ManagedByPlatform`; the PIN is set from the dashboard (`P:lib/data/postgres/postgres_admin_repositories.dart:773-778`). In offline mode the POS sets PINs itself (`:463-464,788-789`).
7. Dashboard: `W:src/pages/dashboard/StaffView.vue:139,167` (PUT, DELETE), shown when the tenant has the `pos` feature, to self or to a holder of update on a non-owner (`:114-116`); the PIN confirm requires four digits (`:130`).

## User journeys and workflows
Manager opens Staff → Set PIN → the cashier enters the PIN on the till after the next bootstrap download.

## Business rules
| ID | Rule | Where implemented | Evidence |
| --- | --- | --- | --- |
| BR-1 | A PIN is exactly four ASCII digits. | request (cloud), `PinRules` (POS) | `SetPosPinRequest.php:19-29`; `pin_hash.dart:24-32`; tests `C:tests/Feature/PosPinLengthTest.php:27,37`, `P:test/core/pin_rules_test.dart` |
| BR-2 | Only a salted PBKDF2 verifier is stored; the PIN is never logged or returned. | controller, helper | `PosPin.php`; `PosPinController.php:46-51`; test `C:tests/Feature/AuditSecretsTest.php:50-69` |
| BR-3 | Self-service is always allowed; others need `staff.update`; the owner's PIN is untouchable by others. | `guard` | `PosPinController.php:88-97` |
| BR-4 | Setting or clearing a PIN bumps `pos_config_version`. | controller | `PosPinController.php:44,65`, `C:app/Services/PosConfigVersion.php:37-46` |
| BR-5 | Cloud and POS use the same algorithm parameters (algorithm, 120000 iterations, salt and key lengths, base64). | helper / `PinHash` | `PosPin.php:19-25`; `pin_hash.dart:38-55` |

## Validation and error handling
422 on any other pin shape (tests assert `482`, `48291`, `482913`, `48a9` and Arabic-Indic digits are refused and nothing is stored: `PosPinLengthTest.php:37`); 404 for out-of-scope targets; 403 `no_access` without `staff.update` on others; 403 when the `pos` feature is off (`EnsureFeatureEnabled`, `feature:pos`); 429 throttle.

## Edge cases and failure handling
- A null verifier is sent as `pin: null`; the POS tolerates it (`P:test/data/cloud_bootstrap_test.dart:145-150`).
- Config-version freshness after staff changes, deleted staff and signup tenants without the `pos` feature: `BEHAVIORAL_ANALYSIS.md`.

## Cross-application dependencies
Cloud PBKDF2 (`PosPin`) and POS `PinHash` must agree; there is no test that crosses the two implementations. Delivery is by `GET /api/pos/bootstrap` (`staff[].pin`).

## Security considerations
- PIN keyspace is 10^4 and the verifier travels to every till of the restaurant; the verifier is behind the device credential (`PosDeviceAuth`).
- Audit and activity logs exclude PIN data (`C:app/Models/User.php:24-26`, test `AuditSecretsTest.php:50-110`).
- Not mass-assignable: set only by `forceFill`.
- The migration docblock and `PosPin.php` comments disagree on the keyspace wording (4-6 vs 4 digits); the code allows only four (`SetPosPinRequest.php`, 2026-10-16 change per its docblock).

## Known limitations
- No cloud-side PIN attempt counter (verification is on the till).
- Stale phrase in `C:database/migrations/2026_09_02_000300_add_pos_columns_to_restaurants_and_users.php` docblock ("4-6 digit").
- The coordination file records a bcrypt decision for POS-BE-024 in a historical changelog row; the code is PBKDF2 (`apps/xorder-cloud/docs/coordination/BACKEND_TO_POS.md:218,2723`).

## Existing automated tests
| Layer | File and test | Covers | Gaps |
| --- | --- | --- | --- |
| Cloud feature | `C:tests/Feature/PosPinLengthTest.php:27,37` | four digits accepted; other shapes refused and nothing stored | the stored hash, DELETE, guard cases (another's PIN with/without `staff.update`, owner's PIN, cross-tenant 404), `feature:pos` 403, throttle, config-version bump |
| Cloud feature | `C:tests/Feature/AuditSecretsTest.php:50-110` | audit never contains PIN columns | |
| Cloud feature | `C:tests/Feature/Pos/PosProvisioningTest.php:242-263` | bootstrap staff row has the PBKDF2 block, iterations 120000, salt, capabilities | null-PIN row; hash value |
| POS | `P:test/core/pin_rules_test.dart` (no database), `P:test/data/cloud_bootstrap_test.dart:145-150` | `PinRules`, bootstrap parse | cross-implementation compatibility |

## Acceptance criteria
- AC-1: A PIN of exactly four digits is stored as a salted PBKDF2 verifier; other shapes are refused.
- AC-2: The PIN is never returned or logged.
- AC-3: A user can set their own PIN; others need `staff.update`; the owner's PIN is only theirs to change.
- AC-4: The verifier reaches tills in the bootstrap and the till accepts the PIN.
- AC-5: Setting or clearing a PIN bumps the POS config version.

## Confirmed source references
`C:routes/api.php:705-711`; `C:app/Http/Controllers/Dashboard/PosPinController.php`; `C:app/Http/Requests/Dashboard/SetPosPinRequest.php`; `C:app/Support/PosPin.php`; `C:app/Services/PosBootstrapService.php:333`; `C:app/Services/PosConfigVersion.php`; `P:lib/core/security/pin_hash.dart`; `P:lib/data/cloud/bootstrap_seeder.dart:465-483`; `P:lib/features/lock/lock_screen.dart`.

## Unknowns and assumptions
- UNVERIFIED: that a PHP-made verifier verifies on the Dart side (no test); `Auditable` row content for user updates; empty-salt hashing behavior of the Dart crypto package for the no-PIN case.
