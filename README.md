# QR Menu SaaS — MVP

Menu-only multi-tenant SaaS. A **Super Admin** provisions restaurants and their first admin; each
**Restaurant Admin** manages their own menu; the public sees a fast, SEO-friendly, RTL/LTR QR menu at
`/r/{slug}`. No cart, orders, or payments (MVP v1).

**Stack:** Laravel 13 (API) · Vue 3 SPA (Super Admin + Restaurant dashboards) · Blade SSR (public menu)
· Sanctum cookie auth · SQLite (dev) / PostgreSQL (prod). See [ARCHITECTURE.md](ARCHITECTURE.md) for the
full design.

## Repo layout

pnpm + Turborepo monorepo. The four apps are independent and talk over HTTP:

| Path | What | Dev URL |
|---|---|---|
| `apps/api` | Laravel API + Blade public menu (`/api`, `/r/{slug}`) | `:8000` |
| `apps/web` | Vue SPA — Super Admin + Restaurant dashboards | `:5173` |
| `apps/landing` | Vue marketing site (xorder.io) | `:5174` |
| `apps/menu` | Vue customer ordering SPA | `:5175` |
| `packages/ui`, `packages/api-client` | shared Vue components, i18n, API client | — |

> The files referencing **Operix** (`docker-compose.cohost.yml`, `deploy.sh`, `go-live.sh`,
> `issue-cert.sh`, `CO-HOST-PREP.md`, `.env.production.example`, `docker/nginx/*`) are **production
> co-host** scaffolding only — Operix is a separate product that shares Xorder's prod VPS. Ignore
> them when running Xorder locally.

## Run locally

### Option A — dev servers (fastest; hot reload)

Two terminals. The SPAs proxy `/api`, `/sanctum` and `/r` to the API, which **must run on port 8000**.

```bash
# Terminal 1 — API (apps/api)
cd apps/api
composer install
cp .env.example .env
#   use SQLite locally: set DB_CONNECTION=sqlite and remove DB_HOST/PORT/DATABASE/USERNAME/PASSWORD
php artisan key:generate
touch database/database.sqlite
php artisan migrate --seed                      # creates the Super Admin from .env
php artisan db:seed --class=DemoSeeder          # optional: demo restaurant at /r/xorderrest
npm run build                                   # builds the public-menu CSS (Vite manifest)
php artisan serve --port=8000                   # MUST be 8000 (the SPAs proxy here)

# Terminal 2 — front-ends (repo root)
pnpm install
pnpm dev:landing    # http://localhost:5174   (marketing site)
pnpm dev:web        # http://localhost:5173   (Super Admin → Landing Management, Leads)
```

Open:
- **Landing:** <http://localhost:5174>
- **Super Admin:** <http://localhost:5173> — log in with the seeded `SUPER_ADMIN_EMAIL` /
  `SUPER_ADMIN_PASSWORD` from `apps/api/.env`.
- **Public menu:** <http://localhost:8000/r/xorderrest>

> `pnpm dev` (turbo) starts the **front-ends only** — the API is a separate `php artisan serve`.
> SPA cookie auth needs the browser origin in `SANCTUM_STATEFUL_DOMAINS`; the default already covers
> `localhost:5173`, `localhost:5174` and `localhost:8000`.

### Option B — full stack in Docker (one container, closest to prod)

Multi-stage build → **Nginx + PHP-FPM + PostgreSQL**, all four apps behind one nginx. No Node/PHP
needed on the host. Uses the standalone [`docker-compose.yml`](docker-compose.yml) (not the co-host one).

```bash
cp apps/api/.env.docker.example apps/api/.env.docker
docker compose run --rm app php artisan key:generate --show   # paste into APP_KEY in apps/api/.env.docker
#   also set DB_PASSWORD and SUPER_ADMIN_PASSWORD in apps/api/.env.docker
docker compose up -d --build
docker compose exec app php artisan db:seed --class=DemoSeeder --force   # optional demo data
```

On first boot the app container waits for Postgres, migrates, seeds the Super Admin
(`SEED_ON_START=true`), and caches config/routes/views. Then:

- **Landing:** <http://localhost:8080>  · **public menu:** `/r/xorderrest`
- **Super Admin:** <http://admin.localhost:8080> (Host-routed to the admin subdomain;
  browsers resolve `*.localhost` automatically)
- Postgres is internal; data persists in the `pgdata` volume, uploads in `storage-data`.

```bash
docker compose logs -f app           # follow app logs (stderr)
docker compose down                  # stop (add -v to wipe db + uploads)
```

Files: [`Dockerfile`](Dockerfile) (stages `assets`/`vendor`/`app`/`web`),
[`docker-compose.yml`](docker-compose.yml), `apps/api/.env.docker`,
[`docker/`](docker/) (nginx conf, php.ini, entrypoint).

> Behavior toggles via env: `RUN_MIGRATIONS`, `SEED_ON_START`, `HIDE_MENU_WHEN_EXPIRED`,
> `ENFORCE_SUBSCRIPTION_WRITES`. For a real domain, set `APP_URL` and `SANCTUM_STATEFUL_DOMAINS`
> to that host and switch `MAIL_MAILER` to a real driver.

## Tests

```bash
cd apps/api && php artisan test tests/Feature
```

> Run the `tests/Feature` suite explicitly — bare `php artisan test` errors on a missing `tests/Unit`
> directory.

62 feature tests cover auth, role gates, **tenant isolation** (cross-restaurant access → 404),
provisioning, validation rules, subscription/status gating, public-menu visibility, the landing-page
**leads** inbox (submit/validate/list/filter/status/CSV), and the **landing content** CMS
(all sections, defaults-merge fallback, super-admin-only editing).

## Public menu domain

By default each menu is served at `/(r)/{slug}`. Set `MENU_DOMAIN` to put every restaurant on its own
subdomain instead — `https://{slug}.tryorder.net/menu`:

```env
MENU_DOMAIN=tryorder.net
MENU_SECURE=true
```

This drives `Restaurant::publicUrl()`, so QR codes, the dashboard URL panel and the admin list all switch
to the subdomain form automatically. The `/r/{slug}` path keeps working as a fallback. Production needs a
**wildcard DNS record** (`*.tryorder.net` → the app) and a **wildcard TLS certificate**. Reserved
subdomains (`www`, `app`, `api`, …) are blocked from being used as slugs — see `config/platform.php`.
Locally, test with a `Host` header (`curl -H "Host: demo.tryorder.net" localhost:8123/menu`) or a
`/etc/hosts` entry.

## Design system

The UI implements the high-fidelity handoff (`design_handoff_qr_menu_saas/`). Tokens and fonts live in
two stylesheets:
- `resources/css/public.css` — the warm public-menu theme (DM Serif Display / Amiri headings, per-tenant
  `--accent` from each restaurant's `brand_color`, Arabic-Indic numerals in RTL).
- `resources/css/app.css` — the SPA design system: `.theme-warm` (restaurant admin) and `.theme-indigo`
  (super admin) token sets plus shared component classes (`.btn`, `.card`, `.stat`, `.switch`, `.segmented`,
  `.badge-*`, `.sheet`, `.qr-card`, …). The theme is applied at the portal root by `PortalShell.vue`.

Fonts: Space Grotesk (UI), IBM Plex Sans/Arabic (body), IBM Plex Mono (slugs/URLs) — loaded from Google
Fonts; self-host for production.

## Key conventions

- **Tenant isolation** is structural: a global `RestaurantScope` + `BelongsToRestaurant` trait scope
  every Category/MenuItem query to the authenticated user's restaurant. `restaurant_id` is never read
  from request input. See `app/Models/Scopes/`, `app/Support/TenantContext.php`.
- **Public data** is served through dedicated `*PublicResource` classes that omit internal/subscription
  fields.
- **Subscription gating** is config-driven — `config/platform.php` (`HIDE_MENU_WHEN_EXPIRED`,
  `ENFORCE_SUBSCRIPTION_WRITES`).
- **Slug** is editable by the Super Admin with a loud "breaks printed QR codes" warning.

## Production notes

- Set `DB_CONNECTION=pgsql` and real DB creds; the Eloquent code is identical.
- Set `APP_URL` to the real domain (drives `/r/{slug}` and QR targets), `SANCTUM_STATEFUL_DOMAINS` to
  the SPA host, and a real `MAIL_*` driver (provisioning emails the generated admin password).
- `UPLOAD_DISK=s3` for object storage; uploads are re-encoded to WebP and stripped of metadata.
- Serve over HTTPS; run `npm run build` and `php artisan migrate --force` on deploy.
