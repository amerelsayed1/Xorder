# Guest paging — API

Status: S1 + S2 as built 2026-11-02 (dashboard and public halves). POS endpoints (S5, POS-BE-034) are **planned, not built**; their shapes are in `FEATURE.md` §10 and the approved plan and must not be integrated against yet.

All dashboard routes: JWT bearer, `role:` portal middleware, `feature:guest_paging`, then the capability shown. Not behind `subscription.writable` (same reasoning as `PATCH orders/{order}/status`). Cross-tenant ids resolve to **404**.

## GET /api/dashboard/pickup-board — `can:orders.read` (orders.view OR live.view)

Query: `branch_id` (optional integer).

Today's paged orders (restaurant timezone), excluding `status = CANCELLED` and orders picked up more than 30 minutes ago, oldest first.

```json
{
  "data": [
    {
      "id": 1024,
      "ref": "ORD-1024",
      "pickup_status": "READY",
      "followed_at": "2026-11-02T10:01:00+00:00",
      "ready_at": "2026-11-02T10:06:00+00:00",
      "acknowledged_at": null,
      "picked_up_at": null,
      "call_out": true,
      "order_type": "pickup",
      "channel": "qr",
      "customer_name": "Amer",
      "created_at": "2026-11-02T10:00:00+00:00",
      "branch_id": 3
    }
  ],
  "meta": { "call_out_minutes": 3, "linger_minutes": 30 }
}
```

`call_out` is true when the order is READY, unacknowledged, and `ready_at` is at least `call_out_minutes` old. The response carries an `ETag`; send `If-None-Match` to get `304` when nothing moved. The pickup token is never in this output.

Errors: 403 feature off or capability missing; 422 bad `branch_id`.

## PATCH /api/dashboard/orders/{order}/pickup — `can:orders.update`

Body: `{ "status": "READY" | "PICKED_UP" }`.

Forward only (`PREPARING → READY → PICKED_UP`, `PREPARING → PICKED_UP` allowed, same → same is a no-op). `READY` stamps `ready_at`, `ready_by`, `ready_source = dashboard` once. `PICKED_UP` stamps `picked_up_at` once and, if the order is still `NEW`, moves `status` to `COMPLETED` and marks its `order.created` notification read.

200: `{ "data": OrderResource, "message": "Pickup status updated." }`
422: `{ "message": "That pickup status change is not allowed." }` (backwards) · `{ "message": "This order has no tracking link." }` (order not paged) · validation error on `status`.
404: order of another restaurant or unknown.

## Public — the diner's tracking page (S2)

No auth. The 40-character token is the only credential; the route constraint is `[A-Za-z0-9]{40}` (anything else is 404 before the controller runs). Every endpoint answers **404** for an unknown token or one older than `tracking_ttl_hours` (48 h, `config/platform.php`), and **403** when the restaurant is not publicly visible or no longer holds `guest_paging`. Locale: `X-Locale: ar|en` header or `?lang=` (the platform's `SetLocale`).

Throttles use their own buckets (`throttle:N,1,<prefix>`): `paging-read` 120/min, `paging-write` 20/min (`follow`, `ack`), `paging-push` 10/min. A bare `throttle:N,1` would key on the IP alone and share one counter with every other public route, so a diner's own polling would 429 their "On my way".

### GET /api/public/orders/track/{token} — `paging-read`, 120/min

```json
{
  "data": {
    "ref": "ORD-1024",
    "status": "READY",
    "order_status": "NEW",
    "placed_at": "2026-11-02T10:00:00+00:00",
    "ready_at": "2026-11-02T10:06:00+00:00",
    "acknowledged_at": null,
    "picked_up_at": null,
    "order_type": "pickup",
    "call_out": true,
    "restaurant": { "name": "Al-Hay Coffee", "name_ar": "قهوة الحي", "name_en": "Al-Hay Coffee", "default_language": "ar", "bilingual": true, "logo_url": "/storage/logos/…png", "brand_color": "#0a7" },
    "branch": { "name": "Maadi" },
    "review_public_url": null,
    "review_thank_you": null
  }
}
```

`restaurant.name_ar`, `name_en`, `default_language` (`ar|en`) and `bilingual` were added on 2026-11-18 (additive) so the order-number page opens in the restaurant's language like the menu does; `name` stays as before, localized by `X-Locale`/`?lang=`. `status` is the pickup state (`PREPARING|READY|PICKED_UP`); `order_status` is the platform lifecycle, so a cancelled order reads `CANCELLED` there. `ref` is the number printed on the slip (`pickup_display_ref`) or `ORD-{id}`. `logo_url` is rewritten to a root-relative path exactly as `RestaurantPublicResource` does (`PublicImageUrl::relative`). Visibility follows `Restaurant::isPubliclyVisible()` (status), not `hide_menu_when_expired`: a diner who already paid keeps their page while the menu of an expired subscription may be hidden. `review_public_url` (through `SafeUrl::forLink`) and `review_thank_you` are present **only when `status = PICKED_UP`**. Never present: items, totals, customer name or phone, the push token. Carries an `ETag`; `If-None-Match` → `304`.

### POST /api/public/orders/track/{token}/follow — `paging-write`, 20/min
Stamps `pickup_followed_at` once ("Following on phone" on the board). 200 with the same payload.

### POST /api/public/orders/track/{token}/ack — `paging-write`, 20/min
"On my way". Stamps `acknowledged_at` once; clears `call_out`. 200 with the payload; **422** `pickup_not_ready` unless `status = READY`; **422** `order_transition_invalid` when `order_status = CANCELLED` (D-6), even if it was READY when cancelled.

### POST /api/public/orders/track/{token}/push-token — `paging-push`, 10/min
Body `{ "token": "<FCM token, max 512>" }` → **204**. Stores `pickup_push_token` (used by S8). 422 on validation.

### DELETE /api/public/orders/track/{token}/push-token — `paging-push`, 10/min
Clears it → **204**.

## Changed: POST /api/public/restaurants/{slug}/orders (additive)

When the restaurant holds `guest_paging`, the `order_type` is in `guest_paging_order_types` (null → `takeaway, pickup, drive_thru`) and the order is not a round of a seated table, the 201 response gains:

```json
{ "data": { "id": 1024, "code": "ORD-1024", "pickup_token": "<40 chars>", "tracking_url": "https://demo.xorder.io/menu/o/<40 chars>" } }
```

Otherwise the response is unchanged. `tracking_url` comes from `Restaurant::trackingUrl()` (same host rules as `tableUrl()`; `/r/{slug}/o/{token}` without a menu domain).

## Changed: OrderResource (additive)

New keys on every order payload (`GET dashboard/orders`, `PATCH .../status`, `PATCH .../pickup`): `pickup_status` (`PREPARING|READY|PICKED_UP|null`), `pickup_ref`, `pickup_followed_at`, `ready_at`, `ready_source` (`pos|dashboard|null`), `acknowledged_at`, `picked_up_at`. All null for orders that are not paged. `pickup_token` is deliberately absent. `PosOrderResource` (what the till reads) is unchanged.

## Changed: PATCH /api/dashboard/orders/{order}/status

Unchanged request and response shape. New behaviour: `COMPLETED` on a paged order also applies `PICKED_UP` (no-op if already picked up). `CANCELLED` leaves the pickup fields alone.

## Changed: RestaurantPublicResource (additive)

`guest_paging: boolean` next to `internal_reviews`.
