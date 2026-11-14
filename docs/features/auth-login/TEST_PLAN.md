# Test plan: Login, session token and password change

Verified against: 2026-10-20 · cloud `main 06bc8e3` · POS `main d592db8` (uncommitted files in both repos are documentation, agent/script files and two POS files outside this feature; none is cited as evidence unless stated). Core state: `drafted` (author self-check, mechanical citation check; five independent passes (rounds 1-5), criterion not met: `docs/validation/2026-10-20-batch1-*-report.md`). Path prefixes: `C:` = `apps/xorder-cloud/apps/api/`, `P:` = `apps/xorder-pos/`, `W:` = `apps/xorder-cloud/apps/web/`, `K:` = `apps/xorder-cloud/packages/`, `A:` = `apps/xorder-cloud/apps/`.

## Test environments
Cloud: `cd apps/xorder-cloud/apps/api && php artisan test --filter "AuthTest|PerTenantAuthTest|JwtRoundTripTest|ChangePasswordTest|SecurityHardeningTest"` (PHPUnit on SQLite `:memory:`, test `JWT_SECRET`). No Vue test framework exists; POS has no login test (the e2e helper `P:integration_test/support/e2e_platform.dart:64` performs a login as setup) (only a log-masking fixture string in `P:test/core/network_log_test.dart:63`).

## Acceptance criteria to tests
| AC | Existing test | Coverage | Planned addition |
| --- | --- | --- | --- |
| AC-1 | `C:tests/Feature/AuthTest.php:15` and `PerTenantAuthTest.php:67,76` (status and `data.*`); a returned token that works: `C:tests/Feature/JwtRoundTripTest.php:17-18,27-31`, `ChangePasswordTest.php:21-23` | covered | assert `token_type`, `expires_in` |
| AC-2 | `AuthTest.php:33,42` | covered | 403 body; wrong password on a suspended account returns 401 |
| AC-3 | `PerTenantAuthTest.php:19,30,48,58` | covered | unknown `restaurant` slug |
| AC-4 | `JwtRoundTripTest.php:21,34,43` | partly | expired token (time travel), `rid` mismatch, real bearer token for a suspended user |
| AC-5 | `SecurityHardeningTest.php:30,44` | covered | token issued in the same second as the change |
| AC-6 | `ChangePasswordTest.php:15,39,51,63` | covered | throttle `6,1` |
| AC-7 | `SecurityHardeningTest.php:154` | account axis covered | IP axis (10/min) |
| AC-8 | none | gap | logout returns success; token still works afterward (documents BR-8) |

## Unit tests
None exist; candidates: `Jwt::issue`/`parse` claims and expiry.

## Integration and API tests
The cloud tests above. Gaps: 422 shapes, audit events `auth.login_blocked`, `auth.logout`, `auth.password_changed`.

## Flutter/Vue UI tests
No framework for Vue; manual check of the login page error display (`W:src/pages/LoginView.vue:55-57`). POS: pairing flow tests are outside this feature.

## Security and tenancy
Cross-tenant login isolation is covered (`PerTenantAuthTest.php`); add a token minted for tenant A used after the user's `restaurant_id` changes (BR-5).

## Order/pricing/payment invariants
Not applicable.

## Regression and manual QA
Sign in on admin and restaurant hosts; change password and confirm the old token on another device stops working; suspend a user and confirm both a fresh login (403) and an existing token (401) fail.

## Test data/fixtures
Factories/helpers in the cloud tests (e.g. `PerTenantAuthTest.php`); test `JWT_SECRET` in `C:phpunit.xml:25-31`.
