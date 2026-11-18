# Shared QR, client types the slip number: API (as built)

Status: **built 2026-11-18, not deployed**. Everything is behind the plan feature `guest_paging`. **No POS contract item** and no database change.

## Public (no login): the join page

The restaurant is the one in the URL (the page takes it from its own host, as the menu does). `403` when the restaurant is hidden or does not have `guest_paging`; `404` for an unknown restaurant.

### GET /api/public/restaurants/{slug}/pager-lookup: `throttle:240,1,pager-info`
So the page opens in the restaurant's language and brand before anything is typed. `Cache-Control: no-store`.
```json
{ "data": { "restaurant": { "name": "…", "name_ar": "…", "name_en": "…", "default_language": "ar", "bilingual": true, "logo_url": "/storage/…", "brand_color": "#7b3fa0" } } }
```

### POST /api/public/restaurants/{slug}/pager-lookup: `throttle:120,1,pager-lookup`
Body `{ "number": "42" }` (string, required, max 40). Finds the client's order from the number on their slip.

How a number is read (`PagerLookupService`):
- **Digits only** means the digits at the end of the invoice number, compared as integers: `42`, `042` and `000042` all match `MAIN-2026-000042`; `1042` does not.
- **Anything else** is taken as the full invoice number as printed, compared ignoring case, spaces and dashes (`main 2026 000042` matches).
- Arabic-Indic digits are folded to Latin first.
- Only this restaurant's till orders (`channel = pos`) sold in the last `GUEST_PAGING_LOOKUP_WINDOW_HOURS` (default 12) are considered, and only those `GuestPagingService::isEligible` accepts (flag on, a paged order type, not a seated table round).

Answers (`Cache-Control: no-store`):
| Status | Body | Meaning |
|---|---|---|
| `200` | `{"data":{"state":"found","tracking_token":"<40 chars>"}}` | exactly one order matches; the page goes to `/menu/o/{token}` (the existing order-number page, see `docs/features/guest-paging/API.md`) |
| `404` | `{"data":{"state":"not_found"}}` | no match (also: the sale has not reached the cloud yet) |
| `409` | `{"data":{"state":"ambiguous"}}` | more than one match (two branches share the number): ask for the full number |
| `422` | validation error | `number` missing |
| `429` | | rate limit |

A found order that has no tracking token (every till order) is given one in the same call: `pickup_token`, `pickup_status = PREPARING`, and `pickup_display_ref` (the number without leading zeros), under a row lock. It is idempotent: the same lookup returns the same token; an order that already has a token (a QR-menu order) keeps it and is never moved backwards. Several phones can follow one order.

## Dashboard (JWT, `settings.view` + `feature:guest_paging`)

### GET /api/dashboard/pager-qr
`{"data":{"join_url":"https://demo.xorder.io/menu/p","svg":"<svg…>"}}`. Always the signed-in user's own restaurant. Without a menu domain (development) the URL is the path form `…/r/{slug}/p`.

### GET /api/dashboard/pager-qr/download
The same QR as a PNG, `Content-Disposition: attachment; filename="qr-counter-{slug}.png"`.

## Menu app route
`/menu/p` (served by the existing `/menu/*` shell route) renders the join page; the response carries `X-Robots-Tag: noindex, nofollow`.

## Compatibility
Nothing existing changes shape. The order-number page and its API are untouched. No migration, no POS change.
