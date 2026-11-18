# Shared QR, client types the slip number: database (as built)

**No change.** No migration, no new table, no new column. The lookup reads existing columns of `orders` (`restaurant_id`, `channel`, `invoice_number`, `order_type`, `created_at`) and, when it finds an order that has none, writes the existing paging columns `pickup_token`, `pickup_status` and `pickup_display_ref` (added by `2026_11_02_000100_add_guest_paging_to_orders_table.php`).

New optional setting: `GUEST_PAGING_LOOKUP_WINDOW_HOURS` (default 12).

**Query cost (by reading; the suite runs on SQLite):** the lookup selects one restaurant's till orders from the last 12 hours, newest first, capped at 2000 rows, and filters in PHP. Whether the existing indexes on `orders` serve `(restaurant_id, channel, created_at)` well in PostgreSQL production was **not verified**; at a counter's volume the window holds hundreds of rows, not millions.

The earlier PIN design's table (`pager_sessions`, in the closed PR 16) was never merged and does not exist.
