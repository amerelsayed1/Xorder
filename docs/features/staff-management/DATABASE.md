# Database impact: Restaurant staff accounts

Verified against: 2026-10-20 · cloud `main 06bc8e3` · POS `main d592db8` (uncommitted files in both repos are documentation, agent/script files and two POS files outside this feature; none is cited as evidence unless stated). Core state: `drafted` (author self-check, mechanical citation check; five independent passes (rounds 1-5), criterion not met: `docs/validation/2026-10-20-batch1-*-report.md`). Path prefixes: `C:` = `apps/xorder-cloud/apps/api/`, `P:` = `apps/xorder-pos/`, `W:` = `apps/xorder-cloud/apps/web/`, `K:` = `apps/xorder-cloud/packages/`, `A:` = `apps/xorder-cloud/apps/`.

## Tables and constraints
Cloud `users` (see `auth-login` DATABASE for the base columns): `role_id` nullable FK to `roles` with `restrictOnDelete` (`C:database/migrations/2026_08_22_000100_create_roles_table.php:45-46`); per-tenant username unique expression index; `restaurant_id` FK. `plans.max_staff` unsigned integer nullable (`C:database/migrations/2026_08_25_000100_add_max_staff_to_plans_table.php:23`); plan CRUD allows `max_staff` null, integer, 1-1000 (`C:app/Http/Requests/Admin/StorePlanRequest.php:29`).
POS `pos_staff` (database triggers added by migration 42 refuse a second active owner and roll back a seeder upsert that would create one: `P:lib/data/postgres/migrations.dart:3736-3823`; the seeder upserts on `id` only, `P:lib/data/cloud/bootstrap_seeder.dart:467`, so a local row with another id and the same `(restaurant_id, username)` would hit the unique constraint at `migrations.dart:184` inside the single seeding transaction): `id bigserial`, `restaurant_id`, `branch_id` nullable, `name`, `username`, `pin_salt text NOT NULL`, `pin_hash text NOT NULL`, `capabilities text[]`, `is_active`, `created_at`, `restaurant_id` NOT NULL with a cascading FK (`:173`), FK on `branch_id` with `ON DELETE CASCADE` (`:174`); POS tables that reference `pos_staff` mostly use `RESTRICT` or `SET NULL` (for example `opened_by`, `:288`, `refunded_by`, `:1161`; other references not all enumerated), while `pos_staff_roles.staff_id` (`:2113`) and `pos_staff_permission_overrides.staff_id` (`:2136`) use `ON DELETE CASCADE`, `capabilities` NOT NULL default `'{}'` (`:179`), unique `(restaurant_id, username)`; a later ALTER adds `role_id bigint REFERENCES pos_roles ON DELETE RESTRICT` (`P:lib/data/postgres/migrations.dart:171-184,416-419`).

## Relationships
`users.role_id` → `roles`; `roles.restaurant_id` cascades with the restaurant; `users.restaurant_id` is nullable with `ON DELETE SET NULL` (`2026_06_27_002001_create_restaurants_table.php:36-39`). The migration foreign keys to `users` that were read use `nullOnDelete` (examples: `audit_logs.actor_id`, `pos_shifts.opened_by_id`/`closed_by_id`; every migration was not re-read for this document), except `device_tokens.user_id`, which cascades on delete (`C:database/migrations/2026_07_19_000100_create_device_tokens_table.php:17`); `sessions.user_id` has no FK. `destroy` is a hard delete (`StaffController.php:132`).

## Shared entities across applications
| Entity | Cloud | POS | Identity |
| --- | --- | --- | --- |
| staff member | `users` (role `RESTAURANT_STAFF`/`RESTAURANT_ADMIN`) | `pos_staff` | cloud user id used as the POS row id for bootstrapped staff (`P:lib/data/cloud/bootstrap_seeder.dart:465-486`) |

## Proposed changes
None.

## Transactions and concurrency
`staffLimitReached` and `create` are separate steps without a surrounding transaction (`StaffController.php:75-81`).

## Indexes and query performance
Staff list is an unpaginated query filtered by `restaurant_id` and role.

## PostgreSQL vs SQLite differences
The username expression index is created by raw SQL in a migration that runs on every driver (`2026_07_21_000300_make_username_unique_per_tenant.php:20`); only the SQLite re-creation is driver-conditional (`2026_08_22_000100_create_roles_table.php:119-128`).

## Migration and rollback plan
None proposed.

## Backup/data access constraints
Personal data (names, emails, usernames, password hashes, PIN verifiers); no backup read.
