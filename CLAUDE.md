# CLAUDE.md — Xorder

Multi-tenant QR-menu & ordering SaaS. Super Admin provisions restaurants + their first admin;
each Restaurant Admin manages menu/branches/orders/QR; diners use a bilingual (AR/EN) Vue menu
with cart + WhatsApp checkout. **Live at https://xorder.io** (push-to-main auto-deploys via CI).

This file is loaded every session — keep it tight. Depth lives in `README.md` (run/deploy) and
`ARCHITECTURE.md` (schema, API map, security). Read those only when you need that depth.

## Repo map (pnpm + Turborepo monorepo)

| Path | What | Dev port |
|---|---|---|
| `apps/api` | Laravel 13 JSON API + SEO menu shell. **This is the backend.** | `:8100` |
| `apps/web` | Vue 3 SPA — Super Admin + Restaurant dashboards | `:5173` |
| `apps/landing` | Vue 3 marketing site (xorder.io) | `:5174` |
| `apps/menu` | Vue 3 customer ordering SPA | `:5175` |
| `packages/{ui,api-client,analytics}` | shared Vue components, i18n, API client | — |

Backend layout (`apps/api/app`): thin `Http/Controllers/{Auth,Admin,Dashboard,Public}`, `Requests/`
(validation), `Policies/` (per-object authz), `Services/` (multi-model logic), `Models/` +
`Models/Scopes/RestaurantScope.php`, `Resources/` (`*PublicResource` = public-safe output).
Routes in `routes/api.php` + `routes/web.php`. Tests in `apps/api/tests/{Feature,Unit}`.

## Commands

```bash
./scripts/dev.sh                                   # one-shot: full local stack
# or, by hand:
cd apps/api && php artisan serve --port=8100       # backend (SPAs proxy to :8100)
pnpm dev                                           # all 3 Vue apps (root)
cd apps/api && php artisan test                    # backend tests
pnpm build                                          # build all apps
```

## Load-bearing facts (some contradict the older docs — trust THIS)

- **Auth is stateless JWT Bearer, NOT Sanctum cookies.** README/ARCHITECTURE say Sanctum — that is
  stale. The real guard is a custom `jwt` driver registered via `Auth::viaRequest()` in
  `app/Providers/AppServiceProvider.php`, backed by `app/Support/Jwt.php` + `config/jwt.php`.
  Sanctum is still a composer dep but is not the API guard. Every env needs `JWT_SECRET` or login 500s.
- **DB:** SQLite in dev, PostgreSQL in prod — identical Eloquent code.
- **Tenant isolation is structural, never manual.** `RestaurantScope` (global scope) +
  `BelongsToRestaurant` trait auto-scope every tenant query to `auth()->user()->restaurant_id`.
  `restaurant_id` is **never** read from request input. Cross-tenant access → 404, not 403.
- **Deploy is push-to-main** (CI runs `apps/api` tests as a gate, then auto-deploys to the VPS).
  Prod is live and co-hosts a separate product (Operix) on the same box — see the deploy memories.
  The `*cohost*`/`deploy.sh`/`go-live.sh`/`issue-cert.sh`/`docker-compose.cohost.yml` files are
  prod co-host scaffolding — ignore them for local work.

## Token hygiene (this file exists to make sessions cheap)

- Don't read lockfiles whole — `pnpm-lock.yaml` and `apps/api/composer.lock` (~9k lines) blow up
  context. `grep` a package name instead.
- Search tools already skip `node_modules/`, `vendor/`, `dist/`, `.turbo/`, `public/build/`
  (they're gitignored). No need to exclude them manually.
- Prefer the repo map above over re-globbing the tree; open `ARCHITECTURE.md` for the DB schema and
  full API route table instead of re-deriving them from code.
