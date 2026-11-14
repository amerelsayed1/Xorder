# Xorder Architecture

**Status:** Active
**Stack:** Laravel 13 JSON API · Vue 3 SPAs (dashboard, landing, customer menu) · PostgreSQL
**Core rule:** Tenant isolation is enforced server-side; the public menu consumes only dedicated public resources.

---

## 1. Clean Architecture Proposal

We deliberately **do not** use full hexagonal/DDD/clean-architecture layering. For an MVP of this size that is over-engineering. We use **pragmatic layered Laravel**, which is production-ready and fast to ship:

```
HTTP (Controllers, thin)
   └─ Form Requests        → input validation + authorization gate
   └─ Policies              → per-resource authorization (tenant isolation)
   └─ Services              → business logic that spans >1 model or is non-trivial
   └─ Eloquent Models       → data + relationships + scopes (tenant scope)
   └─ API Resources         → output shaping (never leak internal fields)
```

Rules of thumb:
- **Controllers stay thin** — validate (Form Request), authorize (Policy), call a Service or Model, return a Resource.
- **Services only when justified** — restaurant provisioning (create restaurant + admin user + initial data in one transaction), reorder logic, QR generation. Simple CRUD does not need a service.
- **Tenant isolation is structural, not manual** — enforced by a global Eloquent scope + a middleware-injected `restaurant_id`, never read from the request body.
- **Two HTTP surfaces:** JSON APIs (`/api/*`) and lightweight HTML shells for the Vue SPAs.

### Why separate frontends
- **Dashboards (Super Admin + Restaurant Admin):** Vue 3 SPA. Rich, interactive, behind auth, not indexed. SEO irrelevant.
- **Public menu:** Vue 3 SPA with a Laravel-served shell. Laravel injects restaurant-specific title,
  canonical, Open Graph, and JSON-LD metadata so crawlers and link-preview bots do not need to execute JavaScript.

---

## 2. Database Schema (PostgreSQL)

### `users`
| column | type | notes |
|---|---|---|
| id | bigint PK | |
| name | varchar | |
| email | varchar | **unique** |
| password_hash | varchar | bcrypt (Laravel `password` column) |
| role | enum | `SUPER_ADMIN`, `RESTAURANT_ADMIN` |
| restaurant_id | bigint FK null | null for Super Admin; required for Restaurant Admin |
| status | enum | `ACTIVE`, `SUSPENDED` |
| created_at / updated_at | timestamp | |

Indexes: `unique(email)`, `index(restaurant_id)`, `index(role)`.

### `restaurants`
| column | type | notes |
|---|---|---|
| id | bigint PK | |
| name_ar / name_en | varchar | at least one required (see validation) |
| slug | varchar | **unique**, lowercase, `[a-z0-9-]` |
| description_ar / description_en | text null | |
| logo_url / cover_image_url | varchar null | |
| phone | varchar null | |
| whatsapp_number | varchar null | E.164 stored (e.g. `+201234567890`) |
| address | text null | |
| brand_color | varchar(7) null | hex, default `#111827` |
| secondary_color | varchar(7) null | hex |
| default_language | enum | `ar`, `en` |
| status | enum | `ACTIVE`, `SUSPENDED`, `ARCHIVED` (default `ACTIVE`) |
| subscription_status | enum | `TRIAL`, `ACTIVE`, `EXPIRED`, `SUSPENDED` (default `TRIAL`) |
| subscription_plan | varchar null | free text in MVP |
| subscription_start_date / subscription_end_date | date null | |
| created_at / updated_at | timestamp | |

Indexes: `unique(slug)`, `index(status)`.

### `categories`
| column | type | notes |
|---|---|---|
| id | bigint PK | |
| restaurant_id | bigint FK | cascade |
| name_ar / name_en | varchar | at least one required |
| description_ar / description_en | text null | |
| image_url | varchar null | |
| display_order | int | default 0 |
| is_active | boolean | default true |
| created_at / updated_at | timestamp | |

Indexes: `index(restaurant_id, display_order)`, **`unique(restaurant_id, name_en)`** and **`unique(restaurant_id, name_ar)`** (uniqueness scoped per restaurant).

### `menu_items`
| column | type | notes |
|---|---|---|
| id | bigint PK | |
| restaurant_id | bigint FK | cascade — denormalized for fast tenant scoping + public query |
| category_id | bigint FK | cascade |
| name_ar / name_en | varchar | at least one required |
| description_ar / description_en | text null | |
| price | decimal(10,2) | >= 0 |
| discounted_price | decimal(10,2) null | <= price |
| image_url | varchar null | |
| is_available | boolean | default true |
| is_featured | boolean | default false |
| display_order | int | default 0 |
| deleted_at | timestamp null | **soft delete** |
| created_at / updated_at | timestamp | |

Indexes: `index(restaurant_id, category_id, display_order)`, `index(restaurant_id, is_featured)`, `index(deleted_at)`.

> **Design note:** `restaurant_id` is denormalized onto `menu_items` (even though it's reachable via `category_id`). This makes tenant-scoping and the public menu query single-table-fast, and lets the global scope work uniformly.

### `password_reset_tokens`
Standard Laravel table for forgot/reset password.

### Migration & seed order
1. `users` (without FK to restaurants yet, or add FK after)
2. `restaurants`
3. add `restaurant_id` FK to `users`
4. `categories`
5. `menu_items`
6. Seeder: one Super Admin (`SUPER_ADMIN`, `restaurant_id = null`) from `.env` credentials.

---

## 3. API Structure

All dashboard/admin APIs return JSON, are auth-protected, and are tenant-scoped server-side.

### Auth (`/api/auth`)
| Method | Path | Role | Notes |
|---|---|---|---|
| POST | `/login` | public | returns user + role; sets session/token |
| POST | `/logout` | auth | |
| POST | `/forgot-password` | public | emails reset link |
| POST | `/reset-password` | public | token + new password |
| GET | `/me` | auth | current user + restaurant context (add this — the SPA needs it) |

### Super Admin (`/api/admin`) — requires `SUPER_ADMIN`
| Method | Path |
|---|---|
| GET | `/restaurants` (list + filters: status, search) |
| POST | `/restaurants` (creates restaurant **+ first admin user** in one transaction) |
| GET | `/restaurants/:id` |
| PUT | `/restaurants/:id` |
| PATCH | `/restaurants/:id/status` |
| PATCH | `/restaurants/:id/subscription` |
| GET | `/restaurants/:id/qr` (and `/qr/download`) |

### Restaurant Dashboard (`/api/dashboard`) — requires `RESTAURANT_ADMIN`
`restaurant_id` is **always** taken from `auth()->user()->restaurant_id`. Never from payload.

| Method | Path |
|---|---|
| GET / PUT | `/restaurant` (own profile only) |
| GET | `/stats` (dashboard home counters — add this) |
| GET POST | `/categories` |
| GET PUT DELETE | `/categories/:id` |
| PATCH | `/categories/:id/status` |
| PATCH | `/categories/reorder` |
| GET POST | `/items` |
| GET PUT DELETE | `/items/:id` |
| PATCH | `/items/:id/availability` |
| PATCH | `/items/reorder` |
| GET | `/qr`, `/qr/download` |

### Uploads (`/api/uploads`) — auth (either role)
| POST | `/image` | validates mime/size/dimensions, returns stored URL |

### Public (no auth)
| GET | `/api/public/restaurants/:slug/menu` | JSON, only public/active data |
| POST | `/api/public/restaurants/:slug/orders` | records a customer order before WhatsApp handoff |
| GET | `/menu/*` | customer-menu SPA shell with restaurant metadata |
| GET | `/r/:slug` | legacy QR route; redirects to the canonical menu URL |

**Standard response envelope:**
```json
{ "data": { ... }, "message": "..." }          // success
{ "message": "...", "errors": { "field": ["..."] } }  // 422 validation
```

---

## 4. Folder Structure

```
app/
  Enums/                 RoleEnum, RestaurantStatus, SubscriptionStatus, UserStatus, LanguageEnum
  Http/
    Controllers/
      Auth/              LoginController, PasswordResetController
      Admin/             RestaurantController, SubscriptionController, QrController
      Dashboard/         RestaurantProfileController, CategoryController, ItemController,
                         StatsController, QrController
      Public/            MenuShellController, PublicMenuApiController,
                         PublicOrderController, RestaurantQrController
      UploadController
    Middleware/
      EnsureRole.php                 (role:SUPER_ADMIN / role:RESTAURANT_ADMIN)
      ResolveRestaurantTenant.php    (binds current restaurant_id into the container)
    Requests/
      Admin/             StoreRestaurantRequest, UpdateRestaurantRequest, UpdateStatusRequest...
      Dashboard/         StoreCategoryRequest, StoreItemRequest, ReorderRequest...
    Resources/
      RestaurantResource, RestaurantPublicResource, CategoryResource,
      MenuItemResource, MenuItemPublicResource, UserResource
  Models/                User, Restaurant, Category, MenuItem
  Models/Scopes/         RestaurantScope.php (global tenant scope)
  Models/Concerns/       BelongsToRestaurant.php (trait)
  Policies/              RestaurantPolicy, CategoryPolicy, MenuItemPolicy
  Services/              RestaurantProvisioningService, QrCodeService, ImageUploadService,
                         ReorderService, SlugService
database/
  migrations/  factories/  seeders/
routes/
  api.php  web.php  (web.php hosts /r/:slug + serves SPA shell)
tests/
  Feature/  Unit/

apps/menu/               Vue 3 customer menu, cart, ordering, and bilingual UI
apps/web/                Vue 3 admin and restaurant dashboards
apps/landing/            Vue 3 marketing site
```

---

## 5. Authentication & Authorization

### Authentication — **Laravel Sanctum (SPA cookie session)**
For a first-party Vue SPA on the same domain, Sanctum's cookie-based session auth is the recommended, production-ready, low-ceremony choice. It is CSRF-protected and avoids token-storage-in-JS pitfalls.

- Flow: SPA hits `GET /sanctum/csrf-cookie` → `POST /api/auth/login` → session cookie set (HttpOnly, Secure, SameSite=Lax).
- Public menu needs no auth at all.
- **If** you later split the dashboard onto a different domain or build mobile apps, swap to JWT/personal-access-tokens — the controller contract stays identical. (Requirement said "Session/JWT"; Sanctum satisfies it.)

Passwords: Laravel default **bcrypt** hashing (`Hash::make` / `Hashable` cast). Never store or log plaintext.

### Authorization — three concentric layers
1. **Route middleware** — `role:SUPER_ADMIN` on `/api/admin/*`, `role:RESTAURANT_ADMIN` on `/api/dashboard/*`. Coarse gate.
2. **Policies** — `CategoryPolicy@update` etc. assert `$category->restaurant_id === $user->restaurant_id`. Per-object gate.
3. **Global tenant scope** — `RestaurantScope` auto-adds `where restaurant_id = <current>` to every query on tenant models for a Restaurant Admin. Makes cross-tenant data **structurally unreachable**, even if a controller forgets a check.

```php
// Models/Concerns/BelongsToRestaurant.php
protected static function bootBelongsToRestaurant(): void {
    static::addGlobalScope(new RestaurantScope);     // SELECT auto-filtered
    static::creating(function ($model) {             // INSERT auto-stamped
        if (auth()->check() && auth()->user()->restaurant_id) {
            $model->restaurant_id ??= auth()->user()->restaurant_id;
        }
    });
}
```
Super Admin queries bypass the scope (they operate by explicit `:id`).

---

## 6. Backend Implementation Plan

1. **Setup** — Laravel 12, PostgreSQL, Sanctum, `simplesoftwareio/simple-qrcode` (or `endroid/qr-code`), Intervention Image for upload processing.
2. **Enums + migrations + models + factories** — all four tables, relationships, the `BelongsToRestaurant` trait + global scope.
3. **Auth** — Sanctum SPA login/logout, `/me`, password reset (Laravel built-in notifications).
4. **Role middleware + Policies** — register `role` middleware; write the three policies.
5. **Super Admin: restaurant provisioning** — `RestaurantProvisioningService` wraps restaurant + admin user creation in a DB transaction; generate password if not supplied (email it). Slug validation/uniqueness via `SlugService`.
6. **Super Admin: status/subscription/QR** controllers + resources.
7. **Dashboard CRUD** — profile, categories, items, availability toggle, reorder, stats counters.
8. **Uploads** — `ImageUploadService`: validate, resize, store to `public`/S3 disk, return URL.
9. **QR** — `QrCodeService` renders PNG pointing at `config('app.url')/r/{slug}`; stream as download.
10. **Public** — `PublicMenuApiController` exposes the public menu query; `MenuShellController` serves
    the built Vue shell and injects restaurant metadata. Suspended/archived visibility is handled consistently by both.
11. **Tests** — feature tests per role, especially **tenant-isolation negative tests** (Admin A cannot touch Restaurant B).

---

## 7. Frontend Implementation Plan

### Vue 3 SPA (dashboards)
- Vite + Vue Router + Pinia + Axios (`lib/api.js` with CSRF + 401 interceptor).
- **Route guards** by role; `auth` store holds `user`, `role`, `restaurant`.
- Two route trees: `/admin/*` (Super Admin) and `/dashboard/*` (Restaurant Admin); redirect after login by role.
- Pages map 1:1 to the spec (Restaurants list/create/edit/details, Subscription; Dashboard home, Profile, Categories, Items, QR).
- Reusable: `ImageUploader`, `BilingualField` (ar/en tabs), `StatusBadge`, `SortableList` (drag reorder → PATCH reorder), `ConfirmDialog`.
- i18n: `vue-i18n`, dashboard UI in ar + en, RTL toggle on `<html dir>`.

### Vue customer menu (`/menu/`)
- Mobile-first Vue UI with a Laravel-served SEO shell.
- `dir` + `lang` from `default_language`, with a language switch.
- Sections: hero, sticky category navigation, search, category/item grids, item options, cart, and WhatsApp checkout.
- Unavailable items render greyed with an "Unavailable / غير متاح" badge.
- SEO: `<title>`, meta description, Open Graph (logo/cover), JSON-LD `Restaurant`/`Menu` schema, canonical URL.
- Suspended/archived restaurants receive the same SPA shell and the menu API returns an unavailable state.

---

## 8. Step-by-Step Development Tasks

**Phase 1 — Foundation**
1. Init Laravel 12 + PostgreSQL + Sanctum + Tailwind/Vite.
2. Enums, migrations, models, factories, global tenant scope.
3. Super Admin seeder.
4. Auth (login/logout/me/password reset) + role middleware + policies.
5. `POST /api/admin/restaurants` provisioning (restaurant + first admin, transaction, slug + password gen).
6. Restaurants list/get/update + status + subscription endpoints.

**Phase 2 — Dashboard**
7. `/api/auth/me`, dashboard stats endpoint.
8. Restaurant profile GET/PUT.
9. Categories CRUD + status + reorder.
10. Items CRUD + availability + reorder.
11. Image upload endpoint + service.
12. Vue SPA shell, router, auth store, guards, layouts; build dashboard pages.

**Phase 3 — Public menu**
13. Public menu JSON, order, QR, and SEO shell controllers.
14. Vue menu UI: hero, navigation, search, badges, cart, options, and WhatsApp checkout.
15. RTL/LTR + i18n + mobile responsiveness.

**Phase 4 — QR, subscription behavior, deploy**
16. QR service + view/download (dashboard + admin).
17. Suspended/archived public behavior + subscription EXPIRED gating.
18. SEO meta + JSON-LD + sitemap.
19. Production deploy (HTTPS, S3, queue for emails, migrations, env).

---

## 9. Edge Cases

- **Slug collision** — reject with 422; offer suggestion (`name-2`). Slug is immutable-by-default after creation (changing it breaks printed QR codes); if you allow it, warn loudly.
- **Deleting a Restaurant Admin / restaurant with one admin** — block deleting the last admin, or cascade-archive.
- **Restaurant suspended while admin is logged in** — block dashboard mutations (middleware checks restaurant status), show banner.
- **Subscription EXPIRED** — decide policy: public menu still visible (recommended for MVP) but dashboard read-only, OR hide menu. Default: menu visible, dashboard locked to read.
- **Deleting a category that has items** — block, or cascade soft-delete items, or force-reassign. MVP: block with a clear message ("move or delete items first").
- **Empty category** — hidden from public menu (business rule), still visible in dashboard.
- **All items unavailable in a category** — category still shows (items have badges); but a category with **zero active items** is hidden publicly.
- **Discounted price == price** — allow (treated as no discount) or reject equality; recommend reject `>=`.
- **Reorder race / partial payload** — reorder endpoint validates that every id belongs to the tenant; wrap in transaction.
- **Image upload failure mid-form** — uploads are independent (return URL first), so a failed item save doesn't strand the image; run a periodic orphan-image cleanup later (post-MVP).
- **Duplicate category name across languages** — uniqueness enforced per `(restaurant_id, name_en)` and `(restaurant_id, name_ar)` independently; a null name in one language is allowed if the other is present.
- **Missing translation** — fall back to `default_language` value when one of ar/en is empty.
- **Cross-tenant id in URL** (`/api/dashboard/items/999`) — global scope + policy → 404 (not 403, to avoid leaking existence).
- **Public slug for SUSPENDED/ARCHIVED** — "unavailable" page, never 404 (preserve the QR's meaning).

---

## 10. Validation Rules

**Restaurant (create/update)**
- `name_en` or `name_ar` required (at least one); each ≤ 150.
- `slug` required, `regex:/^[a-z0-9-]+$/`, unique, ≤ 80, no leading/trailing/double hyphen.
- `admin_email` required, email, unique in `users`.
- `admin_password` optional → if absent, generate strong random + email it; if present, min 8.
- `phone` / `whatsapp_number` nullable, valid phone (store E.164).
- `brand_color` / `secondary_color` nullable, hex `regex:/^#[0-9a-fA-F]{6}$/`.
- `default_language` in `ar,en`.
- `status` in enum; `subscription_status` in enum.
- `logo_url` / `cover_image_url` nullable URL (or upload-returned path).

**Category**
- `name_ar` or `name_en` required; unique per restaurant per language.
- `display_order` integer ≥ 0.
- `is_active` boolean.

**Menu Item**
- `name_ar` or `name_en` required.
- `category_id` required, **must belong to the same restaurant** (validated, not trusted).
- `price` required, numeric, ≥ 0.
- `discounted_price` nullable, numeric, ≥ 0, **`lt:price`** (strictly less than).
- `is_available` / `is_featured` boolean.

**Uploads**
- mimes: `jpg,jpeg,png,webp`; max 4 MB; max dimensions cap (e.g. 4000px); re-encode/strip EXIF on the server.

**Reorder**
- array of `{id, display_order}`; every id `exists` and belongs to tenant.

---

## 11. Security Notes

- **Passwords hashed** (bcrypt); reset tokens hashed + expiring; rate-limit login & forgot-password.
- **Tenant isolation enforced server-side** on every dashboard route: global scope + policy + middleware. **`restaurant_id` is never read from the request body** — always `auth()->user()->restaurant_id`.
- **Super Admin routes require `SUPER_ADMIN`; dashboard routes require `RESTAURANT_ADMIN`** via middleware, re-checked by policies.
- **Public endpoints expose only public fields** via dedicated `*PublicResource` (no subscription data, no internal flags, no other-tenant data, no soft-deleted rows).
- **Validate everything** with Form Requests; reject unknown fields; cast enums.
- **File uploads**: validate mime + extension + size, re-encode via Intervention, store outside webroot or on S3, randomized filenames, strip metadata, serve via signed/public URL only.
- **CSRF** via Sanctum for the cookie-session SPA; **CORS** locked to known origins.
- **HTTPS everywhere** in production; HttpOnly + Secure + SameSite cookies; HSTS.
- **Rate limiting** on auth, upload, and public menu endpoints.
- **404 over 403** for cross-tenant access to avoid existence disclosure.
- **Audit-light**: log status/subscription changes by Super Admin (post-MVP table, but log now).
- Mass-assignment guarded (`$fillable` excludes `restaurant_id`, `role`, `status` on tenant-writable models).

---

## 12. Suggested First Sprint (Sprint 1 — "Provision a restaurant")

Goal: **A Super Admin can log in and provision a restaurant with its first admin, who can then log in.** This proves auth, roles, tenant model, and the core business rule end-to-end.

1. Project scaffolding: Laravel 12 + PostgreSQL + Sanctum + Vite/Vue + Tailwind.
2. Enums + migrations (users, restaurants, categories, menu_items) + models + relationships.
3. `BelongsToRestaurant` trait + `RestaurantScope` global scope.
4. Super Admin seeder (from `.env`).
5. Auth: login, logout, `/me`, password reset; `role` middleware; 3 policies.
6. `SlugService` + `RestaurantProvisioningService` (transactional restaurant + admin creation, password generation + email).
7. `POST/GET /api/admin/restaurants` (+ list) with `StoreRestaurantRequest`.
8. Minimal Vue: login page, role-based redirect, Super Admin "Restaurants" list + "Create restaurant" form.
9. **Feature tests:** Super Admin creates restaurant; created admin can log in; Restaurant Admin **cannot** hit `/api/admin/*`; Restaurant Admin A **cannot** read Restaurant B's data (tenant-isolation negative test).

**Definition of done:** all Sprint-1 feature tests green; manual run: seed super admin → create restaurant in UI → log out → log in as the generated restaurant admin → land on (empty) dashboard.

---

### Appendix — Recommended packages
- `laravel/sanctum` — SPA auth
- `simplesoftwareio/simple-qrcode` or `endroid/qr-code` — QR PNG
- `intervention/image` — upload processing
- `spatie/laravel-data` (optional) — typed DTOs/resources if you want stronger typing
- `vue`, `vue-router`, `pinia`, `axios`, `vue-i18n`, a Vue sortable lib for drag-reorder

> Keep it simple. Ship Phase 1 fully before touching the public menu. The whole MVP is "onboard a restaurant manually, publish a beautiful QR menu."
