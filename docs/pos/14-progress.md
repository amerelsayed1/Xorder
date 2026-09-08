# Progress — where the gap-closure plan stands

**As of 8 September 2026.** Companion to [11-gap-closure-plan.md](11-gap-closure-plan.md),
which is the plan; this is the state of it. When the two disagree, this file is
newer.

---

## 1. The short version

**Wave A is complete. Wave B is built.** Migrations 9 through 15 are applied.

| Wave | State |
|---|---|
| **A** — discount, void, refund, history, price override, reprint, cart density | ✅ |
| **B** — settings, cash movements, business day, blind close | ✅ |

**Verification:** `flutter analyze` clean · **861 unit tests** pass, 15 skipped
(the database suites, which self-skip without `POS_PG_HOST`) · **354 database
tests** pass.

---

## 2. What Wave B added

**Migrations 14 and 15.** `pos_settings`, `pos_cash_drawers`,
`pos_cash_movements`, `pos_business_days`, the late foreign keys, and the owner
role's new capabilities. Settings landed here rather than in Wave D on the
plan's own advice.

**Settings, shaped against the plan's fourth risk.** The map is not the public
surface: `PosSettings` parses, and `RefundPolicy`, `DayPolicy` and `CashPolicy`
are what everything else reads. Every key falls back on its own, because partial
configuration is the normal case.

**The trading day.** `DayPolicy.dateFor` is where it stops being the calendar
day — a restaurant closing at 2 a.m. takes money on Saturday that belongs to
Friday. Opening is idempotent; a closed day is never reopened silently; closing
totals inside the same transaction as the close.

**The drawer.** Pay in and pay out are two variants of one dialog that must
never be confusable — they differ in colour, title, button wording and the sign
beside the amount, because a cashier who reaches for the wrong one records the
drawer 100 up when it is 100 down. Opening the drawer without a sale (§23) has
its own capability, its own confirmation and its own audit row; it used to be a
toast that opened nothing.

**§27's cash-up.** The Z report now carries the fifteen totals — subtotal,
discounts, service, VAT, gross, refunds, voids, net, each tender, float, cash
in, cash out, drawer openings, expected, counted, difference. Refunds are *not*
netted off the gross: a shift that sold 1,000 and refunded 200 did both things,
and showing only 800 hides the number a manager is looking for.

**Blind close (§25)** needs two conditions, not one: the restaurant asked for
it **and** this person lacks `shift.view_expected_cash`. A manager counting
their own drawer under a blind policy still sees the figure, because
withholding it from the person who set the policy protects nobody. The variance
is revealed after committing to anyone holding `cash.variance.view` — which is
why those are two capabilities rather than one.

**The plan's third named risk is closed.** `ShiftSummary.cashTaken` selected the
drawer's cash with `label.contains('cash')`; it now selects on tender type.

---

## 3. What is left, in order

**The order changed on 8 September 2026.** A competitor comparison found that
Egypt's ETA e-receipt mandate has been in force since 15 September 2025, and a
restaurant on the ETA list cannot legally run its tills on this build. Wave C
makes the product better; ETA makes it sellable. See
[15-competitive-position.md](15-competitive-position.md).

| Wave | Theme | Migration | Size |
|---|---|---|---|
| **M** | **Menu & tax model** — `tax_lines[]`, per-product tax, combos, per-branch pricing | 16 | L |
| **N** | **ETA e-receipt** — e-seal signing, submission queue, QR on the slip | 17 | L |
| **C** | Permission model to specification | 18 | L |
| **D** | Settings & configuration screens | 19 | XL |
| **E** | Floors & tables | 20 | M |
| **F** | Kitchen, printing, hardware | 21 | L |
| **G** | Reports · X/Z · export/import | — | L |
| **H** | Customers | 22 | M |
| **I** | Auth & security hardening | 23 | M |
| **J** | Backup · restore · diagnostics | 24 | L |
| **K** | Local API tier | 25 | XXL |
| **L** | Inventory & recipes (P1) | 26 | XL |

**M before N** because `tax_lines[]` cannot be retrofitted onto orders already
filed with the tax authority, and per-product tax treatment is what makes it
expressible. The two are one design, not two.

**Not on the roadmap at all:** payment terminals, delivery aggregators, product
images. Each is table stakes in this market and each is a commercial decision
before it is code.

### Three things Wave B settled

1. **Wave D's settings infrastructure shipped early, inside Wave B**, as the
   plan advised. `RefundPolicy`, `DayPolicy` and `CashPolicy` all read it.
   Wave D now builds screens over an existing store rather than both at once.
2. **The `wireLabel == 'Cash'` trap is defused** ahead of the change that would
   have sprung it. `ShiftSummary.cashTaken` selects on tender type, so §37
   making payment methods configurable is no longer a money bug waiting to
   happen.
3. **`BlindCountDialog` is unblocked and built.** §4.2's reconciliation was
   adopted: `shift.view_expected_cash` gates the figure before counting,
   `cash.variance.view` gates the difference after committing, and
   `cash.view_expected` is folded away as a duplicate.

### What Wave B did not build

**Drawer records and multi-drawer.** `pos_cash_drawers` exists and nothing
writes to it: every till has one drawer and it is theirs, so `drawer_id` stays
null. `cash.view_all_drawers` becomes meaningful when a branch has a shared
service-counter drawer, which is Wave E's shape rather than this one's.

**The X report as its own screen.** §27's figures are all computed and the Z
report draws them; a mid-shift snapshot is the same widget without the count
field. It is a screen, not a calculation, and it belongs with Wave G's reports
where the other read-only views live.

**The granular cash capabilities.** §22's list names twelve
(`cash.view_balance`, `cash.add`, `cash.count`…). Five were added — the ones
with a control behind them. The rest are Wave C's job for the same reason the
Wave A ones were, and migration 15 is the reminder that adding one has a cost.

### Deferred on purpose

**The capability expansion.** The plan's A.10 lists roughly fifty granular keys
(`order.transfer`, `discount.above_limit`, `payment.partial_refund`…). There are
**19**. Three were added as the features that needed them landed; the rest are a
Wave C concern in practice, because the `text[]` model takes them without a
migration and `PosCapability.canonical` means nothing gets renamed later.
Migration 13 is the reminder that adding one is not free: an existing owner role
does not get it by itself.

**The sent timestamp.** Compact density is specified as dropping it and nothing
else. There is nowhere on a `TicketLine` that records when a round went out, so
there is nothing yet to drop. The rule is written down in `CartDensity` for
whoever adds it.

---

## 4. The one thing still unverified

**The `pos_till` password.** Every database suite has been run as `amerelsayed`,
the superuser. That verifies the SQL and none of the grants — a superuser needs
no grant at all, so a missing one is invisible.

It matters most for refunds. Migration 12's counters are maintained by
`SECURITY DEFINER` triggers and the till is deliberately granted **no** UPDATE on
either. Whether that combination works under the till's own privileges is
exactly what a superuser run cannot say.

Partial cover exists: `test/data/till_grants_test.dart` asserts the grant list
itself without a server — that the counters are not grantable, that refunds are
INSERT-only, that every table order history joins is readable. That is the shape
of the grants, not proof they suffice.

---

## 5. Working tree

Everything since `ba665d3` is uncommitted — the price override, the reprint, the
cart density work, migration 13, and the two test fixes. Worth a commit before
Wave B starts.
