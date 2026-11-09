# POS → BACKEND — Requirement Requests

**Channel owner:** Agent 1 (Flutter POS Desktop)
**Absolute path:** `~/Projects/Xorder/xorder-pos/docs/coordination/POS_TO_BACKEND.md`
**Backend repo under analysis:** `~/Projects/Xorder/xorder-cloud` (`apps/api`)
**Reply channel:** `./BACKEND_TO_POS.md`
**Last updated:** 2026-10-07 (owner decisions on both revisions → `APPROVED`) · 2026-09-27 (reconciled statuses to `BACKEND_TO_POS.md` Cloud Wave 1 + POS-BE-010; recorded POS positions on the two 2026-09 revisions — see PROGRESS and change log)

---

## PROGRESS — desktop coordination on the two 2026-09 revisions

**Working notes for the current coordination pass (2026-09-27). Kept at the top so status is reportable at any time.**

- **[done 2026-10-08] POS-BE-031 till side merged** (xorder-pos#5), built against the
  cloud side (Xorder-Menu#4, merged and waiting to deploy). `OnlineLicenceService`
  wraps the signed-file service and replaces only `current()`; activation,
  import and the islanded path are untouched. Settled details:
  - the verdict cache is its own file, `licence_check.json`, until the
    `bootstrap.json` bundle cache exists; it moves there with it;
  - `enforcement` is learned from the claim bundle and from every check reply. A
    cloud till that never heard it asks once, and only a real 200 moves it
    online; a 404 without `licence_not_found` (an older platform) keeps the file;
  - `suspended`, `expired`, `not_yet_valid` and `licence_not_found` all stop the
    next shift with `canSell` true; `unknown` never overwrites the cache or
    blocks; 401/403/429/5xx/offline fall back to the cache;
  - past `grace_policy.cache_seconds` (clamped to 7 days) the state is the new
    `LicenseState.unconfirmed`: the open shift finishes, a new one waits.
  - Verified end to end against a local cloud on 2026-10-07 (see xorder-pos#5).
- **[done 2026-10-07] Owner decisions received.** All asks on both revisions are
  closed in `BACKEND_TO_POS.md` → "Owner decisions — 2026-10-07". The
  `name_ar_snapshot` amendment and **POS-BE-031** are now `APPROVED` (agreed, no
  code authorised). POS-side deltas from what is filed below: handle a seventh
  verdict `not_yet_valid` (`expired`-shaped, shows `starts_at`); read
  `enforcement` from the bootstrap `licence` object or the activate reply,
  treating absent as `offline`; ignore `max_offline_days` on an `online` till.

- **[done] Verified backend state.** `BACKEND_TO_POS.md` marks **16 items `READY`**
  (Cloud Wave 1, 2026-09-04) plus **POS-BE-010 `READY`** (2026-09-22). This file's
  index + several entry headers still read `APPROVED` / "implementation not
  started" from before the wave — reconciled below.
- **[done] Corrected the POS-BE-006 staleness** flagged in
  `REVISION_ORDER_ITEM_ID.md §7 gap 4`: `order_items.menu_item_id` exists
  (nullable FK, shipped as T0.2) and `POST /api/pos/orders` is live and `READY`.
  The old "order_items has no menu_item_id … re-pricing is impossible" prose is
  removed. The POS already sends `menu_item_id` + `name_snapshot` on every line.
- **[done] Verified in the Flutter code (this pass):** the order line the drain
  sends, the English-only `name_snapshot`, the verbatim-id catalog seeding, and
  the shipped offline-signed licensing flow (splash gate, entitlement, states).
  See *Order-line reality* and *Licensing reality* boxes under the new items.
- **[done] Recorded POS positions / requests for both revisions:**
  - Order lines → *Amendment to POS-BE-006 — bilingual name snapshot* below
    (POS will also send `name_ar_snapshot`).
  - Licensing → **POS-BE-031** (online dashboard-managed `/license/check`) below.
- **[open] Asks to the cloud side** are collected under each new item's *Asks for
  Agent 2* heading. Nothing here is built on the till yet; both revisions are
  `PROPOSED` pending owner go, and the POS stays on the shipped offline path
  (POS-BE-015) plus the current `menu_item_id` + `name_snapshot` wire.

---

> ## ✅ Contracts are AGREED. Cloud Wave 1 is BUILT and `READY`.
> **Owner instruction, 2026-09-02:** both agents agreed the contract for every
> item (final wire shapes in `BACKEND_TO_POS.md`, incl. DIS-1…DIS-5).
>
> **2026-09-04 — Cloud Wave 1 shipped `READY`** (owner go "make the POS work with
> cloud for now"): POS-BE-001, 002, 003, 005, **006**, 007, 008, 009, 011, 013,
> 016, 019, 020, 022 (fleet API), 023, 024 — implemented and tested in `apps/api`
> and integrated on the till (`lib/data/cloud/`). **2026-09-22 — POS-BE-010
> (refunds) is `READY`.** POS-BE-015 has been `READY` (shipped) since 2026-08-26.
> Deferred, still `APPROVED`: 004, 012, 014, 017, 018, 021, 025, 026, 027, 028
> (029 `PROPOSED`; 030 platform-half `READY`, till half built, not merged).
>
> `APPROVED` authorises **no backend code**; a `READY` item is safe to integrate.
> Agent 1 integrates real transport for `READY` items and keeps `Fake`
> implementations for the rest. The index below mirrors `BACKEND_TO_POS.md`.

**Status vocabulary:** `PROPOSED` · `APPROVED` · `IN_PROGRESS` · `READY` · `BLOCKED`
Only Agent 2 (after owner approval) moves an item past `PROPOSED`, and it does so
in `BACKEND_TO_POS.md` — this file records the *request*.

---

## Index

| ID | Feature | Priority | Blocking | Status |
|---|---|---|---|---|
| POS-BE-001 | `Feature::POS` entitlement + plan wiring | MEDIUM | NO | **READY** |
| POS-BE-002 | POS tenant capabilities (`pos.*`) | HIGH | NO | **READY** |
| POS-BE-003 | Auto-applied option groups on `/dashboard/items` | HIGH | NO | **READY** |
| POS-BE-004 | `sku` + `barcode` on menu items | MEDIUM | NO | APPROVED (deferred) |
| POS-BE-005 | `supported_order_types` + `code` on `BranchResource` | HIGH | NO | **READY** |
| **POS-BE-006** | **Authenticated, server-priced POS order creation** | **HIGH** | **YES** | **READY** (integrated 2026-09-04) |
| POS-BE-007 | Idempotency + integer minor units on POS writes | HIGH | YES | **READY** |
| POS-BE-008 | Per-branch invoice sequence | HIGH | YES | **READY** |
| POS-BE-009 | Shifts, cash movements, terminal registry | HIGH | YES | **READY** (registry via §023) |
| POS-BE-010 | Refunds / voids as reversing records | MEDIUM | NO | **READY** (2026-09-22) |
| POS-BE-011 | Token lifetime compatible with an offline till | HIGH | NO | **READY** (Option C device token) |
| POS-BE-012 | Incremental catalog sync (`updated_since` + tombstones) | LOW | NO | APPROVED (deferred) |
| POS-BE-013 | Money configuration: tax, charges, tender types, tax id | HIGH | YES | **READY** |
| POS-BE-014 | Authenticated customer creation from the till | LOW | NO | APPROVED — built both sides 2026-09-27 |
| POS-BE-015 | Licence issuance + activation endpoints (offline signed file) | MEDIUM | NO | **READY** |
| POS-BE-016 | Terminal registration against a licence (seat counting) | MEDIUM | NO | **READY** (warns) |
| POS-BE-017 | Branch-server packaging (on-premises deployment) | MEDIUM | NO | APPROVED (deferred) |
| POS-BE-018 | Upstream sync: branch server → platform | MEDIUM | NO | APPROVED (deferred) |
| POS-BE-019 | Machine-readable error codes on POS writes | HIGH | NO | **READY** |
| POS-BE-020 | Server time exposed for clock-skew detection | LOW | NO | **READY** |
| POS-BE-021 | Bulk drain of a queued backlog after an outage | MEDIUM | NO | APPROVED (deferred) |
| POS-BE-022 | Super Admin fleet registry + automatic heartbeat | HIGH | NO | **READY** (fleet API; web UI later) |
| POS-BE-023 | Terminal provisioning from the dashboard + `/api/pos/bootstrap` | HIGH | YES | **READY** |
| POS-BE-024 | POS PIN credential for offline cashier sign-in | HIGH | YES | **READY** (PBKDF2-SHA256 120k) |
| POS-BE-025 | Pre-auth tenant setup config (`/setup/config/{slug}`) + versioning | HIGH | NO | APPROVED (deferred) |
| POS-BE-026 | Site registration and `ServerId` | MEDIUM | NO | APPROVED (deferred) |
| POS-BE-027 | Licence claims: `max_offline_days`, `server_id`, `license_version` | MEDIUM | NO | APPROVED (deferred; amends 015) |
| POS-BE-028 | Terminal display-name update, decoupled from identity | LOW | NO | APPROVED (deferred) |
| POS-BE-029 | Branch view on a cloud till (own branch, per-terminal) | MEDIUM | NO | PROPOSED |
| POS-BE-030 | Purchasing and stock on a cloud terminal are platform-authored | LOW | NO | **READY** (platform half; till half built, not merged) |
| POS-BE-033 | Incoming online orders and table requests on the till (`GET /api/pos/incoming`, accept/reject/handled) | HIGH | NO | PROPOSED (cloud half built, not deployed) |
| **POS-BE-031** | **Online, dashboard-managed licence check (`/license/check`)** | **HIGH** | **NO** | APPROVED (2026-10-07) |
| **POS-BE-033** | **The waiter wire served by the platform (XOrder Waiter – Cloud flavor)** | **HIGH** | **YES** | **BUILT, NOT DEPLOYED** (cloud half 2026-11-09; base URL amended: slug in the path) |
| *Amd 006* | *Bilingual name snapshot on the wire (`name_ar_snapshot`)* | MEDIUM | NO | PROPOSED (see revision) |

Three of the entries above are **amendments rather than new surface**:
POS-BE-025 is a redacted projection of POS-BE-023's bundle, POS-BE-027 adds three
claims to the already-`READY` POS-BE-015, and the POS-BE-022 amendment asks only
that its heartbeat *response* be specified. See `docs/pos/10-setup-architecture.md`.

**POS-BE-006 shipped and is integrated** (Cloud Wave 1, 2026-09-04) — everything
that takes money depended on it, and its prerequisite (`order_items.menu_item_id`)
also fixed product reporting for the existing QR product (BE-A05). The two open
2026-09 revisions are recorded as **POS-BE-031** (online licence check) and the
**Amendment to POS-BE-006** (bilingual `name_ar_snapshot`); both are `PROPOSED`
and neither has an owner go to build on the till yet.

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

**Status:** **READY** — built and tested in `apps/api`, integrated on the till in
Cloud Wave 1 (2026-09-04). `POST /api/pos/orders` is live; the prerequisite schema
`order_items.menu_item_id` (nullable FK, `nullOnDelete`) shipped as T0.2
(`2026_09_02_000100_add_menu_item_id_to_order_items_table.php`). See
`BACKEND_TO_POS.md §006` for the frozen wire shape and the till side in
`lib/data/cloud/` (`OutboxDrain`, `BootstrapSeeder`). The original request text is
kept below for the record; the "no `menu_item_id` / re-pricing impossible" prose
was **corrected** on 2026-09-27 (it predated T0.2).
**Feature:** Authenticated, server-priced POS order creation

> **This was the blocking request; it is now `READY` and integrated.** Everything
> that takes money depended on it. It carries `menu_item_id` + `name_snapshot` per
> line and re-prices server-side. See also the *Amendment to POS-BE-006 —
> bilingual name snapshot* below (the `name_ar_snapshot` follow-up).

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
3. ~~**`order_items` has no `menu_item_id`** — only a `name` string. Server-side
   re-pricing is therefore *impossible* on the current schema.~~ **CORRECTED
   2026-09-27:** `order_items.menu_item_id` now exists (nullable FK, T0.2,
   `2026_09_02_000100_add_menu_item_id_to_order_items_table.php`), the endpoint is
   live, and the till sends `menu_item_id` + `name_snapshot` on every line and
   re-prices server-side. This was the real prerequisite and it shipped.

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

**Status:** READY — built 2026-09-22 (`b15f269` in xorder-cloud), see `BACKEND_TO_POS.md` §010 for the final wire shape. **POS half built 2026-09-22**: the drain stamps `lines[].client_line_id`, the refund writer queues a `refund` event in the same transaction as the refund, and the drain posts it. One gap raised — see *Amendment to POS-BE-010* below: a refund given as a flat amount off the bill has no lines, and §010 has no shape for it
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

**Status:** **BUILT both sides 2026-09-27** (owner go) — contract agreed
2026-09-02, see `BACKEND_TO_POS.md`
**Feature:** Authenticated customer creation from the till

> **What was built.** `POST /api/pos/customers` on the device token, through
> `CustomerDirectory::upsert()` exactly as the contract asked, so a regular who
> has ordered from their phone and then gives the same number at the counter is
> one customer and not two. `customers.create` is the gate; it was already
> declared in `TenantCapability` and had never been used. A replay answers 200
> with the same customer rather than creating a second — the phone is the
> natural key, so this needs no separate idempotency table.
>
> **The bundle now carries the directory** (`customers`, newest first, capped
> at 2000). Owner decision: a cashier must be able to search with no internet,
> and the counter is exactly where the signal is worst. The till seeds it into
> `pos_customers` (migration 51) and searches locally.
>
> **The till upserts on the phone too**, and the seeder matches on the number
> rather than the platform id — a customer created at the counter during an
> outage and the same person arriving in the next bundle merge into one row
> instead of leaving a duplicate the cashier can see.
>
> Deferred: uploading till-created customers through the outbox. They are
> written and usable locally and referenced by the sale; the platform learns
> about them when somebody is created there or the sale carries them.

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
- platform side: CB-09 slice a, `dd9a530` on `feat/cb-09-purchasing` in xorder-cloud — the `PosBootstrapService::staff()` filter.

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

## Amendment to POS-BE-006 — bilingual name snapshot on the wire (`name_ar_snapshot`)

**Status:** APPROVED 2026-10-07 (owner) · was PROPOSED — filed 2026-09-27, POS position on `REVISION_ORDER_ITEM_ID.md`.
Design only; no till code written. POS-BE-006 itself is `READY` and this does not
change its accepted request — it *adds one optional field*.
**Feature:** the till also sends the Arabic name snapshot, so the backend can
freeze a real `name_ar` even on the fallback (unresolved / open-price) path.

### Order-line reality (verified in the Flutter code, 2026-09-27)

The revision's problem statement — "the POS sends the name directly" — is **stale
for the POS path** and exactly true only for the public/QR path. Confirmed:

| Fact | Evidence |
|---|---|
| The wire line already carries `menu_item_id` (nullable) + `name_snapshot` | `lib/data/cloud/outbox_drain.dart:196-218` (`lineJson`) — keys: `client_line_id`, `menu_item_id`, `option_ids`, `quantity`, `note`, `name_snapshot`, `unit_price_minor`, `discount?`, `price_override?` |
| **No `variant_option_id`** on the wire — the variant option travels *inside* `option_ids[]`; the server resolves `is_variant` | `outbox_drain.dart:209-211` |
| `name_snapshot` is **English-only** — it is `product.nameEn`, snapshotted at persist time and read back verbatim by the drain | persisted at `lib/data/postgres/postgres_orders_repository.dart:484` (`'name': line.product.nameEn`); drain re-reads `pos_order_lines.name_snapshot` at `outbox_drain.dart:976,1010` |
| **No Arabic name is on the line at all** — `name_ar` is neither a column nor a wire key | same files; there is no `name_ar` selected or emitted |
| The domain `Product` **does** hold both languages | `lib/domain/models/catalog.dart:58` (`nameEn`, required), `:59` (`nameAr`, nullable); `displayName(locale)` at `:95-98` |
| The local catalog **is** bilingual — the seeder writes `name_en` **and** `name_ar` | `lib/data/cloud/bootstrap_seeder.dart:618-619` |
| Catalog ids are `menu_items.id` **verbatim** (no remap table); serials bumped past the max seeded id | `bootstrap_seeder.dart:615` (`'id': product.id`), `_bumpSequences` at `:680-697` |
| Open-price and combo lines send `menu_item_id = null`; the negative synthetic id is a per-ticket merge key only, never persisted or sent | `postgres_orders_repository.dart:481`; allocator in `lib/domain/services/ticket_engine.dart:715-729,771-777` |

**So the only place bilingual fidelity is lost is the fallback path**: when the
line's `menu_item_id` is null or the item was deleted during an outage, the
backend has only the single English `name_snapshot` to write into both `name_ar`
and `name_en`. On a *resolved* line the backend already has both names from the
item, so this amendment does not affect the common case.

### POS position

- **Accepted, no wire change is *required* to ship the revision's benefit.** The
  resolved-line case (the vast majority) already works from `menu_item_id`; the
  backend freezing both names from the resolved item is a backend-only change.
- **The POS will additionally send `name_ar_snapshot`** so the fallback path is
  bilingual too. This is the one place the revision loses Arabic today, and the
  till already holds `Product.nameAr` locally, so the cost is small.
- The field is **optional and additive**; an older till that omits it is handled
  exactly as today (both frozen columns hold the English snapshot).

### Desktop implementation plan (POS side, gated on owner go)

Ordered, additive, each independently shippable; all behind the repository seam.

1. **Persist the Arabic snapshot.** Add a nullable `name_ar_snapshot` column to
   `pos_order_lines` (a new `bin/pos_migrate.dart` migration; column-scope the
   till grant as with `name_snapshot`). Write `product.nameAr` into it at
   `postgres_orders_repository.dart:460-501` next to the existing
   `'name': line.product.nameEn`. Do the same for combo component rows
   (`pos_order_line_items`, currently `item.nameEn` at `:514-521`).
2. **Carry it to the wire.** Select `l.name_ar_snapshot` in the drain's
   `_linesFor` SQL (`outbox_drain.dart:972-1033`) and add
   `'name_ar_snapshot': nameArSnapshot` to `lineJson` (`:196-218`), null-omitted
   like `discount`/`price_override` so nothing breaks when it is absent.
3. **Response parse.** When the §006 response line gains `name_ar`/`name_en`,
   have the bundle/order-response parser read them tolerantly (fall back to the
   existing `name`), matching the till's never-throw rule. The till prints from
   its own local snapshot, so this is for reconciliation display only.
4. **Tests.** Extend `test/data/outbox_drain_test.dart` for the new key, and the
   repository test for the new column; assert the resolved and fallback cases.

No change to open-price/combo behaviour: they still send `menu_item_id = null`
and now carry a real Arabic snapshot alongside the English one.

### Asks for Agent 2 (cloud side)

1. **Confirm the field name and precedence.** POS proposes `name_ar_snapshot`
   (mirroring `name_snapshot`). On a resolved line the server **ignores both
   snapshots for naming** and freezes `name_ar`/`name_en` from the item; on the
   unresolved/`client_asserted` fallback the server writes
   `name_en = name_snapshot` and `name_ar = name_ar_snapshot ?? name_snapshot`.
   Please confirm this is what §2b will do.
2. **Confirm the response shape.** Each `lines[]` element gains `name_ar` +
   `name_en`, `name` kept for back-compat (revision §3). POS reads them
   tolerantly; an unknown/absent value never blocks.
3. **`StorePosOrderRequest` validation.** `name_ar_snapshot` should be
   `nullable|string`, never `required` — `name_snapshot` stays the
   `required_without:menu_item_id` gate. No new 422 shape.
4. **Public/QR path is out of POS scope.** The revision's "Minimum" (write the
   single diner name into all three columns) and the later "menu SPA sends
   `menu_item_id`" follow-up are backend/`apps/menu` concerns; the POS neither
   sends nor consumes that path.

**Priority:** MEDIUM · **Blocking:** NO — the resolved-line benefit ships without
any till change; this only restores Arabic on the rare fallback line.

---

## POS-BE-031 — Online, dashboard-managed licence check (`POST /api/pos/license/check`)

**Status:** APPROVED 2026-10-07 (owner) · was PROPOSED — filed 2026-09-27, POS position on `REVISION_POS_LICENSING.md`.
Design only; no till code written. This is a **new online verdict path** that sits
beside the shipped, `READY` POS-BE-015 offline-signed file (which is *kept, for
islanded/`enforcement='offline'` tills only*). It supersedes, for connected tills,
the runtime use of the signed file — not POS-BE-015's activation endpoints.
**Feature:** a connected till reads its licence verdict from the server on splash
and before each shift, with a ~72h offline grace cache; the signed file becomes
the islanded-only path.

### Licensing reality (verified in the Flutter code, 2026-09-27)

| Fact | Evidence |
|---|---|
| Runtime licence trust is **offline Ed25519** against a public key compiled into the binary; fails closed in release without the key env var | `lib/features/licensing/domain/license_verifier.dart:65-94`; `lib/features/licensing/data/license_keys.dart:45,51-63` |
| The bound service is the **real `DefaultLicenceService`**, not the dev self-signer | `lib/app/providers.dart:1619-1639`; `FakeLicenceService` (`licence_service.dart:259-362`) is used by tests only |
| `LicenseState` has exactly the 10 spec'd values | `lib/features/licensing/domain/license.dart:4-37` (`valid, expiringSoon, inGrace, expired, notYetValid, missing, invalid, tenantMismatch, modeNotLicensed, terminalNotLicensed`) |
| The gate exposes state-driven `canOpenShift`, **`canSell`**, `canChangeConfiguration`; `canCashUp`/`canReprint`/`canExportData` are hardcoded `true` getters | `license.dart:208-245` (note: spec's "canChangeConfig" = field `canChangeConfiguration`; spec omits the real `canSell` field) |
| Current state→gate mapping | `license_verifier.dart:199-253`: `valid`/`expiringSoon` → all true; `inGrace` → config **frozen**; `expired` → `canOpenShift=false`, **`canSell=true`** (open shift never cut off); every deny state (`missing`/`invalid`/`tenantMismatch`/`modeNotLicensed`/`terminalNotLicensed`/`notYetValid`) → **`canSell=false`** via `_deny` |
| Splash gate: `StartScreen.initState` invalidates `licenceEntitlementProvider` on every arrival; `_start()` blocks a new shift on `!canOpenShift`; a null (slow/unloaded) entitlement is **treated as permitted** | `lib/features/start/start_screen.dart:52`, `:67-68`, `:148-150` |
| `max_offline_days` is a **parsed but NOT-enforced** `LicenseClaims` field; enforcement needs a durable last-contact timestamp that does not exist yet | `license.dart:107-119,161,194` |
| `DeploymentMode` is **`cloud` / `offline`** (two values); `requiresPeriodicCheckIn => offline`, `syncsSalesToPlatform => cloud` | `lib/core/config/deployment.dart:10-75` |
| **No online `/license/check` exists.** The only online licence call is *activation* (`POST /api/pos/licence/activate`); revocation is seen only as HTTP 403 at activation | `lib/features/licensing/data/platform_licence_api.dart:88-89,115-118`; grep for `licence/check` → nothing |
| **`bootstrap.json` + `last_platform_contact_at` are design-only** (no `lib/` code); only `config.json` (device config) and `licence.xlic` exist on disk; `CloudSync.lastSyncedAt()` reads when the bundle was last written to the DB, not a licence timestamp | `docs/pos/10-setup-architecture.md §13`; `lib/data/cloud/cloud_sync.dart:186+` |
| Device-token (terminal) revocation already exists via the heartbeat 401 → `terminalRejectedProvider` (cloud-only, non-persisted), distinct from licence revocation | `providers.dart:1050-1052,1014-1035`; `lib/data/cloud/cloud_api.dart:217-218`; `cloud_sync.dart:132-160` |

### POS position

- **Accepted in principle** — it materially improves revocation latency and
  removes the "signed file can never be recalled" hole for connected tills, while
  keeping the offline file for genuinely islanded tills. It aligns with the
  cardinal rule the client already enforces: **block only the *next* shift, never
  mid-service.**
- **The enforcement axis is a new switch, orthogonal to `DeploymentMode`.** The
  client already has `requiresPeriodicCheckIn` on `offline` mode; the revision's
  `enforcement` flag (`online` vs `offline`) must be delivered to the till (at
  activation/bootstrap) so a single binary picks the path. The POS asks that this
  be a first-class field, not inferred from `DeploymentMode` (a `cloud` till is
  always `online`; an `offline` till may be either connected-offline `online` or
  truly islanded `offline`).
- **The signed-file machinery stays intact** for `enforcement='offline'`: all ten
  `LicenseState` cases, `DefaultLicenceService`, `LicenseVerifier`, the embedded
  public key, and `activate`/`current`. POS-BE-015/027 are unaffected for that
  path.

### Desktop implementation plan (POS side, gated on owner go)

Ordered; the first two are **prerequisites the online path shares with the
still-unenforced POS-BE-027 `max_offline_days`**, so they pay for themselves twice.

1. **Build the durable last-contact cache first (`bootstrap.json`).** Implement
   the design-only `bootstrap.json` beside `config.json`/`licence.xlic` — a
   separate failure domain, written by the client, holding `last_platform_contact_at`
   and (new) the last successful licence verdict + `checkedAt`. This is the single
   missing primitive behind both this revision's grace window **and** POS-BE-027's
   offline-window enforcement. (`docs/pos/10-setup-architecture.md §13` is the design.)
2. **Add the online verdict client.** A `PlatformLicenceApi.check()` →
   `POST /api/pos/license/check` on the **device token** (`xdt_…`, the same
   credential the heartbeat uses), sending `fingerprint` (already computed by
   `TerminalIdFingerprint`), `deployment_mode`, optional `app_version` and the
   till's believed `licence_expires_at`. Timeout ~10s.
3. **A new `LicenceService` for `enforcement='online'`.** Introduce an
   `OnlineLicenceService` bound in `lib/app/providers.dart:1619-1639` when the
   config's enforcement is `online` (else keep `DefaultLicenceService`/
   `SiteLicenceService`). `licenceEntitlementProvider` stays the seam — nothing
   in `StartScreen` changes. The service maps the server `status` enum onto a
   `LicenseEntitlement` and caches the verdict per step 1.
4. **Map the online verdict onto the existing gate — carefully.** The server
   enum (`valid`, `expiring_soon`, `in_grace`, `expired`, `suspended`, `unknown`)
   plus HTTP `404 licence_not_found` must produce entitlements that honour §4.2.
   **Gap to close:** the current `_deny` path sets `canSell=false`, but the
   revision requires `suspended`/`licence_not_found` to behave like `expired`
   (`canOpenShift=false`, **`canSell=true`** so the open shift finishes,
   `canChangeConfiguration=false`). So the online mapping must **not** reuse
   `_deny` for those; it needs an `expired`-shaped entitlement. Options: add
   `LicenseState.suspended` (+ `offlineWindowExpired` from POS-BE-027) or map both
   to the existing `expired` state. `canCashUp`/`canReprint`/`canExportData` stay
   hardcoded `true` regardless.
5. **Wire the splash + before-shift checks (non-blocking).** `StartScreen`
   already invalidates `licenceEntitlementProvider` on every arrival
   (`start_screen.dart:52`) and gates only `_start()` on `canOpenShift`
   (`:67-68`), treating a null/slow verdict as permitted (`:148-150`). The online
   service hangs off that provider: it returns the cached verdict immediately and
   refreshes in the background, so the splash never blocks on the network. A
   renewal/suspend applied minutes ago is visible at the next arrival with no
   restart — which is exactly what the current invalidation already guarantees.
6. **The 72h grace-window rule (client-side).** On a 200, store
   `{verdict, checkedAt}` in `bootstrap.json` and derive the entitlement. On
   network/5xx/timeout, trust the cache if `now - checkedAt <= grace_policy.cache_seconds`
   (default 72h, server-driven, clamped client-side to a sane max e.g. 7d); show a
   subtle "working offline, licence last confirmed <t>" pill. Past the window:
   allow the OPEN shift, **block a new shift**, banner "cannot confirm licence —
   reconnect". On 401/403 reuse the existing re-pair / `terminalRejectedProvider`
   handling. Never write the verdict to `config.json` (gates boot) or as a signed
   file (connected tills stop keeping one).
7. **Clock-skew honesty.** Compare the response `server_time` to local time (the
   heartbeat already carries `server_time`); a large skew shows the honest "check
   the terminal's date and time" rather than a false expiry.
8. **Islanded stays on the file.** A terminal whose config is `enforcement='offline'`
   never calls `/license/check`; `DefaultLicenceService` + the `.xlic` path is
   unchanged, all ten `LicenseState` cases live only there.
9. **Tests.** Fake the HTTP layer (as `branch_sales_api`/`cloud_refunds` tests do)
   and cover: each `status` → entitlement, the 72h cache hit/expiry, the
   suspended/404 "open shift finishes but next is blocked" rule, and the islanded
   path never calling the endpoint.

### Asks for Agent 2 (cloud side)

1. **Confirm the exact request/response shapes and auth.** POS will build against
   `POST /api/pos/license/check` on `pos.device:no-feature` (so a lapsed
   `feature:pos` till is still told *why*), restaurant resolved from the terminal,
   throttle `60,1`. Please confirm the request body fields (`fingerprint`,
   `deployment_mode`, `app_version?`, `licence_expires_at?`) and the 200 body
   (`status`, `licence_ref`, `expires_at`, `lifetime`, `grace_days`, `warn_days`,
   `max_terminals`, `max_users`, `features[]`, `message`, `server_time`,
   `grace_policy.cache_seconds`).
2. **Freeze the verdict enum.** POS needs the final `status` value set —
   `valid | expiring_soon | in_grace | expired | suspended | unknown` — and the
   HTTP/code table (`404 licence_not_found`, `401 DEVICE_TOKEN_INVALID`,
   `403 TERMINAL_REVOKED`, `429 TOO_MANY_ATTEMPTS`). The client switches on
   `status`/`code` and falls back to **retry/trust-cache, never block-on-unknown**,
   so new values can be added safely — but the initial set must be fixed so the
   entitlement mapping (step 4) is correct.
3. **Deliver the `enforcement` flag to the till.** POS asks that
   `enforcement` (`online`/`offline`) be delivered at activation and in the
   bootstrap/setup bundle, so the binary can pick the path without guessing from
   `DeploymentMode`. Name the field and say which bundle carries it.
4. **`grace_policy.cache_seconds` is server-driven but bounded.** Confirm the
   default (72h / 259200s) and that the client may clamp it (POS will clamp to a
   max of 7d so a bad value can't grant forever).
5. **Confirm the verdict is not signed (TLS-only) and that real enforcement stays
   server-side** on `feature:pos` at every money write — the splash verdict is
   commercial hygiene. If an HMAC over the verdict is ever wanted, that is a
   separate contract change; POS is fine deferring it.
6. **Relationship to POS-BE-027.** The `max_offline_days` claim (parsed, not yet
   enforced) and this online window overlap. POS proposes: on an `online` till the
   `/license/check` grace window governs; on an `offline` (islanded) till the
   signed-file `max_offline_days` governs. Please confirm there is **one**
   enforcement path per till, not two competing windows.
7. **Suspend/resume/expire latency semantics.** Confirm the dashboard actions
   bite at the next check (immediate for a launching till; up to the grace window
   for an open one), and that an urgent kill uses device-token revocation
   (`TERMINAL_REVOKED`), which the till already honours immediately.

**Priority:** HIGH · **Blocking:** NO — the shipped offline-signed path
(POS-BE-015) keeps every till working until this lands; the POS builds against a
faked `/license/check` until it reaches `READY`.

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

## Amendment to POS-BE-010 — a refund of an amount off the bill has no lines

**Raised 2026-09-22, after building the till half of §010.** One local refund
shape has no honest request on `POST /api/pos/refunds`, and it is a common one
in a restaurant.

`RefundEngine.quoteForAmount` refunds a flat sum against the bill as a whole —
"give him fifty pounds back" — and attaches **no lines at all**, on purpose:
nobody said which food the money was for, and attributing it would move
`refunded_quantity` on a line the operator never chose. Its parts (subtotal,
discount, service, VAT) are that same fraction of the order's own, so refunded
tax still reconciles with refunded sales.

§010 requires `lines[]` and requires `tenders[]` to **equal the line total**, so
such a refund has exactly two possible fates on the wire, and both are bad:

1. Send `lines: []` with a non-zero tender → `422 VALIDATION_FAILED` on every
   amount refund the restaurant ever gives.
2. Invent an attribution across the order's lines → the platform's own
   `order_items.refunded_quantity` counters then say particular dishes were
   returned when they were not, and the platform's per-line ceiling starts
   refusing later, honest refunds of those dishes.

**The till therefore holds these locally** under a client-side quarantine code
`REFUND_HAS_NO_LINES` (the §019 discipline: decided here, never sent, held for a
person, never deleted — the money did leave the drawer). That is a gap, not a
solution: on a cloud till those refunds do not reach the platform at all, so
platform turnover overstates by their total until this is closed.

**What we ask for** — whichever is cheaper on your side:

- accept `lines: []` when the refund carries an order-level `amount_minor`
  (i.e. the tender balances the *envelope* rather than the lines), and leave
  every `order_items.refunded_quantity` untouched; **or**
- add an explicit `unattributed_amount_minor` to the envelope, counted into
  `orders.refunded_minor` and into `settlement_status` exactly as a line refund
  is, and excluded from the per-line checks.

Either keeps `REFUND_EXCEEDS_SOLD`'s money check intact — that one is the check
that matters here, and the order's `total_minor` is all it needs.

---

## Amendment to POS-BE-022 — `pending_count` stops counting held records; `held_count` beside it

**Raised 2026-10-24 (DATABASE_AND_SYNC D1/D2/D8/D13). Additive, `PROPOSED`.**

`pending_count` and `oldest_pending_at` used to count every undelivered row,
including the ones the drain had **held for a person** (a §019 quarantine code,
or a client-side hold such as `TENDER_NOT_FROM_PLATFORM` /
`REFUND_HAS_NO_LINES`). No pass ever sends those, so one held sale pinned
`oldest_pending_at` to its date for ever and the fleet view showed a current
till as weeks behind.

The heartbeat now sends:

- `pending_count` / `oldest_pending_at` — **what the next drain pass will try**
  (`delivered_at IS NULL AND quarantined_at IS NULL`);
- `held_count` — undelivered and held, waiting on a person (the till's Sync
  pane now lists them with a Retry, behind `terminal.manage`).

The sum is the old `pending_count`. **Ask:** store `held_count` beside
`pending_count` on `pos_terminals` and show it as its own Super Admin column —
it is the money that is stuck rather than slow, which is the call support
should make first. Until then the key is ignored and nothing breaks.

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

## POS-BE-033 — The waiter wire served by the platform (XOrder Waiter – Cloud flavor)

**Status:** PROPOSED 2026-11-09 · **cloud half BUILT 2026-11-09, uncommitted, not deployed, not `READY`** (owner decision: two flavors of the handheld, cloud
and offline, the mode fixed per build; the cloud flavor signs in with slug, name
and PIN). Till-side code: the handheld is built and tested against a fake; nothing
on the platform exists yet.

### What the handheld is, in one paragraph

`apps/xorder_pos_waiter` is a phone app for floor staff: the floor, a table's
check, add lines, send a round to the kitchen. In the **offline flavor** it talks
to the till on the LAN over the waiter wire (`packages/xorder_waiter_link`,
wire v1), and the till prices everything with its `TicketEngine`. In the
**cloud flavor** there is no till on the LAN to talk to: the restaurant is on
xorder.io (QR ordering, table management) and the platform holds its tables,
visits and order rounds. The ask is that **the platform serves the same wire**
at the restaurant's subdomain, so the handheld's screens, strings and tests are
one codebase and the only difference between the flavors is the sign-in screen
and the base URL.

### Base URL and auth

- Base: `https://xorder.io/api/pos/waiter/{slug}` (**amended 2026-11-09: the restaurant is the slug in the path, not a subdomain; `{slug}.xorder.io/api` is not served**) — the handheld appends
  `/v1/<call>`. The slug is what the waiter types in the "Restaurant" field.
- A device token in `Authorization: Device <token>` on every call after sign-in;
  a waiter session in `X-Waiter-Session` after sign-in. Both are opaque strings
  the platform issues. Sessions idle out after 12 h.
- No dashboard password ever reaches the phone.

### Calls (wire v1, as the till serves them today)

| Call | Body / reply |
|---|---|
| `GET /v1/hello` | `{wire: 1, name: "<restaurant name>"}` — no auth |
| `POST /v1/sign-in` | `{username, pin, device_name}` (+ `Authorization: Device` when the phone has a token) → `{session, staff: {id, name, capabilities[]}, device_token?}`. **`device_token` is returned only when the request carried none: the platform registers the phone under `device_name` and the handheld keeps the token.** PIN is the POS PIN of POS-BE-024 (PBKDF2, already on `users`); `username` is the staff username. Both matched together; one error for both wrong. Five failures per device (or per IP for an unknown device) → `TOO_MANY_ATTEMPTS` for a minute. Requires the tenant capability `pos.operate`. |
| `POST /v1/sign-out` | drops the session |
| `GET /v1/menu` | the public menu shape mapped to `WaiterMenu`: categories, products with `price_minor`, modifier groups (`min_select`, `max_select`, `is_variant`, modifiers with `delta_minor`, `available`, `is_default`). Combos and open-price items left out, as the till does. |
| `GET /v1/floor` | every active table: `{id, label, area, seats, state: free|open|bill_asked, total_minor, items, guests}`. `open` = an open table visit with a NEW order; `bill_asked` = an open bill request. |
| `GET /v1/tables/{id}/check` | the visit's running order as a `WaiterCheck`: lines with `stage: draft|sent|voided`, `round`, `version`; totals. |
| `POST /v1/tables/{id}/ops` | `{version, ops[]}` — `add`, `qty`, `remove`, `note`, `guests`, `send_round` — applied all or none; reply is the priced check; `409 CHECK_CHANGED` with the current check when `version` is stale. |

Error codes are the wire's (`UNPAIRED`, `DEVICE_REVOKED`, `SIGN_IN_REQUIRED`,
`PIN_WRONG`, `TOO_MANY_ATTEMPTS`, `NOT_PERMITTED`, `CHECK_CHANGED`, `REFUSED`
+ `reason`, `NOT_FOUND`, `TILL_UNAVAILABLE`, `VERSION_MISMATCH`), as
`packages/xorder_waiter_link/lib/src/wire.dart` lists them.

### What the platform has to add (the cloud half)

1. **A draft round on a table visit.** Today an order round exists only once
   submitted. The wire's `draft` lines ("not sent yet", editable) need a place:
   either an unsent round per visit the ops edit, or a per-device draft the
   platform keeps until `send_round`. Recommendation: one unsent round per
   visit, shared by every device at the table, which is what the till does.
2. **Server-side pricing of lines**, from the menu's own prices and modifier
   deltas. The public QR path trusts the client's `line_total` today; the
   wire sends no price at all, so the platform must compute it. This is the
   change that also closes the QR path's pricing gap if it is done once in a
   service both use.
3. **A `version` on the visit's order**, bumped on every write, for the
   compare-and-swap the wire relies on (the till's XORD-044).
4. **Device registration and revocation** for waiter phones: a `pos_waiter_devices`
   equivalent per restaurant, listed and revocable in the dashboard's Staff
   or POS devices page, token stored hashed.
5. **A served mark per round** (`order_rounds.served_at/served_by`) is wanted by
   the floor but is not part of this contract; it rides on the existing
   `docs/FUTURE_PLAN.md` F2 item in `xorder-cloud`.

### Rule that decides which flavor a restaurant uses

A restaurant with the `pos` feature uses the **offline** flavor against its till:
the till owns the open check, and a second writer in the cloud would make two
truths for one table. A restaurant without a till uses the **cloud** flavor.
Neither flavor shows a mode choice; the licence and the plan decide which app
the restaurant is given.

### Open questions for the platform

- Does a waiter's session count against anything (seats, plan limits)?
- Should the dashboard's Live board show "which waiter" on a round? The wire
  carries `staff.id`; the platform can stamp it on the round.
- Kitchen notification on `send_round`: the same push the QR order uses, or none
  until kitchen steps (F1) exist?

## Change log

| Date | Change |
|---|---|
| 2026-11-09 | **POS-BE-033 cloud half built** (`xorder-cloud`, uncommitted, not deployed): `routes/api.php` `pos/waiter/{slug}/v1/*`, `WaiterWire` middleware, `PosWaiter` controllers, `WaiterCheckService`/`WaiterMenuService`, migration `2026_11_09_000100`, dashboard `waiter-devices` list/revoke; `WaiterWireTest` 31. **Base URL amended to the slug-in-path form**; the handheld follows. Not `READY` until deployed. Open: branch scoping of waiters, order `source` value (`waiter`), kitchen push (same as a QR order). |
| 2026-11-09 | **POS-BE-033 raised: the waiter wire served by the platform**, for the cloud flavor of XOrder Waiter (owner decision: two flavors, mode fixed per build; sign-in with slug, name and PIN). The handheld is built against a fake; the platform half is the proposal above. Nothing on the platform touched. |
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
| 2026-09-11 | **CB-00 — the two repos' copies reconciled** (`xorder-cloud`, docs only). The xorder-pos copy (2026-09-11) was a strict superset of the xorder-cloud copy (2026-09-04) except one passage: the "catalog stays authored in the cloud dashboard" bullet under the 2026-08-26 deployment consequences. xorder-cloud still had the original 2026-08-26 wording ("local catalog authoring on the till is now explicitly *out* of scope"); xorder-pos had the 2026-09-06 owner narrowing ("— on a CLOUD terminal", offline authors its own world). **The later-dated 2026-09-06 text is kept.** Carried into xorder-cloud: that narrowing, the whole POS-BE-029 entry and its summary row, and the 2026-09-06 and 2026-09-10 change-log rows. Change-log rows re-sorted into date order (no row removed or reworded). No request status changed. Both copies are now byte-identical. |
| 2026-09-11 | **Defect: a cloud till paid with its own local tender ids.** The drain sent the till's local `tender_type_id` (the seeded 1–4) unchanged, and the platform validates that field against its own tenant-scoped `tender_types`. So a synced payment was refused with 422 "Unknown tender type", or it landed on a different platform tender that happened to share the id. The owner's go of 2026-09-11 was to fix it as a defect. It is conformance with POS-BE-013, as amended the same day in `BACKEND_TO_POS.md`, so no new request was raised. On a cloud terminal the till now seeds `pos_tender_types` from the bundle's `money.tender_types`, keyed by the platform id, and pays with those ids (`pos-dev`, in parallel with the platform change). It never falls back to null, because the shift report counts a null tender as cash. The platform now guarantees the list is never empty: Cash and Card are created at the restaurant's first terminal. |
| 2026-09-11 | **POS-BE-013 tender types: how the client conforms** (`pos-dev`, same defect go). A cloud till now upserts each `money.tender_types` element into `pos_tender_types`, keyed on a new column `(restaurant_id, platform_id)` (migration 41). The till's own primary key is kept, so platform tender 1 never overwrites local row 1. The drain sends `platform_id` as `payments[].tender_type_id`. A database CHECK keeps platform rows at ids above 4, with code `platform-<id>`. Kind mapping: `cash→cash`, `card→card`, `external→card` (reconciled as electronic against the bank terminal's slip), `other→other`, unknown→`other` (never cash). Only `cash` counts as cash and opens the drawer. Tenders the bundle no longer names are deactivated, never deleted. An empty list changes nothing. **Refused on the client:** a payment on a tender the bundle didn't deliver (the seeded 1–4, or legacy queued sales) is never sent, with a guessed id or with null. The order is quarantined locally with code `TENDER_NOT_FROM_PLATFORM`, which the platform never returns. The Payment methods pane is read-only on cloud. **Relies on the platform to:** never deliver an empty list for a POS restaurant; keep tender ids stable (delete means deactivate); treat a new `kind` as a contract change. It should always deliver one active `cash` tender. **Consequences:** a cloud till no longer offers "On account", because the platform has no `account` kind. Upgraded dev tills must re-apply the cloud till grants (`pos_migrate --cloud-till` or the wizard) and force a reseed. |
| 2026-09-11 | **POS-BE-029 amended: payment kinds are the platform's** (`pos-dev`, docs + client; status unchanged, PROPOSED). Rule 3 and the summary example named the till's kinds (`wallet`, `account`), which the platform cannot produce: since the POS-BE-013 conformance above, a cloud till's payments are on platform tenders whose kind is `cash \| card \| external \| other`. Rule 3 now reads that vocabulary: cash by `counts_as_cash`; `card` and `external` electronic; `other` collected; no `account`. The example's on-account row became an `external` card. The client now parses `kind` through `PlatformTenderKind.tillKind` — the seeder's own mapping — instead of the till's parser, which had read `external` as other and left electronic short of the bank's settlement slip. Unknown kinds read as `other`, so a new kind (`account` included) is a POS-BE-013 contract change before the platform sends it. Both repos' copies updated identically. |
| 2026-09-13 | **POS-BE-030 raised and approved: purchasing and stock on a cloud terminal are platform-authored** (CB-09; owner go "finish all phases"). A cloud till hides its Purchasing, Items, Stock and Units panes whatever the person holds, and the rail, the Manage menu and deep links all agree. A pointer names the xorder.io dashboard, in EN and AR. Built on `feat/cb-09-slice-e` @ `1adb17f`: `flutter analyze` is clean, `flutter test` shows 1734 passed and 43 skipped, and `test/data` shows 876 passed and 1 skipped. Not merged: the main checkout carries other sessions' uncommitted edits to `app.dart` and `management_screen.dart`. The platform half, the bundle withholding `purchase.manage`, is CB-09 slice a. Rows already on a cloud till stay where they are, neither imported nor deleted. |
| 2026-09-27 | **Reconciliation + two 2026-09 revisions recorded (desktop coordination pass).** Synced this file's index and the POS-BE-006 entry to `BACKEND_TO_POS.md`: Cloud Wave 1 (2026-09-04) items and POS-BE-010 (2026-09-22) are `READY`; the stale "`order_items` has no `menu_item_id` / re-pricing impossible" prose and the "implementation not started" headers were corrected (T0.2 shipped, endpoint live, till integrated). Verified in the Flutter code: the wire line sends `menu_item_id` + English-only `name_snapshot` (`product.nameEn`) with no `name_ar` and no `variant_option_id` (folded into `option_ids[]`); catalog is bilingual and seeded with verbatim ids; the licensing runtime is offline Ed25519 (`DefaultLicenceService`, 10 `LicenseState` values, `canCashUp/Reprint/Export` hardcoded true), `max_offline_days` parsed-not-enforced, `bootstrap.json`/`last_platform_contact_at` design-only, and **no** online `/license/check` exists. Recorded **POS-BE-031** (online dashboard-managed `/license/check` — POS position, ordered till plan, and asks for verdict enum / request+response shapes / `enforcement` flag / grace-window bound) and an **Amendment to POS-BE-006** (till also sends `name_ar_snapshot` for the fallback path). Both `PROPOSED`; nothing built on the till; POS stays on POS-BE-015 offline path + the current `menu_item_id`+`name_snapshot` wire. No backend code authorised. |
| 2026-10-07 | **Owner decisions recorded — both 2026-09 revisions agreed.** Every ask under the `name_ar_snapshot` amendment and POS-BE-031 is answered in `BACKEND_TO_POS.md` → "Owner decisions — 2026-10-07". Amendment → `APPROVED` as proposed. POS-BE-031 → `APPROVED` with one addition: the verdict enum gains `not_yet_valid` (+ `starts_at`); `enforcement` arrives in the bootstrap `licence` object and the activate reply (absent ⇒ `offline`). Nothing built on the till yet. |
| 2026-09-22 | **POS-BE-010, till half: a cloud till uploads its refunds.** Two halves, both additive. (1) Every order line the drain sends now carries `lines[].client_line_id` — the LOCAL `pos_order_lines.id` as a string, not `line_key`: `TicketEngine` legitimately holds two rows with the same key (a sent line plus a new draft of the same dish), and the platform indexes `unique(order_id, client_line_id)`, so a key would turn a valid order into a constraint failure. It is excluded from the platform's idempotency hash, so orders already delivered without one do not collide. (2) `PostgresRefundsRepository.issue` queues a `refund` event in `pos_sync_outbox` **in the refund's own transaction**, keyed on `client_refund_id` itself — one key for one act, so a replayed refund cannot queue a second delivery — and the drain's `'refund' => null` guard is replaced by the real §010 request. **Ordering:** a refund is never sent before its sale; while the sale's `pos_outbox` row is undelivered the refund *defers* (self-healing, no person needed), and a sale that was never queued at all holds the refund under `SALE_NEVER_QUEUED`. `REFUND_EXCEEDS_SOLD` quarantines: the ceiling only comes down, so retrying is a queue that never empties. `POS_CAPABILITY_MISSING` still defers — a manager granting `pos.refund` makes the next pass succeed. Migration 50 adds `pos_refunds.server_credit_note_number`, written back from the reply in the same transaction that marks the row delivered, exactly as a sale keeps the platform's invoice number; the till's grant on it is column-scoped. **One gap raised, not worked around** — see *Amendment to POS-BE-010*: a refund given as a flat amount off the bill has no lines, §010 has no shape for it, and the till holds those locally under `REFUND_HAS_NO_LINES` rather than inventing an attribution that would corrupt the platform's per-line counters. Tests: `test/data/cloud_refunds_test.dart` (18, PostgreSQL) + 6 pure ones in `test/data/outbox_drain_test.dart`. **Second defect found and fixed while building this:** the order drain's delivery bookkeeping shared one parameter map between two statements, which the driver refuses — so no cloud sale had EVER been marked delivered. The platform had the sale (idempotency held), but `delivered_at` was never written, the sale was resent on every pass forever and the "owed to the platform" count never came down. Nothing committed or deployed. |
| 2026-10-24 | **Amendment to POS-BE-022 raised: `held_count`.** `pending_count`/`oldest_pending_at` now exclude records the drain has held for a person; the heartbeat carries `held_count` beside them, so the old figure is their sum. The till gains a "Held sync items" list with Retry (audited, `terminal.manage`). Additive; `PROPOSED`. No backend code touched. |
