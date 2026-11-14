# 16 — What the back office is, and what it is not

**Written 8 September 2026, in answer to a direct question:** does the back
office work offline and on cloud, and does it cover the fifteen areas an
offline-first business would expect?

The short answer is that **XOrder POS today is a till with configuration
screens, not a back office** — and that the gap-closure plan's ordering was
built for a different goal than the one that question implies.

---

## 1. Offline and cloud are not the same product here

Three Management panes — **Menu, Floor, Money** — are hidden on a cloud till,
deliberately. `BootstrapSeeder` DELETEs `pos_products`, `pos_modifier_groups`
and `pos_categories` and re-inserts the platform's rows, so anything authored
locally is destroyed by the next bundle. Hiding them is right.

**The Staff pane was not gated the same way, and that was a bug** — fixed in
`d4cc878`. The seeder also upserts `pos_users` and deactivates anybody the
bundle does not name, so a cashier added in the back office of a cloud till was
switched off by the next sync, silently, mid-shift.

The fix is worth reading for what it revealed rather than for its size. The
seeder's ownership is **narrower than the pane boundary**:

| Row | Cloud | Offline |
|---|---|---|
| `pos_users` name, username, PIN, capabilities, active | platform | local |
| `pos_users.role_id` | **local** | local |
| `pos_roles` | **local** | local |
| `pos_user_roles`, overrides, ceilings (Wave C) | **local** | local |
| `pos_categories`, `pos_products`, modifiers | platform | local |
| `pos_dining_tables` | platform | local |
| `pos_receipt_profiles` | local | local |
| `pos_tender_types`, `pos_service_charges` | local | local |

So the honest statement is not "the back office is offline-only". It is:
**who works here comes from the platform; what they may do, what the receipt
says, and how money is taken are the till's** — even on cloud.

**One consequence is currently wrong.** Payment methods (§40) and service
charges (§38) are local on both deployments, but they were put in the **Money**
pane, which is cloud-hidden. A cloud restaurant therefore cannot configure how
it takes money. That is a placement mistake, not a design one, and it is fixed
by moving them out of Money when Wave D's settings navigation lands.

---

## 2. The fifteen areas, scored honestly

| Area | State |
|---|---|
| Users & permissions | **Done.** Roles, multiple roles, per-person overrides, numeric ceilings, risk levels, no-escalation rule (Wave C) |
| Products & menu | **Done bar one thing.** Categories, products, modifiers, prices, per-branch prices, combos, tax groups, barcodes, active/inactive, CSV/Excel import. **No cost price** |
| Sales management | **Done.** History with search and filters, order detail, voids, refunds, reprint |
| Audit log | **Done.** Append-only ledger, Activity pane |
| Cash & shifts | **Nearly.** Open/close, float, cash in/out, blind close, variance, business day, Z report. **No shift history browser** — the current shift only |
| Settings | **Partial.** Business info, receipt setup, taxes, payment methods, service charges ✓. Numbering not configurable; printers partial; no currency picker; no backup settings |
| Expenses | **Barely.** A cash pay-out with a reason code records money leaving the drawer. No categories, no supplier link, no reporting |
| Terminals | **Partial.** Table and registration exist; no pane to see or configure them |
| Dashboard | **Absent** |
| Inventory | **Absent** — Wave L |
| Reports | **Absent** beyond X/Z — Wave G |
| Customers | **Absent** — Wave H |
| Purchases | **Absent — on no wave at all** |
| Suppliers | **Absent — on no wave at all** |
| Accounting lite | **Absent — on no wave at all** |

Five substantially done, three partial, seven absent.

> **Updated 14 September 2026.** Since this table was written, Purchases and
> Suppliers (orders, receiving, supplier invoices and payments — §6) and
> Inventory (stock items, levels, movements, units) are built, and Backup has a
> pane with a directory and back-up-at-day-close settings (`pos_backups`,
> `backup.on_day_close`). Still absent: Dashboard, Reports beyond X/Z,
> Customers, Accounting lite.

> **Updated 4 October 2026.** This table was not re-scored row by row; what
> follows is only what was checked against the code, and it corrects three
> lines above.
>
> * **Combos were sellable but not authorable.** The "Products & menu" row
>   counts combos as done; until this date the till could ring one up
>   (`ComboSheet`, migration 18) and nothing in the app could create one.
>   Management › Menu › **Combos** now lists, creates and edits them: groups,
>   items with optional upgrade prices, min/max choices, category, SKU. Offline
>   only, `catalog.manage`, audited as `combo.saved`. Retired with a switch,
>   never deleted — an order line names its combo.
> * **The chain in §3 is closed at the report.** Purchases → receiving (moving
>   average) → every sale of a stocked item records that cost on its stock
>   movement → **Reports › Items › Profit**, with the same figures as a second
>   sheet of the Items Excel export. "No cost price" in the Products row is
>   still true of the *product*: cost lives on the stock ledger, not on a
>   column of `pos_products`.
> * **Dashboard and Reports are no longer "absent".** Home shows the open
>   day's net sales, orders and average against the day before; Reports has the
>   business summary and the Sales, Items, Payments, Branches and Employees
>   breakdowns. (Depth beyond that was not re-checked.)
>
> **What the profit figures do not claim** — the page and the file say it too:
>
> * Only a **stocked** item is costed. There is no recipe model, so dishes and
>   combos show revenue and no cost; the report prints how much of the revenue
>   it covers (`coverageBp`) and the margin is on the costed part alone.
> * A sale at a carrying cost of **zero** is *not costed*, not free: zero is how
>   "never received" looks on the ledger. The Stock pane draws it as a dash and
>   a "no cost" tag for the same reason.
> * A **refund returns the revenue and not the cost** — no stock movement is
>   written for one — so a plate refunded before it was made reads as a loss.
> * On a **tax-inclusive** restaurant the lines do not store their tax, so it
>   is taken out of the revenue **order by order**: each line is scaled by its
>   order's recorded net-to-gross ratio (`pos_order_taxes`). Exact for an order
>   at one rate; an **estimate** for an order that mixes rates (a zero-rated
>   item beside a 14% one is shared out at the order's blend); an order with no
>   tax rows is left whole. The page and the file say so, and head the column
>   "Amount, no tax" so it is not read against the Items list, which is gross.
>   The mode read is the restaurant's *current* one — orders do not record the
>   mode they were taxed in.
> * Revenue is the lines' own, before order-level discounts, as the Items list
>   has it.
>
> * **An item can be given its first cost by hand.** Stock pane › Set cost, for
>   an item that has stock and no cost: an `opening` movement of quantity zero,
>   audited, `purchase.manage`. Not a revaluation — it refuses an item that
>   already has a cost.
>
> * **Customers has a pane.** People › Customers lists everyone on file with
>   orders, what they kept (net of refunds) and when they last bought, searchable
>   by name or phone; a row opens their contact details, average order and recent
>   orders. Read-only — customers are added at the counter, and the phone is their
>   identity — and **this branch's sales only**, settled ones. Gated on
>   `reports.view`, because it sets a name and a phone beside what somebody spends.
>
> * **The customer is on the sale.** The sales list has a Customer column (not on
>   Cancelled orders), its search matches a customer's name and — from seven
>   digits — their phone, the order detail shows name, phone and email when the
>   sale had one, and the sales Excel export gains Customer and Phone columns
>   after the page's own, so Total does not move.
>
> * **Accounting lite is half built: the profit and loss.** Finance › Profit &
>   loss is one column — sales after discounts and refunds, less the tax collected
>   for the state, is revenue; less cost of goods is gross profit; less what was
>   paid out of the drawers is the operating result. Every line is a figure
>   Reports or Finance already draws, composed rather than recomputed, so it
>   cannot disagree with them. **Receivables are not built**: a sale cannot go on
>   a customer's account (the till says so), so there is nothing to age or collect.
>
> **What the statement says it leaves out**, in the page, under it:
>
> * **Items with no cost** — their cost of goods is missing, so the gross profit
>   (and the result) is a *ceiling*, labelled "before items with no cost" and
>   shown with the share of sales that has a cost, until every sale is costed.
> * **Purchases are stock, not expense.** Paying a supplier is not deducted: the
>   goods are in the cost of goods when sold, and deducting the payment too would
>   count the same food twice. A supplier invoice is one total with no lines, so
>   packaging and gas — a real expense — cannot be told from stock and are not
>   deducted either. What was paid to suppliers is shown beside the statement, not
>   in it.
> * **Rent and salaries** — no expense entity to hold them.
> * **Service charge** is in sales, which are the orders' totals.
>
> Still absent from the code as checked: receivables, and expense categories.
> Expenses, Terminals and the rest were not re-scored here.

---

## 3. Why the absences are one absence

The seven missing areas are not seven independent features. They are one chain,
and each link is worthless without the one before it:

```
purchases → supplier invoices → cost price → inventory valuation
                                     ↓
                                   COGS → profit reports → accounting lite
```

* **Cost price** on a product is a number somebody types and nobody trusts,
  until purchasing writes it.
* **Profit reports** cannot exist without cost price, so "Reports" as a wave
  delivers sales reports and stops.
* **Accounting lite** — revenue, COGS, payables, receivables — needs purchases
  for payables and customers for receivables.

This is why "add reports next" is the wrong instinct. It produces the reports a
till can already almost do, and none of the ones a business actually asks for.

---

## 4. What this means for the plan

`11-gap-closure-plan.md` sequences Reports at **G**, Customers at **H**, Backup
at **J**, Inventory at **L**, and has nothing for purchases, suppliers, expenses
or accounting.

**That ordering was right for the goal it was written for** — "a till that can
trade legally in Egypt" — and Waves A, B, M, N and C delivered exactly that. It
is the wrong ordering for "an offline back office", which is a different
product with a different centre of gravity.

Proposed resequencing, if the back office is the product:

| | Wave | Why here |
|---|---|---|
| 1 | **D — finish** (order types, taxes as data, settings navigation) | In flight; and the navigation is where payment methods and service charges stop being cloud-hidden |
| 2 | **P — purchases, suppliers, cost price** | **Started.** The head of the chain. Nothing downstream is honest without it |
| 3 | **L — inventory** (was last) | Stock levels, movements, adjustments, waste, counts, valuation |
| 4 | **G — reports** | Now able to report profit rather than only takings |
| 5 | **Q — expenses & accounting lite** | Payables from purchases, receivables from customers |
| 6 | **H — customers** | Needed for receivables; also the smaller half of §58 |
| 7 | **J — backup & restore** | Rises with the amount of data that is now local-only and irreplaceable |
| 8 | E, F, I, K | Floors, kitchen, auth hardening, local API — unchanged, after |

**Backup deserves a note.** It is currently at J on the strength of being
housekeeping. Every wave above makes the branch server hold more data that
exists nowhere else — a restaurant's entire purchase and stock history. The
later the back office grows, the earlier backup should move.

---

## 5. What is not decided

Two questions are commercial rather than technical, and they change the answers
above:

1. **Is cloud a deployment you sell, or a direction of travel?** If it is real,
   the back office needs a story better than "hidden on cloud" — a cloud
   restaurant currently cannot configure its payment methods, and will
   eventually want to see its own purchase history.
2. **Is inventory a v1 requirement or a v2 one?** It is the largest single
   piece of work on this page (XL, and the chain behind it is another XL), and
   it is the difference between selling a till and selling a business system.

---

## 6. Purchasing, as it is being built

**Migration 27 — suppliers.** The first row of the chain, and first because
everything else references it.

Two decisions worth recording now, because both will look like omissions later:

* **No balance column on `pos_suppliers`.** What a supplier is owed is invoices
  minus payments. A stored total drifts the first time somebody voids an
  invoice inside a transaction that fails halfway, and then two screens
  disagree with no way to tell which is right. It is derived where it is shown
  — one join, and a number that cannot be wrong. Same reasoning as
  `pos_orders.refunded_minor` living under a trigger rather than under the
  till's hand.
* **Suppliers are not granted to the till at all.** Every other table in this
  product gives the counter credential at least SELECT. A till does not buy
  anything, and handing it who the restaurant owes money to would give away the
  restaurant's commercial position for no operational benefit.

`purchase.manage` is **one capability, not five.** The SRS splits purchasing
several ways; splitting it before there is a screen for each would put keys in
the catalogue that nothing checks — which is exactly what Wave C deferred
§50's sixteen settings keys to avoid.

**Migration 28 — purchase orders and their lines**, with `PurchaseEngine` as
the pure half: what may be edited when, and what a part delivery means.

The decision with the longest reach is **`core/money/quantity.dart`**. Sales
quantities are integers — a cashier sells two grills — and purchases are not: a
restaurant buys 12.5 kg of chicken and 0.75 litres of oil. A `numeric` column
would be honest and every read would arrive as a Dart `double`, sitting directly
upstream of every cost price, stock valuation and margin the reports will
eventually show. So a quantity is an **integer of thousandths**, exactly as
`Money` is an integer of minor units, with one rounding point (`costAt`) and no
unit conversion at all — a system that silently turned 500 g into 0.5 kg would
eventually turn 500 boxes into half a something.

Two smaller ones, recorded because they will look like omissions:

* **Five statuses, not two.** A restaurant almost never receives exactly what it
  ordered, and a model that knew only *ordered* and *received* would have to lie
  about the Tuesday when eight of ten crates turned up.
* **Cancelling is refused once goods have arrived.** Goods in the kitchen are
  not cancellable, and pretending the order never happened would leave stock
  with no record of where it came from. Until migration 44 this was held only
  by hiding the Cancel button, which a receipt booked from another till could
  get round; now `setStatus` re-reads the order under a lock and asks
  `PurchaseEngine`, and a trigger refuses the same moves for any other writer.

**Built since:** receiving (migration 29), with its four writes — line, ledger,
position, status — in one transaction, and **moving average** as the valuation
method (owner, 9 September 2026; the reasoning is in `stock_costing.dart`).
Then supplier invoices and payments (migrations 30, 31 and 33). Receiving
refuses stock held in a different unit rather than converting it, and an item
cannot change its unit while any branch holds stock of it (migration 44).

**Not built: short-closing a part delivery.** `PurchaseStatus.received` is
documented as "all of it arrived, or somebody closed the difference", but
nothing closes a difference. Receiving writes `received` only when every line
is full, and the pane offers only Send and Cancel. So a short-delivered order
stays `partially_received` until the rest arrives. Cancelling it is refused, so
if the rest never comes, the order stays open for good. The platform design
tracks this as CB-09 D11.

---

Related: [15-competitive-position.md](15-competitive-position.md) rates the same
product against the market; this page rates it against a specification.
