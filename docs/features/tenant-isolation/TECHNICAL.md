# Technical design: Tenant isolation (restaurant scope)

Verified against: 2026-10-20 · cloud `main 06bc8e3` · POS `main d592db8` (uncommitted files in both repos are documentation, agent/script files and two POS files outside this feature; none is cited as evidence unless stated). Core state: `drafted` (author self-check, mechanical citation check; no independent validation pass). Path prefixes: `C:` = `apps/xorder-cloud/apps/api/`, `P:` = `apps/xorder-pos/`, `W:` = `apps/xorder-cloud/apps/web/`, `K:` = `apps/xorder-cloud/packages/`, `A:` = `apps/xorder-cloud/apps/`.

## Architecture and modules
`TenantContext` (static override + current user) → `RestaurantScope` (query) and `BelongsToRestaurant` (stamp) on models; `PosDeviceAuth` sets the override for device requests; controllers that must see across tenants use `withoutGlobalScopes`.

## Cloud implementation
| Layer | Files |
| --- | --- |
| Context | `C:app/Support/TenantContext.php` |
| Scope / trait | `C:app/Models/Scopes/RestaurantScope.php`, `C:app/Models/Concerns/BelongsToRestaurant.php` |
| Device middleware | `C:app/Http/Middleware/PosDeviceAuth.php` |
| Hand scoping | `C:app/Http/Controllers/Dashboard/StaffController.php`, `PosPinController.php`, `C:app/Services/PosBootstrapService.php` (staff query) |

## Web frontend implementation
None (the SPA relies on host/slug for login only: `auth-login`).

## Desktop POS implementation
Not applicable.

## Source references
See `FEATURE.md`.

## State and data flow
Tenant id flows from token/user or override to every scoped query in the request.

## Local persistence and caching
None.

## Offline operation and synchronization
Not applicable.

## Dependencies
Eloquent global scopes.

## Failure handling and observability
Null tenant disables the scope silently.

## Platform-specific behavior
None.

## Compatibility and rollout
Any new tenant-owned model must use the trait; unscoped models need explicit scoping in code.
