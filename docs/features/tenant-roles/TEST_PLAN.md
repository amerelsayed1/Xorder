# Test plan: Roles, capabilities and gates

Verified against: 2026-10-20 · cloud `main 06bc8e3` · POS `main d592db8` (uncommitted files in both repos are documentation, agent/script files and two POS files outside this feature; none is cited as evidence unless stated). Core state: `drafted` (author self-check, mechanical citation check; five independent passes (rounds 1-5), criterion not met: `docs/validation/2026-10-20-batch1-*-report.md`). Path prefixes: `C:` = `apps/xorder-cloud/apps/api/`, `P:` = `apps/xorder-pos/`, `W:` = `apps/xorder-cloud/apps/web/`, `K:` = `apps/xorder-cloud/packages/`, `A:` = `apps/xorder-cloud/apps/`.

## Test environments
`php artisan test --filter "TenantRbacTest|CapabilityVerbsTest|UserCreationMatrixTest|PlanEntitlementTest"` (SQLite). POS: `flutter test test/domain/permissions_test.dart test/domain/permission_resolver_test.dart` (no database; not run here).

## Acceptance criteria to tests
| AC | Existing test | Coverage | Planned addition |
| --- | --- | --- | --- |
| AC-1 | `C:tests/Feature/TenantRbacTest.php:101,114,430` | covered | |
| AC-2 | `TenantRbacTest.php:127,141,296`, `CapabilityVerbsTest.php:64-166,194` | covered | |
| AC-3 | `TenantRbacTest.php:313,327`, `UserCreationMatrixTest.php:296,312` (create paths: role POST at `TenantRbacTest.php:313`; staff POST at `TenantRbacTest.php:327`, `UserCreationMatrixTest.php:296,312`) | partial: no test of `PUT roles/{role}` or `PUT staff/{staff}` above self (`UpdateRoleRequest.php:35-38`, `UpdateStaffRequest.php:40-43`) | update paths above self; role-delete reassignment above self |
| AC-4 | `TenantRbacTest.php:74,359,369` | covered | |
| AC-5 | `TenantRbacTest.php:389` | covered | |
| AC-6 | `C:tests/Feature/Admin/PlatformUserTest.php:92,106,115` (route-level) | partial | `RoleEnum::capabilities` matrix vs Vue `ROLE_CAPS`; fleet only Super Admin (licence key route is covered: `C:tests/Feature/Admin/PosLicenceTest.php:125-135` loops ADMIN, SALES, SUPPORT, MODERATOR) |
| AC-7 | cloud: `C:tests/Feature/Pos/PosPurchaseCapabilityWithheldTest.php:20-27` (bundle drops `purchase.manage`, keeps `pos.operate`); POS: `P:test/data/cloud_bootstrap_test.dart:145-150` (staff capabilities and PIN parse), `P:test/domain/permissions_test.dart:73-83` (older-name mapping), `P:test/features/drawer_open_flow_test.dart:38` (`canonicalAll`, `pos.cash_movement` implication), `P:test/data/postgres_permissions_test.dart:83-100` (fixture at `:54-71`) (POS migration renaming stored legacy `pos.*` rows; not the cloud-bundle path) | partial: no bundle-to-resolved-set test | bundle with `staff.view/create/update/delete` → resolved POS set |

## Unit tests
No direct test of `TenantRoleService`. The enums have assertions inside feature tests: `C:tests/Feature/Pos/PosFoundationsTest.php:49-72` (POS-BE-002 strings, `implies()`, `expand()`), `C:tests/Feature/PurchasingFoundationsTest.php` (`PURCHASE_MANAGE` resource, action, group, `implies`, absence from `legacyManageMap`), `C:tests/Feature/CapabilityVerbsTest.php:194-200` (`expand` of a legacy key).

## Integration and API tests
Add `PUT roles/{role}` (including the admin role), `GET roles/capabilities`, bearer-token suspended user, role delete reassignment by a limited actor.

## Flutter/Vue UI tests
No Vue framework. POS key-map tests exist (only the cited lines were read).

## Security and tenancy
Cross-tenant role access covered (AC-5).

## Order/pricing/payment invariants
Not applicable.

## Regression and manual QA
Create a role with one write verb, assign it, sign in as that user and confirm which pages and endpoints work.

## Test data/fixtures
`TenantRbacTest` helpers.
