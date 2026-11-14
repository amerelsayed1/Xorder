# API — pos-incoming-cloud-orders

Status: **S4 as built 2026-11-09 (cloud, not deployed)**. Contract text and error codes: `apps/xorder-cloud/docs/coordination/BACKEND_TO_POS.md` §POS-BE-033 (PROPOSED — the POS integrates only once READY). S1/S2/S5–S9 endpoints are not built and not documented here.

| Route (device token) | Body | Success | Errors |
|---|---|---|---|
| `GET /api/pos/incoming?cursor=` | header `X-App-Version` optional | `{data:{events,cursor,has_more}}`, ETag/304 | `422 INVALID_CURSOR`, `401/403` device errors |
| `POST /api/pos/online-orders/{order}/accept` | `client_request_id` uuid | order event, `state:"accepted"` | `404 NOT_FOUND`, `403 ONLINE_ORDERS_NOT_ON_POS`, `409 ALREADY_ACCEPTED/ALREADY_REJECTED/ORDER_NOT_PENDING` |
| `POST /api/pos/online-orders/{order}/reject` | `client_request_id` uuid, `reason` ≤255 | `state:"rejected"` | same |
| `POST /api/pos/table-requests/{billRequest}/handled` | `client_request_id` uuid | `state:"handled"` | `404`, `403`, `409 ALREADY_HANDLED` |
| `GET /api/public/restaurants/{slug}/orders/{id}/status` (existing) | — | `{data:{status[,rejected:true]}}` — `rejected` only when a till rejected it; the reason text is deliberately not public | unchanged |
