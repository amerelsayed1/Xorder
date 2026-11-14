# Database impact: two POS apps on shared modules

Verified against: 2026-11-08 · POS `development` `7fa0d06` · cloud `feat/licence-one-mode` `30b1529`. Paths are relative to `apps/xorder-pos/` unless they start with `apps/xorder-cloud/`.

## Summary
**No schema change in either repository.** No migration is added, removed or edited (FEATURE.md section 6 "Out", BR-3; TECHNICAL.md section 5). Stage 6 on the cloud adds no migration (TECHNICAL.md stage 6 "Rollout").

## POS branch database
- **One schema for both apps (BR-3).** The migrations stay in the shared package, `packages/shared_module/lib/data/postgres/migrations.dart`, and both apps run them through `packages/shared_module/bin/pos_migrate.dart` (`cd packages/shared_module && dart bin/pos_migrate.dart`). `lib/data/postgres/` stays shared until the planned SQLite work (`pos-cloud-single-till-sqlite`, D11), which is out of scope here.
- **The database name stays `xorder_pos`.** Renaming the Dart package to `shared_module` (`7fa0d06`) did not rename the database: the default is `DeploymentConfig.defaultDatabaseName = 'xorder_pos'` (`packages/shared_module/lib/core/config/deployment.dart`, `git grep` on `7fa0d06`), and `pos_migrate.dart` and `installer_credentials.dart` default to the same name. Existing branch databases therefore keep working.
- **Which app set a database up** is read from data that already exists: the published site licence row carries `mode` (TECHNICAL.md section 1). Stage 2 uses it to refuse a database set up by the other app (BR-8, `TerminalBoot.otherAppMode`, `WrongAppScreen`, `databaseSetUpByOtherApp`). No column was added for this.
- **Data location on Windows** (`%ProgramData%\XOrder POS\pgdata`, service `XOrderPOS-PostgreSQL`) is planned to stay shared by both apps (TECHNICAL.md stage 5, D3). Stage 5 is not started; the installer currently builds the offline app only.
- **`config.json` does not follow** a renamed app: the Windows config folder follows `ProductName`, so a new app finds no `config.json` from today's single app and setup runs again (O1, owner: no migration of it). This is a file, not the database.

## Test databases
`packages/xorder_pos_test_support/lib/pg_fixture.dart` derives the test database tag from the **workspace root**, so every member shares one PostgreSQL test database per checkout; `scripts/check.sh` runs `integration` suites one at a time and drops that database at the end (`packages/shared_module/tool/drop_test_databases.dart`). Test infrastructure only; no effect on a branch database.

## Cloud
No table or column change. `pos_licences.modes` keeps its existing type; stage 6 only narrows what validation accepts on write (see API.md). Existing rows covering both modes are not touched.

## Migration safety
Nothing to review: no migration, no backfill, no lock. AC-9 (an existing database from `3052a53` opened by each new app with no data change) has **no automated test yet** (planned PostgreSQL test, TEST_PLAN.md).

## Unknowns
- UNVERIFIED: how many production licences cover both modes (production not read).
- UNVERIFIED: the exact line in the shared code that reads the site licence's `mode` on `7fa0d06` (TECHNICAL.md cites `providers.dart:2350-2361` on `3052a53`; line numbers have moved since).
