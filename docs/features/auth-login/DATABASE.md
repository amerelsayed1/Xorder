# Database impact: Login, session token and password change

Verified against: 2026-10-20 · cloud `main 06bc8e3` · POS `main d592db8` (uncommitted files in both repos are documentation, agent/script files and two POS files outside this feature; none is cited as evidence unless stated). Core state: `drafted` (author self-check, mechanical citation check; five independent passes (rounds 1-5), criterion not met: `docs/validation/2026-10-20-batch1-*-report.md`). Path prefixes: `C:` = `apps/xorder-cloud/apps/api/`, `P:` = `apps/xorder-pos/`, `W:` = `apps/xorder-cloud/apps/web/`, `K:` = `apps/xorder-cloud/packages/`, `A:` = `apps/xorder-cloud/apps/`.

Written from migrations. Production is PostgreSQL; tests run on SQLite.

## Tables and constraints
| Table.column | Type / rule | Migration |
| --- | --- | --- |
| `users.id`, `name`, `password` | id, string, string (hashed by cast) | `C:database/migrations/0001_01_01_000000_create_users_table.php:15-19` |
| `users.email` | string, globally unique; later made nullable | `0001_01_01_000000_create_users_table.php:17`; `C:database/migrations/2026_07_21_000200_add_username_to_users_table.php:41` |
| `users.role` | string, default `RESTAURANT_ADMIN`, indexed | `0001_01_01_000000_create_users_table.php:20` |
| `users.restaurant_id` | unsigned bigint nullable, indexed; FK added in the restaurants migration | `:22`; `C:database/migrations/2026_06_27_002001_create_restaurants_table.php:35-41` (foreign key with `ON DELETE SET NULL`, `:36-39`) |
| `users.status` | string, default `ACTIVE` (`UserStatus`: ACTIVE, SUSPENDED) | `:23`; `C:app/Enums/UserStatus.php:5-9` |
| `users.username` | added nullable, backfilled, then NOT NULL | `2026_07_21_000200_add_username_to_users_table.php:16,34,38` |
| username uniqueness | global unique dropped; unique expression index `(COALESCE(restaurant_id, 0), username)` named `users_username_per_tenant_unique` | `C:database/migrations/2026_07_21_000300_make_username_unique_per_tenant.php:16-20` (re-created on SQLite only: `C:database/migrations/2026_08_22_000100_create_roles_table.php:119-128` returns early unless the driver is SQLite; PostgreSQL keeps the original index) |
| `users.role_id`, `pos_pin_salt`, `pos_pin_hash` | `role_id` nullable FK to `roles` (`restrictOnDelete`); PIN pair nullable (owned by `tenant-roles`, `pos-pin`) | `C:database/migrations/2026_08_22_000100_create_roles_table.php:44-47`; `C:database/migrations/2026_09_02_000300_add_pos_columns_to_restaurants_and_users.php:39-42` (`pos_pin_*`) |
| `users.password_changed_at` (stamped by change-password, password reset `PasswordResetController.php:44`, admin provisioning `RestaurantProvisioningService.php:118,233-238`, staff create/reset `TenantUserService.php:48,95` and platform-user create/reset `PlatformUserService.php:41,89`) | timestamp nullable | `C:database/migrations/2026_07_25_000200_add_password_changed_at_to_users_table.php:18` |
| `users.remember_token`, `email_verified_at` | standard | `0001_01_01_000000_create_users_table.php:18,24` |
| `password_reset_tokens` | `email` primary, `token`, `created_at` nullable | `:28-32` |
| `sessions` | exists; not used by the JWT guard (use by web routes: `C:config/session.php:21` defaults the driver to `database`, production `SESSION_DRIVER` not read: UNVERIFIED) | `:34-41` |

## Relationships
`users.restaurant_id` → `restaurants`; `users.role_id` → roles (see `tenant-roles`). `User` has no tenant scope (`C:app/Models/User.php`, no `BelongsToRestaurant`).

## Shared entities across applications
The POS does not read `users` to log in: it calls login only at pairing (`FEATURE.md` cross-application section). Staff reach the till through the bootstrap bundle (see `staff-management`).

## Proposed changes
None (as-built documentation).

## Transactions and concurrency
Login and change-password run no explicit transaction (`C:app/Http/Controllers/Auth/AuthController.php`). Per-tenant username uniqueness is guaranteed by the database index; the form requests that create or rename users validate it first with `Rule::unique` (`C:app/Http/Requests/Dashboard/StoreStaffRequest.php:30`, `UpdateStaffRequest.php:29`, `C:app/Http/Requests/Admin/StorePlatformUserRequest.php:26`, `UpdatePlatformUserRequest.php:26`, `UpdateRestaurantAdminRequest.php:31`); `StoreRestaurantRequest` creates the first restaurant admin with no `Rule::unique` on the username (`C:app/Http/Requests/Admin/StoreRestaurantRequest.php:59-61`, comment: enforced by the database index).

## Indexes and query performance
Indexes on `users.role` and `users.restaurant_id`, the unique email index and the per-tenant username expression index; the login lookup is `where username = ? and restaurant_id = ?` (or `restaurant_id IS NULL`) through the Eloquent provider (`AuthController.php:32-41`, `vendor/laravel/framework/src/Illuminate/Auth/EloquentUserProvider.php:126-136`); whether PostgreSQL uses the `COALESCE` expression index for that predicate is UNVERIFIED.

## PostgreSQL vs SQLite differences
The username index migration uses raw SQL with `COALESCE` (`CREATE UNIQUE INDEX`, `up()`, `:20`; `DROP INDEX` is in `down()`, `:25`) executed on every driver (`2026_07_21_000300_make_username_unique_per_tenant.php`); the SQLite tests do not prove PostgreSQL behavior. Strict `rid` typing: UNVERIFIED.

## Migration and rollback plan
Existing migrations only; no change proposed.

## Backup/data access constraints
`users` holds credentials hashes and personal data; no backup content was read.
