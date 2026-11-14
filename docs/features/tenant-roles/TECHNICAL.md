# Technical design: Roles, capabilities and gates

Verified against: 2026-10-20 · cloud `main 06bc8e3` · POS `main d592db8` (uncommitted files in both repos are documentation, agent/script files and two POS files outside this feature; none is cited as evidence unless stated). Core state: `drafted` (author self-check, mechanical citation check; five independent passes (rounds 1-5), criterion not met: `docs/validation/2026-10-20-batch1-*-report.md`). Path prefixes: `C:` = `apps/xorder-cloud/apps/api/`, `P:` = `apps/xorder-pos/`, `W:` = `apps/xorder-cloud/apps/web/`, `K:` = `apps/xorder-cloud/packages/`, `A:` = `apps/xorder-cloud/apps/`.

## Architecture and modules
Enums (`Capability`, `TenantCapability`, `RoleEnum`, `Feature`) → gates in `AppServiceProvider` → middleware aliases in `bootstrap/app.php` → route groups → controllers/requests; `Role` model + `TenantRoleService` for tenant roles; Vue mirrors via `useCaps` and `ROLE_CAPS`.

## Cloud implementation
| Layer | Files |
| --- | --- |
| Enums | `C:app/Enums/Capability.php`, `TenantCapability.php`, `RoleEnum.php`, `Feature.php` |
| Gates | `C:app/Providers/AppServiceProvider.php:118-164` |
| Middleware | `C:app/Http/Middleware/EnsureRole.php`, `EnsureFeatureEnabled.php`, `EnsureSubscriptionAllowsWrites.php`; aliases `C:bootstrap/app.php:57-63` |
| Role CRUD | `C:app/Http/Controllers/Dashboard/RoleController.php`, requests `StoreRoleRequest.php`, `UpdateRoleRequest.php`, `Concerns/GrantsTenantCapabilities.php`, resource `RoleResource.php` |
| Services | `C:app/Services/TenantRoleService.php`, `TenantUserService.php` (`reassignRole`), `PlanEntitlementService.php`, `RestaurantFeatureService.php` |
| Models | `C:app/Models/Role.php`, `User.php` |

## Web frontend implementation
| App | Files | Notes |
| --- | --- | --- |
| `apps/web` | `W:src/pages/dashboard/RolesView.vue`, `RoleForm.vue`, `W:src/lib/capabilities.js`, `useCaps.js`, `W:src/router/index.js:260-291` | matrix vs list layout; implied views locked |
| shared client | `K:api-client/src/auth.js:12-71` | `ROLE_CAPS`, `can()`, `isReadOnly` |

## Desktop POS implementation
`P:lib/domain/models/permissions.dart` (keys, rename map, risk levels, system role templates), `P:lib/domain/services/permission_resolver.dart`, `P:lib/data/cloud/bootstrap_seeder.dart:465-487`.

## Source references
See `FEATURE.md`.

## State and data flow
Roles in `roles` (JSON capabilities); staff point at them with `role_id`; tills receive resolved capability strings.

## Local persistence and caching
POS `pos_staff.capabilities`, `pos_roles`.

## Offline operation and synchronization
A till applies capability changes from a downloaded bundle whose `pos_config_version` is newer than the one it holds (`FEATURE.md` POS paragraph); consequences for role edits: `BEHAVIORAL_ANALYSIS.md` I.

## Dependencies
Plans/features (`PlanEntitlementService`), subscription state.

## Failure handling and observability
403/404/422 JSON; `RoleController` has no explicit audit call (grep), but `Role` uses the `Auditable` trait (`C:app/Models/Role.php:21`) which records model created/updated/deleted events.

## Platform-specific behavior
None.

## Compatibility and rollout
Compatibility notes (what adding or removing a capability touches) are a lead: `BEHAVIORAL_ANALYSIS.md` K.
