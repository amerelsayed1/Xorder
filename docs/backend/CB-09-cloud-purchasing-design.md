# CB-09: Purchasing, suppliers, units and stock on cloud (design)

**Status: `IN PROGRESS — slice b`.** Written 2026-09-12 by `xorder-cloud`,
on the owner's "go CB-09", and reviewed by the owner the same day. Slice a is
committed on branch `feat/cb-09-purchasing` as `dd9a530`, not deployed (§13).
Slice b is built on the same branch after the owner's "go slice b"
(2026-09-12): uncommitted, not deployed, awaiting owner review (§14).
Slices b and c are approved **in order, one at a time, with an owner review
between slices**. Nothing else is approved: slice d waits on D12, slice e
(POS-BE-030 and the till change) is not approved, and D11 is still open.

### Owner decisions, 2026-09-12

1. **D1: on cloud the platform is the only author** of purchasing and
   receiving (option A). D2 follows from it.
2. **D6, amended by the owner.** Verbatim: *"it not restaurant only, say it
   client can be cafe cloud kit and all of these"*. So **`purchasing` is a
   standalone plan feature and does not depend on `pos`**. Any client type
   (restaurant, café, cloud kitchen, and so on) can have it, including one
   with no till. Consequences, all applied below:
   - no `pos` anywhere in the entitlement, the gate stack or the navigation;
   - the dashboard entries get sidebar groups of their own, **not** the
     settings shell's "Point of sale & money" group;
   - **all new user-facing copy, EN and AR, uses neutral wording**
     ("business"/"client", "النشاط"/"العميل"), never "restaurant". Existing
     strings are not renamed.
3. **D7: one capability, `purchase.manage`**, gating reads and writes.
4. **Build slices a, b and c, in that order**, with an owner review after
   each. The first run is slice a only.

Paths: *POS* = `xorder-pos/lib/…`, *MIG* = `xorder-pos/lib/data/postgres/migrations.dart`,
*API* = `xorder-new/apps/api/…`, *WEB* = `xorder-new/apps/web/src/…`. Every
till claim was checked by reading the till's working tree on 2026-09-12. That
tree has other sessions' uncommitted edits, `migrations.dart` among them, so
line numbers may drift. Nothing was run.

---

## 0. Decisions at a glance

| # | Decision | Recommendation | § |
|---|---|---|---|
| D1 | Who authors purchasing and stock on a cloud restaurant | **Decided: the platform only.** The till's four buying and inventory panes are hidden on cloud | 3.1 |
| D2 | Purchasing rows already on cloud tills | **Left in place: not imported, not deleted.** They stay reachable through the till's backup | 3.1 |
| D3 | Where a stock item lives on the platform | **A separate `stock_items` table**, with an optional link to a `MenuItem`. Not a `MenuItem` flag | 3.2 |
| D4 | Stock from sales | **Neither side deducts sales in v1**, matching the till. The stock figure is labelled for what it is | 3.3 |
| D5 | Branch scope | **Stock, POs, invoices and payments are per branch. Suppliers, units and stock items are per restaurant**, as on the till | 3.4 |
| D6 | Entitlement | **Decided, amended by the owner: new plan feature `purchasing`, standalone. It does not require `pos`**, so any client type can buy it, with or without a till. It resolves to false for every existing tenant | 3.5 |
| D7 | Permission | **Decided: one TenantCapability, `purchase.manage`**, the till's own string. It gates reads and writes | 3.5 |
| D8 | What the till gets from the platform | **Nothing in v1**, apart from `purchase.manage` being withheld from the cloud bundle. The draft is POS-BE-030 | 3.6 |
| D9 | Valuation | **The till's moving average**, ported to PHP line for line, integers only | 2.3 |
| D10 | Cross-row invariants | **A service with a row lock, plus portable constraints.** No DB triggers | 5 |
| D11 | Short-closing a part delivery | **Owner decision.** The till's doc promises it and its code can't do it (§10 C1) | 10 |
| D12 | Stock adjustments, counts, waste and openings | **Held.** They'd put the platform ahead of the till (slice d) | 9 |
| D13 | Paying a supplier "out of the drawer" on cloud | **Optional link to a synced till pay-out**, with the rules of the till's migration 33 | 4.10 |
| D14 | Dashboard placement | **Two sidebar groups, Purchasing and Inventory.** Operational pages, not settings, and not under "Point of sale & money"; no `pos` gate on either (follows from D6) | 7 |

---

## 1. What CB-09 is

This is doc 16's chain: *purchases → supplier invoices → cost price → inventory
valuation → COGS* (`16-back-office-scope.md` §3). On the till it's Wave P,
built across migrations 27–31, 33, 39 and 40, with four panes: Purchasing,
Items, Stock and Units. None of it reaches the platform. On a cloud till today:

- **Purchasing** and **Units** are shown to anyone holding `purchase.manage`
  and write till-local rows (POS `features/admin/presentation/management_screen.dart:320-341`).
  The Stock pane is also shown, read-only.
- **Items** is hidden. `_authoringPanes` includes it because a bought-only item
  is a `pos_products` row, and the seeder deletes every product
  (`management_screen.dart:108-114`; POS `data/cloud/bootstrap_seeder.dart:368-377`).
- The PO dialog can't create a stock item on cloud (`management_purchasing_pane.dart:167,175`),
  and the Menu pane, where `is_stocked` is set, is hidden too. **So in
  practice a cloud till's purchasing is money only.** Its PO lines name no
  product, and receiving writes no stock movement
  (`postgres_receiving_repository.dart:121-125`).

The platform has no model for any of it (`BACKOFFICE_TO_CLOUD.md` §3).

---

## 2. The till's rules this design copies

### 2.1 Tables (MIG)

| Migration | Table(s) | What matters |
|---|---|---|
| 27 (`:2420`) | `pos_suppliers` | Per restaurant. `code` defaults to `''` and is unique only when set (partial index `:2455`). `payment_term_days >= 0`. **No balance column** (`:2463-2469`). `purchase.manage` is granted to the owner and manager roles only (`:2476-2494`) |
| 28 (`:2496`) | `pos_purchase_orders`, `_lines`, `pos_purchase_sequences` | Per branch (`branch_id NOT NULL`, `:2503`). Supplier is `RESTRICT` and its name is snapshotted. Five statuses (`:2529-2532`). `ordered_at` is required once the order is past draft (`:2533`). Totals are snapshotted when it is sent. Lines hold `ordered_milli`/`received_milli` (bigint thousandths), `unit` text, `unit_cost_minor`, and a `tax_rate_bp` snapshot. `product_id` is nullable `SET NULL`. The reference comes from a per-restaurant, per-year sequence (`:2603`) |
| 29 (`:2611`) | `pos_stock_movements`, `pos_stock_levels`, `pos_products.stock_unit/is_stocked` | The ledger is append-only (`:2612-2614`). Quantity is signed. Each movement records the resulting `balance_milli` and `average_cost_minor` (`:2630-2636`). `product_id` is `RESTRICT` (`:2620`). The level is keyed `(branch_id, product_id)`: a **justified cache**, because a moving average is a fold (`:2664-2673`). Kinds: `receipt, sale, waste, adjustment, opening, transfer_in, transfer_out` |
| 30 (`:2705`) | `pos_supplier_invoices`, `pos_supplier_payments` | Invoices have **no subtotal and no balance** (`:2709-2713`). `total_minor > 0` and `0 ≤ tax ≤ total`. `due_at >= issued_at`. A void must carry a reason (`:2765`). The supplier's number is unique per supplier among **non-voided** invoices (`:2776-2778`). A payment with `invoice_id` null is **on account**. Methods: `cash, bank_transfer, cheque, card, other` |
| 30, triggers | `pos_supplier_payment_allocation` (`:2858-2908`) | Locks the invoice `FOR UPDATE`. Checks same supplier, same restaurant and not voided. **Allocations excluding voided payments plus the new one must be ≤ the total** |
| 30, triggers | `pos_supplier_invoice_void_is_clear` (`:2915-2941`) | An invoice can't be voided while any live payment is allocated to it |
| 31 (`:2944`) | `pos_reason_codes` scopes `invoice_void`, `payment_void` | Six seeded reasons each, and "other" requires a note (`:2968-2998`) |
| 33 (`:3065`) | `pos_supplier_payments.cash_movement_id` + trigger `pos_supplier_payment_drawer_link` (`:3095-3146`) | One movement per payment (`:3079`). The movement must be a `pay_out` of the same restaurant for **exactly** the same amount |
| 39 (`:3562`) | `pos_units` | Per restaurant. `code` matches `^[a-z][a-z0-9_]{0,15}$` and is immutable. Seven are seeded (`ea kg g l ml box pack`, `:3599-3605`), plus `eta_unit_type` and `allows_fraction`. Retired, never deleted |
| 40 (`:3630`) | `pos_products.category_id` nullable, with CHECK `category_id IS NOT NULL OR is_stocked` | A stock-only item is a product with no category. The menu query joins categories, so it never reaches the cashier |

Grants (POS `data/postgres/local_bootstrap.dart:824-860`, `administrativeGrants`):
the ledger is INSERT+SELECT only. Invoice and payment UPDATEs are
column-scoped, so correcting a figure means voiding the row and entering it
again. Suppliers can't be deleted.

### 2.2 Rules in the domain code

- **Quantity** is integer thousandths, and there is **no unit conversion**
  (POS `core/money/quantity.dart:1-19`). A line's value is `costAt`:
  `roundHalfUp(milli × unitCostMinor, 1000)` (`:115`).
- **Rounding** is `roundHalfUp(n, d)`: half up, with negatives away from zero
  (POS `core/money/rounding.dart:10-17`). PO tax is rounded **per rate**, not
  per line (POS `domain/models/purchase_order.dart:191-218`,
  `Money.percentBp` at `core/money/money.dart:86-87`).
- **PurchaseEngine** (`purchase_order.dart:345-388`): lines can be added only
  to a draft, and only with a positive quantity. `send` needs a draft with
  lines. `cancel` is allowed from draft or sent, and refused once
  partially received or closed.
- **Status follows the lines** after a receipt (`postgres_receiving_repository.dart:196-213`):
  every line full → `received`, anything arrived → `partially_received`, else `sent`.
- **Over-delivery is allowed.** Suppliers round up to a crate
  (`purchase_order.dart:108-111`), and receiving has no upper bound.
- **The cost comes from the PO line's `unit_cost_minor`**, the ordered price
  (`postgres_receiving_repository.dart:109,142-146`). The receive dialog has
  no cost field, and a supplier invoice has no lines, so it never changes a
  cost.
- **Supplier balance** = non-voided invoices − non-voided payments.
  **Overdue** counts only what was *allocated* per invoice, so on-account
  money reduces the balance without making any single bill current
  (`domain/models/supplier_invoice.dart:421-470`; the query is at
  `postgres_supplier_invoices_repository.dart:224-270`).
- Supplier validation: a name is required, terms are ≥ 0, and a tax number,
  when given, is exactly nine digits (`domain/models/supplier.dart:92-117`).

### 2.3 Valuation: moving average (confirmed)

**Moving average**, chosen by the owner on 9 Sept 2026 over last-cost and FIFO
(POS `domain/services/stock_costing.dart:3-11`).

- `receive` (`:64-103`): nothing, or a negative quantity, on hand means the
  arriving cost wins (`:87-89`). Otherwise the new cost is
  `roundHalfUp((costAt(onHand, avg) + costAt(arrived, cost)) × 1000, onHand + arrived)`
  (`:91-97`).
- `issue` (`:116-128`): the quantity goes down (it may go negative), and **the
  cost never moves**.
- `costOfGoods` (`:135-136`): what was issued, at the average held *before* the
  issue.
- The receiving transaction does five things (`postgres_receiving_repository.dart:64-248`):
  lock the PO; lock each line; add to `received_milli`; lock the level row; and
  append a movement carrying the resulting balance and average. Then it upserts
  the level, sets the status from the lines, and writes an audit event. Lines
  with no product move the order along and touch no ledger (`:121-125`).

**D9: the platform uses the same arithmetic.** It is ported to one PHP class
(`App\Support\StockCosting`) with the same integer formulas and the same
`roundHalfUp`, including the negative branch. It's tested against a table of
cases produced by the till's own unit tests, so a figure on the dashboard and
the same delivery booked on an offline till agree to the piastre. PHP `int` is
64-bit. The largest product is `(value × 1000)`, where value is in minor
units, which is far below the limit.

---

## 3. The seven questions

### 3.1 Q1: One author per row. Who authors what on cloud?

| Option | What it means | Verdict |
|---|---|---|
| **A. The platform authors everything** (suppliers, POs, receiving, invoices, payments, units, stock items). The till's Purchasing, Items, Stock and Units panes are **hidden** on cloud | One author per row. Nothing crosses the wire in v1 | **Recommended** |
| B. The platform authors everything, but the till's panes show **read-only** copies | Needs a new bundle block or a read endpoint, plus a read-only mode across four panes and four tabs. A manager who wants to read purchase history has the dashboard, which is the plan-17 §6 rule (*the till never becomes the cloud dashboard*) | Not worth it in v1 |
| C. The platform authors master data and POs, and **the till receives** at the back door | The one reasonable split, since goods do arrive at the branch. But receiving is the transaction that writes the cost and the ledger, so the till would need to post receipts upstream (a new endpoint in POS-BE-021's style: idempotency, rejection codes, a PO that is no longer open). The till would also need platform POs and stock items in a table the seeder doesn't wipe (see the hazard in 3.2). **The dashboard is a responsive web app, and a phone at the back door does the same job with no contract** | Deferred (slice f). Revisit if the owner hears back-door demand |
| D. Leave it till-local on cloud (today's state) | Rows exist in no place the owner can see, and a group can't compare branches | Rejected: it's the status quo CB-09 exists to end |

**Recommendation, D1: option A.** Hiding is the Menu and Floor precedent.
Adding `ManagementPane.purchasing`, `.stock` and `.units` beside `.items` in
the till's `_authoringPanes` is enough. Hiding by **deployment mode**, not by
capability, matters: a till-local role can still grant `purchase.manage` on
cloud (the two-author roles case, `BACKOFFICE_TO_CLOUD.md` §4a Q3), so a gate
on capability alone would leak.

**Rows already on cloud tills (D2).** The no-merge rule means there is no
import. Deleting them is not the seeder's business either: the seeder doesn't
touch these tables, and a delete would destroy the only copy. So they are
**left in place**: hidden, reachable through the till's backup, and never
synced. The exposure is small. Cloud Wave 1 has **not** been deployed to
production (`docs/backend/CLOUD_WAVE1_PROGRESS.md:97`), so no production cloud
till holds any, and on a cloud till those rows can't reference stock anyway
(§1). If the owner wants them kept visible, that's option B for the affected
tills only, and it's the till's work.

### 3.2 Q2: Stock-only items vs the catalogue

| Option | Cost on the platform |
|---|---|
| A. A `MenuItem` flag (`is_stocked`, nullable `category_id`), the till's mig-40 shape | `menu_items.category_id` is **NOT NULL with cascade delete** (API `database/migrations/2026_06_27_002003_create_menu_items_table.php:15`). Relaxing it is a column change on a live table, and on SQLite it means a table rebuild. Every consumer of `MenuItem` would then need a guard: the public menu, `PublicMenuService`, import and export, `ReportService`, and `PlanLimitService`, which counts **every** `MenuItem` against `max_items` (`app/Services/PlanLimitService.php:26`). Buying chicken would eat the menu quota |
| **B. A separate `stock_items` table** with an optional unique `menu_item_id` | One ledger, keyed on `stock_item_id`. A product that is sold *and* counted, such as bottled water, links to its `MenuItem`. The catalogue is untouched |

The till's reason for option A was that a second table would be a second
ledger (`domain/models/stock_item.dart:6-11`). That doesn't carry over: on the
platform the ledger is keyed on `stock_items` from day one, so there is only
ever one.

**Recommendation, D3: option B.**

**How a stock item reaches a till:** in v1 it doesn't, because no cloud till
screen uses one (D1). **A constraint on any future slice-f work:** a platform
stock item must **never** be seeded into `pos_products` on a cloud till. The
seeder `DELETE`s `pos_products` (`bootstrap_seeder.dart:368-377`), and
`pos_stock_movements.product_id` is `ON DELETE RESTRICT` (MIG `:2620`). A
single movement against a product would make the delete fail and **roll back
the whole seed**, the same failure `BACKOFFICE_TO_CLOUD.md` §4a Q4 records for
combos. Any future block goes to its own till table.

### 3.3 Q3: Stock movements from sales

**The till does not deduct stock when it sells.** The only writer of
`pos_stock_movements` and `pos_stock_levels` in the till's code is
`PostgresReceivingRepository.receive` (`postgres_receiving_repository.dart:148-193`).
A grep of `lib/` for both table names finds no other INSERT, and no migration
has a trigger that writes them. The kind `sale` exists in the CHECK (MIG
`:2643`), but nothing writes it. The Stock pane says so: stock moves only when
a delivery is received, and counts, waste and adjustments are "the next wave"
(`management_stock_pane.dart:17-20`). The order payload carries
`menu_item_id` and an integer `quantity` per line
(`data/cloud/outbox_drain.dart:163-171`) and nothing about stock.

**What the platform figure means without it:** cumulative receipts per branch
(plus any adjustments, if slice d is approved), valued at the moving average.
That is **"bought and booked in"**, not "on hand now". The dashboard must say
so in both languages: the column is headed *Received to date*, with a
one-line note that sales are not deducted. It must not be called "On hand".

**Recommendation, D4:** no sales deduction on either side in v1. When it
comes, it's a recipes feature (menu item → stock item × quantity). On cloud,
the **platform** should derive the `sale` movements server-side from synced POS
orders: `order_items.menu_item_id` and `quantity` already arrive through
POS-BE-006 (`app/Services/PosOrderService.php:210-224`). That needs **no new
sync elements**. Adding stock elements to POS-BE-021 would mean the till
computing stock it doesn't compute today. It's recorded here so nobody files
that contract.

### 3.4 Q4: Multi-branch

It mirrors the till exactly:

- **Per restaurant:** suppliers (MIG `:2424`), units (`:3579`), stock items,
  and the PO reference sequence (`:2603-2608`, `PO-2026-000042`, per
  restaurant per year: `postgres_purchase_orders_repository.dart:273-290`).
- **Per branch:** purchase orders (`:2503`: *stock that arrived at Downtown is
  not stock Maadi can sell*), supplier invoices (`:2718`), supplier payments
  (`:2801`), stock movements (`:2619`) and stock levels (PK `(branch_id,
  product_id)`, `:2686`).
- The dashboard user is restaurant-wide (`User` has no branch). Pages carry a
  branch filter. PO, invoice and payment forms carry a branch picker that
  defaults to the only active branch when there is one.
- **Transfers between branches** (`transfer_in`, `transfer_out`) exist on the
  till as kinds only, with no writer. **Left out** until the till defines them.

**D5 as above.**

### 3.5 Q5: Entitlement and capabilities

**D6 (decided 2026-09-12, amended by the owner): a new
`Feature::PURCHASING = 'purchasing'`, standalone, with `requires() => []`.**
- It's sold, not inherited. Like `pos`, it stays out of `defaultSet()` and every
  plan's `feature_keys`, so it resolves to false for every existing tenant
  (API `app/Enums/Feature.php:29-36`, and `PlanEntitlementService`).
- **Not dependent on `pos`.** This design first recommended requiring `pos`,
  on the grounds that cost price pays off against POS sales. The owner
  overruled that: *"it not restaurant only, say it client can be cafe cloud
  kit and all of these"*. Purchasing is sold to any client type (restaurant,
  café, cloud kitchen, and so on), with or without a till. So:
  - the dashboard routes stack `feature:purchasing` on its own, **outside** the
    `feature:pos` group (§6);
  - the navigation has sidebar groups of its own, not the settings shell's
    "Point of sale & money" group, and no leaf carries `feature: 'pos'` (§7);
  - all new copy uses neutral wording: "business"/"client" in English,
    "النشاط"/"العميل" in Arabic, never "restaurant".
  - *Known and accepted:* for a client without a till, cost-in-reports
    (slice f) has only POS sales to cost against, because only POS orders
    carry `menu_item_id`. That is a limit of slice f, not a reason to gate.
- `feature.purchasing` is labelled "Purchasing & suppliers" /
  "المشتريات والموردون".
- Side effects to accept:
  - Plan requests validate `feature_keys.*` against `Feature::values()`
    (`app/Http/Requests/Admin/StorePlanRequest.php:25`), so the key appears in
    the plan editor.
  - The landing pricing card prints `feature.<key>`
    (`apps/landing/src/LandingView.vue:470`), so it needs `feature.purchasing`
    in EN and AR in `packages/ui/src/i18n/index.js` (`:52`, `:1296`), or a raw
    slug goes public.
  - Licence requests validate `features.*` against the same list, so it will
    appear in licence claims. The till parses licence `features` and gates
    nothing on them (POS `features/licensing/domain/license.dart:146`), so
    that is harmless.

**D7: one TenantCapability, `PURCHASE_MANAGE = 'purchase.manage'`**. It's the
till's exact string (POS `domain/models/permissions.dart:91`), and doc 16 §6
says *one capability, not five*. It gates **reads as well as writes**.
Suppliers aren't even granted to the till's credential, because *who the
restaurant owes money to* is its commercial position (doc 16 §6). Stock, items
and units sit under it too, as on the till (`management_screen.dart:336-339`).

Consequences inside the platform's per-verb RBAC, all checked:
- `resource()` = `purchase`, `action()` = `manage`. `implies()` looks for
  `purchase.view`, finds none, and returns null, the same as `pos.operate`
  (`app/Enums/TenantCapability.php`, `implies()`).
- `translateLegacy`/`legacyManageMap` only rewrite the eight listed
  `*.manage` values, so `purchase.manage` passes through untouched. **The enum
  comment must say that this `.manage` is a live single verb and must never
  join `legacyManageMap`**, because elsewhere in this enum `.manage` means
  "pre-split".
- `group()`: add `'purchase' => 'buying'`. The role builder already renders
  non-CRUD verbs as their own list with no frontend change
  (`WEB/pages/dashboard/RoleForm.vue:46-70`). It needs i18n: `capres.purchase`,
  `capaction.manage` and `capgroup.buying`, in EN and AR.
- `useCaps('purchase')` assumes view/create/update/delete verbs
  (`WEB/lib/useCaps.js`). The pages use `auth.can('purchase.manage') && !auth.isReadOnly`
  for writes and `auth.can('purchase.manage')` for reads.
- The owner holds it automatically (`User::tenantCapabilities()` returns every
  value), and so it would flow into the bundle. See D8.

*Owner may add later:* a read-only split (`purchase.view`) when a real screen
needs it, for example an accountant who reads but doesn't buy. Not now.

### 3.6 Q6: What the till needs from the platform

In v1, no data, in either direction. One thing on the wire changes whether we
like it or not. Once `purchase.manage` exists, the owner and anyone granted it
receive it in the bundle's `staff[].capabilities` (API
`app/Services/PosBootstrapService.php:249-264`). The seeder canonicalises it
into `pos_staff.capabilities` (`bootstrap_seeder.dart:322-325`). And
`purchase.manage` *is* the till's canonical name, so **every build before the
pane-hiding change would light up the till-local Purchasing pane** for exactly
the people the platform just made buyers. That's two authors by accident.

**D8 (built in slice a):** the cloud bundle **withholds** `purchase.manage` from
`staff[].capabilities`, which is one filter in `PosBootstrapService::staff()`.
It is unconditional, not tied to the `purchasing` flag: the owner holds every
capability whether or not the client bought purchasing, so the key would reach
a till even on a `pos`-only client. A client without `pos` has no bundle at
all, so D6's standalone ruling doesn't change this.
It's permanent rather than a stopgap: on cloud no till screen checks it, and a
key nothing checks is the thing doc 16 §6 refuses. With the till's
hide-by-mode change (D1), this is belt and braces.

Draft text below. **To be filed as POS-BE-030 on approval**, written to both
repos' `POS_TO_BACKEND.md`/`BACKEND_TO_POS.md`, which this round deliberately
doesn't touch:

> **POS-BE-030: Purchasing and stock on a cloud terminal are platform-authored** · PROPOSED
>
> **Rule.** On a terminal whose deployment is `cloud`, the platform is the
> only author of suppliers, purchase orders, receiving, supplier invoices,
> supplier payments, units and stock items. The till does not show its
> Purchasing, Items, Stock or Units panes on cloud, **whatever capabilities
> the signed-in person holds** (including grants from a till-local role).
> Offline terminals are unchanged.
>
> **Bundle.** No new key. `staff[].capabilities` in a bundle **never contains
> `purchase.manage`**, even for the owner, even though the platform's
> TenantCapability of that name exists and is held on the dashboard. A till
> that finds it there anyway (an older platform) ignores it on cloud under the
> rule above.
>
> **Existing rows.** Till-local purchasing, supplier, unit and stock rows
> already on a cloud terminal are not deleted, not imported and not synced.
> They remain in the till's backup.
>
> **Sync.** Nothing in POS-BE-006/009/021 changes. The platform derives
> nothing from till purchasing. A supplier payment made out of a cloud
> terminal's drawer is recorded at the till as a `pay_out` cash movement
> (POS-BE-009, unchanged), and the dashboard may link a supplier payment to
> that synced movement (platform-side only; no wire change).
>
> **Till work (`pos-dev`).** Add `purchasing`, `stock` and `units` to the
> panes hidden on cloud (`management_screen.dart` `_authoringPanes`, beside
> `items`), with the Manage-menu entries following `managementPanesFor`. Add a
> test that a cloud till with `purchase.manage` granted locally shows none of
> the four.
>
> **Platform work (`xorder-cloud`).** Filter `purchase.manage` out of
> `PosBootstrapService::staff()`. Add a test that the owner's bundle
> capabilities exclude it while `/api/auth/me` includes it.

**For a future slice f** (not proposed now): wire shapes, if receiving at the
till or read-only stock is ever wanted. Quantities are integer thousandths
and money is integer minor units, as in §4:
`stock: { units: [{code, name_en, name_ar, allows_fraction}], items: [{id, name_en, name_ar, unit_code, menu_item_id}] }`,
and upstream `POST /api/pos/stock-receipts {client_transaction_id, purchase_order_id, lines: [{line_id, quantity_milli}], occurred_at}`.
That would need the till-table constraint in 3.2.

### 3.7 Q7: Phasing

See §9.

---

## 4. Proposed platform tables

The rules for all of them:
- **Additive.** Every table is new and nothing existing changes.
- **Tenant-scoped.** Each has `restaurant_id` (FK, cascade on delete), and
  the model uses `BelongsToRestaurant`. `restaurant_id` is never taken from
  input. Child rows get it stamped from the parent, the way `OrderItem` does
  (`PosOrderService.php:217`).
- **Money** is integer minor units in `unsignedBigInteger`, or signed
  `bigInteger` where it can go negative. Rates are basis points.
  **Quantities** are signed `bigInteger` thousandths. `currency` and
  `exponent` are snapshotted on money documents, as the till does.
- **No stored balances** of any kind.
- Timestamps are Laravel's, and actors are `users` FKs with null on delete.

**The portable replacements for the till's partial indexes and CHECKs.**
Laravel's Blueprint has no CHECK, and partial indexes differ between SQLite
and PostgreSQL. So:
1. A **nullable column plus a plain unique index** stands in for "unique where
   set". SQLite and PostgreSQL both treat NULLs as distinct in a unique index.
2. CHECK-type rules live in the FormRequest, and are asserted again in the
   service inside the transaction.

### 4.1 `units`
`id`, `restaurant_id`, `code` string(16), `name_en` string(120), `name_ar`
nullable, `eta_unit_type` string(6) default `EA`, `allows_fraction` bool
default false, `is_active` bool default true, `sort_order` uint default 0,
timestamps. **unique(`restaurant_id`, `code`)**.
- `code` must match `^[a-z][a-z0-9_]{0,15}$` (FormRequest) and is
  **immutable**: the update request doesn't accept it. `eta_unit_type` must
  match `^[A-Z0-9]{1,6}$`.
- There's no DELETE route; retire with `is_active=false`.
- The seven defaults (MIG `:3599-3605`, EN and AR names verbatim) are created
  idempotently by `UnitCatalog::ensureDefaults()` on the first units read of a
  `purchasing` tenant. It uses `firstOrCreate` on the unique key, and a race
  loses to the unique index and retries, like `InvoiceSequenceService`.

### 4.2 `suppliers`
`id`, `restaurant_id`, `name_en` string(160), `name_ar`, `code` string(40)
**nullable** (the till stores `''`; NULL here makes a plain unique work),
`contact_name`, `phone`, `email`, `address` text, `tax_number` string(9)
nullable (exactly nine digits, Arabic-Indic digits folded), `payment_term_days`
uint default 0, `notes` text, `is_active` bool default true, `updated_by`,
timestamps.
- **unique(`restaurant_id`, `code`)** and index(`restaurant_id`, `is_active`, `name_en`).
- **No balance column.** No DELETE: retire with `is_active=false`.
- `Auditable`.

### 4.3 `stock_items`
`id`, `restaurant_id`, `menu_item_id` nullable FK → `menu_items`
**nullOnDelete**, `name_en` string(160), `name_ar`, `sku` string(64)
nullable, `unit_code` string(16), `is_active` bool default true, timestamps.
- **unique(`menu_item_id`)**. NULLs are distinct, so any number of stock-only
  items can exist, but a menu item is counted once.
- index(`restaurant_id`, `is_active`).
- `unit_code` must name a unit of this restaurant (checked in the
  FormRequest). **It can't change once the item has a movement.** That is the
  honest form of the till's no-conversion rule (§10 C3).
- The name is prefilled from the linked menu item and not synced back to it.
  Editing a stock item never reprices or renames the menu.

### 4.4 `purchase_orders`
`id`, `restaurant_id`, `branch_id` FK **restrict**, `supplier_id` FK
**restrict**, `supplier_name` string(160) snapshot, `reference` string(32),
`status` string(20) default `draft`, `currency` char(3), `exponent` tinyint,
`subtotal_minor`, `tax_minor`, `total_minor` unsigned bigint default 0
(snapshotted at send), `ordered_at`, `expected_at` nullable, `notes` text,
`created_by`, `updated_by`, timestamps.
- **unique(`restaurant_id`, `reference`)**; index(`restaurant_id`, `branch_id`,
  `status`); index(`supplier_id`, `ordered_at`).
- `status` is a PHP backed enum `PurchaseStatus`, carrying the till's five
  values and its `isEditable`, `isOpen` and `isClosed` rules.

### 4.5 `purchase_order_lines`
`id`, `restaurant_id`, `purchase_order_id` FK **cascade**, `stock_item_id`
nullable FK **nullOnDelete**, `description` string(200) snapshot, `sku`
nullable, `ordered_milli` bigint, `received_milli` bigint default 0,
`unit_code` string(16) default `ea`, `unit_cost_minor` unsigned bigint,
`tax_rate_bp` uint default 0, `sort_order` uint, timestamps.
- index(`purchase_order_id`, `sort_order`); index(`stock_item_id`).
- Rules: `ordered_milli > 0` and `0 ≤ tax_rate_bp ≤ 10000`. When
  `stock_item_id` is set, `unit_code` is **forced to the item's unit**, as the
  till's dialog locks it (`purchase_order_dialog.dart:344,605`). A fraction
  (`milli % 1000 ≠ 0`) is refused on a unit with `allows_fraction=false`.

### 4.6 `purchase_sequences`
`id`, `restaurant_id`, `period` string(8), `next_value` unsigned bigint default 1,
timestamps. **unique(`restaurant_id`, `period`)**.
- `PurchaseSequenceService::next()` is a copy of `InvoiceSequenceService`:
  `lockForUpdate`, then a create that falls back to a locked re-read on a
  unique violation.
- The number is consumed at **send**, not at draft, so a thrown-away draft
  leaves no gap. The till numbers drafts, but only a sent PO is a document the
  supplier sees. *Small deliberate difference; owner may overrule.*
- Format `PO-{YYYY}-{NNNNNN}`.

### 4.7 `stock_movements` (append-only)
`id`, `restaurant_id`, `branch_id` FK **restrict**, `stock_item_id` FK
**restrict**, `kind` string(16), `quantity_milli` bigint (signed, ≠ 0),
`unit_code`, `unit_cost_minor` unsigned bigint, `balance_milli` bigint,
`average_cost_minor` unsigned bigint, `purchase_order_id` nullable
nullOnDelete, `purchase_order_line_id` nullable nullOnDelete, `reason` string(32)
nullable, `note` text nullable, `occurred_at`, `created_by`, `created_at` (no
`updated_at`).
- index(`stock_item_id`, `branch_id`, `occurred_at`, `id`);
  index(`restaurant_id`, `branch_id`, `occurred_at`).
- **Append-only by construction.** There's no update or delete route, and
  the model's `updating` and `deleting` events throw.
- `kind` is the till's seven. v1 writes only `receipt`, plus `opening`,
  `adjustment` and `waste` if slice d is approved.

### 4.8 `stock_levels` (a justified cache, as on the till)
`id`, `restaurant_id`, `branch_id` FK **restrict**, `stock_item_id` FK
**restrict**, `quantity_milli` bigint signed default 0, `unit_code`,
`average_cost_minor` unsigned bigint default 0, `updated_at`.
- **unique(`branch_id`, `stock_item_id`)**.
- Written only by `StockService`, in the same transaction as the movement,
  under `lockForUpdate`. Each movement stores the resulting position, so drift
  can be *found* by replay. An optional artisan `stock:verify` comes later.

### 4.9 `supplier_invoices`
`id`, `restaurant_id`, `branch_id` FK restrict, `supplier_id` FK restrict,
`supplier_name`, `purchase_order_id` nullable nullOnDelete,
`purchase_order_reference` nullable, `number` string(64),
**`active_number_key` string(64) nullable**, `currency`, `exponent`,
`total_minor` unsigned bigint, `tax_minor` unsigned bigint default 0,
`issued_at` date, `due_at` date, `note`, `voided_at`, `voided_by`,
`void_reason` string(32) nullable, `void_note`, `created_by`, `updated_by`,
timestamps.
- **unique(`restaurant_id`, `supplier_id`, `active_number_key`)**.
  `active_number_key = lower(trim(number))` while live, and NULL once voided.
  That's the portable version of the till's partial unique (MIG `:2776-2778`):
  a voided number can be entered again, and a live duplicate can't.
- index(`restaurant_id`, `branch_id`, `due_at`); index(`supplier_id`,
  `issued_at`); index(`purchase_order_id`).
- **No subtotal and no balance column** (subtotal = total − tax, and what's
  outstanding is derived).
- `void_reason` is a PHP enum carrying the till's six `invoice_void` codes,
  with `other` requiring a note (MIG `:2972-2977`). The platform has no
  `pos_reason_codes` table, and restaurant-editable reason lists are not in
  scope.
- `due_at` defaults in the form to `issued_at` plus the supplier's terms, and
  is stored, never derived (`supplier_invoice.dart:210`, MIG `:2740-2742`).

### 4.10 `supplier_payments`
`id`, `restaurant_id`, `branch_id` FK restrict, `supplier_id` FK restrict,
`supplier_name`, `supplier_invoice_id` nullable FK **restrict** (null = on
account), `method` string(16) (`cash|bank_transfer|cheque|card|other`),
`amount_minor` unsigned bigint, `currency`, `exponent`, `reference` nullable,
`paid_at`, `note`, **`pos_cash_movement_id` nullable FK → `pos_cash_movements`
nullOnDelete**, `voided_at`, `voided_by`, `void_reason` string(32), `void_note`,
`created_by`, timestamps.
- **unique(`pos_cash_movement_id`)**, one pay-out per payment (MIG `:3079`),
  with NULLs distinct.
- index(`supplier_id`, `paid_at`); index(`supplier_invoice_id`);
  index(`restaurant_id`, `reference`).
- `void_reason` is an enum carrying the till's six `payment_void` codes.

**D13, the drawer link.** On cloud, a supplier paid out of the till is already
a synced `pos_cash_movements` row (POS-BE-009): `direction` in/out, plus
`amount_minor` and `reason` (API
`database/migrations/2026_09_02_000900_create_pos_shifts_and_cash_movements_tables.php:50-66`).
The payment form can pick one of those. The service enforces the migration-33
rules (MIG `:3095-3135`): the movement is this restaurant's, its direction is
`out`, the amounts are **exactly equal**, and it isn't already linked. This
is the only till↔platform touchpoint in CB-09, and it needs no new contract.

---

## 5. Cross-row invariants: where and why (D10)

**A service with a row lock, backed by the portable constraints above. Not DB
triggers.** The till's triggers are PL/pgSQL. The platform runs SQLite in dev
and PostgreSQL in prod with identical Eloquent code, and the backend rules
forbid engine-specific SQL. A trigger written twice is two rules that drift
apart. Every write to these tables goes through a service. There's no mass
assignment path around them: no generic CRUD for ledger rows, and the ledger
models refuse update and delete.

| Invariant | Enforced by | Lock |
|---|---|---|
| Allocations to an invoice (live payments + new one) ≤ `total_minor` | `SupplierLedgerService::pay()` | `lockForUpdate` on the invoice row, then `SUM` of live payments in the same transaction |
| A payment's invoice has the same supplier, isn't voided, and is this tenant's | same | same |
| An invoice can't be voided while it has live payments | `SupplierLedgerService::voidInvoice()` | lock the invoice row |
| An invoice's figures can be edited only while nothing is allocated to it; after that, void and re-enter | `SupplierLedgerService::updateInvoice()` | lock the invoice row |
| No duplicate live invoice number per supplier | unique on `active_number_key` (DB) | none |
| The drawer link is an `out` movement for the same amount, used once | `SupplierLedgerService::pay()` plus the unique index | lock the movement row |
| PO transitions follow `PurchaseEngine`: edit only a draft; send only a draft with lines; cancel only draft or sent | `PurchaseOrderService` | `lockForUpdate` on the PO, **with the status re-checked under the lock** (closes the till's gap, §10 C2) |
| Receiving only against an open PO. The five-part write is atomic, the average uses `StockCosting`, the status follows the lines | `ReceivingService::receive()` | lock the PO, then each line, then each `(branch, item)` level row, **in ascending id order** so two receipts can't deadlock |
| Movements are append-only; the level equals the last movement's balance | `StockService` plus model events | level-row lock |
| A stock item's unit is fixed once it has movements | `StockItemService::update()` | lock the item |
| The branch, supplier, stock item and invoice named in a body belong to this tenant | FormRequest `Rule::exists(...)->where('restaurant_id', tenant)` → **422** (the `tender_type_id` precedent). URL-bound models resolve through `RestaurantScope` → **404** | — |

**On SQLite, `lockForUpdate` is a no-op**, but SQLite allows a single writer
per database, so check-then-write inside a transaction stays serial. The worst
outcome is a `SQLITE_BUSY` retry in dev, never a double allocation. PostgreSQL
gets real row locks. Tests run on SQLite, so the lock itself is proved on
PostgreSQL by review. The rule (over-allocation refused) is proved by tests.

**Derived figures use portable SQL only**: `SUM`, `COALESCE`, and `CASE`
instead of `GREATEST`, which SQLite lacks. The till uses `GREATEST` at
`postgres_supplier_invoices_repository.dart:248`. SUMs are cast to int in PHP.

**`pos_config_version` is not bumped** by any of these models. Nothing here
is in the bundle, so hooking them into `PosConfigVersion::registerHooks()`
would make every supplier edit re-pull every till for nothing. If a later
slice adds a bundle block, the hook goes in then.

---

## 6. API (all under `/api/dashboard`)

Gate stack (the POS money-config block in `routes/api.php:540-574` is the
template): `role:<tenant roles>` → `feature:purchasing` → `can:purchase.manage`
→ `subscription.writable` on writes. The route comment explains why reads are
gated on `.manage` too. The group sits **beside** the `feature:pos` group, not
inside it (D6): a client with `purchasing` and no `pos` passes the whole stack.

| Slice | Method | Path | Notes |
|---|---|---|---|
| a | GET / POST / PUT | `units`, `units/{unit}` | no DELETE; `code` immutable |
| a | GET / POST / PUT | `suppliers`, `suppliers/{supplier}` | no DELETE; retire via `is_active` |
| b | GET / POST / PUT | `stock-items`, `stock-items/{stockItem}` | unit fixed once it has movements |
| b | GET / POST | `purchase-orders` | list filterable by `branch_id`, `status`, `supplier_id` |
| b | GET / PUT | `purchase-orders/{purchaseOrder}` | PUT is draft only, and replaces the lines wholesale (as the till's editor does) |
| b | POST | `purchase-orders/{po}/send` | snapshots totals, numbers it, sets `ordered_at` |
| b | POST | `purchase-orders/{po}/cancel` | draft or sent only |
| b | POST | `purchase-orders/{po}/receipts` | `{lines:[{line_id, quantity_milli}], occurred_at?, note?}`; open PO only |
| b | POST | `purchase-orders/{po}/close` | **only if D11 is approved**: sets `received` on a partial order, with a reason |
| b | GET | `stock-levels?branch_id=` | "received to date", value at the average |
| b | GET | `stock-items/{stockItem}/movements?branch_id=` | the ledger, paginated |
| c | GET / POST / PUT | `supplier-invoices`, `supplier-invoices/{invoice}` | PUT only while unallocated |
| c | POST | `supplier-invoices/{invoice}/void` | `{reason, note?}` |
| c | GET / POST | `supplier-payments` | optional `supplier_invoice_id`, optional `pos_cash_movement_id` |
| c | POST | `supplier-payments/{payment}/void` | `{reason, note?}` |
| c | GET | `suppliers/{supplier}/account`, `suppliers/balances` | invoiced, paid, outstanding, overdue, on account, all derived |
| c | GET | `pos-cash-movements?direction=out&unlinked=1&branch_id=` | candidates for the drawer link |
| d | POST | `stock-adjustments` | **held (D12)**: `{branch_id, stock_item_id, kind: opening\|adjustment\|waste, quantity_milli, unit_cost_minor?, reason, note?}` |

Every write goes through `AuditLogger::record()`: send, cancel, receive,
close, void and pay. The models use `Auditable`. Tests (per slice) cover:
- the gate stack: feature off → 403 or 404 per the `EnsureFeatureEnabled`
  convention; no capability → 403; lapsed → the `subscription_inactive` 403;
- cross-tenant URL ids → 404, and cross-tenant body ids → 422;
- every invariant in §5;
- `StockCosting` parity with the till's cases;
- the owner's bundle excluding `purchase.manage` (D8).

---

## 7. Dashboard pages (`apps/web`, D14)

**The sidebar, not the settings shell.** These are daily working screens, not
configuration. Two new groups in `pages/dashboard/nav.config.js`. Every leaf
carries `feature: 'purchasing'` and `capability: 'purchase.manage'`, so an
empty group hides itself (`nav.config.js:96-110`). **No leaf carries
`feature: 'pos'`, and nothing goes in the settings shell's "Point of sale &
money" group** (`settings.config.js` `group_pos`): purchasing is standalone
(D6). The groups sit after "Place Management" and before "Customers &
Engagement".

| Group (EN / AR) | Leaf | Route name | Path |
|---|---|---|---|
| Purchasing / المشتريات | Purchase orders | `dashboard.purchasing.orders` | `/purchasing/orders` (+ `/purchasing/orders/:id`) |
| | Supplier invoices | `dashboard.purchasing.invoices` | `/purchasing/invoices` |
| | Payments | `dashboard.purchasing.payments` | `/purchasing/payments` |
| | Suppliers | `dashboard.purchasing.suppliers` | `/purchasing/suppliers` (+ `/:id` account view) |
| Inventory / المخزون | Stock | `dashboard.inventory.stock` | `/inventory/stock` (+ `/inventory/stock/:itemId` movements) |
| | Stock items | `dashboard.inventory.items` | `/inventory/items` |
| | Units | `dashboard.inventory.units` | `/inventory/units` |

The router uses `meta: { capability: 'purchase.manage' }`. Pages follow the
anatomy in the web skill:
- `withMinDuration` loading, `ListSkeleton`/`TableSkeleton`, `ErrorState`,
  `FormError` for 422s, `Modal`, and `confirm()` for cancel and void.
- The **receive modal** prefills every line with what's still owed
  (`receive_dialog.dart:14`).
- The **payment modal** shows the room left on the invoice and offers "on
  account".
- The **stock page** is headed *Received to date* / *المستلم حتى الآن*, with a
  note that sales aren't deducted (D4).

**Quantities in the browser:** a new `lib/quantity.js` mirrors
`Quantity.tryParse`. It splits on the point, allows at most three decimals,
never uses a float, folds Arabic-Indic digits through `enDigits.js`, and
returns `milli`. Money reuses `lib/money.js` (`amountToMinor`/`formatMinor`
with the restaurant's exponent, as `PosMoneyView.vue` does).

**Both languages, neutral wording (D6):** every string in
`packages/ui/src/i18n/index.js`, EN and AR, in a new `purchasing.*` namespace.
New copy says "business"/"client" and "النشاط"/"العميل", never "restaurant";
existing strings are not renamed. Covered:
- the nav, all page strings, and the void-reason labels (the till's AR strings
  at MIG `:2972-2993` can be reused);
- the unit names;
- `feature.purchasing`, `capres.purchase`, `capaction.manage`, `capgroup.buying`.

**RTL:** logical properties only. Numbers and references go in `.mono`
LTR-isolated spans, so `PO-2026-000042` and `12.5 kg` don't reorder in Arabic.
Tables scroll in their own `overflow-x:auto`.

---

## 8. What the owner is approving

Each is approvable alone: **D1–D14** above. **Decided 2026-09-12:** item 1
(D1, option A; D2 follows), item 2 (D6, amended: standalone, no `pos`) and
item 3 (D7, a single `purchase.manage`), plus the build order a → b → c.
**Still open:** items 4–7. Several of these need a real choice rather than a
nod:

1. **D1/D2.** The platform is the only author on cloud. Cloud tills lose
   their Purchasing, Units and Stock panes. Rows already there stay hidden and
   aren't imported. *Or* option C: receiving stays at the till, which is
   bigger and needs a contract.
2. **D6.** `purchasing` requires `pos`. *Or* it's sellable to a QR-only
   restaurant.
3. **D7.** A single `purchase.manage` that gates reads too. *Or* a view split
   now.
4. **D11.** Build short-close (`close`) on the platform, ahead of the till,
   and have `pos-dev` add it to the till too. *Or* leave part deliveries
   `partially_received` forever, as the till's code does today.
5. **D12.** Stock adjustments, opening balances, waste and counts: wait for
   the till's inventory wave, *or* design them once for both now.
6. **Plan placement.** Which plans get `purchasing`. The landing card changes
   the moment an active plan carries it.
7. **Deploy prerequisite.** Every slice assumes Cloud Wave 1 is live on
   xorder.io. It isn't yet (`BACKOFFICE_TO_CLOUD.md` §5.3).

---

## 9. Phasing

| Slice | Contents | Size | Till work (`pos-dev`)? | Accepted when |
|---|---|---|---|---|
| **a. Foundations: suppliers and units** *(built, §13)* | `Feature::PURCHASING` (standalone, no `pos`); `TenantCapability::PURCHASE_MANAGE` + group + labels; `units` + `UnitCatalog::ensureDefaults`; `suppliers`; the two nav groups (Suppliers and Units live); `purchase.manage` withheld from the bundle (D8) | M | **No** | Migrations are additive and reversible. The feature is false for every existing tenant (test). `purchase.manage` is absent from the owner's bundle (test). Cross-tenant 404/422. Units are seeded once, idempotently; `code` is immutable; no delete route. Supplier tax number is nine digits; code is unique when set, and many suppliers can have none. EN and AR plus RTL checked; `pnpm --filter web build` clean; `php artisan test` green |
| **b. Stock items, POs, receiving, cost** *(built, §14)* | `stock_items`, `purchase_orders`, `_lines`, `purchase_sequences`, `stock_movements`, `stock_levels`; `PurchaseOrderService`, `ReceivingService`, `StockCosting` (PHP); the PO list, detail and receive modal; read-only Stock and movements pages | L | **No** | A `StockCosting` parity table matches the till's (including a negative on-hand, and the half-up edge like 0.333 kg at 47.30). Send snapshots totals, with tax rounded per rate. Cancel is refused once anything arrived, with the status re-checked under the lock. Over-receipt is accepted. The status follows the lines. Lines with no item touch no ledger. A movement's balance and average equal the level's. Movements can't be updated or deleted. The unit is locked once movements exist. Two receipts on one item are serialised (reviewed on PG). References are gap-free per restaurant per year |
| **c. Supplier invoices and payments** | `supplier_invoices`, `supplier_payments`; `SupplierLedgerService`; void reasons; derived balances and overdue; optional drawer link (D13) | M–L | **No** | Over-allocation is refused with the room named. Paying a voided invoice or another supplier's invoice is refused. An invoice with live payments can't be voided. A voided number can be re-entered and a live duplicate can't. On-account payments reduce the balance and not overdue (a test mirroring `supplier_invoice.dart:421-470`). The drawer link is refused unless it's an unlinked `out` movement of equal amount. No balance column exists anywhere |
| **d. Stock adjustments** *(held, D12)* | `opening`, `adjustment`, `waste` movements with reasons; the adjustment modal | M | No, but the till would want the same kinds, so it's better designed together | Issue movements keep the average (`StockCosting::issue`). Openings set the cost when nothing is on hand. Every change is a movement with a reason, never an edit to a level |
| **e. Till integration** | File **POS-BE-030** (§3.6); `pos-dev` hides Purchasing, Stock and Units on cloud by deployment mode | S | **Yes** (small) | On a cloud till with `purchase.manage` granted locally, none of the four panes or their Manage-menu entries appear (test). Offline is unchanged. Existing local rows are untouched |
| *f. Later, not proposed* | Receiving at the till; read-only stock on the till; sales deduction via recipes (derived server-side from synced orders, §3.3); transfers; cost in reports and COGS | — | yes, for the till parts | — |

**Approved order (owner, 2026-09-12): a → b → c**, built one slice at a time
with an owner review between slices. **e** is not approved: POS-BE-030 is not
filed and the till is not changed (the D8 filter, built in slice a, already
protects old builds). **d** waits for D12.

---

## 10. Where the till's code and doc 16 disagree

Found while reading. None of it is fixed here, because xorder-pos belongs to
`pos-dev`. The platform design takes the stricter reading in each case.

- **C1. Short-closing a part delivery has no implementation.** Doc 16 §6 says
  the way out of a part delivery is to *close the difference*, and
  `PurchaseStatus.received` is documented as *"All of it arrived, or somebody
  closed the difference deliberately"* (`purchase_order.dart:29`). No code
  does that. The pane calls `setStatus` only with `sent` and `cancelled`
  (`management_purchasing_pane.dart:215-231`), and receiving derives
  `received` only when every line is full
  (`postgres_receiving_repository.dart:209-213`). **A short-delivered PO stays
  `partially_received` forever.** That is D11.
- **C2. "No cancelling once goods have arrived" is enforced only by the
  button.** `PurchaseEngine.cancel` refuses it (`purchase_order.dart:379-387`),
  but the pane never calls `PurchaseEngine`. It calls
  `repository.setStatus(cancelled)` directly (`management_purchasing_pane.dart:226-231`).
  `setStatus` updates `WHERE id AND restaurant_id` with no status
  precondition (`postgres_purchase_orders_repository.dart:294-318`), and no
  CHECK or trigger guards the transition. The only guard is that Cancel is
  shown on `sent` only (`management_purchasing_pane.dart:653`). A receipt
  booked from another back-office session between render and tap would let a
  partially received order be cancelled. The same bypass means `send` doesn't
  refuse an order with no lines. *The platform re-checks the status under a
  lock (§5).*
- **C3. "No unit conversion… refuses rather than converting" is not
  enforced.** The refusal is a Dart `assert` (`stock_costing.dart:75-80`,
  `quantity.dart:98-106`), which release builds strip, and it can never fire
  anyway. Receiving builds the *before* position with the **line's** unit, not
  the stored level's (`postgres_receiving_repository.dart:127-140`: the query
  doesn't select `pos_stock_levels.unit`). Then it overwrites the level's
  unit (`:181`). The PO dialog locks a line's unit to the item's
  (`purchase_order_dialog.dart:344,605`), so this only bites after an item's
  unit is changed while it holds stock. The Items pane allows that
  (`postgres_stock_items_repository.dart`, the `stock_unit = @unit` updates).
  In that case 10 box + 5 kg is stored as 15 kg. *The platform fixes the unit
  once movements exist (§4.3).*
- **C4. The chain in doc 16 §3 has supplier invoices feeding cost price. In
  the code they don't.** Cost comes from the PO line's `unit_cost_minor` at
  receipt (`postgres_receiving_repository.dart:109,142`). The receive dialog
  has no cost field, and a supplier invoice is a header with no lines that
  never touches stock. The real chain is *PO cost → receipt → moving average*,
  with invoices on a separate money track. That is consistent in itself, but
  the doc overstates it. *The platform mirrors the code, not the diagram.*
  An invoice priced differently from its PO does not reprice stock.
- *Stale, not contradictory:* doc 16 §6 still lists receiving as "to build",
  and the valuation method as undecided. Both are done: moving average,
  9 Sept (`stock_costing.dart:3-11`). Also, `stock_costing.dart:15-16` refers
  to storing the average "in `pos_products`", but it lives in
  `pos_stock_levels` and on each movement (MIG `:2675-2688`, `:2635-2636`).
  And doc 16's "one rounding point (`costAt`)" is true for a line's value, but
  the chain has three: `costAt`, tax per rate (`percentBp`), and the average
  (`stock_costing.dart:97`). The PHP port reproduces all three.

---

## 11. Risks

- **Moving average is a fold.** A bug in the port, or a movement written
  outside `StockService`, silently corrupts every later cost. *Mitigation:*
  the parity table against the till's cases, the resulting position stored on
  every movement, append-only models, and a future `stock:verify` replay.
- **Locking is proved on PostgreSQL by review only.** Tests run on SQLite,
  where `lockForUpdate` is a no-op. *Mitigation:* the rules themselves are
  tested, and locks are taken in a fixed order.
- **The landing page is public.** Adding `purchasing` to an active plan
  changes the pricing card at once, and a missing label prints a slug.
- **`.manage` means two things in one enum.** It's "legacy" for eight values
  and "live" for `purchase.manage`. *Mitigation:* the enum comment and a test
  that `expand(['purchase.manage'])` returns exactly `['purchase.manage']`.
- **"Received to date" will be read as "on hand".** *Mitigation:* the label
  and note (D4), and no low-stock alerts until sales are deducted.
- **Hidden rows on a cloud till.** A restaurant that typed purchasing into a
  cloud till loses sight of it (D2). The exposure is near zero until Wave 1
  deploys.
- **Scope creep toward accounting lite.** Payables are a report away. It's
  deliberately not in these slices.

## 12. Deliberately left out

- Sales deduction and recipes (D4).
- Transfers between branches.
- Stock counts, waste, adjustments and openings (D12).
- Receiving at the till (option C, slice f).
- Any bundle block.
- Supplier credit notes as documents (voiding with reason `credit_note`
  covers the till's case).
- Restaurant-editable reason lists.
- Multi-currency purchasing (the restaurant's currency only).
- A `purchase.view` split.
- Cost price shown on the menu or in reports.
- Payables and accounting lite.
- Any change to xorder-pos, `POS_TO_BACKEND.md` or `BACKEND_TO_POS.md`
  this round.

---

## 13. Slice a as built (2026-09-12)

Branch `feat/cb-09-purchasing` in xorder-new. Committed as `dd9a530`; not
deployed.

**Built:** `Feature::PURCHASING` (standalone); `TenantCapability::PURCHASE_MANAGE`
in group `buying`, with server labels in EN and AR (`xorder.capabilities.purchase_manage`)
and web labels (`capres.purchase`, `capaction.manage`, `capgroup.buying`);
migrations `2026_09_12_000100_create_units_table` and
`2026_09_12_000200_create_suppliers_table`; models `Unit` and `Supplier`
(`BelongsToRestaurant` + `Auditable`); `UnitCatalog::ensureDefaults`;
Store/Update requests; `Dashboard\UnitController` and `SupplierController`;
the route group `feature:purchasing` + `can:purchase.manage` (+
`subscription.writable` on writes), beside `feature:pos` and not inside it;
the D8 filter in `PosBootstrapService::staff()`; sidebar groups Purchasing
(Suppliers) and Inventory (Units); `purchasing/SuppliersView.vue` and
`inventory/UnitsView.vue`; `purchasing` in `PlanForm.vue`.

**Departures from §4 and §6, with reasons:**
- **`name_en` is nullable on both tables.** At least one of `name_en`/`name_ar`
  is required (FormRequest). §4 had `name_en` NOT NULL, but every bilingual
  record on the platform accepts either language, and an Arabic-only client
  must be able to name a supplier.
- **GET `units/{unit}` and `suppliers/{supplier}` exist.** They're cheap, and
  they give a URL-bound read that proves cross-tenant access returns 404.
- **No Policies.** The codebase has no `app/Policies`. Isolation is
  `RestaurantScope` route binding (404), and authorization is route middleware,
  as for every other dashboard resource.
- **Audit goes to the activity file.** Since commit 83edd4e, `AuditLogger`
  writes the daily activity file only, not `audit_logs`. `Auditable` records
  `supplier.created/updated` and `unit.created/updated`. Seeding the seven
  default units is suppressed (`withoutEvents`), so opening the page doesn't
  log seven creations in the reader's name.
- **Default units are seeded by "create the missing codes"**, not by
  `firstOrCreate` per row. The outcome is the same, and one query per read.
  It's idempotent because units are never deleted: a retired default stays
  retired, and a hand-made unit that took a default code first is kept.
- **`payment_term_days` is capped at 3650.** The till has no upper bound;
  this is only a sanity bound.
- **Units have no `updated_by`** (§4.1 didn't list one); suppliers do.
- **No `pos_config_version` hook**, as §5 says: nothing here is in the bundle.

**Deliberately not in slice a:** the supplier account page
(`/purchasing/suppliers/:id`, slice c); `lib/quantity.js` (slice b); the
Stock and Stock items leaves (slice b); a `purchasing` toggle in the Super
Admin's custom-client (no-plan) mode of `RestaurantForm.vue`. `pos` isn't
offered there either, so a no-plan client gets purchasing only by moving
to a plan that carries it. That's an owner call if wanted.

**What slice b builds on:**
- `units.code` is the key. `stock_items.unit_code` and PO lines store the
  code; validate it with `Rule::exists('units','code')->where('restaurant_id', …)`.
  **Call `UnitCatalog::ensureDefaults()` before that check**, because a tenant
  can create a stock item before it ever opened the Units page.
  `units.allows_fraction` drives the "no fraction on a whole unit" rule.
- `suppliers.id` is the target of `purchase_orders.supplier_id` (RESTRICT).
  The name snapshot must take whichever of `name_en`/`name_ar` is set, since
  either may be null.
- Retired suppliers and units (`is_active = false`) must not be offered for
  new POs, but must still resolve on old ones.
- Extend the existing route group and the Inventory nav group, and add keys
  to the `purchasing.*` i18n namespace. The gate is `purchase.manage` for
  everything.

---

## 14. Slice b as built (2026-09-12)

Branch `feat/cb-09-purchasing` in xorder-new, on top of `dd9a530`.
Uncommitted and not deployed. Built on the owner's "go slice b". A first
session started it and was cut off; this one reviewed its drafts, finished
them and built the rest.

**Built (API):**
- Migrations `2026_09_12_000300_create_stock_items_table`,
  `…000400_create_purchase_orders_tables` (`purchase_orders`,
  `purchase_order_lines`, `purchase_sequences`) and
  `…000500_create_stock_ledger_tables` (`stock_movements`, `stock_levels`).
  All five tables are new, and nothing existing is altered. Every table
  carries `restaurant_id` with a cascade, and every model uses
  `BelongsToRestaurant`. Each `down()` drops only its own tables. There is
  no engine-specific SQL: plain uniques with NULLs distinct, and
  `insertOrIgnore` for the two get-or-create rows.
- `PurchaseStatus` (the till's five values, with `isEditable`, `isOpen`,
  `isClosed` and `canCancel`) and the `PurchasingRefusal` exception, which
  renders `{message, code[, errors]}`: 409 for a state conflict, 422 for
  an invalid request.
- `App\Support\StockCosting`, a line-for-line port of the till's
  `stock_costing.dart`: `roundHalfUp` including the negative branch,
  `costAt`, `percentBp`, `receive`, `issue`, `costOfGoods` and `value`.
  Every product is checked, so an overflow throws instead of silently
  becoming a float.
- `PurchaseOrderService` (create, update, send, cancel, and `totals` with tax
  per rate), `PurchaseSequenceService` (`PO-YYYY-NNNNNN`, per business per
  year, consumed at send), `ReceivingService` (the till's five-part receipt as
  one transaction), `StockItemService` (the unit lock) and `StockLedger::replay`
  (folds the ledger through `StockCosting` and reports drift against the
  stored balances and the level).
- Controllers: `StockItemController` (index, show, store, update,
  movements), `PurchaseOrderController` (index, show, store, update, send,
  cancel, receive), `StockLevelController` and `PurchasingLookupController`.
  Requests: `Store/UpdateStockItemRequest`, `Store/UpdatePurchaseOrderRequest`
  and `ReceivePurchaseOrderRequest`. Resource: `PurchaseOrderResource`.
- Routes, inside the slice-a group `feature:purchasing` + `can:purchase.manage`,
  with `subscription.writable` on writes: `purchasing/lookups`;
  `stock-items` (GET, POST), `stock-items/{stockItem}` (GET, PUT) and
  `stock-items/{stockItem}/movements`; `stock-levels`; `purchase-orders`
  (GET, POST), `purchase-orders/{purchaseOrder}` (GET, PUT), and `…/send`,
  `…/cancel`, `…/receipts`.
- Audit: `purchase_order.created/updated/sent/cancelled/received`, written
  by the services (the PO model is not `Auditable`, so a transition isn't
  logged twice), and `stock_item.created/updated` via `Auditable`.
- Server strings in EN and AR: `xorder.purchasing.*` (the refusals and the
  status names), `xorder.validation.stock_item_*`/`po_*`, and
  `xorder.messages.branch_has_purchasing`.

**Built (web):** `lib/quantity.js` (the `Quantity.tryParse`/`format` mirror,
with `costAt`, `percentBp` and `orderTotals` on BigInt; no float anywhere);
`purchasing/PurchaseOrdersView.vue` (list with branch, status and supplier
filters, paginated); `purchasing/PurchaseOrderForm.vue` (create or edit a
draft, with a live integer preview of the totals); `purchasing/PurchaseOrderView.vue`
(detail, send, cancel, and the receive dialog, prefilled with what is still
owed); `inventory/StockItemsView.vue`; `inventory/StockView.vue` (headed
**Received to date** / **المستلم حتى الآن**, with the "sales are not
deducted" note); `inventory/StockMovementsView.vue`; and a shared
`purchasing/format.js`. The Purchasing group gains Purchase orders, and
Inventory gains Received to date and Stock items. Every string is in EN and
AR in `purchasing.*` and `nav.*`, in neutral wording. Codes, quantities,
amounts and references sit in `.mono dir="ltr"` spans.

**Tests:** `tests/Unit/StockCostingParityTest.php` (15) and
`tests/Feature/PurchasingOrdersAndStockTest.php` (27).

**Parity vectors**, all copied from the till's own tests, and all matching:
- `test/domain/stock_costing_test.dart`: 10 kg at 40.00 + 10 at 50.00 gives
  45.00; 30 + 10 at 60.00 gives 45.00; 7.5 kg at 44.00 + 12.5 at 47.30 gives
  20 kg at 46.06; nothing on hand takes 47.30; −2 kg on hand takes 47.30 and
  settles to 8 kg; receiving nothing is a no-op; a free delivery gives 20.00;
  the value property (±1); issue 3 kg keeps 45.00; issuing to −2 kg; COGS
  135.00; 0.333 × 33.33 = 11.10; value 591.25, 0, and −90.00.
- `test/core/quantity_test.dart` `costAt`: 94.60, 15.75 (0.333 kg at
  47.30), 23.68 (0.5 at 47.35), 0, 3 × 3.33, and 10.00.
- `test/domain/purchase_order_test.dart`: line 591.25; line tax 82.78; lines
  sum to 130.00; three lines of 33.33 at 14% give 14.00 tax, not 14.01; two
  rates give two roundings; an empty order is 0; received value 378.40.
- The till has no test for `roundHalfUp`'s negative branch, so those rows
  were derived from `rounding.dart` and are labelled that way.
- The 7.5 kg + 12.5 kg vector also runs through the whole HTTP stack,
  including as a part delivery (5 kg then 7.5 kg, giving 45.32 then 46.06).

**Departures from §4 to §7, with reasons:**
- **The unit lock rule.** §4.3 said the unit is fixed "once the item has a
  movement". Built, per the owner's brief: it is refused while any branch
  holds a **non-zero** quantity, **or** while the item is on a draft, sent or
  part-received order (whose lines were written in the old unit). A zero
  position has nothing to mix, and each movement records its own unit, so the
  history stays honest.
- **Receiving checks the line's unit against the item** (`LINE_UNIT_DIFFERS`)
  as well as the held unit (`STOCK_HELD_IN_ANOTHER_UNIT`). Neither can happen
  through the API, but both are refused rather than converted.
- **`purchase_orders.reference` is nullable** until send: a draft has no
  number, and NULLs are distinct in the unique index.
- **FKs to `branches`, `suppliers` and `stock_items` are NO ACTION, not
  RESTRICT.** Both block deleting a referenced row, but NO ACTION is checked
  at the end of the statement, so deleting a whole business still cascades
  cleanly. **`BranchController::destroy` now answers 409 with a reason**,
  not a 500, for a branch that has purchase orders or stock movements.
- **The supplier-name snapshot is refreshed at send**, and on a draft whose
  supplier changes. The issued document carries the name at the time of
  issue and never changes after that.
- **Sending to a retired supplier is refused** (`PO_SUPPLIER_RETIRED`), even
  for a draft started while the supplier was active. A draft may keep a
  retired supplier, item or unit it already carried; new orders may not pick
  them. Old orders display them, flagged.
- **`GET purchasing/lookups` is new.** It returns branch, supplier, unit,
  stock-item and menu-item ids and names under `purchase.manage` alone. A
  buyer's role need not include `branches.list` or `menu.view` (and so gain
  those screens) just to fill the pickers. Menu-item names are already public.
- **`GET stock-items/{id}` exists**, as in slice a. `stock_items` has
  `updated_by`, and `name_en` is nullable (either language, as in slice a).
- **There is no separate `StockService`.** `ReceivingService` writes the
  movement and the level in one transaction, and `StockLedger::replay` is
  the check. There is no artisan `stock:verify` yet.
- **Limits that keep the arithmetic in 64 bits:** ≤ 100 lines per order;
  quantity ≤ 10⁹ thousandths; unit cost ≤ 10¹⁰ minor; each line ≤ 10¹²
  minor. `occurred_at` may be backdated but not set ahead (a 10-minute
  allowance for clock drift). The ledger is folded and listed in id order,
  which is the order the fold happened in.
- **The PO editor is its own route** (`/purchasing/orders/new`,
  `/purchasing/orders/:id/edit`), not a modal. The nav leaf for levels
  reads "Received to date", like its heading.

**Deliberately not in slice b:**
- short-closing a part delivery (`close`, D11), which is still an owner
  decision: a short order stays `partially_received`, as on the till, and
  the page says closing short isn't available;
- supplier invoices, payments and balances (slice c);
- adjustments, openings, waste and counts (slice d, D12);
- transfers; sales deduction;
- `stock:verify`;
- a per-order receipt history view (the item ledger and the audit trail
  carry it);
- editing or voiding a receipt;
- printing a PO or sending it to the supplier (Send only changes the
  status);
- any till change or POS-BE-030.

**What slice c builds on:**
- `purchase_orders.id`, `reference`, `supplier_id`, `branch_id`, `currency`
  and `exponent`, for `supplier_invoices.purchase_order_id` (nullOnDelete)
  and its `purchase_order_reference` snapshot. `PurchaseOrderService::receivedValue`
  (`received_value_minor` on the resource) is the figure the till says an
  invoice should match. It is for display only: an invoice never reprices
  stock (§10 C4).
- `PurchasingRefusal` (a stable `code`, 409 or 422) for the ledger service's
  over-allocation and void rules, and the `purchasing.*` namespaces on both
  sides.
- `purchasing/lookups` can carry suppliers' `payment_term_days` for the
  due-date default.
- `BranchController::destroy` must also refuse a branch with invoices or
  payments.
- The Purchasing nav group gets the Invoices and Payments leaves, and
  `/purchasing/suppliers/:id` the account view.
