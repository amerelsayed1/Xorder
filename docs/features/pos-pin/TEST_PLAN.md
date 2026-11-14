# Test plan: Cashier PIN for the POS

Verified against: 2026-10-20 · cloud `main 06bc8e3` · POS `main d592db8` (uncommitted files in both repos are documentation, agent/script files and two POS files outside this feature; none is cited as evidence unless stated). Core state: `drafted` (author self-check, mechanical citation check; no independent validation pass). Path prefixes: `C:` = `apps/xorder-cloud/apps/api/`, `P:` = `apps/xorder-pos/`, `W:` = `apps/xorder-cloud/apps/web/`, `K:` = `apps/xorder-cloud/packages/`, `A:` = `apps/xorder-cloud/apps/`.

## Test environments
Cloud: `php artisan test --filter "PosPinLengthTest|AuditSecretsTest"`; POS: `flutter test test/core/pin_rules_test.dart test/data/cloud_bootstrap_test.dart` (no database).

## Acceptance criteria to tests
| AC | Existing test | Coverage | Planned addition |
| --- | --- | --- | --- |
| AC-1 | `C:tests/Feature/PosPinLengthTest.php:27,37` | accepted/refused shapes | assert stored salt/hash after PUT |
| AC-2 | `C:tests/Feature/AuditSecretsTest.php:50-110` | covered | response body has no PIN |
| AC-3 | none | gap | self, other with/without `staff.update`, owner target, cross-tenant 404 |
| AC-4 | `C:tests/Feature/Pos/PosProvisioningTest.php:242-263`, `P:test/data/cloud_bootstrap_test.dart:145-150` | parse and shape | PHP-made verifier verified by `PinHash` (fixture shared between suites) |
| AC-5 | none | gap | config version increments on PUT and DELETE |

## Unit tests
`PosPin` has no unit test; `PinHash` is covered only indirectly.

## Integration and API tests
DELETE, throttle `10,1`, `feature:pos` 403.

## Flutter/Vue UI tests
POS `P:test/core/pin_rules_test.dart`; no Vue framework.

## Security and tenancy
Cross-tenant target (404); non-tenant accounts (404).

## Order/pricing/payment invariants
Not applicable.

## Regression and manual QA
Set a PIN in the dashboard, sync a till, unlock with it; clear it and confirm the lock after the next sync.

## Test data/fixtures
`PosPin::make('4829')` in `PosProvisioningTest.php:242-263`.
