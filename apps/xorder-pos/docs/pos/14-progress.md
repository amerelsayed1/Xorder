# Progress — where the gap-closure plan stands

**As of 8 September 2026** (§§1–5; §6, added 4 October, is the back office's combos and profit). Companion to [11-gap-closure-plan.md](11-gap-closure-plan.md),
which is the plan; this is the state of it. When the two disagree, this file is
newer.

---

> **13 September 2026 — e-receipts are switched off.** The restaurants this is
> being sold to do not need e-invoicing yet. Nothing was deleted: one switch,
> `etaFilingEnabled` in `lib/domain/services/eta_filing.dart`, stops the queue,
> the filer and the reconciler and hides the Tax authority pane, the receipt
> profile's filing block and the unit's ETA code. A build turns it back on with
> `--dart-define=XORDER_ETA_FILING=true`. The seal and the submission client
> are **not** being built until that changes, and ETA no longer blocks sale.
> Where the text below calls Wave N blocking, read it as history.

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

Asking the same question of the **administrator** credential found a worse one.
An admin role is given the till list *and* the administrative one, and on an
offline install the till list **REVOKEs** the catalogue writes — deliberately, so
a recovered till password cannot reprice the menu. The administrative list never
put them back. Management could open the Menu pane on the one deployment where
menu authoring exists at all, and fail on the first save.

Fixed, and guarded four ways:

* `till_grants_enforced_test.dart` now covers every table added through Wave C —
  settings, cash movements, business days, tax groups, the receipt profile, the
  e-receipt queue's column-scoped grant, and the permission tables. The refund
  counters that this section used to say were unverifiable are among them.
* `till_grants_cover_usage_test.dart` scans the source: every table a till
  repository names must appear in `tillGrants`, and every table named in
  `tillGrants` must exist. It runs with no server, so it fires on every commit,
  and it was checked by deleting a grant and watching it fail.
* `admin_grants_enforced_test.dart` does the same for the administrator role,
  applying both lists in the order `pos_migrate --grant-admin-to` applies them,
  and asserting the back office is still not a way around the column-scoped
  grant on a settled sale.
* `till_grants_test.dart` continues to assert the statements' shape.

Both enforced suites were checked the only way that means anything: by deleting
a grant and watching them fail.

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

---

## 6. Back office: combos and profit (4 Oct 2026)

Three slices that close the chain `16-back-office-scope.md` §3 describes,
plus one correction to a screen the chain exposed.

**Combo authoring.** The till has sold combos since Wave M and nothing could
create one. `ComboDraft` / `ComboRules` (pure, `lib/domain/models/combo_draft.dart`)
hold the rules; `CatalogAdminRepository.combos()` and `saveCombo()` write the
whole tree in one transaction, matching groups by id so they keep it, and
replacing a group's options as a set (nothing refers to an option row — an order
line snapshots its items). Refusals are data (`ComboRefused(ComboProblem)`),
worded per language. Hidden on a cloud till with the other authoring panes.

**Profit.** `ReportsRepository.profit(filter)` joins the Items list's revenue to
the stock ledger's cost, per (order, item), in one `REPEATABLE READ` snapshot.
The three rules that matter, each pinned by a database test that was checked by
deleting the rule: only `kind = 'sale'` movements; a recorded cost of zero is
*uncosted*; each movement rounded half-up on its own, as `Quantity.costAt`.
The UI is a second section on Reports › Items and a second sheet of its Excel
export — not a new tab, which would have changed the owner's Reports map.

**Stock pane.** The Average cost column already existed. What was wrong was that
a never-received item read `0.00`, which says "free" about the one item nobody
has priced. It is now a dash and a "no cost" tag, with one note above the rows.

**Decisions worth keeping**

* **Profit is claimed only where it can be honest.** A business-wide profit
  needs every item costed; this reports per item, with coverage beside the
  margin, rather than a number that quietly covers half the menu.
* **A refund does not give the cost back.** The ledger has no refund movement,
  so this is the reading it can support; it can only understate profit.
* **Fixtures:** an option `RESTRICT`s deleting its product, so a suite that
  wipes restaurants must delete `pos_combos` first; and the audit ledger is
  append-only, so a test reading it must filter by restaurant.

**Tax-inclusive restaurants (4 Oct, later the same day).** Profit first shipped
with a warning that revenue still contained VAT. It now takes the tax out: each
line is scaled by its order's net-to-gross ratio from `pos_order_taxes`, in one
integer half-up expression in the query. Lines carry no tax group, so this is
the order's blend — exact at one rate, an estimate at several (pinned by a
database test that states the zero-rated-item case outright). Deliberately **not**
done: per-line tax by re-deriving each product's *current* group, which silently
drifts the day a product is moved to another rate.

**Uncosted stock (4 Oct, on its own branch).** The Stock pane used to add an
item with stock and no cost into the total at zero, so the total read as the
whole shelf. `StockValuation` now totals the costed items and counts the
uncosted items with stock on hand, and the pane says it under the total ("Not
counted: N item(s) with stock on hand and no cost"); an uncosted row's value is a
dash. Chosen over estimating a cost from the menu price, which would put an
invented number in the same total as real ones. Giving such an item a real cost
needs an opening-cost movement — the ledger has an `opening` kind, nothing writes
it yet.

**Opening cost (4 Oct, on the same branch as uncosted stock).** An item with
stock and no cost can now be given its first cost from the Stock pane ("Set
cost"). It is the other way into "costed": a restaurant that starts with stock
already on the shelf says what it cost. The rules are `OpeningCost` (pure,
`stock_costing.dart`): only a cost above zero, only on an item that has none —
changing one is a revaluation, a different act — and quantity is never touched.
`ReceivingRepository.setOpeningCost` records it as an `opening` movement **of
quantity zero** carrying the cost and the resulting position, upserts the level,
and audits it (`stock.cost_set`), under `purchase.manage` as receiving is.

**Migration 52** relaxes `pos_stock_movements_not_nothing` to
`quantity_milli <> 0 OR kind = 'opening'`. A cost is not a physical movement, so
its row moves nothing; every other kind still refuses a movement of nothing, and
a database test pins both halves. Relaxing a CHECK admits rows the old one
refused and invalidates none, so it is safe on a live database.

It also removes a quirk worth knowing: receiving into uncosted stock averages the
shelf in **at zero**, so ten unpriced units plus ten bought at 5.00 read as 2.50.
After an opening cost, the delivery averages against the real figure. Past sales
stay uncosted — they were recorded at zero and the ledger is append-only — so
this prices what is sold from now on, and the dialog says so before it asks.

**Customers pane (4 Oct).** `pos_customers` and `pos_orders.customer_id` arrived in
migration 51 so the counter could attach a customer to an order; nothing in the
back office read them. People › Customers (`CustomerDirectoryRepository`) lists
the directory with each customer's settled orders at this branch, what they kept
net of refunds, and their last order — one `LEFT JOIN LATERAL`, refunds summed per
order — and a row opens their details and recent orders. Search is the counter's
own rule (a name fragment, or phone digits normalised so Arabic-Indic digits
match), so a name finds the same person in both places. Read-only on purpose: the
phone is a customer's identity, and changing it is changing who they are. Two
database mutations were checked the clean way — with a tautology in place of the
filter, because deleting the line leaves an unused parameter and fails every test
for the wrong reason.

**The customer on the sale (4 Oct).** The sales list gets a Customer column, its
search matches the customer's name and, from seven digits, their phone, and the
order detail shows name, phone and email when there is one. The seven-digit floor
is the one decision in it: a short run of digits is the tail of a receipt number
far more often than of a phone, so matching both would list a stranger's sale for
a cashier who typed what was on a receipt — a database test puts such a stranger
in the ledger and fails if the floor is lowered. A customer removed from the
directory leaves their sales behind unnamed (`ON DELETE SET NULL`). Cancelled
orders does not draw the column: its three shared columns are the void, and a
fourth would squeeze the reason that list is read for. At the back office's
1100px with the detail pane open the list already scrolled sideways, so the new
column starts partly off-screen there and shows in full wider.

**Profit & loss (5 Oct).** Finance › Profit & loss composes four reports already
drawn elsewhere (`ProfitAndLoss.of` over sales, tax, profit and expenses, asserted
to be of one period) into revenue → cost of goods → gross profit → drawer expenses
→ operating result. The work was in the definitions, not the arithmetic, and three
of them are decisions worth keeping: **tax is taken out of revenue** (it was
collected for the state); **a supplier payment is not an expense**, because the
goods it bought are in cost of goods when sold — Finance's own Expenses figure is
cash paid out and *does* include it, so the two screens answer different questions
and the page says what it left out; and **while any sales have no cost, the gross
profit and the result are labelled "before items with no cost"**, with the costed
share beside them, rather than quoted as complete. The statement ships with the
list of what it excludes, because a result drawn without it reads as the
business's profit and the data does not support that. Receivables are the other
half of Accounting lite and are not started: a sale cannot go on account yet.

**Known gaps:** the tax mode is today's setting, not a per-order snapshot; an
item that already has a cost cannot be revalued (no revaluation movement exists);
there is no cost column on the product itself.

**Verification:** `flutter analyze` clean · **2,448 unit and widget tests** pass,
64 skipped · the combo, profit and reports database suites (**50 tests**) pass
against PostgreSQL 16. Not run: the rest of the database suites, and the
`integration_test/` end-to-end run, in this change.
