# Technical design: Self-service restaurant signup

Verified against: 2026-10-20 · cloud `main 06bc8e3` · POS `main d592db8` (uncommitted files in both repos are documentation, agent/script files and two POS files outside this feature; none is cited as evidence unless stated). Core state: `drafted` (author self-check, mechanical citation check; no independent validation pass). Path prefixes: `C:` = `apps/xorder-cloud/apps/api/`, `P:` = `apps/xorder-pos/`, `W:` = `apps/xorder-cloud/apps/web/`, `K:` = `apps/xorder-cloud/packages/`, `A:` = `apps/xorder-cloud/apps/`.

## Architecture and modules
`SignupController` → `RestaurantProvisioningService::provision` → models and services: `Restaurant`, `User`, `TenantRoleService`, `RestaurantFeatureService`, `PlanEntitlementService`, `LicenceIssuer`, then `RestaurantAdminCredentials` notification.

## Cloud implementation
| Layer | Files |
| --- | --- |
| Route | `C:routes/api.php:841-842` |
| Controller / request | `C:app/Http/Controllers/Public/SignupController.php`, `C:app/Http/Requests/Public/SignupRequest.php` |
| Services | `C:app/Services/RestaurantProvisioningService.php`, `SlugService.php`, `TenantRoleService.php`, `RestaurantFeatureService.php`, `PlanEntitlementService.php`, `LicenceIssuer.php` |
| Notification | `C:app/Notifications/RestaurantAdminCredentials.php` |
| Config | `C:config/platform.php:42-57` |

## Web frontend implementation
None found.

## Desktop POS implementation
None.

## Source references
See `FEATURE.md`.

## State and data flow
Request → validated data → provisioning transaction → mail after commit → response.

## Local persistence and caching
None.

## Offline operation and synchronization
Not applicable.

## Dependencies
Mail transport (`MAIL_MAILER`), the licence signing configuration (a missing signing key aborts the whole tenant, `RestaurantProvisioningService.php:139-142`).

## Failure handling and observability
Validation errors as 422; provisioning failures roll the transaction back; mail runs after commit; audit entry for the licence.

## Platform-specific behavior
None.

## Compatibility and rollout
Feature flag `SELF_SERVE_SIGNUP` (default off); enabling it in production is a configuration decision outside the code.
