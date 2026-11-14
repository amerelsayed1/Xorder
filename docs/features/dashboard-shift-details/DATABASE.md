# Database — dashboard-shift-details

Migration `apps/api/database/migrations/2026_11_09_000100_add_closed_via_to_pos_shifts_table.php`:
- `pos_shifts.closed_via` `varchar(16) NULL` — `dashboard` for a force close; NULL = closed at the till (every existing row).
- Additive, nullable, no default, no backfill, no index. On PostgreSQL this is a catalogue-only `ALTER TABLE ... ADD COLUMN` (brief ACCESS EXCLUSIVE lock, no table rewrite). Reviewed by reading; the tests run on SQLite and cannot prove PostgreSQL behaviour.
- `down()` drops the column (guarded by `hasColumn`).
- Applied so far: the SQLite test database, and the local Docker PostgreSQL (`xorder-db-1`) on 2026-11-09 with owner approval. **Not** applied anywhere else; production gets it only through a reviewed release (`/release-check`).

Other columns used as they were: `closed_by_id`, `closed_at`, `counted_cash_minor`, `expected_cash_minor`, `variance_minor`, `variance_reason`, `status`. `close_payload_hash` stays NULL on a dashboard close (there is no till payload).
