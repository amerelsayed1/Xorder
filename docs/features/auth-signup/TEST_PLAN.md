# Test plan: Self-service restaurant signup

Verified against: 2026-10-20 · cloud `main 06bc8e3` · POS `main d592db8` (uncommitted files in both repos are documentation, agent/script files and two POS files outside this feature; none is cited as evidence unless stated). Core state: `drafted` (author self-check, mechanical citation check; no independent validation pass). Path prefixes: `C:` = `apps/xorder-cloud/apps/api/`, `P:` = `apps/xorder-pos/`, `W:` = `apps/xorder-cloud/apps/web/`, `K:` = `apps/xorder-cloud/packages/`, `A:` = `apps/xorder-cloud/apps/`.

## Test environments
`cd apps/xorder-cloud/apps/api && php artisan test --filter "SignupTest|RestaurantFeatureTest"` (SQLite).

## Acceptance criteria to tests
| AC | Existing test | Coverage | Planned addition |
| --- | --- | --- | --- |
| AC-1 | `C:tests/Feature/SignupTest.php:28` | covered | |
| AC-2 | `SignupTest.php:35` | covered (restaurant, owner, TRIAL, notification) | licence row, roles, feature rows |
| AC-3 | `SignupTest.php:68` | covered | |
| AC-4 | `SignupTest.php:58` | covered | |
| AC-5 | `SignupTest.php:78` (Arabic name) | partial | reserved slug, collision, `r-` fallback |

## Unit tests
`SlugService::unique` and `normalize` have no direct tests found.

## Integration and API tests
Add throttle (6th request in 10 minutes), invalid `whatsapp`, rollback when licence issue fails.

## Flutter/Vue UI tests
Not applicable.

## Security and tenancy
Assert the owner row has `restaurant_id` of the new restaurant (covered in `SignupTest.php:35`).

## Order/pricing/payment invariants
Not applicable.

## Regression and manual QA
Enable the flag in a staging environment, sign up, read the mail, sign in.

## Test data/fixtures
Test config sets the flag in `SignupTest.php`.
