# Guest paging — test report

## 2026-11-02 — stage S1 (cloud foundation)

Environment: macOS, PHP 8.3.19, SQLite `:memory:` (`apps/api/phpunit.xml`), working tree of `xorder-cloud` at `775bf0f` plus uncommitted S1 changes plus unrelated uncommitted edits (listed in `FEATURE.md` §10). No real database touched; migration not run outside the test database.

| Command (from `apps/xorder-cloud/apps/api`) | Result |
|---|---|
| `php artisan test --filter=GuestPaging` | passed · 13 tests · 89 assertions · 1.4 s |
| `php artisan test` | **aborted by the environment**: `Allowed memory size of 134217728 bytes exhausted` in an unrelated test (first in `StockAdjustmentsTest`, then `PasswordBroker`); the 128 MB default of this machine's php.ini, not a test failure |
| `php -d memory_limit=1G vendor/bin/phpunit` | passed · 1171 tests · 5808 assertions · 34.2 s |
| `pnpm --filter @xorder/web build` (from `apps/xorder-cloud`) | built in 0.9 s (pre-existing chunk-size warnings only) |

After the review fixes (transaction in `updateStatus`, `auditExclude`, board tiebreaker, cancelled rule, two new tests):

| Command | Result |
|---|---|
| `php artisan test --filter=GuestPaging` | passed · 15 tests · 113 assertions · 1.9 s |
| `php -d memory_limit=1G vendor/bin/phpunit` | passed · 1173 tests · 5832 assertions · 44.8 s |

What the tests prove: AC-1 (dashboard half), AC-4, AC-5 (call-out computation), BR-2 (`isEligible` / `pagedOrderTypes`), BR-8, BR-9 (service clamp), BR-10 (lock path exercised, not contention), D-6 (cancelled → 422), board filters, ETag 304, tenant scoping, capability gating, OrderResource shape (new keys present, neither token exposed).

Not proven: PostgreSQL lock/index behaviour of the migration (reviewed by reading, `DATABASE.md`); the admin forms' new checkbox (build only, not opened in a browser); anything from S2 onwards.

## 2026-11-02 — stage S2 (public tracking + QR-menu token)

Same environment. After adding `PublicOrderTrackingController`, token issuance in `PublicOrderController::store`, `Restaurant::trackingUrl()`, the public route group and nine S2 tests (two S1 fixtures changed to `dine_in` orders because a `pickup` order is now paged by design):

| Command | Result |
|---|---|
| `php artisan test --filter=GuestPaging` | passed · 24 tests · 200 assertions · 2.4 s |
| `php -d memory_limit=1G vendor/bin/phpunit` | passed · 1182 tests · 5919 assertions · 44.0 s |

Proves: AC-2 (token only with flag + paged type, `tracking_url` = `Restaurant::trackingUrl`, widened types, no token for a seated-table round), AC-3 (exact payload keys, nothing private, 404 unknown/malformed/expired, 403 when the flag is off, ETag 304, cancellation visible), BR-5 partially (404 before sync is the same 404; the "registering" UX is S3), BR-7 (`follow`/`ack` stamp once, `ack` 422 unless READY, `call_out` clears), push-token store/delete and non-echo, `X-Locale` localisation.

After the security review (distinct throttle buckets, cancelled-order ack refusal, `platform` dropped, logo rewrite, four new tests):

| Command | Result |
|---|---|
| `php artisan test --filter=GuestPaging` | passed · 28 tests · 255 assertions · 2.8 s |
| `php -d memory_limit=1G vendor/bin/phpunit` | passed · 1186 tests · 5974 assertions · 44.0 s |

Adds proof for: 30 polls then `follow`/`ack`/`push-token` still succeed (bucket separation), `ack` 422 on a cancelled order that was READY, writes 404 after the TTL and 403 on a SUSPENDED restaurant, both tokens listed in `Order::auditExcludedAttributes()`, `?lang=ar`, and the `ORD-{id}` fallback on the real intake-issued token.

Not proven: the limit numbers themselves beyond the 20-write bucket, HEAD requests, PostgreSQL behaviour, web-server access logs.

## S3 — the order-number page (2026-11-18)
Branch `feat/guest-paging-s3`, uncommitted. Environment: local machine, PHPUnit on SQLite in-memory with throwaway `APP_KEY` and `JWT_SECRET`; no production access.

| Command | Result |
|---|---|
| `php artisan test tests/Feature/MenuShellTest.php` | 13 passed (includes the new `test_order_tracking_links_are_not_indexable_but_the_menu_is`) |
| `php artisan test` (full suite) | **1320 passed**, 6944 assertions |
| `./vendor/bin/pint --test` | passed |
| `pnpm --filter ./apps/menu build` | built; tracking page is a separate 5.64 kB chunk |

**Checked by running the built app against a local mock of the tracking API** (mobile viewport, in the browser pane): preparing, ready (card in the brand colour, "I'm on my way" button), ready with call-out, picked up, cancelled, not found, reconnecting after a server error and recovery, the status flipping from preparing to ready by itself within one poll, "I'm on my way" accepted, the Arabic right-to-left layout, polls sending `If-None-Match`, and `follow` sent once per load. No console errors.

**Not verified:** a real phone (sound and vibration; iOS ignores vibration), the page against the live API (the live demo restaurant's order was cancelled earlier and the page is not deployed), the 403 "not available" screen visually, an amber brand colour on the page, and the mock stood in for the server's real responses, so a mismatch between the mock and the real payload is possible (the real shape was read from the live endpoint on 2026-11-18).
There is no JavaScript test framework in the repo, so none of the front-end behaviour has an automated test.
