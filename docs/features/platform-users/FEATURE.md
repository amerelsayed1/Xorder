# Feature specification: Platform (Super Admin portal) users

Status: implemented (cloud API and Super Admin SPA)
Slug: `platform-users` · Module: `roles-and-staff` · Footprint: cloud-only
Verified against: 2026-10-20 · cloud `main 06bc8e3` · POS `main d592db8` (uncommitted files in both repos are documentation, agent/script files and two POS files outside this feature; none is cited as evidence unless stated). Core state: `drafted` (author self-check, mechanical citation check; no independent validation pass). Path prefixes: `C:` = `apps/xorder-cloud/apps/api/`, `P:` = `apps/xorder-pos/`, `W:` = `apps/xorder-cloud/apps/web/`, `K:` = `apps/xorder-cloud/packages/`, `A:` = `apps/xorder-cloud/apps/`.

## Summary
Super Admin creates, edits, suspends, deletes and resets the passwords of platform staff accounts with roles `ADMIN`, `MODERATOR`, `SALES` or `SUPPORT`. Platform users have no restaurant.

## Scope and exclusions
Implemented: six routes under `/api/admin/users`, `PlatformUserService`, the credentials email, the Vue list and form. Not found: any endpoint that creates a `SUPER_ADMIN` (the seeding path of the first Super Admin is out of scope here and UNVERIFIED); a throttle on the routes other than reset-password.

## Actors and permissions
Only `SUPER_ADMIN` holds `platform_users.manage` (`C:app/Enums/RoleEnum.php:57-94`); the six routes sit in one group `can:platform_users.manage` (`C:routes/api.php:139-146`) under `auth:jwt` and the platform `role:` list (`:108-110`). `StorePlatformUserRequest::authorize` repeats the check (`C:app/Http/Requests/Admin/StorePlatformUserRequest.php:14`).

## Current implemented behavior
1. `index`: users with `restaurant_id` null (Super Admin rows included), newest first (`C:app/Http/Controllers/Admin/PlatformUserController.php:25-33`).
2. `show`, `update`, `resetPassword`, `destroy` run `guardTarget`: 404 `platform_user_not_found` if the target has a restaurant or a tenant role; 403 `platform_user_super_admin_forbidden` for a `SUPER_ADMIN` target; 403 `platform_user_self_forbidden` for the caller's own account (`:125-142`).
3. `store`: creates the user (`role` one of `ADMIN`, `MODERATOR`, `SALES`, `SUPPORT`), generating a 16-character password when none is given, `password_changed_at` and `email_verified_at` now, status default ACTIVE, `restaurant_id` and `role_id` null; sends `PlatformUserCredentials`; writes audit `platform_user.created`; returns 201 `{data, generated_password (null when supplied), message}` (`C:app/Services/PlatformUserService.php:26-55,97-100`, `PlatformUserController.php:44-60`).
4. `update` sets name, username, email, role and status; audit `platform_user.updated` (`PlatformUserService.php:63-76`).
5. `resetPassword` generates a password, stamps `password_changed_at`, sends the mail, audit `platform_user.password_reset`, returns `{generated_password, message}` (`:83-95`); `throttle:10,1` (`routes/api.php:145`).
6. `destroy`: audit `platform_user.deleted`, then deletes the row (`PlatformUserController.php:103-118`).
7. The credentials mail is sent for any password, supplied or generated, and contains the email, username and the plaintext password with a login link; it is not queued (`C:app/Notifications/PlatformUserCredentials.php:22-38`).

## User journeys and workflows
Super Admin → Users → New → choose a role → the temporary password is shown and emailed (`W:src/pages/admin/UserForm.vue:50-56`, `UsersList.vue:19,46,71`).

## Business rules
| ID | Rule | Where implemented | Evidence |
| --- | --- | --- | --- |
| BR-1 | Only `ADMIN`, `MODERATOR`, `SALES`, `SUPPORT` can be created or assigned here. | `RoleEnum::assignable`, request rule | `RoleEnum.php:103-111`; test `C:tests/Feature/UserCreationMatrixTest.php:109` |
| BR-2 | Only Super Admin may use these endpoints. | gate | tests `UserCreationMatrixTest.php:131,140,154`, `C:tests/Feature/Admin/PlatformUserTest.php:115,123` |
| BR-3 | Super Admin accounts and the caller's own account cannot be changed through these endpoints. | `guardTarget` | `PlatformUserController.php:133-139`; test `PlatformUserTest.php:132` (delete only) |
| BR-4 | Tenant users are invisible here (404). | `guardTarget` | `:129-131`; test `PlatformUserTest.php:141` |
| BR-5 | Platform usernames are unique among platform users; emails are unique across all users. | request rules | `StorePlatformUserRequest.php`; test `UserCreationMatrixTest.php:160,177` |
| BR-6 | A platform user created here can sign in. | | test `PlatformUserTest.php:44` |

## Validation and error handling
`StorePlatformUserRequest`: `name` required string max 150; `username` required string min 3 max 150 regex `^[a-z0-9._-]+$` unique among users with null restaurant; `email` required email max 255 unique; `role` required in `assignable()`; `status` nullable ACTIVE|SUSPENDED; `password` nullable string min 8 max 255. `UpdatePlatformUserRequest` (`C:app/Http/Requests/Admin/UpdatePlatformUserRequest.php:17-32`): same without `password`, uniqueness ignoring the target.

## Edge cases and failure handling
- Role or status changes take effect at the next request because the JWT guard re-reads the user (`auth-login`); whether other effects follow: `BEHAVIORAL_ANALYSIS.md`.

## Cross-application dependencies
None with the POS. Vue: `W:src/pages/admin/UsersList.vue`, `UserForm.vue` (hard-coded assignable roles `:18`), routes `W:src/router/index.js:31-33` (`platform_users.manage`).

## Security considerations
- Capability-gated; guard against self and Super Admin targets; audit events for create, update, reset, delete.
- Temporary passwords are emailed in clear text.
- Throttling only on reset-password.

## Known limitations
- Reset-password, the self-guard and the credentials mail have no tests (`grep` over `C:tests` for `admin/users/.*reset-password`, `platform_user_self`, `PlatformUserCredentials` → no match).
- `PlatformUserTest.php:132` is named for delete and mutate but asserts only delete.
- No UI/endpoint to create a Super Admin.

## Existing automated tests
| Layer | File and test | Covers | Gaps |
| --- | --- | --- | --- |
| Cloud feature | `C:tests/Feature/Admin/PlatformUserTest.php:22,44,63,77,92,106,115,123,132,141,155` | create, login, invalid roles, index scope, per-role access to leads/plans/restaurants/audit, forbidden roles, super-admin protection, CRUD | reset-password, self guard, mail, throttle |
| Cloud feature | `C:tests/Feature/UserCreationMatrixTest.php:79,109,131,140,154,160,177` | creation matrix and uniqueness | |

## Acceptance criteria
- AC-1: Super Admin can create platform users with the four assignable roles and receives or supplies a password.
- AC-2: Other platform roles and tenant users cannot use the endpoints.
- AC-3: Super Admin accounts, the caller's own account and tenant users cannot be modified through them.
- AC-4: A created platform user can sign in and has exactly the matrix capabilities of their role.

## Confirmed source references
`C:routes/api.php:139-146`; `C:app/Http/Controllers/Admin/PlatformUserController.php`; `C:app/Services/PlatformUserService.php`; `C:app/Http/Requests/Admin/{StorePlatformUserRequest,UpdatePlatformUserRequest}.php`; `C:app/Notifications/PlatformUserCredentials.php`; `W:src/pages/admin/{UsersList,UserForm}.vue`.

## Unknowns and assumptions
- UNVERIFIED: how the first Super Admin is created; the mail delivery behavior; whether `Auditable` writes extra rows for these models.
