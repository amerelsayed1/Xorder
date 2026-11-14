---
name: postgres-management
description: Plan and review safe PostgreSQL migrations and queries.
---

# Postgres Management

Knowledge: before significant changes follow `.claude/rules/knowledge.md` (`/project-documentation context <feature> <phase>`); verify critical behavior in current source, and report missing or stale docs.

## Procedure
There are two PostgreSQL surfaces; identify which one a task touches.
1. **Cloud (production, live at xorder.io)**: Laravel migrations in `apps/xorder-cloud/apps/api/database/migrations`. Production runs `migrate` with `--force` on every deploy of `main` (entrypoint + `deploy.sh`), so any new migration's `up()` must be additive and non-destructive. Cloud tests run on SQLite `:memory:`, which cannot catch Postgres-only problems (locks, `ALTER` rewrites, constraint/index syntax) — review those by reading. `apps/xorder-cloud/.claude/skills/release-check` has the per-migration gate; use it.
2. **POS branch server**: migrations in `apps/xorder-pos/lib/data/postgres/` applied by `bin/pos_migrate.dart`; PostgreSQL-backed tests use throwaway databases via `test/data/pg_fixture.dart` (`scripts/check.sh`).

Review: lock duration, index creation strategy on big tables, constraints/foreign keys, defaults on existing rows, backfill cost, rollback path, transaction isolation, `restaurant_id` tenant column and index.

Execution: only against a disposable local test database, with user consent. Never connect to production, never run `migrate:fresh`/`rollback`/`db:wipe`, and never touch `db-backups/` (do not read, restore, export or delete).

## Required output
Report scope, verified file paths, assumptions/unknowns, changed files (if any), exact tests run with outcomes, risks and next action. Follow workspace `CLAUDE.md` approval rules.
