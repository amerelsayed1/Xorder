# Branch order number — technical plan (approved 2026-10-28 and implemented; see FEATURE.md section 14 and TEST_REPORT.md)
Status: implemented, uncommitted · 2026-10-28 · Spec: `FEATURE.md` (decisions of 2026-10-28) · Repo: `xorder-pos` only · Verified against `xorder-pos` `c67c754` (working tree has one unrelated uncommitted file, `test/data/local_bootstrap_test.dart`, which I will not touch or revert) · `xorder-cloud` untouched (12 unrelated uncommitted files there).

## 1. Discrepancies found while re-reading (spec adjusted)
1. The spec said counter per `(branch, business day)`. The business day of an order is chosen **by the database**, not the repository: trigger `pos_stamp_business_day` (latest definition `migrations.dart:3361-3393`, migration 36) fills `business_day_id` BEFORE INSERT from the day whose window contains `occurred_at` for that branch. The number must follow the same day, so it is allocated from `NEW.business_day_id`, not from a separate lookup.
2. Two order writers exist (`submit` `postgres_orders_repository.dart:72`, `voidOrder` `:200`). The team's own rule (comment at `migrations.dart:3253-3262`) is to stamp such a column by trigger rather than at each INSERT. I follow it: one trigger covers both, and any future writer.
3. Offline mode queues nothing for the cloud (`queued` false); cloud mode would send the order. To honour "no cloud change now" the **sync payload is not changed** (spec AC-10 becomes: payload unchanged; pinned by a test).
4. No kitchen print was found, so no kitchen slip change.

## 2. Design
**Schema (migration 63, additive, written not run):**
- `pos_order_day_counters (restaurant_id bigint, branch_id bigint, business_day_id bigint, last_value integer NOT NULL DEFAULT 0, PRIMARY KEY (business_day_id))` with FK to `pos_business_days(id)`. One row per business day.
- `ALTER TABLE pos_orders ADD COLUMN IF NOT EXISTS day_order_number integer` (nullable, no default, no backfill; old orders stay null). Adding a nullable column without default is a catalogue-only change on PostgreSQL 11+ (no table rewrite); the table lock is brief. Reviewed by reading only.
- Function `pos_stamp_day_order_number()` and trigger `pos_orders_number` `BEFORE INSERT ON pos_orders FOR EACH ROW`. PostgreSQL fires BEFORE triggers in name order, so `pos_orders_business_day` (b) runs before `pos_orders_number` (n); a test pins this.
- Body: if `NEW.day_order_number IS NULL AND NEW.business_day_id IS NOT NULL`: `INSERT INTO pos_order_day_counters(...) VALUES (...,1) ON CONFLICT (business_day_id) DO UPDATE SET last_value = pos_order_day_counters.last_value + 1 RETURNING last_value INTO NEW.day_order_number`. The upsert takes the row lock, so two tills settling at once are serialised and get consecutive numbers (BR-7). Single-quoted body, as migration 35/36 (no `$` through Dart).
- No business day → stays NULL (BR-6). Voided orders go through the same trigger, so they keep a number (BR-5). The number is written in the order's own INSERT, i.e. at payment (decision).
- Grants: the trigger runs as the till role, which needs `SELECT, INSERT, UPDATE ON pos_order_day_counters` — add to `local_bootstrap.dart` (next to `:785`) and the `pos_migrate.dart` grant list/comment (`:590-600`); no new grant on `pos_orders` (table-wide INSERT exists, `:682`).
- Gap rule (as for invoice numbers): a lost race on `ON CONFLICT DO NOTHING` spends a number. Replays are found by the existing fast-path SELECT first, so this is rare. Stated in the docs.

**Dart:**
- `SubmitOrderResult` gets `int? dayOrderNumber` (`repositories.dart:470`); both inserts `RETURNING id, invoice_number, day_order_number`; the replay/winner SELECTs also return it.
- `OrderRecord` (`order_record.dart:206`) gets `int? dayOrderNumber`; history `_orderColumns` (`postgres_order_history_repository.dart:77`) and its row mapper add `o.day_order_number`; the fakes (`fake_repositories.dart:788,797,832`) assign a counter so UI tests see a value.
- `ReceiptData` (`receipt_data.dart:124,205`, `:302`) gets the number; `receipt_document.dart:285-310` adds a row labelled "Order no." beside the invoice row. **Note:** the existing label `receiptOrderNumber` is used for the *invoice* string, so a new string `receiptDayOrderNumber` (en/ar) is added rather than reusing it (wording to confirm, see 6).
- History list/detail and reprint (`reprint_dialog.dart`) show it; sale screen shows it after payment (via `ReceiptDialog`, `receipt_dialog.dart:73,282`).
- Not touched: invoice formatting, `_nextInvoiceNumber`, outbox payload, cloud.

## 3. Stages (each ends with its tests; rollback = revert the commit; migration 63 is additive and unused by old builds)
| # | Stage | Files | Tests |
|---|---|---|---|
| 1 | Migration 63 + grants | `migrations.dart`, `local_bootstrap.dart`, `bin/pos_migrate.dart` | new `test/data/day_order_number_test.dart` (PostgreSQL): AC-1, 2, 3 (two connections at once), 4, 6, 7, 9; trigger order; grants via `till_grants_enforced_test` probe role |
| 2 | Return value through the repository | `repositories.dart`, `postgres_orders_repository.dart`, fakes | AC-5 replay returns same number, no extra consumed; `order_lifecycle_test` still green |
| 3 | History + record | `order_record.dart`, `postgres_order_history_repository.dart`, `order_history_screen.dart`, order detail pane | history tests: number shown, null shows "—" |
| 4 | Receipt, reprint, sale screen, strings | `receipt_data.dart`, `receipt_document.dart`, `reprint_dialog.dart`, `app_strings.dart` | receipt document tests en/ar, RTL, null case; payload-unchanged test (AC-10) |
| 5 | Docs | FEATURE/TECHNICAL/DATABASE/TEST_PLAN/TEST_REPORT/CHANGELOG; QA file XORD-036 (ticks only for run tests) | `/project-documentation update` |

Commands: `cd apps/xorder-pos && flutter analyze && flutter test <path>`; PostgreSQL suites need `POS_PG_*` pointing at a **throwaway local** server; `scripts/check.sh` for the full run (drops its test databases at the end). If no local PostgreSQL is available the PostgreSQL tests will be reported **not run**, and the money-adjacent claims stay unproven.

## 4. Impact and risk
- Venue models: café and food truck (pay first, one or several tills on a branch server) gain most; restaurant gets a post-payment number only; cloud kitchen unaffected. **Cloud-mode branches with several tills keep one counter per till** (decided: separate later item).
- Rollout: every till on a branch must run the new build before the migration is applied (same constraint as every migration, see the note at migration 62). Old build + migrated database keeps working (new column nullable, trigger invisible). New build + old database fails on `RETURNING day_order_number`, so migrate first through the new binary, as `pos_migrate` does.
- Money/order integrity: this touches the order write path (trigger on `pos_orders`); totals, tax and payments are not changed.
- PostgreSQL-only behaviour (trigger order, row lock, grants) cannot be proven by the cloud suite and is only proven if the POS PostgreSQL tests are run.

## 5. Approvals needed (nothing is built until you say go)
1. Migration 63 (written, **not applied to any real database**).
2. The order-write-path change (trigger on `pos_orders`).
3. Running PostgreSQL tests against a local throwaway database (`POS_PG_*`): please confirm one is available.
No cloud change, nothing reaches `xorder-cloud` `main`, no commit/push without your say.

## 6. Open points
- Label wording: "Order no." / «رقم الطلب» vs. the invoice row now labelled the same (`receiptOrderNumber`). Suggest relabelling nothing and adding "Order no." for the new one; Arabic wording needs your read.
- Digits on the receipt follow the existing numeric style (to verify in `receipt_document.dart`).
