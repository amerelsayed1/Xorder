# One shared QR for guest paging: API (as built, cloud half)

Status: **built 2026-11-18, not deployed**. Cloud half only: the menu join page, the dashboard QR and the POS are not built. Contract item for the till: **POS-BE-035, PROPOSED** (see `apps/*/docs/coordination/BACKEND_TO_POS.md`).

All routes sit behind the plan feature `guest_paging`. Every JSON error uses the platform's usual shape.

## Public (no login): the join page

The restaurant is the one in the URL (the page takes it from its own host). The phone proves its session with the secret in the `X-Pager-Secret` header (40 letters and digits). The secret is never in a URL.

### POST /api/public/restaurants/{slug}/pager-sessions: `throttle:120,1,pager-start`
Starts a session, or resumes the phone's own if it is still open (send its secret in the header).
- `201` new session, `200` resumed. `Cache-Control: no-store`.
```json
{ "data": {
  "state": "open",
  "code": "4821",
  "expires_at": "2026-11-18T10:30:00+00:00",
  "secret": "<40 chars, only on 201>",
  "restaurant": { "name": "…", "name_ar": "…", "name_en": "…", "default_language": "ar", "bilingual": true, "logo_url": "/storage/…", "brand_color": "#7b3fa0" }
} }
```
- `403` the restaurant is hidden or does not have `guest_paging`; `404` unknown restaurant; `503` no free code (very busy); `429` rate limit.
- An expired session sent in the header is replaced: the response is a new `201` with a new secret.

### GET /api/public/restaurants/{slug}/pager-sessions/current: `throttle:1200,1,pager-read`
Where the phone's session stands. `404` for a missing, malformed or unknown secret, and for a secret that belongs to another restaurant (nothing about other sessions is revealed).
- `state: "open"`: with `code` and `expires_at`.
- `state: "expired"`: no code; the phone starts again.
- `state: "bound"`: with `tracking_token`, the order's own 40-character token. The phone then goes to `/menu/o/{token}` (the existing order-number page; its API is in `docs/features/guest-paging/API.md`).

## Till (device token, group `pos.device`): POS-BE-035, PROPOSED

### GET /api/pos/pager/{code}
Advisory check. `200 {"data":{"open":true}}` when the code is open for the till's restaurant, else `404 {"code":"PAGER_CODE_NOT_FOUND","message":"…"}` (also when the feature is off). Arabic-Indic digits are accepted by the server's code logic, but the till folds them first.

### POST /api/pos/orders: additive
New optional body field `pager_code` (string, max 16).
- It is **not** part of the idempotency hash (`PosOrderService::orderPayloadHash` hashes only id, branch, type, lines, discount and payments), and it is never a reason to refuse the order.
- When it is sent, the answer gains a top-level `pager` beside `data`:
```json
{ "data": { "…": "unchanged order body" }, "pager": { "status": "paired" } }
```
`status` is one of `paired`, `not_found` (unknown, malformed, another restaurant's, or already used: a bound session keeps no code), `expired`, `already_used`, `not_eligible` (order type not paged, or the feature is off).
- A **replay** of the same order binds again, so a retry whose first attempt died before binding finishes the job. An order already paired answers `paired`.
- Binding sets the order's tracking token and `PREPARING` when it has none (a till order has none), and its display reference to the order's `invoice_number`. **UNVERIFIED** that this is the number printed on the slip: confirm on a real till before the POS release.

### GET /api/pos/bootstrap: additive
`restaurant.guest_paging` (bool).

## Compatibility
Old till against the new server: sends no `pager_code`, ignores the extra keys. New till against an old server: the check answers `404` (skip it); the unknown `pager_code` key is dropped by validation. An order without a code gets exactly the answer it got before (tested).
