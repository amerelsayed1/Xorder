# Test report — dashboard-shift-details (2026-11-09)

Run in `apps/xorder-cloud/.claude/worktrees/shift-details/apps/api` (SQLite in-memory).

| Command | Result |
|---|---|
| `php artisan test --filter DashboardShiftTest` | 8 tests, 8 passed |
| `php -d memory_limit=2G vendor/bin/phpunit` (whole suite) | 1194 tests, 1194 passed, 0 failed, 40.1 s |
| `npx vite build` in `apps/web` | built, no errors |

Notes:
- `php artisan test` for the whole suite exhausted PHP's default 128 MB (`Allowed memory size ... exhausted` while loading `routes/api.php`); `artisan test` spawns PHPUnit without `-d`, so the full run used `vendor/bin/phpunit` with 2 GB. Same tests, different runner.
- Manual check in the built Docker app (`demo.localhost:8080`, Arabic): card opens `/admin/shifts/7`; float 200.00 + 7,748.00 cash = 7,948.00 expected; revoked-till note and Force close button shown; order link opens order BR8-2026-000008's sheet; empty dialog submit shows both field errors and sends nothing.
- Not run: an actual force close in the browser; English locale; dark theme; phone width; concurrent closes on PostgreSQL.

## 2026-11-09 — counted-cash parsing fix
- Reproduced in the Docker app: `4,995.00` with a 1-letter reason showed both field errors (the reason one on purpose, so nothing could be sent).
- Parser check (`node`, scratch script, same code as `ShiftView.vue`): `4995`, `4995.00`, `4,995.00`, `4,995`, `4 995` → 499500; `٤٬٩٩٥٫٥٠` → 499550; `12,50` → 1250; `1,234,567.89` → 123456789; `abc` → NaN (refused).
- After rebuilding the web container: the same input shows only the reason error; `4,995.00` is accepted. Shift 6 left open (no request sent; checked in the nginx log and the database).

## 2026-11-09 — opening date on the card
- Docker app, Arabic: the card for shift 6 reads "عامر السيد · بدأت 26 سبتمبر، 10:55 ص" (read from the page text). Formats checked with `node` for `ar` and `en`. Web build passed. Not checked: a shift opened today (time only) in the browser.
