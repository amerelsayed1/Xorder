# Backend — POS Gap Analysis

**Author:** Agent 2 (Backend) · **Mode:** ANALYSIS-ONLY
**Inputs:** `01-existing-system-analysis.md`; Agent 1's `POS_TO_BACKEND.md` (POS-BE-001 … POS-BE-014, all `PROPOSED`)
**Date:** 2026-08-26

> **No backend code has been modified.**

---

## 1. Master gap table

Read "Exists" as *is the concept present in `apps/api` today*, and "Reusable" as
*can the POS use it as-is, or is it a pattern the new work should follow*.

| Capability | Exists | Reusable | Modification Needed | New API Needed | Priority | Req |
|---|---|---|---|---|---|---|
| Login / session | ✅ | ✅ full | No | No | — | — |
| Username-only cashier login | ✅ | ✅ full | No | No | — | — |
| Token lifetime for offline till | ⚠️ partial | — | **Decision** | Maybe | HIGH | 011 |
| Permission machinery | ✅ | ✅ full | No | No | — | — |
| POS permission vocabulary | ❌ | pattern | **Enum cases** | No | HIGH | 002 |
| Feature entitlement (`feature:pos`) | ✅ machinery | pattern | **Enum case + plan wiring** | No | MEDIUM | 001 |
| Branch selection (list) | ✅ | ✅ | No | No | — | — |
| Branch `code` + `supported_order_types` | ✅ columns | ✅ | **Resource only** | No | HIGH | 005 |
| Per-user branch scoping | ❌ | — | **Decision** | Maybe | MEDIUM | — |
| POS device / terminal registry | ❌ | pattern | New table | **Yes** | HIGH | 009 |
| Catalog read (items/categories/groups) | ✅ | ✅ | No | No | — | — |
| Auto-applied option groups on dashboard read | ⚠️ partial | ✅ logic | **Resource + query flag** | No | HIGH | 003 |
| Product lookup by id | ✅ | ✅ | No | No | — | — |
| Barcode / SKU lookup | ❌ | — | **Columns + index** | No | MEDIUM | 004 |
| Server-side pricing logic | ✅ | ✅ full | No | No | — | — |
| Server-side pricing **on the order path** | ❌ | — | **`order_items.menu_item_id`** | **Yes** | HIGH | 006 |
| Tax rules | ❌ | — | New tables | **Yes** | HIGH | 013 |
| Additional charges (service charge) | ❌ | — | New tables | **Yes** | HIGH | 013 |
| Discounts (line + order) | ❌ | — | New columns | **Yes** | HIGH | 006 |
| Tender types | ❌ | — | New table | **Yes** | HIGH | 013 |
| Customers (read) | ✅ | ✅ | No | No | — | — |
| Customer creation from till | ⚠️ public only | ✅ `upsert()` | **New verb** | **Yes** | LOW | 014 |
| Order creation (authenticated) | ❌ | ✅ patterns | Extend `orders` | **Yes** | HIGH | 006 |
| Offline order submission (backdated, bulk) | ❌ | — | `created_at` from client | **Yes** | HIGH | 006 |
| Payments / split payments | ❌ | — | New table | **Yes** | HIGH | 006 |
| Refunds / voids | ❌ | — | New table + status | **Yes** | MEDIUM | 010 |
| Inventory / stock movement | ❌ | — | *Out of scope* | No | — | — |
| Shift management | ❌ | pattern | New table | **Yes** | HIGH | 009 |
| Cash movements | ❌ | pattern | New table | **Yes** | HIGH | 009 |
| Invoice numbering | ❌ | — | New table + service | **Yes** | HIGH | 008 |
| Idempotency | ❌ | — | Column + unique index | **Yes** | HIGH | 007 |
| Money precision (minor units) | ❌ | — | **Decision** | — | HIGH | 007 |
| Incremental catalog sync | ❌ | ✅ `SoftDeletes` | Query param | No | LOW | 012 |
| Audit logs | ✅ | ✅ full | No | No | — | — |

**Score: 12 reusable as-is · 5 need only exposure or vocabulary · 13 genuinely new · 3 owner decisions.**

The encouraging read: *every* piece of hard infrastructure — tenancy, RBAC,
auditing, entitlement, pricing rules, the order graph — already exists and is
good. What is missing is the money layer, and it is missing cleanly rather than
half-built. There is nothing to unpick.

---

## 2. Review of each Agent 1 request

For every request: what already exists, whether an existing API can safely serve
it, backward-compatibility impact, database impact, tenant/branch implications,
and my recommendation. **None of this is implemented.**

### POS-BE-001 — `Feature::POS` entitlement · **ACCEPT as requested**

Existing: `Feature` enum, `restaurant_features`, `PlanEntitlementService`,
`EnsureFeatureEnabled`, `PlanLimitService::staffLimitReached()` as the precedent.
Reuse: complete — one enum case, one middleware key, one optional plan column.
Compat: additive; `Feature::resolve()` defaults unknown/missing keys to `false`,
so every existing tenant is POS-off until the Super Admin opts them in. Zero risk.
DB: optional `plans.max_terminals`.
**Recommendation:** add `case POS = 'pos';` with `requires() => []`. Do **not** add
it to `defaultSet()`. Add `max_terminals` only if terminals are metered commercially.

### POS-BE-002 — POS tenant capabilities · **ACCEPT with a naming correction**

Existing: the whole RBAC. Agent 1 is right that only vocabulary is needed.

Agent 1 flagged the real defect themselves: `implies()` derives the view
capability from `resource()`, which is `strtok($value, '.')`. For
`pos.shift.close` that yields `pos`, so `implies()` would look for a
non-existent `pos.view`, and `expand()` would silently drop nothing but would
also grant nothing — a checkbox that governs less than it appears to.

**Decision (Agent 2's call, as invited): flatten to a single dot.** Final strings:

```
pos.operate          pos.discount         pos.price_override
pos.void             pos.refund           pos.shift_open
pos.shift_close      pos.cash_movement    pos.reprint
```

Rationale: `resource()` returns `pos` for all nine, `action()` returns the verb,
and `implies()` resolves to `pos.view` — which does **not** exist, so `implies()`
must return `null`. That requires either adding a `pos.view` case or special-casing
`pos` in `implies()`. **Cleanest is to treat `pos.operate` as the view-equivalent**
and make `implies()` map the `pos` resource to `pos.operate` rather than `pos.view`.
That is a three-line change to an existing method and keeps one meaning per string.

Compat: additive. Existing roles have none of these, so **every existing staff
account is POS-locked until a role grants them**, and the owner is unaffected
(implicit bypass). `group()` gains a `'pos'` key.
DB: none — `roles.capabilities` is JSON.
**Recommendation:** ACCEPT. Answer to Agent 1: the nine strings above are final.

### POS-BE-003 — Auto-applied option groups on `/dashboard/items` · **ACCEPT**

Existing: `MenuItem::orderedOptionGroups()` already merges and de-duplicates;
`withAutoOptionGroups()` already exists and is N+1-free (one restaurant-level query).
Reuse: total — the logic is written, it is simply never invoked on this path.
Compat: **must be opt-in.** Injecting auto groups unconditionally enlarges the
existing dashboard items payload for every current caller, including the item list
screen that does not need it. Agent 1's own suggestion of `?with=option_groups`
is right.
DB: none.
**Recommendation:** ACCEPT as `GET /api/dashboard/items?resolve=full`. This is a
genuine correctness bug in the *existing* product too — the dashboard shows a
different menu than the diner's phone — so it has value beyond the POS.

### POS-BE-004 — `sku` + `barcode` · **ACCEPT with a uniqueness caveat**

Existing: nothing. Confirmed by grep.
Compat: additive nullable columns.
DB: two `string` columns on `menu_items` + a unique index.

**Caveat Agent 1 could not have known:** `menu_items` uses `SoftDeletes`. A plain
`unique(restaurant_id, barcode)` will collide with a soft-deleted row and block
re-use of a barcode after an item is deleted. The `username` precedent
(`2026_07_21_000300`) does not have this problem because `users` is not
soft-deleted. Options: include `deleted_at` in the unique index (works on both
SQLite and PostgreSQL), or enforce uniqueness in a FormRequest rule scoped
`whereNull('deleted_at')`. **I recommend the composite index** — a database
constraint beats a validation rule for something a scan depends on.
**Recommendation:** ACCEPT, unique on `(restaurant_id, barcode, deleted_at)` and
`(restaurant_id, sku, deleted_at)`.

### POS-BE-005 — `code` + `supported_order_types` on `BranchResource` · **ACCEPT**

Existing: both are real columns, both `$fillable`, `supported_order_types` already
cast to `array`. `BranchResource` simply omits them.
Compat: additive keys on an existing resource. The web SPA ignores unknown keys.
DB: none.
**Recommendation:** ACCEPT. Smallest diff in the whole set; genuinely two lines.
Note `supported_order_types` is nullable — the resource must emit `[]`, not `null`,
or the POS has to special-case it.

### POS-BE-006 — Authenticated, server-priced order creation · **ACCEPT, with the prerequisite made explicit**

This is the blocking request and Agent 1's diagnosis is exactly right.

Existing and reusable: the `Order → OrderRound → OrderItem` graph; the
`lockForUpdate()` table-visit discipline in `PublicOrderController::store()`;
`MenuItem::displayPricing()` / `defaultVariantOption()` / `orderedOptionGroups()`;
`VariantPricingService`; `NotificationService`; `AuditLogger`; `OrderResource`.

**Prerequisite, stated plainly: `order_items.menu_item_id` must exist before any
server-side re-pricing is possible.** It is currently a `name` string only. This
one column also fixes product reporting for the *existing* QR product — `ReportService`
currently has to match order items by name.

Compat: the risk concentrates on the shared `orders` table. Mitigations:
- `orders.channel` defaults to `'qr'`; every existing row and the public endpoint
  are unaffected.
- `order_items.menu_item_id` is **nullable** with `nullOnDelete`, so the public
  path may keep writing name-only rows and a deleted menu item does not cascade
  away order history.
- The POS endpoint is a **new route group**; `PublicOrderController` is not touched.

DB: see `05-database-proposal.md` §B1–B4.
Tenant: `restaurant_id` from the token's `rid`, never from input — non-negotiable.
Branch: `branch_id` validated as belonging to the tenant.
**Recommendation:** ACCEPT. Agent 1's `asserted_totals` design — client figures
sent as an assertion the server confirms, never as an instruction — is the right
shape and I would not change it.

**Answer to Agent 1's open question ("should taking money be blocked by
`subscription.writable`?"):** my recommendation is **no**. It is consistent with
the existing deliberate choice to keep order handling alive on a lapsed plan, and
the alternative means a billing lapse stops a restaurant trading mid-service —
which converts a collections problem into an outage. The owner should confirm.

### POS-BE-007 — Idempotency + minor units · **ACCEPT idempotency · money is a decision**

Existing: nothing. Confirmed.

**Idempotency — accept exactly as specified.** Agent 1's contract ("five
submissions return the same 2xx body, never a 409") is correct and is the part
implementers most often get wrong. `GET /api/pos/orders/by-client-id/{uuid}` is a
good addition and cheap.

**Minor units — this is the owner's decision and the most consequential one in the
document.** Trade-off:

| | Integer minor units (`*_minor`) | `decimal(10,2)` strings |
|---|---|---|
| Consistency with existing code | Diverges | Matches |
| Split-tender / change accuracy | Exact | Drift via `(float)` |
| KWD/BHD/OMR/JOD (3 dp) | Correct | **Cannot represent** |
| Flutter client | Native | Converts at the boundary — the exact place drift enters |
| Effort | New convention on new tables only | Zero |

**My recommendation: integer minor units on POS money fields only**, with a
`currency_exponent` resolved from `CurrencyEnum`. The existing `orders.total`
stays `decimal(10,2)` and is written as the rounded major-unit projection, so the
dashboard, stats and reports keep working untouched. New POS tables carry
`*_minor` `BIGINT`. This confines the new convention to new surface, costs nothing
in compatibility, and is the only option that is *correct* for the four
three-decimal currencies already in the enum. **JSON must never carry a float.**

### POS-BE-008 — Per-branch invoice sequence · **ACCEPT**

Existing: nothing. `Order::code()` is `'ORD-'.$id`.
DB: `invoice_sequences (restaurant_id, branch_id, period, next_value)` +
`orders.invoice_number`.
Concurrency: Agent 1 is right to insist on `lockForUpdate()` over `MAX()+1`; the
latter double-issues under two tills. Note the row must be **created** atomically
too — a `firstOrCreate` outside the lock races on first use of a new period.
Idempotency interaction: a replayed `client_transaction_id` **must return the same
invoice number and must not consume a new one**. That means number assignment
happens inside the same transaction as the idempotent insert, after the uniqueness
check — not before.
**Recommendation:** ACCEPT. Format `{branch.code}-{YYYY}-{NNNNNN}`, configurable
prefix/padding/reset. Falls back to `restaurant.slug` when `branch.code` is null.

### POS-BE-009 — Shifts, cash movements, terminals · **ACCEPT**

Existing: no concept to reuse. Reusable *patterns*: `BelongsToRestaurant`,
`RestaurantScope`, `Auditable`, `AuditLogger`.
DB: three new tables.
Branch: "one open shift per terminal" must be enforced server-side — a partial
unique index is not portable across SQLite/PostgreSQL, so this needs a transactional
check plus a `(terminal_id, status)` index, or a nullable `closed_at` participating
in the unique key.
**Client-supplied timestamps: accepted and important.** A shift opened 08:00
offline and synced 23:45 must record 08:00. Store server receipt time separately
(`received_at`), and reject client times implausibly far in the future.

**Confirmation of Agent 1's expected-cash formula — confirmed with one addition:**
```
expected_cash = opening_float + cash_sales + cash_in − cash_out − cash_refunds − payouts
```
`payouts` covers a supplier paid from the drawer; if the owner does not want that
concept in v1, the formula as Agent 1 wrote it is correct and `payouts` folds into
`cash_out`. **Agent 1's formula is safe to build against.**

### POS-BE-010 — Refunds as reversing records · **ACCEPT**

Existing: `OrderStatus` + `canTransitionTo()`; `AuditLogger`.
**Agent 1's constraint is right and I want to reinforce it:** never mutate the
original order. A refund is a new record pointing at it.

**Answer to Agent 1's question about `OrderStatus` values:** I recommend **not**
extending `OrderStatus`. `canTransitionTo()` encodes a deliberate invariant, and
adding `REFUNDED`/`PARTIALLY_REFUNDED` overloads a *lifecycle* enum with a
*financial* fact. Instead: a derived, computed `settlement_status`
(`UNPAID | PAID | PARTIALLY_REFUNDED | REFUNDED | VOIDED`) exposed on the resource
and computed from payments and refunds. The POS renders that. `OrderStatus` stays
`NEW | COMPLETED | CANCELLED` and its invariant stays intact.
**Recommendation:** ACCEPT with the derived-status approach. Owner may overrule.

### POS-BE-011 — Token lifetime · **DECISION REQUIRED (owner)**

Not a defect; a genuine conflict between a stateless 7-day token and a till that
sells offline.

**My recommendation: Option A now, Option C later.** Raise the POS token TTL via a
dedicated config value (e.g. `JWT_POS_TTL`, default 30 days) issued when the login
carries a `terminal_id`, and revisit a terminal-bound device token (Option C) when
terminal registration (POS-BE-009) is live and can carry it. Option A is a
config-and-claim change; Option C is a new credential surface to build, secure and
revoke, and building it before terminals exist means building it twice.

Blast radius is real but bounded: a leaked POS token is tenant-scoped by `rid`,
capability-scoped by the role, and `password_changed_at` still revokes it instantly.
**This is the owner's call.**

### POS-BE-012 — Incremental catalog sync · **ACCEPT, defer**

Existing: every model has `updated_at`; `menu_items` and `categories` already use
`SoftDeletes`, so Agent 1 is right that tombstones need no new table.
**Caveat:** `option_groups` and `options` do **not** use `SoftDeletes` — a deleted
option group leaves no tombstone and a POS cache would keep offering it. Delta sync
for those two either needs `SoftDeletes` added or must fall back to a full pull.
**Recommendation:** ACCEPT at LOW priority as Agent 1 rated it. Full pulls are fine
at restaurant catalog sizes; this is an optimisation, not a correctness fix — with
the one exception of the missing option-group tombstones, which should be noted in
the POS's own diagnostics.

### POS-BE-013 — Tax, charges, tenders, tax id · **ACCEPT**

Existing: none of it. `RestaurantProfileController` + `settings.view` /
`settings.update` is indeed the natural authoring home; `restaurant_features` is
the precedent for a per-tenant configuration table.

Agent 1's design asks are all correct and I endorse each:
- basis points (`1400` = 14 %), never a float
- explicit `inclusive`/`exclusive` per rule
- scoping by order type / branch / category / item
- `taxable` flag on charges
- tender types as **data** with `kind: cash|card|external|other`, so v1 records a
  card taken on a standalone bank terminal without pretending to be a processor

A single cacheable `GET /api/pos/config` with one `synced_at` is the right shape.

**Interim behaviour is acceptable but should carry a deadline.** Agent 1 proposes
reading tax from read-only local device config until this is `READY`, with the
receipt honest about its source. That is the right stopgap — but a tenant that
charges tax must not go live on it. **For any taxed tenant, POS-BE-013 is blocking.**

### POS-BE-014 — Authenticated customer creation · **ACCEPT**

Existing: `CustomerDirectory::upsert()` — the reusable core. Agent 1's insistence
on reusing it rather than writing a second creation path is right; two paths means
two identities per phone number and a split directory.
**New verb needed:** `customers.create`. The docblock's "read-only from the
dashboard" was a deliberate scoping choice, not a principle, and adding a write
verb does not weaken anything — no existing role holds it.
**Recommendation:** ACCEPT at LOW priority. Mount at `/api/pos/customers` for
symmetry with the rest of the POS surface; the dashboard can gain its own later.

---

## 3. Requests Agent 1 did **not** make, that I believe are needed

Raised here for the owner's awareness. Numbered in a separate `BE-` series so they
never collide with Agent 1's ids.

| ID | Gap | Why it matters | Priority |
|---|---|---|---|
| **BE-A01** | **Payments are not a request of their own.** POS-BE-006 carries them implicitly inside order creation. | Split tender, partial payment and change are first-class records, not order columns. Without an `order_payments` table the POS cannot represent "300 cash + 200 card". | **HIGH** |
| **BE-A02** | Per-user branch scoping (`users.branch_id`) | Today any staff account sees every branch's tills and shift reports. Fine for QR, questionable for cash. Cheaper before deployment than after. | MEDIUM |
| **BE-A03** | `option_groups` / `options` lack `SoftDeletes` | No tombstone → a POS offline cache keeps selling a deleted modifier. Affects POS-BE-012. | LOW |
| **BE-A04** | Terminal revocation | POS-BE-009 registers terminals but nothing revokes a lost one. `password_changed_at` revokes the *cashier*, not the *device*. | MEDIUM |
| **BE-A05** | `ReportService` matches order items by name | Once `menu_item_id` exists (POS-BE-006), reporting should key on it. Existing latent defect. | LOW |

---

## 4. Blocking chain

```
order_items.menu_item_id  ─┬─→ POS-BE-006 (order creation) ─┬─→ BE-A01 (payments)
                           │                                 ├─→ POS-BE-008 (invoice no.)
POS-BE-007 (idempotency) ──┘                                 └─→ POS-BE-010 (refunds)

POS-BE-013 (tax/charges/tenders) ──→ blocking for any TAXED tenant
POS-BE-009 (shifts/cash/terminals) ──→ blocking for Phase 6, depends on 006+007
POS-BE-001/002 ──→ gate everything, block nothing (POS degrades to owner-only)
POS-BE-003/004/005/012/014 ──→ independent, non-blocking
```

**If the owner approves exactly one thing, it should be POS-BE-006 together with
POS-BE-007** — they are not separable in practice. Agent 1 named 006 alone; I would
add 007, because building order creation without the idempotency column means
migrating a table that already holds real money records.

---

> **BACKEND IMPLEMENTATION HAS NOT STARTED. OWNER APPROVAL IS REQUIRED.**
