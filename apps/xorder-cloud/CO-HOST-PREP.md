# Co-host Xorder (xorder.io) on the Operix VPS — prep checklist for Claude CLI

> **Goal:** prepare this repo so Xorder can run on the **same VPS as Operix and
> Rakeeza**, behind Operix's existing nginx, **without touching** Operix or Rakeeza.
> This file is a work-list for a Claude CLI session opened in `xorder-cloud/`.
> It mirrors the proven Rakeeza co-host setup, adapted to Xorder's monorepo +
> subdomain architecture.

---

## 0. Hard rules (do not break — same as Rakeeza)

1. **Never touch the server.** No SSH, no remote commands, no edits to anything on
   the VPS. Claude prepares files in this repo; the **user** runs them on the box.
2. **Never log into the user's accounts** (OVH, Namecheap, GitHub web). Hand the user
   exact clicks/commands/values instead.
3. Server-side facts (Docker network name, nginx container, cert paths) come **from
   the user** running read-only commands and pasting output.
4. **No deploy without explicit OK.** Building artifacts in the repo is fine; running
   anything that goes live needs the user's go-ahead.

## 1. Fixed server facts (the target)

- **VPS:** `51.68.229.216` (OVH). Already runs **Operix** (`operixhq.com`) and
  **Rakeeza** (`rakeezasolutions.com`).
- **Operix's nginx owns ports 80/443.** Everything else sits behind it on a shared
  Docker network and is reached **by hostname**. Xorder = Caddy-less, additive vhost.
- New app must **not collide** with `operix-*` / `rakeeza-*` container names, the
  rakeeza cohost host-port `127.0.0.1:8080`, or existing Docker volumes/networks.

```
internet ─► Operix nginx :443 ─┬─ operixhq.com            → Operix      (untouched)
                               ├─ rakeezasolutions.com    → rakeeza-app  (untouched)
                               └─ xorder.io  + *.xorder.io → xorder-web  (NEW)
                                                                 │ internal nginx
                                       xorder-web → xorder-app (PHP-FPM) → xorder-db
```

Note: Operix's nginx does a **plain host-preserving proxy_pass** to `xorder-web:80`.
Xorder's **own internal nginx** (the `web` build target) does all the apex-vs-subdomain
routing. So the outer vhost is simple; the app's nginx already knows the rest.

## 2. ⚠️ Decision that must be settled first — wildcard subdomains + TLS

Xorder is **not a single-hostname app** like Rakeeza. Its internal nginx routes:
- **`xorder.io`** (apex) → landing + Laravel `/api`, `/r`, `/menu`, `/storage`
- **`admin.xorder.io`** → admin SPA
- **`{slug}.xorder.io`** (one per restaurant, **dynamic**) → dashboard / guest menu SPA

Sanctum cookie auth depends on `*.xorder.io` being valid (see `.env.docker`
`SANCTUM_STATEFUL_DOMAINS=*.localhost...`). So production needs:

> **DNS for xorder.io is hosted at Namecheap** (BasicDNS, nameservers
> `*.registrar-servers.com`). It was at name.com until **Aug 2026**; the domain
> transferred to Namecheap on 2026-08-17 but the registry delegation was left
> pointing at name.com, whose nameservers then answered `REFUSED` — the whole
> site went dark until the nameservers were repointed. If `xorder.io` ever stops
> resolving, check `dig +short xorder.io NS` **before** touching the app.

- **DNS:** an apex `A` record **and a wildcard** `A *  → 51.68.229.216` (plus `www`).
- **TLS:** a certificate covering `xorder.io` **and** `*.xorder.io`. Certbot's
  **HTTP-01** challenge (what Rakeeza uses) **cannot issue wildcards** — wildcards
  require a **DNS-01** challenge (a `_acme-challenge` TXT record at Namecheap).

**→ Claude must confirm with the user before writing the vhost/cert steps:**

| Option | What it means |
|--------|---------------|
| **A. Wildcard (recommended, matches the app)** | Issue `xorder.io` + `*.xorder.io` via **DNS-01**. Best: **`acme.sh --dns dns_namecheap`** (Namecheap API key + whitelisted VPS IP → auto-renew). One-off fallback: `certbot --manual` with TXT records pasted into Namecheap Advanced DNS. Outer nginx: one server block for `xorder.io *.xorder.io`. |
| **B. Fixed subdomain list** | Only works if restaurants are a known, small set. Issue a SAN cert per subdomain via HTTP-01. New restaurant = new cert = not self-service. Usually **not acceptable** for this app. |
| **C. Restructure to path-based** | Drop subdomains, route by path (`/r/{slug}`). Code change in this repo + nginx + Sanctum config. Bigger lift; only if the user wants to avoid wildcards entirely. |

Default to **A** unless the user says otherwise. The rest of this list assumes A.

## 3. Repo artifacts — STATUS

All new files live in this repo; none touch the server. **Items marked [x] are
already created** in this pass; `[ ]` are optional follow-ups.

- [x] **`docker-compose.cohost.yml`** (repo root) — `app` (PHP-FPM), `web`
      (internal nginx, built with `NGINX_SITE_CONF=docker/nginx/default.prod.conf`),
      `db` (postgres:16-alpine). Names `xorder-app` / `xorder-web` / `xorder-db`.
      `web` joins `internal` + `proxy` (`external: true`,
      `name: ${OPERIX_PROXY_NETWORK}`) and binds **`127.0.0.1:8081:80`** (8080 is
      Rakeeza's). Volumes `xorder-db-data` / `xorder-storage`.
- [x] **`Dockerfile`** — the `web` stage now takes a `NGINX_SITE_CONF` build arg
      (defaults to the dev `default.conf`, so `docker compose up` is unchanged).
- [x] **`docker/nginx/default.prod.conf`** — production copy of the internal nginx
      config: apex `xorder.io`/`www` → landing + Laravel; `~^…\.xorder\.io$` →
      admin/menu SPA + Laravel. (Dev `default.conf` hardcodes `.localhost`.)
- [x] **`.env.production.example`** (repo root) — `APP_URL=https://xorder.io`,
      `SANCTUM_STATEFUL_DOMAINS=xorder.io,*.xorder.io`, `SESSION_DOMAIN=null`,
      `SESSION_SECURE_COOKIE=true`, `MENU_DOMAIN=xorder.io`, `MENU_SECURE=true`,
      `MENU_PORT=` (empty), `RUN_MIGRATIONS=true`, `SEED_ON_START=true` (flip to
      false after first boot), plus the compose-only `OPERIX_PROXY_NETWORK=`.
- [x] **`docker/nginx/xorder.io.conf`** — the **Operix-side** additive vhost.
      `server_name xorder.io www.xorder.io *.xorder.io;`, host-preserving
      `proxy_pass http://xorder-web:80;` with `X-Forwarded-Proto https`, plus a
      `:80` ACME/redirect block. Cert paths point at
      `/etc/letsencrypt/live/xorder.io/` — adjust to the user's actual paths.
- [x] **Health endpoint = `/up`** — no new route needed. Laravel's built-in health
      route (`bootstrap/app.php` `health: '/up'`) is already proxied to PHP by the
      internal nginx (`location = /up` in `laravel.conf`). Use
      `https://xorder.io/up` and `http://127.0.0.1:8081/up` (200 = healthy).
- [x] **Proxy trust** — added `$middleware->trustProxies(at: '*')` in
      `apps/api/bootstrap/app.php` so the app sees `https` behind the two nginx hops
      (correct URLs + secure cookies).
- [x] **`issue-cert.sh`** (repo root) — one-shot wildcard cert via `acme.sh`
      `dns_namecheap`: installs acme.sh, issues `xorder.io` + `*.xorder.io`, installs
      the cert to `/etc/letsencrypt/live/xorder.io/`, and reloads Operix's nginx
      (auto-detected or `NGINX_CONTAINER=…`). Sets up auto-renew. Run on the VPS with
      `NAMECHEAP_USERNAME` + `NAMECHEAP_API_KEY` exported. Set `DNS_PROVIDER=cloudflare`
      (+ `CF_Token`) to switch providers. Preflights that the zone is actually
      delegated to that provider before burning a Let's Encrypt rate-limit slot.
- [x] **`go-live.sh`** (repo root) — **one-command first bring-up.** Preflight →
      start xorder stack → wait for `127.0.0.1:8081/up` → issue cert
      (`issue-cert.sh`) → install the Operix vhost (`nginx -t`-gated, **auto-revert**
      on failure) → verify public endpoints. Toggles: `SKIP_CERT=1`, `SKIP_VHOST=1`,
      `NGINX_CONTAINER=`, `NGINX_CONFD=`. Run on the VPS with Namecheap creds exported.
- [ ] **`bootstrap-cohost.sh`** (optional) — adapt Rakeeza's: detect Operix's nginx
      container + network, generate `APP_KEY`/`DB_PASSWORD`, bring the stack up, curl
      internal `/up`, then (gated by `nginx -t`) install the vhost. For wildcard TLS
      it should **stop and print the DNS-01 instructions** rather than HTTP-01.
- [x] **`deploy.sh`** (repo root) — on-VPS deploy: DB backup → `git reset --hard
      origin/main` → `up -d --build` (app+web+db) → wait-for-health → migrate →
      `optimize` → internal smoke test (`http://127.0.0.1:8081/up`). **Auto-rolls
      back** to the previous commit if health fails. Never `down -v`, never touches
      Operix's nginx. `--ci` (non-interactive) and `--rollback` modes.
- [x] **`.github/workflows/deploy.yml`** — CI: **build-check** (pnpm install+build,
      composer install + `php -l` over apps/api) → **deploy** (SSH to the VPS, run
      `./deploy.sh --ci`). Triggers on push to `main` + manual `workflow_dispatch`;
      concurrency-locked so deploys never overlap. See §9 for the secrets to set.
- [ ] **`DEPLOY.md`** (optional) — promote §5/§6/§7 below into a standalone runbook.

## 4. Pre-upload local verification (Claude can run; no server)

- [ ] `docker compose --env-file .env.production -f docker-compose.cohost.yml build`
      succeeds (multi-stage: pnpm assets → composer vendor → php-fpm → nginx).
- [ ] Bring it up locally with a throwaway `OPERIX_PROXY_NETWORK` (create a dummy
      `docker network create xorder-test-proxy` and set it in `.env.production`) and
      confirm:
  - `curl -s http://127.0.0.1:8081/up` → 200 (Laravel health page)
  - `curl -s http://127.0.0.1:8081/` → landing HTML
  - `curl -s -H 'Host: admin.xorder.io' http://127.0.0.1:8081/` → SPA `index.html`
  - `curl -s -H 'Host: demo.xorder.io' http://127.0.0.1:8081/r/demo` → menu (or 404
    JSON if no `demo` restaurant — proves Laravel is routing, not the SPA)
  - migrations ran (entrypoint logs), super-admin seeded.
- [ ] Tear down; **do not** commit real secrets — only `.env.production.example`.

## 5. On-VPS go-live steps (the USER runs these — Claude writes them, doesn't run them)

1. **Facts to gather first** (user pastes output):
   ```bash
   docker network ls
   docker ps --format '{{.Names}}\t{{.Image}}'          # which is Operix's nginx
   ls /etc/letsencrypt/live/ 2>/dev/null
   ```
   → fill the real network name into `.env.production` and cert paths into the vhost.
2. **Clone** to `/opt/xorder`; `cp .env.production.example .env.production`; set
   `APP_KEY`, `DB_PASSWORD`, `OPERIX_PROXY_NETWORK`.
3. **Start Xorder (no 80/443):**
   ```bash
   docker compose --env-file .env.production -f docker-compose.cohost.yml up -d --build
   curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8081/up   # 200
   ```
4. **Issue the wildcard cert (DNS-01 at Namecheap).** Easiest — run the bundled
   helper (key from Namecheap → Tools → API Access). It installs acme.sh, issues the
   cert, installs it where the vhost points, reloads nginx, and sets up auto-renew:
   ```bash
   export NAMECHEAP_USERNAME="<namecheap_username>" NAMECHEAP_API_KEY="<api_key>"
   export ACME_EMAIL="you@xorder.io"
   ./issue-cert.sh                      # or: NGINX_CONTAINER=operix-nginx ./issue-cert.sh
   ```
   Equivalent manual commands (if you'd rather not use the script):
   ```bash
   curl https://get.acme.sh | sh -m you@xorder.io
   export NAMECHEAP_USERNAME="<namecheap_username>"; export NAMECHEAP_API_KEY="<api_key>"
   export NAMECHEAP_SOURCEIP="51.68.229.216"   # must be whitelisted in Namecheap API Access
   ~/.acme.sh/acme.sh --issue --dns dns_namecheap \
     -d xorder.io -d '*.xorder.io' --server letsencrypt
   ~/.acme.sh/acme.sh --install-cert -d xorder.io \
     --key-file       /etc/letsencrypt/live/xorder.io/privkey.pem \
     --fullchain-file /etc/letsencrypt/live/xorder.io/fullchain.pem \
     --reloadcmd      "docker exec <operix-nginx> nginx -s reload"
   ```
   One-off fallback (manual, renew by hand every ~90 days):
   ```bash
   certbot certonly --manual --preferred-challenges dns -d xorder.io -d '*.xorder.io'
   ```
   → add the printed `_acme-challenge` TXT record(s) at Namecheap, wait for
   propagation (`dig +short TXT _acme-challenge.xorder.io`), continue.
5. **Add the vhost:** copy `docker/nginx/xorder.io.conf` into Operix's nginx
   `conf.d/`, then `nginx -t && nginx -s reload` (auto-revert if `nginx -t` fails).
6. **Verify all three sites:** `xorder.io`, `admin.xorder.io`, a `{slug}.xorder.io`,
   **and** that `operixhq.com` + `rakeezasolutions.com` still respond.

## 6. DNS at Namecheap (user does this; Claude can't — it needs an account login)

Domain List → `xorder.io` → **Manage**:

1. **Nameservers** → select **Namecheap BasicDNS** → save. (If it still says
   "Custom DNS" with `*.name.com` entries, that IS the Aug-2026 outage — those
   nameservers answer `REFUSED`.)
2. **Advanced DNS** → delete any default parking / "URL Redirect" record on `@`
   or `www` (Namecheap adds these automatically and they shadow real A records),
   then add:

| Type | Host | Value | TTL |
|---|---|---|---|
| A | `@` | `51.68.229.216` | 1 min |
| A | `www` | `51.68.229.216` | 1 min |
| A | `*` | `51.68.229.216` | 1 min |

The `*` wildcard is load-bearing — every `{slug}.xorder.io` restaurant menu
depends on it. Raise TTL to 30 min once verified.

- Cert issuance via `acme.sh --dns dns_namecheap` writes/removes the
  `_acme-challenge` TXT records automatically (manual fallback: add by hand).
- API key for automation: Namecheap → Profile → **Tools** → Business & Dev Tools
  → **API Access**. Requires account eligibility (20+ domains, or $50 balance, or
  $50 spent in 2 years) **and** the VPS IP `51.68.229.216` added to the API
  whitelist on that same page, or every call returns "Invalid request IP".
- ⚠️ acme.sh's Namecheap hook rewrites the **full** host-record set on each
  renewal (the API has no add-single-record call). Screenshot Advanced DNS before
  the first automated run so the record set can be restored if it clobbers them.

## 7. Collision-avoidance map (vs Operix + Rakeeza on the same box)

| Resource | Rakeeza uses | **Xorder must use** |
|----------|--------------|---------------------|
| App container | `rakeeza-app` | `xorder-app` (PHP-FPM), `xorder-web` (nginx) |
| DB container | `rakeeza-db` | `xorder-db` |
| Host debug port | `127.0.0.1:8080` | `127.0.0.1:8081` |
| Compose volumes | `db-data`, `app-storage` | `xorder-db-data`, `xorder-storage` |
| Internal proxy hostname | `rakeeza-app` | `xorder-web` |
| Domain(s) | `rakeezasolutions.com` | `xorder.io` + `*.xorder.io` |
| Shared `proxy` network | `external: true` Operix net | **same** Operix net (don't recreate) |

## 8. Verify from here (read-only, safe)

Adapt `Rakeeza/.claude/skills/deploy/scripts/check-live.sh` to xorder.io (point its
health check at `/up`). After go-live, also `curl --resolve` a sample
`{slug}.xorder.io` to confirm wildcard routing + cert SAN.

## 9. CI/CD — auto-deploy on push (`.github/workflows/deploy.yml`)

**Flow:** push to `main` (or manual *workflow_dispatch*) → **build-check** (pnpm
install+build, composer install + `php -l`) → **deploy** (SSH to the VPS, run
`./deploy.sh --ci`). Concurrency-locked so two deploys never overlap.

**Why it stays stable:** `deploy.sh` only acts on the `xorder` compose project —
it never reloads/edits Operix's nginx, never runs `down -v`, backs up Postgres
first, and **auto-rolls back to the previous commit** if the post-deploy health
check fails. A broken build can't take xorder (or Operix/Rakeeza) down.

**One-time setup (user does this in GitHub — Claude can't):**

GitHub repo → Settings → Secrets and variables → Actions:

| Kind | Name | Value |
|------|------|-------|
| Secret | `SSH_HOST` | VPS IP `51.68.229.216` |
| Secret | `SSH_USER` | the deploy user on the VPS |
| Secret | `SSH_KEY`  | **private** key whose public half is in that user's `~/.ssh/authorized_keys` |
| Secret | `SSH_PORT` | SSH port (optional; defaults to 22) |
| Variable | `XORDER_DEPLOY_PATH` | optional; defaults to `/opt/xorder` |
| Variable | `XORDER_COMPOSE_FILE` | optional; defaults to `<path>/docker-compose.cohost.yml` |

Prereqs on the VPS (the human, once): repo cloned to `/opt/xorder`, a valid
`.env.production` present, and the first manual bring-up + cert done (§5).
Generate a dedicated deploy keypair (`ssh-keygen -t ed25519`), put the **public**
half in the VPS user's `authorized_keys`, the **private** half in `SSH_KEY`.

> The `deploy` job uses a GitHub `production` environment — add required reviewers
> there if you want a manual approval gate before each deploy.

---

### TL;DR of what's different from Rakeeza
1. **Monorepo** (pnpm/turbo) with its **own internal nginx** → outer vhost is a simple
   host-preserving proxy; the app routes apex vs subdomains itself.
2. **Subdomains + Sanctum** → needs **wildcard DNS** and a **wildcard TLS cert
   (DNS-01, not HTTP-01)**. This is the one real decision to settle up front (§2).
3. **Health check uses Laravel's built-in `/up`** (already proxied) — no new route.
4. **Port 8080 is taken by Rakeeza** → Xorder's debug port is **8081**, and every
   container/volume is namespaced `xorder-*`.
