# Database impact: Platform (Super Admin portal) users

Verified against: 2026-10-20 · cloud `main 06bc8e3` · POS `main d592db8` (uncommitted files in both repos are documentation, agent/script files and two POS files outside this feature; none is cited as evidence unless stated). Core state: `drafted` (author self-check, mechanical citation check; no independent validation pass). Path prefixes: `C:` = `apps/xorder-cloud/apps/api/`, `P:` = `apps/xorder-pos/`, `W:` = `apps/xorder-cloud/apps/web/`, `K:` = `apps/xorder-cloud/packages/`, `A:` = `apps/xorder-cloud/apps/`.

## Tables and constraints
`users` rows with `restaurant_id` NULL and `role` in `ADMIN`, `MODERATOR`, `SALES`, `SUPPORT` (`SUPER_ADMIN` seeded elsewhere); platform usernames share the "tenant 0" namespace of the unique expression index `(COALESCE(restaurant_id, 0), username)` (`C:database/migrations/2026_07_21_000300_make_username_unique_per_tenant.php:16-20`). Columns: see `auth-login` DATABASE.

## Relationships
None beyond `users`.

## Shared entities across applications
None.

## Proposed changes
None.

## Transactions and concurrency
`create` followed by `notify` and audit; no explicit transaction in the controller.

## Indexes and query performance
Unpaginated `whereNull('restaurant_id')` list (`PlatformUserController.php:25-33`).

## PostgreSQL vs SQLite differences
Same index caveat as `auth-login`.

## Migration and rollback plan
None.

## Backup/data access constraints
Staff personal data; no backup read.
