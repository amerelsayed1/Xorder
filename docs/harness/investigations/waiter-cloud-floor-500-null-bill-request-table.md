# waiter-cloud-floor-500-null-bill-request-table — XOrder Waiter (cloud) cannot load the floor when any open bill request has no table

Status: investigated · 2026-11-18 · Confidence: **confirmed mechanism, unproven on the production demo data** · Verified against: xorder-cloud `9aec07d4` on branch `feat/guest-paging-slip-number` (the files involved are not among the uncommitted changes)

## 1. Symptom
- App: XOrder Waiter, cloud flavor (`lib/main_cloud.dart`), release build, real Android phone (POCO 22101320G, Android 14), against the production demo tenant (`demo`, Good Cafe), waiter `sara`.
- Steps: sign in (restaurant `demo`, name `sara`, PIN) → app lands on **Tables**.
- Expected: the list of active tables with their state (free / open / bill asked).
- Actual: red banner "xorder.io could not do that. Try again." and no tables. Pull-to-refresh repeats it. Sign-in itself succeeds (header shows the waiter's name).

## 2. How it was reproduced
Throwaway PHPUnit file (scratchpad, not in the repo): `/private/tmp/claude-501/-Users-amerelsayed--claude-spares-spare-vfHrxq/aef21210-62a1-4270-9582-ec70342ef34d/scratchpad/FloorRepro/FloorReproTest.php`, in-memory SQLite, same seed pattern as `tests/Feature/Pos/WaiterWireTest.php` (tenant, branch, area, one table, waiter with PIN, shift started).

```
php artisan test <that file>     (throwaway APP_KEY / JWT_SECRET env vars)
```

| Case | `GET /api/pos/waiter/alpha/v1/floor` |
|---|---|
| no bill request (control) | 200, table `state: free` |
| open bill request for the table | 200, `state: bill_asked` |
| completed bill request, `table_id` null | 200 |
| **open (REQUESTED) bill request, `table_id` null** | **500** `{"message":"Server Error"}` |
| **open bill request, then its table deleted** (`$table->delete()`) | **500**; the bill's `table_id` printed as `NULL` after the delete |

The 500 is `ErrorException: array_flip(): Can only flip string and integer values, entry skipped` at `vendor/laravel/framework/src/Illuminate/Collections/Collection.php:465`, called from `app/Services/WaiterCheckService.php:64`.

## 3. Root cause
`WaiterCheckService::floor()` builds the set of tables that asked for the bill:

```php
// app/Services/WaiterCheckService.php:61-64
$asked = BillRequest::query()
    ->whereIn('status', [open statuses])
    ->pluck('table_id')->flip();
```

- **Cause:** `bill_requests.table_id` is nullable (`database/migrations/2026_07_20_000200_create_bill_requests_table.php:16`, `nullOnDelete`). If any open bill request of the tenant has `table_id = NULL`, `pluck` yields a `null`; `Collection::flip()` calls PHP `array_flip`, which raises an `E_WARNING` for a null value; Laravel's `HandleExceptions` converts every warning into `ErrorException`, so the whole `floor` request fails with HTTP 500. One bad row hides every table.
- **How the row appears (confirmed in schema and code):** `DiningTable` has no `SoftDeletes`, so `$table->delete()` hard-deletes and the FK sets `bill_requests.table_id` to NULL for its requests. `Dashboard\TableController::destroy` (line 301) refuses only when the table has **orders**; a table whose only history is a bill request ("call the waiter / ask for the bill") can be deleted. Bulk delete follows the same rule. A second possible source, a menu session with no table (`resolveSession` tolerates `$session->table === null`, line 146), is **unproven**.
- **Symptom path on the phone:** the 500 body has no `code`, so the client maps it to `WaiterError.unavailable` (`packages/xorder_waiter_link/lib/src/client.dart`, `code = ... : WaiterError.unavailable`), which `strings.dart:132` renders with the catch-all `tillProblem` text. The same text is used for any unmapped failure, so the banner hides the real cause.
- **Contributing conditions:** (a) no test builds a bill request without a table; (b) the app's catch-all message gives the waiter no retry button, no detail and no way forward.

## 4. Evidence and alternatives ruled out
- Reproduced with a 500 and a stack trace pointing at `WaiterCheckService.php:64` (section 2); three control cases stay 200, so the null-table row is what triggers it, not the bill-request feature in general.
- Dashboard table board has the same `pluck('table_id')->flip()` shape (`TableController.php:106`) but its query is `whereIn('table_id', $tableIds)`, which excludes NULL: **not affected**.
- `SHIFT_REQUIRED` (403) is handled by the app with its own message and `state.dart:331`; codes match on both sides: **ruled out**.
- Auth/device/session middleware: sign-in and the shift gate passed (the app reached Tables): **ruled out**.
- The full cloud suite passes (1332), so this is data-dependent, not a regression from a code change.
- **Not checked:** the production data. Per the investigation rules the live site and production DB were not used. Whether the demo tenant actually holds an open bill request with no table is therefore **unproven**; the 500 and the banner match, but another 500 inside `floor()` (e.g. `Branch::findOrFail($table->branch_id)` at line 544 for a table with an open check and a null/foreign branch) is not excluded.

## 5. Impact
- **Waiter app (cloud):** every device of the affected tenant loses the floor, check and ops entry point until the row is closed or removed. Café/counter models that use no tables are unaffected; restaurants with tables and "ask for the bill" are exposed. The longer a stale open request survives, the longer the outage (open statuses: REQUESTED, SEEN, IN_PROGRESS; nothing expires them here).
- **Tenant boundary:** none; the query is tenant-scoped. **Money / order integrity:** none (read endpoint).
- **Cross-app:** the till-over-LAN flavor of the waiter wire is the Dart server in `packages/xorder_waiter_link/lib/src/server.dart`, a separate implementation; not examined here.
- **Data already wrong:** only the bill request rows with a NULL table; read-only count needed on the real database by the owner (not run).

## 6. Fix options
1. **Narrowest (recommended):** in `WaiterCheckService::floor()` drop null table ids before flipping: `->whereNotNull('table_id')->pluck('table_id')->flip()` (or `->filter()`/`->reject(null)`). No contract, schema or response change.
2. Same fix plus: when a table is deleted, cancel or detach its open bill requests (`TableController::destroy` and `bulkDestroy`), so the dashboard bill board does not keep an orphan. Slightly wider, behaviour change in the dashboard; needs a product decision on what to do with the request.
3. Client side, independent of the cause: show the real status/reason on the Tables screen error and add a retry button, so a server fault is diagnosable by the waiter (`apps/xorder_pos_waiter/lib/screens/floor_screen.dart`, `strings.dart`).
Must not change: the wire contract (`floor` response shape, error codes), tenant scoping, `bill_requests` schema (no migration is needed).

## 7. Tests the fix needs
- Regression in `apps/xorder-cloud/apps/api/tests/Feature/Pos/WaiterWireTest.php`: (a) floor with an open bill request that has `table_id` NULL → 200 and the real table is not marked `bill_asked`; (b) floor after deleting a table that had an open bill request → 200; (c) floor with an open bill request for the table → `state: bill_asked` (no existing coverage found for `bill_asked`).
- Run: `php artisan test --filter WaiterWireTest`, `--filter WaiterShiftTest`, then the full suite.
- If option 2: a dashboard feature test for table deletion with an open bill request (also cross-tenant 404 rules unchanged).
- If option 3: a Flutter widget test for the error state and the retry control (`apps/xorder-pos/apps/xorder_pos_waiter/test`).

## 8. Approvals the fix needs
- None for the narrow fix beyond normal review. It reaches `xorder-cloud` `main`, which auto-deploys to production: only with the user's explicit approval after `/release-check`. No migration. Option 2 changes dashboard behaviour (product decision).

## 9. Open questions and what could not be verified
- Does the production demo tenant really hold an open bill request with no table? To confirm without touching code: in the demo dashboard's bill-requests board, look for an open request showing no table; or the owner can run a **read-only** `select id, status, table_id, created_at from bill_requests where restaurant_id = <demo> and table_id is null and status in ('REQUESTED','SEEN','IN_PROGRESS')`. Closing that request from the dashboard should make the floor load; that would confirm the cause. (Nothing was changed on production.)
- The exact HTTP status/body the phone received was not captured (release build, no network log, no server log access). A debug build or the server's `laravel.log` would show it.
- Whether a menu session without a table can create a bill request (second source of NULL) is unproven.
- Docs: `docs/FEATURE_INVENTORY.md` row `waiter-app` says "no cloud routes", but cloud routes `pos/waiter/{slug}/v1/*` exist (POS-BE-033, `routes/api.php:914`); the row is stale. No FEATURE docs exist for the cloud waiter wire.

## Commands run
- `git rev-parse`, `git log`, `git status`, source reads (listed above).
- `php artisan test <scratchpad FloorReproTest.php>` (4 tests: 3 passed, 1 failed with the 500 above) and `--filter test_deleting` (failed with the 500). Output quoted in sections 2 and 4. No repo file was changed.
