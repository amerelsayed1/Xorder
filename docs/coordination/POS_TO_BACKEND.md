# POS → BACKEND — Requirement Requests

**Channel owner:** Agent 1 (Flutter POS Desktop)
**Absolute path:** `~/Projects/Mobile Application/xorder-pos/docs/coordination/POS_TO_BACKEND.md`
**Backend repo under analysis:** `~/Projects/Web Application/xorder-new` (`apps/api`)
**Reply channel:** `./BACKEND_TO_POS.md`
**Last updated:** 2026-09-11 (POS-BE-029 rule 3: payment kinds are the platform's — see change log)

---

> ## ✅ Contracts are AGREED. Implementation is still gated.
> **Owner instruction, 2026-09-02:** both agents were directed to agree the
> contract for every item. Every request below is now `APPROVED` — the final
> wire contracts live in `BACKEND_TO_POS.md`, including the resolutions of
> DIS-1…DIS-5 — except POS-BE-015, which is `READY` (shipped).
>
> `APPROVED` authorises **no backend code**. Implementation of any item still
> needs the owner's explicit go, item by item. Agent 1 keeps building against
> repository interfaces and fake implementations, and integrates real transport
> only when an item reaches `READY`.

**Status vocabulary:** `PROPOSED` · `APPROVED` · `IN_PROGRESS` · `READY` · `BLOCKED`
Only Agent 2 (after owner approval) moves an item past `PROPOSED`, and it does so
in `BACKEND_TO_POS.md` — this file records the *request*.

---

## Index

| ID | Feature | Priority | Blocking | Status |
|---|---|---|---|---|
| POS-BE-001 | `Feature::POS` entitlement + plan wiring | MEDIUM | NO | APPROVED |
| POS-BE-002 | POS tenant capabilities (`pos.*`) | HIGH | NO | APPROVED |
| POS-BE-003 | Auto-applied option groups on `/dashboard/items` | HIGH | NO | APPROVED |
| POS-BE-004 | `sku` + `barcode` on menu items | MEDIUM | NO | APPROVED |
| POS-BE-005 | `supported_order_types` + `code` on `BranchResource` | HIGH | NO | APPROVED |
| **POS-BE-006** | **Authenticated, server-priced POS order creation** | **HIGH** | **YES** | APPROVED |
| POS-BE-007 | Idempotency + integer minor units on POS writes | HIGH | YES | APPROVED |
| POS-BE-008 | Per-branch invoice sequence | HIGH | YES | APPROVED |
| POS-BE-009 | Shifts, cash movements, terminal registry | HIGH | YES | APPROVED |
| POS-BE-010 | Refunds / voids as reversing records | MEDIUM | NO | APPROVED |
| POS-BE-011 | Token lifetime compatible with an offline till | HIGH | NO | APPROVED |
| POS-BE-012 | Incremental catalog sync (`updated_since` + tombstones) | LOW | NO | APPROVED |
| POS-BE-013 | Money configuration: tax, charges, tender types, tax id | HIGH | YES | APPROVED |
| POS-BE-014 | Authenticated customer creation from the till | LOW | NO | APPROVED |
| POS-BE-015 | Licence issuance + activation endpoints | MEDIUM | NO | **READY** |
| POS-BE-016 | Terminal registration against a licence (seat counting) | MEDIUM | NO | APPROVED |
| POS-BE-017 | Branch-server packaging (on-premises deployment) | MEDIUM | NO | APPROVED |
| POS-BE-018 | Upstream sync: branch server → platform | MEDIUM | NO | APPROVED |
| POS-BE-019 | Machine-readable error codes on POS writes | HIGH | NO | APPROVED |
| POS-BE-020 | Server time exposed for clock-skew detection | LOW | NO | APPROVED |
| POS-BE-021 | Bulk drain of a queued backlog after an outage | MEDIUM | NO | APPROVED |
| POS-BE-022 | Super Admin fleet registry + automatic heartbeat | HIGH | NO | APPROVED |
| POS-BE-023 | Terminal provisioning from the dashboard + `/api/pos/bootstrap` | HIGH | YES | APPROVED |
| POS-BE-024 | POS PIN credential for offline cashier sign-in | HIGH | YES | APPROVED |
| POS-BE-025 | Pre-auth tenant setup config (`/setup/config/{slug}`) + versioning | HIGH | NO | APPROVED |
| POS-BE-026 | Site registration and `ServerId` | MEDIUM | NO | APPROVED |
| POS-BE-027 | Licence claims: `max_offline_days`, `server_id`, `license_version` | MEDIUM | NO | APPROVED |
| POS-BE-028 | Terminal display-name update, decoupled from identity | LOW | NO | APPROVED |
| POS-BE-030 | Purchasing and stock on a cloud terminal are platform-authored | LOW | NO | APPROVED — built both sides, not merged or deployed |

Three of the entries above are **amendments rather than new surface**:
POS-BE-025 is a redacted projection of POS-BE-023's bundle, POS-BE-027 adds three
claims to the already-`READY` POS-BE-015, and the POS-BE-022 amendment asks only
that its heartbeat *response* be specified. See `docs/pos/10-setup-architecture.md`.

**If the owner approves only one item, it should be POS-BE-006** — everything
that takes money depends on it, and its prerequisite (`order_items.menu_item_id`)
independently fixes product reporting for the existing QR product.

---

## POS-BE-001

**Status:** APPROVED — contract agreed 2026-09-02, see `BACKEND_TO_POS.md`; implementation not started
**Feature:** `Feature::POS` entitlement flag + plan wiring

**Description:** Add a `pos` case to `App\Enums\Feature` so the POS surface can be
gated by `feature:pos` exactly as `table_management`, `bill_requests` and
`internal_reviews` already are, and so it can be sold as its own SKU. Optionally
`plans.max_terminals`, mirroring the existing `max_items` / `max_branches` /
`max_staff` pattern in `PlanLimitService`.

**Why POS needs it:** without an entitlement the POS is either free to every
tenant or gated by an ad-hoc check. The existing pattern already solves this.

**Existing API discovered:** `App\Enums\Feature`,
`App\Services\PlanEntitlementService`, `App\Http\Middleware\EnsureFeatureEnabled`,
`restaurant_features` table, `2026_08_25_000100_add_max_staff_to_plans_table.php`
as the precedent for a new plan limit.

**Suggested method / endpoint:** none new — a middleware key applied to whatever
POS routes are approved.

**Suggested request/response:** `UserResource.restaurant.features` gains
`"pos": true|false`. The POS reads it at login and shows a clear "not entitled"
screen rather than failing at first write.

**Permissions:** tenant-level flag, toggled by Super Admin (existing wizard step 5).
**Tenant behaviour:** per-restaurant, as every other feature flag.
**Branch behaviour:** none.
**Offline requirements:** cached with the session; a lapse is honoured at next sync,
never mid-shift.
**Idempotency:** n/a.
**Priority:** MEDIUM · **Blocking:** NO

---

## POS-BE-002

**Status:** APPROVED — contract agreed 2026-09-02, see `BACKEND_TO_POS.md`; implementation not started
**Feature:** POS tenant capabilities

**Description:** Add POS verbs to `App\Enums\TenantCapability`:

```
pos.operate         may use the till at all
pos.discount        apply a line or order discount
pos.price_override  override a line price
pos.void            void a fired line / cancel a fired order
pos.refund          issue a refund
pos.shift.open      open a shift
pos.shift.close     close a shift (cash-up)
pos.cash_movement   record cash in / cash out
pos.reprint         reprint a receipt
```

**Why POS needs it:** the whole permission model is already built and shipped —
`roles` table, `users.role_id`, `TenantRoleService`, `Gate` wiring,
`User::holdsTenantCapability()`, owner bypass, and `UserResource.capabilities[]`
delivered to the client. The POS needs **vocabulary**, not machinery.

**Existing API discovered:** `App\Enums\TenantCapability` (already per-verb, with
`resource()`, `action()`, `group()`, `implies()`, `expand()` and a legacy-`manage`
translation map), `Dashboard\RoleController@capabilities`,
`GET /api/dashboard/roles/capabilities`.

**Suggested method / endpoint:** none new. New enum cases flow automatically into
the existing role editor and into `capabilities[]`.

**Notes for Agent 2:**
- `TenantCapability::group()` will need a `'pos'` grouping key for the role editor.
- `implies()` derives `<resource>.view` from the resource half — `pos.shift.close`
  has two dots, so `resource()` returns `pos` and `implies()` would look for
  `pos.view`, which does not exist. Either add `pos.view` or flatten the name to
  `pos.shift_close`. **Agent 1 has no preference; please decide and tell us the
  final strings** — the client treats them as opaque.
- The "cannot grant above self" concern already noted in
  `docs/RESEARCH_RBAC_AND_POS.md` §1.5 applies unchanged.

**Permissions:** these *are* permissions.
**Tenant behaviour:** per-restaurant roles, as today. Owner holds all implicitly.
**Branch behaviour:** none requested. Per-branch staff scoping is out of scope.
**Offline requirements:** cached with the session; the client gates UI on them and
the server re-gates on sync.
**Idempotency:** n/a.
**Priority:** HIGH · **Blocking:** NO — the POS degrades to owner-only until then.

---

## POS-BE-003

**Status:** APPROVED — contract agreed 2026-09-02, see `BACKEND_TO_POS.md`; implementation not started
**Feature:** Auto-applied option groups on the dashboard items endpoint

**Description:** `GET /api/dashboard/items` should return the same *complete* set
of option groups the public menu resolves, including groups that apply by
`apply_scope = 'categories'` or `'all'`.

**Why POS needs it:** a restaurant-wide "Extras" group is invisible to the POS
today, so a cashier physically cannot add an extra the diner can add from their
phone. Same menu, two different answers.

**Existing API discovered:** `MenuItem::orderedOptionGroups()` already merges
inline + shared + `autoOptionGroups` and de-duplicates. `MenuItem::$autoOptionGroups`
is populated by `PublicMenuService` via `withAutoOptionGroups()` from a single
restaurant-level query, so it is already N+1-free. `MenuItemResource` gates the
`option_groups` key on `relationLoaded('optionGroups') || relationLoaded('sharedOptionGroups')`
only — the auto groups are simply never injected on this path.

**Suggested method / endpoint:** unchanged — `GET /api/dashboard/items`.
Ideally behind an explicit `?with=option_groups` or `?resolve=full` so existing
dashboard callers keep their current payload size.

**Suggested response:** unchanged shape; the `option_groups[]` array is simply
complete. Each entry already carries `id`, `is_global`, `is_required`,
`is_variant`, `max_select` and `options[]`.

**Permissions:** `can:menu.view` (unchanged).
**Tenant behaviour:** `RestaurantScope` (unchanged).
**Branch behaviour:** none.
**Offline requirements:** this response is cached wholesale by the POS; a missing
group means a permanently wrong cart offline.
**Idempotency:** read-only.
**Priority:** HIGH · **Blocking:** NO — but the POS is *wrong* without it, not
merely incomplete.

---

## POS-BE-004

**Status:** APPROVED — contract agreed 2026-09-02, see `BACKEND_TO_POS.md`; implementation not started
**Feature:** `sku` and `barcode` on menu items

**Description:** Nullable `sku` and `barcode` columns on `menu_items`, exposed on
`MenuItemResource`, editable in the dashboard item form, and included in the
existing CSV/XLSX menu import/export.

**Why POS needs it:** barcode scanning has nothing to match against. Verified: no
SKU, PLU, barcode or article-number column exists anywhere in `apps/api`.

**Existing API discovered:** `menu_items` table; `MenuItemController`,
`MenuImportController`, `MenuExportController`.

**Suggested request:** `POST/PUT /api/dashboard/items` accepts
`{ "sku": "BRG-001", "barcode": "6221031492818" }`.
**Suggested response:** both fields on `MenuItemResource`.

**Validation suggested:** `barcode` unique per restaurant when present
(a scan must resolve to exactly one item); `sku` unique per restaurant when present.

**Permissions:** `can:menu.create` / `can:menu.update`.
**Tenant behaviour:** unique **per tenant**, following the `username` precedent
(`2026_07_21_000300_make_username_unique_per_tenant.php`).
**Branch behaviour:** none.
**Offline requirements:** cached; barcode lookup is a local index.
**Idempotency:** standard CRUD.
**Priority:** MEDIUM · **Blocking:** NO — POS-R023 is inert until this lands.

---

## POS-BE-005

**Status:** APPROVED — contract agreed 2026-09-02, see `BACKEND_TO_POS.md`; implementation not started
**Feature:** Expose `supported_order_types` and `code` on `BranchResource`

**Description:** `branches.supported_order_types` (already a real column, already
in `$fillable`, already cast to `array`) is not serialised by `BranchResource`.
Same for `branches.code`.

**Why POS needs it:** the POS must show only the order types the branch actually
supports (POS-R071) and must not hardcode a set. `code` is wanted as the invoice
prefix in POS-BE-008.

**Existing API discovered:** `App\Models\Branch` — `supported_order_types` and
`code` both `$fillable`; `App\Http\Resources\BranchResource` omits both.
`GET /api/dashboard/branches` is gated `can:branches.list`.

**Suggested method / endpoint:** `GET /api/dashboard/branches` (unchanged).
**Suggested response addition:**

```jsonc
{ "code": "MAADI", "supported_order_types": ["dine_in", "takeaway", "delivery"] }
```

**Permissions:** `can:branches.list` (unchanged).
**Tenant behaviour / branch behaviour:** unchanged.
**Offline requirements:** cached with branch config.
**Idempotency:** read-only.
**Priority:** HIGH · **Blocking:** NO — smallest diff in this document.

---

## POS-BE-006

**Status:** APPROVED — contract agreed 2026-09-02, see `BACKEND_TO_POS.md`; implementation not started
**Feature:** Authenticated, server-priced POS order creation

> **This is the blocking request. Everything that takes money depends on it.**

**Description:** An authenticated endpoint that creates an order from **item ids
and option ids**, prices it **server-side**, and returns the authoritative totals
and invoice number.

**Why POS needs it:**
1. There is **no authenticated order-creation endpoint anywhere** today. The only
   write path is `POST /api/public/restaurants/{slug}/orders`, which is
   unauthenticated, throttled `20,1`, and documented as taking no payment.
2. That endpoint recomputes `total` from **client-submitted `line_total` values**
   (`PublicOrderController::store`) — acceptable when no money changes hands,
   unacceptable at a till.
3. **`order_items` has no `menu_item_id`** — only a `name` string
   (`2026_08_19_000100_create_table_visits_and_order_rounds.php`). Server-side
   re-pricing is therefore *impossible* on the current schema. This is the real
   prerequisite.

**Existing API discovered / reusable:**
`Order` → `OrderRound` → `OrderItem` graph; `TableVisit` + `MenuSession` with the
existing `lockForUpdate()` discipline; `PublicOrderController::store` as the
reference implementation for table-visit binding and round recording;
`MenuItem::displayPricing()` / `defaultVariantOption()` /
`orderedOptionGroups()` as the authoritative pricing rules;
`VariantPricingService`; `NotificationService`; `AuditLogger`; `OrderResource`.

**Agent 1 recommends extending this graph, not creating a parallel one.** A POS
order must be the same `Order` the dashboard already lists, distinguished by a
`channel` column — otherwise the restaurant has two order histories.

**Suggested method:** `POST`
**Suggested endpoint:** `/api/pos/orders` (or `/api/dashboard/pos/orders` if a new
top-level group is unwelcome — Agent 1 has no preference)

**Suggested request:** the envelope in `docs/pos/05-data-contracts.md` §14. Key points:
- `client_transaction_id` (idempotency key)
- `lines[]` with `menu_item_id`, `variant_option_id`, `option_ids[]`, `quantity`,
  `note`, `name_snapshot`
- cashier adjustments: `discount`, `price_override` (each with a reason)
- `asserted_totals` — the client's computed figures, sent **as an assertion the
  server must confirm**, never as an instruction
- `created_at` supplied by the client (an offline order may be hours old)
- `priced_offline` + `catalog_synced_at`

**Suggested response:** `201` with server-computed `totals`, `id`,
`invoice_number`, `client_transaction_id`, `created_at`.

**Suggested validation / behaviour:**
- Re-price every line from `menu_item_id` + option ids. **Ignore client prices
  except to compare.**
- If server totals ≠ `asserted_totals`, still create the order (money was taken)
  but return both figures with a `totals_mismatch` marker so the POS can raise a
  reconciliation dialog (POS-R081).
- Accept a line whose `menu_item_id` no longer resolves (item deleted during an
  outage) by falling back to `name_snapshot` + the asserted price, flagged.
- Reuse `lockForUpdate()` on `TableVisit` for dine-in.
- Set `orders.channel = 'pos'` so POS revenue is distinguishable from QR revenue.

**Errors:** `401` · `403` (`feature:pos`, `can:pos.operate`) · `409` should **not**
be used for a duplicate key — see POS-BE-007 · `422` validation.

**Permissions:** `can:pos.operate` (POS-BE-002), `feature:pos` (POS-BE-001).
**Tenant behaviour:** `RestaurantScope`, `restaurant_id` from the token's `rid` and
never from input.
**Branch behaviour:** `branch_id` validated as belonging to the tenant.
**Offline requirements:** must accept `created_at` in the past, out of order, and
in bulk after a long outage.
**Idempotency requirements:** see POS-BE-007. **Mandatory.**

**Open product question for the owner:** should taking money be blocked by
`subscription.writable`? The existing code deliberately keeps *order handling*
available on a lapsed subscription. Agent 1 has no view; it is a commercial call.

**Priority:** HIGH · **Blocking:** **YES**

---

## POS-BE-007

**Status:** APPROVED — contract agreed 2026-09-02, see `BACKEND_TO_POS.md`; implementation not started
**Feature:** Idempotency and integer minor units on every POS write

**Description:** Every POS write accepts a client-generated
`client_transaction_id` (UUID v4), unique-indexed per tenant per aggregate type.

**The contract Agent 1 needs, stated precisely:**

> Five submissions of the same `client_transaction_id` must create **exactly one**
> authoritative record, and **all five must return the same 2xx response body** —
> including the assigned id and invoice number.
>
> A replay must **not** return `409`. The single case idempotency exists for is a
> request that timed out with no response, where the client cannot know whether
> the first attempt succeeded. A `409` on replay leaves that client with no way to
> learn the record's id, which is precisely the state the key was meant to prevent.

**Why POS needs it:** an offline till retries. A double-tapped Pay button must not
create two payments. Verified: no idempotency key, unique client-id column, or
dedupe mechanism exists anywhere in `apps/api`.

**Existing API discovered:** none — genuinely new. `orders`, `order_items`,
`order_rounds` have no client-supplied identifier.

**Suggested transport:** both `Idempotency-Key: <uuid>` **and** a
`client_transaction_id` body field. Belt and braces: a proxy may strip headers,
and the body field is what gets persisted and indexed.

**Suggested storage:** a `client_transaction_id` column on each POS aggregate with
a unique index scoped `(restaurant_id, client_transaction_id)`, plus a lookup
endpoint `GET /api/pos/orders/by-client-id/{uuid}` so a client that lost the
response can recover the record.

**Money representation:** Agent 1 asks that POS money fields be **integer minor
units** (`*_minor`) rather than `decimal:2` strings. Rationale: the existing order
path does `(float)` arithmetic (`PublicOrderController::store`), which produces
cent drift on split bills. The Flutter client uses integer minor units end-to-end
and would otherwise convert at the boundary — the exact place drift is introduced.
Currency exponent varies (EGP/SAR/AED/QAR/USD/EUR/GBP = 2; **KWD/BHD/OMR/JOD = 3**,
all present in `App\Enums\CurrencyEnum`). **If the backend prefers decimal strings, Agent 1 can
work with that** — but please make it a decision rather than an accident, and
never send a JSON float.

**Permissions:** inherited from the wrapped endpoint.
**Tenant behaviour:** the unique index must be tenant-scoped; two tenants may
legitimately generate the same UUID (astronomically unlikely, but the index should
not be the thing that discovers it).
**Branch behaviour:** none.
**Offline requirements:** this request exists entirely for offline.
**Priority:** HIGH · **Blocking:** YES (paired with POS-BE-006)

---

## POS-BE-008

**Status:** APPROVED — contract agreed 2026-09-02, see `BACKEND_TO_POS.md`; implementation not started
**Feature:** Per-branch invoice sequence

**Description:** A human-readable invoice number assigned **server-side**, distinct
from the database primary key, sequenced per branch, concurrency-safe.

**Why POS needs it:** `Order::code()` is literally `'ORD-'.$this->id` — a database
id. It is not a legal invoice number, it is not per-branch, it has gaps, and it
leaks total order volume across the whole tenant. A printed receipt needs a real
sequence.

**Existing API discovered:** none. `Order::code()` is the only order reference that
exists.

**Suggested shape:**

```
{branch.code}-{YYYY}-{NNNNNN}      e.g.  MAADI-2026-001042
```

with prefix, padding and reset rule (never / yearly / monthly) configurable per
tenant. `branch.code` already exists as a column (POS-BE-005 exposes it).

**Concurrency:** a dedicated `invoice_sequences` table
`(restaurant_id, branch_id, period, next_value)` with `lockForUpdate()` inside the
order-creation transaction. A `MAX(number)+1` scan will double-issue under two
concurrent tills — please don't.

**The human-readable sequence must NOT be the primary key.** It needs to be
reassignable and format-configurable; a PK is neither.

**Offline requirements:** the till prints a **provisional**, terminal-scoped
reference (`T3-000117`) while offline and clearly marks the receipt as
provisional. The authoritative number is assigned on sync and bound back to the
local record. Agent 1 does **not** ask the server to honour a client-proposed
number — that would guarantee collisions across tills.

**Permissions:** inherited from order creation.
**Tenant/branch behaviour:** sequence is `(tenant, branch, period)`.
**Idempotency:** a replayed `client_transaction_id` must return the **same**
invoice number, not consume a new one.
**Priority:** HIGH · **Blocking:** YES

---

## POS-BE-009

**Status:** APPROVED — contract agreed 2026-09-02, see `BACKEND_TO_POS.md`; implementation not started
**Feature:** Shifts, cash movements, and a terminal registry

**Description:** Three related concepts, none of which exist today (verified — no
shift, till, register, drawer, cashier-session or device concept anywhere in
`apps/api`):

1. **`pos_terminals`** — `(restaurant_id, branch_id, terminal_id UUID, name,
   platform, app_version, last_seen_at)`. The client generates `terminal_id` and
   uses it regardless; registration is so a manager can name and audit tills.
2. **`pos_shifts`** — see `docs/pos/05-data-contracts.md` §19. Opening float,
   expected vs counted cash, variance + reason, denominations, status.
3. **`pos_cash_movements`** — see §20. Direction, amount, reason, reference.

**Why POS needs it:** cash-up is the reason a restaurant buys a POS. Without a
server-side shift there is no X/Z report, no over/short, and no way for an owner
to see yesterday's till from the dashboard.

**Existing API discovered:** none to reuse for the concepts themselves.
Reusable *patterns*: `BelongsToRestaurant` + `RestaurantScope` for isolation,
`AuditLogger` for the trail, `Auditable` on the models.

**Suggested endpoints:**

| Method | Endpoint | Purpose |
|---|---|---|
| `POST` | `/api/pos/terminals` | register / heartbeat this terminal |
| `POST` | `/api/pos/shifts` | open a shift |
| `GET` | `/api/pos/shifts/current` | current open shift for this terminal |
| `POST` | `/api/pos/shifts/{clientId}/close` | close with counted cash + denominations |
| `GET` | `/api/pos/shifts/{clientId}/report` | X / Z report figures |
| `POST` | `/api/pos/cash-movements` | cash in / out |

**Critical detail:** `opened_at`, `closed_at` and `created_at` must be
**client-supplied**. A shift opened at 08:00 offline and synced at 23:45 must not
record 23:45 as its opening time. Server receipt time should be stored separately.

**Expected-cash formula the POS uses (please confirm or correct):**
`opening_float + cash_sales + cash_in − cash_out − cash_refunds`

**Permissions:** `pos.shift.open`, `pos.shift.close`, `pos.cash_movement`
(POS-BE-002).
**Tenant behaviour:** tenant-scoped.
**Branch behaviour:** a shift belongs to `(branch, terminal)`. Only one open shift
per terminal at a time — please enforce server-side; the client enforces it too.
**Offline requirements:** a full shift lifecycle must be openable, operable and
closable offline and sync afterwards as a batch.
**Idempotency:** per POS-BE-007, on every one of these writes.
**Priority:** HIGH · **Blocking:** YES for Phase 6

---

## POS-BE-010

**Status:** APPROVED — contract agreed 2026-09-02, see `BACKEND_TO_POS.md`; implementation not started
**Feature:** Refunds and voids as reversing records

**Description:** Partial and full refunds against a settled order, recorded as a
**reversing counter-record** — never an edit or deletion of the original.

**Why POS needs it:** `OrderStatus` is `NEW / COMPLETED / CANCELLED` only, and
`canTransitionTo()` explicitly forbids reopening to `NEW`. There is no reason code,
no manager approval, no partial refund, and no concept of returning money.

**Existing API discovered:** `App\Enums\OrderStatus` +
`OrderStatus::canTransitionTo()`; `PATCH /api/dashboard/orders/{order}/status`
(`can:orders.update`); `AuditLogger`.

**Suggested method / endpoint:** `POST /api/pos/refunds`
**Suggested request:** `docs/pos/05-data-contracts.md` §18.
**Suggested response:** the refund record with its own invoice/credit-note number
and a reference to the original.

**Design constraints Agent 1 asks for:**
- Never mutate or delete the original order. A refund is a new record pointing at it.
- Server must validate that the cumulative refunded quantity per line never exceeds
  the sold quantity. The client checks too; the server is authoritative.
- The existing "an order can never be reopened to `NEW`" invariant should stay
  intact — a refund is not a reopening.
- Extending `OrderStatus` (e.g. `REFUNDED`, `PARTIALLY_REFUNDED`, `VOIDED`) is
  Agent 2's call; please tell us the final values, as the POS renders them.

**Permissions:** `pos.refund`, plus a supervisor override above a configurable
amount (POS-R164).
**Tenant/branch behaviour:** tenant-scoped; refund belongs to a branch and a shift.
**Offline requirements:** refunds are creatable offline and queue like orders.
**Idempotency:** per POS-BE-007.
**Priority:** MEDIUM · **Blocking:** NO (Phase 9)

---

## POS-BE-011

**Status:** APPROVED — contract agreed 2026-09-02, see `BACKEND_TO_POS.md`; implementation not started
**Feature:** A token lifetime story compatible with a till that goes offline

**Description:** Not a request for a specific implementation — a request for a
**decision**, because the current design and an offline till are in direct conflict.

**The conflict:** tokens expire after `config('jwt.ttl')` minutes. There is no
refresh token. `users.password_changed_at` retroactively invalidates every token
issued before it (`AppServiceProvider`). A till that sells offline for four hours
and reconnects to a `401` — holding a queue of real, paid transactions — is the
worst state in the whole system: money has changed hands and the client cannot
report it.

**What the POS does regardless of the answer:** it never discards the queue. It
enters an explicit "sign in to sync" state, keeps selling, and drains the queue
after re-authentication. So this is not *blocking* — it is the difference between
a cashier being interrupted mid-rush and not.

**Options Agent 1 sees (Agent 2 and the owner decide):**

| Option | Note |
|---|---|
| A — longer TTL for POS tokens | Simplest. Weakens a leaked token's blast radius. |
| B — refresh token bound to `terminal_id` | Standard; new surface to build and secure. |
| C — device token issued at terminal registration, separate from the user session | Cleanest conceptually (the *terminal* is authenticated, the *cashier* is identified). Most work. |
| D — accept it | The POS handles it as described. Free, but it will be a support ticket. |

**Existing API discovered:** `App\Support\Jwt` (`issue`/`parse`, claims
`iss sub iat nbf exp rid`), `config/jwt.php`, the `viaRequest('jwt')` guard,
`AuthController::changePassword` re-minting on rotation.

**Priority:** HIGH (as a decision) · **Blocking:** NO

---

## POS-BE-012

**Status:** APPROVED — contract agreed 2026-09-02, see `BACKEND_TO_POS.md`; implementation not started
**Feature:** Incremental catalog sync

**Description:** `?updated_since=<iso8601>` on the catalog reads, returning changed
rows plus a `deleted_ids[]` tombstone list.

**Why POS needs it:** the POS refreshes its catalog every 15 minutes. A full pull
of items + option groups + categories per till per 15 minutes is wasteful, and on
a slow branch connection it is slow enough that staff turn it off.

**Existing API discovered:** `GET /api/dashboard/items`, `/categories`,
`/option-groups`, `/combos` — all full-collection reads today. Every model has
`updated_at`. `menu_items` and `categories` use `SoftDeletes`, so tombstones are
already recoverable from `deleted_at` rather than needing a new table.

**Suggested endpoint:** unchanged, plus the query parameter.
**Suggested response addition:** `{"data": [...], "deleted_ids": [...], "synced_at": "…"}`

**Permissions:** `can:menu.view` (unchanged).
**Offline requirements:** this exists to make the offline cache cheap to keep fresh.
**Idempotency:** read-only.
**Priority:** LOW · **Blocking:** NO — the POS does full pulls until then, which is
fine at restaurant catalog sizes.

---

## POS-BE-013

**Status:** APPROVED — contract agreed 2026-09-02, see `BACKEND_TO_POS.md`; implementation not started
**Feature:** Money configuration — tax rules, additional charges, tender types,
tax registration number

**Description:** The server must become the author of everything that decides how
much money is owed. **None of it exists today** — verified: no tax rate on
restaurant, branch or item; no service charge; no tender type; no tax registration
number.

Shapes requested: `docs/pos/05-data-contracts.md` §10 (tax rule), §12 (charge),
§13 (tender type), §1 (tax registration number on the restaurant).

**Why POS needs it:** if the client authors tax, then tax is whatever the till
says it is — different per terminal, unauditable, and impossible to correct
centrally. This is the single clearest "server must own it" case in the document.

**Existing API discovered:** none for tax/charges/tenders.
`RestaurantProfileController` + `settings.view` / `settings.update` is the natural
home for authoring them; `restaurant_features` is the precedent for per-tenant
configuration tables.

**Suggested endpoints:**

| Method | Endpoint | Purpose |
|---|---|---|
| `GET` | `/api/pos/config` | one call returning tax rules + charges + tender types + branch config + restaurant tax id |
| `GET/POST/PUT/DELETE` | `/api/dashboard/tax-rules`, `/charges`, `/tender-types` | authoring, from the dashboard |

A single `/api/pos/config` read is what the POS actually wants: one cacheable
document, one `synced_at`, one thing to invalidate.

**Design asks:**
- Tax rate as **integer basis points** (`1400` = 14 %), never a float.
- Explicit `inclusive` / `exclusive` mode per rule.
- Scope by order type, branch, category or item.
- Charges flagged `taxable` so the POS knows whether service charge is taxed.
- Tender types as data with `kind: cash|card|external|other`, so v1 can record a
  card taken on a standalone bank terminal without pretending to be a processor.

**Interim behaviour:** until this is `READY` the POS reads tax and charge rules
from **read-only local device config**, and every receipt produced that way is
honest about its source. Tax is never invented by the client at runtime.

**Permissions:** read — `pos.operate`; author — `settings.update`.
**Tenant behaviour:** per-restaurant, with optional per-branch overrides.
**Offline requirements:** cached wholesale; a stale tax rule is visible in
diagnostics.
**Idempotency:** reads.
**Priority:** HIGH · **Blocking:** YES for any tenant that charges tax

---

## POS-BE-014

**Status:** APPROVED — contract agreed 2026-09-02, see `BACKEND_TO_POS.md`; implementation not started
**Feature:** Authenticated customer creation from the till

**Description:** An authenticated endpoint to create a customer (and optionally an
address) from the POS.

**Why POS needs it:** a delivery order requires a customer with an address
(POS-R072), and a cashier taking a phone order has no way to create one.
Customers can currently only be created through `CustomerDirectory::upsert()` on
the **public**, unauthenticated diner path.

**Existing API discovered:** `App\Services\CustomerDirectory::upsert()` (the
reusable core), `Customer`, `CustomerAddress`, `App\Traits\NormalizesPhoneNumbers`,
`GET /api/dashboard/customers` (`can:customers.view`),
`Public\PublicCustomerController` as the existing caller.

**Suggested method:** `POST` · **endpoint:** `/api/pos/customers`
(or `/api/dashboard/customers` — Agent 1 has no preference).
**Suggested request:** `{ name, phone, address?, latitude?, longitude?, note? }`
**Suggested response:** `CustomerResource`.

**Important:** please reuse `CustomerDirectory::upsert()` rather than writing a
second creation path, so POS-created and diner-created customers deduplicate to
one identity. Phone normalisation must be identical or the directory splits.

**Permissions:** a `customers.create` verb would be needed —
`TenantCapability` currently has `customers.view` only, deliberately ("read-only
from the dashboard"). Adding a write verb is a judgement call for Agent 2.
**Tenant behaviour:** tenant-scoped, phone unique per tenant as today.
**Branch behaviour:** none.
**Offline requirements:** the POS creates the customer locally and queues it; the
order references it by `client_transaction_id` until the server id comes back.
**Idempotency:** per POS-BE-007 — and an upsert on phone makes a replay naturally safe.
**Priority:** LOW · **Blocking:** NO — v1 can require an existing customer for
delivery.

---

## POS-BE-015

**Status:** **READY** — implemented and tested in `apps/api`, with the Super
Admin screens in `apps/web`. Owner decision D6, 2026-08-26: a licence is its own
per-client record, issued from Super Admin. The final contract is in
`BACKEND_TO_POS.md`. Remaining POS-side work: add `max_offline_days` to
`LicenseClaims`, then swap `licenceServiceProvider` to `DefaultLicenceService`
with the real public key.
**Feature:** Licence issuance and activation endpoints

**Description:** A licence server that mints **Ed25519-signed** licence files and
exchanges a human-typed key for one. The client half is built and tested — see
`docs/pos/09-licensing.md` and `lib/features/licensing/`.

**Why POS needs it:** the POS currently self-signs a development licence at
runtime so the setup wizard is walkable. Nothing real can be issued, renewed or
revoked. On-premises tills in particular need a licence they can install from a
**file**, because they may never reach the internet.

**Existing API discovered:** none for licensing. Reusable *patterns*:
`restaurant_features` for per-tenant configuration, `PlanLimitService` for
limits, `AuditLogger` for the trail, `Plan` for what a licence should mirror.

**Suggested endpoints:**

| Method | Endpoint | Purpose |
|---|---|---|
| `POST` | `/api/pos/licence/activate` | exchange a key for a signed licence |
| `GET` | `/api/pos/licence/current` | latest licence for this tenant + terminal |
| `POST` | `/api/admin/licences` | Super Admin issues / renews / revokes |

**Suggested response:** the file format in `docs/pos/09-licensing.md` §3 —
`{payload, signature, key_id}`, payload base64url JSON.

**Design asks:**
- **Ed25519, detached signature, no `alg` field** — the algorithm is fixed in the
  client, so there is no `alg: none` class of bug.
- The signing private key never leaves the issuer. `key_id` allows rotation.
- Claims must include `modes[]` — a cloud licence need not cover a branch server.
- `grace_days` and `warn_days` are issuer-controlled, since the commercial
  posture belongs to you, not to the till.

**Permissions:** activation is unauthenticated by key (the key *is* the
credential); issuance is Super Admin.
**Tenant behaviour:** a licence names one tenant; the client refuses a mismatch.
**Offline requirements:** **the file must be verifiable with no network at all.**
This is the whole point.
**Idempotency:** re-activating the same key returns the same licence.
**Priority:** MEDIUM · **Blocking:** NO — the client runs on a development issuer.

---

## POS-BE-016

**Status:** APPROVED — contract agreed 2026-09-02, see `BACKEND_TO_POS.md`; implementation not started
**Feature:** Terminal registration against a licence (seat counting)

**Description:** Count terminals server-side, so `max_terminals` means something.

**Why POS needs it:** a fresh install cannot see its siblings, so the offline
check is **advisory and honestly documented as such**. Only a server can tell a
customer they are running six tills on a four-till licence.

**Existing API discovered:** none — but this pairs naturally with the
`pos_terminals` table already proposed in POS-BE-009, which would gain a
`licence_id` and a revocation flag.

**Suggested behaviour:** registering a terminal beyond the licensed count should
**warn, not refuse**. Refusing to register the sixth till mid-service is the
"brick a POS" failure mode all over again; a report to the owner is the right
lever.

**Priority:** MEDIUM · **Blocking:** NO

---

## POS-BE-017

**Status:** APPROVED — contract agreed 2026-09-02, see `BACKEND_TO_POS.md`; implementation not started
**Feature:** Branch-server packaging (on-premises deployment)

**Description:** A supported way to run `apps/api` on a box inside a restaurant,
serving the tills on its LAN. See `docs/pos/08-deployment-modes.md`.

**Why POS needs it:** the per-terminal offline queue solves **single-till**
outages. It does **not** solve **multi-till consistency** — two offline tills can
both seat the same table. A server inside the building is the only fix.

**Existing API discovered — and this is the encouraging part:**
`docker-compose.yml` (app + scheduler + web + `postgres:16-alpine`), `Dockerfile`,
`deploy.sh`, and `config/database.php` already supporting SQLite *and* pgsql.
**Agent 1's reading is that this is packaging, not new engineering** — but that
judgement is Agent 2's to make.

**What seems to be missing:** single-tenant provisioning for a box that holds one
restaurant; a backup routine (**the largest real risk** — a mini-PC under a
counter with no backup is how a restaurant loses a year of sales); an update
path; and licence distribution to the tills, so a six-till branch renews once
rather than six times.

**Open question for the owner, flagged rather than assumed:** Egypt ETA
e-receipt and Saudi ZATCA Phase 2 involve clearing receipts with the tax
authority. Agent 1 has **not** verified the current rules and is not competent to
— but if clearing is mandatory in a target market, it constrains on-premises more
than anything else in this document.

**Priority:** MEDIUM · **Blocking:** NO — the client supports the mode already.

---

## POS-BE-018

**Status:** APPROVED — contract agreed 2026-09-02, see `BACKEND_TO_POS.md`; implementation not started
**Feature:** Upstream sync — branch server → platform

**Description:** A branch server forwards its orders, payments, shifts and cash
movements to the hosted platform when the internet is available.

**Why POS needs it:** without it an on-premises restaurant has no cloud
dashboard and no QR menu, which the setup wizard makes the operator confirm
explicitly. Most customers will want both.

**Design ask:** reuse **exactly** the idempotency contract of POS-BE-007. The
branch server is just another client holding a queue of
`client_transaction_id`-keyed records — it should need no second mechanism.

**Priority:** MEDIUM · **Blocking:** NO

---

## POS-BE-019

**Status:** APPROVED — contract agreed 2026-09-02, see `BACKEND_TO_POS.md`; implementation not started
**Feature:** Machine-readable error codes on every `/api/pos/*` write

**Description:** Every 4xx from a POS write carries a stable
`{"code": "SNAKE_CASE", "message": "..."}` alongside the HTTP status.

**Why POS needs it:** the client's reaction to a failure differs completely by
cause, and the status code alone cannot distinguish them. A `403` today could
mean *the tenant does not have `feature:pos`*, *this cashier lacks
`pos.operate`*, *the subscription lapsed* (if D2 goes the other way), or *this
branch is not yours*. The queue must **hold and retry** for the first, **stop and
tell the manager** for the second, **hold and surface a billing banner** for the
third, and **quarantine that one record** for the fourth. Guessing from a status
code means either discarding money or retrying forever.

**Suggested minimum vocabulary:**

```
POS_FEATURE_DISABLED     POS_CAPABILITY_MISSING     SUBSCRIPTION_LAPSED
BRANCH_NOT_IN_TENANT     TERMINAL_REVOKED           SHIFT_NOT_OPEN
CATALOG_STALE            MENU_ITEM_NOT_FOUND        VALIDATION_FAILED
```

**Design ask:** the client switches on `code` and falls back to *retry later,
never discard* for any unrecognised value — so adding a new code can never brick
a till, and the list can grow freely.

**Priority:** HIGH · **Blocking:** NO — but the sync queue's retry policy is
guesswork without it, and a wrong guess is either lost money or an infinite loop.

---

## POS-BE-020

**Status:** APPROVED — contract agreed 2026-09-02, see `BACKEND_TO_POS.md`; implementation not started
**Feature:** Server time exposed, so a till can detect its own clock skew

**Description:** `GET /api/pos/config` returns `server_time` (ISO 8601, UTC), or
the API sets a `Date` header the client is allowed to rely on.

**Why POS needs it:** POS-BE-006 and POS-BE-009 both ask the server to trust
**client-supplied** `created_at` / `opened_at` / `occurred_at`, because an
offline order is genuinely hours old. That trust is only safe if the till can
tell when its own clock is wrong. A mini-PC under a counter that lost its RTC
battery will happily stamp an entire shift with last year's date, and nothing in
the current design would notice until the accountant did.

**Client behaviour:** on every config sync the POS compares its clock to
`server_time`. Beyond a threshold it shows a persistent diagnostics warning and
stamps outgoing records with the measured offset so the server can correct them.
It does **not** refuse to sell — a wrong clock is not a reason to stop trading.

**Design ask:** do **not** silently overwrite a client timestamp server-side.
Store both (`occurred_at` as sent, `received_at` as observed — which
`05-database-proposal.md` §C4 already does) and let reporting decide.

**Priority:** LOW · **Blocking:** NO

---

## POS-BE-021

**Status:** APPROVED — contract agreed 2026-09-02, see `BACKEND_TO_POS.md`; implementation not started
**Feature:** Bulk drain of a queued backlog

**Description:** A way to submit many queued POS records in one request after a
long outage, with **per-element** results.

**Why POS needs it:** a four-hour outage at a busy branch leaves a till holding
one to two hundred orders, each with payments. Draining that as sequential
`POST`s is hundreds of round trips over the connection that just came back —
slow, and every one of them a fresh chance to fail halfway.

**Suggested shape:** `POST /api/pos/sync` with `{"orders": [...],
"cash_movements": [...], "shifts": [...]}` returning `207`-style per-element
results keyed by `client_transaction_id`:

```jsonc
{ "results": [ { "client_transaction_id": "…", "status": "created",
                 "id": 8814, "invoice_number": "MAADI-2026-001042" },
               { "client_transaction_id": "…", "status": "duplicate", "id": 8813 },
               { "client_transaction_id": "…", "status": "rejected",
                 "code": "MENU_ITEM_NOT_FOUND" } ] }
```

**Design asks:**
- **One element failing must never fail the batch.** Partial success is the
  normal outcome; the client re-queues only what was rejected.
- Idempotency is **per element**, exactly as POS-BE-007 defines it — a replayed
  batch returns `duplicate` plus the same id and invoice number for the elements
  already stored, and creates the rest.
- Bound the batch size and say what the bound is, so the client chunks correctly
  rather than discovering a `413` in the field.
- If this is unwelcome, the fallback is fine: the POS drains serially with
  backoff. It is slower, not incorrect.

**Priority:** MEDIUM · **Blocking:** NO

---

## POS-BE-022

**Status:** APPROVED — contract agreed 2026-09-02, see `BACKEND_TO_POS.md`; implementation not started
**Feature:** Super Admin fleet registry + automatic terminal heartbeat

> **Owner requirement, 2026-08-26: every client must be trackable from Super
> Admin.** This entry exists because that requirement is not satisfiable by
> anything currently proposed, and because it removes a mode the client
> previously supported.

**Description:** Two halves.

1. **A platform-level view of every terminal**, across every tenant — the
   Super Admin counterpart to the tenant-scoped `pos_terminals` table already
   proposed in POS-BE-009.
2. **An automatic heartbeat** the till sends on its own schedule, *independent
   of the outbound sync queue and of the operator's sync policy*.

**Why POS needs it:** the owner's requirement is a hard constraint on the
deployment model, not a reporting nicety. Three consequences the POS cannot
resolve on its own:

- **A truly islanded terminal becomes unsupportable.** `DeploymentMode.standalone`
  and a branch server with `upstreamUrl == null` are both documented today as
  legitimate "no platform contact, ever" configurations. Neither can be tracked.
  Either the requirement or those configurations has to give, and the client
  assumes the requirement wins — see *Deployment consequences* below.
- **`last_seen_at` is worthless if it rides on the sync queue.** With manual
  sync, a till's last contact becomes a function of whether a cashier pressed a
  button. The heartbeat must therefore be its own small, automatic request —
  automatic **even when the operator has chosen manual sync**, because the
  operator is choosing when *money* moves, not whether the platform may know the
  till is alive.
- **A blocked queue must not silence a till.** If a rejected or stuck record
  could stop the heartbeat, the sickest terminals in the fleet go dark precisely
  when Super Admin most needs to see them. The heartbeat must succeed
  independently of queue state, and must carry no money.

**Suggested endpoints:**

| Method | Endpoint | Purpose |
|---|---|---|
| `POST` | `/api/pos/terminals/heartbeat` | small, frequent, automatic |
| `GET`  | `/api/admin/pos/terminals` | Super Admin, cross-tenant fleet list |
| `GET`  | `/api/admin/pos/terminals/{id}` | one terminal's detail + history |

**Suggested heartbeat payload** — deliberately tiny, and it never carries a sale:

```jsonc
{ "terminal_id": "…uuid…", "app_version": "1.4.2", "platform": "windows",
  "deployment_mode": "cloud", "sync_policy": "manual",
  "pending_count": 37, "oldest_pending_at": "2026-08-26T09:14:00Z",
  "shift_open": true, "licence_expires_at": "2026-12-31",
  "clock_offset_seconds": -4, "last_catalog_sync_at": "2026-08-26T08:02:00Z" }
```

**`pending_count` and `oldest_pending_at` are the two most valuable fields in
this document.** Together they are *unsynced money, per till, in real time* —
the number that tells Super Admin which restaurant is about to have a
reconciliation problem, before the restaurant knows it.

**Suggested Super Admin list columns:** restaurant · branch · terminal name ·
mode · sync policy · last seen · app version · pending count · oldest pending ·
licence status · shift open. Sortable by last seen and by pending count.

**Deployment consequences the client will adopt unless told otherwise:**

- `DeploymentMode.standalone` stops meaning *no server, ever* and starts meaning
  **islanded operation with a mandatory check-in window**. The till sells offline
  indefinitely; it must reach the platform within the licensed window or the
  **next** shift is blocked. Never the open one — the same rule that already
  governs licence expiry in `docs/pos/09-licensing.md`.
- **Reuse the licence for the window.** Claims already carry `grace_days` and
  `warn_days`; a `max_offline_days` claim alongside them is the whole mechanism.
  Please do not build a second enforcement path — one signed, offline-verifiable
  document deciding all of it is why the licensing design is simple.
- A branch server with **no upstream configured is no longer offered** by the
  setup wizard. `upstreamUrl` becomes required. This directly contradicts the
  current doc comment in `lib/core/config/deployment.dart` and both will be
  changed together.
- **There is no "online required" mode.** Owner decision, 2026-08-26: the POS is
  a desktop application, so every install has a disk and every install is
  offline-first. This removes a variant, not a capability — a terminal on a good
  connection is simply one whose queue is always empty. The consequence for the
  backend is that **no tenant is exempt** from POS-BE-008's provisional
  references, POS-BE-011, POS-BE-019, POS-BE-020 or POS-BE-021; they are
  universal, not per-SKU.
- **The catalog stays authored in the cloud dashboard — on a CLOUD terminal.**
  A Super Admin cannot meaningfully track a fleet whose tills each invented
  their own menu and prices, so a cloud till remains a reader: seeded from the
  platform and refreshed at each check-in, with `BootstrapSeeder` replacing its
  catalogue wholesale.

  **Narrowed 2026-09-06 (owner decision):** this rule binds the *cloud* product
  only. `DeploymentMode.offline` now authors its own menu, floor and money
  rules on the till, because an offline restaurant has no dashboard to author
  them in and no fleet for a Super Admin to track. The two are kept apart by
  construction rather than by convention — `catalogAdminRepositoryProvider`
  returns null outside offline, and `PostgresCatalogAdminRepository` refuses
  again on its own, so a cloud till cannot author even if something built one.
  There is still **exactly one author per deployment**, which is what the
  no-merge rule below actually depends on.

**Permissions:** heartbeat — `pos.operate` (or the terminal's own credential, if
POS-BE-011 lands as Option C). Fleet views — Super Admin `Capability`, not
`TenantCapability`.
**Tenant behaviour:** the heartbeat is tenant-scoped as every other POS write.
The **fleet views are deliberately cross-tenant** and are the one POS surface
that must escape `RestaurantScope` — please make that explicit and audited rather
than incidental.
**Offline requirements:** heartbeats are **not** queued and replayed. A missed
heartbeat is stale information, not lost money; sending a backlog of them on
reconnect would just be noise. Send the current state, discard the rest.
**Idempotency:** n/a — last write wins by design.
**Priority:** HIGH · **Blocking:** NO for selling, **YES** for shipping any
islanded or on-premises deployment.

**Amends:** POS-BE-016 (seat counting stops being advisory once every terminal
checks in — it can now be reported accurately, though the POS still asks that
exceeding the count **warn rather than refuse**) and POS-BE-017 (an islanded
branch server is withdrawn as an offered configuration).

---

## POS-BE-023

**Status:** APPROVED — contract agreed 2026-09-02, see `BACKEND_TO_POS.md`; implementation not started
**Feature:** Terminal provisioning from the dashboard + `GET /api/pos/bootstrap`

> **Owner requirement, 2026-08-26:** the terminal is created **in the dashboard**,
> and the desktop pulls its configuration, users and everything else down. Two
> setup paths: a provisioned one and a manual one.

**Description:** Invert the registration direction. Today's POS-BE-009 has the
till announce itself and the platform discover it. This entry has the **platform
provision the terminal first** and the till **claim** it.

**Why this is the answer to "how do we track an offline client":** because the
record exists before the terminal does. Tracking stops being best-effort
telemetry and becomes structural — the fleet list is a list of things Super Admin
*created*, and a till that never appears is visibly a till that never activated.
Three states, all meaningful:

| State | Meaning |
|---|---|
| `provisioned` | created in the dashboard, never claimed. A box that was ordered and never installed |
| `active` | claimed and checking in within its window |
| `stale` | claimed, then missed its check-in window (POS-BE-022) |

**Path A — provisioned (recommended default).**

1. Dashboard → *Settings → Terminals → Add terminal*: name, branch, deployment
   mode, sync policy. Creates the `pos_terminals` row in state `provisioned`.
2. The dashboard issues a **pairing code** — short, human-typable, single-use,
   short-lived.
3. The desktop wizard offers *"I have a setup code"*: operator types the tenant
   slug and the code. `POST /api/pos/terminals/claim` returns the terminal
   identity, a device credential and the full bootstrap bundle.

**Path B — manual.** Operator types base URL, tenant slug, username and password;
the till authenticates as that user, creates its own terminal row and pulls the
same bundle. This exists for an installer with no dashboard access, and for a
branch-server install where the dashboard is not reachable at setup time.

**A security recommendation on Path B, offered rather than assumed.** Path B as
requested puts a **restaurant admin's password** into every till, typically typed
by an installer, on a machine that stays in a public-facing room and may be
stolen. That credential also opens the web dashboard. Agent 1's recommendation is
that **Path A is the default and Path B the fallback**, and that Path B accepts
any staff account holding a `pos.provision` verb rather than requiring the owner.
A pairing code that dies in 24 hours is a much smaller thing to lose than the
owner's password. **Both paths are built either way — this is a default, not a
refusal.**

**Suggested endpoints:**

| Method | Endpoint | Purpose |
|---|---|---|
| `POST` | `/api/dashboard/pos/terminals` | provision (dashboard) |
| `POST` | `/api/dashboard/pos/terminals/{id}/pairing-code` | issue / regenerate a code |
| `DELETE` | `/api/dashboard/pos/terminals/{id}` | revoke (BE-A04) |
| `POST` | `/api/pos/terminals/claim` | desktop claims by code — **Path A** |
| `POST` | `/api/pos/terminals/register` | desktop self-registers — **Path B** |
| `GET` | `/api/pos/bootstrap` | everything this terminal needs, one document |

**The bootstrap bundle** — one call, one `synced_at`, one thing to invalidate.
This supersedes the separate `/api/pos/config` sketched in POS-BE-013:

```jsonc
{ "synced_at": "…", "server_time": "…",                    // POS-BE-020
  "terminal":  { "id", "name", "branch_id", "deployment_mode", "sync_policy" },
  "restaurant":{ "id", "name", "slug", "tax_registration_number",
                 "currency": "EGP", "exponent": 2 },        // POS-BE-013 / A7
  "branches":  [ { "id", "code", "name", "supported_order_types" } ],  // POS-BE-005
  "catalog":   { "categories": [], "items": [], "option_groups": [] }, // 003 / 004
  "money":     { "tax_rules": [], "charges": [], "tender_types": [] }, // POS-BE-013
  "staff":     [ { "id", "name", "username", "role_id",
                   "capabilities": [], "pin_hash": "…" } ],            // POS-BE-024
  "licence":   { "payload", "signature", "key_id" } }                  // POS-BE-015
```

**Design asks:**

- **The pairing code is a credential.** Hash it at rest, single-use, short TTL
  (24 h suggested), rate-limit `claim` the way `login` is already rate-limited per
  IP and per identifier, and never log it.
- The claim endpoint resolves the tenant **from the code**, never from request
  input — `TenantContext::overrideId()` released in a `finally`, following the
  existing public-path pattern.
- Claiming is **idempotent per code**: a claim that times out and retries returns
  the same terminal and the same device credential, not a second terminal.
- A revoked or already-claimed code fails with a distinct POS-BE-019 code, so the
  wizard can say *"this code was already used"* rather than *"invalid"*.
- **Claim and revoke are `AuditLogger::record()` events.** A terminal appearing in
  a restaurant is exactly the kind of thing an owner should find in the trail.
- Provisioning counts toward `max_terminals` only when **claimed**, so an owner
  can prepare next month's tills without buying seats early. Show provisioned
  rows in the fleet list regardless.

**This makes POS-BE-011 Option C the natural answer.** Claiming is the moment a
*device* credential can be issued, separate from the cashier's session. Agent 2's
D3 recommendation was "Option A now, Option C later, because building C first
means building it twice" — that reasoning weakens once provisioning exists,
because the issuance point now exists anyway. Agent 1 has no strong view; flagging
that the trade-off changed.

**Permissions:** dashboard endpoints — `feature:pos` + `settings.update` (or a
dedicated `pos.provision` verb, Agent 2's call). `claim` — unauthenticated by
code. `bootstrap` — the device credential, or `pos.operate`.
**Tenant behaviour:** standard. Note `User` has no `RestaurantScope`, so the
`staff` half of the bundle must be scoped by hand — `Dashboard\StaffController`
is the pattern.
**Offline requirements:** the bundle is the till's entire world for the length of
its check-in window. It must be complete enough that a terminal can open, sell,
authenticate cashiers and close a shift having never spoken to the server again.
**Idempotency:** per POS-BE-007 on `claim` and `register`.
**Priority:** HIGH · **Blocking:** YES for any install that is not hand-configured.

---

## POS-BE-024

**Status:** APPROVED — contract agreed 2026-09-02, see `BACKEND_TO_POS.md`; implementation not started
**Feature:** A POS PIN credential, distinct from the dashboard password

**Description:** A per-staff-member PIN, set in the dashboard, hashed, delivered
in the bootstrap bundle, and used **only** to unlock a till.

**Why POS needs it:** offline cashier sign-in is the hard requirement hiding
inside "pull all users". A till that must authenticate staff with no network has
to hold a verifier locally. If that verifier is the **dashboard password hash**,
then a till stolen from a restaurant is an offline brute-force rig against
credentials that also open the web dashboard, the menu, the customer list and the
reports — for every member of staff at once. The blast radius of a stolen till
should be *the till*.

**What Agent 1 asks for instead:**

- A separate `pos_pin_hash` on `users`, nullable, **never** in `$fillable`, set
  only through a trusted service — the same discipline `users.role` and
  `users.restaurant_id` already follow.
- **Never serialised by `UserResource`**, never returned by any dashboard
  endpoint. It appears in exactly one place: the bootstrap bundle, behind the
  device credential.
- Set and reset from the dashboard staff form. Write-only in the UI — the
  dashboard shows *"PIN set"*, never the PIN.
- Independently revocable: clearing the PIN locks that cashier out of every till
  at next sync without touching their dashboard access.
- A PIN is **not** a password. Rate-limit attempts on the till, lock after a
  small number of failures, and never let a PIN authenticate anything but a till.

**Client behaviour:** the POS verifies the PIN locally against the hash and
attributes the shift, the sale and the audit trail to that user id. Online, the
server re-attributes from the same id on sync — the PIN never travels.

**Permissions:** `staff.update` to set another user's PIN; a user may set their
own.
**Tenant behaviour:** tenant-scoped as all staff data.
**Offline requirements:** this request exists entirely for offline.
**Priority:** HIGH · **Blocking:** YES for offline operation with more than one
cashier.

---

## POS-BE-025

**Status:** APPROVED — contract agreed 2026-09-02, see `BACKEND_TO_POS.md`; implementation not started
**Feature:** Pre-auth tenant setup configuration — versioning and conditional fetch

> **Design document:** `docs/pos/10-setup-architecture.md` §6, §7.

**Description:** A configuration bundle a terminal can fetch **holding nothing at
all**, keyed on the tenant slug, plus a version endpoint cheap enough to poll.

### First: this is not a rival to POS-BE-023 — it is a second projection of it

`GET /api/pos/bootstrap` requires the device credential, which does not exist
before a terminal has claimed. This endpoint has to answer a machine that has
just been unboxed. **Same document, different auth, different moment in time.**
So please build it as a redacted sibling of the bootstrap bundle sharing one
`config_version` counter, not as a second source of truth that can disagree.

**Redacted means, precisely:**

- **no `staff` block at all** — therefore no `pos_pin_hash`, ever, on this path
- no device credential
- no `licence` object **unless** the licence is already bound to the
  `terminal_fingerprint` presented on the request
- rate-limited per IP **and** per slug, the way `login` and `licence/activate`
  already are

### Endpoints

| Method | Endpoint | Auth | Purpose |
|---|---|---|---|
| `GET` | `/api/pos/setup/config/{slug}` | none (rate-limited) | the redacted bundle |
| `GET` | `/api/pos/setup/config/{slug}/version` | none (rate-limited) | ~80 bytes, pollable |

```jsonc
// GET /api/pos/setup/config/{slug}/version
{ "config_version": 7, "last_updated_at": "2026-08-28T09:00:00Z",
  "server_time": "2026-08-28T09:00:01Z" }              // POS-BE-020, reused not reinvented
```

```jsonc
// GET /api/pos/setup/config/{slug}
{ "config_version": 7, "last_updated_at": "…", "server_time": "…",
  "tenant":   { "id", "slug", "name", "tax_registration_number",
                "currency": "EGP", "exponent": 2, "timezone", "default_language" },
  "branches": [ { "id", "code", "name", "supported_order_types" } ],   // POS-BE-005
  "endpoints":{ "base_url", "database_host", "database_name",
                "database_user", "database_port", "verify_tls" },
  "pos":      { "sync_policy", "service_charge_percent", "rounding",
                "invoice_prefix_source" },
  "modules":  ["pos", "kds"],
  "features": { "pos.split_tender": true },
  "printers": [ { "role", "transport", "host", "port", "copies" } ],
  "app":      { "lock_after_seconds", "shift_required" },
  "branding": { "display_name", "logo_url", "accent_hex" },
  "licence":  { "payload", "signature", "key_id" }     // only if fingerprint-bound
}
```

### Design asks

- **`config_version` must be a monotonically increasing integer per tenant, and
  must never be reused.** It is the client's *sole* precedence signal. The client
  accepts a bundle if and only if `incoming > cached`, and treats a lower value
  as a rollback to be refused rather than applied — see §16.7 of the design doc.
- `last_updated_at` and the ETag are **advisory**. The client will not let either
  decide precedence: an ETag dies the moment a bundle arrives by file or USB
  stick, and a timestamp comparison against a till with a wrong clock is how a
  stale configuration wins.
- Honour `If-None-Match` on the full GET → `304`. Emit `ETag` and
  `X-Config-Version` headers.
- **`modules[]` must never be emitted empty** — same trap as `modes[]` on
  POS-BE-015. The client reads an empty set as "everything", not "nothing",
  because the alternative is a till that will not configure with no way to say
  why.
- `currency` and `exponent` are **mandatory**. Hardcoding 100 is a bug for a
  Kuwaiti tenant and one the client cannot detect on its own (A7).
- The `money` block of POS-BE-013 belongs in **this** bundle rather than a
  separate `/api/pos/config`. One document, one version, one thing to invalidate.

**Errors** (POS-BE-019 vocabulary): `SETUP_SLUG_UNKNOWN` (404),
`SETUP_SLUG_SUSPENDED` (403), `SETUP_RATE_LIMITED` (429).

**Why a 404 must be honest:** the client treats two consecutive 404s as "the slug
was renamed", shows a banner and offers a field for the new one. It does
**nothing destructive** — the slug is not the terminal's identity, `restaurant_id`
is — so please do not return 404 for a transient outage.

**Permissions:** none, by design. **Tenant behaviour:** resolved from the slug.
**Offline requirements:** the client must survive this endpoint being
unreachable for the whole of setup; the wizard falls back to manual entry and
never blocks.
**Priority:** HIGH · **Blocking:** NO.

---

## POS-BE-026

**Status:** APPROVED — contract agreed 2026-09-02, see `BACKEND_TO_POS.md`; implementation not started
**Feature:** Site registration and `ServerId`

> **Design document:** `docs/pos/10-setup-architecture.md` §4, §9.

**Description:** A **site** is the box that hosts a branch's PostgreSQL and runs
the `apps/api` stack for it. It gets a `server_id` (uuid, minted locally by the
main device at setup) so the fleet registry can group terminals under the box
their data actually lives on.

**Why this is not just another terminal.** A main device whose disk dies gets
replaced. If the site's identity were the box's identity, every hardware failure
would become a licence support ticket — `max_terminals` would be counting against
a machine rather than against a restaurant. So `server_id` identifies the *site's
database* and `server_installation_id` records *which box currently hosts it*.
Replacing hardware then changes one column, not a licence.

| Method | Endpoint | Purpose |
|---|---|---|
| `POST` | `/api/pos/sites/register` | claim a site |
| `POST` | `/api/pos/sites/{server_id}/replace` | move a site to new hardware — audited |
| `GET` | `/api/admin/pos/sites` | Super Admin fleet view (cross-tenant, per POS-BE-022) |

```jsonc
// POST /api/pos/sites/register
{ "tenant_slug", "branch_id", "server_id", "server_installation_id",
  "app_version", "platform": "macos" }
→ { "site": { "server_id", "branch_id", "registered_at" },
    "allowed_terminal_count": 4 }
```

**Design asks:**

- **Idempotent on `(restaurant_id, branch_id, server_id)`.** A registration that
  times out and retries returns the same site, not a second one.
- A second call with a *different* `server_id` for the same branch returns
  `SITE_ALREADY_REGISTERED` **carrying the existing id**, so the wizard can say
  *"this branch already has a main device at …"* rather than *"conflict"*.
  Replacing a main device is a deliberate, audited act via the `replace`
  endpoint — never an accident of retyping.
- **Registration is not required for a site to work.** An offline restaurant with
  no uplink at install time must still finish setup; it registers at first
  contact. Please do not make this a precondition for anything.
- `AuditLogger::record()` on register and replace, same posture as POS-BE-023's
  claim/revoke.

**Relates to:** POS-BE-022 — the fleet registry gains a **site** tier above
terminals, so a branch's tills are grouped under the box hosting their database.
POS-BE-016 — a site is the natural unit to count seats against, since the
terminals sharing one database are exactly the ones a `max_terminals` claim is
about.

**Permissions:** `register` — unauthenticated, resolved from slug + branch, rate
limited (it is only useful to someone already inside the restaurant's LAN);
`replace` — `settings.update`; admin reads — SUPER_ADMIN.
**Priority:** MEDIUM · **Blocking:** NO — a site works unregistered, it is simply
not visible to Super Admin as a site.

---

## POS-BE-027

**Status:** APPROVED — contract agreed 2026-09-02, see `BACKEND_TO_POS.md`; implementation not started — **this amends POS-BE-015, which is `READY`**
**Feature:** Three additive licence claims — offline window, site pin, claims version

> **Design document:** `docs/pos/10-setup-architecture.md` §13.

**Description:** Three keys added to the existing signed payload. Nothing else
about POS-BE-015 changes.

| Claim | Key | Type | Absent → | Note |
|---|---|---|---|---|
| Offline window | `max_offline_days` | int, nullable | `null` = unlimited | **The server already stores and emits this**; the client has simply never read it. Listed as an outstanding client gap in the POS-BE-015 contract |
| Claims version | `license_version` | int | `1` | Schema version of the claims object — **not** a generation counter |
| Site pin | `server_id` | string, nullable | `null` = not site-pinned | Same semantics as an empty `fingerprints[]` |

**No licence needs re-signing, and none may be invalidated.** The signature
covers the payload bytes; this change only *reads more of them*. Every default
reproduces today's behaviour exactly — the same tolerance `fromJson` already
applies to `grace_days`, `warn_days` and `max_terminals`.

**Client behaviour, so the semantics are agreed before either side builds:**

- `max_offline_days` elapsed since last platform contact →
  `LicenseState.offlineWindowExpired`, whose entitlement is **byte-identical to
  `expired`**: the next shift cannot open, the open one is never cut off, and
  cash-up, reprint and export are never gated. This is the single mechanism
  POS-BE-022 asked for, and it needs no second enforcement path.
- `server_id` present and not this site's → `LicenseState.siteMismatch`.
- `license_version` greater than the client understands → **evaluate what is
  understood and attach a notice; never deny.** Refusing would brick a till
  holding a licence issued for a newer build, which inverts the cardinal rule.

**Explicitly declining a separate "offline certificate".** The requirement that
prompted this work asked for a second signed document carrying LicenseId,
TenantId, BranchId, ServerId, AllowedTerminalCount, EnabledModules, IssuedAt,
ExpiresAt and LicenseVersion. Seven of those nine are already claims on the
licence; these three additions cover the rest. Building a second document
contradicts POS-BE-022's own instruction — *"please do not build a second
enforcement path"* — and would mean two expiry dates to reconcile, two
revocation paths, and a support call that opens with "which one is wrong".
**Flagged as a documented disagreement, not a silent substitution.**

**Priority:** MEDIUM · **Blocking:** NO — the client ships against self-signed
fixtures until this lands.

---

## POS-BE-028

**Status:** APPROVED — contract agreed 2026-09-02, see `BACKEND_TO_POS.md`; implementation not started
**Feature:** Terminal display-name update, decoupled from identity

**Description:** `PATCH /api/pos/terminals/{terminal_id}` `{"name": "Bar 2"}` →
`200`.

**Why it is worth an entry of its own.** "The display name is never a security
identity" has to be true on *both* sides, not just in the client. Today a till's
name is chosen at setup and there is no way to change it without re-registering —
which pushes operators toward re-registering a terminal to rename it, and that
is exactly the act that breaks `terminal_id` continuity and orphans the shift
and order history hanging off it.

**Design asks:** the name is free text, trimmed, non-empty, unique per branch
only as a *warning* rather than a constraint (two tills called "Bar" is untidy,
not an error). Renaming never touches `terminal_id`, `server_id` or any
credential. `AuditLogger::record()`, because a till changing name in a restaurant
is worth finding in the trail.

**Errors:** `TERMINAL_NAME_INVALID`.
**Permissions:** `settings.update`, or the device credential for its own row.
**Priority:** LOW · **Blocking:** NO.

---

## POS-BE-029

**Status:** PROPOSED — filed 2026-09-10. Client built against this text and tested against a fake HTTP layer (`lib/data/cloud/branch_sales_api.dart`); no backend work exists. **Amended 2026-09-11:** payment kinds are the platform's POS-BE-013 vocabulary (rule 3).
**Feature:** The branch view on a cloud till — its own branch, every terminal summed and broken out

**Description:** Two reads, both scoped to the branch of the terminal whose
device token makes the request:

- `GET /api/pos/branch/sales/summary?business_day=YYYY-MM-DD&acting_user_id=9`
  → one row per terminal of the branch, **zeros included**, for that business day.
- `GET /api/pos/branch/sales?terminal_id=<uuid>&business_day=YYYY-MM-DD&acting_user_id=9`
  → that terminal's sales for the day, for drill-down.

**Why it is worth an entry of its own.** Owner decision, 2026-09-10: a cloud
till shows its own branch — the summary and the per-terminal breakdown
(`docs/pos/17-sales-and-payments-plan.md` §3a, §6 C4). Where a branch's tills
share one LAN database the till answers that locally and needs nothing from
the platform. Where each till has its own database, the till holds only its own
sales, and the platform is the only place the branch exists as a whole.

**Scope — the rule `GET /shifts/{id}/report` already follows.** Device token
+ `feature:pos` + `pos.reports` on `acting_user_id` (the till's
`reports.view`; `permissions.dart` maps one to the other). There is **no
`branch_id` parameter**: the branch is the requesting terminal's, so there is
nothing to tamper with. A `terminal_id` outside that branch, or unknown →
`404`, regardless of the user's capability — the no-existence-leak rule from
§009's "Report scoping". This stays a branch read and must never become a
cross-branch dashboard; that is C3's job, on the web.

**Rules the numbers must keep** (§3a, binding on both sides):

1. The branch total is the sum of the terminal rows — one query, `GROUP BY`
   terminal. The client **derives** its totals from `terminals[]` and only
   checks `totals` against them; a disagreement is flagged, not shown.
2. Every terminal of the branch is listed, including one with no sales, and a
   revoked terminal that took money that day. `last_received_at` is what lets
   a manager see a till that stopped syncing.
3. Payments by method carry the tender's `kind` and the payment's
   `counts_as_cash`. The kind is the **platform's** tender kind —
   `cash | card | external | other`, the POS-BE-013 vocabulary a cloud till
   seeds its tenders from — never the till's own. Cash = `counts_as_cash`,
   whatever the kind. Otherwise card / electronic = `card` and `external` (a
   card on the bank's own terminal: electronic is the figure held against the
   bank's settlement slip); `other` is collected, beside vouchers. There is
   **no `account` kind**, so nothing here is owed rather than collected.
   Adding one — or any fifth kind — is a POS-BE-013 contract change first: a
   client that has not heard of a kind reads it as `other`, i.e. as takings.
4. A refund belongs to the terminal that **issued** it, in the business day it
   was issued — not the original sale's terminal or day.
5. Net = gross − discounts − refunds, where gross is **before** discounts
   (`total_minor + discount_minor` in the till's terms).

Settled sales only: voided, cancelled and still-open orders are not sales.

**Summary response `200`:**

```jsonc
{ "data": {
    "branch_id": 3, "business_day": "2026-09-10",
    "currency": "EGP", "exponent": 2,
    "generated_at": "2026-09-10T21:00:04Z",
    "terminals": [
      { "terminal_id": "uuid", "name": "POS-01",
        "orders": 2, "gross_minor": 67345, "discount_minor": 5000,
        "refund_minor": 0, "refund_count": 0, "net_minor": 62345,
        "last_received_at": "2026-09-10T20:58:11Z",
        // tender_type_id is the platform's — what the till sent as
        // payments[].tender_type_id (POS-BE-013).
        "payments": [
          { "tender_type_id": 1, "label": "Cash", "kind": "cash",
            "counts_as_cash": true, "count": 1, "amount_minor": 30000 },
          { "tender_type_id": 3, "label": "Card (bank terminal)",
            "kind": "external", "counts_as_cash": false, "count": 1,
            "amount_minor": 12345 } ] },
      { "terminal_id": "uuid", "name": "POS-03",
        "orders": 0, "gross_minor": 0, "discount_minor": 0,
        "refund_minor": 0, "refund_count": 0, "net_minor": 0,
        "last_received_at": null, "payments": [] } ],
    "totals": { "orders": 2, "gross_minor": 67345, "discount_minor": 5000,
                "refund_minor": 0, "net_minor": 62345 } } }
```

**Drill-down response `200`:**

```jsonc
{ "data": [
    { "id": 8814, "client_transaction_id": "uuid",
      "invoice_number": "MANS-2026-000042", "settlement_status": "PAID",
      "created_at": "2026-09-10T13:05:00+02:00",
      "total_minor": 30000, "discount_minor": 1000, "refunded_minor": 0,
      "acting_user_id": 9 } ],
  "meta": { "terminal_id": "uuid", "business_day": "2026-09-10",
            "currency": "EGP", "exponent": 2 } }
```

Without `pos.order_view_all` on `acting_user_id`, only that user's own sales
are listed — the till's S1 rule, applied where the rows are.

**Open question — the platform needs each sale's business day.** §006 carries
only `created_at`, and a trading day that runs past midnight is not a calendar
date. Proposed: an optional `business_day` (`YYYY-MM-DD`) on §006 and §010
requests, additive; until the till sends it, the platform derives it from
`created_at` and the branch's day boundary and **says which it did** in the
response. The till does not yet stamp a business day on its own sales rows
(recorded in the plan's §6 C4), so this is not a field the client can fill
today — flagged now so the two land together.

**Client behaviour, so the semantics are agreed before either side builds:**

- A `200` naming another `branch_id`, another `business_day`, or carrying a
  money figure that is not an integer is refused as unreadable — never shown,
  never rounded (POS-BE-007).
- When a refresh fails, the till shows the last snapshot it did read, labelled
  with the time it read it. Never silently stale.
- The till's own not-yet-synced sales are counted in a banner and **never
  added** to these figures — adding them would double-count each one the moment
  it syncs.

**Errors:** `401 DEVICE_TOKEN_INVALID` · `403 POS_FEATURE_DISABLED /
POS_CAPABILITY_MISSING / TERMINAL_REVOKED` · `404` terminal not in the
requesting branch · `422 VALIDATION_FAILED` (malformed `business_day`).
**Priority:** MEDIUM · **Blocking:** NO — shared-database branches need nothing
from the platform; only per-till cloud branches wait on this.

---

## POS-BE-030

**Status:** APPROVED — filed 2026-09-13; owner go "finish all phases" (CB-09). Built on both sides, neither merged nor deployed:
- till side: `feat/cb-09-slice-e` @ `1adb17f` in xorder-pos, branched from `pos/offline-solid`;
- platform side: CB-09 slice a, `dd9a530` on `feat/cb-09-purchasing` in xorder-new — the `PosBootstrapService::staff()` filter.

**Feature:** Purchasing and stock on a cloud terminal are platform-authored

**Description:** On a terminal whose deployment is `cloud`, the platform is the
only author of suppliers, purchase orders, receiving, supplier invoices,
supplier payments, units and stock items. The till does not show its
Purchasing, Items, Stock or Units panes on cloud, **whatever capabilities the
signed-in person holds** — including a grant from a till-local role or a direct
grant. Offline terminals are unchanged.

**Why it is worth an entry of its own.** Owner decision 2026-09-12 (CB-09 D1):
one author per row. The panes are hidden by deployment mode rather than by
capability, because roles are the till's own even on cloud (doc 16 §1). A local
Owner or Manager role still grants `purchase.manage`, so a capability gate
alone would leak exactly the panes this closes.

**Bundle.** No new key. `staff[].capabilities` in a bundle **never contains
`purchase.manage`**, even for the owner, even though the platform's
TenantCapability of that name exists and is held on the dashboard. A till that
finds it there anyway, from an older platform, ignores it on cloud under the
rule above.

**Existing rows.** Till-local purchasing, supplier, unit and stock rows already
on a cloud terminal are not deleted, not imported and not synced. They remain
in the till's backups.

**Sync.** Nothing in POS-BE-006/009/021 changes. The platform derives nothing
from till purchasing. A supplier payment made out of a cloud terminal's drawer
is recorded at the till as a `pay_out` cash movement (POS-BE-009, unchanged).
The dashboard may link a supplier payment to that synced movement; that is
platform-side only, with no wire change.

**Till behaviour (built).** The four panes join Menu and Floor in
`_authoringPanes`, and the rail, the Manage menu (`managementBarFor`) and deep
links all follow it. On cloud the bar keeps a Buying entry with one line
pointing to the xorder.io dashboard. A deep link to any of the four lands on the
back office's first pane with the same sentence, in EN and AR. Tested: a cloud
till where `purchase.manage` comes from a local role or a direct grant shows
none of the four.

**Errors:** none. **Permissions:** none new.
**Priority:** LOW · **Blocking:** NO — the platform's bundle filter already
protects older till builds.

---

## Amendment to POS-BE-022 — please specify the heartbeat *response*

**This is the highest-leverage single item in the whole request set, and it costs
one response body.**

POS-BE-022 specifies a heartbeat request and says nothing about what comes back.
Specifying it collapses three client polling loops into one:

```jsonc
{ "server_time": "2026-08-28T09:00:01Z",   // → clock-skew probe   (POS-BE-020)
  "site_last_contact_at": "…",             // → max_offline_days window
  "licence_expires_at": "…",               // → renewal banner without a second call
  "config_version": 7,                     // → replaces polling POS-BE-025's /version
  "terminal_status": "active" }            // → active | stale | revoked (BE-A04)
```

With this, a till that heartbeats does not also need to poll the config version
endpoint, does not need a separate time source, and learns it has been revoked
without a dedicated call. Without it, the client runs three schedules where one
would do.

`terminal_status: "revoked"` is handled under the BE-A04 rule already agreed:
refuse the next sign-in and the next shift, never cut off the open one, and keep
accepting queued records for drain.

---

## Amendment to POS-BE-023 — add a pre-auth projection

See **POS-BE-025**. In short: keep `GET /api/pos/bootstrap` exactly as
specified, and add `GET /api/pos/setup/config/{slug}` as a redacted,
unauthenticated sibling sharing the same `config_version`. The authenticated
bundle stays the complete document; the pre-auth one exists because a machine
that has not yet claimed has no credential to present.

---

## Additions to the POS-BE-019 error vocabulary

```
SETUP_SLUG_UNKNOWN        SETUP_SLUG_SUSPENDED      SETUP_RATE_LIMITED
CONFIG_VERSION_STALE      SITE_ALREADY_REGISTERED   SITE_NOT_FOUND
TERMINAL_NAME_INVALID     LICENCE_SITE_MISMATCH
```

Same rule as everywhere else in this channel: **an unrecognised code is retried,
never discarded.** The client will not infer meaning from an HTTP status alone.

---

## Replies to `BACKEND_TO_POS.md` — 2026-08-26

Agent 2's analysis is accepted almost in full. Recorded here so the channel keeps
the whole conversation. **Nothing below authorises backend code.**

### Accepted with no further comment

**A1** (capability strings) — flattened names adopted, `pos.operate` treated as
the view-equivalent. The client stores them opaquely and gates UI on
`capabilities[]`; it hardcodes no implication rules of its own.
**A2** (`unique(restaurant_id, barcode, deleted_at)`) — no client impact; item
authoring lives in the web dashboard, not the till.
**A3** (expected-cash formula confirmed) — building against it. If a `payouts`
concept is added later, please deliver it as another `pos_cash_movements` reason
rather than a new term, and the client needs no change at all.
**A5** (tombstone gap) — accepted, and the fallback is the right one. Please name
the flag (`complete: false` assumed) and say whether it sits on the catalog
envelope or per collection; the POS will do a full pull for option groups
whenever it is false.
**BE-A03** — endorsed, same point.
**BE-A05** (`ReportService` matching by name) — endorsed; not a POS concern, but
it is a real defect and `menu_item_id` fixes it for the existing QR product.

### A4 — `settlement_status` derived, `OrderStatus` untouched: agreed, with one requirement

The right call. Two client-side conditions:

1. The field must appear on the **POS order response**, not only on the dashboard
   `OrderResource`. The till prints and reprints from what it gets back.
2. An unrecognised value must be safe. Per the client's never-throw rule the POS
   will render an unknown settlement status as **unknown — neither paid nor
   unpaid** and will **not** gate any action on it. It deliberately will *not*
   fall back to `UNPAID`, because a paid bill silently displayed as unpaid is how
   a customer gets charged twice.

### A6 — `subscription.writable`: agreed, and here is the client cost either way

The POS has no commercial opinion and defers to the owner (D2). Whichever way it
goes, the queue is never discarded. If the owner **does** decide a lapsed plan
blocks POS writes, the POS needs `SUBSCRIPTION_LAPSED` as a distinct code
(POS-BE-019) — otherwise a lapsed tenant is indistinguishable from a permission
error, and the till would tell a cashier they lack permission while a paid,
unsynced order sits in the queue.

### A7 — money representation: endorsed, plus the one thing that matters regardless

Integer minor units on new POS tables, `orders.total` keeping its decimal
projection, is exactly right. Two conditions that hold **even if the owner picks
decimal strings instead**:

1. **Never a JSON float.** String or integer, not `1338.68` as a number.
2. The **currency code and exponent must be discoverable**, not assumed.
   `GET /api/pos/config` should return `{"currency": "KWD", "exponent": 3}`.
   `Money` already carries an exponent for this reason — hardcoding 100 is a bug
   for a Kuwaiti tenant, and it is a bug the client cannot detect on its own.

Filed as an addendum to POS-BE-013 rather than a new item.

### BE-A01 — `order_payments` as its own table: **accepted, and it is the best correction in the reply**

Agent 2 is right and the POS request set was wrong to carry payments implicitly.
Split tender is the normal case; the client already models `Ticket.tenders` as a
list. Accepting the table costs the client almost nothing today and would have
cost a schema migration later.

**One contract question that decides a small client change.** Is a payment row
deduplicated by its own key, or by the order envelope's?

- If **payments are children of the order envelope** and only
  `orders.client_transaction_id` is the key, the client needs no change: replay
  the envelope, get the whole thing back.
- If **each payment row carries its own `client_transaction_id`** (as §C4
  proposes), the POS must generate a UUID **per tender at the moment it is
  added**, not at sync time — `Tender` currently has no such field.

**POS recommendation: both.** The envelope key for order creation, and a
per-payment key because paying an open bill in a second request is a real till
flow (seat the party, fire two rounds, settle at the end — possibly from a
different terminal). If Agent 2 confirms per-row keys, the client adds
`Tender.clientId` and generates it in `TicketEngine.addTender`. Say the word and
it is a one-commit change on this side, done before the endpoint exists.

### BE-A02 — per-user branch scoping: no POS dependency, one request if it is skipped

The till does not need `users.branch_id` to work — branch is a property of the
machine (`TerminalProfile`), chosen at setup, and survives a cashier change. So
this is the owner's call on cash visibility, not a POS blocker.

The one ask either way: **`GET /api/pos/shifts/{id}/report` should scope to the
requesting terminal's branch by default.** A cashier pressing the report key
should not be able to read another branch's cash position by accident, even if
the underlying permission would allow it.

### BE-A04 — terminal revocation: wanted, with the till's governing rule attached

Please build it, and please build it so it **cannot brick a till mid-service**,
the same rule that governs licensing:

- A revoked terminal is refused a **new sign-in** and refused **opening the next
  shift**.
- A revoked terminal's **open shift keeps running**, and its **queued records are
  still accepted for drain**. Rejecting a queued order because the device was
  later revoked destroys money that has already been taken from a customer —
  revocation must stop *future* trade, never erase *past* trade.
- Client behaviour: `TERMINAL_REVOKED` (POS-BE-019) on a drain response is
  displayed to the manager and the record is retried, never dropped.

### The approval slice the POS would pick

If the owner approves one thing: **T0.2, `order_items.menu_item_id`.** It is the
prerequisite for POS-BE-006, it independently fixes BE-A05 for the live QR
product, and it is additive to a production table with no behaviour change.

If the owner approves one wave: **Wave 0.** Six items, all additive, all valuable
to the existing product on their own, none of them requiring the POS to exist.

The POS stays entirely on fakes until an item appears in `BACKEND_TO_POS.md` as
`READY`, and nothing here changes that.

---


## Note to Agent 2 — 2026-08-26: branch-server deployments now write SQL directly

The owner has directed that on a **branch-server** deployment the till writes
orders straight to the branch box's PostgreSQL rather than over HTTP, with every
access behind the existing repository contracts so it can be swapped back later.
Implemented in `lib/data/postgres/`.

**This does not withdraw any request.** Three things change what "blocking" means
for a branch-server tenant, and nothing at all for a cloud tenant:

* **`POS-BE-007` (idempotency)** is satisfied locally by
  `UNIQUE (restaurant_id, client_transaction_id)`, and **`POS-BE-008` (invoice
  sequence)** by a `FOR UPDATE` row lock — both verified against a real
  PostgreSQL. The server-side contracts are still wanted, unchanged, for cloud
  tenants and for the upstream sync in `POS-BE-018`, which must dedupe on the
  same key.
* **`POS-BE-006` (server-priced orders)** stays the blocking request. Pricing is
  currently local, which is defensible for a pure `TicketEngine` but is not
  centrally auditable.
* **`POS-BE-022` (heartbeat + fleet registry) is unaffected and still needed.**
  Only the money path uses SQL; the heartbeat, licence refresh and provisioning
  still travel over HTTP to the same box, which forwards upstream.

Agent 1 asks only that the eventual server schema keep the shapes already agreed
— integer minor units, `payments[]` as rows per **BE-A01**, and the same
`client_transaction_id` key — so a branch database and the platform do not
diverge.

## Replies to `BACKEND_TO_POS.md` — 2026-09-02: contracts closed

The owner directed both agents to agree the contract for everything. Agent 2
rewrote `BACKEND_TO_POS.md` as the full agreed-contract document (every item
`APPROVED`, POS-BE-015 `READY`), answered every open question (a–l), and raised
five disagreements/counter-proposals. Agent 1's responses, all recorded in that
file too:

- **DIS-1 (no `database_*` pre-auth) — accepted.** The database block moves to
  the authenticated bootstrap; the wizard's manual-entry fallback covers the
  branch-server edge. `docs/pos/10-setup-architecture.md` §6/§7 will be updated
  to match (client-side doc task).
- **DIS-2 (`licence_ref` required on `sites/register`) — accepted**, with one
  fix Agent 1 requested and Agent 2 applied: the register ref check fails with
  a new uppercase `LICENCE_TENANT_MISMATCH`, distinct from
  `LICENCE_SITE_MISMATCH` (which is solely the `server_id` claim mismatch).
  §019, §026 and DIS-2 now agree.
- **DIS-3 (separate offline certificate) — jointly declined** by both agents;
  it remains on the owner's desk.
- **DIS-4 (grandfathered lowercase licence codes) — accepted.** The client's
  code-switch tables carry both casings knowingly, including the deliberate
  case-only collision between `licence_tenant_mismatch` (activation, shipped)
  and `LICENCE_TENANT_MISMATCH` (site register, new).
- **DIS-5 (`POST /api/pos/orders/{id}/payments`) — accepted and welcomed**;
  it is the endpoint the settle-later flow needs.

**Client-side commitments this agreement creates (Agent 1's backlog):**

1. `Tender.clientId` — generated in `TicketEngine.addTender` at the moment the
   tender is added, never at sync time (BE-A01 per-payment idempotency key).
2. Update `docs/pos/10-setup-architecture.md` for DIS-1 (no `database_*` in the
   pre-auth bundle) and the final claim/bootstrap shapes in §023.
3. Carry both casings of the licence error codes in the sync-queue switch
   tables; unrecognised codes stay retry-never-discard.
4. Device token: persist `xdt_…` with the `TerminalProfile`, honour the 24 h
   rotation overlap; PIN verify is bcrypt (`$2y$`, cost 10) locally.
5. Chunk the drain at 100 elements per `POST /api/pos/sync` request.
6. Full-pull exactly the catalog collections whose delta response carries
   `complete: false`.

Nothing here authorises backend implementation; each item still needs the
owner's explicit go to move `APPROVED → IN_PROGRESS`.

---

## Change log

| Date | Change |
|---|---|
| 2026-08-25 | Initial request set POS-BE-001 … POS-BE-014 raised by Agent 1 as `PROPOSED`. No backend code touched. |
| 2026-08-26 | POS-BE-015 … POS-BE-018 raised for licensing and on-premises deployment. Client-side deployment modes, licensing and the setup wizard are built and tested against fakes; no backend code touched. |
| 2026-08-26 | Replies to `BACKEND_TO_POS.md` (A1–A7, BE-A01–BE-A05) recorded. POS-BE-019 … POS-BE-021 raised: error taxonomy, server time, bulk drain. No backend code touched. |
| 2026-08-26 | Owner requirement: every client trackable from Super Admin. POS-BE-022 raised; islanded deployments withdrawn; local catalog authoring ruled out. |
| 2026-08-26 | Owner decision: no cloud-only mode — the POS is desktop-only and therefore offline-first everywhere. Sync policy reduces to `dynamic` / `manual`. |
| 2026-08-26 | POS-BE-023 / 024 raised: dashboard-provisioned terminals with a pairing-code claim, a single bootstrap bundle, and a POS PIN separate from the dashboard password. |
| 2026-08-26 | Owner directed direct PostgreSQL access on branch-server deployments; implemented behind the repository contracts. No request withdrawn — see the note above the change log. |
| 2026-08-26 | Owner decision **D6**: a licence is its own per-client record, issued from the Super Admin dashboard — not derived from the subscription. POS-BE-015 contract frozen in `BACKEND_TO_POS.md` (table, endpoints, wire shape, claims mapping). Two client-side gaps recorded: `max_offline_days` is not yet read by `LicenseClaims`, and `modes[]` must never be emitted empty. No code written on either side. |
| 2026-08-26 | POS-BE-015 **implemented**: `pos_licences`, Ed25519 issuance, key activation, renewal-supersedes-in-place, revocation, `.xlic` download, `licences.manage` (SUPER_ADMIN only), 14 feature tests green. Super Admin screens shipped at `/pos/licences`. POS client still on `FakeLicenceService` pending the `max_offline_days` claim and the real public key. |
| 2026-08-28 | **Client gap closed:** `LicenseClaims` now reads `max_offline_days` and `license_version`, tolerantly — absent, null or wrongly typed all fall back to the safe default, because a throw here becomes `LicenceFileDamaged` and refuses trade. No existing licence needs re-signing; proven by a signed fixture in `test/features/licensing_test.dart`. The window is **parsed but not yet enforced**, pending a durable last-contact timestamp. `licenceServiceProvider` was already on `DefaultLicenceService` — the earlier note saying otherwise was stale. **Still outstanding: the real Ed25519 public key**, which only the issuer can produce. |
| 2026-08-28 | Setup architecture designed end to end — `docs/pos/10-setup-architecture.md`. POS-BE-025 … POS-BE-028 raised: pre-auth tenant config by slug with a monotonic `config_version`, site registration and `ServerId`, three additive licence claims, terminal rename. Amendments requested to POS-BE-023 (a redacted pre-auth projection of the bootstrap bundle) and POS-BE-022 (specify the heartbeat *response*, which collapses three client polling loops into one). A separate "offline certificate" was requested by the owner and **declined** in favour of three claims on the existing licence — recorded as a disagreement in POS-BE-027, not a silent substitution. Design only; no client or backend code written. |
| 2026-09-02 | **Contracts closed.** Owner directed full contract agreement. Agent 2 assessed every item and rewrote `BACKEND_TO_POS.md` as the agreed-contract document: POS-BE-001…028 all `APPROVED` (015 `READY`), open questions a–l decided (dual idempotency keys, per-collection `complete` flag, heartbeat response as proposed, **POS-BE-011 resolved as Option C** device token, batch bound 100, PIN hash bcrypt cost 10, canonical §019 error list). Agent 1 accepted DIS-1…DIS-5; `LICENCE_TENANT_MISMATCH` split from `LICENCE_SITE_MISMATCH`. Statuses here flipped to `APPROVED`; client backlog recorded above. **No code written on either side.** |
| 2026-09-04 | **Cloud Wave 1 integrated and smoke-verified end-to-end.** Owner go: "make the POS work with cloud for now". Client side shipped in `lib/data/cloud/`: `PosCloudApi`, tolerant `BootstrapBundle` parser, `BootstrapSeeder` (bundle → local PostgreSQL, platform ids verbatim, staff deactivated never deleted), `OutboxDrain` (§006 requests, per-payment uuid-v5 keys, quarantine-vs-defer per §019, delivery bookkeeping in migration 6), `CloudSync` (heartbeat → config-version reseed → drain; automatic timer + kick-on-sale + sync-pill manual), `DeviceTokenVault` (keychain), cloud `ProvisioningRepository` (Path A claim + Path B login/register). Backend Wave 1 implemented in `apps/api` (see `BACKEND_TO_POS.md` and `docs/backend/CLOUD_WAVE1_PROGRESS.md`). **Live smoke against `php artisan serve`: claim → bootstrap (frozen key map, 0 products dropped by the real parser) → server-priced order `201` with invoice `MAIN-2026-000001` → replay `200` same id+invoice → recovery → heartbeat → error envelope. All passed.** Client suites green (247); backend green (721). |
| 2026-09-06 | Owner decision: **`DeploymentMode.offline` is buildable, and authors its own world.** The two phase-1 blocks are removed and the wizard offers whichever modes the licence covers. An offline till can create its own database from the wizard (admin credential used once, never stored), and its Management section gains Menu, Floor and Money panes writing `pos_categories` / `pos_products` / `pos_dining_tables` / `pos_money_config` with the same audited-write discipline as staff and roles. **The 2026-08-26 ruling above is narrowed, not reversed:** local authoring is refused on cloud terminals in both the provider and the repository, so every deployment still has exactly one author and no merge path is needed. Back-office writes also move onto a second database role, asked for when Management opens and held in memory only — `bin/pos_migrate.dart` always refused to grant both role sets to one role, and the app now honours that instead of running Management as `pos_till`. No backend contract changed. |
| 2026-09-10 | POS-BE-029 raised: the branch view on a cloud till whose database is its own — `GET /api/pos/branch/sales/summary` and `GET /api/pos/branch/sales`, device token + `pos.reports`, the requesting terminal's branch only (404 otherwise). Open question recorded: the platform needs each sale's business day, which §006 does not carry. Client built against the text in `lib/data/cloud/branch_sales_api.dart`, tested against a fake HTTP layer; no backend code touched. |
| 2026-09-11 | **CB-00 — the two repos' copies reconciled** (`xorder-cloud`, docs only). The xorder-pos copy (2026-09-11) was a strict superset of the xorder-new copy (2026-09-04) except one passage: the "catalog stays authored in the cloud dashboard" bullet under the 2026-08-26 deployment consequences. xorder-new still had the original 2026-08-26 wording ("local catalog authoring on the till is now explicitly *out* of scope"); xorder-pos had the 2026-09-06 owner narrowing ("— on a CLOUD terminal", offline authors its own world). **The later-dated 2026-09-06 text is kept.** Carried into xorder-new: that narrowing, the whole POS-BE-029 entry and its summary row, and the 2026-09-06 and 2026-09-10 change-log rows. Change-log rows re-sorted into date order (no row removed or reworded). No request status changed. Both copies are now byte-identical. |
| 2026-09-11 | **Defect: a cloud till paid with its own local tender ids.** The drain sent the till's local `tender_type_id` (the seeded 1–4) unchanged, and the platform validates that field against its own tenant-scoped `tender_types`. So a synced payment was refused with 422 "Unknown tender type", or it landed on a different platform tender that happened to share the id. The owner's go of 2026-09-11 was to fix it as a defect. It is conformance with POS-BE-013, as amended the same day in `BACKEND_TO_POS.md`, so no new request was raised. On a cloud terminal the till now seeds `pos_tender_types` from the bundle's `money.tender_types`, keyed by the platform id, and pays with those ids (`pos-dev`, in parallel with the platform change). It never falls back to null, because the shift report counts a null tender as cash. The platform now guarantees the list is never empty: Cash and Card are created at the restaurant's first terminal. |
| 2026-09-11 | **POS-BE-013 tender types: how the client conforms** (`pos-dev`, same defect go). A cloud till now upserts each `money.tender_types` element into `pos_tender_types`, keyed on a new column `(restaurant_id, platform_id)` (migration 41). The till's own primary key is kept, so platform tender 1 never overwrites local row 1. The drain sends `platform_id` as `payments[].tender_type_id`. A database CHECK keeps platform rows at ids above 4, with code `platform-<id>`. Kind mapping: `cash→cash`, `card→card`, `external→card` (reconciled as electronic against the bank terminal's slip), `other→other`, unknown→`other` (never cash). Only `cash` counts as cash and opens the drawer. Tenders the bundle no longer names are deactivated, never deleted. An empty list changes nothing. **Refused on the client:** a payment on a tender the bundle didn't deliver (the seeded 1–4, or legacy queued sales) is never sent, with a guessed id or with null. The order is quarantined locally with code `TENDER_NOT_FROM_PLATFORM`, which the platform never returns. The Payment methods pane is read-only on cloud. **Relies on the platform to:** never deliver an empty list for a POS restaurant; keep tender ids stable (delete means deactivate); treat a new `kind` as a contract change. It should always deliver one active `cash` tender. **Consequences:** a cloud till no longer offers "On account", because the platform has no `account` kind. Upgraded dev tills must re-apply the cloud till grants (`pos_migrate --cloud-till` or the wizard) and force a reseed. |
| 2026-09-11 | **POS-BE-029 amended: payment kinds are the platform's** (`pos-dev`, docs + client; status unchanged, PROPOSED). Rule 3 and the summary example named the till's kinds (`wallet`, `account`), which the platform cannot produce: since the POS-BE-013 conformance above, a cloud till's payments are on platform tenders whose kind is `cash \| card \| external \| other`. Rule 3 now reads that vocabulary: cash by `counts_as_cash`; `card` and `external` electronic; `other` collected; no `account`. The example's on-account row became an `external` card. The client now parses `kind` through `PlatformTenderKind.tillKind` — the seeder's own mapping — instead of the till's parser, which had read `external` as other and left electronic short of the bank's settlement slip. Unknown kinds read as `other`, so a new kind (`account` included) is a POS-BE-013 contract change before the platform sends it. Both repos' copies updated identically. |
| 2026-09-13 | **POS-BE-030 raised and approved: purchasing and stock on a cloud terminal are platform-authored** (CB-09; owner go "finish all phases"). A cloud till hides its Purchasing, Items, Stock and Units panes whatever the person holds, and the rail, the Manage menu and deep links all agree. A pointer names the xorder.io dashboard, in EN and AR. Built on `feat/cb-09-slice-e` @ `1adb17f`: `flutter analyze` is clean, `flutter test` shows 1734 passed and 43 skipped, and `test/data` shows 876 passed and 1 skipped. Not merged: the main checkout carries other sessions' uncommitted edits to `app.dart` and `management_screen.dart`. The platform half, the bundle withholding `purchase.manage`, is CB-09 slice a. Rows already on a cloud till stay where they are, neither imported nor deleted. |
