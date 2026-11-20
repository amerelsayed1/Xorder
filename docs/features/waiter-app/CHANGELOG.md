# Changelog — waiter-app

## 2026-11-09 — WA1 built (xorder-pos `development`, uncommitted)
- New app **XOrder Waiter** (`apps/xorder_pos_waiter`, Android/iOS): pair with the till by address + one-time code, sign in with the till PIN, see every table, open a table, add items with options/quantity/notes, change or remove unsent lines, set guests, send a round to the kitchen. Arabic and English. Priced by the till only.
- New package `packages/xorder_waiter_link`: the wire, the handheld's client and the till's server.
- The till (both apps) can serve handhelds: Settings › Waiter devices (turn on, pair, revoke), `terminal.manage`. Off by default.
- POS migration 65: `pos_waiter_devices` (token hashes only), on PostgreSQL and SQLite.
- Known gaps before any pilot: no TLS on the LAN link, token not in the OS keystore, no offline queue, no kitchen dockets, no waiter role/clock-in, no device limit. See TECHNICAL §11.

## 2026-11-09 — POS-BE-033 cloud half built (xorder-cloud `775bf0f` + uncommitted work, not deployed)
- The platform now serves wire v1 at `/api/pos/waiter/{slug}/v1/*` for the cloud flavor: hello, sign-in (registers the device), sign-out, menu, floor, check, ops/send. Migration `2026_11_09_000100` (additive). Dashboard list/revoke of waiter devices (API only; no Vue page yet).
- **Contract amended:** the restaurant is the slug in the path (`https://xorder.io/api/pos/waiter/{slug}`), not a subdomain; the handheld's cloud client and sign-in field follow (`lib/state.dart`, `lib/mode.dart`, `sign_in_screen.dart`).
- Build fix for the handheld: `resValues = true` in `android/app/build.gradle.kts`.

## 2026-11-18 — cloud waiter floor no longer fails on a bill request with no table (xorder-cloud, uncommitted, not deployed)
- Fix: `GET /api/pos/waiter/{slug}/v1/floor` returned HTTP 500 when any open bill request had a NULL `table_id` (for example after its table was deleted), so the waiter app showed "xorder.io could not do that" and no tables. Such requests are now ignored by the floor.
- Deleting a table (single or bulk) now cancels its open bill requests instead of leaving a request that points at no table. Tables with orders are still not deletable.
- No API shape change, no migration. Root-cause report: `docs/harness/investigations/waiter-cloud-floor-500-null-bill-request-table.md`.
- Deleting a whole dining area (no orders) now also cancels its tables' open bill requests; the logic is shared as `BillRequest::cancelOpenForTables`.
- Known gap: deleting a branch still orphans its tables' open bill requests (the waiter floor is protected; the dashboard bill board is not).
