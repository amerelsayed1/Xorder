# API — waiter-app (WA1): the waiter link

**Not a cloud API.** A LAN HTTP API served by the till that holds the tables (`WaiterLinkServer`, `packages/xorder_waiter_link/lib/src/server.dart`), port 8787, wire version 1 (`/v1/...`). JSON in and out; money is integer minor units with the currency's exponent. Plain HTTP in WA1 — TLS is the first follow-up (TECHNICAL §11).

## Auth
| Layer | How | Missing / bad |
|---|---|---|
| Device | `Authorization: Device <token>` from `/v1/pair` | 401 `UNPAIRED`; revoked 401 `DEVICE_REVOKED` |
| Waiter | `x-waiter-session: <session>` from `/v1/sign-in` | 401 `SIGN_IN_REQUIRED` (also after 12 h idle) |

## Routes
| Method | Path | Needs | Body → reply |
|---|---|---|---|
| GET | `/v1/hello` | — | `{wire: 1, name}` |
| POST | `/v1/pair` | — | `{code, device_name}` → `{device_token, device_id}`; 403 `PAIRING_CODE_INVALID`; 429 `TOO_MANY_ATTEMPTS` after 5 wrong codes from one address (1 min) |
| POST | `/v1/sign-in` | device | `{pin}` → `{session, staff{id,name,capabilities}}`; 403 `PIN_WRONG`; 403 `NOT_PERMITTED` without `pos.operate`; 429 after 5 wrong PINs on the device |
| POST | `/v1/sign-out` | device | ends the session |
| GET | `/v1/menu` | session | `{currency, categories[], products[{id,category_id,name{en,ar},price_minor,available,groups}], groups[{id,name,min,max,variant,modifiers[{id,name,delta_minor,available,default}]}]}` — open-price items and combos are not offered |
| GET | `/v1/floor` | session | `{currency, tables[{id,label,area,seats,state: free\|open\|bill_asked,total_minor,items,guests}]}` |
| GET | `/v1/tables/{id}/check` | session | the check (below); 404 `NOT_FOUND` |
| POST | `/v1/tables/{id}/ops` | session | `{version?, ops[]}` → 200 check; 409 `CHECK_CHANGED` + `check` (current); 422 `REFUSED` + `reason`; 403 `NOT_PERMITTED` + capability; 404 |

Ops (applied in order, **all or none**): `add {product_id, modifier_ids, qty, note?}`, `qty {line, delta}`, `remove {line}`, `note {line, note}`, `guests {guests}`, `send`.

Refusal reasons: `unknown_product`, `unknown_option`, `open_price`, `bad_quantity`, `bad_guests`, `out_of_stock`, `options_required`, `too_many_options`, `unknown_line`, `line_sent`, `nothing_to_send`, `payment_started`, `not_permitted`, `refused`.

Check: `{table_id, table_label, currency, version?, lines[{key,name,qty,total_minor,modifiers,note,stage: draft\|sent\|voided,round}], subtotal_minor, discount_minor, service_minor, tax_minor, total_minor, rounds_sent, guests?}`. `version` is `pos_parked_tickets.version`; null = nothing saved on the table.

Mismatched wire version → 426 `VERSION_MISMATCH`.


## Cloud flavor — the same wire served by the platform (POS-BE-033, built 2026-11-09, not deployed)

Base `https://xorder.io/api/pos/waiter/{slug}` + `/v1/...` (the restaurant is the slug in the path). Implementation: `xorder-cloud/apps/api` — `routes/api.php` (group `pos/waiter/{slug}/v1`), `Http/Middleware/WaiterWire.php`, `Http/Controllers/PosWaiter/{AuthController,FloorController}.php`, `Services/WaiterCheckService.php`, `Services/WaiterMenuService.php`. Differences from the LAN link:

| Aspect | Cloud |
|---|---|
| Device | `Authorization: Device xwd_<64 hex>`; **no pairing code**: the first `sign-in` registers the phone and returns `device_token` once. `POST /v1/pair` does not exist. Unknown token → 401 `UNPAIRED`; revoked → 403 `DEVICE_REVOKED` |
| Session | header `X-Waiter-Session: xws_<64 hex>`, idles out after 12 h → 401 `SIGN_IN_REQUIRED` |
| Sign-in | `{username, pin, device_name}` (username is the staff username, PIN the POS PIN of POS-BE-024). Wrong username or PIN → 401 `PIN_WRONG` (one error); 5 failures per device (per IP when no token) → 429 `TOO_MANY_ATTEMPTS` + `retry_after`; no `pos.operate` → 403 `NOT_PERMITTED` `reason: pos_operate` |
| Entitlement | the restaurant needs `table_management`; suspended/archived or missing feature → 403 `NOT_PERMITTED` `reason: service_unavailable`; unknown slug → 404 `NOT_FOUND`. **Not gated on `pos`** and **not refused when a restaurant has `pos`** (the "pos ⇒ offline flavor" rule is by plan, not enforced in code) |
| Version | `check.version` is `table_visits.check_version` (0 for a table with no visit); a stale `version` → 409 `CHECK_CHANGED` + `check` |
| Refusal reasons used | `unknown_product`, `unavailable`, `bad_quantity`, `required_option`, `too_many_options`, `invalid_options`, `line_sent`, `nothing_to_send` |
| Sent lines | cannot be edited, removed or voided from the handheld (REFUSED `line_sent`); no discounts, payment or open-price items |
| Dashboard | `GET /api/dashboard/waiter-devices` (`tables.view`), `POST /api/dashboard/waiter-devices/{id}/revoke` (`tables.update`, subscription writable); a revoke also signs the device's waiters out |

A check = the table visit's one NEW order (rounds appended, as the QR path does) as `sent` lines + the visit's shared draft. Draft lines carry ids and quantities only; every price, modifier delta, service charge and tax is computed on the server by `PosPricingEngine` (`dine_in`), and sent lines keep the price they were sent at. `send` creates (or appends to) the visit's order with `source = 'waiter'` when it creates it, adds one `order_rounds` row and its `order_items`, empties the draft and sends the same `order.created` push a QR order sends. A repeated `send` with the old version is `CHECK_CHANGED`, never a second round.
