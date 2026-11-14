# Backend — POS API Proposal

# STATUS: PROPOSED — OWNER APPROVAL REQUIRED

**Author:** Agent 2 (Backend) · **Mode:** ANALYSIS-ONLY
**Date:** 2026-08-26 · **Inputs:** `01`, `02`, Agent 1's `POS_TO_BACKEND.md`

> Every contract in this document is **PROPOSED**. None of it exists. None of it
> has been written. Agent 1 must continue running against fakes until an entry
> appears in `BACKEND_TO_POS.md` marked `READY`.

---

## 0. Cross-cutting decisions

These apply to every endpoint below and are stated once.

| Concern | Proposal |
|---|---|
| **Route group** | `/api/pos/*`, a sibling of `/api/dashboard/*`. Rationale: the gate stack differs (terminal context, `feature:pos`), and burying it under `dashboard` would inherit gates that do not apply. Agent 1 expressed no preference. |
| **Gate stack** | `auth:jwt` → `role:RESTAURANT_ADMIN,RESTAURANT_STAFF` → `feature:pos` → `can:<pos capability>`. **`subscription.writable` deliberately omitted** — see `02` §POS-BE-006; owner to confirm. |
| **Tenant resolution** | `restaurant_id` from the token's `rid` claim via `TenantContext`. **Never from request input.** `RestaurantScope` does the rest. Cross-tenant → 404. |
| **Branch resolution** | `branch_id` in the body, validated `exists` **within the tenant**. A foreign branch id is a 404, not a 403. |
| **Money on the wire** | Integer minor units, field suffix `_minor`, `BIGINT`. Paired with `currency` (ISO) and `currency_exponent` (2, or 3 for KWD/BHD/OMR/JOD). **No JSON floats, ever.** Subject to the owner's decision in `02` §POS-BE-007. |
| **Timestamps** | ISO-8601 with offset. Client supplies `created_at` / `occurred_at`; the server additionally records `received_at`. Client times more than 24h in the future are rejected `422`. |
| **Idempotency** | Every write takes `client_transaction_id` (UUID v4) in the body **and** accepts `Idempotency-Key` as a header. Replay returns the **original 2xx body**, never `409`. See `04`. |
| **Pagination** | Existing dashboard convention (`?page`, `?per_page`, Laravel paginator envelope). POS reads are either single-object or terminal-scoped and small; only order history paginates. |
| **Errors** | `401` unauthenticated · `403` unentitled/uncapable · `404` cross-tenant or missing · `422` validation · `429` throttle. `409` is **never** used for a replayed idempotency key. |
| **Audit** | Every write calls `AuditLogger::record()`; every new model uses `Auditable`. |
| **Throttling** | `throttle:120,1` per authenticated user on writes — high enough for a rush, low enough to bound a runaway client. Sync batch endpoints are exempt and bounded by payload size instead. |

---

## 1. `POST /api/pos/orders` — create an order  · **POS-BE-006, 007, 008**

| Field | Value |
|---|---|
| **Requirement** | POS-BE-006 (+007 idempotency, +008 numbering) |
| **Purpose** | The single authoritative write that turns a cart into a priced, numbered, paid order. |
| **Auth** | `auth:jwt` |
| **Permission** | `feature:pos` + `can:pos.operate`; `pos.discount` / `pos.price_override` additionally required **if** the payload contains those adjustments |
| **Tenant** | token `rid` |
| **Branch** | body `branch_id`, validated within tenant |
| **Idempotency** | **Mandatory.** `client_transaction_id` unique per `(restaurant_id)` on `orders` |
| **Pagination** | n/a |

**Request DTO**

```jsonc
{
  "client_transaction_id": "3f2a…",        // uuid v4, required
  "terminal_id": "9b1c…",                  // uuid, required
  "shift_client_id": "7d4e…",              // uuid, required when shifts are live
  "branch_id": 12,
  "order_type": "dine_in",                 // must be in branch.supported_order_types
  "table_id": 34,                          // required when order_type = dine_in
  "customer_id": 88,                       // or customer_client_id for an offline-created customer
  "created_at": "2026-08-26T14:02:11+03:00",
  "priced_offline": true,
  "catalog_synced_at": "2026-08-26T09:00:00+03:00",
  "currency": "EGP",
  "lines": [{
    "client_line_id": "l1",
    "menu_item_id": 501,
    "variant_option_id": 9001,             // the is_variant selection
    "option_ids": [9101, 9102],
    "quantity": 2,
    "note": "no onions",
    "name_snapshot": "Beef Burger",        // fallback if the item was deleted mid-outage
    "unit_price_minor_snapshot": 12000,
    "discount": { "type": "percent", "value": 1000, "reason": "staff meal" },
    "price_override_minor": null
  }],
  "order_discount": { "type": "amount", "value_minor": 5000, "reason": "manager comp" },
  "payments": [
    { "tender_type_id": 1, "amount_minor": 30000, "reference": null },
    { "tender_type_id": 2, "amount_minor": 12400, "reference": "auth 004512" }
  ],
  "asserted_totals": {
    "subtotal_minor": 44000, "discount_minor": 5000, "tax_minor": 5460,
    "charges_minor": 0, "total_minor": 44460, "paid_minor": 42400, "change_minor": 0
  }
}
```

**Response DTO — `201` (and identically on replay, `200`)**

```jsonc
{
  "data": {
    "id": 9412,
    "client_transaction_id": "3f2a…",
    "invoice_number": "MAADI-2026-001042",
    "channel": "pos",
    "status": "COMPLETED",
    "settlement_status": "PAID",
    "created_at": "2026-08-26T14:02:11+03:00",
    "received_at": "2026-08-26T18:40:02+03:00",
    "currency": "EGP", "currency_exponent": 2,
    "totals": { "subtotal_minor": 44000, "discount_minor": 5000, "tax_minor": 5460,
                "charges_minor": 0, "total_minor": 44460, "paid_minor": 42400,
                "change_minor": 0, "balance_minor": 2060 },
    "totals_mismatch": false,
    "lines": [ /* server-priced, echoing client_line_id */ ],
    "payments": [ /* with server ids */ ],
    "warnings": []
  }
}
```

**Validation / behaviour**

1. **Re-price every line from `menu_item_id` + `variant_option_id` + `option_ids`**
   using `MenuItem::displayPricing()`, `defaultVariantOption()` and
   `orderedOptionGroups()`. Client prices are read **only for comparison**.
2. Validate that `option_ids` actually belong to groups attached to that item, and
   that `max_select` / `is_required` are respected. A cart that violates the
   option model is `422`.
3. If server totals ≠ `asserted_totals`: **still create the order** (money changed
   hands) and return `totals_mismatch: true` with both figures, so the POS raises
   its reconciliation dialog. This is deliberately not a rejection.
4. If `menu_item_id` no longer resolves (deleted during an outage): accept the line
   using `name_snapshot` + `unit_price_minor_snapshot`, set
   `menu_item_id = null`, and append a `warnings[]` entry. Never drop the line.
5. Discounts/overrides require the matching capability; without it → `403` naming
   the capability, before anything is written.
6. `order_type` must appear in the branch's `supported_order_types`.
7. Dine-in: reuse the exact `lockForUpdate()` discipline from
   `PublicOrderController::store()` — lock `TableVisit`, then the open `Order`.
8. Invoice number assigned **inside** the same transaction, **after** the
   idempotency check, so a replay never consumes a number.

**Existing services reused:** `MenuItem` pricing methods · `VariantPricingService`
· `TableVisitService` · `CustomerDirectory` · `NotificationService` (via
`app()->terminating()`) · `AuditLogger` · `OrderResource` · `TenantContext`.

**Database impact:** `orders` +`channel`, +`client_transaction_id`,
+`invoice_number`, +`terminal_id`, +`shift_id`, +`*_minor` totals;
`order_items` +`menu_item_id`, +discount/override columns; new `order_payments`.
See `05` §B1–B5.

**Breaking-change risk: LOW.** New route, new nullable columns, existing public
order path untouched. The one shared surface is `OrderResource` gaining keys —
additive, and both SPAs ignore unknown keys.

---

## 2. `GET /api/pos/orders/by-client-id/{uuid}` — recover a lost response · **POS-BE-007**

Auth `auth:jwt` · `can:pos.operate` · tenant from `rid` · **read-only, no idempotency**.
Returns the identical body as §1, or `404` if never received.
**Purpose:** the client timed out and cannot know whether the write landed. Without
this the POS must either risk a duplicate or lose the record.
**Existing reused:** none. **DB impact:** none beyond §1's index. **Risk: none.**

---

## 3. `GET /api/pos/config` — one cacheable configuration document · **POS-BE-013, 005, 001**

Auth `auth:jwt` · `can:pos.operate` · tenant from `rid` · `?branch_id=` optional.

```jsonc
{
  "data": {
    "synced_at": "2026-08-26T18:40:02+03:00",
    "restaurant": { "id": 3, "name_en": "…", "name_ar": "…", "currency": "EGP",
                    "currency_exponent": 2, "timezone": "Africa/Cairo",
                    "tax_registration_number": "203-456-789", "logo_url": "…" },
    "features": { "pos": true, "dine_in": true, "delivery": true },
    "branches": [{ "id": 12, "code": "MAADI", "name_en": "Maadi",
                   "supported_order_types": ["dine_in","takeaway","delivery"],
                   "is_open": true }],
    "tax_rules": [{ "id": 1, "name_en": "VAT", "name_ar": "ضريبة القيمة المضافة",
                    "rate_bp": 1400, "mode": "exclusive",
                    "scope": { "order_types": ["dine_in"], "branch_ids": [],
                               "category_ids": [], "menu_item_ids": [] } }],
    "charges": [{ "id": 1, "name_en": "Service", "kind": "percent",
                  "value_bp": 1200, "taxable": true,
                  "scope": { "order_types": ["dine_in"] } }],
    "tender_types": [{ "id": 1, "name_en": "Cash", "kind": "cash",
                       "opens_drawer": true, "is_active": true },
                     { "id": 2, "name_en": "Card", "kind": "external",
                       "requires_reference": true, "is_active": true }],
    "invoice_format": { "pattern": "{branch_code}-{YYYY}-{NNNNNN}", "reset": "yearly" },
    "policies": { "refund_approval_above_minor": 50000,
                  "allow_price_override": true, "allow_negative_stock": true }
  }
}
```

**Purpose:** one document, one `synced_at`, one thing to invalidate — exactly what
Agent 1 asked for. **Pagination:** none by design; this must stay small enough to
cache whole.
**Existing reused:** `PlanEntitlementService` (features), `BranchResource`,
`Restaurant` model, `CurrencyEnum` (exponent + timezone).
**DB impact:** new `tax_rules`, `charges`, `tender_types`; `restaurants.tax_registration_number`.
**Breaking-change risk: none** (new endpoint).

---

## 4. `GET /api/pos/catalog` — the sellable menu, POS-shaped · **POS-BE-003, 004, 012**

Auth `auth:jwt` · `can:pos.operate` (**not** `menu.view` — a cashier sells without
being allowed to edit the menu) · `?updated_since=` optional.

```jsonc
{ "data": { "categories": [...], "items": [...], "option_groups": [...] },
  "deleted": { "categories": [], "items": [], "option_groups": [] },
  "synced_at": "2026-08-26T18:40:02+03:00", "complete": true }
```

`items[]` entries carry `id`, names, `price_minor`, `discounted_price_minor`,
`sku`, `barcode`, `is_available`, `category_id`, `option_group_ids[]`.

**Decision worth flagging:** Agent 1 asked for `?resolve=full` on
`GET /api/dashboard/items` (POS-BE-003). I propose **both**: fix the dashboard
endpoint as requested *because it is an existing bug*, and additionally expose
this POS-shaped read. Reason — the dashboard resource is item-centric and repeats
each shared option group per item; a till caching 800 items would download the same
"Extras" group 800 times. This endpoint normalises groups once.
`complete: false` signals the client must fall back to a full pull (see `02`
§POS-BE-012 on the missing option-group tombstones).

**Existing reused:** `MenuItem::orderedOptionGroups()`, `withAutoOptionGroups()`,
`PublicMenuService` auto-group query, `SoftDeletes` for tombstones.
**DB impact:** `menu_items` +`sku` +`barcode`. **Risk: none** (new endpoint).

---

## 5. `POST /api/pos/terminals` — register / heartbeat · **POS-BE-009**

Auth `auth:jwt` · `can:pos.operate` · idempotent on `terminal_id` (upsert).
Request `{ terminal_id, name, platform: "windows"|"macos", app_version, branch_id }`
Response the terminal record incl. `is_revoked`.
**Purpose:** the client uses its `terminal_id` regardless; registration exists so a
manager can name, audit and (per BE-A04) revoke a till.
**DB impact:** new `pos_terminals`. **Risk: none.**

---

## 6. Shift endpoints · **POS-BE-009**

| Method | Endpoint | Permission | Idempotent on |
|---|---|---|---|
| `POST` | `/api/pos/shifts` | `pos.shift_open` | `client_transaction_id` |
| `GET` | `/api/pos/shifts/current?terminal_id=` | `pos.operate` | read |
| `POST` | `/api/pos/shifts/{clientId}/close` | `pos.shift_close` | `client_transaction_id` |
| `GET` | `/api/pos/shifts/{clientId}/report` | `pos.shift_close` | read |
| `POST` | `/api/pos/cash-movements` | `pos.cash_movement` | `client_transaction_id` |

Open request: `{ client_transaction_id, terminal_id, branch_id, opening_float_minor,
opened_at, denominations? }`.
Close request: adds `counted_cash_minor`, `closed_at`, `variance_reason?`,
`denominations?`. Server computes `expected_cash_minor` itself and returns both,
plus `variance_minor` — **the client's count is data, the expectation is the
server's**.

Report response (X/Z): gross sales, discounts, tax, charges, net, per-tender
breakdown, cash in/out, refunds, expected vs counted, variance, order count, voids.

**Server-enforced invariant:** at most one `OPEN` shift per `(terminal_id)`.
Enforced transactionally, since a partial unique index is not portable across
SQLite and PostgreSQL.
**Client-supplied `opened_at`/`closed_at` are authoritative for the shift; the
server stores `received_at` separately.**
**DB impact:** new `pos_shifts`, `pos_cash_movements`. **Risk: none.**

---

## 7. `POST /api/pos/refunds` — reversing record · **POS-BE-010**

Auth `auth:jwt` · `can:pos.refund` (+ supervisor approval above
`policies.refund_approval_above_minor`) · idempotent.

Request `{ client_transaction_id, order_id | order_client_transaction_id,
lines: [{ order_item_id, quantity, amount_minor? }], reason_code, reason_note?,
refund_payments: [{ tender_type_id, amount_minor }], approved_by_user_id?,
occurred_at, terminal_id, shift_client_id }`

Response: the refund record with **its own credit-note number** and a reference to
the original order, plus the original's recomputed `settlement_status`.

**Invariants:** never mutate or delete the original order; cumulative refunded
quantity per line may never exceed the sold quantity (server-authoritative);
`OrderStatus` is not extended — `settlement_status` is derived (see `02` §POS-BE-010).
**DB impact:** new `pos_refunds`, `pos_refund_lines`. **Risk: LOW** — `OrderResource`
gains a derived key.

---

## 8. `POST /api/pos/customers` — create from the till · **POS-BE-014**

Auth `auth:jwt` · `can:customers.create` (**new verb**) · idempotent on
`client_transaction_id`, and naturally safe on replay because the underlying call
is an upsert.
Request `{ client_transaction_id, name, phone, address?, latitude?, longitude?, note? }`
Response `CustomerResource`.
**Must call `CustomerDirectory::upsert()`** — not a second creation path — so
POS-created and diner-created customers deduplicate to one identity. Phone
normalisation is inherited and must not be reimplemented.
**DB impact:** none. **Risk: none.**

---

## 9. `POST /api/pos/sync/batch` — drain the queue · **POS-BE-006, 007, 009**

Auth `auth:jwt` · `can:pos.operate` · **the batch itself is not idempotent; each
operation inside it is.**

Request `{ terminal_id, operations: [{ op: "order"|"refund"|"cash_movement"|
"shift_open"|"shift_close"|"customer", client_transaction_id, payload: {…} }] }`
— maximum 100 operations per call.

Response `200` with a **per-operation result array**, each entry
`{ client_transaction_id, status: "created"|"duplicate"|"failed", data?, error? }`.

**The batch never fails as a whole.** One bad operation must not block the other
99 — that is precisely the state that loses a real transaction. Ordering
dependencies (a shift must exist before its orders) are resolved server-side by
processing in dependency order, not by trusting array order.
**Risk: none** (new endpoint). Full semantics in `04`.

---

## 10. Modifications to **existing** endpoints

Only three, all additive. Each is a shared surface, so each is listed with its
blast radius.

| Requirement | Endpoint | Change | Callers affected | Risk |
|---|---|---|---|---|
| **POS-BE-005** | `GET /api/dashboard/branches` | `BranchResource` gains `code` and `supported_order_types` (emit `[]`, never `null`) | web SPA branch list | **None** — additive keys |
| **POS-BE-003** | `GET /api/dashboard/items` | new `?resolve=full` injecting auto-applied option groups | none by default | **None** — opt-in |
| **POS-BE-004** | `POST`/`PUT /api/dashboard/items`, import/export | accept + emit `sku`, `barcode` | web SPA item form, CSV/XLSX | **LOW** — new optional columns; export gains two columns, which changes a file shape scripts may parse |

**No existing endpoint changes behaviour for an existing caller.**
`PublicOrderController` is not touched at all.

---

## 11. What is deliberately *not* proposed

- **No payment processing.** Card payments are recorded as taken on a standalone
  bank terminal (`tender_type.kind = external`, plus a reference string). No PAN,
  no track data, no PCI scope.
- **No inventory.** Out of scope; see `01` §12.
- **No parallel POS order table.** POS orders are `orders` rows with `channel = 'pos'`.
- **No new authentication system.** POS signs in through the existing
  `POST /api/auth/login`.
- **No change to `OrderStatus`.** Its invariant stays intact; settlement is derived.
- **No client-proposed invoice numbers.** Guaranteed collisions across tills.

---

> **BACKEND IMPLEMENTATION HAS NOT STARTED. OWNER APPROVAL IS REQUIRED.**
