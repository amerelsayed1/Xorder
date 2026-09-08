# Progress — where the gap-closure plan stands

**As of 8 September 2026.** Companion to [11-gap-closure-plan.md](11-gap-closure-plan.md),
which is the plan; this is the state of it. When the two disagree, this file is
newer.

---

## 1. The short version

**Waves A, B and M are complete.** Migrations 9 through 18 are applied.
**Wave N — the ETA e-receipt — is next, and it is what makes the product
legal to sell in Egypt.**

| Wave | State |
|---|---|
| **A** — discount, void, refund, history, price override, reprint, cart density | ✅ |
| **B** — settings, cash movements, business day, blind close | ✅ |
| **M** — menu & tax model | ✅ |
| **N** — ETA e-receipt | ⬜ next, and blocking |

**Verification:** `flutter analyze` clean · **943 unit tests** pass, 18 skipped
· **389 database tests** pass.

---

## 2. Wave M so far

### The tax model — the blocking prerequisite, done

`tax_lines[]` exists. Tax is computed **per rate**, not per ticket and not per
line: products name a tax group, bases accumulate per group, and each group is
rounded once. Per-rate is what a filing needs and — on a menu where everything
shares one rate — arithmetically identical to what it replaced. **All 31 golden
money tests from Wave A pass unchanged**, which is how that is checked rather
than asserted.

The first attempt failed one of them immediately, which was worth having:
`defaultTaxGroup` built its fallback fresh per call, so without value equality
on `TaxGroup` every line became its own map key and was rounded alone.

Migration 16 backfills every existing restaurant with the rate it has been
charging, read out of `pos_money_config` so a branch on 15% keeps 15%. A
database test found the other half — nothing seeded a restaurant created
*after* the migration — which `LocalBootstrap.seedTaxGroup` now does.

### Per-branch pricing, done

An override table, resolved at the catalogue read. A restaurant with one price
everywhere writes no rows. An override can withdraw a product and never
reinstate one: the menu is the ceiling.

**Per-channel pricing is schema-only**, deliberately. It needs the price to vary
with the *ticket's* order type, which a catalogue read cannot know. The column
exists and nothing authors one, so nobody can set a delivery price and watch it
be ignored.

### Modifier economics, done

`free_options`, `min_select`, `is_default`. The free allowance takes the
**cheapest** options, so the price cannot depend on tap order. It is a snapshot
computed when the line is added — a group edited tomorrow must not reprice a
table still sitting there.

### Combos, done

A combo is **not** a product with modifiers: its components are real menu items
a kitchen has to make and a receipt has to list. It is also not the sum of its
parts, which is the entire point — the components' own prices are never
consulted.

`TicketLine` keeps its product beside the selection rather than growing a second
shape, because every path on the ticket is written in terms of a product. The
picker only opens when there is something to decide, and combos lead their
category on the grid — one buried under forty items is one nobody rings up.

`pos_combo_options.product_id` is `RESTRICT`, so deleting a product cannot
silently empty a group. That also means a test fixture must clear combos before
deleting a restaurant: Postgres cannot tell a teardown from a mistake.

---

## 3. What is left, in order

**The order changed on 8 September 2026.** A competitor comparison found that
Egypt's ETA e-receipt mandate has been in force since 15 September 2025, and a
restaurant on the ETA list cannot legally run its tills on this build. Wave C
makes the product better; ETA makes it sellable. See
[15-competitive-position.md](15-competitive-position.md).

| Wave | Theme | Migration | Size |
|---|---|---|---|
| **N** | **ETA e-receipt** — e-seal signing, submission queue, QR on the slip | 19 | L |
| **C** | Permission model to specification | 20 | L |
| **D** | Settings & configuration screens | 21 | XL |
| **E** | Floors & tables | 22 | M |
| **F** | Kitchen, printing, hardware | 23 | L |
| **G** | Reports · X/Z · export/import | — | L |
| **H** | Customers | 24 | M |
| **I** | Auth & security hardening | 25 | M |
| **J** | Backup · restore · diagnostics | 26 | L |
| **K** | Local API tier | 27 | XXL |
| **L** | Inventory & recipes (P1) | 28 | XL |

**Wave N is unblocked.** `tax_lines[]` is underneath it, and the offline
architecture is already the right shape: ETA permits store-and-forward within 24
hours, so the outbox, the idempotency and the never-silently-discarded rule are
all reusable. What is missing is a second destination and a signature.

**Still schema-only:** per-channel (delivery vs dine-in) pricing. It needs the
price to vary with the *ticket's* order type, which a catalogue read cannot
know. The column exists and nothing authors one, so nobody can set a delivery
price and watch it be ignored.

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

## 4. Grants — resolved, and what it cost to leave it

**This was wrong for months, and the fix did not need the `pos_till` password.**

Every database suite ran as `amerelsayed`, the superuser, so a missing grant was
invisible. The standing note here said the way out was the till's own password.
It was not: `test/data/till_grants_enforced_test.dart` creates a **throwaway
probe role**, applies the grant list to it and connects as that role — which
verifies the grants exactly and needs no credential anybody has to be asked for.
The mechanism was already in the file; it had simply never been pointed at
anything added after Wave A.

When it was, it found six tables the till uses and had **no grant on at all**:
`pos_product_prices`, `pos_combos`, `pos_combo_groups`, `pos_combo_options`
(joined by the catalogue query) and `pos_order_taxes`, `pos_order_line_items`
(written at settlement). An offline till on its own credential could not have
loaded its menu or recorded a sale. Nothing failed in CI because the superuser
needs no grant — which is the precise class of bug a superuser run cannot see.

Fixed, and guarded three ways:

* `till_grants_enforced_test.dart` now covers every table added through Wave C —
  settings, cash movements, business days, tax groups, the receipt profile, the
  e-receipt queue's column-scoped grant, and the permission tables. The refund
  counters that this section used to say were unverifiable are among them.
* `till_grants_cover_usage_test.dart` scans the source: every table a till
  repository names must appear in `tillGrants`, and every table named in
  `tillGrants` must exist. It runs with no server, so it fires on every commit,
  and it was checked by deleting a grant and watching it fail.
* `till_grants_test.dart` continues to assert the statements' shape.

**The lesson worth keeping:** a grant list only ever grows and nobody re-reads
it. The guard reads it.

---

## 5. Where the waves stand (8 Sep 2026)

**A, B, M, N and C are done**, in that order; everything is committed.

* **Wave M** — tax by rate, per-branch pricing, modifier economics, combos, and
  menu import from CSV or Excel.
* **Wave N** — the receipt profile, the ETA document with its canonical
  serialization and uuid, the queue with its per-device chain and 24-hour
  deadline, settlement wiring, the QR column and rendering, and the Management
  screen showing what has not cleared. **Not built:** the e-seal and the
  submission client, which need a token and a sandbox account rather than a
  decision. The signing binding chosen is ETA's own integration toolkit.
* **Wave C** — the §106 resolution as a pure resolver, §107 risk levels driving
  the override and hide/disable rules, §105 per-person overrides, §16/§18
  ceilings that bind at the till, §48 (no granting what you lack) enforced at
  every write, and §49's six role templates. §50's sixteen `SETTINGS.*` keys are
  deferred to Wave D, where the sections they gate exist.

Two claims in the older plan text were **stale and have been struck through
rather than quietly deleted**: branch scoping was already enforced on both
sign-in paths with a test, and Wave C's `pos_permissions` table was deliberately
not built — the catalogue lives in Dart because the code checks against string
constants, so a table would be a seeded copy.

**Next: Wave D** — the settings surface, the configurable order types, taxes,
service charges and tender types, and the settings navigation the six Management
panes fold into.
