# API contract: Cashier PIN for the POS

Verified against: 2026-10-20 · cloud `main 06bc8e3` · POS `main d592db8` (uncommitted files in both repos are documentation, agent/script files and two POS files outside this feature; none is cited as evidence unless stated). Core state: `drafted` (author self-check, mechanical citation check; no independent validation pass). Path prefixes: `C:` = `apps/xorder-cloud/apps/api/`, `P:` = `apps/xorder-pos/`, `W:` = `apps/xorder-cloud/apps/web/`, `K:` = `apps/xorder-cloud/packages/`, `A:` = `apps/xorder-cloud/apps/`.

## Producers and consumers
`PUT|DELETE /api/dashboard/staff/{staff}/pin` — producer `C:app/Http/Controllers/Dashboard/PosPinController.php`; consumer `W:src/pages/dashboard/StaffView.vue:139,167`. Bootstrap `staff[].pin` — producer `C:app/Services/PosBootstrapService.php:333`; consumer `P:lib/data/cloud/bootstrap_bundle.dart:432-452`.

## Verified endpoints
| Method | Path | Middleware | Controller@method | Route |
| --- | --- | --- | --- | --- |
| PUT | `/api/dashboard/staff/{staff}/pin` | `auth:jwt`, `role:<tenant roles>`, `feature:pos`, `subscription.writable`, `throttle:10,1` | `Dashboard\PosPinController@update` | `C:routes/api.php:709` |
| DELETE | `/api/dashboard/staff/{staff}/pin` | same | `@destroy` | `:710` |

## Authentication and authorization
No `can:` middleware; guard in the controller (see `FEATURE.md`).

## Request and response examples (redacted)
`PUT` body `{"pin": "1234"}` (rule `^[0-9]{4}$`) → 200 `{"pin_set": true, "message": "..."}`. `DELETE` → 200 `{"pin_set": false, "message": "..."}`.
Bootstrap block: `"pin": {"algorithm": "pbkdf2_sha256", "iterations": 120000, "salt": "<base64>", "hash": "<base64>"}` or `null` (fake structure; `C:app/Support/PosPin.php:39-51`).

## Error formats
404 `staff_not_found`; 403 `no_access`; 422 validation on `pin`; 403 feature disabled (`pos`); 429 throttle.

## Idempotency, retries and concurrency
Each `PUT` makes a fresh salt, so two identical PINs give different verifiers.

## POS and other client usage
POS reads `staff[].pin` from `GET /api/pos/bootstrap`; it sends no PIN to the cloud.

## Backward compatibility
The wire block names the algorithm and iteration count; the POS ignores the count and uses 120000 (`P:lib/core/security/pin_hash.dart:38`), so a change of iterations needs a coordinated POS release.

## Contract tests
`C:tests/Feature/PosPinLengthTest.php:27,37`, `C:tests/Feature/Pos/PosProvisioningTest.php:242-263`.
