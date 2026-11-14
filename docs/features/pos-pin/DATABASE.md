# Database impact: Cashier PIN for the POS

Verified against: 2026-10-20 · cloud `main 06bc8e3` · POS `main d592db8` (uncommitted files in both repos are documentation, agent/script files and two POS files outside this feature; none is cited as evidence unless stated). Core state: `drafted` (author self-check, mechanical citation check; no independent validation pass). Path prefixes: `C:` = `apps/xorder-cloud/apps/api/`, `P:` = `apps/xorder-pos/`, `W:` = `apps/xorder-cloud/apps/web/`, `K:` = `apps/xorder-cloud/packages/`, `A:` = `apps/xorder-cloud/apps/`.

## Tables and constraints
Cloud: `users.pos_pin_salt string(32) nullable`, `users.pos_pin_hash string(64) nullable`, `restaurants.pos_config_version unsigned bigint default 1` (`C:database/migrations/2026_09_02_000300_add_pos_columns_to_restaurants_and_users.php:34,40-41`). POS: `pos_staff.pin_salt text NOT NULL`, `pos_staff.pin_hash text NOT NULL` (`P:lib/data/postgres/migrations.dart:171-184`).

## Relationships
Columns belong to the user row; `pos_staff.id` equals the cloud user id for bootstrapped staff.

## Shared entities across applications
Verifier pair cloud `users` ↔ POS `pos_staff`, encoded base64 on both sides.

## Proposed changes
None.

## Transactions and concurrency
Single-row update; the config version bump is a separate statement (`C:app/Services/PosConfigVersion.php:37-46`).

## Indexes and query performance
None specific.

## PostgreSQL vs SQLite differences
None found.

## Migration and rollback plan
None.

## Backup/data access constraints
Verifiers are credentials-adjacent; excluded from audit diffs (`C:app/Models/User.php:24-26`); no backup read.
