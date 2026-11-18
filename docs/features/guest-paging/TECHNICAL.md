# Guest paging — technical plan and as-built notes

Status: S1 built 2026-11-02 (not committed) · Verified against: xorder-cloud `775bf0f` + working tree, xorder-pos `c67c754`. Specification: `FEATURE.md`. Stage list and verified paths: the approved plan of 2026-11-02 (owner approved the whole plan, then said "Yes, start S1").

## Stages (rollout order)

| Stage | Repo / app | Change | Proof | Rollback |
|---|---|---|---|---|
| S1 | cloud `apps/api` (+2 admin key lists in `apps/web`) | pickup lifecycle beside `OrderStatus`, feature flag, service, board API | `tests/Feature/GuestPagingTest.php` | migration `down()`; routes behind `feature:guest_paging` (off everywhere) |
| S2 | cloud `apps/api` | public tracking endpoints, QR-order token issuance | `GuestPagingTest` + `OrderTest` | same flag |
| S3 | cloud `apps/menu` | tracking page (poll + sound) | build + a person | not served unless flag on |
| S4 | cloud `apps/web` | pickup board page, profile fields | build + a person | nav hidden by flag |
| S5 | cloud `apps/api` | POS-BE-034: sale fields, pickup event endpoint, bootstrap keys | `tests/Feature/Pos/PosPickupTest.php` | additive; POS ignores |
| S6 | POS | token + receipt QR behind `paging.enabled=false` | PG tests, receipt tests | toggle off |
| S7 | POS | Ready / Picked up + `order_pickup` outbox event | drain tests | toggle off |
| S8 | cloud api + menu | diner web push | push tests + a person | push token optional |
| S9 | cloud api + web | prep-time report | `ReportTest` | route behind flag |
| S10 | docs | seven files, inventory, QA entry | — | — |

Verification commands: cloud `cd apps/xorder-cloud/apps/api && php artisan test --filter GuestPaging` then the full suite as `php -d memory_limit=1G vendor/bin/phpunit` (on this machine `php artisan test` dies at PHP's 128 MB default inside the parallel runner; the flag does not reach its child processes); Vue `cd apps/xorder-cloud && pnpm --filter @xorder/web build` (no JS test framework exists); POS `cd apps/xorder-pos && scripts/check.sh`.

## S1 as built (cloud foundation)

**Schema** — `database/migrations/2026_11_02_000100_add_guest_paging_to_orders_table.php`
- `orders`: `pickup_token` varchar(40) nullable **unique**; `pickup_status` varchar(12) nullable; `pickup_display_ref` varchar(40); `pickup_followed_at`, `ready_at`, `acknowledged_at`, `picked_up_at` timestamps; `ready_by` FK `users` null-on-delete; `ready_source` varchar(10); `pickup_push_token` varchar(512). No index on `pickup_status` (the board filters it with `!=` in an `OR`; the existing `(restaurant_id, created_at)` index serves the query) — dropped after the database review.
- `restaurants`: `guest_paging_order_types` json nullable.
- Additive only, no defaults on existing rows, no backfill. PostgreSQL notes are in `DATABASE.md` (one transaction, `ACCESS EXCLUSIVE` on `orders` for two scans; no `lock_timeout` configured anywhere, pre-existing). Say so in `/release-check`.

**Enums** — `app/Enums/PickupStatus.php` (`PREPARING|READY|PICKED_UP`, `canTransitionTo` forward-only, same→same allowed). `app/Enums/Feature.php` gains `GUEST_PAGING = 'guest_paging'` (no `requires()`, not in `defaultSet()`).

**Service** — `app/Services/GuestPagingService.php`
- `pagedOrderTypes()`, `isEligible()` (BR-2), `generateToken()` (BR-3, unique across tenants).
- `transition(Order, PickupStatus, source, ?User, ?CarbonInterface $at)`: re-reads the row with `lockForUpdate` in a transaction; returns `['applied','reason','order']` with reason `ok|noop|backwards|not_paged|cancelled` (never throws for a lifecycle reason; `cancelled` is D-6). READY stamps `ready_at/ready_by/ready_source` once; PICKED_UP stamps `picked_up_at` and, for a `NEW` order, moves `status` to COMPLETED through `canTransitionTo` and marks the `order.created` notification read (BR-8). `$at` is clamped to `[created_at, now()]` (BR-9). READY schedules `pushReady()` via `app()->terminating`; the method is a no-op until S8.
- `isCallOut()` (BR-7) uses `config('platform.guest_paging.call_out_minutes')`.

**Model / resource** — `Order`: fillable + casts for the new columns, `isPaged()`, `readyBy()`. `Restaurant`: `guest_paging_order_types` fillable + array cast. `OrderResource`: adds `pickup_status`, `pickup_ref`, `pickup_followed_at`, `ready_at`, `ready_source`, `acknowledged_at`, `picked_up_at` (additive; **the token is not exposed**). `RestaurantPublicResource`: adds `guest_paging` boolean. The POS reads `PosOrderResource`, which is untouched.

**Routes** — `routes/api.php`, dashboard group, after the order queue:
- `GET dashboard/pickup-board?branch_id=` · `feature:guest_paging` + `can:orders.read` · today's paged orders (restaurant tz), excluding CANCELLED and PICKED_UP older than 30 min, oldest first; rows `{id, ref, pickup_status, followed_at, ready_at, acknowledged_at, picked_up_at, call_out, order_type, channel, customer_name, created_at, branch_id}`, `meta.call_out_minutes`, `meta.linger_minutes`; ETag → 304.
- `PATCH dashboard/orders/{order}/pickup {status: READY|PICKED_UP}` · `feature:guest_paging` + `can:orders.update` · 200 `OrderResource`; 422 `pickup_transition_invalid` (backwards) / `order_not_paged`; 404 cross-tenant; not behind `subscription.writable` (same reasoning as order status).
- `Dashboard\OrderController::updateStatus`: the status write, the BR-8 `transition(PICKED_UP)` call and the notification courtesy now run in one `DB::transaction` (review SF-1); the service's own transaction becomes a savepoint.
- Board rows are ordered by `created_at, id` so same-second orders keep one order between polls on PostgreSQL (review SF-3).
- `Order::$auditExclude = ['pickup_token', 'pickup_push_token']` keeps both tokens out of the activity log (review SF-2; pattern `PosTerminal`).
- Review 2026-11-02 (`code-reviewer`, `database-reviewer`): no blockers; four should-fixes applied (above + D-6); nits recorded: `app()->terminating` inside a transaction (revisit with `DB::afterCommit` when S8 wires the push), offline licences issued without an explicit feature list now carry `guest_paging` (POS parses it as a plain string set, no action).

**Config / seed / i18n** — `config/platform.php` `guest_paging.call_out_minutes` (3), `tracking_ttl_hours` (48). `PlanSeeder` adds `guest_paging` to Restaurant Pro (first-boot only). `lang/{en,ar}/xorder.php` messages `pickup_updated`, `pickup_transition_invalid`, `order_not_paged`. `packages/ui/src/i18n/index.js` `feature.guest_paging` (en, ar). `PlanForm.vue` `capabilityKeys`, `RestaurantForm.vue` `featureDisplayOrder` + `customCapabilityKeys` include `guest_paging`.

**Deliberately not in S1**: token issuance on either intake path, public endpoints, the board page, the POS contract, push, reports. `pickup_token` is only ever written by tests until S2/S5.

## S2 as built (public tracking + QR-menu token)

- `Restaurant::trackingUrl(string $token)` beside `tableUrl()`: `https://{slug}.{menu_domain}/menu/o/{token}`, fallback `{app.url}/r/{slug}/o/{token}`.
- `PublicOrderController::store`: inside the existing transaction, on the new-order branch only, `GuestPagingService::isEligible($restaurant, $order->order_type, $session?->table_visit_id !== null)` → `pickup_token` + `pickup_status = PREPARING` before `save()`. The round branch (existing open table-visit order) never gets a token. Response gains `pickup_token` + `tracking_url` when paged. `pickup_display_ref` stays null for QR orders; readers fall back to `code()`.
- `app/Http/Controllers/Public/PublicOrderTrackingController.php` (shape of `PublicBillRequestController`): `show`, `follow`, `acknowledge`, `storePushToken`, `destroyPushToken`. `resolve()` looks the token up across tenants (`withoutGlobalScopes`, eager `restaurant.features` + `branch`), 404 unknown/expired (`created_at` older than `tracking_ttl_hours`), 403 not visible / feature off. No `TenantContext` override: the controller issues no scoped query. `present()` returns ref + state + branding only; `review_public_url` (via `SafeUrl::forLink`) and the thank-you text only once PICKED_UP. ETag/304 like the pulse.
- Routes: `Route::prefix('public/orders/track/{token}')->where(['token' => '[A-Za-z0-9]{40}'])` group; throttles `120,1,paging-read` / `20,1,paging-write` / `10,1,paging-push`. The third argument is the limiter-key prefix: without it `ThrottleRequests` keys on `sha1(domain|ip)` alone and every bare `throttle:N,1` public route shares one counter per address (security review SF-1).
- `acknowledge()` refuses a CANCELLED order with 422 (D-6, review SF-2). `platform` was dropped from the push-token body (nothing stored it). `logo_url` goes through `PublicImageUrl::relative()` for parity with the public resource.
- Messages: `pickup_not_ready` (en/ar).
- Review 2026-11-02 (`security-reviewer`): no blockers; SF-1/SF-2 applied; nits recorded: nginx access logs will carry the token in the path (infrastructure, outside the repo — BR-3 "never in logs" holds for application logs only); a staff JWT sent to the public route scopes the eager-load to that staff's tenant and yields 403 for another venue's token (no data exposed); tracking ignores `hide_menu_when_expired` by design (documented in API.md).
- Tests: `GuestPagingTest` S2 section (token issuance by flag/type/round, payload shape and privacy, 404/403/TTL, 304, cancellation, follow/ack idempotency and call-out, push token store/delete and non-echo, locale).

## Approvals that remain
- The migration reaches production on the next push of `xorder-cloud` `main` (`/release-check` first; owner pushes).
- POS-BE-034 contract text (S5), the public throttle values (S2), the `PushService` refactor (S8), POS migration 63 + till grant (S6).

## S3 plan — the client number page (written 2026-11-18, awaiting approval)

Scope: `apps/xorder-cloud/apps/menu` only (plus one optional response header in the cloud API). No migration, no POS change, no contract change. Verified against monorepo `2ac114fb` and against the live demo restaurant on 2026-11-18.

### Facts verified
- The menu app has **no router**: `App.vue` reads `window.location` itself (restaurant slug from the subdomain, table token from `…/t/{token}`; `App.vue:45-53`). `MenuShellController::show` serves the same SPA shell for any `/menu/*` path (`app/Http/Controllers/Public/MenuShellController.php:24-40`), so `/menu/o/{token}` already reaches the shell and **no server routing change is needed**. Today the SPA then renders the full menu there (seen live on `demo`).
- Tracking API, live on demo: `GET /api/public/orders/track/{token}` returns `ref`, `status` (`PREPARING|READY|PICKED_UP`), `order_status`, `ready_at`, `acknowledged_at`, `call_out`, `restaurant {name, logo_url, brand_color}`; ETag/304; `POST …/ack` (422 until READY); 404 unknown or older than 48 h; 403 when the restaurant lacks `guest_paging`; 120/min read limit.
- The page needs nothing else from the API.

### Design
1. **Entry switch in `src/main.js`**: if `location.pathname` matches `^/menu/o/([A-Za-z0-9]{40})/?$`, dynamically import `src/tracking/TrackingApp.vue` and mount only that. `App.vue` (the menu), the cart and the menu fetch are never loaded for this URL. Every other path runs exactly as today.
2. **`useOrderTracking(token)`** composable: polls the endpoint every 5 s with the ETag (a 304 costs no body), pauses while the tab is hidden and refreshes on return, backs off after errors, stops on `PICKED_UP`, `CANCELLED` or 404.
3. **Screen** (mobile first, Arabic default, English supported, RTL-safe): the client number large and centred; one status line and a simple 3-step indicator (being prepared, ready, picked up); restaurant name and logo and the brand colour (text colour chosen for contrast with the helper from PR 9, moved to a shared `src/lib/contrast.js`). **No menu, no cart, no prices, no customer name or phone.**
4. **States covered**: loading, preparing, ready (highlighted), "On my way" button (only when READY, calls `ack`, then shows confirmed), picked up, cancelled, not found or expired, paging off (403, shown as "not available"), offline or error (keeps the last known status and shows "reconnecting").
5. **Alert when ready, while the page is open**: vibration (`navigator.vibrate`, where the browser supports it) and a short beep through the Web Audio API. Browsers block sound until the user touches the page, so the page shows a one-tap "Enable sound" control. Push to a closed page is **S8**, not this stage.
6. **Strings** in English and Arabic next to the menu's existing strings; digits via the existing `installEnDigits`; `<meta name="robots" content="noindex">` set at runtime.
7. **Optional, cloud API:** an `X-Robots-Tag: noindex` header on `/menu/o/*` in `MenuShellController::show`, because crawlers do not run the page's JavaScript. One line plus one feature test; skip if you prefer to keep this stage menu-app only.

### Tests and how each acceptance point is proven
No JavaScript test framework exists in the repo, so nothing here is covered by an automated front-end test and I will say so. Checks: `cd apps/xorder-cloud && pnpm build`; the full API suite stays green (API untouched, except the optional header test). Manual checklist on the live demo with a test order, on a real phone: scan shows the number and "being prepared" (not the menu); marking Ready flips the page, vibrates and beeps after enabling sound; "On my way" works and is refused before Ready; cancel shows cancelled; a wrong token shows "not found"; a restaurant without paging shows "not available"; Arabic and English; the normal menu and table-QR URLs still behave as before.

### Rollout and rollback
Cloud deploy only; the existing tokens and the tracking API are already live, so the page works as soon as the build ships. Rollback is `./deploy.sh --rollback`, which returns to today's behavior (the menu opens). Needs `/release-check` and your approval before anything reaches `main`.

### Risks
- The page is public; the 40-character token is the only credential and the endpoint answers 404 for anything else. Nothing personal is shown.
- iOS Safari ignores vibration; sound needs a tap; both are browser limits, hence S8 push.
- Polling every 5 s per open page is within the 120/min limit, but a very busy venue with many phones on one Wi-Fi IP could hit it; the page backs off on 429.

### Open questions (defaults chosen)
Poll interval 5 s; keep the screen awake with the Wake Lock API while a page is open (suggestion, default off); apply `noindex` through the response header (default yes).

### S3 as built (2026-11-18)
Matches the plan above, with these differences, all small:
- **The menu bundle is still downloaded** for `/menu/o/{token}`, because the tracking page is selected inside the menu's entry file (a second entry hop would have added a round trip to every normal menu load). None of the menu runs: no menu fetch, no cart, no analytics (`initAnalytics` is skipped). The tracking page itself is its own chunk (`TrackingApp-*.js`, 5.6 kB, 2.6 kB gzip), loaded only on that path.
- **`POST …/follow` is called once per page load** (best effort), so the dashboard board can show "Following on phone". The plan did not list it; it is part of the S2 API and the original description.
- **Language:** Arabic by default, English when the phone's language is English, with a toggle on the page.
- Not built, as planned: push to a closed page (S8), Wake Lock (default off).
