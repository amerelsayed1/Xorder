# 01 — Existing System Analysis

**Author:** Agent 1 (Flutter POS Desktop)
**Date:** 2026-08-25
**Scope inspected:**

| What | Path | Verdict |
|---|---|---|
| Flutter POS app | `~/Projects/Mobile Application/xorder-pos` | Bare `flutter create` output. `lib/main.dart` = counter demo. No git history. **Greenfield.** |
| XOrder backend + web | `~/Projects/Web Application/xorder-cloud` | Live product (`https://xorder.io`). Laravel 13 API + 3 Vue SPAs, pnpm/Turborepo. **Authoritative source of truth.** |
| Prior research | `xorder-cloud/docs/RESEARCH_RBAC_AND_POS.md` (2026-08-22) | Still accurate on the POS gap. Its recommendation of a Vue `apps/pos` is **superseded** by the decision to build a Flutter desktop app. |

> **Cross-repo note.** The POS app and the backend live in two different
> repositories on this machine. Agent 1 owns `xorder-pos/` only, and has made
> **no** change of any kind inside `xorder-cloud/`. The coordination files under
> `xorder-pos/docs/coordination/` are the shared channel; their absolute path is
> stated at the top of each file so Agent 2 can find them.

---

## 1. Backend shape (what the POS will talk to)

Laravel 13 JSON API at `apps/api`, dev port `:8100`.

- **Auth:** stateless **JWT Bearer**, custom `jwt` guard registered via
  `Auth::viaRequest()` in `app/Providers/AppServiceProvider.php`, backed by
  `app/Support/Jwt.php`. *Not* Sanctum — the `README`/`ARCHITECTURE` files that
  say Sanctum are stale, per `CLAUDE.md`.
  Claims: `iss, sub, iat, nbf, exp, rid` (restaurant id). TTL from `config/jwt.ttl`
  (minutes), echoed to the client as `expires_in` seconds.
  `users.password_changed_at` invalidates every token issued before it.
- **Tenancy:** structural. `App\Models\Scopes\RestaurantScope` + the
  `BelongsToRestaurant` concern auto-scope every tenant query to
  `auth()->user()->restaurant_id`. `restaurant_id` is **never** read from request
  input. Cross-tenant access returns **404**, not 403.
- **Login is tenant-scoped:** `AuthController::resolveLoginTenantId()` resolves the
  tenant from an explicit `restaurant` slug in the request body, falling back to
  the Host subdomain. Usernames are unique *per tenant*
  (`2026_07_21_000300_make_username_unique_per_tenant.php`), and `email` is
  nullable — so **username-only cashier accounts already work**.
- **DB:** SQLite in dev, PostgreSQL in prod.
- **Locale:** clients send `X-Locale: en|ar`; every model carries `*_ar`/`*_en` pairs.

### Route groups

| Prefix | Gate stack | Notes |
|---|---|---|
| `/api/auth/*` | — / `auth:jwt` | `login`, `logout`, `me`, `change-password`, password reset |
| `/api/admin/*` | `auth:jwt` + `role:<platform roles>` + `can:<Capability>` | Super-admin portal. Not for POS. |
| `/api/dashboard/*` | `auth:jwt` + `role:RESTAURANT_ADMIN,RESTAURANT_STAFF` + `feature:<key>` + `can:<TenantCapability>` + `subscription.writable` | **This is the tenant surface the POS would reuse.** |
| `/api/public/*` | none | Diner-facing menu/order endpoints |

Four orthogonal gates stack on the dashboard group, and they answer different questions:

- `role:` — which portal this account belongs to
- `feature:<key>` — did the **tenant** buy this (plan entitlement, `App\Enums\Feature`)
- `can:<tenant capability>` — may this **person** do it (`App\Enums\TenantCapability`)
- `subscription.writable` — may the tenant write at all right now

---

## 2. Reusable — POS is not starting from zero

### 2.1 Authentication & identity — **reusable as-is**

`POST /api/auth/login` with `{username, password, restaurant}` returns
`{data: UserResource, token, token_type: "Bearer", expires_in}`.
`GET /api/auth/me` re-bootstraps.

`UserResource` (`app/Http/Resources/UserResource.php`) already emits everything a
POS session screen needs:

```
id, name, username, email, role, restaurant_id, status,
is_owner, role_id, role_name, role_name_ar,
capabilities[],            // ← authoritative permission list, server-computed
restaurant { …, currency, currency_symbol, brand_color, default_language, bilingual, timezone, features }
```

`capabilities[]` is exactly the shape a Flutter `PermissionSet` wants. The server
stays authoritative; the client mirror is UX-only.

### 2.2 Tenant RBAC — **reusable, already shipped**

`App\Enums\TenantCapability` is a live, per-verb capability enum (`menu.view`,
`menu.create`, `orders.update`, `staff.delete`, …) with `roles` table
(`2026_08_22_000100_create_roles_table.php`), `users.role_id`,
`TenantRoleService`, `TenantUserService`, `Dashboard\StaffController`,
`Dashboard\RoleController`. `RESTAURANT_ADMIN` is the owner and implicitly holds
everything (`User::holdsTenantCapability()`).

Consequence for the POS: **cashier accounts are already creatable today** by the
restaurant owner. Phase 0 of the older research is **done**.

What is missing is the POS *half* of the vocabulary — there is no `pos.operate`,
`pos.discount`, `pos.void`, `pos.refund`, `pos.shift.close`, `pos.price_override`.
Raised as `POS-BE-002`.

### 2.3 Catalog — **reusable, one gap**

`GET /api/dashboard/items`, `/categories`, `/option-groups`, `/combos`
(`can:menu.view`). `MenuItemResource` returns:

```
id, restaurant_id, category_id, name_ar/en, description_ar/en,
price, discounted_price, image_url, is_available, is_featured, display_order,
option_groups[] { id, is_global, name_ar/en, is_required, is_variant, max_select,
                  options[] { id, name_ar/en, price, discounted_price, is_available } }
```

Two real subtleties the POS must honour, both already solved server-side:

1. **A variant group replaces the item price, it does not add to it.**
   `MenuItem::defaultVariantOption()` + `displayPricing()` — the first *available*
   option of the first `is_variant` group is the default and *is* the price.
   `VariantPricingService` keeps `menu_items.price` in sync with it.
   The Flutter cart engine must reproduce this rule exactly or every sized item
   is mispriced.
2. **Option groups reach an item by three paths** — inline (`menu_item_id` on the
   group), shared via the `menu_item_option_group` pivot, and auto-applied by
   `apply_scope = 'categories' | 'all'`. `MenuItem::orderedOptionGroups()` merges
   and de-duplicates them. The dashboard `MenuItemResource` only emits the first
   two paths (`whenLoaded('optionGroups') || whenLoaded('sharedOptionGroups')`);
   the **public** resource is the one that gets `autoOptionGroups` injected by
   `PublicMenuService`. A POS reading `/dashboard/items` would silently miss
   restaurant-wide extras. Raised as `POS-BE-003`.

**Gap:** no barcode/SKU/PLU column exists anywhere on `menu_items`. Barcode
scanning has nothing to match against. Raised as `POS-BE-004`.

### 2.4 Branches & floor plan — **reusable**

- `GET /api/dashboard/branches` (`can:branches.list`) → `BranchResource`:
  `id, name_ar/en, address, phone, whatsapp_number, opening_hours, business_hours,
  map_url, latitude, longitude, geofence, geofence_enabled, require_branch_wifi,
  is_open, is_active, sort_order`.
  `branches.supported_order_types` exists as a column but is **not** in
  `BranchResource` — the POS needs it to show only enabled order types. Raised
  as `POS-BE-005`.
- `GET /api/dashboard/tables/live` (`can:tables.live`, `feature:table_management`)
  → per-table `{id, label, dining_area_id, area_name_ar/en, active_orders,
  has_request, has_new_order, occupied}`. A POS table map can render off this
  **today**, unchanged.
- `DiningArea`, `DiningTable`, `TableVisit` (with `lockForUpdate()` discipline in
  `PublicOrderController`), `MenuSession`.

### 2.5 Order graph — **partially reusable**

`Order → OrderRound → OrderItem`, plus `TableVisit`/`MenuSession`.
`OrderRound` is documented as a "kitchen-visible submission round" — that *is* a
fire-to-kitchen ticket, and it is the right primitive for POS "send to kitchen".

But the write path is diner-only: `POST /api/public/restaurants/{slug}/orders`
(`PublicOrderController::store`). It is unauthenticated, throttled `20,1`, and
explicitly takes no payment. The dashboard can only *read* orders and flip status
(`can:orders.read` / `can:orders.update`) — there is **no authenticated order
creation endpoint anywhere**. Raised as `POS-BE-006`.

### 2.6 Customers — **reusable for read, missing for write**

`GET /api/dashboard/customers`, `/customers/{id}` (`can:customers.view`).
Creation happens only through `CustomerDirectory::upsert()` on the public path.
A cashier cannot create a customer from an authenticated endpoint. Raised as
`POS-BE-014`.

### 2.7 Ops plumbing — **reusable**

`NotificationService` + FCM, `AuditLogger` (file-based daily trail),
`GET /api/dashboard/pulse` (ETag'd consolidated heartbeat — a KDS/POS poll can
piggyback), `PlanEntitlementService` + `EnsureFeatureEnabled`.

### 2.8 Design language — **reusable as a reference, not as code**

`packages/ui` is Vue/PrimeVue (SakaiLayout, Dialog, Toast, `theme.css`) and cannot
be imported into Flutter. What transfers:

- **Per-tenant brand colour.** `restaurants.brand_color` / `secondary_color` come
  down on `UserResource.restaurant` and on the public branding endpoint. The
  Flutter theme must be seeded from them at login, not hardcoded.
- **Bilingual AR/EN with RTL** is a first-class product property
  (`default_language`, `bilingual`, `*_ar`/`*_en` on every model). The POS is
  RTL-first-class from day one, not as a retrofit.
- **Arabic-numeral normalisation** already exists as `packages/ui/src/enDigits.js`
  — the same problem exists on a Flutter numeric keypad and must be solved again
  in Dart.

---

## 3. Missing — verified absent across `apps/api/app`

Confirmed by grep across models, migrations, enums and services. **No** payment,
tender, cashier, shift, till, refund, tax, or print concept exists anywhere.

| Missing capability | Evidence |
|---|---|
| **Payments** | No `payments` table, no tender types, no split bill, no change due, no partial payment. |
| **Money breakdown** | `orders` has only `total decimal(10,2)` + `currency`. No `subtotal`, `discount_total`, `tax_total`, `service_charge`, `paid_total`, `rounding`. |
| **Tax** | Zero tax model — no rate on restaurant, branch or item; no inclusive/exclusive handling. |
| **Discounts** | No discount entity at all. `options.discounted_price` is a *menu* discount, not a cashier action. |
| **Cash management** | No shift / register session, no opening float, no cash count, no X/Z report, no over/short. |
| **Receipts** | Screen-only dialog in `OrdersView.vue`. No receipt sequence, no per-branch numbering, no print, no reprint audit. `Order::code()` is literally `'ORD-'.$this->id` — a database id, not an invoice number. |
| **Voids / refunds** | `OrderStatus` = `NEW / COMPLETED / CANCELLED` only, and `canTransitionTo()` forbids reopening. No reason codes, no manager approval, no partial refund. |
| **Item traceability** | **`order_items` has no `menu_item_id`** — only a `name` string (`2026_08_19_000100_create_table_visits_and_order_rounds.php`). `orders.items` is a free-form JSON snapshot. Server-side re-pricing is therefore impossible today. |
| **Terminals / devices** | No device registry, no branch↔terminal binding, no printer config. |
| **Offline / sync** | Fully online SPA. No idempotency key anywhere, no sync endpoint. |
| **Inventory** | No stock, no BOM, no 86-ing beyond `menu_items.is_available`. |

---

## 4. Technical constraints

**C-1 — Flutter target.** Flutter 3.47.0 / Dart 3.13.0 (`flutter --version`).
`pubspec.yaml` declares `sdk: ^3.13.0`. `macos/`, `windows/` and `linux/` runners
are all present; the project is desktop-capable out of the box. Windows and macOS
are the supported targets; `android/`, `ios/`, `web/` and `linux/` are retained but
unsupported and untested.

**C-2 — Server-side pricing is non-negotiable for money.**
`PublicOrderController::store` recomputes `total` from *client-submitted*
`line_total` values and clamps it to `99999999.99`. That is acceptable when no
money changes hands; it is **unacceptable** for a POS. The POS must send item ids +
option ids and let the server price. Blocked on `order_items.menu_item_id`
existing at all.

**C-3 — Float arithmetic on the money path.** The backend uses `decimal:2` casts
but PHP `(float)` arithmetic in the order path. On split bills that produces cent
drift. The Flutter side will use **integer minor units** end-to-end and will ask
for the same in `POS-BE-007`.

**C-4 — JWT TTL vs. an offline till.** Tokens expire on `config('jwt.ttl')` and
`password_changed_at` invalidates them retroactively. There is no refresh token.
A till that goes offline for four hours and comes back to a 401 with a full sync
queue is a returned product. Needs a deliberate answer — `POS-BE-011`.

**C-5 — `subscription.writable` blocks writes on a lapsed plan.** The existing
code deliberately keeps *order handling* available when a subscription lapses.
Whether taking money is in that same category is a product decision, not a
technical one — flagged in `POS-BE-006`.

**C-6 — Cross-tenant is 404, not 403.** Flutter error handling must not treat a
404 on a tenant resource as "deleted" — it can also mean "not yours".

**C-7 — Concurrency at the table.** A waiter POS and a diner's QR menu can both
append to the same open `TableVisit`. `PublicOrderController` already takes
`lockForUpdate()` on the visit; any POS write path must join that discipline
rather than race it.

**C-8 — Printing has no Flutter-blessed cross-platform path.** ESC/POS over
network sockets works identically on Windows and macOS from pure Dart; USB and
OS-spooler printing do not. This drives the `PrinterService` abstraction and the
recommendation to standardise on network/ESC-POS printers first.

---

## 5. Risks

| # | Risk | Impact | Mitigation |
|---|---|---|---|
| R-1 | POS ships before `order_items.menu_item_id` exists → totals can never be server-verified, and product reporting stays a string match. | **High** | `POS-BE-006` is marked blocking. Until it is `READY`, POS runs entirely on fakes. |
| R-2 | Backend is in analysis-only mode with no approval date. Flutter work could stall waiting. | **High** | Every data source sits behind a repository interface with a `Fake*` implementation. **Phases 1–4 and 7 need no backend at all.** |
| R-3 | Client-side pricing becomes the de-facto authority because it shipped first. | **High** | The cart engine is written as a *quote*, and every order envelope carries the client's computed totals **as an assertion the server must confirm**, never as an instruction. A server/client mismatch is a hard error, not a silent overwrite. |
| R-4 | Offline order lost on crash between "checkout confirmed" and "queued". | **High** | The order is written to SQLite **inside the same transaction that clears the cart**, before any UI transition. Nothing is ever held only in memory. |
| R-5 | Two tills offline at once both mint receipt number 1041. | **Medium** | Client-side numbers are provisional and namespaced by terminal; the server assigns the authoritative invoice number on sync (`POS-BE-008`). The receipt says so. |
| R-6 | JWT expires mid-offline (C-4). | **Medium** | `POS-BE-011`. Until answered, the app keeps selling offline and surfaces a blocking "re-authenticate to sync" state rather than dropping the queue. |
| R-7 | RTL/Arabic regressions found late. | **Medium** | Every screen is built and reviewed in both directions from Phase 1, with `Directionality` driven by locale, and `ms/me`-equivalent (`EdgeInsetsDirectional`) spacing only. |
| R-8 | Tax/e-invoicing (Egypt ETA, KSA ZATCA) turns out to be in scope. | ~~Medium~~ **CRITICAL — materialised** | **This is no longer conditional.** Egypt's ETA B2C e-receipt mandate took effect **15 September 2025** and binds every POS of every listed taxpayer. The stated mitigation was never built either: there is no `tax_lines[]` in `lib/` — `TaxConfig` carries two scalars. See [15-competitive-position.md](15-competitive-position.md). |
| R-9 | Scope creep into inventory/KDS. | **Low** | Explicitly out of scope; noted in `02-pos-requirements.md` §Out of scope. |

---

## 6. Assumptions

Each is falsifiable. If the owner contradicts one, the affected doc section is
what changes — not the architecture.

- **A-1** The Flutter POS replaces the previously-proposed Vue `apps/pos`. There
  will be exactly one POS client.
- **A-2** The POS is a *restaurant* POS (menu items, modifiers, tables, kitchen),
  not a retail POS. Barcode support is a convenience for packaged goods, not the
  primary input method.
- **A-3** v1 is **cash + "card via external terminal, recorded as a tender type"**.
  No payment-processor integration.
- **A-4** One terminal is bound to exactly one branch at a time, chosen at setup
  and changeable only with `settings.update`.
- **A-5** Order types come from `branches.supported_order_types`, and the POS shows
  only what is enabled. Nothing white-label-specific is hardcoded.
- **A-6** Receipt printing standardises on **network ESC/POS** first; OS-spooler
  and USB are later implementations behind the same `PrinterService`.
- **A-7** The POS authenticates as a normal tenant user against the existing
  `/api/auth/login` with the restaurant slug supplied in device setup — no new
  auth mechanism unless `POS-BE-011` concludes otherwise.
- **A-8** Arabic and English are both first-class; the till's language is a
  per-device setting defaulting to `restaurant.default_language`.

---

## 7. What Agent 1 can build with zero backend changes

Stated plainly, because it determines the whole plan:

- Phase 1 (foundation), Phase 2 (auth UI + session + permissions),
  Phase 3 (catalog, search, grid, cart), Phase 4 (all calculations),
  Phase 5 (checkout/payment/receipt **UI**), Phase 7 (local DB + sync queue
  + retry + status UI) — **all buildable now against fakes.**
- Phase 2/3 can additionally run against the *real* API today in read-only mode:
  `auth/login`, `auth/me`, `dashboard/branches`, `dashboard/categories`,
  `dashboard/items`, `dashboard/customers`, `dashboard/tables/live` all exist and
  need no change.
- What genuinely cannot ship without backend work: **taking money**. Order
  creation, payment recording, shifts, refunds and invoice numbering
  (`POS-BE-006` … `POS-BE-009`).

See `docs/coordination/POS_TO_BACKEND.md` for the numbered requests.
