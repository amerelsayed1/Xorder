# Branch order number — database (xorder-pos, migration 63)
Status: implemented, **not applied to any real database** · 2026-10-28 · Source `lib/data/postgres/migrations.dart` (migration 63), `local_bootstrap.dart` (grant), `bin/pos_migrate.dart` (comment). Verified against `xorder-pos` `c67c754` + uncommitted changes (this work, plus one unrelated test file).

| Object | What | Notes |
|---|---|---|
| `pos_order_day_counters` | one row per business day: `business_day_id` (PK, FK `pos_business_days` ON DELETE CASCADE), `last_value integer NOT NULL DEFAULT 0 CHECK (>= 0)` | the lock row: two tills settling at once queue on it |
| `pos_orders.day_order_number` | `integer`, nullable, no default | no table rewrite; old rows stay NULL |
| `pos_stamp_day_order_number()` | trigger function, single-quoted body | sets the number only if `NEW.day_order_number IS NULL AND NEW.business_day_id IS NOT NULL`; upsert `ON CONFLICT (business_day_id) DO UPDATE SET last_value = last_value + 1 RETURNING` |
| `pos_orders_number` | `BEFORE INSERT ON pos_orders FOR EACH ROW` | fires after `pos_orders_business_day` (name order); pinned by a test |
| Till grant | `SELECT, INSERT, UPDATE ON pos_order_day_counters` | no DELETE; no new grant on `pos_orders` (table-wide INSERT; UPDATE stays column-scoped, so the till cannot renumber a sale) |

Rules in the database: invoice numbers and `pos_invoice_sequences` untouched. Orders outside any business day keep NULL. A lost idempotency race (`ON CONFLICT DO NOTHING` on the order) spends one number (a gap), as it already does for the invoice number. Voided orders go through the same trigger.

Review by reading (PostgreSQL behaviour, not proven on a large live table): adding a nullable column without default is catalogue-only; the new table is empty; the trigger adds one index lookup and one row lock per order insert; rollback = drop the trigger, function, column and table (nothing depends on them; old builds ignore them). Rollout: migrate through the new binary first; every till on a branch must be upgraded together (as for every migration).
