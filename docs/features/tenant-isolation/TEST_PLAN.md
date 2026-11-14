# Test plan: Tenant isolation (restaurant scope)

Verified against: 2026-10-20 · cloud `main 06bc8e3` · POS `main d592db8` (uncommitted files in both repos are documentation, agent/script files and two POS files outside this feature; none is cited as evidence unless stated). Core state: `drafted` (author self-check, mechanical citation check; no independent validation pass). Path prefixes: `C:` = `apps/xorder-cloud/apps/api/`, `P:` = `apps/xorder-pos/`, `W:` = `apps/xorder-cloud/apps/web/`, `K:` = `apps/xorder-cloud/packages/`, `A:` = `apps/xorder-cloud/apps/`.

## Test environments
`php artisan test --filter "TenantIsolationTest|TenantRbacTest"` (SQLite).

## Acceptance criteria to tests
| AC | Existing test | Coverage | Planned addition |
| --- | --- | --- | --- |
| AC-1 | `C:tests/Feature/TenantIsolationTest.php:24`, `TenantRbacTest.php:243,389,564` | categories, staff, roles | one test per model family (orders, customers, stock, purchasing) |
| AC-2 | `TenantIsolationTest.php:39,52` | covered for category and item | other scoped models |
| AC-3 | none direct | gap | unit test of the trait stamping and explicit-id preservation |
| AC-4 | none found | gap | device token of tenant A cannot read tenant B; override cleared after the request |
| AC-5 | `C:tests/Feature/TenantRbacTest.php:214`, `UserCreationMatrixTest.php:435`, `SecurityHardeningTest.php:197` | covered | |

## Unit tests
None for `RestaurantScope`, `BelongsToRestaurant`, `TenantContext`.

## Integration and API tests
As above.

## Flutter/Vue UI tests
Not applicable.

## Security and tenancy
This feature is the tenancy control; the security review of batch 1 should cover the unscoped-model list and every `withoutGlobalScopes` site.

## Order/pricing/payment invariants
Not applicable.

## Regression and manual QA
Sign in as two tenants and compare list endpoints.

## Test data/fixtures
Two restaurants created in the test files.
