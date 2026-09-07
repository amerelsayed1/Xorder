# Backend — POS Implementation Plan

# STATUS: PROPOSED — OWNER APPROVAL REQUIRED

**Author:** Agent 2 (Backend) · **Mode:** ANALYSIS-ONLY · **Date:** 2026-08-26

> This is a plan, not progress. **No task below has been started.**
> Every task references a `POS-BE-xxx` (Agent 1's) or `BE-Axx` (Agent 2's) id.
> Tasks are only actionable once the owner approves that specific id.

**Standing gate:** CI runs `apps/api` tests as a deploy gate. Every task below
ships with tests or it does not ship.

---

## Wave 0 — Zero-risk, independently valuable (no POS code required)

Each of these is shippable on its own, improves the existing product, and is
reversible. **They are the safest possible place to start if the owner wants to
approve something small first.**

### T0.1 — `BranchResource` exposes `code` + `supported_order_types` · **POS-BE-005**
- **Depends on:** nothing
- **Reuses:** existing columns, already `$fillable`, already cast
- **Files:** `app/Http/Resources/BranchResource.php`
- **DB:** none · **API:** two additive keys (emit `[]` not `null`)
- **Tests:** resource shape; null `supported_order_types` → `[]`
- **Risk: NONE** · ~30 minutes

### T0.2 — `order_items.menu_item_id` · **POS-BE-006 prerequisite**, **BE-A05**
- **Depends on:** nothing. **Everything financial depends on this.**
- **Files:** new migration; `app/Models/OrderItem.php`; optionally `ReportService`
- **DB:** `05` §B1 — nullable FK + index, plus a separate best-effort backfill
- **Tests:** nullable add is non-breaking; public order path still writes name-only rows; backfill matches unambiguously and leaves ambiguous rows null
- **Risk: LOW** · fixes an existing reporting defect on its own
- ~half a day including the backfill migration

### T0.3 — `?resolve=full` on `GET /api/dashboard/items` · **POS-BE-003**
- **Depends on:** nothing
- **Reuses:** `MenuItem::orderedOptionGroups()`, `withAutoOptionGroups()` — the
  logic already exists and is N+1-free; it is simply never invoked on this path
- **Files:** `Dashboard/MenuItemController`, `MenuItemResource`
- **DB:** none · **API:** opt-in query param; default payload unchanged
- **Tests:** without the flag payload is byte-identical to today; with it, an
  `apply_scope = 'all'` group appears; no N+1 (assert query count)
- **Risk: NONE** · **fixes a real existing bug** — the dashboard currently shows a
  different menu than the diner's phone
- ~half a day

### T0.4 — `Feature::POS` + optional `plans.max_terminals` · **POS-BE-001**
- **Reuses:** `Feature`, `PlanEntitlementService`, `EnsureFeatureEnabled`,
  `PlanLimitService::staffLimitReached()` as the precedent
- **Files:** `app/Enums/Feature.php`; migration if metering terminals; `PlanLimitService`
- **Tests:** every existing tenant resolves `pos => false`; `Feature::resolve()` unaffected
- **Risk: NONE** — additive, off by default · ~2 hours

### T0.5 — POS capabilities in `TenantCapability` · **POS-BE-002**
- **Reuses:** the entire RBAC. Vocabulary only.
- **Final strings (Agent 2's decision, as Agent 1 invited):**
  `pos.operate` `pos.discount` `pos.price_override` `pos.void` `pos.refund`
  `pos.shift_open` `pos.shift_close` `pos.cash_movement` `pos.reprint`
- **Also:** `group()` gains `'pos'`; `implies()` must map the `pos` resource to
  **`pos.operate`** rather than a non-existent `pos.view` (three-line change)
- **Files:** `app/Enums/TenantCapability.php`
- **Tests:** `expand()` round-trips the nine; `implies()` resolves to `pos.operate`;
  no existing role gains anything; owner still holds all
- **Risk: NONE** — every existing staff account is POS-locked until granted
- ~2 hours

### T0.6 — `menu_items.sku` + `barcode` · **POS-BE-004**
- **Files:** migration; `MenuItem`; `MenuItemResource`; `StoreMenuItemRequest` /
  `UpdateMenuItemRequest`; `MenuImportController`; `MenuExportController`
- **DB:** `05` §B4 — **note the `SoftDeletes` uniqueness caveat**; unique must
  include `deleted_at`
- **Tests:** duplicate barcode in-tenant → 422; same barcode in another tenant → OK;
  **barcode re-usable after the holding item is soft-deleted** (the caveat); import/export round-trip
- **Risk: LOW** — export gains two columns, which changes a file shape a customer
  script may parse. Worth a release note.
- ~1 day

**Wave 0 total: ~3 days. Nothing in it can break production, and T0.2 + T0.3 are
worth doing whether or not the POS ships.**

---

## Wave 1 — The money core *(the blocking work)*

**Do not start Wave 1 before the three decisions in §"Decisions required" are
answered.** Building order creation before the money representation is settled
means migrating a table that already holds real financial records.

### T1.1 — Idempotency infrastructure · **POS-BE-007**
- **Depends on:** money-representation decision
- **New:** `App\Services\IdempotencyGuard` — the lock-check-return-original pattern
  from `04` §3, reusable by every POS write
- **Files:** migration (`orders.client_transaction_id` + unique); new service;
  a middleware or FormRequest rule reconciling `Idempotency-Key` with the body field
- **Tests:** all ten obligations in `04` §10 — especially **unique-violation-is-a-success-path**
- **Risk: LOW** (new surface) · ~2 days

### T1.2 — Invoice sequences · **POS-BE-008**
- **Depends on:** T1.1 (a replay must not consume a number)
- **New:** `invoice_sequences` table; `App\Services\InvoiceNumberService`
- **Critical:** `lockForUpdate()`, never `MAX()+1`; atomic first-use row creation
- **Tests:** concurrent allocation issues distinct numbers; replay returns the same
  number and consumes none; yearly reset; null `branch.code` falls back to `restaurant.slug`
- **Risk: LOW** · ~1.5 days

### T1.3 — Money configuration · **POS-BE-013**
- **New:** `tax_rules`, `charges`, `tender_types`; `restaurants.tax_registration_number`;
  `App\Services\PosPricingService` (applies rules, basis points, inclusive/exclusive)
- **Also:** dashboard CRUD under `settings.update`; seed a sane default set per tenant
- **Tests:** inclusive vs exclusive; taxable service charge; scope resolution
  (order type / branch / category / item); rounding at the currency exponent;
  a 3-dp currency (KWD) end to end
- **Risk: LOW** (new surface) · ~3 days
- **Blocking for any tenant that charges tax.**

### T1.4 — `POST /api/pos/orders` · **POS-BE-006** + **BE-A01**
- **Depends on:** T0.2, T0.5, T1.1, T1.2, T1.3
- **Reuses:** `MenuItem::displayPricing()` / `defaultVariantOption()` /
  `orderedOptionGroups()`; the `lockForUpdate()` table-visit discipline in
  `PublicOrderController::store()`; `TableVisitService`; `NotificationService`;
  `AuditLogger`; `OrderResource`; `TenantContext`
- **New:** `app/Http/Controllers/Pos/OrderController`; `StorePosOrderRequest`;
  `App\Services\PosOrderService`; `order_payments` table (**BE-A01 — split tender
  is the normal case, not an edge case**); `orders`/`order_items` columns per `05` §B2–B3
- **Files touched that are shared:** `OrderResource` (additive keys only).
  **`PublicOrderController` is NOT modified.**
- **Tests:** server re-pricing ignores client prices; `totals_mismatch` still creates
  the order; deleted item falls back to `name_snapshot` with a warning and is never
  dropped; discount without `pos.discount` → 403 before any write; cross-tenant
  `branch_id` → 404; dine-in concurrency; split tender balances; option-model
  violations → 422
- **Risk: MEDIUM** — the largest single piece, and it touches the shared `orders` table
- ~5 days

### T1.5 — `GET /api/pos/config` + `GET /api/pos/catalog` · **POS-BE-003, 004, 005, 013**
- **Depends on:** T0.1, T0.3, T0.6, T1.3
- **New:** `Pos/ConfigController`, `Pos/CatalogController`
- **Tests:** one round-trip returns everything the till needs; payload stays small
  enough to cache whole; `?updated_since` skips nothing across the watermark
- **Risk: NONE** (new endpoints) · ~2 days

### T1.6 — `GET /api/pos/orders/by-client-id/{uuid}` · **POS-BE-007**
- **Depends on:** T1.4 · trivial once the column exists · ~2 hours

**Wave 1 total: ~14 days. This is the blocking work; nothing takes money without it.**

---

## Wave 2 — Shift and cash *(POS Phase 6)*

### T2.1 — `pos_terminals` + registration · **POS-BE-009**, **BE-A04**
Depends on T1.1. Includes `is_revoked` (BE-A04) — `password_changed_at` revokes the
cashier, not the device. ~1 day · **Risk: NONE**

### T2.2 — `pos_shifts` + open/close/current · **POS-BE-009**
Depends on T2.1, T1.4. Server computes `expected_cash_minor`; the count is data.
**Client-supplied `opened_at`/`closed_at`; `received_at` separate.** One-open-shift-per-terminal
enforced transactionally (**not** a partial unique index — not portable to SQLite).
Formula confirmed to Agent 1 in `02` §POS-BE-009. ~3 days · **Risk: LOW**

### T2.3 — `pos_cash_movements` · **POS-BE-009**
Depends on T2.2. ~1 day · **Risk: NONE**

### T2.4 — X / Z report · **POS-BE-009**
Depends on T2.2, T2.3. Reuses `ReportService` patterns. Totals derived from
`created_at` inside the shift window, **not** arrival order. ~2 days · **Risk: NONE**

**Wave 2 total: ~7 days.**

---

## Wave 3 — Sync hardening and the long tail

| Task | Req | Depends | Effort | Risk |
|---|---|---|---|---|
| T3.1 `POST /api/pos/sync/batch` (per-op results, dependency ordering, never all-or-nothing) | 006, 007, 009 | Waves 1–2 | 3 d | LOW |
| T3.2 POS token lifetime — implement the owner's chosen option | 011 | decision | 1–5 d | **MEDIUM** (auth surface) |
| T3.3 Refunds + credit notes | 010 | T1.4, T1.2 | 4 d | MEDIUM |
| T3.4 `POST /api/pos/customers` + `customers.create` verb | 014 | T0.5 | 1 d | NONE |
| T3.5 `?updated_since` + tombstones | 012 | T1.5 | 2 d | NONE |
| T3.6 `SoftDeletes` on `option_groups` + `options` | BE-A03 | — | 1 d | LOW |
| T3.7 *(if approved)* `users.branch_id` + branch scoping | BE-A02 | — | 3 d | **MEDIUM** (policy change) |

**Wave 3 total: ~15 days depending on which options are chosen.**

---

## Aggregate

| Wave | Scope | Effort | Blocking for POS? |
|---|---|---|---|
| 0 | Exposure, vocabulary, prerequisites | ~3 d | No — but T0.2 gates everything |
| 1 | Money core | ~14 d | **YES** |
| 2 | Shift + cash | ~7 d | Phase 6 only |
| 3 | Sync hardening + long tail | ~15 d | No |
| | **Total** | **~39 working days** | |

Single backend engineer, including tests, excluding review and deploy windows.
Waves 0 and 1 are sequential; 2 and 3 partly parallelise.

---

## Decisions required before Wave 1 starts

| # | Decision | Recommendation | Consequence of deferring |
|---|---|---|---|
| **D1** | **Money representation** — integer minor units on POS tables, or `decimal(10,2)` throughout? | **Minor units on new POS tables only.** `orders.total` keeps its decimal projection so stats/reports/SPAs are untouched. Only option that is *correct* for KWD/BHD/OMR/JOD, all already in `CurrencyEnum`. | Migrating money columns after the first real receipt is printed |
| **D2** | **`subscription.writable` on POS writes** — does a lapsed plan stop a restaurant taking money? | **No.** Consistent with the existing deliberate choice to keep order handling alive on a lapsed plan. Blocking sales converts a collections problem into an outage. | Ambiguous behaviour on the first lapsed tenant |
| **D3** | **POS token lifetime** (POS-BE-011) | **Option A now** (longer POS TTL via dedicated config, issued when login carries a `terminal_id`), **Option C later** once terminals exist to bind to. Building C first means building it twice. | A cashier interrupted mid-rush holding real paid transactions |
| D4 | Per-user branch scoping (BE-A02) | Owner's call. Cheap now, expensive after deployment. Today any staff account sees every branch's cash. | A policy change forced on live users |
| D5 | Extend `OrderStatus`? | **No.** Derive `settlement_status` instead; keep the `canTransitionTo()` invariant intact. | An overloaded lifecycle enum that is hard to unpick |

---

## What Agent 1 can rely on **today**

Unchanged and already `READY` in the existing product — these need no approval:

- `POST /api/auth/login` (username + `restaurant` slug, no email needed) → JWT
- `GET /api/auth/me` → user, restaurant, features, `capabilities[]`
- `GET /api/dashboard/branches` (`can:branches.list`)
- `GET /api/dashboard/items`, `/categories`, `/option-groups`, `/combos` (`can:menu.view`)
- `GET /api/dashboard/customers` (`can:customers.view`)
- `GET /api/dashboard/orders`, `PATCH /api/dashboard/orders/{order}/status`
- The table-experience endpoints (`feature:table_management`)

**Everything else in this plan is `PROPOSED` and must stay behind a fake in the
Flutter app until it appears in `BACKEND_TO_POS.md` as `READY`.**

---

> **BACKEND IMPLEMENTATION HAS NOT STARTED. OWNER APPROVAL IS REQUIRED.**
