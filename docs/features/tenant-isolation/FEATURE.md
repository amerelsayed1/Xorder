# Feature specification: Tenant isolation (restaurant scope)

Status: implemented (cross-cutting mechanism of the cloud API)
Slug: `tenant-isolation` · Module: `auth-and-tenancy` · Footprint: cloud-only (the POS has its own tenant column; the device middleware sets the cloud tenant for POS requests)
Verified against: 2026-10-20 · cloud `main 06bc8e3` · POS `main d592db8` (uncommitted files in both repos are documentation, agent/script files and two POS files outside this feature; none is cited as evidence unless stated). Core state: `drafted` (author self-check, mechanical citation check; no independent validation pass). Path prefixes: `C:` = `apps/xorder-cloud/apps/api/`, `P:` = `apps/xorder-pos/`, `W:` = `apps/xorder-cloud/apps/web/`, `K:` = `apps/xorder-cloud/packages/`, `A:` = `apps/xorder-cloud/apps/`.

## Summary
Each restaurant's data is separated by a `restaurant_id` column. A global Eloquent scope adds `where <table>.restaurant_id = <current tenant>` to every query of a tenant-owned model, and a model trait stamps `restaurant_id` on create. The current tenant comes from the signed-in user, or from an explicit override set by the POS device middleware and a few public/service paths. `restaurant_id` is never read from request input by this mechanism.

## Scope and exclusions
Implemented: `RestaurantScope`, `BelongsToRestaurant`, `TenantContext`, the device middleware override, hand-scoped queries where a model is deliberately unscoped, 404-instead-of-403 behavior in controllers that guard targets.
This document records the mechanism and where it is applied; it is **not** an audit of every controller (see `docs/features/*` of each feature, and the security review planned for the plan's batch 1).

## Actors and permissions
No actor-facing permission; the mechanism is automatic. `SUPER_ADMIN` has no tenant (scope off); other platform roles have `restaurant_id` null by data, so the scope is also off for them (`C:tests/Feature/UserCreationMatrixTest.php:79-107`).

## Current implemented behavior
1. `RestaurantScope::apply` adds `where <table>.restaurant_id = TenantContext::restaurantId()` and does nothing when that id is null (`C:app/Models/Scopes/RestaurantScope.php:21-30`).
2. `BelongsToRestaurant` registers the scope and, on `creating`, sets `restaurant_id` from `TenantContext::restaurantId()` only if the attribute is null; an explicit value is kept (`C:app/Models/Concerns/BelongsToRestaurant.php:17-26`).
3. `TenantContext::restaurantId()` returns the override if set; otherwise null without a user, null for `SUPER_ADMIN`, else the user's `restaurant_id` (`C:app/Support/TenantContext.php:34-52`). The override is a static property set by `overrideId` and cleared by `clearOverride` (`:22-32`).
4. Places that set the override: `PosDeviceAuth` (set `:77`, cleared in `finally` `:82`), `PublicOrderController`, `PublicCustomerController`, `PosCustomerService`, `PosProvisioningService`, `PublicMenuService` (`C:app/Http/Middleware/PosDeviceAuth.php:75-83` and the other files by `grep -rn "TenantContext::overrideId" C:app`).
5. Models that use the trait (48 in `C:app/Models`; the list is in `FEATURE_INVENTORY.md` evidence; examples: Branch, Category, MenuItem, Role, Order, OrderItem, OrderPayment, Customer, DiningTable, PosShift, PosTerminal, PurchaseOrder, Supplier, StockItem, Unit). Models without it: AuditLog, DeviceToken, LandingContent, Lead, Plan, PosLicence, Restaurant, ReviewInternalNote, User.
6. `User` is deliberately unscoped (`C:app/Http/Controllers/Dashboard/StaffController.php:20-24` explains why); staff queries are scoped by hand (`StaffController.php:47-59`). `PosLicence` is deliberately unscoped (`C:app/Models/PosLicence.php:13`, `C:app/Http/Controllers/Admin/LicenceController.php:24`).
7. Explicit bypasses with `withoutGlobalScopes`: models `BillRequest.php:51`, `MenuViewDaily.php:36,49,60`, `DiningTable.php:50`; controllers `PublicOrderController.php:117,209,230,266`, `PublicReviewController.php:59,73,94`, `PublicBillRequestController.php:34,37,128,158`, `PublicTableController.php:121`, `Admin/LicenceController.php:262`; services `StockLedger.php:35,51`, `InvoiceSequenceService.php:43,60`, `TableVisitService.php:21,23,54,59,62,74`, `BranchEgressIpService.php:118` (paths under `C:app/`).
8. Cross-tenant ids return 404 through route-model binding on scoped models (tests `C:tests/Feature/TenantIsolationTest.php:39,52`), and through the guards in `StaffController::guardTarget` and `PosPinController::guard` (404 for another tenant, or the owner) (`C:app/Http/Controllers/Dashboard/StaffController.php:154-163`, `C:app/Http/Controllers/Dashboard/PosPinController.php:76-97`). The `{staff}` route parameter binds `User` without a scope; the controller guard does the filtering (no `Route::bind` or `scopeBindings` in `C:routes/api.php`).
9. Validation rules that depend on the scope: `rejectRoleAboveSelf` loads the role through the scoped model (`C:app/Http/Requests/Dashboard/Concerns/GrantsTenantCapabilities.php:72-74`); staff `role_id` uses `exists:roles,id` with a `restaurant_id` condition (`C:app/Http/Requests/Dashboard/StoreStaffRequest.php:36-39`).

## User journeys and workflows
Not applicable (infrastructure).

## Business rules
| ID | Rule | Where implemented | Evidence |
| --- | --- | --- | --- |
| BR-1 | Tenant-owned model queries are limited to the current tenant. | global scope | `RestaurantScope.php:21-30` |
| BR-2 | New tenant-owned rows get the current tenant unless an id is given. | trait | `BelongsToRestaurant.php:21-25` |
| BR-3 | The tenant is the signed-in user's, except `SUPER_ADMIN` (none) and an explicit override. | `TenantContext` | `TenantContext.php:34-52` |
| BR-4 | POS requests authenticated by a device token run with the terminal's tenant as override, cleared afterwards. | middleware | `PosDeviceAuth.php:75-83` |
| BR-5 | Another tenant's resource is reported as not found (404). | binding and guards | tests `TenantIsolationTest.php:39,52`; `StaffController.php:154-163` |
| BR-6 | `restaurant_id`, `role` and `role_id` are not mass-assignable on `User`. | model | `C:app/Models/User.php:28-39`; test `C:tests/Feature/SecurityHardeningTest.php:197` |

## Validation and error handling
404 `staff_not_found` for cross-tenant or owner targets in staff/PIN endpoints; 404 from model binding on scoped models; 422 on `role_id` for another tenant's role (`C:tests/Feature/UserCreationMatrixTest.php:334`).

## Edge cases and failure handling
- A null tenant disables the scope, so any code path that runs without a user or override (queue, console, service) sees all tenants' rows. Call sites that rely on this are listed under Current behavior 7 and 4.
- Roles of other platform staff (`ADMIN`, `MODERATOR`, `SALES`, `SUPPORT`) have no tenant by data, not by explicit code.

## Cross-application dependencies
The POS reaches cloud data only through `PosDeviceAuth` (tenant override from the terminal row) and the public endpoints that set the override. The POS database has its own tenant column and is not governed by this mechanism.

## Security considerations
- Strength: structural scoping; `restaurant_id` is not taken from request input in the scope or trait.
- The override is process-global static state (`TenantContext.php:22`); it is cleared in `finally` by the device middleware (`PosDeviceAuth.php:79-83`). Behavior across other override sites: `BEHAVIORAL_ANALYSIS.md`.
- Unscoped models carry their own isolation in controllers; each such place is a review item.

## Known limitations
- No unit test of `RestaurantScope`, the trait's stamping, or `PosDeviceAuth` cross-tenant isolation was found (name-level search).
- Stale text: `C:app/Http/Controllers/Dashboard/StaffController.php` docblock lines 17 and 26-28 do not match the code (see `staff-management`).

## Existing automated tests
| Layer | File and test | Covers | Gaps |
| --- | --- | --- | --- |
| Cloud feature | `C:tests/Feature/TenantIsolationTest.php:16,24,39,52,65` | admin routes forbidden to a restaurant admin; own categories only; foreign category and item 404; item cannot attach to a foreign category (422) | scope on models other than category/item |
| Cloud feature | `C:tests/Feature/TenantRbacTest.php:243,389,564` | staff and roles invisible across tenants | |
| Cloud feature | `C:tests/Feature/UserCreationMatrixTest.php:334` | foreign role not assignable | |
| Cloud feature | `C:tests/Feature/Pos/PosRefundsTest.php:319,437`, `C:tests/Feature/Pos/PosDefaultTendersTest.php:125-147`, `C:tests/Feature/PerTenantAuthTest.php:19-126` | POS and login isolation (bodies partly read) | |
All use SQLite `:memory:`; SQLite cannot show PostgreSQL-specific behavior.

## Acceptance criteria
- AC-1: A tenant user lists only their restaurant's rows of any scoped model.
- AC-2: A tenant user requesting another tenant's scoped resource gets 404.
- AC-3: Rows created by a tenant user carry that tenant unless explicitly given.
- AC-4: POS requests with a device token see only the terminal's tenant, and the tenant context is cleared afterwards.
- AC-5: `restaurant_id` and `role` cannot be set through the staff endpoints.

## Confirmed source references
`C:app/Models/Scopes/RestaurantScope.php`; `C:app/Models/Concerns/BelongsToRestaurant.php`; `C:app/Support/TenantContext.php`; `C:app/Http/Middleware/PosDeviceAuth.php`; `C:app/Http/Controllers/Dashboard/StaffController.php:154-170`; `C:app/Http/Controllers/Dashboard/PosPinController.php:76-100`; `C:tests/Feature/TenantIsolationTest.php`.

## Unknowns and assumptions
- UNVERIFIED: that every scoped query path in controllers and services honours the scope (this document does not audit them).
- UNVERIFIED: absence of direct unit tests beyond the name-level search.
