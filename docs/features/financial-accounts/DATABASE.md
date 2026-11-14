# Database impact: financial accounts (XORD-015, stage 1)

Verified against: xorder-cloud `06bc8e3`, xorder-pos `a6f5fe5` (working trees dirty) · 2026-10-26. **Both migrations are written, tested on SQLite (cloud) and on a local throwaway PostgreSQL (POS), and not applied to any real or production database.** The cloud migration reaches production when the owner pushes `main` (CI runs `migrate --force`): run `/release-check` first.

## Tables and constraints

### Cloud (`C:database/migrations/`)
**`2026_10_26_000100_create_financial_accounts_table.php`** → `financial_accounts`

| Column | Type | Notes |
| --- | --- | --- |
| `id` | bigint PK | |
| `restaurant_id` | FK `restaurants`, cascade | tenant column; `BelongsToRestaurant` |
| `branch_id` | nullable FK `branches`, **no on-delete action** | null = shared by the whole business. NOT `nullOnDelete`: removing a branch must not silently turn its drawer into a shared account. Deleting a **branch** that has an account is refused by the database, and `BranchController::destroy` now answers that as a 409 with a message (`branch_has_accounts`) instead of a 500. Deleting a **restaurant** (cascade to branches and accounts) was checked on PostgreSQL 16 with a throwaway temporary-table repro of this exact shape (older branches constraint, newer accounts constraint): it succeeds. A reviewer argued from PostgreSQL's cascade ordering that it could fail; the repro did not bear that out. **UNVERIFIED on production's PostgreSQL version** |
| `name` | string(120) | unique with `restaurant_id` |
| `kind` | string(8) | `cash | bank | wallet`, validated in the request (no DB CHECK, same as `tender_types.kind`) |
| `currency` | string(3) | server-set from the restaurant |
| `reference_label` | nullable string(40) | short hint; the API refuses 9+ digits |
| `is_active` | boolean, default true | accounts are never deleted |
| `sort_order` | unsigned int, default 0 | |
| timestamps | | |

Indexes: `unique(restaurant_id, name)`, `index(restaurant_id, branch_id)`.

**`2026_10_26_000200_create_tender_account_defaults_table.php`** → `tender_account_defaults`

| Column | Type | Notes |
| --- | --- | --- |
| `id` | bigint PK | |
| `restaurant_id` | FK, cascade | |
| `tender_type_id` | FK `tender_types`, cascade | |
| `branch_id` | nullable FK `branches`, cascade | null = business-wide fallback |
| `branch_key` | unsigned bigint, default 0 | `branch_id` as a **non-null** number, 0 = whole business. Set by the model (`TenderAccountDefault::booted`) |
| `financial_account_id` | FK `financial_accounts`, no on-delete action | |

Unique `(tender_type_id, branch_key)` (`tender_account_defaults_method_branch_unique`). A plain unique over a nullable `branch_id` would let two business-wide rows in (NULLs never collide on SQLite or PostgreSQL), and this repo avoids engine-specific SQL such as partial indexes (`.claude/rules/cloud-laravel-vue.md`), hence `branch_key`.

`branch_key` is kept in step by the model's `saving` hook only. A query-builder `insert`, `upsert` or `update` skips it, so nothing may write this table except through the model (today only `TenderAccountDefaultController` does). The cloud has no CHECK to back that up (the POS does: `branch_key = COALESCE(branch_id, 0)`). `branch_id` here is `cascadeOnDelete`, on the POS it has no action; the difference is harmless today (branches are not deleted on a till).

### POS (`P:lib/data/postgres/migrations.dart`, migration **60**)
`pos_financial_accounts` (`id bigserial` = the platform id on a cloud till, `restaurant_id`, `branch_id` nullable FK `pos_branches`, `name`, `kind` CHECK in (cash, bank, wallet), `currency` nullable, `reference_label`, `is_active`, `sort_order`, `created_at`; CHECK `btrim(name) <> ''`) and `pos_tender_account_defaults` (`restaurant_id`, `tender_type_id` FK `pos_tender_types` cascade — the **local** method id, `branch_id`, `branch_key`, `financial_account_id` FK, `UNIQUE (tender_type_id, branch_key)`, CHECK `branch_key = COALESCE(branch_id, 0)`). Plus one idempotent `UPDATE pos_roles` giving the **owner** role `finance.accounts`.

Migration number 60 is only free because **56-59 are still uncommitted** in `xorder-pos`; if other work lands first the number must be re-checked.

## Proposed changes
None to `tender_types`, `order_payments`, `pos_refund_tenders`, `pos_tender_types`, `pos_order_payments` or `pos_refund_payments`. Stage 2 (not built) adds a payment-side account snapshot and a movements table.

## Transactions and concurrency
- Cloud: a default is set with a find-then-save and a `UniqueConstraintViolationException` retry (two admins setting the same pair at once). That retry works in autocommit; on PostgreSQL a unique violation aborts an enclosing transaction (25P02), so it would fail if a middleware ever wrapped requests in one (none does today). Account name races are answered as a 422 (`FinancialAccountController::persist`). Account `PUT`/`DELETE` guards read the defaults first; a race between disabling an account and setting it as a default can leave a default pointing at a just-disabled account (the foreign key still holds). UNVERIFIED under real concurrency; stage 1 has no money at stake.
- POS: every authoring write is one transaction with its audit row (`financial_account.saved`, `tender_account_default.saved`). `setDefault` locks the pair (`FOR UPDATE`) and upserts on `(tender_type_id, branch_key)`.
- POS seeding runs inside the existing bundle transaction (`BootstrapSeeder.seed`).

## Known hazards carried to stage 2
- **Platform account ids are the POS primary keys** (like branches and products). A till that authored accounts offline and later became a cloud till would have local ids 1..n that a platform id could overwrite in place. Harmless in stage 1 (nothing references an account), but once a payment names an account it would re-point history. `pos_tender_types` solved the same problem with a separate `platform_id` column (migration 41). **Stage 2 must add the same before any payment stores an account id**, or refuse to seed over local rows.
- The POS name-uniqueness check (`lower(btrim(name))`) is an application check with no database index; two administrator sessions could race. The cloud has a unique key (exact case) plus the request's case-insensitive check.
- Cloud `kind` has no CHECK (validated in the request, like `tender_types.kind`); the POS has one. Cloud `currency` is NOT NULL; the POS column is nullable (nothing offline knows the currency).

## Indexes and query performance
Tables hold a handful of rows per restaurant. The `(restaurant_id, branch_id)` index serves the dashboard list; the unique keys serve the lookups. No backfill, no table rewrite, no long lock: both cloud migrations only `CREATE TABLE`.

## Migration and rollback plan
- Additive. Cloud `down()` drops both tables; since nothing else references them, a rollback is `DROP TABLE` in reverse order. A deployed rollback would need the owner's approval (`migrate:rollback` is never run by Claude).
- POS migration 60 is append-only and idempotent (`IF NOT EXISTS`, guarded `UPDATE`), and was re-run in `financial_accounts_test` ("migration 60"). There is no down migration on the POS (by the project's rule that an applied migration is history).
- **PostgreSQL versus SQLite (cloud):** the cloud suite runs on SQLite and cannot prove PostgreSQL locks, constraint or index behaviour. Reviewed by reading: only `CREATE TABLE` with ordinary foreign keys and one ordinary unique index; no engine-specific SQL.
- Grants (POS, `local_bootstrap.dart`): the till role `SELECT`s both tables; a **cloud** till also `INSERT, UPDATE` on accounts and `INSERT, UPDATE, DELETE` on defaults (the seeder), revoked again on an offline till; sequence `UPDATE` is granted only on the accounts sequence (the seeder's `setval`), not on the defaults sequence; the administrator gets `SELECT, INSERT, UPDATE` on accounts (never `DELETE`) and `SELECT, INSERT, UPDATE, DELETE` on defaults. Proved against real roles: `till_grants_enforced_test`, `admin_grants_enforced_test`.

## Backup/data access constraints
No backup, dump or production database was read. Test data are throwaway rows in the checkout's own test database (`xorder_pos_test_<checkout>`) and in SQLite `:memory:`. No account number or credential is stored: `reference_label` is a short hint and the API and the till both refuse a digit run of nine or more.
