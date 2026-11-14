# Test plan: Platform (Super Admin portal) users

Verified against: 2026-10-20 · cloud `main 06bc8e3` · POS `main d592db8` (uncommitted files in both repos are documentation, agent/script files and two POS files outside this feature; none is cited as evidence unless stated). Core state: `drafted` (author self-check, mechanical citation check; no independent validation pass). Path prefixes: `C:` = `apps/xorder-cloud/apps/api/`, `P:` = `apps/xorder-pos/`, `W:` = `apps/xorder-cloud/apps/web/`, `K:` = `apps/xorder-cloud/packages/`, `A:` = `apps/xorder-cloud/apps/`.

## Test environments
`php artisan test --filter "PlatformUserTest|UserCreationMatrixTest"` (SQLite).

## Acceptance criteria to tests
| AC | Existing test | Coverage | Planned addition |
| --- | --- | --- | --- |
| AC-1 | `C:tests/Feature/Admin/PlatformUserTest.php:22,44,155`, `UserCreationMatrixTest.php:79` | covered | supplied password path, status SUSPENDED |
| AC-2 | `PlatformUserTest.php:115,123`, `UserCreationMatrixTest.php:131,140,154` | covered | |
| AC-3 | `PlatformUserTest.php:132,141` | delete and tenant target | PUT on Super Admin, self-targets, reset-password |
| AC-4 | `PlatformUserTest.php:92,106` | partial route-level | each role vs each capability |

## Unit tests
None.

## Integration and API tests
Reset-password (including throttle), credentials mail, audit events.

## Flutter/Vue UI tests
No framework.

## Security and tenancy
Tenant users refused (covered).

## Order/pricing/payment invariants
Not applicable.

## Regression and manual QA
Create a SALES user, sign in, confirm access to leads/plans and refusal on restaurants.manage routes.

## Test data/fixtures
Helpers in `PlatformUserTest.php`.
