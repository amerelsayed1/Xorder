# Database impact: POS business day

## Tables and constraints
POS `pos_business_days` (`P:lib/data/postgres/migrations.dart:1448-1484`): `id`, `restaurant_id`, `branch_id`, `business_date date NOT NULL`, `opened_at`, `opened_by`, `closed_at`, `closed_by`, `forced`, `force_reason`, `gross_minor`, `net_minor`; `UNIQUE (restaurant_id, branch_id, business_date)`; CHECK that closed_at and closed_by come together; CHECK that a forced close has a reason. Nullable `business_day_id` on `pos_orders`, `pos_refunds`, `pos_shifts` and `pos_cash_movements`.
Trigger `pos_stamp_business_day(<time column>)` on orders and refunds (`occurred_at`) and shifts (`opened_at`) files the row under the day whose window contains that time, newest first, else NULL: **migration 36**, `migrations.dart:3343-3392`, which replaced migration 35's "whichever day is open" (`:3246-3341`).

## Proposed changes
**None.** No migration, no column, no index.

## Transactions and concurrency
`open()` is a single autocommit INSERT `ON CONFLICT (restaurant, branch, business_date) DO NOTHING` followed by a read (`P:lib/data/postgres/postgres_business_day_repository.dart:86-118`). It is **not** inside the shift's transaction, so the day is committed before the shift INSERT, which the trigger needs. Two tills on the same date are safe. Two tills on different dates at the roll-over hit `pos_business_days_one_open` (not the ON CONFLICT target); the service catches that and re-reads `current()`.

## Indexes and query performance
Existing: `pos_business_days_one_open` (partial unique on `closed_at IS NULL`) and the date unique key. The change adds one `current()` read per shift open or lock sign-in on an open shift, and one `lastClosed` read for the start-screen notice; both use those indexes.

## Migration and rollback plan
No migration. Rollback by reverting the code; open and closed day rows stay valid.

## Backup/data access constraints
An open day blocks restore (`P:lib/data/backup/backup_service.dart:378-396`); day close triggers the automatic copy (`P:lib/features/cash/presentation/day_close_dialog.dart:62-76`). This feature reads and writes no backup files.
**Known data edges:** a shift already open at install time, and any row whose time precedes the day's `opened_at`, stay NULL (FEATURE.md).
