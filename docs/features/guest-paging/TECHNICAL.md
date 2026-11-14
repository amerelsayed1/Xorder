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
