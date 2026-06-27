# QR Menu SaaS — MVP

Menu-only multi-tenant SaaS. A **Super Admin** provisions restaurants and their first admin; each
**Restaurant Admin** manages their own menu; the public sees a fast, SEO-friendly, RTL/LTR QR menu at
`/r/{slug}`. No cart, orders, or payments (MVP v1).

**Stack:** Laravel 13 (API) · Vue 3 SPA (Super Admin + Restaurant dashboards) · Blade SSR (public menu)
· Sanctum cookie auth · SQLite (dev) / PostgreSQL (prod). See [ARCHITECTURE.md](ARCHITECTURE.md) for the
full design.

## Quick start

```bash
composer install
npm install
cp .env.example .env          # then set SUPER_ADMIN_* and APP_URL
php artisan key:generate
touch database/database.sqlite
php artisan migrate --seed     # creates the Super Admin from .env
php artisan db:seed --class=DemoSeeder   # optional: a demo restaurant at /r/demo
npm run build                  # or: npm run dev
php artisan serve
```

Open:
- **Public menu:** `/r/demo`
- **Login (SPA):** `/login` → Super Admin redirects to `/admin`, Restaurant Admin to `/dashboard`
- **Super Admin:** the seeded `SUPER_ADMIN_EMAIL` / `SUPER_ADMIN_PASSWORD`
- **Demo restaurant admin:** `owner@demo.test` / `password`

> SPA cookie auth requires the browser origin to be listed in `SANCTUM_STATEFUL_DOMAINS`. The default
> covers `127.0.0.1:8123`; if you run `php artisan serve` on another port, add it there.

## Run with Docker

Multi-stage build → **Nginx + PHP-FPM + PostgreSQL**. Front-end assets are compiled in an image
stage, so no Node is needed on the host.

```bash
# 1. Create the compose env, then set APP_KEY + passwords inside it
cp .env.docker.example .env.docker
docker compose run --rm app php artisan key:generate --show   # paste into APP_KEY
docker compose up -d --build
```

On first boot the app container waits for Postgres, runs migrations, seeds the Super Admin
(`SEED_ON_START=true`), and caches config/routes/views. Then:

- App: <http://localhost:8080>  · public menu at `/r/{slug}` · SPA at `/login`
- Postgres is internal; data persists in the `pgdata` volume, uploads in `storage-data`.

```bash
docker compose logs -f app           # follow app logs (logged to stderr)
docker compose exec app php artisan db:seed --class=DemoSeeder --force   # optional demo data
docker compose down                  # stop (add -v to wipe db + uploads)
```

Files: [`Dockerfile`](Dockerfile) (stages `assets`/`vendor`/`app`/`web`),
[`docker-compose.yml`](docker-compose.yml), [`.env.docker`](.env.docker),
[`docker/`](docker/) (nginx conf, php.ini, entrypoint).

> Behavior toggles via env: `RUN_MIGRATIONS`, `SEED_ON_START`, `HIDE_MENU_WHEN_EXPIRED`,
> `ENFORCE_SUBSCRIPTION_WRITES`. For a real domain, set `APP_URL` and `SANCTUM_STATEFUL_DOMAINS`
> to that host and switch `MAIL_MAILER` to a real driver.

## Tests

```bash
php artisan test
```

30 feature tests cover auth, role gates, **tenant isolation** (cross-restaurant access → 404),
provisioning, validation rules, subscription/status gating, and public-menu visibility.

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
