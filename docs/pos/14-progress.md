# Wave A progress — where the gap-closure plan stands

**As of 7 September 2026.** Companion to [11-gap-closure-plan.md](11-gap-closure-plan.md),
which is the plan; this is the state of it. When the two disagree, this file is
newer.

---

## 1. The short version

Wave A is **five of eight items done**. Everything that needed new schema is
built and applied: migrations 9 through 12 cover the order lifecycle, discounts,
order authorship and refunds. What is left in Wave A needs no migration at all.

| | Item | State |
|---|---|---|
| A.1 | Order lifecycle, void provenance, reason codes | ✅ migration 9 |
| A.2 | Discounts | ✅ migration 10 |
| A.3 | Void & cancel — line and order | ✅ |
| A.4 | Order history · `served_by` | ✅ migration 11 |
| A.5 | Refunds | ✅ migration 12 |
| A.2b | **Price override** | 🔨 **in progress** |
| A.7 | **Receipt reprint** | ⬜ not started |
| A.8 | Cart density modes · per-line note | ⬜ not started |

**Verification:** `flutter analyze` clean · **723 unit tests** pass, 13 skipped
(the database suites, which self-skip without `POS_PG_HOST`) · **117 database
tests** pass against PostgreSQL.

---

## 2. What is in progress right now

### Price override (A.2 in the design brief)

**No migration needed** — migration 9 already provisioned
`pos_order_line_events.unit_price_before_minor`, `unit_price_after_minor` and
the `price_overridden` event in its CHECK constraint. That foresight is now
paying for itself.

Done:

* `PriceOverride` on `TicketLine` — a snapshot carrying the replaced price as
  well as the replacing one, plus who, why and the approver. It overrides the
  **whole unit price**, modifiers folded in, so adding an extra to a repriced
  line cannot walk the price back up past what was agreed.
* `TicketLineEvent` gained `unitPriceBefore` / `unitPriceAfter`.

Still to do:

* `TicketEngine.overridePrice` / `removeOverride`, with refusals.
* **The limit loophole.** A price override is a discount by another name: a
  cashier with `price.override` and a 10 % discount ceiling could reprice a
  50.00 dish to 5.00 and bypass the ceiling entirely. The engine will measure
  the *reduction* against the same `DiscountLimit` the discount sheet uses, and
  escalate to a manager the same way. This is the one part of the feature that
  is a control rather than a convenience.
* Writing the `price_overridden` event at settlement.
* Parked-ticket codec round-trip, so a repriced line survives a restart.
* Inline cart affordance — mono entry, old price struck through.
* Tests: engine, codec, cart, and the database event.

---

## 3. What is left in Wave A after that

### Receipt reprint (A.7)

`receipt.reprint` exists as a capability, is overridable, and is held by every
seeded role including cashier. The audit action constant exists and **is never
written** — wiring it is part of this.

Needs: a reprint action on the order-history detail pane (the footer is already
the place for it), the `REPRINT` marking on the output, and an audit row. The
order lookup it depends on is built.

### Cart density modes and the per-line note (A.8)

From §9.1 of the patterns handoff. Comfortable and compact modes, plus the
per-line note affordance. Neither is blocked on anything.

### The capability expansion

The plan's A.6 lists roughly fifty granular keys (`order.transfer`,
`discount.above_limit`, `payment.partial_refund`…). There are **19**. Four have
been added as the features that needed them landed —
`order.item.delete_before_send`, `order.item.delete_after_send`,
`order.view_all` — and the rest are a Wave C concern in practice: the `text[]`
model takes them without a migration and `PosCapability.canonical` means nothing
gets renamed later. It is a real deviation from the plan's sequencing, recorded
here rather than quietly skipped.

---

## 4. Everything after Wave A

| Wave | Theme | Migration | Size |
|---|---|---|---|
| **B** | Cash drawer · pay in/out · business day | 13 | L |
| **C** | Permission model to specification | 14 | L |
| **D** | Settings & configuration screens | 15 | XL |
| **E** | Floors & tables | 16 | M |
| **F** | Kitchen, printing, hardware | 17 | L |
| **G** | Reports · X/Z · export/import | — | L |
| **H** | Customers | 18 | M |
| **I** | Auth & security hardening | 19 | M |
| **J** | Backup · restore · diagnostics | 20 | L |
| **K** | Local API tier | 21 | XXL |
| **L** | Inventory & recipes (P1) | 22 | XL |

Migration numbers have each shifted by one from the original plan: migration 11
became `who sold it` (order authorship), which the plan had not anticipated and
which history, refunds and sales-by-staff all needed.

**§113 P0 is complete at the end of Wave G** — everything the SRS calls
mandatory for v1, except §71's API tier, which is Wave K.

### Three things worth carrying forward

1. **Ship Wave D's settings *infrastructure* early, inside Wave B.** Scoped
   `pos_settings` plus the Settings shell. B, F and G all want it, and
   `RefundPolicy` is already written to read from it the day it exists.
2. **Wave B carries a trap.** Making payment methods data breaks the
   `wireLabel == 'Cash'` string match behind `ShiftSummary.cashTaken`. It must
   be replaced by a `counts_as_cash` column in the *same* change, or every
   Arabic till reports a false variance on every cash-up. The note is now on
   `TenderMethod.wireLabel`, where somebody changing it will read it.
3. **`BlindCountDialog` (pattern 7) is blocked** on the `cash.variance.view`
   naming decision — §4.2 of [13-pattern-handoff-review.md](13-pattern-handoff-review.md).
   It is Wave B work anyway.

---

## 5. Verification debt

**The `pos_till` password.** Every database suite so far has been run as
`amerelsayed`, the superuser. That verifies the SQL and none of the grants —
a superuser needs no grant at all, so a missing one is invisible.

Where this bites hardest is refunds. Migration 12's counters are maintained by
`SECURITY DEFINER` triggers, and the till is deliberately granted **no** UPDATE
on either of them. Whether that combination actually works under the till's own
privileges is exactly what a superuser run cannot tell us.

Partial cover exists: `test/data/till_grants_test.dart` asserts the grant list
itself, without a server — including that the counters are not grantable and
that refunds are INSERT-only. That is the shape of the grants, not proof they
suffice.

**Two known `postgres_wiring_test.dart` failures** when run with a database
present: one environmental, one pre-existing in uncommitted `providers.dart`
work.

---

## 6. Everything is uncommitted

76 changed or new files sit in the working tree against `077d3d3`. That includes
migrations 9–12, discounts, void, order history, refunds, and roughly 250 new
tests.

This is the single largest risk on the list. A `git stash` during earlier work
already resurrected a deleted file and broke `flutter analyze`; a tree this
large with no commits behind it has no floor under it.
