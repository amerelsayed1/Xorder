# Gap-Closure Plan — SRS v1.0 → shipped POS

**Baseline:** the SRS/implementation comparison of 2026-09-07.
**Current state:** 8 migrations, 16 capabilities (5 enforced), 6 management panes,
10 wizard steps, no local API tier.
**Scope of this document:** every item marked ❌ or 🟡 in that comparison, sequenced,
with the schema, domain, permission, audit, UI and test work each one implies.

This plan does **not** re-litigate what is already built. Where the implementation
already exceeds the SRS — append-only audit, integer minor units, migration
discipline, the unconfigured-repository honesty rule — those are constraints on
the new work, not candidates for change.

---

## 0. One decision that shapes everything else

SRS §71 mandates:

```
POS Terminal → XOrder Local REST/WebSocket API → Business Logic → PostgreSQL
```

The till today **is** the PostgreSQL client. Business rules live in the repository
layer, which is honest and testable, and the `pos_till` grant set (no DELETE, no
DDL) is a real mitigation — but §116's guarantee ("even if someone calls
`POST /orders/{id}/refund` directly, the server must verify `PAYMENT.REFUND`")
cannot hold when there is no endpoint at all, and §86's live configuration
propagation has no transport.

**Two viable answers, and the rest of the plan is written to work under either:**

| | Option A — keep direct-to-PG | Option B — introduce the local API tier |
|---|---|---|
| Effort | 0 | Wave K, the single largest item in this plan |
| §65, §71, §86, §6 (approve/reject) | permanently deviated | satisfied |
| Multi-till config propagation | poll on read | WebSocket push |
| Trust boundary | database GRANTs + repository layer | API auth + repository layer |
| Terminal fields (§5), last-seen, app version | must be written by the till itself | server-observed |

**Recommendation: Option B, but *last* (Wave K), not first.** Every wave below is
written against the `domain/repositories/` interfaces, which is precisely the seam
the README already names as the swap point. Building features against those
interfaces now and moving the implementation behind an HTTP client later is a
provider-binding change, not a rewrite. Building the API tier first would delay
every revenue-visible gap — discounts, refunds, cash movements — behind
infrastructure no cashier can see.

**Everything in Waves A–J must therefore be written so that no widget imports the
`postgres` driver and no business rule lives in a widget.** That is already the
house rule; it becomes load-bearing here.

---

## 1. Invariants — apply to every wave, no exceptions

1. **Money is integer minor units.** `bigint` in SQL, `Money` in Dart, exponent
   carried, never `numeric`, never `double`. Rounding half-up, applied once.
2. **Timestamps are `timestamptz`.** Never `timestamp`.
3. **The migration list is append-only.** New work adds migrations 9…N; no applied
   migration is edited.
4. **Audit is append-only and written in the same transaction as the change.**
   New audit actions are added to `AuditAction`; the trigger and grants stay.
5. **Financial and catalogue rows are archived, never deleted.** The one exception
   remains `pos_parked_tickets`.
6. **Every permission check goes through `Authorization`.** UI may be more
   restrictive than the data layer; never less.
7. **No fake data reaches a real install.** New repositories get an
   `Unconfigured…` counterpart that returns nothing or refuses out loud.
8. **Every new capability string is added to `PosCapability.all` and to
   `CapabilityGroup`, and every rename goes through `canonical`.**
9. **Every new screen ships EN + AR with RTL, and both palettes.**

---

## 2. Wave map

| Wave | Theme | Migrations | SRS sections closed | Size |
|---|---|---|---|---|
| **A** | Discount · Void · Refund | 9, 10, 11, 12, 13 | 14–21, 39, 42, 90, 91 | XL |
| **B** | Cash drawer · Pay in/out · Business day | 14 | 22–28, 92 | L |
| **C** | Permission model to spec | 13 | 10–17, 22, 24, 29, 32, 48, 50, 55, 60–61, 81, 105–108, 112 | L |
| **D** | Settings & configuration surface | 14 | 4.5, 4.7, 31, 37, 38, 40, 51–54, 85 | XL |
| **E** | Floors & tables | 15 | 29, 30, 42 | M |
| **F** | Kitchen & printing & hardware | 16 | 8, 33–34, 43–46, 78–81 | L |
| **G** | Reports · X/Z · export/import | — | 59–61, 95, 96 | L |
| **H** | Customers | 17 | 58, 31 (required-customer) | M |
| **I** | Auth & security hardening | 18 | 7, 8, 47, 82, 83, 84, 111 | M |
| **J** | Backup · restore · diagnostics · logs · updates | 19 | 72–77, 99, 110 | L |
| **K** | Local API tier · registration · propagation | 20 | 5, 6, 65, 66, 71, 86, 116, 117 | XXL |
| **L** | Inventory & recipes (P1) | 21 | 33 (inventory), 55–57 | XL |
| **M** | P1/P2 remainder | — | 114, 115 | — |

Sizes: **M** ≈ 1–2 engineer-weeks · **L** ≈ 3–5 · **XL** ≈ 6–10 · **XXL** ≈ 10+.
They assume one engineer familiar with the codebase, with design specs in hand.

**Dependency notes.**
* C wants to come before A on paper, because A needs granular keys. It does not,
  because A can add its keys to the existing `text[]` model and C migrates the
  *storage* later without renaming anything — the `canonical` map is exactly the
  mechanism for that. **Do A first; it is what the business is missing.**
* D is a prerequisite for F (printer/station config), G (report filters) and
  parts of B (blind-close toggle, business-day start time). Ship D's *settings
  infrastructure* (scoped `pos_settings` + the Settings shell) early, inside
  Wave B, and its screens progressively.
* K can start any time after C; it is sequenced last only by priority.

---

## 3. Wave A — Discount, Void, Refund

The largest single gap. Three operations the permission model, the override flow
and the audit ledger were all built to police, none of which exist.

### A.1 Order lifecycle (SRS §90, §91)

`pos_orders` today is written **only at settlement**. In-flight state lives in
`pos_parked_tickets` (jsonb). That is workable for selling, but void, refund and
kitchen tickets all need an order row that exists before the money moves.

**Migration 9 — order lifecycle** — **applied ✅**

```
ALTER TABLE pos_orders ADD COLUMN status text NOT NULL DEFAULT 'PAID'
  CHECK (status IN ('DRAFT','OPEN','SENT_TO_KITCHEN','READY','PAID','CLOSED',
                    'VOIDED','CANCELLED','REFUNDED','PARTIALLY_REFUNDED'))
ALTER TABLE pos_orders ADD COLUMN status_changed_at timestamptz NOT NULL DEFAULT now()
ALTER TABLE pos_orders ADD COLUMN voided_at timestamptz
ALTER TABLE pos_orders ADD COLUMN voided_by bigint REFERENCES pos_staff(id) ON DELETE RESTRICT
ALTER TABLE pos_orders ADD COLUMN void_reason_id bigint
ALTER TABLE pos_orders ADD COLUMN void_note text
ALTER TABLE pos_orders ADD COLUMN business_day_id bigint          -- FK added in M12
ALTER TABLE pos_order_lines ADD COLUMN voided_at timestamptz
ALTER TABLE pos_order_lines ADD COLUMN voided_by bigint
ALTER TABLE pos_order_lines ADD COLUMN void_reason_id bigint
ALTER TABLE pos_order_lines ADD COLUMN refunded_quantity integer NOT NULL DEFAULT 0
CREATE TABLE pos_reason_codes (
  id bigserial PRIMARY KEY, restaurant_id bigint NOT NULL REFERENCES pos_restaurants(id),
  scope text NOT NULL CHECK (scope IN ('void','refund','pay_out','pay_in','waste','adjustment','price_override','discount')),
  code text NOT NULL, name_en text NOT NULL, name_ar text,
  requirement text NOT NULL DEFAULT 'required' CHECK (requirement IN ('required','optional','disabled')),
  sort_order integer NOT NULL DEFAULT 0, is_active boolean NOT NULL DEFAULT true,
  UNIQUE (restaurant_id, scope, code))
CREATE TABLE pos_order_line_events (        -- §15: delete-after-send ≠ delete-before-send
  id bigserial PRIMARY KEY, order_id bigint NOT NULL REFERENCES pos_orders(id),
  line_key text NOT NULL, event text NOT NULL,   -- added|quantity_changed|removed_before_send|voided_after_send|price_overridden
  quantity_before integer, quantity_after integer,
  unit_price_before_minor bigint, unit_price_after_minor bigint,
  reason_id bigint, note text,
  staff_id bigint NOT NULL, approved_by_id bigint, occurred_at timestamptz NOT NULL DEFAULT now())
```

`status` defaults to `PAID` because every existing row is a settled sale — inventing
any other status for history would be a lie in the ledger.

Seed the eight §20 void reasons and the §56 adjustment reasons per restaurant, as
`is_system`-style rows a restaurant edits.

### A.2 Discounts (SRS §16, §39)

**Migration 10 — discounts** — **applied ✅**

```
CREATE TABLE pos_discounts (
  id bigserial PRIMARY KEY, restaurant_id bigint NOT NULL,
  code text NOT NULL, name_en text NOT NULL, name_ar text,
  kind text NOT NULL CHECK (kind IN ('percentage','fixed')),
  value_bp integer, value_minor bigint,       -- exactly one non-null, by CHECK
  scope text NOT NULL CHECK (scope IN ('order','item')),
  min_order_minor bigint, max_discount_minor bigint,
  starts_at timestamptz, ends_at timestamptz,
  days_of_week smallint[] NOT NULL DEFAULT '{}',
  time_from time, time_to time,
  requires_customer boolean NOT NULL DEFAULT false,
  requires_manager  boolean NOT NULL DEFAULT false,
  is_restricted     boolean NOT NULL DEFAULT false,
  is_active boolean NOT NULL DEFAULT true,
  revision integer NOT NULL DEFAULT 1, updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (restaurant_id, code))
CREATE TABLE pos_discount_targets (          -- categories / products / order types
  discount_id bigint NOT NULL REFERENCES pos_discounts(id) ON DELETE CASCADE,
  target_type text NOT NULL CHECK (target_type IN ('category','product','order_type')),
  target_id text NOT NULL, PRIMARY KEY (discount_id, target_type, target_id))
CREATE TABLE pos_order_discounts (           -- SNAPSHOT: name, kind, value at time of sale
  id bigserial PRIMARY KEY, order_id bigint NOT NULL REFERENCES pos_orders(id) ON DELETE CASCADE,
  order_line_id bigint REFERENCES pos_order_lines(id) ON DELETE CASCADE,  -- null = order-level
  discount_id bigint, name_snapshot text NOT NULL, kind text NOT NULL,
  value_bp integer, value_minor bigint, amount_minor bigint NOT NULL,
  reason_id bigint, note text,
  applied_by bigint NOT NULL, approved_by_id bigint,
  applied_at timestamptz NOT NULL DEFAULT now(),
  CHECK (amount_minor >= 0))
ALTER TABLE pos_orders ADD COLUMN discount_minor bigint NOT NULL DEFAULT 0
```

**Manual-discount ceilings (§16)** are a *limit*, not a permission — see Wave C's
`pos_permission_limits`. Until C lands they are two columns on `pos_roles`
(`max_discount_bp`, `max_discount_minor`), shipped in migration 10. **NULL means
unlimited, never zero** — reading a missing cap as zero would have left every
existing role, the owner's included, unable to discount anything the moment the
migration ran. Read them in the same place the resolution engine will later read
the limit table, so the call site does not move.

**`TicketEngine` changes.** Discount is a pure function on the ticket:
`applyOrderDiscount`, `applyLineDiscount`, `removeDiscount`, each returning
`TicketResult`. Refusals: `DiscountAboveLimit(limit, requested)`,
`DiscountRequiresCustomer`, `DiscountNotApplicable(product)`. `TicketTotals` gains
`discount` and the VAT base becomes `subtotal − discount + service` — **this is the
single riskiest calculation change in the plan** and needs a golden-file test suite
of at least 30 cases before it ships.

### A.3 Void & cancel (SRS §19, §20)

Four distinct operations, four distinct permissions, four distinct records:

| Act | When | Permission | Record |
|---|---|---|---|
| Cancel line | before send | `ORDER.ITEM.DELETE_BEFORE_SEND` | `pos_order_line_events` |
| Void line | after send | `ORDER.ITEM.DELETE_AFTER_SEND` | line event + `pos_order_lines.voided_*` + kitchen void ticket (Wave F) |
| Cancel order | before send | — | **nothing** — see below |
| Void order | after send, before payment | `order.void` | a `VOIDED` order row + its lines + audit |

**Built, with one decision worth recording.** The plan implied an order row
existing from `DRAFT` onward, so a void could `UPDATE` its status. That would
mean writing an order at send-round time and turning settlement from an INSERT
into an UPDATE — a change to idempotency, invoice numbering and the outbox, all
on the money path, for a status nothing yet reads.

So a voided order is **written at void time**, complete, with `status =
'VOIDED'`. The settlement path is untouched. The full `DRAFT → OPEN →
SENT_TO_KITCHEN` progression becomes worth building when something observes it —
the KDS in Wave F — and migration 9's `status` column already accepts it.

**Clearing an unsent ticket records nothing at all.** Nothing was made and
nothing was wasted; a row for every abandoned keystroke would fill the ledger
with noise and make the void report useless. The boundary is whether the kitchen
has seen any of it, which is the SRS's own distinction between Cancel and Void.
| Refund | after payment | `PAYMENT.REFUND` | A.4 |

`_void()` in [sale_screen.dart](../../lib/features/sale/sale_screen.dart) is replaced by
a dialog that picks the right one from ticket state, demands a reason where the
reason code says `required`, routes through `Authorization` → `SupervisorOverride`
when the decision is `NeedsOverride`, and writes the audit row with both parties.

### A.4 Order history (SRS §90)

**Migration 11 — `who sold it`** — **applied ✅**

Not in the original plan. It was found while building the history list: an
order could say who *voided* it and could not say who *sold* it. `shift_id` is
not an answer — a drawer is worked by more than one person, and attributing
every sale to whoever opened the till is not a smaller truth, it is a wrong one.

```
ALTER TABLE pos_orders ADD COLUMN served_by bigint REFERENCES pos_staff(id) ON DELETE RESTRICT
CREATE INDEX pos_orders_history_idx     ON pos_orders (restaurant_id, branch_id, occurred_at DESC)
CREATE INDEX pos_orders_served_by_idx   ON pos_orders (restaurant_id, served_by, occurred_at DESC)
                                        WHERE served_by IS NOT NULL
```

Nullable, because every order written before this has no seller and there is
nobody to backfill them with. `RESTRICT`, so deleting a member of staff cannot
delete the record of what they sold.

Three things needed it before they could be built: history lists the seller, a
refund (§18) is issued against a sale somebody made, and sales-by-staff (§59) is
a report with no subject without it. **This is why history comes before
refunds** — A.5 and A.7 both start with "find the order", and building the
lookup once means neither invents its own.

**Built:** `OrderHistoryRepository` (`search` · `detail` · `byInvoiceNumber`),
read-only and branch-scoped, kept apart from `OrdersRepository` so a screen that
merely looks at history cannot be handed something that can settle a sale.
`OrderRecord` is deliberately **not** a `Ticket`: it has no `totals` getter, and
that absence is the point — every number on it was decided once and must not
move because a menu price or a tax rate changed afterwards.

The screen is a routed destination (`/orders`, `F7`), gated on the new
`order.view_all` capability — seeded to owner, manager and supervisor, withheld
from cashier. `order.view_own` is left to Wave C: scoping history to "mine" is
only meaningful once `served_by` has data behind it.

**Not built here:** reprint (A.7) and refund (A.6) actions. They attach to the
detail pane, which is why it is its own file.

### A.4b Price override (SRS §16) — **built ✅**

**No migration.** Migration 9 already provisioned
`pos_order_line_events.unit_price_before_minor`, `unit_price_after_minor` and
`price_overridden` in its CHECK constraint. Building the feature was a matter of
filling columns that were waiting for it.

`PriceOverride` sits on `TicketLine` as a snapshot — the replaced price as well
as the replacing one, plus who, why and the approver. It overrides the **whole
unit price**, modifiers folded in: "make it 40" means the customer pays 40 for
that item, not 40 plus the extras.

**The control that matters — a price override is a discount by another name.**
Without a ceiling, a cashier holding `price.override` and a 10 % discount limit
could reprice a 50.00 dish to 5.00 and take 90 % off a line the discount sheet
would have refused. `TicketEngine.overridePrice` therefore measures the
*reduction* against the same `DiscountLimit`, refuses with `PriceBelowLimit`,
and the flow escalates to a supervisor and retries with `limit: null` — the same
three steps the discount sheet already makes.

Two details that follow from it:

* The ceiling is measured against the **menu** price, not the current one.
  Otherwise 50 → 45 passes, then 45 → 40.50 passes, and the customer has 19 %
  off with no approval anywhere.
* "Was" always quotes the menu. A second override that quoted the first one's
  price as the list price would understate what the restaurant gave away.

Charging **more** than the menu price is allowed and unlimited — it gives
nothing away, so there is no ceiling to breach — and still recorded and
reasoned. Zero is allowed: it is a comp. Below zero is refused; that is a refund
wearing a disguise, and it has its own flow and its own permission.

Restoring the menu price is recorded as another `price_overridden` event rather
than by deleting the first. A correction that erased its predecessor would let
somebody reprice, sell, and tidy up after.

**One deviation from the design brief.** The brief asks for this inline on the
cart line. The half that must be inline is: a repriced line shows its menu price
struck through above what is being charged, with a `PRICE` chip. The editing is
a dialog, because a reason is **required** and a reason picker does not fit in a
378 px panel — and a required field with nowhere to go is how a required field
quietly becomes optional.

Reached by `F5` on the selected line. Unlike `F6`, it refuses rather than
falling back to the order: a bill is not an item.

### A.5 Refunds (SRS §18) — **built ✅**

**Migration 12 — refunds** — **applied ✅**

```
CREATE TABLE pos_refunds (
  id bigserial PRIMARY KEY, client_refund_id uuid NOT NULL,
  restaurant_id bigint NOT NULL, branch_id bigint NOT NULL, terminal_id uuid NOT NULL,
  order_id bigint NOT NULL REFERENCES pos_orders(id) ON DELETE RESTRICT,
  shift_id bigint REFERENCES pos_shifts(id), business_day_id bigint,
  kind text NOT NULL CHECK (kind IN ('full','partial')),
  subtotal_minor bigint NOT NULL, vat_minor bigint NOT NULL,
  service_minor bigint NOT NULL, total_minor bigint NOT NULL,
  reason_id bigint NOT NULL, note text,
  refunded_by bigint NOT NULL, approved_by_id bigint,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (restaurant_id, client_refund_id),
  CHECK (total_minor > 0))
CREATE TABLE pos_refund_lines (
  id bigserial PRIMARY KEY, refund_id bigint NOT NULL REFERENCES pos_refunds(id) ON DELETE CASCADE,
  order_line_id bigint NOT NULL REFERENCES pos_order_lines(id) ON DELETE RESTRICT,
  quantity integer NOT NULL CHECK (quantity > 0),
  unit_price_minor bigint NOT NULL, line_total_minor bigint NOT NULL,
  name_snapshot text NOT NULL)
CREATE TABLE pos_refund_payments (           -- how the money went back
  id bigserial PRIMARY KEY, refund_id bigint NOT NULL REFERENCES pos_refunds(id) ON DELETE CASCADE,
  tender_type_id bigint NOT NULL, label text NOT NULL,
  amount_minor bigint NOT NULL CHECK (amount_minor > 0), reference varchar(80))
```

**Refund policy (§18) as settings**, scoped restaurant-level (Wave D infrastructure):
`refund.enabled`, `refund.window` (`same_shift|same_day|7d|30d|unlimited`),
`refund.max_value_minor`, `refund.approval_threshold_minor`,
`refund.receipt_required`, `refund.reason_required` (default `true`).

**Invariants held by the database, not by code — all five in place:**
1. `SUM(pos_refund_lines.quantity)` per `order_line_id` never exceeds
   `pos_order_lines.quantity`. A trigger bumps the `refunded_quantity` counter;
   migration 9's CHECK refuses the row.
2. `SUM(pos_refunds.total_minor)` per order never exceeds `total_minor`. Same
   shape, via a new `pos_orders.refunded_minor` counter and CHECK.
3. **A refund line must belong to the order being refunded.** Not in the
   original plan. Without the `order_id` clause in the trigger a mistyped line
   id refunds somebody else's food and every total still adds up.
4. **A refund says where the money went, and the tender adds up to it.** A
   `DEFERRABLE INITIALLY DEFERRED` constraint trigger, checked at commit
   because the payments are written after the refund they belong to.
5. Idempotent on `client_refund_id`.

**The status follows the money.** The trigger derives `REFUNDED` /
`PARTIALLY_REFUNDED` from the counter, so no Dart path writes an order status
during a refund and the two cannot drift.

**The counters are the till's only lever.** Both triggers are `SECURITY
DEFINER` with a pinned `search_path`, and the till role is granted **no** UPDATE
on either counter — the `refunded_quantity` grant migration 9 added has been
withdrawn. A refund row is the only way the numbers move.

**Two deviations from the plan, both deliberate:**

* `pos_refunds.reason_id` is **nullable**, not `NOT NULL`. §18 lists
  `refund.reason_required` as a *setting* with a default of true; a `NOT NULL`
  column would make its off position unimplementable. The policy is enforced in
  `RefundPolicy`, where it can be configured.
* `pos_refunds` gained `discount_minor`, which the plan's sketch omitted. A
  partial refund gives back a share of the discount too, and a refund that
  recorded subtotal, service and VAT but not discount would not foot.

**The arithmetic — `RefundEngine`.** No tax is ever recomputed. Every part of a
partial refund is a *share* of what the order actually charged, rounded half-up;
the tax configuration is not consulted at all, because a rate that changed since
the sale must not move a figure on a refund receipt.

**And the last refund takes the remainder.** When a refund clears the order, its
parts are the order's parts less everything already given back, rather than a
fresh pro-rata. Without that rule a bill refunded in three pieces can strand a
piastre, and `refunded_minor <= total_minor` eventually refuses a refund that is
arithmetically correct. "Clears" additionally requires the *value* to reconcile,
so a short read of the lines falls back to pro-rata rather than handing back the
whole bill.

**Refund policy (§18)** is `RefundPolicy` — a value object with the SRS's own
defaults today, behind `refundPolicyProvider`, so every screen already asks the
right question. It reads `pos_settings` when Wave D lands and nothing that
depends on it changes.

**UI.** One dialog, not a wizard: the specification's five steps are four single
decisions, and four screens to hand back 62.70 with a customer waiting is three
too many. Items or amount, the tender the money came in on, the reason, and the
running total visible throughout — which is what §18 actually asks for. Reached
from the order-history detail pane. The client refund id is generated **once
when the dialog opens**, so a retry after a timeout replays instead of paying
twice.

### A.7 Receipt reprint (SRS §21) — **built ✅**

`AuditAction.receiptReprinted` had existed as a constant since the audit ledger
was built and had never been written by anything. This is what writes it.

**The receipt had to be taken apart first.** It was built straight from a live
`Ticket`, and a settled order is not one: no `Product` objects, snapshot prices,
and rebuilding a ticket from the ledger would re-price the sale against today's
menu — handing a customer a receipt that disagrees with the one in their hand.
`ReceiptData` is the plain shape both paths feed: a ticket at settlement, an
`OrderRecordDetail` on a reprint. It holds no catalogue and no tax
configuration, so there is nothing there that *could* recompute a total.

Three decisions on the slip itself:

* **`REPRINT — NOT AN ORIGINAL` across the top**, before the restaurant's name.
  Two identical receipts for one sale is how a refund gets claimed twice, and
  somebody handed a slip has to know what it is before they read what is on it.
* **`REFUNDED <amount>` when money has already gone back**, so the paper cannot
  be used to claim a refund that has already been given.
* **The sale's time and the seller's name, not the reprint's.** A slip
  reprinted a week later carrying today's date would be a forgery the till
  produced on request. An order with no recorded seller prints a dash rather
  than falling back to whoever is standing at the till.

**No tax rate is printed on a reprint.** The rates are not columns on
`pos_orders`, and dividing the tax by the net would print a figure that is right
most of the time and wrong wherever rounding went the other way. "Service" and
"VAT" without a percentage is honest; an invented rate is a document somebody
will argue with.

**If the ledger cannot be written, nothing prints.** An unrecorded reprint is
precisely the one somebody wanted, and a missing printer is a smaller problem
than a missing record.

Offered on any order including a voided one — somebody asking for a copy of a
voided slip is asking a fair question, and the paper answers it.

### A.8 Cart density and the line note — **built ✅**

`CartDensity` is a parameter on `CartPanel`, never read from a provider inside
it: the switch is automatic above seven lines and then **sticky for the rest of
that order**, and that rule lives in the sale screen where the order does. Rows
that resize under a finger mid-sale are how a cashier taps the wrong line.

**Compact drops one thing and one thing only: the sent timestamp.** Notes,
discounts, void reasons and struck-through prices all survive at both densities.
A density that hid a reason would make the screen and the ledger disagree at
exactly the moment somebody was arguing about them. (The timestamp is not built
— nothing on a `TicketLine` records when a round went out — so the rule is
written down for whoever adds it.)

The **note** sits on the meta row behind a 6px accent square, added from the
line's action row beside the quantity steppers. No F-key: the map is full, which
is an honest answer rather than a squeezed-in binding. No permission gate
either — a note is an instruction, not a concession, and gating it would put a
supervisor between a cashier and the words "no onions". Draft lines only: a note
added after the round went out would never reach the kitchen, and a control that
silently does nothing is worse than none.

### A.9 Migration 13 — the owner role — **applied ✅**

Not planned, found by a database test. `SystemRoles.owner` is `PosCapability.all`
and `RolesRepository.save` enforces it, but a role seeded **before** Wave A added
`order.item.delete_before_send`, `order.item.delete_after_send` and
`order.view_all` kept an owner who could not grant them — the exact failure the
invariant exists to prevent: a restaurant where nobody can grant a capability
nobody holds.

Additive union, idempotent, and **only the owner**. Manager, supervisor and
cashier are defaults a restaurant edits, and pushing this build's opinion back
over an edited role is what migration 12's reason seed was careful not to do.
The capability list is a frozen literal rather than an interpolation of
`PosCapability.all`: an applied migration is history, and a capability added
after this needs its own migration — which is the point, because somebody has to
think about it.

### A.10 Capabilities added in Wave A

```
order.create · order.view_own · order.view_all · order.edit_own · order.edit_others
order.cancel_before_send · order.void_after_send · order.reopen · order.transfer
order.merge · order.split · order.change_table · order.change_order_type · order.add_note
order.item.add · order.item.delete_before_send · order.item.delete_after_send
order.item.change_quantity · order.item.change_price · order.item.add_free_item
discount.order · discount.item · discount.percentage · discount.fixed
discount.custom_value · discount.above_limit · discount.apply_restricted
discount.create · discount.edit · discount.delete
payment.accept · payment.cash · payment.card · payment.other · payment.split
payment.change_method · payment.delete · payment.refund · payment.partial_refund
payment.full_refund · payment.view_history
```

All added to `PosCapability.all`, grouped into new `CapabilityGroup` members
(`orders`, `items`, `discounts`, `payments`), and seeded into the four system roles
per the §49 default matrix. `discount.apply` and `order.void`/`order.refund` stay as
they are and become *umbrella* keys the finer ones sit under — no renames, so no
`canonical` entries needed.

### A.11 Audit actions added

`order.created` · `order.cancelled` · `order.voided` · `line.cancelled` ·
`line.voided` · `line.quantity_changed` · `price.overridden` · `discount.applied` ·
`discount.removed` · `refund.issued` · `payment.recorded` · `payment.removed` ·
`receipt.reprinted` (constant exists, is never written — wire it).

### A.12 UI

Discount sheet (F6) · void/cancel dialog with reason picker · refund flow (find
order → pick lines or amount → reason → tender back → refund receipt) · price
override on a cart line · reprint action on a settled order. All specified in the
design brief.

### A.13 Acceptance

* Golden money tests: 30+ cases covering order/line discount × percentage/fixed ×
  dine-in/takeaway × VAT base, each asserting `subtotal + service − discount + vat`.
* A void of a sent line leaves the order total, the kitchen record and the audit
  row mutually consistent.
* A partial refund twice over the same line is refused by the database, not by Dart.
* A refund above `refund.approval_threshold_minor` cannot complete without an
  approver id on the row.
* `flutter test` stays green with no PostgreSQL present.

---

## 4. Wave B — Cash drawer, pay in/out, business day

**Migration 12**

```
CREATE TABLE pos_cash_drawers (
  id bigserial PRIMARY KEY, restaurant_id bigint NOT NULL, branch_id bigint NOT NULL,
  terminal_id uuid REFERENCES pos_terminals(id), name text NOT NULL,
  is_active boolean NOT NULL DEFAULT true, created_at timestamptz NOT NULL DEFAULT now())
CREATE TABLE pos_cash_movements (
  id bigserial PRIMARY KEY, restaurant_id bigint NOT NULL, branch_id bigint NOT NULL,
  terminal_id uuid NOT NULL, drawer_id bigint REFERENCES pos_cash_drawers(id),
  shift_id bigint NOT NULL REFERENCES pos_shifts(id) ON DELETE RESTRICT,
  business_day_id bigint,
  kind text NOT NULL CHECK (kind IN ('pay_in','pay_out','drawer_open','float_adjust')),
  amount_minor bigint NOT NULL DEFAULT 0,
  reason_id bigint, note text,
  staff_id bigint NOT NULL, approved_by_id bigint,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  CHECK ((kind = 'drawer_open' AND amount_minor = 0) OR amount_minor > 0))
CREATE TABLE pos_business_days (
  id bigserial PRIMARY KEY, restaurant_id bigint NOT NULL, branch_id bigint NOT NULL,
  business_date date NOT NULL, opened_at timestamptz NOT NULL DEFAULT now(),
  closed_at timestamptz, closed_by bigint, forced boolean NOT NULL DEFAULT false,
  force_reason text, gross_minor bigint, net_minor bigint,
  UNIQUE (restaurant_id, branch_id, business_date))
CREATE UNIQUE INDEX pos_business_days_one_open
  ON pos_business_days (restaurant_id, branch_id) WHERE closed_at IS NULL
-- late FKs
ALTER TABLE pos_orders   ADD CONSTRAINT ... FOREIGN KEY (business_day_id) REFERENCES pos_business_days(id)
ALTER TABLE pos_refunds  ADD CONSTRAINT ... FOREIGN KEY (business_day_id) REFERENCES pos_business_days(id)
ALTER TABLE pos_shifts   ADD COLUMN business_day_id bigint REFERENCES pos_business_days(id)
ALTER TABLE pos_shifts   ADD COLUMN opened_with_approval_by bigint  -- §26 require-manager
```

**Business day start time (§92)** is a restaurant setting (`day.start_time`,
default `06:00`). The business day a sale belongs to is computed from
`occurred_at` and that offset, resolved once at order insert, stored, never derived.

**Shift close (§27)** expands `ShiftSummary` to carry every required total:
gross, net, tax, service, discounts, refunds, voids, cash, card, other, cash-in,
cash-out, expected, counted, variance. Closing validation lists blockers —
open orders, parked tickets, unsettled payments — and states them rather than
refusing silently.

**Blind closing (§25)** is a restaurant setting plus a permission
(`shift.view_expected_cash`). The close dialog hides the expected figure and the
live variance when blind is on and the closer lacks the permission; it reveals
both after commit for anyone who can see them.

**Business day close (§28)** is a separate screen with a blocker list (open
shifts, open tables, open orders, unpaid orders, unclosed drawers) and a
`day.force_close` path requiring a reason and a manager PIN.

**Capabilities:** `cash.open` · `cash.open_without_sale` · `cash.view_balance` ·
`cash.view_expected` · `cash.add` · `cash.remove` · `cash.pay_in` · `cash.pay_out` ·
`cash.count` · `cash.close` · `cash.view_history` · `cash.view_all_drawers` ·
`shift.close_own` · `shift.close_any` · `shift.view_own` · `shift.view_all` ·
`shift.view_expected_cash` · `shift.adjust` · `shift.reopen` · `shift.force_close` ·
`day.close` · `day.force_close`.

**Audit:** `drawer.opened` · `cash.paid_in` · `cash.paid_out` · `shift.adjusted` ·
`shift.reopened` · `shift.force_closed` · `day.opened` · `day.closed` ·
`day.force_closed`.

**Also in Wave B:** ship the **scoped settings infrastructure** from Wave D early —
`pos_settings` and the Settings shell — because blind-close, day-start and the
refund policy are all settings and hard-coding them now means moving them twice.

---

## 5. Wave C — Permission model to specification

**Migration 13**

```
CREATE TABLE pos_permissions (
  id bigserial PRIMARY KEY, key text NOT NULL UNIQUE,
  name_en text NOT NULL, name_ar text, category text NOT NULL,
  description_en text, description_ar text,
  risk_level text NOT NULL CHECK (risk_level IN ('LOW','MEDIUM','HIGH','CRITICAL')),
  is_overridable boolean NOT NULL DEFAULT false)
CREATE TABLE pos_role_permissions (
  role_id bigint NOT NULL REFERENCES pos_roles(id) ON DELETE CASCADE,
  permission_id bigint NOT NULL REFERENCES pos_permissions(id) ON DELETE RESTRICT,
  PRIMARY KEY (role_id, permission_id))
CREATE TABLE pos_staff_roles (                 -- §11 multiple roles
  staff_id bigint NOT NULL REFERENCES pos_staff(id) ON DELETE CASCADE,
  role_id  bigint NOT NULL REFERENCES pos_roles(id) ON DELETE RESTRICT,
  PRIMARY KEY (staff_id, role_id))
CREATE TABLE pos_staff_permission_overrides (  -- §105 effect ALLOW|DENY
  staff_id bigint NOT NULL REFERENCES pos_staff(id) ON DELETE CASCADE,
  permission_id bigint NOT NULL REFERENCES pos_permissions(id) ON DELETE RESTRICT,
  effect text NOT NULL CHECK (effect IN ('ALLOW','DENY')),
  granted_by bigint, granted_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (staff_id, permission_id))
CREATE TABLE pos_permission_limits (           -- §16, §18 numeric ceilings
  id bigserial PRIMARY KEY, restaurant_id bigint NOT NULL,
  subject_type text NOT NULL CHECK (subject_type IN ('role','staff')),
  subject_id bigint NOT NULL, limit_key text NOT NULL,
  limit_bp integer, limit_minor bigint,
  UNIQUE (restaurant_id, subject_type, subject_id, limit_key))
```

**Backfill, not cutover.** The migration reads every `pos_roles.capabilities` and
`pos_staff.capabilities` array and writes the junction rows. The `text[]` columns
**stay** for one release as a read fallback, so a till on an older binary against a
migrated database still works — the same discipline migration 5 already used.
A later migration drops them.

**`Authorization` grows to the §106 resolution:**

```
1. staff active?          2. terminal permits this staff?   3. gather roles
4. union role permissions 5. apply overrides (DENY wins)    6. apply limits
7. NeedsOverride if the capability is overridable and a limit was exceeded
```

`Allowed` gains an optional `limit` so a caller can say *"allowed, up to 10%"*
rather than asking twice. `PermissionDecision` gains `DeniedByLimit(limit, requested)`,
which is what turns a 30% discount request by a 10% cashier into a manager prompt
rather than a flat refusal.

**Risk levels (§107)** drive the override UX: `CRITICAL` is never overridable and
never merely disabled — it is hidden (§112).

**Settings permissions (§50)** replace the single `settings.manage` with the
sixteen `SETTINGS.*` keys. `settings.manage` becomes an umbrella retained via
`canonical` so no existing role is silently demoted.

**Role administration (§48):** a person may only grant a permission they hold.
Enforced in `RolesRepository.save`, not in the widget.

**Default matrix (§49)** ships as the seed for the four system roles plus six new
templates (shift manager, kitchen staff, inventory manager, accountant, delivery
staff, restaurant manager) — templates a restaurant edits, not rules the code holds.

---

**Built**, except §50. The sixteen `SETTINGS.*` keys are deliberately **deferred
to Wave D**, where the nine settings sections they gate actually exist. Adding
sixteen constants now would add sixteen permissions nothing checks — dead
capability keys in a catalogue whose whole value is that every key in it means
something. `settings.manage` stays the umbrella until then, which is what
`canonical` is for.

One thing worth recording about the ceilings. `pos_roles.max_discount_bp`
predates this wave and restaurants have set it, so `limitFor` reads **both** it
and `pos_permission_limits` and takes the tighter. Reading only the new table
would silently lift every ceiling already configured; reading only the old column
would make the new table decorative.

### Admin Mode — 12 September 2026, and three departures it made

The back office became **Admin Mode**: a session with a person, a start and an end,
entered by a hidden chord and a username + PIN, separate from whoever is signed in
at the till. It replaced a door that was a state the till drifted into —
Management opened for the till's operator once the `pos_admin` password was held,
and nothing ever forgot it, so after a manager had used it once, F8 at a locked till
opened the staff pane for anybody (`test/features/admin_entry_test.dart` was written
red against exactly that). What it departs from, all owner decisions:

1. **The administrator's database password is now kept on the machine.** It used
   to be typed at the door and never persisted. The owner chose a username and PIN
   and nothing else, which leaves no field to type it into, so the wizard writes it
   to `secrets.json` (`FileSecretStore.adminPasswordKey`) and Admin Mode loads it
   into memory only for a session. **The cost:** anybody with the till OS account's
   files has administrator rights to the branch database without a PIN. Installs
   from before this ask for it once, after a username and PIN have already got
   somebody in. `pos_migrate` still refuses to grant one role both credentials.
2. **`admin.enter`, critical, Owner only** (migration 44). The back office is no
   longer opened by `staff.manage`: managers who used it lose it until the owner
   gives the Manager role the key in Roles. Critical, so no manager PIN ever lends it.
3. **The chords moved.** Ctrl/Cmd+Shift+S opens Admin Mode (configurable per
   terminal, System › Terminal, from a fixed list that avoids the sale screen's
   F-keys); the forced reset moved to Ctrl/Cmd+Shift+R and now asks for a
   username + PIN holding `terminal.manage` rather than the database password;
   F8 is retired. The inactivity timeout is per terminal, 1–30 minutes, with no
   "never" — an Admin Mode that does not lock is a back office left open in a
   public room.

### Manager approval — Phase 2 of the same request

The till's approvals were checked on the screen and nowhere below it: every
till repository took `approvedBy: PosStaff?` and wrote whatever it was handed.

* **An approval is a single-use record now** (`Approval`, from
  `Authorization.approve`): the capability, the approver, and what it was for —
  an order, a ticket, a shift. `Authorization.authorize` is what a write asks:
  the person's own permission, or an approval for this capability and this
  thing, from somebody who may still give it, not yet spent. It is spent there.
* **Enforced in the writes**, PostgreSQL and fakes alike: refund, cash movement
  (a drawer opening asks `cash.open_without_sale`, not `cash.movement`), order
  void, shift close. A refusal there is a `PermissionRefused` exception rather
  than data — deliberately: every screen asks first, so reaching the repository
  without authority means something went round a screen.
* **Two acts need a second person whoever does them** (`approvalRequired`): a
  refund above the restaurant's threshold, and somebody else's drawer. The
  approver may not be the requester.
* **The approver's ceiling binds**, not no ceiling: discounts and price
  overrides retried after an approval used `limit: null`.
* **`payment.remove`** (migration 45) — taking a payment off an unsettled bill
  had no key and no check. Owner, manager and supervisor keep it; a cashier
  needs a supervisor's PIN. The ticket engine asks as well as the screen.
* **Audit rows** for the approvals that wrote none: a discount above the limit,
  somebody else's drawer, a refund above the threshold; a reprint's row now
  names its approver.

Found on the way, and fixed with it: a supervisor's refund above the threshold
was never shown to a second person (`requestPermission` answers "allowed" at
once for a holder); a cashier over their own price-override limit was retried
with no ceiling for the same reason; a supervisor's approval for a cashier's
pay-out was dropped before the write; and the shift repository let anybody
close anybody's drawer, which the close dialog had stopped allowing long ago.

Not done: the approver on a voided order is on the audit row and not on
`pos_orders` (no column); `LimitKey.refund` and `LimitKey.cashPayOut` are still
unread, as they were before; day close is unchanged.

---

## 6. Wave D — Settings & configuration surface

**Migration 14**

```
CREATE TABLE pos_settings (                 -- §85 scoped configuration
  id bigserial PRIMARY KEY, restaurant_id bigint NOT NULL,
  scope text NOT NULL CHECK (scope IN ('restaurant','branch','terminal','staff')),
  scope_id text, key text NOT NULL, value jsonb NOT NULL,
  created_by bigint, created_at timestamptz NOT NULL DEFAULT now(),
  updated_by bigint, updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (restaurant_id, scope, scope_id, key))
ALTER TABLE pos_restaurants ADD COLUMN legal_name text, commercial_registration text,
  phone text, email text, address text, city text, country text, logo_path text,
  currency text NOT NULL DEFAULT 'EGP', currency_symbol text, decimal_places smallint NOT NULL DEFAULT 2,
  rounding_rule text NOT NULL DEFAULT 'half_up', time_zone text NOT NULL DEFAULT 'Africa/Cairo',
  tax_mode text NOT NULL DEFAULT 'exclusive', default_locale text NOT NULL DEFAULT 'en',
  operation_mode text                       -- §7 QSR | FSR | cafe | takeaway | delivery | mixed
CREATE TABLE pos_order_types (              -- §31 configurable, not an enum
  id bigserial PRIMARY KEY, restaurant_id bigint NOT NULL, code text NOT NULL,
  name_en text NOT NULL, name_ar text, is_active boolean NOT NULL DEFAULT true,
  requires_customer boolean NOT NULL DEFAULT false, requires_table boolean NOT NULL DEFAULT false,
  requires_address boolean NOT NULL DEFAULT false, service_charge_id bigint,
  receipt_template_id bigint, price_list_id bigint, sort_order integer NOT NULL DEFAULT 0,
  UNIQUE (restaurant_id, code))
CREATE TABLE pos_taxes (                    -- §37
  id bigserial PRIMARY KEY, restaurant_id bigint NOT NULL, name_en text NOT NULL, name_ar text,
  rate_bp integer NOT NULL, is_inclusive boolean NOT NULL DEFAULT false,
  is_active boolean NOT NULL DEFAULT true, revision integer NOT NULL DEFAULT 1)
CREATE TABLE pos_tax_targets (tax_id, target_type CHECK IN ('category','order_type'), target_id)
CREATE TABLE pos_service_charges (          -- §38
  id bigserial PRIMARY KEY, restaurant_id bigint NOT NULL, name_en text NOT NULL, name_ar text,
  rate_bp integer, fixed_minor bigint, dine_in boolean, takeaway boolean, delivery boolean,
  is_taxable boolean NOT NULL DEFAULT true, is_automatic boolean NOT NULL DEFAULT true,
  is_optional boolean NOT NULL DEFAULT false, is_active boolean NOT NULL DEFAULT true)
CREATE TABLE pos_tender_types (             -- §40 payment methods as data
  id bigserial PRIMARY KEY, restaurant_id bigint NOT NULL, code text NOT NULL,
  name_en text NOT NULL, name_ar text, kind text NOT NULL,
  requires_reference boolean NOT NULL DEFAULT false, opens_drawer boolean NOT NULL DEFAULT false,
  counts_as_cash boolean NOT NULL DEFAULT false, refund_allowed boolean NOT NULL DEFAULT true,
  is_active boolean NOT NULL DEFAULT true, sort_order integer NOT NULL DEFAULT 0,
  UNIQUE (restaurant_id, code))
CREATE TABLE pos_receipt_templates (id, restaurant_id, name, config jsonb, is_default)
```

**Built so far in D:** payment methods (§40, migration 23), service charges
(§38, migration 24) — both with their editors in the Money pane — and order
types (§31, migration 25), data and engine wiring only.

**§31 departs from the shape above in three ways, all deliberate.**
`service_charge_id` and `price_list_id` were **not** built: both relationships
already exist pointing the other way — `pos_service_charges.order_types` and
`pos_product_prices.order_type` — and adding the reverse pointers would model
each twice with nothing keeping them in step. `receipt_template_id` waits for
receipt templates to exist.

The **codes remain an enum.** What the table configures is the four the product
ships with: their names, whether they are offered, and the three requires-flags.
Opening the set needs one more thing that is not built — every place that
renders an order type reads its name off the enum, so a fifth code would have
no name to show until the display path takes a config instead of a value. Saying
so is better than shipping a table that implies a freedom the UI does not have.

**§37 is built too** (migration 26), and departs from its sketch for the same
reason §31 did. `pos_taxes` was **not** created: `pos_tax_groups` already is
that table — named rates, per-product assignment, ETA codes, a default — and a
second would be a third tax model beside it and `pos_money_config`, with nothing
keeping the three in step. What §37 genuinely adds over what exists is two
things, and those are what migration 26 builds:

* **Tax-inclusive pricing**, as `pos_restaurants.tax_mode`. On the restaurant
  rather than on each tax group, because a restaurant is one or the other —
  per-tax inclusivity would let somebody price food inclusive and a levy
  exclusive, which is a receipt no customer can check.
* **A tax group on the category**, which a product with none falls back to.
  That is the useful half of `pos_tax_targets`; targeting an *order type* is
  left out because `pos_product_prices.order_type` already varies a price by
  channel, and a restaurant needing delivery taxed differently is describing a
  different price rather than a different rate.

`Money.taxWithinBp` is a separate method from `percentBp` rather than a flag on
it: the two are different arithmetic, and a caller that picked the wrong one
would be out by the square of the rate — small enough to survive a spot check,
large enough to matter over a month.

The **editor is deferred to the settings navigation (§51)**, not skipped. The
Money pane already holds three sections and a fourth would make it a junk
drawer; and §51 should be designed against the fifteen-area back office in
[16-back-office-scope.md](16-back-office-scope.md) rather than against today's
six panes. Order types
(§31) were **deliberately taken second**, not first: their most useful columns
point at a service charge, a receipt template and a price list, so building the
table first would have meant three columns pointing at nothing.

**`pos_money_config` is superseded but not dropped.** It keeps working as the cloud
cache; the offline authoring path moves to `pos_taxes` / `pos_service_charges`, and
the ticket engine reads a resolved `MoneyRules` object either way. **Historic orders
never re-price** — the tax snapshot on the order row is already the record.

**Payment methods stop being hardcoded.** **Built** (migration 23). The payment
screen reads `pos_tender_types`, Management authors them from the Money pane,
and the substring match on the label is gone.

One decision came out differently from the sketch above. `counts_as_cash` is
**snapshotted onto the payment row**, not read from the tender type at cash-up.
The drawer expectation is a fact about what happened, not about current
configuration: a restaurant deciding on Thursday that its wallet counts as cash
must not change what Monday's shift said the drawer should have held, because
the manager investigating Monday's variance needs the number Monday was judged
against. It also removes a hazard the sketch did not consider — `tender_type_id`
was assigned by a compiled-in Dart list, so on a branch server with two
restaurants those ids do not necessarily mean the same thing in both. A payment
that carries its own answer does not care, which is why there is deliberately no
foreign key from a payment to a tender type.

Naming follows the restaurant too: the built-in translations apply only while a
method still carries the name it shipped with. Renaming "Card" to "Visa" used to
leave the screen saying "Card" while the customer's receipt said "Visa".

**Setup wizard gains two steps** — *Restaurant Information* (§4.5, after account)
and *Operation Mode* (§4.7, after branch) — and the *Hardware* step expands
(§4.8). `SetupStep` is an ordered enum with a `visibleSteps` getter; adding steps
is additive, and the wizard's own rule (one linear path, no forks) holds.

**Settings navigation (§51)** is the nine-section shell. Management's six panes
move into it: Staff → People, Menu → Menu, Floor → Restaurant, Money → Restaurant,
Roles → People, Activity → System.

**POS behaviour (§53) and receipt settings (§54)** are `pos_settings` keys with
typed accessors — a `PosBehaviour` value object read once per screen, not a map
looked up ad hoc.

**Order number reset (§53)** makes `_nextInvoiceNumber`'s `period` configurable:
`never | daily | monthly | yearly`, defaulting to the current `yearly`.

---

## 7. Wave E — Floors & tables

**Migration 15**

```
CREATE TABLE pos_floors (
  id bigserial PRIMARY KEY, restaurant_id bigint NOT NULL, branch_id bigint NOT NULL,
  name_en text NOT NULL, name_ar text, sort_order integer NOT NULL DEFAULT 0,
  is_active boolean NOT NULL DEFAULT true)
ALTER TABLE pos_dining_tables ADD COLUMN floor_id bigint REFERENCES pos_floors(id),
  shape text NOT NULL DEFAULT 'rect' CHECK (shape IN ('rect','round','square')),
  width smallint, height smallint, pos_x smallint, pos_y smallint,
  status text NOT NULL DEFAULT 'available'
    CHECK (status IN ('available','occupied','reserved','bill_requested','needs_cleaning')),
  reserved_for text, reserved_at timestamptz
```

Backfill `pos_floors` from the distinct `area_name` values so no restaurant loses
its areas; keep `area_name` for one release as a read fallback.

`TableState` grows from three members to five. Capabilities: `table.view` ·
`table.open` · `table.change` · `table.transfer` · `table.merge` · `table.reserve` ·
`table.release` · `table.edit_layout`. Order transfer/merge and split-bill
(equal · item · seat · custom, §42) land here because they are table operations
before they are payment ones.

---

## 8. Wave F — Kitchen, printing, hardware

**Migration 16**

```
CREATE TABLE pos_kitchen_stations (id, restaurant_id, branch_id, name_en, name_ar, sort_order, is_active)
CREATE TABLE pos_printers (
  id bigserial PRIMARY KEY, restaurant_id bigint NOT NULL, branch_id bigint NOT NULL,
  name text NOT NULL, role text NOT NULL CHECK (role IN ('receipt','kitchen','bar','label','report')),
  connection text NOT NULL CHECK (connection IN ('network','usb','serial')),
  host text, port integer, usb_identifier text,
  paper_width_mm smallint NOT NULL DEFAULT 80, chars_per_line smallint NOT NULL DEFAULT 48,
  auto_cut boolean NOT NULL DEFAULT true, opens_drawer boolean NOT NULL DEFAULT false,
  terminal_id uuid, is_active boolean NOT NULL DEFAULT true)
CREATE TABLE pos_printer_routes (            -- §79, one item may route to several
  id bigserial PRIMARY KEY, restaurant_id bigint NOT NULL,
  station_id bigint REFERENCES pos_kitchen_stations(id),
  printer_id bigint REFERENCES pos_printers(id), target text CHECK (target IN ('printer','kds','both')))
CREATE TABLE pos_kitchen_tickets (
  id bigserial PRIMARY KEY, order_id bigint NOT NULL REFERENCES pos_orders(id),
  station_id bigint, round_number integer NOT NULL,
  state text NOT NULL DEFAULT 'new' CHECK (state IN ('new','accepted','preparing','ready','served','cancelled')),
  printed_at timestamptz, print_failed_at timestamptz, print_error text,
  reprint_count integer NOT NULL DEFAULT 0, is_void_ticket boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now())
CREATE TABLE pos_kitchen_ticket_lines (ticket_id, order_line_id, quantity, name_snapshot, modifier_summary, note)
ALTER TABLE pos_products   ADD COLUMN station_id bigint, prep_minutes smallint, course smallint,
  dine_in_allowed boolean DEFAULT true, takeaway_allowed boolean DEFAULT true, delivery_allowed boolean DEFAULT true,
  description_en text, description_ar text, image_path text, cost_price_minor bigint,
  tax_id bigint, is_open_price boolean NOT NULL DEFAULT false
ALTER TABLE pos_categories ADD COLUMN colour text, image_path text, station_id bigint
ALTER TABLE pos_modifier_groups ADD COLUMN min_select smallint NOT NULL DEFAULT 0, allow_multiple_qty boolean NOT NULL DEFAULT false
ALTER TABLE pos_modifiers  ADD COLUMN kitchen_name text
```

**Print failure (§80) is the rule that matters:** a failed kitchen print is
recorded as failed and surfaced with Retry / Choose printer / Mark handled, gated
by permission. **Never silently marked successful** — this belongs in the
repository, not the widget, so the record exists even if the dialog is dismissed.

Reprint (§46) stamps `REPRINT` on the ticket, increments `reprint_count`, and
writes `kitchen_ticket.reprinted` to the audit ledger.

USB transports (§78) need one platform channel per OS; scope them as a separate
sub-task with a `HardwarePorts` implementation swapped by platform, so the network
implementation stays the default and testable path.

Combos (§36) are a schema addition here too: `pos_combos`, `pos_combo_groups`,
`pos_combo_choices`, with a combo expanding into ordinary order lines at ring-up
so every downstream consumer — kitchen, inventory, reports — sees real items.

---

## 9. Wave G — Reports, X/Z, export & import

No new tables; **read models** over the ledger, built as SQL in a
`ReportsRepository` with one method per report and a shared
`ReportFilter(businessDay|dateRange, branch, terminal, staff, orderType)`.

| Family (§59) | Reports |
|---|---|
| Sales | daily · by hour · by order type · by product · by category · by employee · by terminal |
| Payments | summary · cash · card · other |
| Cash | drawer · pay-in · pay-out · variance |
| Operations | discounts · voids · refunds · deleted items · open orders |
| Staff | sales · discounts · voids · refunds per employee |
| Inventory | deferred to Wave L |

**X report (§61)** is `ShiftSummary` computed without closing — the code already
exists inside `CloseShiftDialog`; extract it so both callers share one function.
**Z report** becomes reachable standalone as well as at cash-up.

Permissions: the eleven `REPORT.*` keys, plus `report.x` / `report.z`.
Export (§95) as CSV and XLSX from the same rows the screen renders, PDF for
report layouts; **export is permission-gated** because it carries the business out
of the building. Import (§96) is products/categories/prices/inventory with a
three-stage flow — parse → preview with per-row validation → commit in one
transaction. A partially-applied import is not an outcome the code may produce.

---

## 10. Wave H — Customers

**Migration 17**

```
CREATE TABLE pos_customers (
  id bigserial PRIMARY KEY, restaurant_id bigint NOT NULL,
  name text NOT NULL, phone text, alt_phone text, email text,
  tax_number text, notes text, is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(), created_by bigint)
CREATE UNIQUE INDEX pos_customers_phone_unique ON pos_customers (restaurant_id, phone) WHERE phone IS NOT NULL
CREATE TABLE pos_customer_addresses (
  id bigserial PRIMARY KEY, customer_id bigint NOT NULL REFERENCES pos_customers(id) ON DELETE CASCADE,
  area text, street text, building text, floor text, apartment text, landmark text,
  is_default boolean NOT NULL DEFAULT false)
ALTER TABLE pos_orders ADD COLUMN customer_id bigint REFERENCES pos_customers(id),
  delivery_address_id bigint REFERENCES pos_customer_addresses(id),
  customer_name_snapshot text, customer_phone_snapshot text
```

Snapshots on the order for the same reason product names are snapshotted: a
renamed customer must not rewrite an old delivery ticket.

Capabilities: `customer.view` · `customer.create` · `customer.edit` ·
`customer.delete` · `customer.view_history`. Order types with
`requires_customer`/`requires_address` block settlement until satisfied —
enforced in `TicketEngine`, so it is testable without a widget.

---

## 11. Wave I — Authentication & security hardening

**Migration 18**

```
ALTER TABLE pos_staff ADD COLUMN first_name text, last_name text, display_name text,
  phone text, email text, badge_id text, job_title text, hire_date date,
  password_hash text, password_salt text, password_changed_at timestamptz,
  failed_login_count integer NOT NULL DEFAULT 0, locked_until timestamptz,
  last_login_at timestamptz
CREATE UNIQUE INDEX pos_staff_badge_unique ON pos_staff (restaurant_id, badge_id) WHERE badge_id IS NOT NULL
```

* **Username + password (§7)** for owner/administrator/accountant, hashed with the
  same PBKDF2 parameters as PINs — or Argon2id if a maintained Dart binding is
  acceptable; the SRS says "or equivalent" and PBKDF2-HMAC-SHA256 ×120,000 already
  qualifies. **Decide once, record the decision, do not mix.**
* **Auto-lock (§53, §82)**: an idle timer at the shell, configurable
  `never | 1 | 2 | 5 | custom` minutes, routing to the existing lock screen. The
  shift stays open — that rule already exists and must not change.
* **Failed attempts and lockout (§82)**: counter and `locked_until` on the staff
  row, checked before PIN verification, cleared on success. Audit
  `auth.failed_login` and `auth.locked_out`.
* **Dedicated sign-in screen** (the outstanding `POS-BE-024`), replacing
  "`SessionRepository.current()` returns the first active member of staff".
* **Audit:** `auth.login` · `auth.logout` · `auth.failed_login` · `auth.locked_out`.
* **Reauthentication for sensitive settings (§84)** becomes a reusable
  `RequireReauth` wrapper rather than the Management screen's bespoke gate.
* **PIN policy (§82)**: min/max length as settings inside the existing 4–12 bounds.

---

## 12. Wave J — Backup, restore, diagnostics, logs, updates

**Migration 19**

```
CREATE TABLE pos_backup_records (
  id bigserial PRIMARY KEY, restaurant_id bigint NOT NULL,
  kind text NOT NULL CHECK (kind IN ('scheduled','manual','pre_restore','pre_update')),
  destination text NOT NULL, path text NOT NULL, size_bytes bigint,
  encrypted boolean NOT NULL DEFAULT true, checksum text,
  started_at timestamptz NOT NULL, finished_at timestamptz, error text,
  created_by bigint)
```

* **Backup (§72–74)**: `pg_dump` driven by a scheduler, frequency and retention as
  settings (7 daily / 4 weekly / 6 monthly default), destinations local folder ·
  external volume · network share. Encrypted at rest. **Backup must never require
  the cloud.**
* **Restore (§75)**: administrator credential + explicit confirmation + backup
  validation + **a pre-restore backup taken first**, then an audit event. Gated on
  `system.restore`, which is `CRITICAL` and therefore never overridable.
* **Diagnostics (§76)**: one screen showing app/backend/db version, db size, server
  IP/port/uptime, connected terminals, printer status, last backup, licence status,
  disk space, local API status — with Test Database · Test Printer · Test Network ·
  Export Logs · Restart Service.
* **System logs (§77)**: a rotating file log separate from the audit ledger, with a
  redaction rule that passwords, PINs and payment references never reach it.
* **Offline updates (§99, §100)**: validate package → check version → dry-run
  migration → back up → apply → migrate → verify health. The migrator already
  satisfies §100; this wraps it.
* **§110**: `created_by` / `updated_by` columns land on every configuration table
  in this wave, backfilled null.

---

## 13. Wave K — The local API tier (the §71 decision)

Only if Option B is chosen. Shape:

```
POS terminal  →  http(s)://branch:PORT  →  business logic  →  PostgreSQL
                 ws://branch:PORT       →  config & availability push
```

* Reuse `apps/api` (already deployed on the branch box for heartbeat, licence and
  provisioning) rather than writing a second service.
* Endpoints per §65: health · auth · POS · menu · order · kitchen · payment ·
  settings. Every one re-checks the capability server-side (§116).
* **Terminal registration (§6)**: request → admin approve/reject screen → credential
  issued → stored in the OS keystore (the `DeviceTokenVault` already does this).
* **Terminal fields (§5)**: type, device identifier, IP, enabled, printer bindings,
  default order type, default floor, auto-login, require-staff-login, last seen,
  app version — most only observable server-side, which is the argument for this wave.
* **Config propagation (§86, §87)**: WebSocket push for availability and settings;
  the till applies without restart.
* **Connection status (§66–68)**: the sync pill becomes a three-state
  `Connected · Connecting · Server unreachable`, distinct from internet.
* Migration 20 carries the terminal columns and a `pos_terminal_credentials` table.
* The repository swap is `lib/app/providers.dart` only — that is the whole point of
  the current layering, and it is worth protecting in every earlier wave.

---

## 14. Wave L — Inventory (P1)

`pos_units` · `pos_stock_locations` · `pos_inventory_items` ·
`pos_inventory_transactions` · `pos_recipes` · `pos_recipe_lines`, the ten
`INVENTORY.*` capabilities (with `inventory.view_cost` genuinely separate, §55),
adjustment reasons from `pos_reason_codes`, and the §57 deduction-policy setting
(`on_send | on_paid`, default `on_paid`) with explicit void/refund behaviour.
Everything here is P1; it is listed so the schema above does not have to be
reshaped when it arrives.

---

## 15. Cross-cutting workstreams

Run alongside the waves, not after them.

| Workstream | Content |
|---|---|
| **Permission UX (§111, §112)** | Three behaviours — hidden · disabled · manager-approval — chosen by risk level, applied consistently. A `PermissionGate` widget that takes a capability and a `PermissionDecision` and renders the right one, so no screen invents its own. |
| **Localization** | Management and every new screen in AR + EN. `admin_messages.dart` folds into `AppStrings` in one pass. Per-surface language (§94): admin · POS · receipt · kitchen ticket. |
| **Arabic receipts** | ESC/POS code page 864/1256 selection per printer model, configured on the printer row, with a fallback that emits nothing rather than mojibake — the current behaviour, kept. |
| **Fonts** | Ship `.ttf`/`.otf` for Archivo, IBM Plex Mono and Tajawal into `assets/fonts/`. Closes the known fidelity gap and is a prerequisite for design sign-off. |
| **Test strategy** | Every wave: pure engine tests with no DB · repository tests against a real PostgreSQL that self-skip without `POS_PG_HOST` · one end-to-end path in `integration_test/`. The suite-per-database rule stays. |
| **Performance (§101)** | Add a benchmark harness asserting the five targets (add item <200 ms, open order <500 ms, send round <1 s, checkout <1 s, search <300 ms) against a seeded 500-product catalogue. Currently unmeasured. |

---

## 16. Sequencing — revised 8 September 2026

> **Superseded on 13 September 2026 for Wave N.** E-receipts are not needed
> for the restaurants being sold to now, so filing is switched off
> (`etaFilingEnabled`, see `14-progress.md`) and the two unbuilt pieces — the
> e-seal and the submission client — are parked, not next. What Wave N built
> stays in the tree, dormant. The rest of this section is kept as written.

Waves A and B are shipped. The order below changes from the original for one
reason, set out in [15-competitive-position.md](15-competitive-position.md):
**Egypt's ETA e-receipt mandate has been in force since 15 September 2025**, and
a restaurant on the ETA list cannot legally run its tills on this build.

Wave C makes the product better. ETA makes it sellable.

```
DONE ──► A (discount/void/refund)  ──► B (cash & day, + settings infra)
                                        │
                                        ▼
                          ┌─────────────────────────────┐
                          │  M — menu & tax model       │  ← NEW, first
                          │  N — ETA e-receipt          │  ← NEW, blocking
                          └─────────────────────────────┘
                                        │
                                        ├─► C (permissions to spec)
                                        │      ├─► D (settings screens)
                                        │      │     ├─► E (floors/tables)
                                        │      │     ├─► F (kitchen/printing)
                                        │      │     └─► G (reports/export)
                                        │      ├─► H (customers)
                                        │      ├─► I (auth hardening)
                                        │      └─► J (backup/diagnostics)
                                        └─► K (local API tier)   ← decision §0
                                               └─► L (inventory, P1)
```

### Wave M — menu and tax model · migration 16 · **L**

First, because everything else depends on the shape of a line.

1. **`tax_lines[]`** on the ticket, the order and the receipt — the mitigation
   R-8 promised and nobody built. It cannot be retrofitted onto orders already
   filed with ETA, so it lands before anything is filed.
2. **Per-product tax treatment.** One VAT rate for a whole ticket cannot express
   a zero-rated or exempt line, and a restaurant selling food *and* packaged
   goods has both. This is why the tax model and the menu model are one wave and
   not two.
3. **Combos.** A meal deal at one price. Ubiquitous in Egyptian QSR and
   unpriceable today.
4. **Per-branch and per-channel price and availability.** Delivery prices differ
   from dine-in almost universally.
5. **Free and default modifier options**, and a minimum selection per group.
6. **Menu import from CSV or Excel.** Not in the original list; added because a
   restaurant arrives with four hundred items already in a spreadsheet, and
   typing them into a till one dialog at a time is the reason a pilot stalls.

**Built.** On the import specifically, three rules are load-bearing and worth
recording because they are what make the feature safe to hand to an operator:

* **Nothing is ever deleted.** An item missing from the file is one the
  restaurant did not mention, not one it wants gone.
* **One bad row blocks the whole file.** Half a menu is worse than none, because
  nobody can tell which half landed. The repository re-checks this rather than
  trusting the screen.
* **Preview before apply, naming each price change.** "Changes 40 items" is not
  a sentence anybody can approve.

The parsing (`MenuImport`) is pure and knows nothing about files or the
database; `SpreadsheetReader` is the only place that knows about formats.
Matching is SKU first, then name — the fallback matters more than it looks,
because the first file a restaurant sends is usually its own menu with SKUs
newly added, and matching on SKU alone would duplicate all four hundred rows.
A name already held under a *different* SKU is refused rather than guessed.

### Wave N — ETA e-receipt · migration 17 · **L**

Blocking. Needs Wave M's `tax_lines[]` underneath it.

1. **E-seal (X.509) storage and per-receipt signing.** The secret store and the
   keychain work already exist to build on.
2. **ETA structured-format submission**, over authenticated HTTPS.
3. **A submission queue with its own retry and its own idempotency.** The outbox
   is the right shape; this is a second destination beside the platform, not a
   reuse of it.
4. **The QR code on the printed slip.** `ReceiptPaper` is already the one place
   both the live receipt and the reprint pass through.
5. **A submission state on the order, and a screen showing what has not
   cleared.** "Which receipts has ETA not accepted" becomes a daily question,
   and a queue growing where nobody looks is a failure mode this codebase has
   already been bitten by once.

**Built:** the receipt profile (2), the document with its canonical
serialization and uuid, the queue with its chain and deadline (3), settlement
wiring, the QR square (4), the screen (5), and the signing seam. **Not built:**
the seal itself and the submission client — the two that need a token and a
sandbox account rather than a decision.

The chosen binding for the seal is **ETA's own integration toolkit**, run as a
local service beside the branch server. It is their tooling, so the CAdES-BES
structure and the QR payload are guaranteed right rather than reverse-engineered
— and the QR in particular is generated by the toolkit, not by this app, which
is why `pos_eta_receipts.qr_payload` is a column the slip reads and never one
this process computes. A square this app invented would scan to nothing.

Three findings from the SDK worth recording, because each one changes a design:

* **The private key cannot live in this process.** Egypt issues an e-seal as an
  X.509 certificate on a hardware token or HSM, not exportable — which is the
  point of it. Signing is therefore an interface, and the deployment binds ETA's
  own integration toolkit (a local REST service they publish), a signing service
  on the branch server holding the token, or a service provider signing under
  `signatureType` `S`. **This is an open commercial question, not a code one.**
* **Receipts are chained per device.** Each names the uuid of the one before it
  from the same POS serial, so a gap is visible to the authority. That makes
  enqueuing a locked read-modify-write rather than an append, and makes the
  device serial part of the identity rather than decoration.
* **The uuid is a fingerprint, not an identifier.** It is SHA-256 of the
  canonical document without its own uuid in it, so the same sale resubmitted is
  recognisably the same document rather than a second one. Idempotency comes
  free; a random id would have had to buy it.

**The architecture is already right for this.** ETA permits store-and-forward
within 24 hours — it does not require real-time clearance the way Saudi ZATCA
Phase 2 does for B2B. A till that sells through an outage and submits when the
line returns is compliant. What is missing is a destination and a signature.

### Then Wave C, unchanged in content

With one decision to take deliberately rather than by default: **Management is
gated on a PostgreSQL password rather than a permission.** That is stronger than
the market's model and it does not scale to a restaurant group, because sharing
one Postgres password among branch managers is the failure mode it exists to
prevent. Wave C either keeps it and accepts an owner-only back office, or moves
to role-based access and leans on the column-scoped grants that are already
doing most of the work.

~~Wave C also carries the **branch scoping** that `pos_staff.branch_id` has
always had a column for and never enforced.~~ **This was already done.** Both
`signIn` and `verifyPin` filter on `(s.branch_id IS NULL OR s.branch_id =
@branch)`, and `postgres_directory_test.dart` pins it — *"a cashier at another
branch cannot unlock this till"*. The claim above was stale; nothing was
built for it in Wave C.

**Two departures from the shape above, both deliberate.**

`pos_permissions` and `pos_role_permissions` were **not** built. The catalogue
lives in Dart because the code checks against string constants, so a table would
be a seeded *copy* of it and a foreign key onto a copy buys integrity against the
wrong thing — while making every new capability need a Dart change *and* a seed
row, with a till on an older binary holding a row it cannot interpret. Role
capabilities stay in `pos_roles.capabilities text[]`, which three migrations
already rely on and which `PosCapability.canonical` already makes rename-safe.

`pos_staff_roles` holds the **additional** roles, not all of them. The plan's
backfill was tried and reverted: it needs both places written on every role
change forever, and when somebody's primary role changes the backfilled row
stays, silently leaving them holding the role they were moved off. A promotion
that quietly keeps the old permissions is the exact failure this wave exists to
prevent.

### The ordering above assumes a till, not a back office

**Read [16-back-office-scope.md](16-back-office-scope.md) before planning past
Wave D.** Scored against what an offline-first business expects from a back
office, this product is five areas done, three partial and seven absent — and
the seven absent ones are one chain (purchases → cost price → inventory → COGS →
profit → accounting) whose head, purchasing, appears on no wave here at all.

The sequencing below was written for "a till that can trade legally in Egypt",
which Waves A, B, M, N and C delivered. It is the wrong sequencing for "an
offline back office". §4 of that page proposes the alternative.

### What is still not on the roadmap

Payment terminals, delivery aggregators and product images are table stakes in
this market and appear in no wave. They are named in
[15-competitive-position.md](15-competitive-position.md) §4 rather than
scheduled here, because each is a commercial decision — a payment integration is
a contract before it is code.

**§113 P0 is complete at the end of Wave G.** Legal sale in Egypt is complete at
the end of Wave N, which is sooner and matters more.

---

## 17. Risks worth naming now

0. **E-invoicing is no longer a risk, it is a deadline.** R-8 in
   `01-existing-system-analysis.md` was rated *Medium* and *out of scope for
   v1*; Egypt's ETA mandate took effect 15 September 2025. It now heads this
   list, and Waves M and N exist to answer it. The mitigation that entry
   promised — a `tax_lines[]` breakdown "from day one" — was never built, which
   is the part worth remembering: a recorded mitigation is not a shipped one.

1. **The VAT base changes in Wave A.** Adding discounts moves the tax base from
   `subtotal + service` to `subtotal − discount + service`. Every historic order is
   safe (totals are snapshotted), but the golden tests must land *before* the
   feature, not with it.
2. **Wave C's backfill touches every role and every staff row.** It must be
   idempotent, additive, and leave the `text[]` columns readable for one release —
   migration 5 is the precedent and it should be copied closely.
3. **Payment methods becoming data breaks the cash-detection string match.** The
   `wireLabel == 'Cash'` heuristic behind `ShiftSummary.cashTaken` must be replaced
   by `counts_as_cash` in the *same* change, or every Arabic till reports a false
   variance — the exact failure the current comment warns about.
4. **Wave D's settings model can sprawl.** Typed accessors over `pos_settings`,
   one value object per screen. A raw map read at forty call sites is how a
   settings table becomes unmaintainable.
5. **Cloud vs offline authorship.** The Menu and Money panes are offline-only
   because the bootstrap seeder overwrites the local catalogue. Every new
   administration screen must declare which mode authors it, or a cloud till will
   silently lose whatever was typed into it.
