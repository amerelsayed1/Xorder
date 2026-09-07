# Wave A progress — where the gap-closure plan stands

**As of 8 September 2026.** Companion to [11-gap-closure-plan.md](11-gap-closure-plan.md),
which is the plan; this is the state of it. When the two disagree, this file is
newer.

---

## 1. The short version

**Wave A is complete.** All eight items are built, and one migration nobody
planned for turned up along the way.

| | Item | State |
|---|---|---|
| A.1 | Order lifecycle, void provenance, reason codes | ✅ migration 9 |
| A.2 | Discounts | ✅ migration 10 |
| A.3 | Void & cancel — line and order | ✅ |
| A.4 | Order history · `served_by` | ✅ migration 11 |
| A.4b | Price override | ✅ no migration needed |
| A.5 | Refunds | ✅ migration 12 |
| A.7 | Receipt reprint | ✅ |
| A.8 | Cart density modes · line note | ✅ |
| A.9 | Owner role backfill | ✅ migration 13 |

**Verification:** `flutter analyze` clean · **799 unit tests** pass, 13 skipped
(the database suites, which self-skip without `POS_PG_HOST`) · **302 database
tests** pass against PostgreSQL, with **no failures left** — the two
long-standing ones are fixed and explained below.

---

## 2. The two that were sitting there

Both surfaced from running the whole `test/data` suite rather than the files a
change touched.

**`postgres_permissions_test` was a real bug, not a stale fixture.** The seeded
owner role held 16 capabilities; the code says it holds all 19. `SystemRoles.owner`
is `PosCapability.all` and `RolesRepository.save` enforces it, but a role seeded
*before* Wave A added its three keys kept an owner who could not grant them —
the exact failure the invariant exists to prevent: a restaurant where nobody can
grant a capability nobody holds. **Migration 13** backfills it, additively, owner
only.

**`postgres_wiring_test` was a stale assertion.** It expected a bare
`PostgresOrdersRepository` on a cloud terminal, which was asserting the *absence*
of the sync wrapper a cloud terminal is supposed to have. It now asserts
`SyncingOrdersRepository`, which is the binding, with a note on why the write is
identical either way.

---

## 3. What is left, in order

Nothing in Wave A. The next decision is where to start Wave B.

| Wave | Theme | Migration | Size |
|---|---|---|---|
| **B** | Cash drawer · pay in/out · business day | 14 | L |
| **C** | Permission model to specification | 15 | L |
| **D** | Settings & configuration screens | 16 | XL |
| **E** | Floors & tables | 17 | M |
| **F** | Kitchen, printing, hardware | 18 | L |
| **G** | Reports · X/Z · export/import | — | L |
| **H** | Customers | 19 | M |
| **I** | Auth & security hardening | 20 | M |
| **J** | Backup · restore · diagnostics | 21 | L |
| **K** | Local API tier | 22 | XXL |
| **L** | Inventory & recipes (P1) | 23 | XL |

Migration numbers have each shifted by two from the original plan: 11 became
`who sold it`, and 13 became the owner backfill. Neither was anticipated.

**§113 P0 is complete at the end of Wave G** — everything the SRS calls
mandatory for v1, except §71's API tier, which is Wave K.

### Three things to carry into Wave B

1. **Ship Wave D's settings *infrastructure* early, inside Wave B.** Scoped
   `pos_settings` plus the Settings shell. B, F and G all want it, and two
   things are already written to read from it the day it exists:
   `RefundPolicy` and the cart's per-terminal density default.
2. **Wave B carries a trap.** Making payment methods data breaks the
   `wireLabel == 'Cash'` string match behind `ShiftSummary.cashTaken`. It must
   be replaced by a `counts_as_cash` column in the *same* change, or every
   Arabic till reports a false variance on every cash-up. The note now lives on
   `TenderMethod.wireLabel`, where somebody changing it will read it.
3. **`BlindCountDialog` (pattern 7) is blocked** on the `cash.variance.view`
   naming decision — §4.2 of [13-pattern-handoff-review.md](13-pattern-handoff-review.md).
   It is Wave B work, so this is the moment to settle it.

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
