# Test plan: Password reset by email

Verified against: 2026-10-20 · cloud `main 06bc8e3` · POS `main d592db8` (uncommitted files in both repos are documentation, agent/script files and two POS files outside this feature; none is cited as evidence unless stated). Core state: `drafted` (author self-check, mechanical citation check; no independent validation pass). Path prefixes: `C:` = `apps/xorder-cloud/apps/api/`, `P:` = `apps/xorder-pos/`, `W:` = `apps/xorder-cloud/apps/web/`, `K:` = `apps/xorder-cloud/packages/`, `A:` = `apps/xorder-cloud/apps/`.

## Test environments
Cloud: `cd apps/xorder-cloud/apps/api && php artisan test --filter SecurityHardeningTest` (SQLite `:memory:`, mailer `array`).

## Acceptance criteria to tests
| AC | Existing test | Coverage | Planned addition |
| --- | --- | --- | --- |
| AC-1 | `C:tests/Feature/SecurityHardeningTest.php:99` | covered | assert body equality between existing and unknown email |
| AC-2 | `SecurityHardeningTest.php:55` | covered | old token rejected after reset (end to end) |
| AC-3 | `SecurityHardeningTest.php:74` | covered | expired token |
| AC-4 | `SecurityHardeningTest.php:138` | covered | |
| AC-5 | none | gap | 6th request within a minute returns 429 for both endpoints |

## Unit tests
None.

## Integration and API tests
Add: link host/slug for a tenant user and a platform user (`:119` asserts only path, token and email); platform-user reset; account without email.

## Flutter/Vue UI tests
Not applicable (no client).

## Security and tenancy
Enumeration checks exist (AC-1, AC-3). Add: reset for a suspended user.

## Order/pricing/payment invariants
Not applicable.

## Regression and manual QA
Manual: request a link in a staging environment, open it, confirm which page answers.

## Test data/fixtures
Users created in the test file; broker tokens created via the `Password` facade in `SecurityHardeningTest.php`.
