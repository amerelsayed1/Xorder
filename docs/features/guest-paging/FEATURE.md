# Guest paging — guest-paging

Status: proposed · 2026-11-02 · Source: the user's request ("https://pingloy.com/en — I want to check how to add this feature into Xorder", followed by four decisions recorded in §13) · Verified against: xorder-cloud `775bf0f`, xorder-pos `c67c754` (both working trees carry unrelated uncommitted changes; listed in §10).

Paths are relative to `apps/xorder-cloud/` (cloud) and `apps/xorder-pos/` (POS). Line numbers were read on 2026-11-02 and may shift.

## 1. Summary

Replace the restaurant pager with the diner's own phone, the way Pingloy does it. The till prints a second QR code on the receipt (and QR-menu orders get a tracking link); the diner opens a public order-tracking page that shows only the order number and its state; when staff mark the order **Ready** on the POS or on a new dashboard pickup board, the page rings and vibrates (and sends a web push where the browser allows it); the diner taps **On my way**; after pickup the diner is asked to rate the restaurant on Google; the owner gets prep-time reports. No app, no phone number, no account.

## 2. Why

In a café, food truck or quick-service counter the diner pays first and then waits. Today Xorder has no way to tell them the order is ready: the cashier shouts the number, or the venue buys a pager kit (Pingloy quotes roughly SAR 500–1,600 per kit). The POS has a `READY` status in its enum that nothing writes (`lib/domain/models/order_record.dart:28-55`), and the cloud has no ready or prepared timestamp at all, so neither the diner nor the owner can see how long an order took.

Venue models (domain handbook §2, §6): **café** and **food truck** gain the most (counter, pay first, diner waits nearby). **Quick-service restaurant** with counter pickup gains as well. **Full-service restaurant**: dine-in orders are served to the table, so they are excluded by default. **Cloud kitchen**: delivery only, not applicable; a kitchen with a pickup window can opt in. The feature assumes a counter and the diner's own phone; it does not assume a table, an address, or a stable network (the till prints the QR before the sale reaches the cloud).

## 3. Goal and success

- A diner who scans the receipt QR within seconds of paying sees their order number and "being prepared", and is alerted on the phone the moment staff mark it ready, without installing anything.
- Staff can mark Ready and Picked up from the till's order detail pane and from a tablet on the dashboard, and the two never disagree about the final state.
- The owner sees average prep time, prep time by hour and the busiest hour per branch and per day.
- Success is proven by the acceptance criteria in §8 and the end-to-end run in §12.

## 4. Users, roles and permissions

| Who | Does | Permission (existing identifiers) |
|---|---|---|
| Diner (anonymous) | Opens the tracking page, taps "Notify me", "On my way", opens the Google review link | none; possession of the receipt token |
| Cashier / counter staff on the POS | Marks Ready / Picked up on the order detail pane | POS session as today; no new POS permission (UNVERIFIED whether the pane's existing Refund action is role-gated and whether Ready should follow it — open question OQ-3) |
| Counter staff on the dashboard board | Views the board, marks Ready / Picked up | `orders.read` (= `orders.view` OR `live.view`, `app/Providers/AppServiceProvider.php:161`) to view; `orders.update` to act, same as `PATCH dashboard/orders/{order}/status` (`routes/api.php:459-460`) |
| Restaurant admin | Sets the Google review URL, thank-you texts and which order types are paged | `settings.update` on `PUT dashboard/restaurant` (`routes/api.php:334-339`) |
| Owner / analyst | Prep-time reports | `reports.view` + feature `product_analytics`, same group as `reports/dining-areas` (`routes/api.php:549-553`) |
| Super admin | Turns the `guest_paging` feature on per plan or per restaurant | existing plan / restaurant feature forms |

No permission is narrowed. No new `TenantCapability` is added.

## 5. Today

**Cloud**
- Order status is `NEW | COMPLETED | CANCELLED` (`app/Enums/OrderStatus.php`, `canTransitionTo` L26-36). A recorded final decision says the enum "does not grow" (`docs/coordination/BACKEND_TO_POS.md:847-853`). POS sales auto-complete when paid (`app/Services/PosOrderService.php:372-376`).
- No `ready_at`, `prepared_at` or pickup state anywhere in `app/`, `database/`, `routes/`. The closest pattern is `BillRequest` (`app/Models/BillRequest.php:50-53` 40-char `public_token`; `seen_at/started_at/completed_at` set in `Dashboard/BillRequestController.php:69-89`; public routes `routes/api.php:896-899`; polled every 8 s from `apps/menu/src/components/BillRequestButton.vue:72`).
- The only public order status endpoint, `GET public/restaurants/{slug}/orders/{id}/status` (`routes/api.php:876-877`, `Public/PublicOrderController.php:199-218`), is keyed by the sequential id, returns only `status`, and is enumerable. It is not reused for the tracking page.
- No websockets or broadcasting; the dashboard polls (`apps/web/src/stores/realtime.js` → `dashboard/pulse` every 10 s with ETag, `PulseController.php:28-62`).
- Web push exists for **staff only**: `app/Services/PushService.php::toRestaurant` (FCM multicast to `device_tokens`, which require a `user_id`), registered through `POST/DELETE dashboard/push/token`. `apps/menu` has no service worker, manifest or `firebase` dependency (`apps/menu/package.json`, `apps/menu/vite.config.js` base `/menu/`).
- `restaurants.review_public_url`, `review_thank_you_ar/en` exist (migration `2026_07_20_000500`) and are read by `Http/Resources/Public/RestaurantPublicResource.php:76` and `PublicReviewController.php:140`, but **nothing writes them** (no request rule, no dashboard field).
- `apps/menu` has no router; `App.vue` switches on `view` (`'menu' | 'branches'`, `useMenu.js:11,105,110`; `App.vue:447,483`). Slug = subdomain (`App.vue:48-50`); table token parsed from the path in `useTableSession.js:20`. `routes/web.php:17-18` serves `/menu/{path?}`, so `/menu/o/{token}` already reaches the SPA. After checkout `App.vue:357-364` stores the order and `useReviewPrompt.js` later shows `ReviewPromptModal.vue` with `public_review_url` once the order is COMPLETED.
- Feature flags: `app/Enums/Feature.php` (cases incl. `pos`, `purchasing`; `requires()` L67-77, `defaultSet()` L87-96), `restaurant_features` table, `plans.feature_keys`, middleware `feature:<key>` (`EnsureFeatureEnabled`), public exposure of `internal_reviews` at `RestaurantPublicResource.php:75`.
- Reports: `app/Services/ReportService.php` aggregates in PHP in the restaurant timezone; `billTimings()` (~L518-540) is the timing template.
- `GET /api/pos/bootstrap` returns `restaurant.{id,name,name_ar,slug,…}` (`app/Services/PosBootstrapService.php:69-86`) and **no public menu URL**; `Restaurant::publicUrl()` (`app/Models/Restaurant.php:269-286`) builds it from `config/platform.php` (`MENU_DOMAIN`, `MENU_SECURE`, `MENU_PORT`), which the till cannot know.
- POS intake: `Http/Requests/Pos/StorePosOrderRequest.php:25-76` (no status, no token); `PosOrderService::orderPayloadHash` (L537-559) hashes money fields only, so new optional fields do not break idempotent replays; `resolveOrder` (L417) accepts an id or a client uuid. `POST /api/pos/sync` (POS-BE-021) is **not implemented**; each `pos_sync_outbox` event type has its own endpoint.

**POS**
- `OrderStatus` enum has `ready('READY')` but nothing writes DRAFT/OPEN/SENT_TO_KITCHEN/READY/CLOSED; `pos_orders` rows are inserted only at settlement as `PAID` (`lib/data/postgres/postgres_orders_repository.dart:72-197`), voided sales as `VOIDED`, and a refund trigger is the only UPDATE of status. Unpaid tickets live as JSON in `pos_parked_tickets`. No KDS, no "ready" button, no order board (routes `lib/app/router.dart:22-31`).
- Receipt pipeline `lib/features/receipt/`: `ReceiptData.etaQrPayload` (`receipt_data.dart:108-117`) is the only QR slot, rendered by `receipt_document.dart:488-493`, `receipt_paper.dart`, `receipt_raster.dart:776-797` with `qr ^3.0.2` (`receipt_qr.dart`), and **never set in `lib/`** (only in tests). The slip prints `invoiceNumber` only (`receipt_document.dart:290-305`), format `PREFIX-YEAR-000001` (`postgres_orders_repository.dart:454-463`); the cloud assigns its own `invoice_number`, kept as `server_invoice_number`. The order uuid is not printed.
- Sync: the paid sale is enqueued in `pos_outbox` in the same transaction (`_enqueueForSync`, L345-367) and sent by `OutboxDrain.buildOrderRequest` (`lib/data/cloud/outbox_drain.dart:166-206`); other events use `pos_sync_outbox` (migration 49, `lib/data/postgres/migrations.dart:4358-4385`; CHECK `pos_sync_outbox_event_known` widened once at L4451-4453) with one builder per type (`_lifecycleEvent` L642-665; `_refundEvent` L898-949 waits until the sale is delivered). Device token Bearer + `Idempotency-Key` (`cloud_api.dart:263-273`). Drain cadence: 4 h idle, 30 min on retry, 2 s nudge on a new row.
- Till DB role may UPDATE only listed `pos_orders` columns (`lib/data/postgres/local_bootstrap.dart:689`). Settings: `pos_settings` key/value with `SettingKey` constants and policy objects (`lib/domain/models/pos_settings.dart:65-87,145`; providers `lib/app/providers.dart:506-547`). `BootstrapBundle` has no settings/features block (`bootstrap_bundle.dart:690-760`); POS-BE-025's features block is approved but unbuilt.
- Orders screen `lib/features/history/presentation/order_history_screen.dart` → `OrderHistoryRepository.search` (filters `from/to`, `statuses`, `orderTypes`, `order_record.dart:446-486`); detail pane `_actions` footer at `order_detail_pane.dart:143` hosts Reprint and Refund. `pos_orders.order_type` exists (migration 1 L53).

**Missing**: everything in §6 "In". **UNVERIFIED**: whether `useMenu` auto-fetches the menu on setup (the tracking view must tolerate it); whether the dashboard router guard admits `live.view`-only users to a route whose meta says `orders.view` (mirror `dashboard.orders`); whether the live `pos_sync_outbox` CHECK already lists `'customer'` (L4451-4453 suggests yes; the new migration repeats the drop/add pattern regardless).

**Documentation drift found**: `docs/qa/XORDER_QA_FINDINGS.md` XORD-036 and `docs/features/shift-order-number/FEATURE.md` §14 record a shared daily order number as "implemented 2026-10-28, uncommitted, migration 63 not applied", but **no such code is in the POS tree** (no `day_order_number` / `dayOrderNumber` in `lib/` or `test/`, latest migration is 62 at `migrations.dart:4768`, the uncommitted files are unrelated). The receipt still prints the yearly invoice number. This feature therefore sends the printed number explicitly as `receipt_number` and does not depend on XORD-036. `docs/FEATURE_INVENTORY.md` has no row for paging, kitchen or order tracking; `apps/menu` was never scanned (inventory L255).

## 6. Scope

**In**
1. Cloud pickup state on `orders` (separate from `OrderStatus`), feature flag `guest_paging`, a `GuestPagingService` that owns every transition.
2. Public tracking page in `apps/menu` at `/menu/o/{token}`: order number + state + restaurant branding only; polling with sound, vibration and a wake lock after a user gesture; "On my way"; cancelled and picked-up states; Google review prompt after pickup.
3. Web push to the diner through FCM where the browser allows it (service worker + manifest in `apps/menu`; iPhone requires "Add to Home Screen"). The open page is the guaranteed path.
4. Dashboard pickup board (Preparing / Following on phone / Ready / Picked up) with a "Call it out" badge after N minutes without acknowledgement; Ready and Picked up actions.
5. Dashboard profile fields for `review_public_url`, `review_thank_you_ar/en` and the paged order types.
6. POS: token generated at settlement, stored on `pos_orders`, printed as a second QR (`{menu_url}o/{token}`), sent with the sale; Ready / Picked up on the order detail pane; a new `order_pickup` sync event; `paging.*` settings; bootstrap `menu_url` and `features.guest_paging` seeded into settings.
7. Contract item **POS-BE-034** (PROPOSED): sale fields `pickup_token`, `receipt_number`; endpoint `POST /api/pos/orders/{order}/pickup`; bootstrap additions.
8. Prep-time report (`reports/prep-times`) and its dashboard page.
9. Docs: this folder's seven files, inventory row, QA entry for the XORD-036 drift if the owner confirms it.

**Out**
- Any new value in the cloud `OrderStatus` enum (owner decision, 2026-11-02).
- SMS, WhatsApp or e-mail alerts; asking the diner for a phone number or account.
- A kitchen display (KDS remains the SRS non-goal, `docs/domain/FOOD_SERVICE_DOMAIN.md:43`); kitchen docket printing; per-line or per-round readiness.
- A POS order board screen (the POS gets buttons on the existing detail pane only; the board is the dashboard's).
- Pingloy's AI assistant, waiting screen with voice, custom banners, and a bulk-drain endpoint (POS-BE-021).
- Delivery / rider tracking; `delivery` orders are never paged by default.
- The daily order number (XORD-036) — reported as drift, not built here.

## 7. Behavior and business rules

- **BR-1 Pickup state is separate and monotonic.** `pickup_status ∈ {PREPARING, READY, PICKED_UP}`, nullable (null = not a paged order). Allowed moves: PREPARING→READY, READY→PICKED_UP, PREPARING→PICKED_UP; same→same is a no-op; backwards is refused. `ready_at`, `acknowledged_at`, `picked_up_at` and `pickup_followed_at` are each set once. `OrderStatus` and its `canTransitionTo` are unchanged.
- **BR-2 Which orders are paged.** Only when the restaurant has `guest_paging` enabled and the order type is in `restaurants.guest_paging_order_types` (null → `takeaway, pickup, drive_thru`; owner may add `dine_in` or `delivery`). Never a table-visit round. POS side: `paging.enabled` is true and the ticket's order type is in `paging.order_types` (default `takeaway, drive_thru`; POS wire values are `dine_in, takeaway, delivery, drive_thru`, `lib/domain/models/ticket.dart:14-18`; the cloud also accepts `pickup`).
- **BR-3 Token.** 40 alphanumeric characters, unguessable, one per order, never regenerated. POS sales: generated by the till at settlement (`Random.secure()`), stored on `pos_orders.pickup_token`, printed, and sent as `pickup_token` on `POST /api/pos/orders`; the cloud stores it as sent. QR-menu orders: generated by the cloud in `PublicOrderController::store` and returned as `pickup_token` + `tracking_url`. Possession of the token is the only authorization (same model as `BillRequest.public_token`). Tokens expire for the public page after `tracking_ttl_hours` (default 48) and never appear in logs or analytics events.
- **BR-4 What the public page shows.** Order reference (`pickup_display_ref`: the number printed on the slip for POS sales, `ORD-{id}` for QR orders), `pickup_status`, `order_status` (so a cancelled order reads "cancelled"), timestamps, order type, restaurant name/logo/brand colour, branch name, and, only once PICKED_UP, `review_public_url` and the thank-you text. **Never** line items, prices, totals, customer name or phone.
- **BR-5 Not synced yet.** A receipt QR can be scanned before the sale reaches the cloud (2 s nudge, or hours in an outage). The page treats 404 as "registering your order" and backs off 5→30 s for 15 minutes before saying it could not find the order. The board does not list the order until it lands.
- **BR-6 Ready.** Either the till or the dashboard may mark READY. On READY the cloud sends the web push (if a diner push token is stored) and the open page rings/vibrates on its next poll. `ready_source` records `pos` or `dashboard`; `ready_by` the dashboard user, null for the till.
- **BR-7 Acknowledge.** The page sends `follow` once when opened (→ "Following on phone") and `ack` when the diner taps "On my way" (only while READY; otherwise 422). `call_out` is true on the board when READY for ≥ `call_out_minutes` (default 3) without `acknowledged_at`.
- **BR-8 Picked up.** PICKED_UP from the board or the till. For a QR-menu order still `NEW`, PICKED_UP also moves `OrderStatus` to COMPLETED through the existing `canTransitionTo` (the diner's existing review flow keys on COMPLETED). Marking a paged order COMPLETED through the existing `PATCH dashboard/orders/{order}/status` sets PICKED_UP. CANCELLED leaves pickup fields alone; the board hides the order and the page says cancelled.
- **BR-9 POS event ordering and clocks.** The `order_pickup` event is sent only after its sale is delivered (`_Waiting`, like refunds). The cloud clamps `occurred_at` to `[order.created_at, now()]`. A replayed, stale or backwards event answers 200 `applied:false`, never 4xx, so the drain marks it delivered and never quarantines a pickup. Events older than 24 h are dropped by the drain as `PICKUP_STALE` (not held for a person). A 404 from an older cloud defers the row (retry later), never quarantines.
- **BR-10 Two write paths.** Cloud transitions run under `lockForUpdate`; the monotonic rule decides. The POS detail pane shows the till's own stamps and never claims the cloud's state.
- **BR-11 Feature gating.** Dashboard and public routes are behind `feature:guest_paging` (public: checked in-controller, 403, like bill requests); the dashboard nav entry carries `feature: 'guest_paging'`; `RestaurantPublicResource` exposes `guest_paging`. The POS prints no QR and sends no token while `paging.enabled` is false (default).
- **BR-12 Reports.** Prep time = `ready_at − created_at` (POS `created_at` is the till's clock per POS-BE-020, clamped at intake); wait-after-ready = `picked_up_at − ready_at`. Aggregated in the restaurant timezone like `billTimings()`; filters `from`, `to`, `branch_id`, `group=hour|day`.
- **BR-13 Localization.** Every diner-facing string exists in English and Arabic; the tracking page follows the menu app's locale and RTL; digits follow the existing menu convention (UNVERIFIED which digit set `apps/menu` uses for order codes — reuse whatever `OrderSuccessModal.vue` does).
- **BR-14 Existing rules preserved.** `PATCH dashboard/orders/{order}/status` keeps its OPEN-table-visit refusal and `canTransitionTo` check; `completeIfSettled` is untouched; `orderPayloadHash` is untouched (the new fields are outside it); `subscription.writable` is deliberately not applied to pickup actions, for the same reason it is not applied to order status.

## 8. Acceptance criteria

- **AC-1** Given `guest_paging` is off for the restaurant, When any pickup endpoint is called, Then 403 (public) / 403 via middleware (dashboard), and `POST public/restaurants/{slug}/orders` returns no `pickup_token`. *Cloud feature test.*
- **AC-2** Given the flag is on and a QR-menu `takeaway` order is created, When the response is read, Then it carries a 40-char `pickup_token` and a `tracking_url` equal to `Restaurant::trackingUrl($token)`; a `dine_in` order with default types carries none; a table-visit round carries none. *Cloud feature test.*
- **AC-3** Given a valid token, When `GET public/orders/track/{token}` is called, Then 200 with exactly the fields of BR-4 and no `items`, `lines`, `total`, `customer` keys; an unknown, expired or other-tenant token gives 404; a second call with the ETag gives 304. *Cloud feature test.*
- **AC-4** Given a paged order, When the dashboard calls `PATCH dashboard/orders/{order}/pickup {status: READY}` twice, Then `ready_at` is set on the first call and unchanged on the second; `PICKED_UP` then succeeds; `READY` after `PICKED_UP` gives 422; a user from another restaurant gets 404; a user without `orders.update` gets 403. *Cloud feature test.*
- **AC-5** Given a READY order with no `acknowledged_at` for `call_out_minutes`, When the board is listed, Then `call_out` is true; after `POST .../ack` it is false. Given PREPARING, `ack` gives 422. *Cloud feature test with `Carbon::setTestNow`.*
- **AC-6** Given a POS sale posted with `pickup_token` and `receipt_number`, When it is replayed with the same body and `Idempotency-Key`, Then the same order is returned with the same token and `pickup_status = PREPARING`. *`tests/Feature/Pos` test on `PosTestCase`.*
- **AC-7** Given the board marked an order PICKED_UP, When a delayed POS `pickup` event with `status: READY` arrives, Then 200 `applied:false` and `picked_up_at` is intact. Given `occurred_at` before `created_at` or in the future, Then `ready_at` is clamped. Given an unknown order, Then 422. *Cloud POS feature test.*
- **AC-8** Given bootstrap is fetched, When the response is read, Then `restaurant.menu_url` equals `Restaurant::publicUrl()` and `features.guest_paging` reflects the flag. *Cloud POS feature test; POS bootstrap seed test proves `paging.menu_url` is written.*
- **AC-9** Given `paging.enabled = true` and a `takeaway` ticket, When it is settled on the POS, Then `pos_orders.pickup_token` is 40 chars, the receipt document contains a second QR whose payload is `{paging.menu_url}o/{token}`, and `buildOrderRequest` carries `pickup_token` and `receipt_number = invoice_number`. Given `paging.enabled = false` or a `dine_in` ticket, Then no token, no QR, no fields. *POS PostgreSQL test, receipt document/raster test, `outbox_drain_test`.*
- **AC-10** Given a settled paged sale on the POS, When the cashier presses Ready on the detail pane, Then `pickup_ready_at` is stamped once, one `pos_sync_outbox` row of type `order_pickup` exists (replay keeps the same `pickup_ready_event_id`), and the drain sends it only after the sale is delivered; a 404 defers, a >24 h event is quarantined as `PICKUP_STALE`. *POS `pickup_drain_test` with a recording fake API; widget test for the buttons.*
- **AC-11** Given the till role, When it updates the new pickup columns, Then the grant allows it and nothing else new. *`till_grants_enforced_test`.*
- **AC-12** Given the tracking page is open in Arabic, When the order becomes READY, Then the page rings and vibrates after the earlier "Notify me" gesture, shows RTL text and the "On my way" button, and after PICKED_UP shows the Google review button when `review_public_url` is set. *A person looks (in-app browser, mobile preset, en and ar); no JS test runner exists and none is added.*
- **AC-13** Given the diner installed the page to the Home Screen (iOS) or allowed notifications (Android/desktop), When READY is set, Then a push arrives; a dead FCM token is pruned from the order on the next send. *Cloud test with a fake Messaging for the pruning; delivery itself needs a person.*
- **AC-14** Given orders with `ready_at` across two branches and several hours, When `reports/prep-times?group=hour` is called, Then averages are computed in the restaurant timezone, the branch filter applies, and the route refuses without `reports.view` / `product_analytics`. *`ReportTest` cases.*
- **AC-15** Given every cloud migration of this feature, When `php artisan migrate` runs on an existing database, Then it only adds nullable columns and one unique index on an all-null column (no drops, renames, type changes or backfill). *Reviewed by reading; `/release-check` before any push.*

## 9. Edge cases and failure modes

| Case | Behaviour |
|---|---|
| Receipt scanned before the sale reaches the cloud | BR-5: "registering your order", backoff, no error for 15 min |
| Till offline for hours | Token still printed; the page keeps backing off; the board shows the order when the outbox drains; the READY event waits behind the sale |
| Diner closes the page | Push arrives if allowed; otherwise nothing — the counter still has "Call it out" |
| iPhone in Safari tab (no Home Screen install) | No push; the page alerts only while open; the page shows a one-line install hint, never blocks |
| Same order marked READY on till and tablet | Both succeed; first write wins the timestamp; second is a no-op |
| Board PICKED_UP, then delayed POS READY | 200 `applied:false`; state stays PICKED_UP |
| POS clock skew | `occurred_at` clamped server-side to `[created_at, now()]` |
| Token guessed / enumerated | 40 random chars (≈238 bits), throttled per IP in dedicated buckets (`paging-read` 120/min, `paging-write` 20/min, `paging-push` 10/min), 48 h TTL, no PII in the payload |
| Café Wi-Fi shares one public IP | Reads and writes are throttled in separate buckets so polling never starves "On my way"; page falls back to 8 s polling on 429 |
| Order cancelled after paging | Pickup fields untouched; board hides it; page reads "cancelled" |
| Refund after pickup | Unaffected (refund state is `settlement_status`, A4) |
| Restaurant turns the feature off mid-day | Public endpoints 403; existing tokens stop resolving; board nav disappears; POS keeps printing until its own toggle is off (see §10 deploy order) |
| Older cloud, newer POS | `pickup` endpoint 404 → outbox row deferred, never quarantined; owner keeps `paging.enabled` off until the cloud ships |
| Newer cloud, older POS | Nothing sent, no QR, no behaviour change |
| Arabic / RTL | All new strings in `en` and `ar` on cloud, web, menu and POS (`app_strings.dart`); page direction follows the menu locale |
| Plan / licence | Gated by `guest_paging` in `plans.feature_keys` / `restaurant_features`; no POS licence change |
| Empty board / very large day | Board lists today's paged orders only, excluding PICKED_UP older than 30 min; single indexed lookup per poll with ETag/304 |
| Tenant boundary | Every dashboard endpoint is tenant-scoped through the order's `BelongsToRestaurant`; public endpoints resolve the tenant from the token row and never accept a restaurant id |

## 10. Impact

**Apps and repos**: `xorder-cloud` (`apps/api`, `apps/web`, `apps/menu`, `packages/ui` i18n) and `xorder-pos` (`lib/data/postgres`, `lib/data/cloud`, `lib/features/receipt`, `lib/features/history`, `lib/features/admin`, `lib/domain/models`, `lib/core/l10n`). Two independent deploys.

**API and contract**: new public routes `GET public/orders/track/{token}`, `POST …/follow`, `POST …/ack`, `POST|DELETE …/push-token`; new dashboard routes `GET dashboard/pickup-board`, `PATCH dashboard/orders/{order}/pickup`, `GET dashboard/reports/prep-times`; `POST public/restaurants/{slug}/orders` response gains two optional keys; `PUT dashboard/restaurant` gains three optional fields. POS contract: **POS-BE-034 (PROPOSED)** — `POST /api/pos/orders` gains optional `pickup_token`, `receipt_number`; new `POST /api/pos/orders/{order}/pickup`; bootstrap gains `restaurant.menu_url`, `features.guest_paging`. All additive. The POS integrates only once the item is READY (after the cloud half is deployed). Existing READY items touched: POS-BE-006 (additive fields), POS-BE-023/025 bootstrap (additive keys).

**Data and migrations**: cloud — one migration adding nullable columns to `orders` (`pickup_token` unique, `pickup_status`, `pickup_display_ref`, `pickup_followed_at`, `ready_at`, `ready_by`, `ready_source`, `acknowledged_at`, `picked_up_at`, `pickup_push_token`) and `restaurants.guest_paging_order_types` json; `Feature::GUEST_PAGING`; `config/platform.php` `guest_paging` block. Cloud tests run on SQLite, so the unique index and locks are reviewed by reading. POS — migration 63 (or 64 if XORD-036 reappears first): `pos_orders` pickup columns, partial unique index, widened `pos_sync_outbox_event_known` CHECK (+ `order_pickup`), till grant columns; `pos_settings` keys `paging.enabled`, `paging.menu_url`, `paging.order_types`.

**Permissions**: none added or narrowed (§4).

**Localization**: `lang/{en,ar}/xorder.php`, `packages/ui/src/i18n/index.js`, `apps/menu/src/composables/useLocale.js`, `lib/core/l10n/app_strings.dart`.

**Documentation**: this folder (TECHNICAL, API, DATABASE, TEST_PLAN, TEST_REPORT, CHANGELOG to follow); `docs/FEATURE_INVENTORY.md` new row `guest-paging` (shared); `BACKEND_TO_POS.md` (cloud copy, mirrored to POS) POS-BE-034; `docs/qa/XORDER_QA_FINDINGS.md` entry for the XORD-036 drift (next free id XORD-042) if the owner confirms it.

**Deploy order**: cloud stages first (`/release-check`, owner pushes `main`); flip POS-BE-034 to READY; then the POS build; then enable `guest_paging` per restaurant and `paging.enabled` per till.

**Unrelated dirty files at verification time** (not touched by this feature): cloud — `.github/workflows/deploy.yml`, financial-accounts/landing/tender files, `lang/*/xorder.php`, `packages/ui/src/i18n/index.js`, `apps/landing/src/components/`; POS — `pos_widgets.dart`, four `management_*`/`shift_history_bits.dart` panes, `order_history_screen.dart`, `test/data/local_bootstrap_test.dart`, `test/core/pos_dropdown_field_test.dart`. Note that `order_history_screen.dart`, `lang/*/xorder.php` and the ui i18n file are also on this feature's path: whoever implements must rebase on or commit those edits first.

## 11. Dependencies, known gaps, risks

- **KDS gap** (handbook §3): not depended on; Ready is a counter action, not a kitchen one. If a KDS ever arrives, it would call the same `GuestPagingService::transition`.
- **Push on iOS**: Web Push only after Home Screen install (iOS 16.4+); the open page is the guaranteed path.
- **FCM configuration for `apps/menu`**: needs the same Firebase project keys as `apps/web` exposed in `apps/menu/public/firebase-config.js` (today GA4 only) — an ops step, not code (UNVERIFIED whether one Firebase web app may serve both origins; if not, a second web app in the same project).
- **XORD-036 drift**: the receipt number sent to the cloud is whatever the slip prints; if the daily number lands later it replaces `invoice_number` in `receipt_number` and takes migration 63, pushing this feature's migration to 64.
- **Polling load**: bounded by throttle + ETag; the board polls every 5 s per open tablet.
- **Firebase dependency size in `apps/menu`**: lazy-import `firebase/messaging` from the tracking view only.
- **Uncommitted work on both repos** (see §10) must be committed or stashed by the owner before implementation touches the overlapping files.

## 12. How it will be tested

| AC | Proof |
|---|---|
| AC-1…AC-5, AC-13 pruning | `apps/api/tests/Feature/GuestPagingTest.php` (new) + `OrderTest.php` extensions; `php artisan test --filter=GuestPaging`, then the full suite |
| AC-6…AC-8 | `apps/api/tests/Feature/Pos/PosPickupTest.php` (new, on `PosTestCase`) and a bootstrap assertion |
| AC-14 | `apps/api/tests/Feature/ReportTest.php` new cases |
| AC-9, AC-11 | POS `test/data/order_lifecycle_test.dart`, `till_grants_enforced_test.dart`, `test/data/outbox_drain_test.dart`, `test/features/receipt_raster_test.dart` + a receipt document test |
| AC-10 | POS `test/data/pickup_drain_test.dart` (new, recording fake API like `cloud_refunds_test.dart:898`), a widget test for the detail-pane buttons; `scripts/check.sh` for the whole suite |
| AC-12, AC-13 delivery | A person: settle a takeaway sale on the POS against a local cloud, scan/open the URL in the in-app browser (mobile preset, en and ar), press Ready on the till, confirm the ring and "On my way", mark Picked up on the board, see the review prompt; screenshots kept in TEST_REPORT.md |
| AC-15 | Reading the migration; `/release-check` |
| Vue builds | `pnpm --filter @xorder/menu build`, `pnpm --filter @xorder/web build` |

## 13. Decisions and open questions

**Decided (2026-11-02, owner, via AskUserQuestion)**
- D-1 Both POS counter orders and QR-menu orders are paged.
- D-2 Alert = tracking page open (poll + sound + vibration) plus FCM web push where allowed. No SMS/WhatsApp.
- D-3 Ready is pressed on the POS till and on a new dashboard pickup board.
- D-4 Ready is a separate pickup state; the cloud `OrderStatus` enum does not grow.
- D-6 (2026-11-02, implementer's default after review, **owner to confirm**) A CANCELLED order is never paged forward: Ready / Picked up on it answer 422 on the dashboard and `applied:false` from the POS, so no diner is told a cancelled order is ready. BR-8 already keeps its pickup fields untouched.
- D-5 (derived, this description) Token generated by the till at settlement; `receipt_number` sent explicitly; default paged types `takeaway, pickup, drive_thru`; `call_out_minutes` 3; `tracking_ttl_hours` 48; `PICKED_UP` older than 30 min leaves the board. Change any of these in `config/platform.php` / restaurant settings without touching the rules.

**Still open (assumptions written in; answer changes only details)**
- OQ-1 Should "Picked up" on the board be required, or should READY orders auto-expire after N minutes? Assumed: required, with the 30-minute board hide as the safety net.
- OQ-2 Should the dashboard board play a sound when a new READY order goes unacknowledged? Assumed: optional, off by default (suggestion, not requested).
- OQ-3 Should Ready / Picked up on the POS be limited to a role (as Refund may be)? Assumed: any signed-in till user. UNVERIFIED how Refund is gated on the pane.
- OQ-4 Does the owner want `drive_thru` paged by default (useful only with a waiting bay)? Assumed yes, removable per restaurant.
- OQ-5 Confirm the XORD-036 drift (daily order number absent from the tree) and whether to log it as XORD-042.

Next: `/implement guest-paging`. It will need approval for: the cloud migration (reaches `xorder-cloud` `main` → production), the POS-BE-034 contract text, the public-endpoint throttle values, the `PushService` refactor, the POS migration 63 and grant change, and each push to `main` (after `/release-check`).
