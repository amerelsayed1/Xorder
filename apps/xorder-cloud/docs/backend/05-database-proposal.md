# Backend — Database Proposal

# STATUS: PROPOSED — OWNER APPROVAL REQUIRED

**Author:** Agent 2 (Backend) · **Mode:** ANALYSIS-ONLY · **Date:** 2026-08-26

> **No migrations have been written. No migrations have been run.**
> This document describes changes; it does not make them.

**Standing constraints for every change below**

- **SQLite in dev, PostgreSQL in prod.** No engine-specific DDL. In particular:
  **no partial unique indexes** (`WHERE status = 'OPEN'`) — they are not portable.
  Where a conditional constraint is wanted, use a transactional check plus a plain
  index, or fold the condition into the key.
- Every tenant table carries `restaurant_id` + the `BelongsToRestaurant` trait, so
  `RestaurantScope` isolates it **for free**. This is not optional.
- Every new model uses `Auditable`; every financial write calls `AuditLogger`.
- Additive and nullable by default. Production is live.
- Money columns on new POS tables: `BIGINT` minor units, suffix `_minor`
  (pending the owner's decision in `02` §POS-BE-007).

---

## A. Investigation of "does this already exist?"

The brief asks explicitly whether equivalents exist before introducing new
concepts. Each was searched across `app/` and `database/migrations/`:

| Proposed concept | Already exists? | Nearest existing thing |
|---|---|---|
| `POSDevice` / terminal | **No** | `device_tokens` — FCM push tokens for *phones*, unrelated |
| `POSShift` | **No** | `table_visits` has open/close semantics but models a *diner's stay*, not a cashier's session |
| `CashTransaction` | **No** | nothing |
| `OrderPayment` | **No** | nothing — `orders.total` is the only money field |
| `Refund` | **No** | `OrderStatus::CANCELLED`, which is a lifecycle state, not a reversal |
| `SyncRecord` | **No** | nothing |
| `InvoiceSequence` | **No** | `Order::code()` = `'ORD-'.$id` |
| `TaxRule` / `Charge` | **No** | nothing |
| `TenderType` | **No** | nothing |

**Conclusion: nothing is being duplicated.** The money layer is absent, not
half-built — which is the good case. `table_visits` is worth a second look as
prior art for open/close + `closed_by` semantics, and `pos_shifts` should follow
its column conventions for consistency.

---

## B. Changes to existing tables

### B1. `order_items` +`menu_item_id` — **the prerequisite** · POS-BE-006

| | |
|---|---|
| **Existing** | `order_items` — `name(200)`, `quantity`, `options` json, `unit_price`, `line_total`. **No product foreign key.** |
| **Change** | `foreignId('menu_item_id')->nullable()->after('order_id')->constrained()->nullOnDelete()` |
| **Reason** | Server-side re-pricing is structurally impossible without it. Also fixes product reporting for the existing QR product, which currently matches by name (BE-A05). |
| **Types / relations** | `unsignedBigInteger` nullable → `menu_items.id`, `nullOnDelete` |
| **Indexes** | `(restaurant_id, menu_item_id)` for reporting |
| **Nullable because** | (a) history predates the column; (b) `menu_items` is soft-deleted and a hard delete must not cascade away order history; (c) an offline line whose item vanished still records via `name_snapshot` |
| **Backfill** | Best-effort by `(restaurant_id, name)` in a separate, reversible data migration. Ambiguous or unmatched rows stay `null`. **Never guess** — a wrong product id is worse than none. |
| **Tenant / branch scope** | tenant (inherited) / n/a |
| **Migration risk** | **LOW.** Nullable add on a live table; PostgreSQL adds a nullable column without a table rewrite. Backfill runs separately and is interruptible. |
| **Backward compatibility** | Total. `PublicOrderController` keeps writing name-only rows and is not modified. |

### B2. `orders` — POS columns · POS-BE-006, 007, 008

| Column | Type | Note |
|---|---|---|
| `channel` | `string(20)` default `'qr'` | `qr` \| `pos`. Distinguishes POS revenue. **Defaulted, so every existing row is correct.** |
| `client_transaction_id` | `uuid` nullable | `UNIQUE (restaurant_id, client_transaction_id)` |
| `invoice_number` | `string(40)` nullable | `UNIQUE (restaurant_id, invoice_number)`. **Not** the primary key. |
| `terminal_id` | `uuid` nullable | which till |
| `shift_id` | `foreignId` nullable | → `pos_shifts`, `nullOnDelete` |
| `served_by_user_id` | `foreignId` nullable | the cashier → `users`, `nullOnDelete` |
| `subtotal_minor`, `discount_minor`, `tax_minor`, `charges_minor`, `total_minor` | `bigInteger` nullable | authoritative POS figures |
| `currency_exponent` | `unsignedTinyInteger` nullable | 2, or 3 for KWD/BHD/OMR/JOD |
| `received_at` | `timestamp` nullable | server receipt time, distinct from `created_at` |
| `totals_mismatch` | `boolean` default false | client assertion disagreed |

**`orders.total` (`decimal(10,2)`) stays and keeps being written** as the rounded
major-unit projection of `total_minor`, so stats, reports and both SPAs continue
working untouched. This is the whole reason the minor-unit convention can be
confined to new surface.

**Uniqueness caveat:** a plain `UNIQUE (restaurant_id, client_transaction_id)`
across many `NULL`s is fine on both engines (NULLs do not collide), so QR orders
are unaffected.
**Migration risk: LOW-MEDIUM** — 12 nullable columns on the busiest table. Split
across two migrations and run outside service hours.

### B3. `order_items` — cashier adjustments · POS-BE-006

`variant_option_id` (nullable FK → `options`), `option_ids` (json, the resolved
selection — `options` json already exists but stores display data),
`unit_price_minor`, `line_total_minor`, `discount_minor`, `discount_reason(120)`,
`price_override_minor`, `price_override_reason(120)`, `name_snapshot(200)`,
`client_line_id(64)`.
All nullable. **Risk: LOW.**

### B4. `menu_items` +`sku` +`barcode` · POS-BE-004

`sku string(64) nullable`, `barcode string(64) nullable`.

**Indexes — and the caveat Agent 1 could not have known:** `menu_items` uses
`SoftDeletes`. `UNIQUE (restaurant_id, barcode)` would collide with a soft-deleted
row and permanently block re-use of a barcode after an item is deleted. The
`username` precedent (`2026_07_21_000300`) does not hit this because `users` is not
soft-deleted.

**Proposal:** `UNIQUE (restaurant_id, barcode, deleted_at)` and
`UNIQUE (restaurant_id, sku, deleted_at)`, which behaves correctly on both engines
(distinct `deleted_at` values do not collide; multiple live rows with `NULL`
barcode do not collide either). Plus a plain index on `(restaurant_id, barcode)`
for scan lookup.
**Risk: LOW.** **Backward compatible:** yes — both nullable.

### B5. `restaurants` +`tax_registration_number` · POS-BE-013

`string(64) nullable`. Required on a tax receipt in every jurisdiction
`CurrencyEnum` covers. Authored via `RestaurantProfileController`
(`settings.update`). **Risk: none.**

### B6. `branches` — no schema change · POS-BE-005

`code` and `supported_order_types` **already exist**. Resource-layer change only.
Recorded here to make explicit that POS-BE-005 needs **no migration**.

### B7. `users` +`branch_id` — **owner decision, not proposed for v1** · BE-A02

`foreignId('branch_id')->nullable()->constrained()->nullOnDelete()`, `null` = all
branches.

**Not proposed for v1**, but flagged now because the cost asymmetry is sharp:
adding it before tills are deployed is one nullable column; adding it afterwards
is a migration *plus* a policy change *plus* re-training staff whose access
silently narrows. Today **any restaurant staff account can read and write every
branch's tills and shift reports.** For a QR menu that is fine. For cash it is a
question only the owner can answer. **Risk if deferred: MEDIUM.**

---

## C. New tables

Every one carries `id`, `restaurant_id` (FK, cascade), `timestamps`, the
`BelongsToRestaurant` trait and `Auditable`.

### C1. `pos_terminals` · POS-BE-009
`branch_id` FK nullable · `terminal_id` uuid · `name(80)` · `platform(20)` ·
`app_version(20)` · `last_seen_at` · `is_revoked` bool default false ·
`revoked_at` nullable.
`UNIQUE (restaurant_id, terminal_id)` · index `(restaurant_id, branch_id)`.
`is_revoked` addresses BE-A04 — `password_changed_at` revokes the *cashier*, not
the *device*.

### C2. `pos_shifts` · POS-BE-009
`branch_id` FK · `terminal_id` uuid · `opened_by_user_id` / `closed_by_user_id` FK
nullable · `client_transaction_id` uuid · `status(20)` (`OPEN`/`CLOSED`) ·
`opening_float_minor` · `expected_cash_minor` nullable · `counted_cash_minor`
nullable · `variance_minor` nullable · `variance_reason` text nullable ·
`opening_denominations` / `closing_denominations` json nullable ·
**`opened_at`, `closed_at` (client-supplied)** · `received_at` (server).

`UNIQUE (restaurant_id, client_transaction_id)` · index `(terminal_id, status)` ·
index `(restaurant_id, branch_id, opened_at)`.

**"One open shift per terminal" is enforced transactionally, not by a partial
unique index** — those are not portable to SQLite. Follows `table_visits`'
open/close + `closed_by` conventions.

### C3. `pos_cash_movements` · POS-BE-009
`shift_id` FK cascade · `branch_id` FK · `client_transaction_id` uuid ·
`direction(10)` (`in`/`out`) · `amount_minor` · `reason_code(40)` ·
`reason_note` text nullable · `reference(80)` nullable · `user_id` FK ·
`occurred_at` (client) · `received_at` (server).
`UNIQUE (restaurant_id, client_transaction_id)` · index `(shift_id, direction)`.

### C4. `order_payments` · **BE-A01** — Agent 1 did not raise this separately
`order_id` FK cascade · `tender_type_id` FK · `client_transaction_id` uuid ·
`amount_minor` · `change_minor` default 0 · `reference(80)` nullable ·
`status(20)` default `CAPTURED` · `shift_id` FK nullable · `user_id` FK nullable ·
`occurred_at` · `received_at`.
`UNIQUE (restaurant_id, client_transaction_id)` · index `(order_id)`.

**Why a table and not columns on `orders`:** split tender is the normal case at a
till, not an edge case. "300 cash + 200 card" is two rows. Columns on `orders`
cannot represent it, and once a receipt has been printed showing two tenders the
schema cannot be changed cheaply. **This is the most important thing in this
document that Agent 1's request set does not already contain.**

### C5. `pos_refunds` + `pos_refund_lines` · POS-BE-010
`pos_refunds`: `order_id` FK restrict · `branch_id` · `shift_id` nullable ·
`client_transaction_id` uuid · `credit_note_number(40)` (own sequence) ·
`reason_code(40)` · `reason_note` · `total_minor` · `refunded_by_user_id` ·
`approved_by_user_id` nullable · `occurred_at` · `received_at`.
`pos_refund_lines`: `refund_id` FK cascade · `order_item_id` FK restrict ·
`quantity` · `amount_minor`.

**`restrict`, not `cascade`, on the original order** — a refund must never be
orphaned, and the original must never be deletable while a reversal points at it.
Server validates cumulative refunded quantity per line ≤ sold quantity.
**The original order is never mutated.**

### C6. `invoice_sequences` · POS-BE-008
`branch_id` FK nullable · `period(10)` (`'2026'`, `'2026-08'`, or `'ALL'`) ·
`prefix(20)` nullable · `padding` unsignedTinyInteger default 6 ·
`next_value` unsignedBigInteger default 1 · `kind(20)` default `'invoice'`
(also `'credit_note'`).
`UNIQUE (restaurant_id, branch_id, period, kind)`.

Allocation: `lockForUpdate()` on the row inside the order transaction. **Never
`MAX(number)+1`** — that double-issues under two tills. First use of a new period
must create the row atomically (`firstOrCreate` outside a lock races); safest is
`insertOrIgnore` then `lockForUpdate()`.

### C7. `tax_rules` · POS-BE-013
`name_en` / `name_ar` · `rate_bp` unsignedInteger (**basis points**, `1400` = 14 %) ·
`mode(10)` (`inclusive`/`exclusive`) · `scope_order_types` json nullable ·
`scope_branch_ids` / `scope_category_ids` / `scope_menu_item_ids` json nullable ·
`is_active` · `sort_order`.
Null scope arrays = applies to everything. **Basis points, never a float.**

### C8. `charges` · POS-BE-013
`name_en` / `name_ar` · `kind(10)` (`percent`/`fixed`) · `value_bp` nullable ·
`value_minor` nullable · `taxable` bool · `scope_*` json as above · `is_active` ·
`sort_order`.
`taxable` decides whether service charge is itself taxed — a per-jurisdiction
question the server must own.

### C9. `tender_types` · POS-BE-013
`name_en` / `name_ar` · `kind(20)` (`cash`/`card`/`external`/`other`) ·
`opens_drawer` bool · `requires_reference` bool · `is_active` · `sort_order`.
`UNIQUE (restaurant_id, name_en)`.
`kind = external` is how v1 records a card taken on a standalone bank terminal
without the backend pretending to be a payment processor. **No PAN, no track data,
no PCI scope.**

---

## D. Migration sequencing and risk

| # | Migration | Depends on | Risk |
|---|---|---|---|
| 1 | `order_items.menu_item_id` (nullable) | — | LOW |
| 2 | backfill `menu_item_id` by name (separate, reversible) | 1 | LOW |
| 3 | `menu_items.sku` + `barcode` + indexes | — | LOW |
| 4 | `restaurants.tax_registration_number` | — | none |
| 5 | `tax_rules`, `charges`, `tender_types` | — | none (new) |
| 6 | `pos_terminals` | — | none (new) |
| 7 | `invoice_sequences` | — | none (new) |
| 8 | `orders` POS columns | 7 | **LOW-MEDIUM** |
| 9 | `order_items` adjustment columns | 1 | LOW |
| 10 | `order_payments` | 5, 8 | none (new) |
| 11 | `pos_shifts`, `pos_cash_movements` | 6, 8 | none (new) |
| 12 | `pos_refunds`, `pos_refund_lines` | 8, 10 | none (new) |
| 13 | *(if approved)* `users.branch_id` | — | MEDIUM (policy change) |
| 14 | *(if approved)* `SoftDeletes` on `option_groups`, `options` | — | LOW |

**Every migration has a working `down()`.** Steps 1–7 are independently shippable
and reversible with no POS code at all — step 1 alone improves the existing product.

**Prod-safety notes**

- Nullable adds do not rewrite tables on PostgreSQL.
- The `menu_item_id` backfill is a separate, resumable migration, not inline.
- No column is dropped, renamed or re-typed. **Nothing existing is destroyed.**
- SQLite rebuilds tables on `ALTER`, so dev/test migrate times grow slightly —
  irrelevant in CI, but the reason step 8 is split.

---

## E. Financial integrity summary

The brief requires the server to validate money rather than trust client totals.
Where each guarantee lives:

| Guarantee | Mechanism |
|---|---|
| Prices are the server's | Re-price from `menu_item_id` + option ids; client prices compared only |
| Discounts are authorised | `pos.discount` / `pos.price_override` checked before any write |
| Tax is the server's | `tax_rules` in basis points, server-applied, never client-authored |
| Charges are the server's | `charges` with an explicit `taxable` flag |
| Totals are reproducible | Every input persisted per line; totals recomputable from the record |
| Payments balance | `SUM(order_payments.amount_minor) − change` reconciled against `orders.total_minor` |
| Refunds cannot exceed sales | Cumulative refunded quantity per line validated server-side |
| Cash is reconciled | `expected_cash_minor` computed server-side; the count is data, the expectation is the server's |
| Nothing is silently edited | Refunds are reversing records; originals are immutable |
| Everything is attributable | `served_by_user_id`, `terminal_id`, `shift_id` on every money row + `AuditLogger` |
| Sequences are legal | `invoice_sequences` with row locking; no gaps from replays |

---

> **BACKEND IMPLEMENTATION HAS NOT STARTED. OWNER APPROVAL IS REQUIRED.**
> **NO MIGRATIONS HAVE BEEN WRITTEN. NO MIGRATIONS HAVE BEEN RUN.**
