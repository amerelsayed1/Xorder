# 17 — Sales & payments: offline now, cloud next

The Sales & Payment Tracking SRS (cited here as **SALES-§n**, so its numbers do
not collide with the existing SRS the code already cites — its §21 is Refunds,
the code's §21 is Reprint) asks XOrder to track the lifecycle of money, not only
of orders. That principle is right. This document is how we get there without
rebuilding what exists, in the order that respects what blocks sale.

**Offline is built first and completely.** An offline install has no platform
to lean on: the desktop *is* its back office, so everything a manager needs has
to be here. **Cloud is planned, not built yet** — its cross-branch dashboard
belongs on the platform, which already receives the facts it needs.

---

## 0. The rules this plan keeps

1. **One ledger.** `pos_orders` is the sale. No second `sales` table (SALES-§33
   is declined — see §7). Every screen is a view over the same rows.
2. **Integer minor units.** Not decimal (SALES-§34 says decimal); minor units
   are stricter and are what every table and the platform contract (POS-BE-007)
   already use.
3. **Derived, never stored twice.** Payment status is computed from payment and
   refund rows, not written into a second column that can drift from them.
4. **Immutable money.** A payment is added, never edited; a refund is a new row
   that points at what it reverses. This is already how refunds work.
5. **Business day, not calendar day.** "Today" is the trading day. A restaurant
   open until 2 a.m. must not see its night split across two dates.
6. **ETA first.** Wave N is the ship blocker. Nothing here jumps ahead of it.

---

## 1. What already exists — reference it, do not rebuild it

| SALES-§ | Already in the code |
|---|---|
| §16 split payments | `pos_order_payments` — many rows per order, tender, amount, reference |
| §14 / §26 snapshots | `pos_order_lines.name_snapshot`, `unit_price_minor`, `modifier_summary` |
| §21–22 refunds | `pos_refunds`, `pos_refund_lines`, `pos_refund_payments`; reason, approver, `client_refund_id` |
| §28 cancel ≠ refund | `VOIDED` / `CANCELLED` distinct from `REFUNDED` / `PARTIALLY_REFUNDED` |
| §29 shifts | `pos_shifts`, `pos_cash_movements`, `pos_business_days`, Z report, blind count |
| §27 / §35 audit, reprint | `pos_audit_events`, `pos_print_jobs`, `receipt.reprint` |
| §36–38 offline, duplicates | `client_transaction_id` UUIDs, `pos_outbox`, `pos_invoice_sequences` |
| §4 configurable methods | `pos_tender_types`, including the `account` kind |
| §7 / §10 / §12 list, search, details | Order history: date range, status, order type filters, search, detail pane |

---

## 2. Where each half lives

| | Offline install | Cloud install |
|---|---|---|
| Branches | one | many |
| Terminals per branch | one, or several on a shared LAN database | one or several |
| Sales dashboard | **on the desktop** — the only back office it has | **the till's own branch on the desktop** (§3a); **across branches on the platform** |
| Branch summary + per-terminal breakdown | yes, when the branch has more than one terminal (§3a) | yes (§3a) |
| Reports | local PostgreSQL, full set | the branch on the desktop; cross-branch on the platform |
| Money owed / add payment | local rows, synced nowhere | local row + `POST /api/pos/orders/{id}/payments` (§006-P) |
| Another branch's figures | n/a — there is one branch | **platform only** — a till never sees another branch |

This keeps faith with [16-back-office-scope.md](16-back-office-scope.md), which
scores the desktop dashboard **Absent** because offline and cloud are not the
same product. The offline half reverses that for offline installs only, which
is the case that document left undecided.

**Owner decision, 2026-09-10:** a cloud till shows its **own branch** — every
terminal summed, and each terminal broken out with its own drill-down (§3a).
Not other branches. That is the rule the backend already applies to till reads
(`GET /shifts/{id}/report` resolves only to the requesting terminal's branch),
so the branch view is a till feature and cross-branch stays a dashboard one.

---

## 3. Offline — the waves

All five follow Wave N. **S1** and **S5** can start while the Wave N e-seal is in
review; **S3** is Wave G and absorbs its existing spec rather than replacing it.

### S0 — Prerequisites that live in Wave N · already planned

Not new work, but this plan depends on them and says so:

* The ETA UUID and QR on every bill, reproduced exactly on reprint —
  production-readiness **#5**.
* Refunds filed to ETA as return receipts — production-readiness **#4**.
* The submission client and e-seal — **#2**.

A sale that shows as refunded on the desktop and was never filed is a sale the
tax authority still counts. The Sales screens show the ETA state of each sale
(filed / queued / failed) from `pos_eta_receipts`; they do not re-file anything.

### S1 — Sales list and sale details · **M**

Extend the order history screen; do not build a second one.

* **Filters:** add cashier (`served_by`), payment method (tender type),
  terminal. Change the date filter's meaning to **business day**.
* **Payment status, derived:** a SQL view (and a matching domain function for
  the till) computing `UNPAID · PARTIALLY_PAID · PAID · PARTIALLY_REFUNDED ·
  REFUNDED` from payments and refunds. Shown as its own chip beside the order's
  lifecycle status — SALES-§8/§9's "two separate concepts".
* **Sale details:** the payments list (exists), refunds against this sale with
  their lines, and this sale's audit rows — printed, reprinted, voided, refunded.
* **Own sales only:** without `order.view_all`, the list shows `served_by = me`.

**Data caveat, stated in the screen's help:** `served_by` is trustworthy only
from the username sign-in fix (2026-09-10). Before it, shared PINs attributed
sales to the lowest staff id. Per-cashier history before that date is not
reliable and is not presented as if it were.

*Accepted when* every completed sale appears; each filter narrows correctly and
they combine; payment status matches the rows it is derived from (a test sums
them); a cashier without `order.view_all` sees no one else's sales.

### S2 — The payment ledger, completed · **S** · one migration

* `pos_order_payments.client_payment_id uuid` — unique per restaurant, nullable
  for existing rows, required for new ones. It mirrors the platform's
  `order_payments.client_transaction_id` (§006-P) so a payment added later can
  sync without ever being booked twice.
* `pos_refund_payments.original_payment_id` — the payment a refund reverses
  (SALES-§21). Needed to answer "back to the same card".
* **Payments record the amount applied, never tendered.** Change is a till
  concern, exactly as §006-P rejects overpayment. This is what makes SALES-§9's
  "Overpaid" status unnecessary rather than something every cash sale trips.
* **Payments screen:** one row per payment, the accountant's view — a sale with
  three tenders is one row in Sales and three here (SALES-§19). Drills to its sale.

*Accepted when* a sale's payments sum to its total less refunds (domain +
test); a refund names the payment it reverses; the migration is additive and
leaves every existing row readable.

### S3 — Reports and the dashboard · **L** · this IS Wave G

Wave G in [11-gap-closure-plan.md §9](11-gap-closure-plan.md) already specifies
the read models, the shared `ReportFilter`, CSV/XLSX/PDF export and the
permission gate. SALES-§3–6, §30–32 are folded into it, adding:

* **KPI cards for the business day:** gross, discounts, net, refunds, final
  revenue, orders, average order value, collected by tender.
* **Drill-down (SALES-§32):** every card opens S1's list or S2's payments,
  pre-filtered to what the card counted.
* **Charts:** by hour of the business day, by tender, by category, by cashier,
  by terminal. **No branch chart offline** — there is one branch.
* **The branch view (§3a):** the branch total and every terminal broken out,
  with drill-down. On any install whose terminals share one database — offline
  or cloud — this is a local query and needs nothing else.
* **Export gated** on a new `report.export` capability — it carries the
  business out of the building.

*Accepted when* every KPI equals the sum of the rows its drill-down shows —
**enforced by tests**, not by inspection (SALES-§45 #5 and #14).

### S4 — Money owed · **M** · after Wave H (customers)

SALES-§20 puts outstanding balances in the MVP and accounts receivable in
Phase 2. They are the same thing: a balance nobody is recorded as owing cannot
be collected. So this waits for customers.

* Close a sale with a balance on the `account` tender → lifecycle `CLOSED`,
  payment status `PARTIALLY_PAID` or `UNPAID`, **customer required**.
* **Add payment** on sale details → a new `pos_order_payments` row with its own
  `client_payment_id`. Earlier payments are never touched.
* **Outstanding report:** invoice, customer, total, paid, remaining, age.
* New capability `payment.settle_later`.

### S5 — The bill as a document · **S** · can ride with S1

* Export the existing receipt document to PDF.
* A reprint is marked **DUPLICATE** and logged — `pos_print_jobs` and the audit
  trail already record it; this only puts the word on the paper.

---

## 3a. The branch view — every terminal, summed and broken out

Asked for by the owner for the cloud till; the same screen serves any offline
install with more than one terminal.

**Branch summary** — for the selected business day (or range), over every
terminal whose `branch_id` is this branch:

* gross sales · orders · discounts · refunds · net sales
* payments collected, by method

**Per-terminal breakdown** — one row per terminal of the branch:

* gross sales · orders · cash · card / electronic · discounts · refunds · net sales

```text
Branch: Mansoura · business day 10 Sep
  POS-01   EGP 5,000
  POS-02   EGP 3,000
  POS-03   EGP 2,000
  ─────────────────
  Branch   EGP 10,000
```

Clicking a terminal opens S1's sales list filtered to that terminal and the
same period; clicking the branch total opens it unfiltered by terminal;
clicking a payment method opens S2's payments filtered to it.

### Rules that make the numbers agree

1. **The branch total is the sum of the terminal rows — one query, not two.**
   Computed as a `GROUP BY terminal` with the total taken from those rows, so the
   two can never disagree by construction. Tested anyway.
2. **Every terminal of the branch is listed, including one with no sales.** A
   till that stopped syncing, or never opened, shows as zeros rather than
   disappearing — a missing row is the one thing a manager cannot notice.
3. **Cash** is `counts_as_cash`. **Card / electronic** is the `card` and `wallet`
   tender kinds. **On account is neither** — it is money owed, not collected, and
   is shown as its own figure so it is never counted as takings.
4. **A refund belongs to the terminal that issued it**, in the business day it
   was issued — not to the terminal of the original sale. It is that terminal's
   drawer the money left. The branch total is the same either way; the
   per-terminal rows reconcile against the drawers they describe.
5. **Net sales** = gross − discounts − refunds, per row and for the branch.

### Where the numbers come from — two shapes

| Branch shape | Source | Offline |
|---|---|---|
| **Shared LAN database** — `max_terminals > 1`, the branch-hub topology [08-postgres-lan.md](08-postgres-lan.md) recommends | one local query over the `pos_orders`, `pos_order_payments` and `pos_refunds` every terminal already writes | **fully works** — the hub is on the LAN |
| **Each till its own database** — cloud, `localhost` per till | the platform, via **POS-BE-029** (§6, C4), as one consistent snapshot | this terminal stays live from local rows; other terminals show **as of the last fetch, with its time** — never silently stale; drilling into another terminal needs the connection |

In the per-till shape, this till's own sales that have not yet synced are
**counted in a banner** ("3 sales on this till are not in these totals yet")
rather than mixed into the platform's figures — mixing local and platform rows
would double-count them the moment they sync, and rule 1 would stop holding.

### Permissions

The branch view needs `reports.view`. Drilling into a terminal applies S1's rule:
without `order.view_all`, only the user's own sales are listed.

### Accepted when

* the branch total equals the sum of its terminal rows, to the piastre;
* each terminal row equals the sum of the sales its drill-down lists;
* cash + card / electronic + on account reconciles to the payments in S2;
* every terminal of the branch appears, zeros included;
* offline, the shared-database shape shows the full branch, and the per-till
  shape labels anything it could not refresh.

---

## 4. The status column — changed carefully

`pos_orders.status` mixes the order's stage (`OPEN`, `SENT_TO_KITCHEN`,
`READY`) with money (`PAID`, `REFUNDED`). SALES-§8 is right that these are two
questions. The column is not split in one step: ETA, history and the existing
refund flow all read it.

1. **S1** adds the derived payment status beside it. The UI shows both.
2. **S3** moves every report to the derived value.
3. **Later, one migration:** once nothing reads the money states from `status`,
   stop writing them there. Tracked here so it is a decision, not a leftover.

---

## 5. Permissions — mapped onto the catalogue that exists

The catalogue stays in Dart. New keys only where nothing fits.

| SALES-§23 asks for | Use |
|---|---|
| `sales.view`, `sales.view_all` | `order.view_all` (without it: own sales only) |
| `sales.view_own` | the default for anyone who may operate the till |
| `refund.create` / `refund.partial` / `refund.full` | `order.refund`, limited by `refund.max` |
| `sales.reprint_bill` | `receipt.reprint` |
| `sales.cancel` | `order.void` |
| `payments.view`, dashboard | `reports.view` |
| `sales.export` | **new** `report.export` |
| add a payment later | **new** `payment.settle_later` |

---

## 6. Cloud — the future plan

**The principle: the till never becomes the cloud dashboard.** A cloud tenant's
cross-branch view belongs on the platform, which already has the tables and a
dashboard projection (`orders.total`, maintained "for the dashboard" per §006-P).
The till's job is to deliver the facts intact and keep working offline.

### C1 — Every money fact reaches the platform · verify, mostly built

Orders (POS-BE-006, READY), refunds (POS-BE-010), shifts (§009) and bulk drain
(POS-BE-021, APPROVED) already carry `client_transaction_id` under POS-BE-007's
idempotency rules: five submissions, one record. **Work:** confirm every row S2
adds — payments added later, the refund→payment link — goes through the outbox,
and add them where it does not.

#### C1 findings — 2026-09-10

Read from the code, not the plan. **One money fact syncs: the settled sale,
with its payments.** It is claimed for the outbox in the same transaction that
writes it (`postgres_orders_repository.dart:168`, `:315`), and drained oldest
first to `POST /api/pos/orders` with the order's `client_transaction_id` as the
idempotency key (`outbox_drain.dart:164`, `cloud_api.dart:172`). Each payment
travels inline with a stable uuid-v5 key (`outbox_drain.dart:77`, `:295`), so
POS-BE-007's five-submissions-one-record holds. Serial POST, not the
POS-BE-021 bulk drain — which the contract permits.

**What does not reach the platform:**

| Money fact | Evidence | Effect |
|---|---|---|
| **Discounts** | `asserted_totals.discount_minor` is hard-coded `0` (`outbox_drain.dart:135`); neither `order_discount` nor a line `discount` is sent (`:106`–`:143`), though `pos_order_discounts` holds them | the server re-prices without them, so every discounted sale lands at the undiscounted price, flagged `totals_mismatch` (`:233`) rather than refused — the platform overstates revenue by every discount |
| **On account, as owed** | every `pos_order_payments` row is sent as a payment, whatever its kind (`outbox_drain.dart:295`–`:318`) | a sale put on account arrives fully paid; §006 already allows payments to sum to less than the total, and that is what an on-account balance should look like |
| **Refunds** | written to `pos_refunds` / `pos_refund_payments` with no outbox claim (`postgres_refunds_repository.dart:90`, `:172`); `PosCloudApi` has no refund call — `submitOrder` is its only money endpoint (`cloud_api.dart:172`) | POS-BE-010 is unbuilt client-side; money that left a drawer is invisible to the platform |
| **Shifts and cash-up** | `pos_shifts` written locally only (`postgres_shift_repository.dart:68`, `:114`); every order goes up with `shift_client_id: null` (`outbox_drain.dart:128`) | float, counted cash and variance never leave the building; §009 is unbuilt client-side |
| **Cash movements** | `pos_cash_movements` written locally only (`postgres_cash_movements_repository.dart:22`) | pay-ins and pay-outs are not on the platform |
| **Supplier payments from the till** | `postgres_supplier_invoices_repository.dart:773` | not in any POS-BE contract today; noted, not a contract gap |
| **Anything after delivery** | the outbox is one row per order (`migrations.dart:366`) and the drain reads only undelivered rows (`outbox_drain.dart:175`) | a later change to a delivered sale is never re-sent. S2's rows — a payment added later, the refund→payment link — cannot ride this queue as it is; they need their own entries (POS-BE-021 already has `payments[]` and `refunds[]`) |

Voids are deliberately not queued (`postgres_orders_repository.dart:295`): no
money moved, and no void shape is agreed. Recorded as a known absence, not a
gap. **None of the above was fixed this round** — C1 was scoped to find them.

### C2 — The POS half of settle-later · **S** · after S4

S4's "add payment" enqueues `POST /api/pos/orders/{id}/payments` with the
payment's `client_payment_id`, the acting user and the shift. The platform
recomputes `settlement_status`; the till does not overwrite its own rows with
the answer (SALES-§37 — never replace local financial records with server ones).

### C3 — The platform's sales dashboard · **L** · backend and web repos, not this one

Cross-branch KPIs, the branch dimension, accounts receivable and aging, built on
`order_payments` and refunds. Specified in the platform's own plan; this repo's
only obligation is C1.

### C4 — The branch view on a cloud till · **M**

The owner's decision: a cloud till shows its **whole branch** — every terminal
summed, each broken out, each drillable — exactly as §3a.

* **Shared LAN database:** nothing beyond S3. The query is local and works
  offline.
* **Each till its own database:** needs **POS-BE-029**. The branch view comes
  from the platform as one snapshot; this till's unsynced sales go in a banner,
  not into the totals.
* **Offline, either shape:** this terminal, this shift and this business day
  keep working from local rows. The drawer can still be counted and the Z
  printed.

**POS-BE-029** — filed 2026-09-10 in [POS_TO_BACKEND.md](../coordination/POS_TO_BACKEND.md), with the full wire shape:

* `GET /api/pos/branch/sales/summary?business_day=YYYY-MM-DD` → the branch
  totals, payments by method, and one row per terminal of the branch (zeros
  included).
* `GET /api/pos/branch/sales?terminal_id=…&business_day=…` → that terminal's
  sales, for drill-down.
* Device token + `reports.view`. Resolves **only to the requesting terminal's
  branch** — 404 otherwise — the rule `GET /shifts/{id}/report` already
  follows, so it stays a branch read and never becomes a cross-branch
  dashboard.

**Built 2026-09-10 — data layer and contract, no screen yet.** The model
(`lib/domain/models/branch_sales.dart`, `branch_sales_source.dart`), the
shared-database query (`lib/data/postgres/postgres_branch_sales_repository.dart`),
the POS-BE-029 client (`lib/data/cloud/branch_sales_api.dart`) and the
providers that pick between them (`lib/app/branch_sales_providers.dart`).

**Found while building — `business_day_id` is never stamped.** The column
exists on `pos_orders` and `pos_refunds` with its foreign key, but neither
INSERT names it (`postgres_orders_repository.dart:97`,
`postgres_refunds_repository.dart:90`). The branch query falls back to the
business day's own open-to-close window, which gives the same answer and yields
to the stamped id as soon as one is written. The day close has no such
fallback: its totals (`postgres_business_day_repository.dart:176`) are summed
by `business_day_id` alone, so they record zero. Not fixed here.

### C5 — Sync health

A per-business-day comparison of counts and sums between the till and the
platform, keyed by client ids, with the mismatches listed. SALES-§45 #13 —
"synchronisation does not duplicate" — is a claim; this is how it is checked.

### Decided — 2026-09-10

* A cloud till shows **both** the branch summary and the per-terminal
  breakdown (§3a), with drill-down into any terminal's sales.
* It shows **its own branch only**. Other branches stay on the platform — the
  backend's existing rule for till reads, and C3's job.

---

## 7. Declined, and why

| SALES-§ | Declined | Because |
|---|---|---|
| §33–34 | a separate `sales` table | `pos_orders` is the sale. Splitting buys only split bills, which nobody asked for, at the cost of migrating every reader. |
| §34 | decimal money columns | integer minor units are stricter and already universal |
| §9, §17 | `failed` / `pending` payments | nothing produces them until a card terminal is integrated |
| §9 | `Overpaid` | payments record the amount applied; change is not a payment |
| §44 | GL, COGS, credit limits | platform scope, and Phase 2 by the SRS's own account |

---

## 8. Order and size

| Wave | What | Size | Depends on |
|---|---|---|---|
| **N** | ETA e-receipt (existing plan) | L | — |
| **S1** | sales list, derived payment status, details | M | — |
| **S5** | bill PDF, DUPLICATE marking | S | — |
| **S2** | payment ledger migration, payments screen | S | S1 |
| **S3 = G** | reports, dashboard, branch view (§3a), drill-down, export | L | S1, S2 |
| **H** | customers (existing plan) | M | — |
| **S4** | money owed, add payment, outstanding | M | H, S2 |
| **C1** | verify every money fact syncs | S | S2 |
| **C2** | settle-later to the platform | S | S4 |
| **C4** | branch view on a cloud till; POS-BE-029 for per-till branches | M | S3 · backend for the per-till shape |
| **C5** | sync health | M | C1 |
| **C3** | platform dashboard | L | C1 — other repos |

S1 and S5 can overlap Wave N's review. Nothing in the cloud column blocks the
offline product, and nothing in the offline column waits on the platform.
