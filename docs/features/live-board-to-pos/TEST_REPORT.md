# Test report — live-board-to-pos

2026-11-10 · xorder-cloud working tree on `main` base `1ae5fd8`, **uncommitted** · SQLite `:memory:` · `APP_KEY` throwaway

| Command (from `apps/xorder-cloud/apps/api`) | Result |
|---|---|
| `php artisan test --filter 'WhatsappPendingOrderTest\|OrderingModeTest'` (first run, before fixture fix) | 8 of 17 failed (test fixture used a restaurant with no ordering entitlement; fixed) |
| `php artisan test --filter WhatsappPendingOrderTest` | 13/13 passed |
| `php artisan test --filter 'StaleLiveView\|CapabilityVerbs'` | 19/19 passed (2026-11-16; full cloud suite 1299/1299) |
| `php -d memory_limit=-1 vendor/bin/phpunit` (full suite, 1st run after stage A) | 2 failed: `OrderingModeReconciliationTest::test_order_pipeline_honours_the_coerced_mode`, `PlanEntitlementTest::test_orders_route_requires_system_ordering` (both asserted the old rule; updated) |
| same, after stage D | 1 failed: the reconciliation test again (my later "WhatsApp order needs a phone" rule; fixture given a phone) |
| same, after the review fixes (pulse, insights, audit log, generic-route refusal, old migration constants) | **1277 passed**, 6606 assertions, 0 failed |
| `cd apps/xorder-cloud && pnpm build` | built (menu, landing, web; chunk-size warning only) |
| **After merging `origin/main` (`dd1a6c6`)**: `php -d memory_limit=-1 vendor/bin/phpunit` | **1298 passed**, 6782 assertions, 0 failed (includes upstream's new tests) |
| same tree: `pnpm build` | exit 0, 3 of 3 tasks successful |

## Criteria → proof

| Criterion | Proof | Status |
|---|---|---|
| AC-6 pending order exists, listed, accept makes it real, never kitchen/sales | `WhatsappPendingOrderTest` (checkout PENDING, list/summary/new-count/stats, accept idempotent, reject with reason, cross decisions refused, no move back to PENDING, tenant 404, `orders.update` needed, plan gate, paused restaurant, phone required) | proven on SQLite |
| BR-3 pending not a sale | stats `orders_today` and insights `orders_total` 0 → 1 after accept; pulse counts pending for a WhatsApp-only plan | proven for stats, insights, pulse; `ReportService` and the pickup board edited, **no direct test** (gap) |
| AC-5 restaurants without a POS keep an order queue | `PlanEntitlementTest::test_orders_route_requires_an_ordering_feature` (WhatsApp-only plan reaches it) | proven |
| D9/D11 `live.view` removed, no mapping | `CapabilityVerbsTest` (each read needs its own view; stale value grants nothing), `StaleLiveViewCapabilityTest` (removed value ignored, other capabilities keep working, stored row never rewritten) | proven |
| AC-1, AC-7 nav/redirect/bell/RTL | `pnpm build`; then seen in the built-in browser (2026-11-10, below) | orders page, nav and redirect seen; menu checkout and bell link not seen |
| AC-2 dashboard refuses table/bill/visit routes | **not done** (see TECHNICAL.md section 7) | open |
| AC-3 delivery in both places, AC-4 POS handles tables | depend on `pos-incoming-cloud-orders` and the POS consumer | open |

## Not proven
- `lockForUpdate` on accept/reject (no-op on SQLite; the race is serial in tests); PostgreSQL migration and lock behavior never run.
- The menu SPA checkout, the Accept/Reject/WhatsApp buttons, Arabic/RTL: built, never opened.
- The `wa.me` message opening for Arabic text and international numbers.
- No Vue test framework exists; none added.

## Seen in a browser (2026-11-10)

Vite dev server `web` (port 5180, main checkout on branch `feat/live-board-to-pos`), `demo.localhost:5180`, **API replaced by a browser-side XHR stub** (no real API or database involved), so this shows the screens, not the server. Stub orders: two WhatsApp PENDING, two NEW.

- `/admin/orders` in Arabic (RTL) and English: Pending tab with count, "Pending" badge, **Accept** and a reject icon on pending rows; normal NEW rows keep "Received".
- Accept on ORD-101 sent `POST /api/dashboard/orders/101/accept`, the row became New and a "Message on WhatsApp" button appeared; its link is `https://wa.me/201234567890?text=...` (Arabic text, `target=_blank`, `rel=noopener`).
- Reject on ORD-102 opened the reject dialog (title, optional reason, confirm), sent `POST .../reject`, the row became Cancelled with a "sorry, could not accept" WhatsApp link.
- `/admin/live` redirects to `/admin`; the sidebar has no Live link and still has upstream's Plan and Waiter shifts.
- Tab title count moves with new + pending orders (it lags by one 10-second pulse).
- Console: the only errors were from the stub (an unstubbed endpoint returned 502; the home page expected a list where the stub returned an object). No error from the changed pages.

### Menu checkout (2026-11-11)

Menu dev server (port 5175, branch `feat/live-board-to-pos`), `demo.localhost:5175`, a throwaway mock API on port 8100 serving a real menu payload (captured from a test-database factory) and mimicking the order endpoint. No real API or database.

- WhatsApp-only menu loads; added a burger, opened the cart, continued to details: the submit button reads "Send order" and the note says the order reaches the restaurant directly (no "order via WhatsApp" wording, so the cart-drawer fix works). The phone field is marked required.
- Submitted: exactly one `POST .../orders` with name, phone, pickup, items and total 120. The dialog says "Your order was sent", shows the order reference, and "Waiting for the restaurant to confirm. They will message you on WhatsApp at your number once they accept it." There is no re-open WhatsApp link, and no WhatsApp tab opened.
- Observed, existing behavior and not from this change: after a failed first load, the menu's Retry button does not recover even when the API answers (the error flag is never cleared), so a reload is needed.

**Not seen:** the English wording of the dialog; the server's "phone required" 422 shown in the menu (the form blocks it first); the bell link for bill requests; `wa.me` opening in WhatsApp itself; any real API response.
