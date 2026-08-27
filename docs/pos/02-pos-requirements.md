# 02 — POS Requirements

**Author:** Agent 1 (Flutter POS Desktop) · **Date:** 2026-08-25
**Targets:** Windows 10+ and macOS 13+. Desktop-first, not a stretched phone UI.

Requirement IDs are `POS-Rxxx`. Backend-dependent requirements name the
`POS-BE-xxx` they wait on; everything else is buildable by Agent 1 alone.

---

## 0. Product framing

A cashier's shift is measured in seconds per order. Every requirement below is
judged against one question: **does it cost or save keystrokes at the till?**

Three non-negotiables that shape everything else:

1. **The till never stops selling.** Network loss degrades features, never the
   sale path (§7).
2. **The server owns money.** The client computes a quote so the cashier sees a
   number instantly; the server confirms it. A mismatch is a visible error, never
   a silent overwrite (§4.6).
3. **Nothing is lost.** A transaction that a cashier confirmed exists in durable
   local storage before the UI moves on (§7.2).

---

## 1. Login & session

| ID | Requirement | Notes |
|---|---|---|
| POS-R001 | **Device setup** on first run: API base URL + restaurant slug + branch + terminal name. Persisted; changeable only by a user holding `settings.update`. | Slug is required — `AuthController::resolveLoginTenantId()` needs it (Host-subdomain fallback is meaningless from a desktop app). |
| POS-R002 | **Login** with username + password against `POST /api/auth/login` with `{username, password, restaurant: <slug>}`. Usernames are unique per tenant and email is optional, so email-less cashier accounts work today. | Reuses existing API. |
| POS-R003 | **Session persistence** across app restarts. Token in the OS secure store (Keychain / DPAPI), never in a plain file. | |
| POS-R004 | **Permission loading** from `UserResource.capabilities[]` at login and on every `GET /api/auth/me`. Client gating is UX-only; the server stays authoritative. | Existing field. |
| POS-R005 | **Branch selection.** If the terminal is bound to a branch (POS-R001) that branch is used and the picker is skipped. Otherwise pick from `GET /api/dashboard/branches`. | |
| POS-R006 | **Cashier identity** shown persistently in the shell (name + role) and stamped on every order, payment and cash movement. | |
| POS-R007 | **Fast user switch / lock screen.** Lock to a PIN-style re-entry without tearing down the session, so a shared till doesn't re-sync the catalog on every handover. | UI-only in v1; PIN is a local re-auth of the *same* session, not a second credential. |
| POS-R008 | **Device identification.** A stable per-install `terminalId` (UUID v4, generated once, stored locally) sent on every write as `X-POS-Terminal`. | Server-side registry is `POS-BE-009`; the client id is generated regardless so it can be adopted later. |
| POS-R009 | **Token expiry while offline** must not discard queued work. The app enters a "sync blocked — sign in again" state and keeps selling. | Depends on `POS-BE-011`. |

---

## 2. Main selling screen

Three-pane desktop layout, resizable, minimum window **1280×800**.

```
┌──────────────┬──────────────────────────────────┬──────────────────────┐
│ CATEGORIES   │  SEARCH / BARCODE                │  CART                │
│  (rail)      │  ────────────────────────────────│  order type · table  │
│              │                                  │  ──────────────────  │
│  All         │   ┌────┐ ┌────┐ ┌────┐ ┌────┐    │  line items          │
│  Burgers     │   │    │ │    │ │    │ │    │    │  qty · price · notes │
│  Drinks      │   └────┘ └────┘ └────┘ └────┘    │  ──────────────────  │
│  Desserts    │   ┌────┐ ┌────┐ ┌────┐ ┌────┐    │  subtotal            │
│              │   │    │ │    │ │    │ │    │    │  discount · tax      │
│              │   └────┘ └────┘ └────┘ └────┘    │  charges             │
│              │                                  │  ══ TOTAL ══         │
│  [Hold] [Resume]                                │  [ CHECKOUT  F12 ]   │
└──────────────┴──────────────────────────────────┴──────────────────────┘
```

| ID | Requirement |
|---|---|
| POS-R020 | Category rail from `GET /api/dashboard/categories`, honouring `display_order`, `is_active` and `availability_hours` (a category outside its serving window is visibly closed, not hidden — the cashier must be able to explain why). |
| POS-R021 | Product grid from `GET /api/dashboard/items`. Photo tile or dense text tile, following `restaurant.menu_layout`. Unavailable items are shown greyed and unselectable, never removed — cashiers navigate by muscle memory and a shifting grid destroys that. |
| POS-R022 | **Search** filters as you type across `name_ar`, `name_en` and (once it exists) SKU/barcode. Focus is on the search box by default; typing anywhere that isn't a text field routes there. Arabic and English match simultaneously regardless of UI language. |
| POS-R023 | **Barcode lookup**: a scanner is a keyboard. Input ending in `Enter` that matches a barcode adds the item directly to the cart with qty 1 and no dialog. Depends on `POS-BE-004`; until then the same path resolves against a local `sku` field that is always empty. |
| POS-R024 | **Product selection.** An item with no required option group and no variant group is added on a single click. Anything else opens the configuration dialog. |
| POS-R025 | **Variants.** The first *available* option of the first `is_variant` group is pre-selected and **replaces** the item price (it does not add to it) — reproducing `MenuItem::defaultVariantOption()` / `displayPricing()` exactly. |
| POS-R026 | **Modifiers / add-ons.** Honour `is_required`, `max_select`, per-option `price`/`discounted_price` and `is_available`. Options resolved from all three application paths — inline, shared pivot, and `apply_scope` auto-apply (`POS-BE-003`). |
| POS-R027 | **Quantity** editable inline (+/−, direct entry, keypad). Fractional quantities are out of scope for v1. |
| POS-R028 | **Per-line note** free text, sent to the kitchen. |
| POS-R029 | **Remove line** with undo. A removed line after the round was fired is a *void*, not a delete (§9). |
| POS-R030 | **Price override**, gated on `pos.price_override`. Records the original price, the new price and a reason. Always audited. |
| POS-R031 | **Line discount** — percentage or fixed amount, gated on `pos.discount`. |
| POS-R032 | **Order discount** — percentage or fixed amount, gated on `pos.discount`. Applied after line discounts, before tax. |
| POS-R033 | **Additional charges** — service charge and delivery fee, configuration-driven, never hardcoded per customer. |
| POS-R034 | **Hold order** parks the cart locally with a label (table, customer or free text). Survives app restart. |
| POS-R035 | **Resume order** from the held list. |
| POS-R036 | **Cancel order** clears the cart, gated on `pos.void` once anything has been fired to the kitchen; free before that. |
| POS-R037 | **Table selection** for dine-in, rendered from `GET /api/dashboard/tables/live` — occupancy, active orders and open bill requests are already in that payload. |
| POS-R038 | **Send to kitchen** without settling, creating an order round. Depends on `POS-BE-006`. |

---

## 3. Desktop UX

| ID | Requirement |
|---|---|
| POS-R050 | Full keyboard operation. Nothing in the sale path requires a mouse. |
| POS-R051 | Global shortcuts (defaults, remappable in settings): `F1` help · `F2` search focus · `F3` customer · `F4` order type · `F5` hold · `F6` resume · `F7` line discount · `F8` order discount · `F9` open shift/cash drawer · `F10` reprint last receipt · `F12` checkout · `Enter` confirm · `Esc` close dialog / clear search · `Del` remove line · `+`/`-` qty · `Ctrl+F` search · `Ctrl+L` lock. |
| POS-R052 | Every dialog closes on `Esc` and confirms on `Enter`. No dialog traps focus without an escape. |
| POS-R053 | Numeric keypad workflow: amount entry accepts a bare number stream; `Enter` commits. Arabic-Indic digits (٠١٢…) normalise to ASCII on input — the same problem `packages/ui/src/enDigits.js` solves on the web. |
| POS-R054 | Resizable window, minimum 1280×800, size and position restored across restarts. |
| POS-R055 | High-DPI correct on Retina and 150%/200% Windows scaling. |
| POS-R056 | Touch-friendly hit targets (≥44 logical px) so the same build runs on a touch Windows terminal. |
| POS-R057 | Full RTL. Arabic mirrors the whole layout — cart pane moves to the left. Directional insets only. |
| POS-R058 | Visible connectivity + sync status in the shell at all times (§7.6). |
| POS-R059 | No destructive action is a single unconfirmed click: void, refund, price override and shift close all confirm. |

---

## 4. Order types & cart calculation

### 4.1 Order types

| ID | Requirement |
|---|---|
| POS-R070 | Supported types: `dine_in`, `takeaway`, `pickup`, `delivery`. Only types enabled for the branch are shown. |
| POS-R071 | The enabled set comes from `branches.supported_order_types` — a column that exists but is not currently exposed (`POS-BE-005`). Never hardcoded, never customer-conditional. |
| POS-R072 | `dine_in` requires a table; `delivery` requires a customer with an address. Enforced before checkout. |

### 4.2 Calculation model

Computed by a **pure Dart engine with no Flutter imports**, unit-tested
independently of any UI (`docs/pos/04-flutter-pos-architecture.md` §5).

```
line.base           = variantOption?.effectivePrice ?? item.effectivePrice
line.modifiers      = Σ option.effectivePrice          (variant options excluded)
line.gross          = (base + modifiers) × qty
line.discount       = pct → gross × p/100  |  fixed → min(amount × qty, gross)
line.net            = gross − discount
                      ────────────────────────────────
order.subtotal      = Σ line.net
order.discount      = pct → subtotal × p/100 | fixed → min(amount, subtotal)
order.taxableBase   = subtotal − order.discount
order.charges       = Σ charge (percent of taxableBase, or fixed)
order.tax           = Σ taxLine  over (taxableBase + taxableCharges)
order.total         = taxableBase + charges + exclusiveTax + rounding
                      ────────────────────────────────
order.paid          = Σ payment.amount
order.remaining     = max(0, total − paid)
order.change        = max(0, paid − total)
```

`effectivePrice = discounted_price ?? price` — mirroring the menu, where
`discounted_price` when set *is* the price.

| ID | Requirement |
|---|---|
| POS-R073 | **Integer minor units everywhere.** All money is `int` in the currency's smallest unit. Doubles never touch the money path. Currency exponent is per-currency (EGP/SAR/AED/QAR/USD/EUR/GBP = 2; **KWD/BHD/OMR/JOD = 3** — all present in `App\Enums\CurrencyEnum`). |
| POS-R074 | Rounding is **half-up at the last step only**; intermediate values keep full integer precision. Percentage discounts and taxes round once, at the point they become a money amount. |
| POS-R075 | Tax supports **inclusive and exclusive** modes. Inclusive tax is extracted from the total for display and does not increase it. |
| POS-R076 | Multiple tax lines per order, each with a name and rate, retained as a breakdown for the receipt and for later e-invoicing. |
| POS-R077 | Discount can never make a line or an order negative. Clamped at zero, and the clamp is visible to the cashier. |
| POS-R078 | Every calculation is deterministic and side-effect-free. Same cart in → same totals out, no clock, no locale, no I/O. |
| POS-R079 | Unit tests cover: variant replacement, modifier stacking, per-line vs order discount ordering, inclusive vs exclusive tax, multi-tax, rounding at the boundary, split-payment change, over-discount clamp, and 3-decimal currencies. |

### 4.6 Client vs server authority

| ID | Requirement |
|---|---|
| POS-R080 | The client total is a **quote**. The order envelope sends item ids + option ids + quantities + cashier-applied adjustments, and *also* the client's computed totals — as an assertion, not an instruction. |
| POS-R081 | If the server returns different totals, the POS shows a blocking reconciliation dialog with both figures. It never silently adopts either. |
| POS-R082 | Offline orders are priced from the cached catalog, and are flagged as such, so a price change during the outage is visible at reconciliation rather than hidden. |

---

## 5. Payments

| ID | Requirement |
|---|---|
| POS-R090 | Tender types are **data, not an enum in the UI**: `cash`, `card`, and tenant-defined methods. v1 records card as an external-terminal tender with an optional reference — no processor integration. |
| POS-R091 | **Split payment**: any number of tenders on one order, each with its own amount and reference. |
| POS-R092 | **Partial payment** leaves a remaining balance; the order stays open and settleable later. |
| POS-R093 | **Change due** is computed and displayed prominently for cash, and is never recorded as a negative payment. |
| POS-R094 | Quick-cash buttons (exact, next 5/10/50/100) derived from the total, in the tenant's currency. |
| POS-R095 | **Double-tap protection.** Every payment carries a client-generated idempotency key reused verbatim across retries (`POS-BE-007`). |
| POS-R096 | Payment succeeds locally the moment it is durably written, whether or not the server has acknowledged. The sync state is separate from the payment state and both are visible. |

---

## 6. Receipts & printing

| ID | Requirement |
|---|---|
| POS-R100 | Receipt shows: restaurant (name, logo, tax id, address, phone) · branch · invoice number · internal reference · cashier · terminal · date/time in the restaurant's timezone · customer (when present) · table/order type · line items with qty, unit price, modifiers and line total · discount lines · tax breakdown · additional charges · payment lines with tender and reference · total · paid · change. |
| POS-R101 | The **invoice number** shown is authoritative once assigned by the server. An unsynced offline receipt prints its provisional terminal-scoped reference and is clearly marked provisional (`POS-BE-008`). |
| POS-R102 | Receipt language follows the till language; a bilingual receipt is a per-tenant setting. |
| POS-R103 | **Reprint** any receipt from order history, gated on `pos.reprint`, and audited (`reprint #n`). |
| POS-R104 | **Kitchen ticket** printing per order round, routed per category to a printer (kitchen/bar/grill). Category→printer routing is local device config in v1. |
| POS-R105 | Printing sits behind a `PrinterService` abstraction. Implementations: network ESC/POS (v1), OS spooler, USB/serial ESC/POS, and a no-op preview. Checkout logic never references a printer implementation. |
| POS-R106 | **Print failure never blocks the sale.** A failed print is a queued, retryable job with a visible banner and a manual "print again" — the order is already committed. |
| POS-R107 | Printer selection and configuration in settings, with a test-print button. |
| POS-R108 | Cash drawer kick via the receipt printer on cash tender and on `F9`, gated on `pos.operate`. |

---

## 7. Offline-first

Full design in `docs/pos/03-offline-strategy.md`. Requirements here.

| ID | Requirement |
|---|---|
| POS-R120 | The **entire sale path works offline**: browse, search, configure, cart, discount, tax, checkout, tender, receipt print. |
| POS-R121 | Catalog, categories, option groups, branch config, tax config, tender types, customers and the current shift are cached locally and usable with no network. |
| POS-R122 | Every locally-created transaction carries a stable `clientTransactionId` (UUID v4), generated once at creation and **reused verbatim on every retry, forever**. |
| POS-R123 | A confirmed transaction is durable **before** the UI advances. No transaction exists only in memory at any point. |
| POS-R124 | Queued operations sync in causal order per aggregate; a failed operation blocks its own aggregate's successors, not the whole queue. |
| POS-R125 | Retry with exponential backoff and jitter. Permanent failures (4xx that are not 401/408/409/429) move to a **dead-letter** state that is surfaced to a supervisor, **never** silently dropped. |
| POS-R126 | Server acknowledgment binds the server id and the authoritative invoice number back onto the local record. |
| POS-R127 | Conflict rule: for money, **the server always wins**; for catalog, the server always wins; the local record is retained with the divergence recorded so it can be reviewed rather than lost. |
| POS-R128 | Connectivity and sync status are always visible: online/offline, pending count, last successful sync, dead-letter count. Clicking opens the queue. |
| POS-R129 | Closing the app with a non-empty queue warns and requires confirmation. |
| POS-R130 | A supervisor can inspect, retry and (with `pos.void` + a reason) reverse a dead-lettered transaction — a reversing counter-record, never a destructive delete. |

---

## 8. Shift management

| ID | Requirement |
|---|---|
| POS-R140 | **Open shift** with an opening float. No sale is possible without an open shift on this terminal. |
| POS-R141 | Current shift summary: sales count, gross, discounts, tax, tender breakdown, cash in/out. |
| POS-R142 | **Cash in / cash out** (paid-in, paid-out, petty expense) with reason and optional reference. |
| POS-R143 | **Close shift**: expected cash (opening float + cash sales + cash in − cash out − refunds) vs counted cash, with a denomination counter. Difference shown as over/short. |
| POS-R144 | Closing requires `pos.shift.close`. A variance over a configurable threshold requires a reason. |
| POS-R145 | X report (mid-shift, non-closing) and Z report (closing, printed). |
| POS-R146 | A shift can be opened and operated fully offline and syncs on reconnect (`POS-BE-009`). |

---

## 9. Voids, returns & refunds

| ID | Requirement |
|---|---|
| POS-R160 | **Void** an unfired line freely; a fired line requires `pos.void` and a reason code. |
| POS-R161 | **Find the original order** by invoice number, date, table or customer. |
| POS-R162 | Select returned items and quantities — full or partial. |
| POS-R163 | Refund reason code from a configurable list, plus free text. |
| POS-R164 | Refunds require `pos.refund`; above a configurable amount they require a supervisor override entered at the till. |
| POS-R165 | A refund is a **reversing counter-record** against the original order, never an edit or deletion of it (`POS-BE-010`). |
| POS-R166 | Refund tender defaults to the original tender and can be changed with a reason. |
| POS-R167 | The refund receipt prints and references the original invoice number. |

---

## 10. Customers

| ID | Requirement |
|---|---|
| POS-R180 | Search by phone or name against the local cache first, then the server. |
| POS-R181 | Attach a customer to the order; the customer is optional for every order type except `delivery`. |
| POS-R182 | Create a customer from the till: name, phone, address, note (`POS-BE-014`). |
| POS-R183 | View a customer's recent orders when online. |
| POS-R184 | Phone numbers normalise the same way the backend does (`NormalizesPhoneNumbers`) so the POS and dashboard agree on identity. |

---

## 11. Settings

| ID | Requirement |
|---|---|
| POS-R200 | Device: API URL, restaurant slug, branch, terminal name, terminal id (read-only). |
| POS-R201 | Language (AR/EN) and text direction, defaulting to `restaurant.default_language`. |
| POS-R202 | Printers: receipt + kitchen routing, test print. |
| POS-R203 | Shortcuts: view and remap. |
| POS-R204 | Sync: queue inspector, force sync, dead-letter review. |
| POS-R205 | Diagnostics: version, last sync, log export, catalog cache age and manual refresh. |
| POS-R206 | Settings that change money behaviour (tax, charges, tender types) are **server-owned and read-only at the till** — the POS displays them, it does not author them. |

---

## 12. Non-functional

| ID | Requirement |
|---|---|
| POS-R220 | Cold start to a usable selling screen ≤ 3 s on a 2019-class i5. |
| POS-R221 | Add-to-cart to on-screen total ≤ 50 ms with a 2,000-item catalog. |
| POS-R222 | Search results ≤ 100 ms over 2,000 items. |
| POS-R223 | No unhandled exception may leave the app in a state where a sale cannot be completed. Errors degrade a feature, never the till. |
| POS-R224 | Cart engine unit-test coverage ≥ 95 % (branch). It is the only code in the app where a bug is a financial loss. |
| POS-R225 | Credentials only in the OS secure store; local DB holds no plaintext secrets. |
| POS-R226 | Logs never contain tokens, passwords or full payment references. |
| POS-R227 | Every money-moving action records who, when, which terminal, which shift. |

---

## Out of scope for v1 (stated so it is a decision, not an omission)

- Payment-processor / card-present integration (assumption A-3)
- E-invoicing compliance — Egypt ETA, KSA ZATCA (`R-8`)
- Inventory, stock deduction, recipes/BOM
- Kitchen Display System (kitchen *printing* is in scope; a KDS surface is not)
- Loyalty, gift cards, store credit
- Multi-currency within one tenant
- Table-service floor editing (the POS reads the floor plan; the dashboard authors it)
