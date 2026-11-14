---
paths:
  - "apps/xorder-cloud/apps/api/database/**"
  - "apps/xorder-pos/lib/data/postgres/**"
  - "apps/xorder-pos/bin/**"
---

# PostgreSQL migrations and queries

Two surfaces; identify which one a task touches.
1. **Cloud (production at xorder.io)**: Laravel migrations in `apps/xorder-cloud/apps/api/database/migrations`. Every deploy of `main` runs `migrate --force` (entrypoint and `deploy.sh`), so a new migration's `up()` must be additive and non-destructive: nullable or defaulted columns, no drops/renames/type changes of populated columns, no `unique()` on columns with possible duplicates, no `DB::table()->update/delete` on tenant data without an approved plan. Cloud tests run on SQLite `:memory:` and cannot catch Postgres-only problems (locks, `ALTER` rewrites, constraint/index syntax): review those by reading and say so. `/release-check` is the per-migration gate before any push.
2. **POS branch server**: migrations in `apps/xorder-pos/lib/data/postgres/` applied by `bin/pos_migrate.dart`; PostgreSQL-backed tests use throwaway databases via `test/data/pg_fixture.dart` (`scripts/check.sh`).

Review: lock duration, index creation strategy on big tables, constraints and foreign keys (orphans), defaults on existing rows, backfill cost, rollback path, transaction isolation, the `restaurant_id` tenant column and its index.

Execution: only against a disposable local test database, with user consent. Never connect to production, never run `migrate:fresh`/`refresh`/`rollback`/`db:wipe`, never touch `db-backups/` (no read, restore, export or delete). Never modify a migration that has already shipped; write a new one.
