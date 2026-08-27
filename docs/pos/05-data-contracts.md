# 05 — Data Contracts

**Author:** Agent 1 (Flutter POS Desktop) · **Date:** 2026-08-25

What the POS expects for every shared entity. Each block states its **source of
truth** and its **status**:

- **EXISTS** — the backend already returns this shape; the POS parses it as-is.
- **EXTEND** — the field exists in the database but is not exposed, or the resource
  needs one addition.
- **PROPOSED** — no server representation exists. Client-side shape only until the
  matching `POS-BE-xxx` is `READY`.

**Reuse rule.** Where the backend already has a shape, the POS adopts it verbatim,
including its naming (`name_ar`/`name_en`, snake_case, ISO-8601 timestamps).
Divergence would be a translation layer with no payer.

**Money rule.** On the wire, money is whatever the backend sends today
(`decimal:2` rendered as a string or number). **In the Flutter app, every monetary
value is parsed immediately into `Money` — an integer count of minor units plus a
currency.** Doubles never survive past the parse boundary. Where the POS proposes
a new contract it asks for `*_minor` integers (`POS-BE-007`).

---

## 1. Restaurant — EXISTS

Source: `UserResource.restaurant` (`RestaurantResource`) at login / `auth/me`.

```jsonc
{
  "id": 12, "name_ar": "…", "name_en": "…", "slug": "hellokid",
  "logo_url": "/storage/…", "cover_image_url": "/storage/…",
  "phone": "+20…", "whatsapp_number": "+20…", "address": "…",
  "brand_color": "#C81E1E", "secondary_color": "#1F2937",
  "menu_layout": "photo",                 // photo|list|grid
  "default_language": "ar", "bilingual": true,
  "currency": "EGP", "currency_symbol": "EGP",
  "timezone": "Africa/Cairo",
  "features": { "system_ordering": true, "table_management": true, … }
}
```

POS use: theme seed (`brand_color`), locale default, currency + exponent, day
boundary for shift/report dates, feature gating.

**Missing for POS:** tax registration number (required on a receipt in EG/KSA).
Client-side optional field until `POS-BE-013`.

## 2. User / Cashier — EXISTS

Source: `UserResource`.

```jsonc
{
  "id": 88, "name": "Sara", "username": "sara", "email": null,
  "role": "RESTAURANT_STAFF", "restaurant_id": 12, "status": "ACTIVE",
  "is_owner": false, "role_id": 4,
  "role_name": "Cashier", "role_name_ar": "كاشير",
  "capabilities": ["live.view","orders.view","orders.update","menu.view", …]
}
```

`email` being nullable and `username` being unique per tenant is what makes
email-less cashier accounts work **today**.

## 3. Permission — EXISTS (needs POS verbs)

`capabilities[]` is a flat list of `resource.verb` strings from
`App\Enums\TenantCapability`. The POS treats it as an opaque set — it never
derives one capability from another, because the server already expands implied
`*.view` on save (`TenantCapability::expand()`).

POS verbs requested in **`POS-BE-002`**:

```
pos.operate  pos.discount  pos.price_override  pos.void
pos.refund   pos.shift.open  pos.shift.close  pos.cash_movement  pos.reprint
```

Client rule: **absence of a capability hides the control; it never fabricates
authority.** The server is the gate.

## 4. Branch — EXTEND (`POS-BE-005`)

Source: `GET /api/dashboard/branches` → `BranchResource`. Exists:

```jsonc
{ "id": 3, "name_ar": "…", "name_en": "…", "address": "…", "phone": "…",
  "whatsapp_number": "…", "opening_hours": "…", "business_hours": {…},
  "map_url": "…", "latitude": 30.04, "longitude": 31.23,
  "geofence": null, "geofence_enabled": false, "require_branch_wifi": false,
  "is_open": true, "is_active": true, "sort_order": 1 }
```

**Add** (column exists on `branches`, simply not serialised):

```jsonc
{ "supported_order_types": ["dine_in","takeaway","delivery"], "code": "MAADI" }
```

Without it the POS cannot honour POS-R071 and would have to show every order type.

## 5. Category — EXISTS

Source: `GET /api/dashboard/categories` → `CategoryResource`.

```jsonc
{ "id": 5, "restaurant_id": 12, "name_ar": "…", "name_en": "…",
  "description_ar": "…", "description_en": "…", "image_url": "/storage/…",
  "display_order": 2, "is_active": true,
  "availability_hours": null,          // null = unrestricted
  "items_count": 24 }
```

POS use: the rail, plus category→kitchen-printer routing (local config keyed by
`category.id`).

## 6. Menu item — EXTEND (`POS-BE-003`, `POS-BE-004`)

Source: `GET /api/dashboard/items` → `MenuItemResource`.

```jsonc
{
  "id": 301, "restaurant_id": 12, "category_id": 5,
  "name_ar": "برجر", "name_en": "Burger",
  "description_ar": "…", "description_en": "…",
  "price": "85.00", "discounted_price": null,
  "image_url": "/storage/…",
  "is_available": true, "is_featured": false, "display_order": 3,
  "option_groups": [ /* §7 */ ]
}
```

Two documented behaviours the POS reproduces exactly (see `01` §2.3):

- `price` / `discounted_price` here are **already** `displayPricing()` — i.e. the
  default variant's price when the item is variant-priced. The POS must not
  re-derive them from the columns.
- `effectivePrice = discounted_price ?? price`.

**Add:**

| Field | Why | Request |
|---|---|---|
| `option_groups` including `apply_scope`-auto groups | Restaurant-wide extras are invisible on this endpoint today | `POS-BE-003` |
| `sku`, `barcode` | Nothing to scan against | `POS-BE-004` |

## 7. Option group & option — EXISTS

Nested in `MenuItemResource.option_groups`:

```jsonc
{
  "id": 44, "is_global": true,
  "name_en": "Size", "name_ar": "الحجم",
  "is_required": true,
  "is_variant": true,           // ← REPLACES the item price; never additive
  "max_select": 1,
  "options": [
    { "id": 91, "name_en": "Medium", "name_ar": "وسط",
      "price": "85.00", "discounted_price": null, "is_available": true },
    { "id": 92, "name_en": "Large",  "name_ar": "كبير",
      "price": "110.00", "discounted_price": "99.00", "is_available": true }
  ]
}
```

Client invariants, enforced in the cart engine and unit-tested:

1. At most one group per item may be `is_variant`; the first available option of
   the first such group is pre-selected.
2. A variant option **replaces** `line.base`. Non-variant options **add** to it.
3. `max_select == 1` → radio; `> 1` → checkbox capped at `max_select`;
   `is_required` → at least one selection before the line can be added.
4. `is_available == false` → shown, disabled, never silently dropped (a cashier
   must be able to tell a customer "we're out of Large").

## 8. Combo — EXISTS (deferred)

`GET /api/dashboard/combos` → `ComboResource` (`base_price`, `groups[].items[].extra_price`).
Parsed and cached from Phase 3; **not sellable in v1** — combo pricing has its own
rules and is scheduled with the advanced phase.

## 9. Customer — EXISTS (read) / PROPOSED (write, `POS-BE-014`)

Read: `GET /api/dashboard/customers` → `CustomerResource`.

```jsonc
{ "id": 700, "name": "Ahmed", "phone": "+201000000000",
  "orders_count": 12, "last_order_at": "2026-08-20T18:04:11+00:00",
  "addresses": [ { "id": 9, "label": "Home", "address": "…",
                   "latitude": 30.0, "longitude": 31.2 } ] }
```

Write (proposed): `POST /api/pos/customers` `{name, phone, address?, note?}` →
the same resource. Phone normalisation must match the backend's
`NormalizesPhoneNumbers` so POS and dashboard resolve to one identity.

## 10. Tax rule — PROPOSED (`POS-BE-013`)

No tax model exists anywhere in the backend today. The POS defines the shape it
needs; the server must become the author of it.

```jsonc
{
  "id": "vat-14", "name_en": "VAT", "name_ar": "ضريبة القيمة المضافة",
  "rate_bp": 1400,              // basis points — integer, no float rates
  "mode": "exclusive",          // exclusive|inclusive
  "applies_to": "order",        // order|category|item
  "category_ids": [], "item_ids": [],
  "applies_to_charges": true,
  "order_types": ["dine_in","takeaway"],
  "branch_ids": [],             // empty = all branches
  "is_active": true
}
```

Until `POS-BE-013` is `READY` the POS reads tax rules from **read-only local
device config**, and every receipt produced that way is honest about it. Tax is
never invented by the client at runtime.

## 11. Discount — PROPOSED (client-authored)

A cashier action, not a catalog entity. `options.discounted_price` is a *menu*
discount and is unrelated.

```jsonc
{ "scope": "line",              // line|order
  "type": "percent",            // percent|fixed
  "value_bp": 1000,             // percent → basis points
  "value_minor": null,          // fixed → minor units
  "reason_code": "staff_meal", "reason_note": "…",
  "applied_by": 88, "requires_capability": "pos.discount" }
```

Sent with the order; the server must re-validate the resulting amount
(`POS-BE-006`), because a client-authored discount is exactly the field an
attacker would forge.

## 12. Additional charge — PROPOSED (`POS-BE-013`)

```jsonc
{ "code": "service", "name_en": "Service", "name_ar": "خدمة",
  "type": "percent", "value_bp": 1200, "value_minor": null,
  "taxable": true, "order_types": ["dine_in"], "is_active": true }
```

## 13. Tender type — PROPOSED (`POS-BE-013`)

```jsonc
{ "code": "cash", "name_en": "Cash", "name_ar": "نقدي",
  "kind": "cash",              // cash|card|external|other
  "opens_drawer": true, "requires_reference": false,
  "allows_change": true, "is_active": true, "sort_order": 1 }
```

`kind: "external"` is how v1 records a card taken on a standalone bank terminal
(assumption A-3) without pretending to be a processor integration.

## 14. Order — PROPOSED (`POS-BE-006`)

The envelope the POS submits. Every money field is **integer minor units**.

```jsonc
{
  "client_transaction_id": "9f1c…",     // idempotency key, immutable
  "terminal_id": "T-8b31…",
  "shift_client_id": "4ac2…",
  "branch_id": 3,
  "order_type": "dine_in",
  "table_id": 17,
  "customer_id": 700,
  "channel": "pos",                      // distinguishes POS from QR revenue
  "currency": "EGP", "currency_exponent": 2,
  "note": "no onions",
  "created_at": "2026-08-25T14:03:11+03:00",   // CLIENT time; may be hours old
  "priced_offline": true,
  "catalog_synced_at": "2026-08-25T09:00:00+03:00",

  "lines": [{
    "line_id": "L1",
    "menu_item_id": 301,
    "variant_option_id": 92,
    "option_ids": [130, 131],
    "quantity": 2,
    "note": "extra crispy",
    "name_snapshot": "Burger",           // survives an item deleted mid-outage
    "unit_base_minor": 9900,
    "modifiers_minor": 1500,
    "discount": { "type": "percent", "value_bp": 1000, "reason_code": "…" },
    "price_override": { "from_minor": 9900, "to_minor": 8500, "reason": "…" },
    "line_total_minor": 20520
  }],

  "order_discount": { "type": "fixed", "value_minor": 2000, "reason_code": "…" },
  "charges": [{ "code": "service", "amount_minor": 2462 }],
  "tax_lines": [{ "id": "vat-14", "rate_bp": 1400, "base_minor": 20982,
                  "amount_minor": 2937, "mode": "exclusive" }],

  // ASSERTION, not instruction. The server recomputes and must agree (POS-R080).
  "asserted_totals": {
    "subtotal_minor": 20520, "discount_minor": 2000, "charges_minor": 2462,
    "tax_minor": 2937, "rounding_minor": 0, "total_minor": 23919
  }
}
```

Response the POS needs back:

```jsonc
{ "data": {
    "id": 5521,
    "client_transaction_id": "9f1c…",
    "invoice_number": "MAADI-2026-001042",     // authoritative (POS-BE-008)
    "code": "ORD-5521",
    "status": "open",
    "totals": { "subtotal_minor": …, "total_minor": … },   // server-computed
    "created_at": "2026-08-25T11:03:14+00:00" } }
```

**Replay of the same `client_transaction_id` must return this identical body,
not a 409** — that is what makes the ambiguous-timeout retry safe.

## 15. Order round — EXISTS (model) / PROPOSED (POS write)

`OrderRound` already models a kitchen-visible submission round
(`order_id, menu_session_id, sequence, total, note, submitted_at`).
The POS sends `{client_transaction_id, order_client_id, line_ids[], note}` and
the server assigns `sequence`.

## 16. Order item — EXTEND (`POS-BE-006`)

`order_items` currently has **no `menu_item_id`** — only `name`. Server-side
re-pricing, honest product reporting and stock deduction are all impossible
without it. This is the single highest-leverage backend change in the whole
programme, and it improves the *existing* product independently of the POS.

## 17. Payment — PROPOSED (`POS-BE-006` / `POS-BE-007`)

```jsonc
{ "client_transaction_id": "b72e…",       // its own key, per tender
  "order_client_id": "9f1c…",
  "tender_code": "cash",
  "amount_minor": 20000,
  "tendered_minor": 25000, "change_minor": 5000,
  "reference": null,
  "shift_client_id": "4ac2…", "terminal_id": "T-8b31…",
  "created_at": "2026-08-25T14:05:02+03:00" }
```

`change_minor` is **derived and recorded, never a negative payment row.**

## 18. Refund — PROPOSED (`POS-BE-010`)

A reversing counter-record. Never an edit or deletion of the original.

```jsonc
{ "client_transaction_id": "c31a…",
  "original_order_id": 5521,
  "lines": [{ "original_line_id": "L1", "quantity": 1, "amount_minor": 10260 }],
  "reason_code": "wrong_item", "reason_note": "…",
  "refund_tender_code": "cash", "total_minor": 10260,
  "approved_by": 88, "shift_client_id": "4ac2…", "terminal_id": "T-8b31…" }
```

## 19. Shift — PROPOSED (`POS-BE-009`)

```jsonc
{ "client_transaction_id": "4ac2…",
  "terminal_id": "T-8b31…", "branch_id": 3,
  "opened_by": 88, "opened_at": "2026-08-25T08:00:00+03:00",
  "opening_float_minor": 50000,
  "closed_by": 88,  "closed_at": "2026-08-25T23:30:00+03:00",
  "expected_cash_minor": 412500, "counted_cash_minor": 412000,
  "variance_minor": -500, "variance_reason": "…",
  "denominations": [ { "value_minor": 20000, "count": 15 } ],
  "status": "closed" }
```

`opened_at` / `closed_at` are **client-supplied**, because an offline shift that
syncs at 23:45 must not record 23:45 as its opening time.

## 20. Cash movement — PROPOSED (`POS-BE-009`)

```jsonc
{ "client_transaction_id": "77de…", "shift_client_id": "4ac2…",
  "direction": "out", "amount_minor": 15000,
  "reason": "supplier_payment", "reference": "INV-9912",
  "created_by": 88, "created_at": "2026-08-25T12:11:00+03:00" }
```

## 21. Terminal / device — PROPOSED (`POS-BE-009`)

```jsonc
{ "terminal_id": "T-8b31…",      // client-generated UUID, stable per install
  "name": "Front Till 1", "branch_id": 3,
  "platform": "windows", "app_version": "1.0.0+1",
  "last_seen_at": "2026-08-25T14:05:02+03:00" }
```

The client generates and uses `terminal_id` **regardless** of whether a server
registry exists, so adopting one later requires no data migration on the till.

## 22. Sync operation — client-only

Never crosses the wire as a document; it *is* the local queue row (`03` §3).
Included here because it is part of the POS's own contract surface:

```dart
class SyncOperation {
  final int id;                    // causal order
  final String clientTransactionId;// idempotency key
  final AggregateType aggregateType;
  final String aggregateId;        // dependency grouping
  final SyncOp operation;          // create | update | void
  final String endpoint;
  final String payload;            // FROZEN at enqueue, never regenerated
  final int attempts;
  final DateTime nextAttemptAt;
  final SyncState state;           // pending | inFlight | done | dead
  final String? lastError;
  final int? lastStatus;
}
```

---

## Contract change protocol

1. No contract in this file changes silently. A change means a new
   `POS-BE-xxx` entry, or a versioned amendment to an existing one, in
   `docs/coordination/POS_TO_BACKEND.md`.
2. A **PROPOSED** shape is a request, not an agreement. Agent 1 codes against it
   behind a repository interface with a fake implementation, and treats it as
   production-ready only when Agent 2 marks the matching requirement `READY` in
   `BACKEND_TO_POS.md`.
3. Where the backend already has a shape, the POS adopts it verbatim rather than
   proposing a nicer one.
