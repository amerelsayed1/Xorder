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
`d4cc878`. The seeder also upserts `pos_staff` and deactivates anybody the
bundle does not name, so a cashier added in the back office of a cloud till was
switched off by the next sync, silently, mid-shift.

The fix is worth reading for what it revealed rather than for its size. The
seeder's ownership is **narrower than the pane boundary**:

| Row | Cloud | Offline |
|---|---|---|
| `pos_staff` name, username, PIN, capabilities, active | platform | local |
| `pos_staff.role_id` | **local** | local |
| `pos_roles` | **local** | local |
| `pos_staff_roles`, overrides, ceilings (Wave C) | **local** | local |
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
| 2 | **P — purchases, suppliers, cost price** | The head of the chain. Nothing downstream is honest without it |
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

Related: [15-competitive-position.md](15-competitive-position.md) rates the same
product against the market; this page rates it against a specification.
