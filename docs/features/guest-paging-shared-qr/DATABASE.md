# One shared QR for guest paging: database (as built, cloud half)

Migration `apps/xorder-cloud/apps/api/database/migrations/2026_11_18_000100_create_pager_sessions_table.php`. **Written and tested on SQLite; not run on any real database.** Additive: one new table, nothing existing is changed.

`pager_sessions`

| Column | Type | Notes |
|---|---|---|
| `id` | bigint | |
| `restaurant_id` | FK `restaurants`, cascade on delete | tenant column |
| `code` | string(8), **nullable** | the number the client reads out; `NULL` once bound |
| `secret_hash` | string(64), **unique** | sha256 of the phone's secret; the secret itself is never stored |
| `order_id` | FK `orders`, nullable, **unique**, null on delete | set when bound; an order is paired at most once |
| `expires_at` | timestamp | an unclaimed code dies here (default 30 minutes) |
| `bound_at` | timestamp, nullable | |
| `created_at`, `updated_at` | | |

Indexes: unique `(restaurant_id, code)` (an open code is unique inside one restaurant; NULLs do not collide in PostgreSQL or SQLite, so binding frees the number at once), index on `expires_at`.

**PostgreSQL review (by reading; the suite runs on SQLite):** `CREATE TABLE` and indexes on a new empty table, so no table rewrite and no long lock. The foreign keys point at populated tables, but a new table has no rows to check. Rollback is `down()` (drop the table), and nothing else depends on it.

Pruning: `php artisan pager:prune`, scheduled hourly in `routes/console.php`: deletes unclaimed sessions expired for over an hour, and bound sessions older than the order-number page's lifetime (`GUEST_PAGING_TRACKING_TTL_HOURS`, 48). New optional settings (defaults apply): `GUEST_PAGING_PAIRING_CODE_DIGITS` (4), `GUEST_PAGING_PAIRING_TTL_MINUTES` (30).
