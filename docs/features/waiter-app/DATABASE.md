# Database — waiter-app (WA1)

POS migration **65** (`packages/shared_module/lib/data/postgres/migrations.dart`), with its SQLite counterpart in `sqliteUpgrades[65]` (`lib/data/sqlite/sqlite_migrator.dart`) — a cloud till hosts handhelds too.

`pos_waiter_devices`: `id` bigserial PK · `business_id` → `pos_businesses` ON DELETE CASCADE · `branch_id` → `pos_branches` (nullable) · `name` text NOT NULL (CHECK not blank) · `token_hash` text NOT NULL UNIQUE (SHA-256 hex of the device token; the token itself is never stored) · `paired_at` timestamptz default now() · `last_seen_at` · `revoked_at`. Index `(business_id, branch_id)`.

- Additive: a new table, nothing else touched. Grant for the till role: `SELECT, INSERT, UPDATE` + the sequence (`LocalBootstrap.tillGrants`); no DELETE — a revoked device stays on record.
- Applied only by the till's own migrator on install/upgrade, and in tests on the throwaway PostgreSQL database and temporary SQLite files. Not applied to any real branch database.

Read and written, unchanged: `pos_parked_tickets` (the handheld's checks are the same rows the tills park, with migration 63's `version` compare-and-swap), `pos_users`/`pos_roles` (PIN sign-in), `pos_dining_tables`, the catalog, `pos_settings` (`waiter.link_enabled`, terminal scope).


## Cloud half (POS-BE-033, built 2026-11-09, not run on any real database)

Migration `xorder-cloud/apps/api/database/migrations/2026_11_09_000100_create_pos_waiter_tables.php`, **additive only** (three new tables, one defaulted column; nothing altered, dropped or backfilled):
- `pos_waiter_devices`: `restaurant_id` FK cascade · `name` · `token_hash` (HMAC-SHA256, unique; the token is never stored) · `created_by` → users (null on delete) · `last_seen_at` · `revoked_at` · timestamps · index `(restaurant_id, revoked_at)`.
- `pos_waiter_sessions`: `restaurant_id`, `device_id` → devices (cascade), `user_id` → users (cascade), `token_hash` unique, `last_seen_at`.
- `table_check_drafts`: `restaurant_id`, `table_visit_id` UNIQUE → table_visits (cascade), `lines` json (ids and quantities, never prices), `guests`.
- `table_visits.check_version` unsigned int NOT NULL DEFAULT 0 (the compare-and-swap counter).

Locks/PostgreSQL: on production PostgreSQL `ADD COLUMN … DEFAULT 0` on `table_visits` is metadata-only (PG 11+); the new tables are empty. Row locking in `WaiterCheckService::apply` (`lockForUpdate` on the table and visit) is **not exercised by the SQLite test suite**; reviewed by reading only. Reads and writes, unchanged in shape: `orders`, `order_rounds`, `order_items` (a waiter send appends a round to the visit's NEW order, or creates one with `source='waiter'`, `order_type='dine_in'`, `acting_user_id`).
