---
paths:
  - "apps/xorder-cloud/**"
---

# xorder-cloud (Laravel 13 + Vue 3) — verified 2026-10-22

- Defer to `apps/xorder-cloud/CLAUDE.md`; it is authoritative and corrects stale README/ARCHITECTURE text (auth is JWT, not Sanctum). Before significant changes follow `.claude/rules/knowledge.md` (`/project-documentation context <feature> <phase>`).
- Pushing `main` deploys to production and migrates the live database — see `production-safety.md`. Ignore the co-host scaffolding (`deploy.sh`, `go-live.sh`, `issue-cert.sh`, `*cohost*`) for local work; never run it.
- Do not read `pnpm-lock.yaml` / `composer.lock` whole, or `.env*`. No PHP formatter/static analyser and no JS test or lint scripts exist; do not add tooling without approval.

## Laravel API (`apps/api`)
- Layering: thin `Http/Controllers/{Auth,Admin,Dashboard,Public,Pos}` → `Http/Requests` (all validation) → `app/Services` (multi-model logic; ~45 exist, look before writing one) → `Models` → `Http/Resources` (`*PublicResource` = safe for unauthenticated output). Authorization is `Gate::define` in `app/Providers/AppServiceProvider.php` plus middleware; there is no `Policies/` directory.
- Tenant isolation is structural: `RestaurantScope` + `BelongsToRestaurant`; `restaurant_id` is never read from input; cross-tenant access returns **404**, never 403. `User` has no scope: scope staff queries by hand (`Dashboard\StaffController` is the pattern). `users.role` and `users.restaurant_id` stay non-fillable; only trusted services set them. `TenantContext::overrideId()` on public paths is released in a `finally`.
- Dashboard routes stack `role:` (portal) + `feature:<key>` (did the tenant buy it) + `can:<TenantCapability>` (may this person do it) + `subscription.writable`; copy the neighbouring route group and its comment. Platform `Capability` and restaurant `TenantCapability` must not leak across.
- The server owns prices, discounts, tax, totals and order transitions (`PosPricingEngine`, `PosOrderService`, `InvoiceSequenceService`). Order/payment endpoints are idempotent and transactional; `Http/Controllers/Pos/OrderController.php` is the existing pattern. Sensitive writes call `AuditLogger::record()`.
- SQLite in dev/tests, PostgreSQL in prod: no engine-specific SQL (partial unique indexes, `ON CONFLICT`, JSON operators). `SoftDeletes` on `menu_items`/`categories` changes what `unique()` means.
- Verify: `cd apps/xorder-cloud/apps/api && php artisan test --filter <Name>`, then the full suite (SQLite `:memory:`). New endpoints need feature tests for happy path, validation, authorization, cross-tenant 404 and idempotent retry. Never run `migrate` against a non-test database.

## Vue SPAs (`apps/web|landing|menu`, `packages/*`)
- `apps/web` is one bundle, two portals, split by host in `src/lib/host.js` (`admin.<root>` → Super Admin, `<slug>.<root>` → restaurant dashboard); locally the dashboard only works on a subdomain such as `demo.localhost:<port>`. Dev servers: use the preview tools with `.claude/launch.json` (`api`, `web`, `landing`, `menu`), never `pnpm dev` in Bash.
- Inspect the neighbouring page in `src/pages/{admin,dashboard}` and reuse `packages/ui` (`Modal`, `FormError`, `ListSkeleton`, `confirm()`/`alert()` — never `window.confirm`), the shared axios client in `packages/api-client` (JWT bearer, paths without a leading slash, 401 clears the token, the read-only 403 is handled once in the shell) and `useCaps()` for write controls. Hiding a control is a courtesy; the server is the boundary. No Pinia for page-local state.
- Every user-facing string in both `en` and `ar`; RTL via logical utilities (`ms-/me-/ps-/pe-/text-start/text-end`); colours only from theme CSS variables; fonts stay self-hosted. Cover loading, error, empty and success states; `v-for` keyed by stable id. Never compute final prices client-side.
- `apps/menu` is unauthenticated and tenant-branded: tenant-supplied URLs go through `src/lib/safeUrl.js`; ordering channels come from feature flags, not assumptions.
- Verify: `cd apps/xorder-cloud && pnpm build` (or `pnpm --filter @xorder/<app> build`), then check both themes and both locales in the preview; say plainly what was verified manually or not at all.
