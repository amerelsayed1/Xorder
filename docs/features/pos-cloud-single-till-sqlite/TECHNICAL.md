# Cloud till on encrypted SQLite — technical plan

Status: **built, stages 0–6 committed on xorder-pos `development` (not pushed); stage 7 verification below** · 2026-11-09 · Specification: `FEATURE.md` with the owner's 2026-11-08 answers (Q1 Windows+macOS together, Q4 encrypted file, Q6 `sqlite3` FFI, Q8 every cloud till on its own file) · Verified against: xorder-pos `development` `76b0039`

Paths are relative to `apps/xorder-pos/`. **pp** = `packages/shared_module/lib/app/providers.dart`.

## Progress (2026-11-09)
| Stage | Commit | What landed | Proven by |
|---|---|---|---|
| 1 Seam | `28f6b67` | `lib/data/sql/sql.dart` (`SqlDatabase`, `Sql.named`, `TxSession`, `Result`); `PosDatabase` is the PostgreSQL engine; repositories off `package:postgres`; `PosDbException.sqlState` | full `check.sh` green, counts unchanged |
| 2 Portable reads | `6217b0d` | `row_reads.dart`; `SqlDialect`; SQLite forms of the 9 LATERAL joins; seeder sequence bump; refund-foots check on SQLite | full `check.sh` green |
| 3–4 Engine + schema | `fc1faa2` | `SqliteDatabase` (sqlite3mc/SQLCipher, serialised writer, `now()`, `gen_random_uuid()`, TRUNCATE, VACUUM INTO); `SqliteStatement` translator; generated schema (66 tables, 79 indexes); 18 triggers + 5 shape checks as triggers; `PosMigrator` on SQLite; `POS_TEST_ENGINE=sqlite` fixture | engine/translator/schema suites; cloud-till suites on SQLite (shared 412 pass / 16 skipped, cloud 178 / 8) |
| 5 Cloud app | `52d3e29` | cloud wiring binds the file; `embeddedDatastoreProvider` (setup prepares the file, no DB screen); backup snapshot; defaults seeder on the file; hard reset keeps the key; every cloud till main; "each till alone" notice (en/ar); cloud app drops `postgres` | `cloud_datastore_test`, `hard_reset_test`, `cloud_setup_collapsed_test`; unit suites shared 2620 / cloud 127 / offline 852 |
| 6 Installer | `53255d2` | Cloud flavor: no pgsql, pos_migrate, provision.ps1, types or LAN task; workflow Cloud leg | `installer_consistency_test` (17); the workflow itself not run |
| 7 Verification | — | `scripts/check.sh` gains the SQLite pass; docs | see `TEST_REPORT.md` |

**Found by running the suites on both engines (fixed):** the outbox drain read an `EXISTS` as `== true` (SQLite returns 1), so on SQLite a sale did not wait for its customer; `RETURNING business_day_id` is read before SQLite's AFTER trigger stamps it (no app code relies on it; tests read it back); SQLite enforces `ON DELETE RESTRICT` before a cascade clears the child (generated as NO ACTION); `xmax` has no SQLite form (seeding branches); 49 more date/boolean casts in the data layer.

**Deviations from the plan, stated:** the engine runs on the main isolate with every statement serialised, not on a worker isolate (a one-till file answers in milliseconds; not yet measured on years of history — follow-up). The `pos_users_password_hash_shape` regex check is kept as a GLOB-based trigger, an approximation of the regex.

## 1. What the code says (measured, read-only sweep 2026-11-08)
| Fact | Evidence |
|---|---|
| `PosDatabase` is a concrete class; **no interface above it**. Repositories use `package:postgres` types directly (`TxSession`, `Sql.named`, `Result`) and rely on the driver's decoding (`timestamptz`→`DateTime`, `jsonb`→`Map`, `text[]`→`List`, `bytea`→`Uint8List`) | `data/postgres/pos_database.dart:282-472`; pp:1638-1646 |
| A cloud **main** till reaches 24 repository files, about **7,400 lines** of SQL: catalog, discounts, reasons, floor, directory (branch, session), orders, order history, refunds, settings, business day, cash movements, print queue, parked tickets, sync queue, order types, shift, site licence, customers, tender types, receipt profile, staff directory + audit (`admin_repositories.dart`), backup | sweep §2 |
| Not reached on a cloud till: stock/purchasing/suppliers/units/service charges (admin pool, offline back office only), reports, roles, financial-accounts admin, ETA queue (compile flag `XORDER_ETA_FILING`) | sweep §2 |
| Cloud app database code: `outbox_drain` 1,322 · `bootstrap_seeder` 910 · `cloud_sync` 322 · `logo_sync` 137 lines | `apps/xorder_pos_cloud/lib/data/cloud/` |
| PostgreSQL-only SQL in reached files: `FOR UPDATE` (orders ×3, sync queue, admin ×2), `= ANY(@list)` (history ×4, refunds ×2, cash, directory, seeder ×4, drain), `::` casts (~50), `ILIKE` (history ×3), `array_agg` (catalog, history), `bool_or` (shift), `now()` (~30), `setval(pg_get_serial_sequence)` (seeder ×2), `::jsonb` (3). Portable already: `ON CONFLICT … DO UPDATE`, `RETURNING`, `FILTER (WHERE …)` (SQLite ≥ 3.35 / 3.30) | sweep §3 |
| Schema: 64 PostgreSQL migrations (5,098 lines) under one advisory lock. About 55 tables are used by a cloud till. Their behaviour relies on **triggers**: append-only audit, refund counters (`SECURITY DEFINER`), a **deferred** constraint trigger (`pos_refunds_tendered_in_full`), business-day stamping, print-once, one-owner rules, stock unit and catalogue scope triggers | `data/postgres/migrations.dart:519-4916` |
| A **cloud child** (tablet or extra desktop) logs in to the main device's PostgreSQL over the LAN | `apps/xorder_pos_cloud/lib/wiring.dart:126-137`; pp:666-693 |
| Day-close backup is reached on a cloud till (`pg_dump` from `<exe>\pgsql\bin`) | `features/home/.../day_close_dialog.dart:66-73`; `data/backup/pg_tools.dart:51-52` |
| Tests: 75 shared + 9 cloud test files use `PgFixture` (real PostgreSQL) | `packages/xorder_pos_test_support/lib/pg_fixture.dart` |
| Installer: both flavors ship the `database` component (EDB PostgreSQL 16, `provision.ps1`, `pos_migrate.exe`) | `installer/xorder-pos.iss:158-172`; `.github/workflows/windows-installer.yml:42,143-160` |
| Library: `sqlite3` **3.9.1** resolves with the workspace. It bundles prebuilt SQLite through Dart build hooks, selectable with `hooks: user_defines: sqlite3: source: sqlite3 \| sqlite3mc \| sqlcipher`. `sqlcipher_flutter_libs` is **end of life** (`0.7.0+eol`) | `flutter pub add --dry-run`; sqlite3.dart `doc/hook.md` |

## 2. The key design decision: one set of repositories, two engines
Writing a SQLite copy of 7,400 lines of repository code would create two copies that drift (FEATURE §11). **Proposed instead:** put a small SQL seam under the repositories and make the repositories' SQL portable. One repository class then runs on PostgreSQL (offline app, unchanged behaviour) and on SQLite (cloud app).

- **Seam** (new, `packages/shared_module/lib/data/sql/`):
  - `SqlDatabase`: `runTx`, `query`, `probe`, `close`.
  - `SqlSession`: `execute`, `query` inside a transaction.
  - `SqlRow`: typed accessors `int`, `text`, `dateTime`, `json`, `bytes`, `list`. These read either engine's representation.
  - `SqlDialect`: the handful of constructs that differ.
- **PostgreSQL engine** = today's `PosDatabase`, adapted to the seam. The same SQL is sent and the same results come back.
- **SQLite engine** = `sqlite3` on its own isolate, so a long statement never blocks the UI. It holds one connection and one writer. Each transaction is `BEGIN IMMEDIATE`, which is how SQLite gives the "row lock" that `FOR UPDATE` gives today, for the whole file. Pragmas: `journal_mode=WAL`, `synchronous=FULL` (BR-7), `foreign_keys=ON`, `busy_timeout`.
- **Portable SQL rules,** applied to the reached repositories:

  | PostgreSQL construct | Portable form |
  |---|---|
  | `= ANY(@list)` | `IN (…)` expanded by the seam |
  | `now()` | a timestamp parameter from the Dart clock |
  | `ILIKE` | `lower(x) LIKE lower(@q)` |
  | `::date`/`::text` casts | dialect helpers |
  | `array_agg` | `dialect.jsonAgg` |
  | `bool_or` | `MAX(CASE …)` |
  | `FOR UPDATE` | dropped on SQLite (the transaction already holds the write lock) |
  | `setval(...)` | dialect helper (`sqlite_sequence`) |

  Plain portable SQL stays as it is: `ON CONFLICT … DO UPDATE`, `RETURNING`, `FILTER (WHERE …)`.
- **Storage in SQLite:**
  - Money: `INTEGER` minor units (BR-3).
  - Timestamps: ISO-8601 UTC text, so they sort in time order and `date()` works.
  - JSON: `TEXT`.
  - Booleans: `INTEGER` 0/1.
  - Ids: `INTEGER PRIMARY KEY AUTOINCREMENT`.

**Cost of this choice:** stage 1 touches every repository once, offline included. That is a behaviour-preserving refactor, proven by the existing PostgreSQL suite. **What it buys:** no second copy, and the existing repository tests run on both engines, which gives AC-3 parity almost for free.

## 3. Schema on SQLite
- A **baseline schema**, equal to PostgreSQL migration 64 for the about 55 tables a cloud till uses, written once in SQLite DDL. There are no SQLite tills in the field, so there is no history to replay. From then on SQLite has its own numbered list, and every future migration on those tables is written twice (FEATURE §10).
- **Triggers rewritten in SQLite trigger syntax:**
  - append-only audit and backups;
  - refund counters;
  - business-day stamping;
  - print-once;
  - one-owner rules;
  - stock unit;
  - catalogue scope.

  `SECURITY DEFINER` has no meaning in a file the app owns.
- **The deferred trigger** (`pos_refunds_tendered_in_full`, checked at commit) has no SQLite equivalent. That check moves into `PostgresRefundsRepository`'s transaction, renamed with the seam, before commit, on both engines. A parity test proves the rule is kept.
- **Not created on SQLite:** purchasing, suppliers, stock items, units admin, service-charge admin, reports, ETA, roles admin (§1).

## 4. Encryption (Q4)
- **Engine:** `source: sqlite3mc` (SQLite3MultipleCiphers) configured with `PRAGMA cipher='sqlcipher'`. It writes a SQLCipher-compatible encrypted file, uses the newest SQLite (≥ 3.35, needed for `RETURNING` / `ON CONFLICT`), is MIT-licensed, and needs no OpenSSL. The `sqlcipher` source links OpenSSL on Windows and may carry an older SQLite. **Needs your confirmation** (the decision was "SQLCipher"; this is the same encryption from a different build).
- **Key:** 32 random bytes made at setup, kept in the existing secret store (`PosDbSecretStore`: DPAPI on Windows, the 0600 file store on macOS).
- **Honest limit:** on macOS the key file sits on the same user account as the database. The encryption protects a copied file or a stolen disk, not a person already logged in as that user. Recorded as the AC-10 risk.

## 5. Cloud app behaviour changes
- **Datastore follows the app** (Q8): the cloud app always uses SQLite; the offline app always uses PostgreSQL. This supersedes BR-1's terminal-count rule.
- **Setup connecting step:** creates the file (`<app support>/XOrder POS/xorder_pos.db`), makes the key, applies the schema, seeds from the bundle. **No database fields, no PostgreSQL.** The screen you saw on the Mac goes away.
- **No cloud children.** The "till only" / tablet path is removed from the cloud app: every cloud till is a main device with its own file. In the installer, the Cloud flavor has no "till only" type.
- **Several tills in one venue, each alone** (Q8). Each till's open tables, parked checks and drawer are its own. **Domain risk (restaurant):** two tills can seat table 5 at once. The setup summary and the floor screen say so plainly (new strings, en + ar). Shared tables via the cloud is its own feature later (new `POS-BE` items).
- **Day-close backup:** `VACUUM INTO` an encrypted copy (same key), verified by reopening it. Restore needs the key and stays a technician action.
- **Outbox, drain, seeder:** same idempotency key (`client_transaction_id`), same order and retries (BR-4); the seed stays one transaction (BR-5).

## 6. Stages
Each stage ends green before the next starts. Commit per stage on `development`, with your approval.

| # | Stage | Repo paths | Proven by | Rollback |
|---|---|---|---|---|
| 0 | **ADR** recording that the cloud app moves off "PostgreSQL in every mode" (`docs/pos/08-postgres-lan.md`); baseline `scripts/check.sh` | workspace `docs/`; ADR text for you to place | the green baseline output | none needed |
| 1 | **Seam + PostgreSQL engine**: `data/sql/` interfaces; `PosDatabase` behind them; every repository and the four cloud data files moved off `package:postgres` types. Behaviour-preserving | shared `data/postgres/*`, `data/sql/*`, pp; cloud `data/cloud/*` | full PostgreSQL suites unchanged and green (shared, offline, cloud) | revert the stage |
| 2 | **Portable SQL** in the 24 reached repositories and the cloud data files (the §2 table); the refund deferred check moved into the transaction | same | PostgreSQL suites green; new refund-tender test | revert |
| 3 | **SQLite engine**: add `sqlite3` with `sqlite3mc`, isolate worker, pragmas, key from the secret store, error classification (busy, full disk, corrupt/not a database, wrong key) | shared `data/sqlite/*`, pubspecs | engine unit tests: transactions, rollback, a crash mid-transaction then reopen (AC-4), wrong key refused | revert; remove the dependency |
| 4 | **SQLite schema** + `SqliteFixture` (temp file, no server); the reached repositories' test suites **run on both engines** | shared `data/sqlite/schema.dart`, test_support | parity: the same baskets on both engines give the same totals, invoice numbers and outbox payloads (AC-3); shift X/Z parity (AC-7); seed rollback (AC-6); Arabic and Latin search (AC-11) | revert |
| 5 | **Cloud app on SQLite**: providers choose the engine by app; setup builds the file; cloud child path removed; backup by `VACUUM INTO`; multi-till notice | pp, cloud `wiring.dart`, setup, `data/backup/` | cloud suite on SQLite; setup widget tests (no database step); backup and restore test (AC-8); offline suite unchanged (AC-2) | revert |
| 6 | **Installer and CI**: the Cloud flavor ships no PostgreSQL, `provision.ps1` or `pos_migrate.exe`; the workflow's cloud leg skips the EDB download and checks the app starts with no service | `installer/`, `.github/workflows/windows-installer.yml` | `installer_consistency_test`; a manual workflow run on Windows (**you trigger it**) | revert |
| 7 | **Verification and docs**: `scripts/check.sh`; the e2e driver on SQLite; repo `CLAUDE.md` "Primary datastore is PostgreSQL" fact; feature docs | — | real output in `TEST_REPORT.md` | — |

**Size:** about 18,000 lines touched. Stage 1 is the largest (mechanical, every repository). This is several sessions of work, not one.

## 7. Verification commands
```
cd apps/xorder-pos && scripts/check.sh                        # every member, PostgreSQL included
cd packages/shared_module && flutter test --tags sqlite         # the SQLite engine and parity suites (new tag; no server needed)
```

## 8. Approvals needed
- **This plan.**
- **The encryption build:** `sqlite3mc` (recommended) or `sqlcipher` (§4).
- **The new SQLite schema** (written, run only on temporary test files and on a till at setup).
- **Order, payment, refund and outbox repositories touched** (integrity work, but behaviour-preserving, with parity tests).
- **The installer change** (stage 6).
- **The ADR reversing "PostgreSQL in every mode"** for the cloud app.

## 9. Risks
- **Restaurants with several cloud tills double-seat tables** (Q8 by design). Mitigated only by the notice, until shared tables exist via the cloud.
- **Two schema lists from now on.** Every migration on a cloud-till table is written twice; a schema parity test (table and column sets) catches drift.
- **SQLite isolate:** every query crosses an isolate boundary. Measured in stage 3; a sale must stay instant.
- **Existing cloud tills on PostgreSQL** (none in the field, per the owner) are not migrated (BR-8). A dev machine resets setup.
- **The macOS key** sits with the user (§4).
- **Build-time download:** `sqlite3` fetches its prebuilt library from GitHub releases at build time (sha256-checked). The Windows CI needs that network access, or a mirror (`url_pattern`).
