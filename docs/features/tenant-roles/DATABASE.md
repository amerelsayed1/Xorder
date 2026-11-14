# Database impact: Roles, capabilities and gates

Verified against: 2026-10-20 · cloud `main 06bc8e3` · POS `main d592db8` (uncommitted files in both repos are documentation, agent/script files and two POS files outside this feature; none is cited as evidence unless stated). Core state: `drafted` (author self-check, mechanical citation check; five independent passes (rounds 1-5), criterion not met: `docs/validation/2026-10-20-batch1-*-report.md`). Path prefixes: `C:` = `apps/xorder-cloud/apps/api/`, `P:` = `apps/xorder-pos/`, `W:` = `apps/xorder-cloud/apps/web/`, `K:` = `apps/xorder-cloud/packages/`, `A:` = `apps/xorder-cloud/apps/`.

## Tables and constraints
`roles` (`C:database/migrations/2026_08_22_000100_create_roles_table.php:21-38`): `id`, `restaurant_id` (FK, cascade on delete), `name` string(80), `name_ar` string(80) nullable, `capabilities` json not null, `is_system` boolean default false, `slug` string(40) nullable, timestamps; unique `(restaurant_id, name)` (`:36`); index `(restaurant_id, is_system)` (`:37`). `users.role_id` nullable FK to `roles` with `restrictOnDelete` (`:45-46`). The same migration backfills one `admin` role per existing restaurant with a frozen list of 28 verbs (`:70-107`); `2026_08_23_000200` seeds missing Admin roles through the live `TenantRoleService::presets()`, i.e. the current capability list (`:23-33`).
Later migrations: `C:database/migrations/2026_08_23_000200_make_admin_the_only_protected_role.php:21-41` (seed missing admin roles; other roles become non-system), `2026_08_23_000300_split_manage_capabilities_into_verbs.php:19-36` (rewrite roles through `TenantCapability::expand`; irreversible), `2026_08_23_000400_grant_live_view_to_roles_that_had_it.php:19-36`. No migration mentions `pos.operate`, `purchase.manage`, `pos.provision` or `customers.create` (`grep -rln` over `database` → no file).

## Relationships
`roles.restaurant_id` → restaurants; `users.role_id` → roles.

## Shared entities across applications
Capability strings only (no role row on the POS from the cloud); POS local roles live in `pos_roles` (`P:lib/data/postgres/migrations.dart:392-410`).

## Proposed changes
None.

## Transactions and concurrency
Role deletion with reassignment runs two statements (move holders, delete) with no `DB::transaction` call in the controller (`RoleController.php:111-114`); consequences: `BEHAVIORAL_ANALYSIS.md` I.

## Indexes and query performance
See above.

## PostgreSQL vs SQLite differences
The per-tenant username index is re-created by `restoreSqlitePerTenantUsernameIndex()` in the roles migration on SQLite only (`2026_08_22_000100_create_roles_table.php:120-128`, returns early for other drivers; also called from its `down()`); JSON column behavior not compared.

## Migration and rollback plan
Existing migrations only. `down()` bodies: `2026_08_23_000300` is empty; `2026_08_23_000400` strips `live.view` from every role (`:39-52`); `2026_08_23_000200` sets `is_system=false` on all admin roles (`:48-51`); the create-roles migration drops `roles` and `users.role_id` (`:130-140`).

## Backup/data access constraints
Role data is configuration; no backup read.
