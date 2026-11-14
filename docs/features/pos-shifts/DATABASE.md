# Database impact: POS shifts and cash movements

Verified against: 2026-10-20 · cloud `main 06bc8e3` · POS `main d592db8`. Written from migrations. Prefixes: `C:` = `apps/xorder-cloud/apps/api/`, `P:` = `apps/xorder-pos/`.

## Tables and constraints
### Cloud (PostgreSQL in production, SQLite in tests)
Created by `C:database/migrations/2026_09_02_000900_create_pos_shifts_and_cash_movements_tables.php`.
| Table | Notes |
| --- | --- |
| `pos_shifts` | tenant column `restaurant_id` (FK, cascade); unique `(restaurant_id, client_transaction_id)` (line 45); index `(restaurant_id, pos_terminal_id, status)` (line 46) |
| `pos_cash_movements` | tenant `restaurant_id`, also `branch_id` (line 52); unique `(restaurant_id, client_transaction_id)` (line 66); both tables have `created_at`/`updated_at` (`timestamps()`); referenced by `supplier_payments` (`C:app/Models/SupplierPayment.php:35,63`) and listed by `GET /api/dashboard/purchasing/drawer-payouts` (`C:routes/api.php:596`) |
| `orders.pos_shift_id`, `order_payments.pos_shift_id` | FK added to `pos_shifts`, `nullOnDelete` (lines 71-76); `orders.pos_shift_id` is created in `C:database/migrations/2026_09_02_000600_add_pos_columns_to_orders_tables.php:42`; `order_payments.pos_shift_id` is created in `2026_09_02_000700_create_order_payments_table.php:27` (FK added in the shifts migration, line 74); `pos_refunds.pos_shift_id` is in `2026_09_22_000200_create_pos_refunds_tables.php:42` |

| Column (pos_shifts) | Type | Null | Meaning |
| --- | --- | --- | --- |
| `restaurant_id`, `branch_id`, `pos_terminal_id` | FK ids | no | tenant, branch, till (cascade on delete) |
| `client_transaction_id` | uuid | no | till-generated idempotency/identity |
| `opened_by_id`, `closed_by_id` | FK users | yes | nullOnDelete; null when unattributed |
| `opened_at`, `closed_at`, `received_at` | timestamp | closed/received yes | client instants, normalised to the app time zone (`PosShiftService.php:79,121,195`); server observation |
| `opening_float_minor` | unsigned bigint | no, default 0 | minor units |
| `counted_cash_minor`, `expected_cash_minor` | unsigned bigint | yes | set at close |
| `variance_minor` | bigint signed | yes | short is negative |
| `variance_reason` | string | yes | |
| `denominations` | json | yes | |
| `status` | string(10) | no, default `open` | `open` or `closed` |
| `payload_hash`, `close_payload_hash` | char(64) | yes | idempotency hashes |

| Column (pos_cash_movements) | Type | Null |
| --- | --- | --- |
| `pos_shift_id` (FK, cascade), `pos_terminal_id` (nullOnDelete), `acting_user_id` (nullOnDelete) | ids | terminal/user yes |
| `client_transaction_id` | uuid | no |
| `direction` | string(3) `in`/`out` | no |
| `amount_minor` | unsigned bigint | no |
| `reason` (120), `reference` (255) | string | reference yes |
| `occurred_at`, `received_at`, `payload_hash` | timestamp, timestamp, char(64) | received/hash yes |

Cloud `pos_cash_movements` also has `branch_id` (FK, cascade; migration line 52).

### Desktop POS (branch PostgreSQL, `P:lib/data/postgres/migrations.dart`)
Migration 3 "shifts, the drawer count, and the shift a sale belongs to" (line 279).
| Table | Details |
| --- | --- |
| `pos_shifts` (lines 281-322) | `terminal_id uuid`, `opened_by` / `closed_by` → `pos_staff` (RESTRICT), `opened_at timestamptz`, `opening_float_minor`, `closed_at`, `counted_cash_minor`, `expected_cash_minor`, `variance_minor`, `closing_note`; CHECKs: float ≥ 0, counted ≥ 0, and `pos_shifts_closed_is_complete` (all-or-none of the close fields) |
| unique partial index `pos_shifts_one_open_per_terminal` on `(terminal_id) WHERE closed_at IS NULL`; index `pos_shifts_branch_opened_idx (branch_id, opened_at)`; `pos_shifts.restaurant_id`/`branch_id` NOT NULL | lines 281-326; partial unique indexes `(restaurant_id, client_transaction_id)` and `(restaurant_id, close_client_transaction_id)` `WHERE … IS NOT NULL` at `:4335-4346`; also `pos_shifts.business_day_id` (FK RESTRICT, `:1560`), `pos_shifts.opened_with_approval_by` (`:1566`; no reader in `lib`/`bin` (grep); only `P:test/data/business_day_schema_test.dart:434-439` writes and reads it), trigger `pos_shifts_business_day` before insert, current definition re-created with `pos_stamp_business_day('opened_at')` (`:3390-3393`), `pos_orders_shift_idx` (`:330`), `pos_refunds.shift_id` ON DELETE SET NULL (`:1151`) |
| `pos_orders.shift_id` | nullable FK, orders before the migration belong to no shift (lines 329-330) |
| `pos_cash_movements` (lines 1499-1531; also `terminal_id uuid`, `drawer_id` (FK `pos_cash_drawers`, SET NULL), `business_day_id`, `note` and `occurred_at DEFAULT now()`; `pos_shifts.terminal_id` is an FK to `pos_terminals ON DELETE CASCADE` (`:285`); indexes `pos_cash_movements_shift_idx`, `_day_idx` at 1533-1540; `client_transaction_id` column and partial unique index added at `:4347-4352`) | `shift_id NOT NULL` (RESTRICT), `kind IN ('pay_in','pay_out','drawer_open','float_adjust')`, CHECK amount = 0 only for `drawer_open`, `staff_id`, `approved_by_id`, `reason_id` |
| `pos_sync_outbox` | rows `shift_open` / `shift_close` / `cash_movement`, `ON CONFLICT (restaurant_id, client_transaction_id) DO NOTHING` (`P:lib/data/postgres/postgres_shift_repository.dart:576-595`); defined at `P:lib/data/postgres/migrations.dart:4358-4380` (migration 49): `id`, `restaurant_id`, `branch_id`, `event_type`, `source_id`, `client_transaction_id uuid`, `enqueued_at`, `attempts`, `last_attempt_at`, `last_error`, `delivered_at`, `quarantined_at`, `quarantine_code`; event-type CHECK (widened later to include `customer`, `:4453`), `UNIQUE (restaurant_id, client_transaction_id)`, partial pending index |
Columns `client_transaction_id` and `close_client_transaction_id` on `pos_shifts` are read by the drain (`P:lib/data/cloud/outbox_drain.dart:676,726-733`) and are added by `P:lib/data/postgres/migrations.dart:4335-4336` (`ADD COLUMN IF NOT EXISTS`, nullable uuid).

## Relationships
Cloud: `PosShift` belongsTo `PosTerminal`, `User` (opener); hasMany `PosCashMovement`, `Order` (`C:app/Models/PosShift.php:41-60`). `OrderPayment` and `PosRefund` carry `pos_shift_id` (`PosShiftService.php:214,240`).
Shared entity map: cloud `pos_shifts` ↔ POS `pos_shifts`; join identity is `client_transaction_id`; amounts are integer minor units on both sides; times are client-supplied and stored on the cloud as the same instant, normalised to the app time zone; staff ids differ (cloud `users.id` vs POS `pos_staff.id`; the drain sends `acting_user_id` from `opened_by`, `outbox_drain.dart:687`; cloud-bootstrapped POS staff are seeded with the platform user id, `P:lib/data/cloud/bootstrap_seeder.dart:465-486`; locally created staff ids were not traced).

## Shared entities across applications
See the identifier map under Relationships above (join identity `client_transaction_id`; amounts in minor units; staff ids differ).

## Proposed changes
None (as-built documentation).

## Transactions and concurrency
Cloud open runs in `DB::transaction` with `lockForUpdate` on the terminal row (`PosShiftService.php:57-61`); close and cash movement are not wrapped in an explicit transaction in this service. POS open and close use `runTx`; the close update is guarded by `closed_at IS NULL` and the summary is read in the same transaction (`postgres_shift_repository.dart:343-430`).

## Indexes and query performance
Cloud index `(restaurant_id, pos_terminal_id, status)` supports `current()`. `expectedCash()` loads all cash movements of the shift into memory (`PosShiftService.php:261`); bounded by one shift's movements. No index on `pos_shifts(branch_id)` is created in this migration although `resolve()` filters by `branch_id` (`PosShiftService.php:303`); no migration under `database/migrations` that mentions `pos_shifts` (only `2026_09_02_000900` and `2026_09_22_000200` mention `pos_shifts`; `2026_09_13_000300` mentions only `pos_cash_movements`) adds one, so none exists.

## PostgreSQL vs SQLite differences
The cloud locking (`lockForUpdate`, `PosShiftService.php:61`) is not exercised by the SQLite test suite. `resolve()` compares a non-numeric reference with a uuid column (`PosShiftService.php:305-307`); PostgreSQL behavior there is not established (`BEHAVIORAL_ANALYSIS.md` I). The POS partial unique index is PostgreSQL-only and is covered by the integration-tagged tests (`P:test/data/postgres_shift_test.dart:191`), which skip without `POS_PG_HOST`.

## Migration and rollback plan
Existing migration `down()` drops the two foreign keys then both tables (cloud migration lines 79-89). No new migration is proposed.

## Backup/data access constraints
Shift and cash data are financial records. Cloud deletion of a terminal cascades its shifts (`C:app/Services/PosProvisioningService.php:362-419`; the method comment at `:370-375` says "no money history", and the guard at `:393-409` blocks only when a shift of the terminal has `closed_at`, `closed_by_id` or `counted_cash_minor` set or an opening float above 0, or when any order exists for the terminal; it does not look at `pos_cash_movements`, payments or refunds, and `pos_cash_movements.pos_shift_id` cascades on delete (migration `2026_09_02_000900`, line 53); the comment at `:388-392` states the intent (a shift row alone is not money history; what must survive is an order, a float, a counted drawer, a close); tests: `C:tests/Feature/Pos/PosProvisioningTest.php:408` (a closed shift with float and counted cash blocks) and `:447` (an open zero-float shift is deleted with the terminal), `C:tests/Feature/Admin/TenantCreationTest.php:347` (a shift with a float blocks); no test covers the `closed_by_id` condition, the order condition or cash-movement cascade; see `BEHAVIORAL_ANALYSIS.md` M). The POS has backup features (`P:lib/data/backup`); this document did not read any backup content.
