# Module: roles-and-staff

Verified against: 2026-10-20 · cloud `main 06bc8e3` · POS `main d592db8`
Path prefixes: `C:` = `apps/xorder-cloud/apps/api/`, `P:` = `apps/xorder-pos/`, `W:` = `apps/xorder-cloud/apps/web/`, `K:` = `apps/xorder-cloud/packages/`.
Status: core `drafted` for 4 of 4 features · Footprint: shared via the POS bootstrap

## Purpose and scope
Who can do what: platform staff (Super Admin portal) and restaurant staff accounts, tenant roles and capabilities, platform users, and the cashier PIN for the POS.

## Features
| Slug | Title | Footprint | Status | Docs |
| --- | --- | --- | --- | --- |
| `staff-management` | Restaurant staff accounts | shared (bootstrap download) | drafted | `docs/features/staff-management/` |
| `tenant-roles` | Roles, capabilities and gates | shared (bootstrap download) | drafted | `docs/features/tenant-roles/` |
| `platform-users` | Platform (Super Admin portal) users | cloud-only | drafted | `docs/features/platform-users/` |
| `pos-pin` | Cashier PIN for the POS | shared (bootstrap download) | drafted | `docs/features/pos-pin/` |

## Actors and permissions
Platform roles (`SUPER_ADMIN`, `ADMIN`, `MODERATOR`, `SALES`, `SUPPORT`) with the fixed matrix in `RoleEnum`; tenant owner (all capabilities) and staff (role capabilities). 12 platform and 40 tenant capability keys; see `tenant-roles`.

## Architecture of the module
Cloud: `Dashboard\StaffController`, `RoleController`, `PosPinController`, `Admin\PlatformUserController`; services `TenantUserService`, `TenantRoleService`, `PlatformUserService`, `PlanLimitService`; `Support\PosPin`; gates in `AppServiceProvider`. Web: staff, role and platform-user pages. POS: bootstrap seeder, `permissions.dart`, `permission_resolver.dart`, `pin_hash.dart`, staff pane.

## Data
`users`, `roles`, `plans.max_staff`, `users.pos_pin_*`, `restaurants.pos_config_version`; POS `pos_staff`, `pos_roles`.

## Module-level workflows
Owner creates a role → creates staff on it → sets a PIN → the till downloads staff, capabilities and PIN verifiers at bootstrap.

## Cross-application dependencies
Staff, capabilities and PIN verifiers travel in `staff[]` of `GET /api/pos/bootstrap`; capability strings are renamed to POS keys; the till keeps local roles/grants; cloud-bootstrapped staff share the cloud user id. Local staff id reconciliation: UNVERIFIED.

## Dependencies on other modules
`auth-and-tenancy` (login, tenant scope), `plans-subscriptions` (staff cap, features), `pos-provisioning-licensing` (bootstrap).

## Tests
Cloud: `TenantRbacTest`, `CapabilityVerbsTest`, `UserCreationMatrixTest`, `PlanStaffLimitTest`, `Admin/PlatformUserTest`, `PosPinLengthTest`, `AuditSecretsTest`. POS: `cloud_bootstrap_test`, `pin_rules_test`, permission tests (bodies not read), integration-tagged `postgres_admin_test`.

## Risks, gaps and unknowns
Unvalidated analyses per feature: bootstrap freshness after staff changes, legacy aliases reaching tills, role-delete reassignment above self, existing tenants' admin role lacking newer capabilities, PHP/Dart PIN compatibility untested.
