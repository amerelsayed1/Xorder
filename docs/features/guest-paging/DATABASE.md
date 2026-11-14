# Guest paging — database

Status: S1 as built 2026-11-02; **written, not run on any non-test database**. Cloud tests run on SQLite `:memory:`; PostgreSQL behaviour reviewed by reading only.

## Migration `2026_11_02_000100_add_guest_paging_to_orders_table.php`

### `orders` (additive, all nullable, no defaults, no backfill)

| Column | Type | Written by | Meaning |
|---|---|---|---|
| `pickup_token` | varchar(40), **unique** | S2 `PublicOrderController::store`; S5 `PosOrderService` (as sent by the till) | opaque public key; null = not a paged order |
| `pickup_status` | varchar(12) | `GuestPagingService` | `PREPARING` / `READY` / `PICKED_UP` (`App\Enums\PickupStatus`) |
| `pickup_display_ref` | varchar(40) | intake paths | the number shown to the diner (receipt number, or `ORD-{id}`) |
| `pickup_followed_at` | timestamp | S2 public `follow` | first time the tracking page opened |
| `ready_at` | timestamp | service (READY) | set once; prep-time reports use `ready_at - created_at` |
| `ready_by` | FK `users`, null on delete | service | dashboard user; null when the till pressed Ready |
| `ready_source` | varchar(10) | service | `pos` / `dashboard` |
| `acknowledged_at` | timestamp | S2 public `ack` | diner tapped "On my way" |
| `picked_up_at` | timestamp | service (PICKED_UP) | set once |
| `pickup_push_token` | varchar(512) | S8 | diner's FCM token, nulled when FCM reports it dead |

No index on `pickup_status` on purpose: the board filters it with `!=` inside an `OR`, which no btree can use; the existing `(restaurant_id, created_at)` index serves the board's "today, this tenant, oldest first" query and its sort. The unique index on `pickup_token` is load-bearing: `generateToken()` checks collisions across every tenant because the public URL carries no slug.

### `restaurants`

| Column | Type | Meaning |
|---|---|---|
| `guest_paging_order_types` | json, nullable | order types that get a tracking QR/link; null = `['takeaway','pickup','drive_thru']` (`GuestPagingService::DEFAULT_ORDER_TYPES`) |

### PostgreSQL review (by reading; `database-reviewer` pass 2026-11-02, no blockers)
- Laravel runs the whole `up()` in one transaction, so `orders` is under `ACCESS EXCLUSIVE` from the first `ADD COLUMN` until `COMMIT`, and that request queues behind any in-flight order transaction (`lockForUpdate` in `PosOrderService` / `GuestPagingService`). No `lock_timeout` is configured anywhere in the project (pre-existing gap; note it in `/release-check`).
- Nullable `ADD COLUMN` without default: catalog-only, no rewrite.
- `pickup_token` unique **constraint**: one btree build over every row (btree indexes NULLs, so "all-null" is a full scan, not instant). Multiple NULLs never collide on PostgreSQL (`NULLS DISTINCT` default) or SQLite.
- FK `ready_by → users` with `ON DELETE SET NULL`: validation scans `orders` once (all null, no lookups), `SHARE ROW EXCLUSIVE` on `users` until commit (reads keep working).
- Net: two scans of `orders` under an exclusive lock. Fine at current sizes (row count UNVERIFIED, no production access); the shipped precedent `2026_09_02_000600` had the same shape.
- `down()` names resolve (`orders_ready_by_foreign`, `orders_pickup_token_unique`) and the order is right; it is unexercised by any test (rollback is forbidden on real databases).
- `json()` not `jsonb()`: the codebase convention (28 `json(`, 0 `jsonb(`); the column is read only through the `array` cast.

### Invariants
- `OrderStatus` (`NEW|COMPLETED|CANCELLED`) is untouched (contract decision, `BACKEND_TO_POS.md` §010).
- `pickup_status` only moves forward; each timestamp is written at most once (`GuestPagingService::transition` under `lockForUpdate`).
- `restaurant_id` is never read from input; the board and the pickup endpoint go through `RestaurantScope`.
