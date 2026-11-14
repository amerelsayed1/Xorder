# Database — pos-incoming-cloud-orders

Migration `2026_11_09_000100_add_incoming_feed_to_orders_and_requests.php` (cloud, additive, **written and applied only on the SQLite test database**; never run on a real database).

| Table | Columns added | Notes |
|---|---|---|
| `branches` | `online_orders_on_pos` bool default false | the per-branch switch (A4); no UI yet |
| `orders` | `accepted_at`, `accepted_by_terminal_id` (nullable FK `pos_terminals`, null on delete), `accept_client_request_id`, `rejected_at`, `reject_reason`, `reject_client_request_id` | accepted is not a status; index `orders_feed_idx (restaurant_id, branch_id, updated_at)` |
| `bill_requests` | `handled_by_terminal_id` (nullable FK), `handled_client_request_id` | index `bill_requests_feed_idx` |
| `pos_terminals` | `last_feed_at` | telemetry, written at most every 20 s |

PostgreSQL (by reading, not run): ADD COLUMN nullable/constant default is metadata-only; the two indexes and the FKs take brief write locks on `orders` and `bill_requests`. See the database review in `TEST_REPORT.md`. `down()` drops indexes, FKs and columns.
