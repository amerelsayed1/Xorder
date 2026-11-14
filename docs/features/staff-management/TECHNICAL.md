# Technical design: Restaurant staff accounts

Verified against: 2026-10-20 · cloud `main 06bc8e3` · POS `main d592db8` (uncommitted files in both repos are documentation, agent/script files and two POS files outside this feature; none is cited as evidence unless stated). Core state: `drafted` (author self-check, mechanical citation check; five independent passes (rounds 1-5), criterion not met: `docs/validation/2026-10-20-batch1-*-report.md`). Path prefixes: `C:` = `apps/xorder-cloud/apps/api/`, `P:` = `apps/xorder-pos/`, `W:` = `apps/xorder-cloud/apps/web/`, `K:` = `apps/xorder-cloud/packages/`, `A:` = `apps/xorder-cloud/apps/`.

## Architecture and modules
`StaffController` → `StoreStaffRequest`/`UpdateStaffRequest` (+ `GrantsTenantCapabilities`) → `PlanLimitService`, `TenantUserService` → `User`; credentials via `StaffCredentials`; POS via `PosBootstrapService` → `BootstrapSeeder`.

## Cloud implementation
| Layer | Files |
| --- | --- |
| Routes | `C:routes/api.php:300-322` |
| Controller | `C:app/Http/Controllers/Dashboard/StaffController.php` |
| Requests | `C:app/Http/Requests/Dashboard/StoreStaffRequest.php`, `UpdateStaffRequest.php`, `Concerns/GrantsTenantCapabilities.php` |
| Services | `C:app/Services/TenantUserService.php`, `PlanLimitService.php`, `TenantRoleService.php`, `PosBootstrapService.php` |
| Notification | `C:app/Notifications/StaffCredentials.php` |

## Web frontend implementation
| App | Pages | Notes |
| --- | --- | --- |
| `apps/web` | `W:src/pages/dashboard/StaffView.vue`, `StaffForm.vue`; `W:src/lib/useCaps.js:23-33`; routes `W:src/router/index.js:170-172` | row menu hidden for the owner; client password generator (14 chars) used on create |

## Desktop POS implementation
`P:lib/data/cloud/bootstrap_bundle.dart:514-531` (`BootstrapStaff`), `bootstrap_seeder.dart:459-507`, `P:lib/features/admin/presentation/management_staff_pane.dart`, `P:lib/features/admin/presentation/staff_grants_dialog.dart`, `P:lib/data/postgres/postgres_admin_repositories.dart` (`PostgresStaffDirectoryRepository`).

## Source references
See `FEATURE.md`.

## State and data flow
Cloud `users` are the source of truth for bootstrapped staff; the till stores copies in `pos_staff` and may hold local roles/grants (`tenant-roles`).

## Local persistence and caching
POS table `pos_staff`.

## Offline operation and synchronization
Staff changes reach a till when it downloads the bootstrap bundle; update timing: `BEHAVIORAL_ANALYSIS.md`.

## Dependencies
Plans (`max_staff`), roles, mail transport, `PosPin` (PIN verifier).

## Failure handling and observability
422/404/403 JSON `{message}` (validation: `errors` bag); audit call `staff.password_reset`; the controller has no try/catch around the mail send (mail failure behavior: `BEHAVIORAL_ANALYSIS.md` D).

## Platform-specific behavior
None.

## Compatibility and rollout
Bootstrap `capabilities` carries legacy aliases (`API.md`); what removing them would affect: `BEHAVIORAL_ANALYSIS.md` F.
