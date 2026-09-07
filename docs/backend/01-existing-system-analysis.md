# Backend — Existing System Analysis (for the Flutter POS)

**Author:** Agent 2 (Backend) · **Mode:** ANALYSIS-ONLY
**Repo under analysis:** `~/Projects/Web Application/xorder-new` — `apps/api`
**Analysed at:** `main` @ `2743c1e` · 2026-08-26
**Companion docs:** `02-pos-gap-analysis.md` · `03-pos-api-proposal.md` · `04-pos-sync-proposal.md` · `05-database-proposal.md` · `06-implementation-plan.md`

> **No backend code has been modified.** This document is the result of reading
> `apps/api` only. Every file path and line-level claim below was verified
> against the source, not inferred from `README.md` or `ARCHITECTURE.md` (both of
> which are stale on authentication — see §3).

---

## 1. Framework and project architecture

| Aspect | Reality |
|---|---|
| Framework | Laravel 13 (PHP), JSON API + a small SEO menu shell on `routes/web.php` |
| Data access | Eloquent ORM. No repository layer, no CQRS, no DDD ceremony. |
| Database | **SQLite in dev, PostgreSQL in prod** — identical Eloquent code, so any proposal must avoid engine-specific SQL |
| Layering | `Http/Controllers/{Auth,Admin,Dashboard,Public}` (thin) → `Http/Requests/*` (validation) → `Services/*` (multi-model logic) → `Models/*` → `Http/Resources/*` (output shaping) |
| Route map | `routes/api.php`, 514 lines, one file, heavily commented — the single source of truth for who may call what |
| Tests | 76 test files under `tests/{Feature,Unit}`. **CI runs these as a deploy gate**, so any approved work must land with tests or it cannot ship. |
| Deploy | push-to-main → CI → VPS. Prod is live at `https://xorder.io` and co-hosts a second product. |

The codebase is disciplined and internally consistent. Controllers are genuinely
thin, validation genuinely lives in FormRequests, and the comments explain *why*
rather than *what*. **The correct strategy for the POS is extension along the
existing seams, not a parallel subsystem.**

---

## 2. Domain model as it exists today

```
Restaurant ─┬─ Branch ─┬─ DiningArea ── DiningTable ─┬─ MenuSession ── TableVisit
            │          └─ (business_hours, geofence, egress_ips, supported_order_types)
            ├─ Category ── MenuItem ─┬─ OptionGroup ── Option
            │                        └─ (menu_item_option_group pivot, global groups)
            ├─ Combo ── ComboGroup ── ComboGroupItem
            ├─ Customer ── CustomerAddress
            ├─ Order ── OrderRound ── OrderItem
            ├─ BillRequest, InternalReview ── ReviewInternalNote
            ├─ Role (tenant RBAC), User (role, role_id)
            ├─ RestaurantFeature (per-tenant flags)
            └─ MenuViewDaily, MenuSession, Notification, DeviceToken, AuditLog
```

**33 models. Not one of them models money movement.** There is no `Payment`,
`Tender`, `Shift`, `Register`, `Drawer`, `Refund`, `CreditNote`, `TaxRule`,
`Charge`, `Invoice`, `Sequence`, `StockItem`, `Warehouse` or `StockMovement`.
This is not an oversight — XOrder is a QR-menu product where the diner pays the
restaurant out of band. The POS is the first feature that takes money.

---

## 3. Authentication — **Existing, reusable, one decision needed**

Stateless **JWT Bearer**, not Sanctum cookies. `README.md` and `ARCHITECTURE.md`
say Sanctum; they are wrong and `CLAUDE.md` already flags this.

- Guard: custom `jwt` driver registered by `Auth::viaRequest('jwt', …)` in
  `app/Providers/AppServiceProvider.php`.
- Token: `app/Support/Jwt.php` — HS256, claims `iss sub iat nbf exp rid`.
  `rid` binds the token to a restaurant so a stale token cannot outlive a tenant
  reassignment.
- TTL: `config/jwt.php` → `JWT_TTL`, **default 7 days**. `JWT_SECRET` is mandatory
  or login 500s.
- **No refresh token exists.**
- `users.password_changed_at` retroactively invalidates every token issued before
  it — a clean offboarding primitive, and a hazard for an offline till (§POS-BE-011).
- Login is **tenant-scoped**: `AuthController::resolveLoginTenantId()` derives the
  tenant from a `restaurant` slug in the body or the Host subdomain, so
  `username` is unique per tenant and an account can only sign in on its own
  tenant. `email` is nullable — **staff can already log in with a username and no
  email address, which is exactly what a cashier needs.**
- Rate limiting: named `login` limiter caps per-IP *and* per-(username, IP).

**Verdict: Existing / Reusable.** The POS signs in through
`POST /api/auth/login` unchanged. The only open item is token lifetime versus a
till that goes offline for hours — a decision, not a defect.

---

## 4. Authorization — **Existing, reusable, needs new vocabulary only**

Two permission systems share one Laravel Gate namespace.

| | Platform staff | Restaurant staff |
|---|---|---|
| Enum | `App\Enums\Capability` (9 values) | `App\Enums\TenantCapability` (28 values) |
| Source of truth | static matrix `RoleEnum::capabilities()` | per-restaurant `roles` row, `users.role_id` |
| Bypass | `Gate::before` → `SUPER_ADMIN` allows all | `RESTAURANT_ADMIN` (owner) holds all, via `User::holdsTenantCapability()` |
| Editor | fixed | `Dashboard\RoleController`, `GET /api/dashboard/roles/capabilities` |

`TenantCapability` is already **per-verb** (`menu.create`, `menu.update`,
`menu.delete`, …) with `resource()`, `action()`, `group()`, `implies()`,
`expand()` and a `legacyManageMap()` translation for pre-split values. It also
carries derived, non-checkbox abilities defined directly in `AppServiceProvider`:
`branches.list`, `orders.read`, `bills.read`, `tables.live`.

Dashboard routes stack four orthogonal gates, and the comment in `routes/api.php`
states the distinction precisely:

```
role:…                   which portal this account belongs to
feature:<key>            whether the tenant BOUGHT this capability (plan)
can:<tenant capability>  whether this PERSON may do it
subscription.writable    whether the tenant may write at all right now
```

**Verdict: Existing / Reusable.** The POS needs *enum cases*, not machinery — new
values flow into the role editor and `UserResource.capabilities[]` automatically.

---

## 5. Multi-tenancy — **Existing, structural, excellent**

`app/Models/Scopes/RestaurantScope.php` + the `BelongsToRestaurant` trait
auto-scope every tenant query to `auth()->user()->restaurant_id`.

- `restaurant_id` is **never** read from request input.
- Cross-tenant access resolves to **404, not 403** (no existence leak).
- `users.role` and `users.restaurant_id` are deliberately **non-fillable**
  (`app/Models/User.php`); only trusted services set them via `forceCreate`/`forceFill`.
  This is what prevents self-promotion.
- `TenantContext::overrideId()` / `clearOverride()` pins the tenant on
  unauthenticated public paths, always released in a `finally`.
- **`User` deliberately has no `RestaurantScope`** — staff queries are scoped by
  hand (`Dashboard\StaffController`). Any POS code touching users must do the same.

**Verdict: Existing / Reusable. Do not touch.** Every POS table inherits isolation
for free by using the trait.

---

## 6. Branch isolation — **Partially reusable · this is a real finding**

Branches exist as a **data dimension**, not a **security boundary**.

- `branches` carries `code`, `supported_order_types`, `business_hours`,
  `geofence`, `egress_ips`, `require_branch_wifi`, `is_open`, `is_active`.
- `orders.branch_id`, `table_visits.branch_id`, `menu_sessions.branch_id` all exist.
- **There is no `users.branch_id` and no per-user branch scoping anywhere.** Any
  restaurant staff account can read and write every branch's data.

For a QR-menu product that is fine. For a POS it is a decision the owner must
make consciously: *may a cashier at the Maadi till see Zamalek's shift report?*
Today the answer the code gives is **yes**. See `05-database-proposal.md` §B7.

---

## 7. Catalog, pricing and the option model — **Existing, reusable, one gap**

`menu_items`: `price`, `discounted_price` (both `decimal(10,2)`), `is_available`,
`is_featured`, `display_order`, `SoftDeletes`.

`option_groups` is more capable than it first appears:

| Column | Meaning |
|---|---|
| `is_variant` | the group *prices* the item (size), rather than adding to it |
| `is_global` | a reusable library group rather than an inline one |
| `apply_scope` | `items` \| `categories` \| `all` — how broadly a global group attaches |
| `is_required`, `max_select` | selection rules |
| `display_name_ar/en` | customer-facing label distinct from the internal name |

`options`: `price`, `discounted_price`, `is_available`, `sort_order`.

Pricing rules already live on the server and are already authoritative:

- `MenuItem::displayPricing()` — the price actually shown/charged
- `MenuItem::defaultVariantOption()` — the default size
- `MenuItem::orderedOptionGroups()` — inline + shared + auto groups, de-duplicated
- `App\Services\VariantPricingService` — keeps `menu_items.price` in step with the
  default variant option

**The gap is exposure, not logic.** `PublicMenuService` injects auto-applied
groups via `withAutoOptionGroups()`, but the dashboard path never does:
`MenuItemResource` gates `option_groups` on
`relationLoaded('optionGroups') || relationLoaded('sharedOptionGroups')` only. A
restaurant-wide "Extras" group is therefore **visible to a diner's phone and
invisible to the dashboard** — and would be invisible to the POS.

**Verdict: Reusable (pricing logic) / Requires modification (exposure).**
Confirmed: Agent 1's POS-BE-003 is correct and the fix is small.

`sku`, `barcode`, `plu`, `article_number` — **none exist.** Confirmed by grep
across `app/` and `database/migrations/`.

---

## 8. Orders — **Partially reusable · the central problem**

### Schema

```
orders          id, restaurant_id, branch_id, dining_area_id, table_id,
                menu_session_id, table_visit_id, status(20), items(json),
                total decimal(10,2), currency(3), customer_id,
                customer_address_id, customer_name, customer_phone,
                order_type, note, source(40), timestamps
order_rounds    id, restaurant_id, order_id, menu_session_id, sequence,
                total decimal(10,2), note, submitted_at    UNIQUE(order_id, sequence)
order_items     id, restaurant_id, order_id, order_round_id, name(200),
                quantity, options(json), note,
                unit_price decimal(10,2), line_total decimal(10,2)
```

The `Order → OrderRound → OrderItem` graph is genuinely good and models
multi-round dine-in correctly.

### Four blocking facts

1. **There is no authenticated order-creation endpoint anywhere.** The only write
   path is `POST /api/public/restaurants/{slug}/orders` — unauthenticated,
   throttled `20,1`.
2. **`order_items` has no `menu_item_id`** — only a `name` string
   (`2026_08_19_000100_create_table_visits_and_order_rounds.php`). Server-side
   re-pricing is therefore *structurally impossible* on the current schema. This
   is the single most important finding in this document, and it independently
   degrades product reporting for the existing QR product.
3. **Totals come from the client.** `PublicOrderController::store()` recomputes
   `total` as a `(float)` sum of client-submitted `line_total` values, clamped to
   `99999999.99`. The comment is explicit that this is acceptable *because no
   payment is taken*. At a till it is not acceptable.
4. **`OrderStatus` is `NEW | COMPLETED | CANCELLED`**, and `canTransitionTo()`
   forbids ever returning to `NEW`. There is no settled/paid/refunded concept.

### What *is* reusable from that controller

The table-visit binding discipline is exactly right and should be copied verbatim:
`lockForUpdate()` on the `TableVisit`, then `lockForUpdate()` on the open `Order`,
inside `DB::transaction()`, with `TenantContext` released in a `finally`. Also
reusable: `recordRound()`, `NotificationService` via `app()->terminating()`,
`AuditLogger`, `OrderResource`.

**Verdict: Partially reusable.** Extend this graph with a `channel` column;
do **not** create a parallel POS order table. Agent 1's recommendation is right —
two order histories would be a product defect, not just duplication.

---

## 9. Money handling — **Requires a decision · precision hazard**

- Every monetary column is `decimal(10,2)`. Casts are `decimal:2`.
- The order path does **`(float)` arithmetic** (`PublicOrderController::store`,
  `recordRound()` divides `line_total / quantity` and `round(…, 2)`).
- `CurrencyEnum` contains **KWD, BHD, OMR and JOD — all three-decimal currencies** —
  alongside two-decimal ones. `decimal(10,2)` cannot represent 0.001 KWD.
- No minor-unit representation anywhere.

For a display-only menu this is invisible. For split tenders and change
calculation it produces cent drift, and for a Kuwaiti tenant it is simply wrong.
Agent 1 asks for integer minor units on POS money fields; §POS-BE-007 explains why.
**This must be a decision, not an accident.**

---

## 10. Invoice / serial numbering — **Missing**

`Order::code()` is literally `'ORD-'.$this->id`.

That is a database primary key wearing a prefix. It is not per-branch, it has
gaps, it leaks tenant-wide order volume to anyone holding one receipt, and it is
not a legal invoice number in any of the jurisdictions `CurrencyEnum` covers.
No sequence table, prefix, padding or reset rule exists.

**Verdict: Missing.** And note the rule the owner's brief already states: the
human-readable number must **not** be the primary key.

---

## 11. Auditing — **Existing, reusable**

- `App\Services\AuditLogger::record(string $action, array $opts)` — static entry point.
- Writes both an `audit_logs` row and a **per-day activity file**
  (`writeToActivityFile()`), exposed by `Admin\AuditLogController` including
  file listing and download.
- `App\Models\Concerns\Auditable` on models; `auditActorRoleFallback()` and
  `auditLabel()` are overridable — `Order` already overrides both, attributing
  diner orders to `CUSTOMER`.
- `$auditExclude` suppresses noisy columns (`Branch` excludes `egress_ips`).

**Verdict: Existing / Reusable.** Every financial action the POS introduces can be
audited by calling `AuditLogger::record()` and using the `Auditable` trait — no
new machinery. This satisfies the owner's rule 9 ("financial transactions must be
auditable") at low cost.

---

## 12. Inventory, warehouses, stock movement — **Missing entirely**

No `Warehouse`, `StockItem`, `StockLevel`, `StockMovement`, `Recipe` or
`Ingredient` model, table or service. `menu_items.is_available` is a manual
boolean toggle, not a stock level.

Agent 1 has **not** requested inventory, and the POS requirement set does not
depend on it. **Out of scope**; recorded here so it is not mistaken for an
oversight later.

---

## 13. Synchronisation and idempotency — **Missing entirely**

- No `client_transaction_id`, `idempotency_key`, `request_id` or equivalent
  anywhere in `app/` or `database/migrations/`.
- No `updated_since` / delta parameter on any read. Every catalog read is a
  full-collection read.
- No tombstone endpoint — though `menu_items` and `categories` already use
  `SoftDeletes`, so deletions **are** recoverable from `deleted_at` without a new
  table.
- Nothing in the codebase has ever needed to survive a client retry.

**Verdict: Missing.** This is the largest genuinely-new surface the POS requires.

---

## 14. Feature entitlement and plan limits — **Existing, reusable**

- `App\Enums\Feature` — 12 flags, with a `requires()` prerequisite graph,
  `defaultSet()` and a transitive `resolve()`.
- `restaurant_features` table + `PlanEntitlementService` + `EnsureFeatureEnabled`
  (`feature:<key>` middleware).
- `PlanLimitService` — `max_items`, `max_categories`, `max_branches`, `max_staff`,
  each returning "the exceeded limit or null". `max_staff` is the most recent and
  is the exact precedent for a `max_terminals` limit.
- `EnsureSubscriptionAllowsWrites` (`subscription.writable`) puts a lapsed tenant
  into read-only mode — but deliberately **not** for order handling, so a
  restaurant whose plan expired can still work the orders already in the queue.

**Verdict: Existing / Reusable.** Selling the POS as its own SKU is a one-case
enum addition plus plan wiring.

---

## 15. Customers — **Existing, reusable, one verb missing**

`customers` + `customer_addresses`, upserted through
`App\Services\CustomerDirectory::upsert(array $data): array`, with phone
normalisation via `App\Traits\NormalizesPhoneNumbers` (including Arabic-Indic
digit folding). Dashboard access is `GET /api/dashboard/customers`, gated
`can:customers.view`.

`TenantCapability` has **`customers.view` only** — deliberately, per its own
docblock ("read-only from the dashboard"). Creating a customer from the till
therefore needs a new verb *and* an authenticated endpoint that calls the same
`upsert()`, or the directory will split into two identities per phone number.

**Verdict: Reusable core / Missing write surface.**

---

## 16. Capability classification summary

| Capability | Status | Evidence |
|---|---|---|
| Framework, layering, conventions | **Existing / Reusable** | §1 |
| JWT authentication | **Existing / Reusable** | §3 |
| Username-only (email-less) staff login | **Existing / Reusable** | §3 |
| Token lifetime for an offline till | **Requires a decision** | §3, POS-BE-011 |
| Tenant RBAC machinery | **Existing / Reusable** | §4 |
| POS permission vocabulary | **Missing (enum cases only)** | §4, POS-BE-002 |
| Tenant isolation | **Existing / Reusable** | §5 |
| Branch isolation as a security boundary | **Missing** | §6 |
| Catalog + option model | **Existing / Reusable** | §7 |
| Server-side pricing logic | **Existing / Reusable** | §7 |
| Auto-applied groups on the dashboard read | **Requires modification** | §7, POS-BE-003 |
| SKU / barcode | **Missing** | §7, POS-BE-004 |
| `branches.code` / `supported_order_types` exposure | **Requires modification** | §6, POS-BE-005 |
| Order graph (`Order→Round→Item`) | **Partially reusable** | §8 |
| Authenticated order creation | **Missing** | §8, POS-BE-006 |
| `order_items.menu_item_id` | **Missing (prerequisite)** | §8 |
| Server-authoritative totals | **Missing** | §8 |
| Money precision / minor units | **Requires a decision** | §9 |
| Invoice numbering | **Missing** | §10 |
| Payments / tenders / split payment | **Missing** | §2 |
| Refunds / credit notes | **Missing** | §2, POS-BE-010 |
| Shifts / cash movements / terminals | **Missing** | §2, POS-BE-009 |
| Tax rules / service charges | **Missing** | §2, POS-BE-013 |
| Audit trail | **Existing / Reusable** | §11 |
| Inventory / warehouses | **Missing — out of scope** | §12 |
| Idempotency | **Missing** | §13 |
| Incremental sync | **Missing** | §13, POS-BE-012 |
| Feature flags + plan limits | **Existing / Reusable** | §14 |
| Customer directory | **Reusable core / missing write verb** | §15, POS-BE-014 |

---

## 17. Constraints, risks and assumptions

**Constraints**

1. **Production is live.** Every proposal must be additive and backward compatible.
2. **CI runs `apps/api` tests as a deploy gate.** No approved work ships without tests.
3. **SQLite dev / PostgreSQL prod.** No engine-specific SQL; partial unique indexes
   and `ON CONFLICT` behave differently and must be avoided or abstracted.
4. **`decimal(10,2)` is the established money type**, and three-decimal currencies
   are already in the enum.
5. The public menu SPA and dashboard SPA are deployed from the same repo; a
   `Resource` shape change ripples to both.

**Risks**

| Risk | Severity | Note |
|---|---|---|
| Adding `menu_item_id` to `order_items` touches the live order path | **Medium** | Nullable + backfill-by-name; never break the public endpoint |
| Money-representation change mid-flight | **High if deferred** | Cheap now, expensive after the first POS receipt is printed |
| Two order histories if a parallel POS table is created | **High** | Avoidable by decision — use `orders.channel` |
| Branch-scoping added later | **Medium** | Adding `users.branch_id` after tills are deployed is a migration *and* a policy change |
| Offline queue + 7-day JWT | **Medium** | Support burden, not data loss — the client never discards the queue |

**Assumptions** — flagged because they are the owner's calls, not mine:

- **A1.** The POS is sold as an entitlement (`feature:pos`), not bundled free.
- **A2.** POS orders live in the existing `orders` table, distinguished by `channel`.
- **A3.** Inventory is out of scope for POS v1.
- **A4.** v1 records a card payment taken on a **standalone bank terminal**; the
  backend is not a payment processor and stores no PAN data.
- **A5.** Per-user branch scoping is out of scope for v1 unless the owner says otherwise.

---

> **BACKEND IMPLEMENTATION HAS NOT STARTED. OWNER APPROVAL IS REQUIRED.**
