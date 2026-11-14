# Research — Tenant Permission Management & a Standalone POS Module

Date: 2026-08-22 · Scope: `xorder-cloud` @ `main` (0aa7670)

Two asks, researched against the actual code:

1. **Permission management + create users** — can a Restaurant Admin create staff and restrict what they see?
2. **POS as a standalone module** — what would it take?

Short answer: (1) is a *half-built* system — a complete RBAC exists on the platform side and is
entirely absent on the tenant side. (2) is a *greenfield* module with real foundations (orders,
tables, menu, tenancy) but **zero** money/payment/shift/tax primitives. **(1) is a hard prerequisite
for (2)** — a POS without cashier accounts is not a POS.

---

## Part 1 — Permission Management & User Creation

### 1.1 What already exists (platform side) — and it's good

The Super Admin portal already has a full, well-factored RBAC. This is the pattern to copy, not
replace:

| Layer | File | What it does |
|---|---|---|
| Roles | `apps/api/app/Enums/RoleEnum.php` | `SUPER_ADMIN, ADMIN, MODERATOR, SALES, SUPPORT` + `RESTAURANT_ADMIN` |
| Abilities | `apps/api/app/Enums/Capability.php` | 9 fine-grained caps (`restaurants.manage`, `plans.manage`, …) |
| Role→caps | `RoleEnum::capabilities()` | static matrix |
| Gate wiring | `app/Providers/AppServiceProvider.php:110-120` | `Gate::before` bypass for SUPER_ADMIN + `Gate::define` per capability |
| Route gate | `routes/api.php` | outer `role:SUPER_ADMIN,ADMIN,…` then `can:<capability>` per section |
| Coarse gate | `app/Http/Middleware/EnsureRole.php` | also rejects non-`ACTIVE` accounts |
| CRUD | `Admin/PlatformUserController.php` + `Services/PlatformUserService.php` | create/update/delete/reset-password, guarded `role`/`restaurant_id` |
| UI | `apps/web/src/pages/admin/UsersList.vue`, `UserForm.vue` | list + form |
| UI gating | `packages/api-client/src/auth.js` (`ROLE_CAPS`, `can()`) + router `meta.capability` | mirrors server caps; server stays authoritative |

Notable good habits already in place that any new work must preserve:

- `users.role` and `users.restaurant_id` are **deliberately non-fillable** (`app/Models/User.php:24-35`).
  Only trusted services set them, via `forceCreate`/`forceFill`. This is what stops self-promotion.
- `username` is **unique per tenant** (`2026_07_21_000300_make_username_unique_per_tenant.php`) and
  `email` is nullable — so staff can log in with a username and no email. Directly useful for POS
  cashiers.
- JWT carries `rid` (restaurant id) and `password_changed_at` invalidates every prior token
  (`app/Support/Jwt.php`, `AppServiceProvider:173`) — clean staff-offboarding primitive.
- `TenantContext::restaurantId()` returns `$user->restaurant_id` for **any** non-super-admin, so new
  tenant roles get `RestaurantScope` isolation for free, with zero new code.

### 1.2 What does not exist (tenant side) — the actual gap

- `RoleEnum::RESTAURANT_ADMIN->capabilities()` returns **`[]`**. There is no tenant capability model.
- The entire `/api/dashboard/*` group is gated by exactly one check: `role:RESTAURANT_ADMIN`
  (`routes/api.php`). Every restaurant user therefore sees and can do *everything*.
- There is **no endpoint anywhere** to create a second user inside a restaurant. The only tenant user
  is the one minted once by `RestaurantProvisioningService::provision()`. The Super Admin can edit or
  reset that single admin (`Admin/RestaurantAdminController`), and that's it.
- What *is* gated per-tenant today is orthogonal to people:
  - `feature:<key>` — plan entitlement (`EnsureFeatureEnabled`)
  - `subscription.writable` — lapsed-subscription read-only mode
  Neither says *who* may do a thing, only *whether the tenant bought it*.
- Frontend has no tenant-side concept either: `nav.config.js` gates only on **feature flags**
  (`permission:` there means feature key, not user permission — a naming trap worth renaming);
  restaurant routes in `router/index.js` carry no `meta.capability`; `auth.js` `ROLE_CAPS` has no
  tenant half; `homeRoute()`/`inPortalHome()` hard-code `isRestaurantAdmin`.

### 1.3 Design options

**Option A — Fixed tenant roles (enum-driven).**
Add `MANAGER, CASHIER, WAITER, KITCHEN` to `RoleEnum`, add a `TenantCapability` enum, extend
`RoleEnum::capabilities()`. No new tables. Mirrors the platform side exactly.
*Pros:* smallest diff, reuses `Gate`/`can:`/`EnsureRole` untouched, ~3–5 days.
*Cons:* a restaurant cannot say "my waiters may also apply discounts". Not sellable as a feature.

**Option B — Custom roles per restaurant (table-driven).**
New `roles` table (`restaurant_id`, `name_ar/en`, `capabilities` JSON, `is_system`), `users.role_id`
nullable FK. Restaurant Admin builds roles in the dashboard.
*Pros:* real product feature, upsell-able, matches what POS buyers expect.
*Cons:* more surface (role CRUD UI, seeding system roles per tenant, migration of existing users),
plus a `Gate::define` that reads from DB instead of a static matrix.

**Recommendation: B, seeded with A's presets.** Ship `roles` from day one, auto-seed four
system roles (Manager / Cashier / Waiter / Kitchen) per restaurant, mark them `is_system` so they
can't be deleted, and let the Admin clone/customize. Keep `users.role` as the coarse **portal
discriminator** (`RESTAURANT_ADMIN` vs platform roles) and put fine-grained permission in `role_id`.
Doing A first and B later means migrating live user rows twice.

### 1.4 Concrete work items (Option B)

**Backend**
1. `App\Enums\TenantCapability` — e.g. `orders.view/manage`, `menu.view/manage`, `tables.manage`,
   `customers.view`, `reports.view`, `reviews.manage`, `branches.manage`, `settings.manage`,
   `staff.manage`, and (for POS) `pos.operate`, `pos.discount`, `pos.void`, `pos.refund`,
   `pos.shift.close`.
2. Migration: `roles` table + `users.role_id` FK. Backfill: existing `RESTAURANT_ADMIN` users get
   `role_id = null` and keep implicit full access (mirror `Gate::before` — a tenant *owner* bypass).
3. `Gate::define` for each `TenantCapability`, resolving from `$user->role?->capabilities`.
   Owner bypass: `RESTAURANT_ADMIN` with `role_id === null` → true.
4. `TenantUserService` (mirror of `PlatformUserService`) + `Dashboard\StaffController` +
   `Dashboard\RoleController`. **`forceCreate` only** — never mass-assign `role`/`restaurant_id`.
5. Widen the group gate: `role:RESTAURANT_ADMIN` → a tenant-role list (or a `role:tenant` helper),
   then annotate ~90 dashboard routes with `can:<tenant capability>`.
6. `RestaurantProvisioningService`: seed the four system roles inside the existing transaction.
7. Plan hooks: `Feature::STAFF_MANAGEMENT` + `plans.max_users` (mirror `max_items`/`max_branches` in
   `PlanLimitService`).

**Frontend**
8. `auth.js`: tenant `ROLE_CAPS` half + make `can()` read server-sent capabilities rather than a
   hard-coded mirror (the tenant set is dynamic under Option B — send it in `UserResource`).
9. `UserResource`: add `role_id`, `role_name`, `capabilities[]`. `AuthController::me` already
   eager-loads `restaurant.features`; add the role.
10. `nav.config.js`: add a `capability` field distinct from the existing (feature-flag) `permission`,
    and rename `permission` → `feature` to kill the ambiguity.
11. Restaurant routes: add `meta.capability`; generalize `isRestaurantAdmin` →`isTenantUser` in
    `homeRoute()` / `inPortalHome()`.
12. New dashboard pages: Staff list/form, Roles list/form. Bilingual AR/EN as everywhere else.

### 1.5 Traps found in the code

- **`User` does NOT use `BelongsToRestaurant`** — it has no `RestaurantScope`. A tenant staff
  endpoint must scope by `restaurant_id` **explicitly**, exactly like
  `PlatformUserController::guardTarget()` does. Adding the global scope to `User` wholesale would
  break login lookups and Super Admin queries — don't.
- `users.email` still carries a unique index. Multiple NULLs are fine in both SQLite and Postgres, so
  email-less cashiers work — but two staff sharing a real email will 500 at the DB. Validate.
- Privilege escalation: a `MANAGER` with `staff.manage` must not be able to create a
  `RESTAURANT_ADMIN` or assign capabilities they don't hold. Needs an explicit "cannot grant above
  self" check — the platform side sidesteps this because only SUPER_ADMIN holds
  `platform_users.manage`.
- `audit_logs.actor_role` is `string(40)` — fine for new role names, but under Option B log the role
  *name* plus `role_id`, since a tenant can rename roles.
- Deleting a role that users hold — needs `restrictOnDelete` or a reassign flow.

**Estimate:** ~2 weeks for one developer (backend 5–6 d, frontend 4–5 d, tests 2–3 d). The 61
existing feature tests give a solid regression net; expect to touch `PerTenantAuthTest`,
`RestaurantProvisioningTest`, and every `role:RESTAURANT_ADMIN` assertion.

---

## Part 2 — POS as a Standalone Module

### 2.1 Foundations that already exist and are reusable

Genuinely substantial — POS is not starting from zero:

- **Order graph:** `Order` → `OrderRound` → `OrderItem`, plus `TableVisit` and `MenuSession`
  (`2026_08_19_000100_create_table_visits_and_order_rounds.php`). `OrderRound` is already documented
  as "kitchen-visible submission round" — that *is* a fire-to-kitchen ticket.
- **Floor plan:** `DiningArea`, `DiningTable`, table QR tokens, and a live occupancy endpoint
  (`GET dashboard/tables/live`) with active-order and open-request signals per table. A POS table map
  can render off this today.
- **Menu & pricing:** `MenuItem`, `OptionGroup`/`Option` (incl. `is_variant` sizes and
  `discounted_price`), `Combo`, and `VariantPricingService`.
- **Tenancy & authz:** `RestaurantScope` + `TenantContext` make cross-tenant leakage structural, not
  a code-review concern.
- **Ops plumbing:** `NotificationService` + FCM push, `AuditLogger`, `PulseController` heartbeat
  (ETag'd) — a POS/KDS poll can piggyback.
- **Entitlements:** `Feature` enum + `PlanEntitlementService` + `EnsureFeatureEnabled` — adding
  `Feature::POS` is a one-line enum case plus plan wiring.
- **UI:** shared `packages/ui` (SakaiLayout, Dialog, Toast…), bilingual AR/EN with RTL, PrimeIcons.

### 2.2 What is completely missing

Verified by grep across `apps/api/app`, `apps/*/src`, `packages/*/src` — **no** payment, tender,
cashier, shift, till, refund, tax, or print concept exists anywhere. Specifically:

| Missing | Detail |
|---|---|
| **Payments** | No `payments` table, no tender types (cash / card / wallet / voucher), no split bill, no change-due, no partial payment. `StoreOrderRequest` explicitly notes "no payment is taken through this endpoint". |
| **Money breakdown** | `orders` has only `total decimal(10,2)` + `currency`. No `subtotal`, `discount`, `tax`, `service_charge`, `tip`, `rounding`. |
| **Tax** | Zero tax model. No `tax_rate` on restaurant, branch, or item. No inclusive/exclusive handling. |
| **Cash management** | No shift/register session, no opening float, no cash count, no X/Z report, no over/short. |
| **Receipts** | `OrdersView.vue` has a screen-only "receipt" dialog. No receipt sequence number, no per-branch numbering, no printing (ESC/POS or `window.print` template), no reprint audit. |
| **Voids / refunds / comps** | `OrderStatus` is only `NEW / COMPLETED / CANCELLED`, and `canTransitionTo()` forbids reopening. No reason codes, no manager-approval flow, no partial refund. |
| **Item traceability** | **`order_items` has no `menu_item_id`** (`…create_table_visits_and_order_rounds.php:54-64` — only a `name` string), and `orders.items` is a free-form JSON snapshot. POS repricing, stock deduction, and honest product reporting all need the real id. |
| **Terminals** | No device/register registry, no branch↔terminal binding, no printer config. |
| **KDS** | No kitchen display surface (though `OrderRound` is the right seed). |
| **Offline** | Fully online SPA, JWT with TTL, no local queue. A till that stops selling when Wi-Fi drops is a returned product. |
| **Inventory** | No stock, no recipe/BOM, no 86-ing beyond a manual availability toggle. |

### 2.3 "Standalone module" — what that should mean here

Two readings. Recommending the second:

- ❌ **Separate service/repo.** Would duplicate menu, pricing, tenancy, auth, and the tenant DB.
  Rejected — the POS's whole value is sharing the menu and orders with the QR product.
- ✅ **Fourth app in the monorepo: `apps/pos` (Vue 3 SPA, dev `:5176`)**, talking to the same Laravel
  API under a new `/api/pos/*` route group, gated by `feature:pos` + the tenant capabilities from
  Part 1, and shipped/sold as its own plan feature. "Standalone" = independently deployable,
  independently entitled, independently priced — not independently architected.

Rationale: it matches the existing repo shape exactly (`apps/web`, `apps/landing`, `apps/menu`), gets
`packages/ui` + `packages/api-client` for free, and keeps one source of truth for the menu.

A POS UI is a genuinely different shell from the dashboard — touch-first, large targets, keypad,
no sidebar, offline-aware — which is why it wants its own app rather than another `dashboard/` route.

### 2.4 Proposed phasing

**Phase 0 — Tenant RBAC (Part 1).** Blocking. ~2 weeks.

**Phase 1 — Money data model.** Nothing user-visible; everything downstream depends on it.
- `payments` (order_id, tender_type, amount, reference, terminal_id, shift_id, created_by, refund_of_id)
- `pos_shifts` (branch_id, terminal_id, opened_by/at, closing float, counted cash, variance, status)
- `pos_terminals` (branch_id, name, printer config, last_seen_at)
- `orders`: `subtotal`, `discount_total`, `tax_total`, `service_charge`, `paid_total`, `channel`
- `order_items`: `menu_item_id` FK (nullable for historic rows) + `option_ids` JSON
- Per-branch receipt sequence
- Extend `OrderStatus` (`PREPARING`, `READY`, `SERVED`, `VOIDED`) and relax `canTransitionTo` for the
  new states only — keep the "never reopen to NEW" invariant.
- Tax config on restaurant/branch (rate, inclusive/exclusive, service-charge %).
~1.5–2 weeks.

**Phase 2 — POS app v1 (cash only).** Order entry (category/item grid, variants, modifiers, notes),
table map reusing `tables/live`, send-to-kitchen via `OrderRound`, settle with cash, print receipt.
~3–4 weeks.

**Phase 3 — Shifts, cash-up, corrections.** Open/close shift, X/Z reports, voids/refunds with reason
codes and manager approval, every one audited via `AuditLogger`. ~2 weeks.

**Phase 4 — KDS + offline + hardware.** Kitchen display (ticket lanes, bump), IndexedDB write queue
with idempotency keys, cash drawer kick via printer, barcode input. ~3–4 weeks.

**Phase 5 — Compliance (market-dependent).** Egypt ETA e-invoicing / KSA ZATCA Phase 2 (QR + signed
XML) if selling into those markets. Substantial and regulated — scope separately once a target market
is confirmed.

**Rough total to a sellable v1 (Phases 0–3): ~9–11 weeks** for one full-stack developer.

### 2.5 Risks & decisions to settle before building

1. **Server-side pricing is non-negotiable.** The current public order path recomputes the total from
   *client-submitted* `line_total` values (`PublicOrderController::store`) — acceptable when no money
   changes hands, **unacceptable** for POS. POS must price from `menu_item_id` + option ids
   server-side. Recommend integer minor units in the money path, formatting at the edge; the existing
   `(float)` arithmetic will produce cent drift on split bills.
2. **Payment idempotency.** A double-tapped "Pay" must not create two payments. Client-generated
   idempotency key, unique-indexed.
3. **Offline vs. JWT.** Token TTL and `password_changed_at` invalidation conflict with an offline
   till. Needs a deliberate answer (longer-lived POS-terminal token? device-bound refresh?) rather
   than an accident.
4. **Card payments.** Recommend **cash-only + "card via external terminal, recorded as a tender
   type"** for v1. Integrating a payment processor is a regulated, contract-bound workstream — don't
   bundle it into the POS build.
5. **Concurrency at the table.** Waiter POS and diner QR can both add to the same open `TableVisit`.
   The existing code already does `lockForUpdate()` on the visit — extend that discipline to the POS
   write path.
6. **Reporting split.** POS revenue vs. QR-order revenue must be distinguishable — hence the
   `orders.channel` column in Phase 1, before any reports are written against it.
7. **Pricing/packaging.** POS is a new SKU: `Feature::POS`, likely `plans.max_terminals`, and a
   landing-page pricing card (the landing pricing already renders live from active `/plans`).

---

## Recommended order

1. **Part 1 (tenant RBAC + staff users)** — ~2 weeks. Ships standalone value (restaurants have asked
   for staff accounts regardless of POS) and unblocks everything else.
2. **Phase 1 money data model** — ~2 weeks. Invisible but load-bearing; also retro-fixes
   `order_items.menu_item_id`, which improves existing product reports.
3. **`apps/pos` v1** — ~4 weeks.
4. Shifts/cash-up, then KDS/offline.

Open questions for the product owner: target market for tax/e-invoicing compliance; cash-only vs.
card at v1; custom roles (Option B) vs. fixed roles (Option A); whether POS is bundled into an
existing plan or sold as its own SKU.
