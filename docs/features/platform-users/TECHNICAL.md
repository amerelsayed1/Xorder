# Technical design: Platform (Super Admin portal) users

Verified against: 2026-10-20 · cloud `main 06bc8e3` · POS `main d592db8` (uncommitted files in both repos are documentation, agent/script files and two POS files outside this feature; none is cited as evidence unless stated). Core state: `drafted` (author self-check, mechanical citation check; no independent validation pass). Path prefixes: `C:` = `apps/xorder-cloud/apps/api/`, `P:` = `apps/xorder-pos/`, `W:` = `apps/xorder-cloud/apps/web/`, `K:` = `apps/xorder-cloud/packages/`, `A:` = `apps/xorder-cloud/apps/`.

## Architecture and modules
`PlatformUserController` → requests → `PlatformUserService` → `User`; `PlatformUserCredentials` mail; `AuditLogger` events.

## Cloud implementation
| Layer | Files |
| --- | --- |
| Routes | `C:routes/api.php:139-146` |
| Controller | `C:app/Http/Controllers/Admin/PlatformUserController.php` |
| Requests | `C:app/Http/Requests/Admin/StorePlatformUserRequest.php`, `UpdatePlatformUserRequest.php` |
| Service | `C:app/Services/PlatformUserService.php` |
| Notification | `C:app/Notifications/PlatformUserCredentials.php` |

## Web frontend implementation
`W:src/pages/admin/UsersList.vue`, `UserForm.vue` (client password generator, 14 chars), routes `W:src/router/index.js:31-33`.

## Desktop POS implementation
None.

## Source references
See `FEATURE.md`.

## State and data flow
Direct writes to `users`; effects apply at the next request through the JWT guard.

## Local persistence and caching
None.

## Offline operation and synchronization
Not applicable.

## Dependencies
Mail transport; `RoleEnum::assignable`.

## Failure handling and observability
JSON errors; audit events `platform_user.created|updated|password_reset|deleted`.

## Platform-specific behavior
None.

## Compatibility and rollout
Adding a platform role needs: enum case, matrix row, `assignable()`, Vue role list (`UserForm.vue:18`), `ROLE_CAPS`.
