# Test plan: Restaurant staff accounts

Verified against: 2026-10-20 · cloud `main 06bc8e3` · POS `main d592db8` (uncommitted files in both repos are documentation, agent/script files and two POS files outside this feature; none is cited as evidence unless stated). Core state: `drafted` (author self-check, mechanical citation check; five independent passes (rounds 1-5), criterion not met: `docs/validation/2026-10-20-batch1-*-report.md`). Path prefixes: `C:` = `apps/xorder-cloud/apps/api/`, `P:` = `apps/xorder-pos/`, `W:` = `apps/xorder-cloud/apps/web/`, `K:` = `apps/xorder-cloud/packages/`, `A:` = `apps/xorder-cloud/apps/`.

## Test environments
`php artisan test --filter "TenantRbacTest|UserCreationMatrixTest|PlanStaffLimitTest|CapabilityVerbsTest"` (SQLite). POS: `flutter test test/data/cloud_bootstrap_test.dart` (no database); `test/data/postgres_admin_test.dart` needs `POS_PG_HOST`.

## Acceptance criteria to tests
| AC | Existing test | Coverage | Planned addition |
| --- | --- | --- | --- |
| AC-1 | `C:tests/Feature/TenantRbacTest.php:196,214,327`, `UserCreationMatrixTest.php:258-312,391` | covered | `password` min 8; SUSPENDED on create |
| AC-2 | `TenantRbacTest.php:243` (cross-tenant show and delete, `:263,:265`), `:527,550` (owner PUT/reset/delete 404, `:537,:543`), `:564` (listing only) | partial | cross-tenant PUT and reset-password |
| AC-3 | `TenantRbacTest.php:270` | covered for delete | self update, self reset |
| AC-4 | `C:tests/Feature/PlanStaffLimitTest.php:46-104` | covered | concurrent creates; limit on update |
| AC-5 | `UserCreationMatrixTest.php:411` (POST by three platform roles), `:423` (suspended owner via `actingAs`, the 403 path), `TenantRbacTest.php:175` (suspended staff 403 on pulse), `:186` (staff cannot reach the admin panel) | partial | bearer-token suspended account (401 at the guard) |
| AC-6 | cloud: `C:tests/Feature/Pos/PosProvisioningTest.php:266-271` (owner row PIN block, `pos.operate`), `C:tests/Feature/Pos/PosPurchaseCapabilityWithheldTest.php:20-27`; POS: `P:test/data/cloud_bootstrap_test.dart:145-150` (parse) | partial: owner row only on the cloud side, parse only on the POS side | `_seedStaff` upsert and deactivation test; bundle test for non-owner staff rows |

## Unit tests
None for `TenantUserService` or `PlanLimitService`.

## Integration and API tests
Gaps listed in `FEATURE.md`: PUT success/validation, show success, throttle, read-only subscription, mail sent, hard-delete effects.

## Flutter/Vue UI tests
No Vue framework; POS `P:test/data/postgres_admin_test.dart:417-499` (integration).

## Security and tenancy
Covered by isolation tests above; add a test where a staff member without `staff.update` calls PUT (403); DELETE without `staff.delete` is covered by `C:tests/Feature/CapabilityVerbsTest.php:171-173`.

## Order/pricing/payment invariants
Not applicable.

## Regression and manual QA
Create staff, sign in as them, pair a till and confirm the staff member appears on the till.

## Test data/fixtures
`TenantRbacTest` helpers; POS `P:test/data/pg_fixture.dart` for integration tests.
