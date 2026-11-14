#!/usr/bin/env bash
# =============================================================================
# Xorder — FIRST go-live on the Operix VPS (one command).
# Run ON THE SERVER from the repo dir (e.g. /opt/xorder/go-live.sh).
#
# This is the one-time bring-up. For subsequent deploys use ./deploy.sh.
#
# What it does, in order — each phase gated, nothing forced:
#   1. Preflight   — checks .env.production, docker, the Operix proxy network.
#   2. Bring up    — starts xorder app + web + db (no 80/443) and waits until
#                    http://127.0.0.1:8081/up returns 200.
#   3. Cert        — issues the wildcard cert via ./issue-cert.sh (Namecheap DNS-01).
#   4. Vhost       — installs docker/nginx/xorder.io.conf into Operix's nginx,
#                    `nginx -t`-gated with AUTO-REVERT on failure, then reloads.
#   5. Verify      — curls the public endpoints + checks the cert SANs.
#
# Stability: only the xorder containers are created; the Operix vhost step is
# additive and self-reverting (a bad config is removed before any reload, so
# operixhq.com / rakeezasolutions.com are never put at risk).
#
# Required env (cert phase):
#   NAMECHEAP_USERNAME  NAMECHEAP_API_KEY   Namecheap API creds (Profile → Tools
#                                           → API Access; VPS IP must be whitelisted)
# Optional env:
#   DNS_PROVIDER      namecheap (default) | cloudflare — passed to issue-cert.sh
#   CF_Token          Cloudflare API token, when DNS_PROVIDER=cloudflare
#   ACME_EMAIL        Let's Encrypt contact (default admin@xorder.io)
#   NGINX_CONTAINER   Operix's nginx container (auto-detected if unset)
#   NGINX_CONFD       host dir bind-mounted to the nginx container's conf.d.
#                     If set, the vhost is copied here; otherwise `docker cp`
#                     places it inside the container.
#   SKIP_CERT=1       skip phase 3 (cert already issued)
#   SKIP_VHOST=1      skip phase 4 (install the vhost yourself)
# =============================================================================
set -euo pipefail

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOMAIN="${DOMAIN:-xorder.io}"
COMPOSE_FILE="${XORDER_COMPOSE_FILE:-$DEPLOY_DIR/docker-compose.cohost.yml}"
ENV_FILE="${XORDER_ENV_FILE:-$DEPLOY_DIR/.env.production}"
HEALTH_URL="${XORDER_HEALTH_URL:-http://127.0.0.1:8082/up}"
HEALTH_TIMEOUT="${HEALTH_TIMEOUT:-120}"
VHOST_SRC="$DEPLOY_DIR/docker/nginx/${DOMAIN}.conf"
CERT_LIVE="/etc/letsencrypt/live/${DOMAIN}"
NGINX_CONTAINER="${NGINX_CONTAINER:-}"
NGINX_CONFD="${NGINX_CONFD:-}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'
log()      { echo -e "[$(date '+%H:%M:%S')] $*"; }
log_step() { log "${BLUE}${BOLD}▶ $*${RESET}"; }
log_ok()   { log "${GREEN}✓ $*${RESET}"; }
log_warn() { log "${YELLOW}⚠ $*${RESET}"; }
die()      { log "${RED}✗ $*${RESET}"; exit 1; }

compose() { docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"; }

detect_nginx() {
  [ -n "$NGINX_CONTAINER" ] && return 0
  NGINX_CONTAINER="$(docker ps --filter ancestor=nginx --format '{{.Names}}' | head -n1)"
  [ -z "$NGINX_CONTAINER" ] && NGINX_CONTAINER="$(docker ps --format '{{.Names}}' | grep -i nginx | head -n1 || true)"
  [ -n "$NGINX_CONTAINER" ] || die "Could not auto-detect Operix's nginx container. Set NGINX_CONTAINER=<name> (docker ps)."
  log_ok "Operix nginx container: $NGINX_CONTAINER"
}

# ── 1. Preflight ────────────────────────────────────────────────────────────
log_step "Preflight"
command -v docker >/dev/null || die "docker not found."
[ -f "$ENV_FILE" ] || die "Missing $ENV_FILE — copy .env.production.example and fill APP_KEY, DB_PASSWORD, OPERIX_PROXY_NETWORK."
set -a; . "$ENV_FILE"; set +a
# JWT_SECRET and SUPER_ADMIN_PASSWORD are seeded/used on first bring-up: an
# empty JWT_SECRET makes every login 500, and an empty SUPER_ADMIN_PASSWORD
# would (before the seeder's fail-closed guard) provision a guessable platform
# admin. Require both here so go-live aborts loudly instead of shipping either.
for v in APP_KEY DB_PASSWORD OPERIX_PROXY_NETWORK JWT_SECRET SUPER_ADMIN_PASSWORD; do
  [ -n "${!v:-}" ] || die "$v is empty in $ENV_FILE."
done
# Provisioning/reset emails carry the generated admin password in cleartext; the
# `log` mailer would write it to disk. Warn loudly (non-fatal — a real SMTP
# transport should be configured before any tenant is provisioned).
[ "${MAIL_MAILER:-}" = "log" ] && log_warn "MAIL_MAILER=log writes admin-credential emails (cleartext passwords) to the log. Configure real SMTP before provisioning tenants."
docker network inspect "$OPERIX_PROXY_NETWORK" >/dev/null 2>&1 \
  || die "Docker network '$OPERIX_PROXY_NETWORK' not found. Set OPERIX_PROXY_NETWORK to Operix's nginx network (docker network ls)."
[ -f "$VHOST_SRC" ] || die "Vhost template not found: $VHOST_SRC"
log_ok "Env, docker, and proxy network '$OPERIX_PROXY_NETWORK' look good."

# ── 2. Bring up the xorder stack + health gate ──────────────────────────────
log_step "Starting xorder stack (app + web + db)…"
compose up -d --build --remove-orphans
log_step "Waiting for $HEALTH_URL (max ${HEALTH_TIMEOUT}s)…"
elapsed=0
until curl -sf --max-time 10 "$HEALTH_URL" >/dev/null 2>&1; do
  sleep 3; elapsed=$((elapsed + 3))
  [ "$elapsed" -ge "$HEALTH_TIMEOUT" ] && { compose logs --tail=40 app || true; die "App did not become healthy in ${HEALTH_TIMEOUT}s."; }
done
log_ok "xorder is serving internally ($HEALTH_URL = 200)."

# ── 2b. One-time seeding (Super Admin + plans + demo data) ──────────────────
# Seeding lives HERE, not in deploy.sh / SEED_ON_START: DatabaseSeeder
# updateOrCreate()s the Super Admin, so re-running it on every deploy would
# reset the Super Admin password back to the .env value. Seed once, then
# leave SEED_ON_START=false in .env.production.
log_step "Seeding Super Admin + subscription plans (one-time, idempotent)…"
compose exec -T app php artisan db:seed --force
if [ "${SEED_DEMO:-true}" = "true" ]; then
  log_step "Seeding demo data (XorderRest + showcase tenants)…"
  compose exec -T app php artisan db:seed --class=DemoSeeder --force
  log_ok "Demo data seeded. Deploys do NOT re-seed; refresh with: SEED_DEMO=true ./deploy.sh"
fi

# ── 3. Wildcard cert (DNS-01) ───────────────────────────────────────────────
if [ "${SKIP_CERT:-0}" = "1" ]; then
  log_warn "SKIP_CERT=1 — skipping cert issuance."
else
  log_step "Issuing wildcard cert for ${DOMAIN} + *.${DOMAIN}…"
  case "${DNS_PROVIDER:-namecheap}" in
    namecheap)
      [ -n "${NAMECHEAP_USERNAME:-}" ] && [ -n "${NAMECHEAP_API_KEY:-}" ] \
        || die "NAMECHEAP_USERNAME / NAMECHEAP_API_KEY not set (needed for DNS-01). Export them, or re-run with SKIP_CERT=1 if the cert already exists." ;;
    cloudflare)
      [ -n "${CF_Token:-}" ] \
        || die "CF_Token not set (needed for DNS-01 via Cloudflare). Export it, or re-run with SKIP_CERT=1 if the cert already exists." ;;
    *)
      die "Unknown DNS_PROVIDER='${DNS_PROVIDER}' (expected: namecheap | cloudflare)." ;;
  esac
  detect_nginx
  NGINX_CONTAINER="$NGINX_CONTAINER" "$DEPLOY_DIR/issue-cert.sh"
  log_ok "Cert issued + installed to ${CERT_LIVE}."
fi

# ── 4. Install the Operix-side vhost (additive, self-reverting) ─────────────
if [ "${SKIP_VHOST:-0}" = "1" ]; then
  log_warn "SKIP_VHOST=1 — install docker/nginx/${DOMAIN}.conf into Operix's nginx yourself."
else
  log_step "Installing the ${DOMAIN} vhost into Operix's nginx…"
  detect_nginx

  # The vhost references the cert; Operix's nginx must be able to read it.
  if ! docker exec "$NGINX_CONTAINER" sh -c "test -f ${CERT_LIVE}/fullchain.pem" 2>/dev/null; then
    log_warn "Operix's nginx ($NGINX_CONTAINER) can't see ${CERT_LIVE}/fullchain.pem."
    log_warn "Its container probably doesn't mount /etc/letsencrypt. Mount the host's"
    log_warn "/etc/letsencrypt into $NGINX_CONTAINER (read-only) and re-run with SKIP_CERT=1,"
    log_warn "or install the vhost manually. Skipping the vhost step to stay safe."
  else
    CONF_NAME="${DOMAIN}.conf"
    if [ -n "$NGINX_CONFD" ]; then
      # conf.d is a host bind-mount.
      cp "$VHOST_SRC" "$NGINX_CONFD/$CONF_NAME"
      REVERT() { rm -f "$NGINX_CONFD/$CONF_NAME"; }
    else
      # conf.d lives inside the container.
      docker cp "$VHOST_SRC" "$NGINX_CONTAINER:/etc/nginx/conf.d/$CONF_NAME"
      REVERT() { docker exec "$NGINX_CONTAINER" rm -f "/etc/nginx/conf.d/$CONF_NAME"; }
    fi

    if docker exec "$NGINX_CONTAINER" nginx -t >/dev/null 2>&1; then
      docker exec "$NGINX_CONTAINER" nginx -s reload
      log_ok "Vhost installed and nginx reloaded (operixhq.com / rakeezasolutions.com untouched)."
    else
      log_warn "nginx -t FAILED with the new vhost — reverting, nothing reloaded:"
      docker exec "$NGINX_CONTAINER" nginx -t || true
      REVERT
      die "Vhost not installed (auto-reverted). Fix the cert paths in $VHOST_SRC and re-run with SKIP_CERT=1."
    fi
  fi
fi

# ── 5. Verify ───────────────────────────────────────────────────────────────
log_step "Verifying public endpoints…"
PUB_OK=true
curl -sf --max-time 15 "https://${DOMAIN}/up" >/dev/null 2>&1 && log_ok "https://${DOMAIN}/up → 200" || { log_warn "https://${DOMAIN}/up not reachable yet (DNS/cert propagation?)."; PUB_OK=false; }
curl -sf --max-time 15 "https://admin.${DOMAIN}/" >/dev/null 2>&1 && log_ok "https://admin.${DOMAIN}/ → 200" || log_warn "https://admin.${DOMAIN}/ not reachable yet."
if [ -f "${CERT_LIVE}/fullchain.pem" ]; then
  log "Cert SANs: $(openssl x509 -in "${CERT_LIVE}/fullchain.pem" -noout -ext subjectAltName 2>/dev/null | tail -1 | sed 's/^ *//')"
fi

echo
if [ "$PUB_OK" = true ]; then
  log_ok "${BOLD}Xorder is LIVE at https://${DOMAIN}.${RESET}"
else
  log_warn "Stack is up and the cert/vhost are in place; the public check didn't pass yet."
  log_warn "Re-test in a few minutes:  curl -sI https://${DOMAIN}/up"
fi
log "Confirm the neighbours still work:  curl -sI https://operixhq.com  ;  curl -sI https://rakeezasolutions.com"
