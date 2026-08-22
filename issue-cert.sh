#!/usr/bin/env bash
# ============================================================================
# issue-cert.sh — issue & auto-renew the WILDCARD TLS cert for Xorder.
#
#   Domains:  xorder.io  +  *.xorder.io   (one cert, two SANs)
#   Method:   ACME DNS-01 (wildcards cannot use HTTP-01)
#   Result:   cert installed where docker/nginx/xorder.io.conf expects it,
#             and Operix's nginx reloaded. acme.sh adds a cron job that
#             auto-renews + reloads from here on.
#
# Run this ON THE VPS (it talks to the DNS API + Let's Encrypt and reloads the
# live nginx). It does NOT touch operixhq.com or rakeezasolutions.com.
#
# ---------------------------------------------------------------------------
# DNS provider — set DNS_PROVIDER (default: namecheap).
#
#   namecheap  (default, current)  NAMECHEAP_USERNAME, NAMECHEAP_API_KEY
#                                  NAMECHEAP_SOURCEIP (auto-detected if unset)
#     Enable at: Namecheap → Profile → Tools → Business & Dev Tools → API Access.
#     The VPS public IP MUST be added to Namecheap's API whitelist on that page,
#     or every call returns "Invalid request IP".
#
#   cloudflare                     CF_Token  (scoped: Zone:DNS:Edit)
#
#   namecom    (LEGACY — DEAD)     NAMECOM_USERNAME, NAMECOM_TOKEN
#     xorder.io moved off name.com in Aug 2026. Kept only so an old cron job
#     that still calls this script fails loudly instead of silently.
#
#   NGINX_CONTAINER    name of Operix's nginx container (docker ps) — used for
#                      the post-issue reload. Auto-detected if left unset.
#   ACME_EMAIL         contact email for Let's Encrypt expiry notices.
#
# Usage:
#   export NAMECHEAP_USERNAME=... NAMECHEAP_API_KEY=... ACME_EMAIL=you@xorder.io
#   ./issue-cert.sh
#   # or:  DNS_PROVIDER=cloudflare CF_Token=... ./issue-cert.sh
#
# Re-running is safe: acme.sh skips issuance if a valid cert already exists
# (pass --force in ACME_ISSUE_EXTRA to override).
# ============================================================================
set -euo pipefail

# --- Config (override via env) ---------------------------------------------
DOMAIN="${DOMAIN:-xorder.io}"
CERT_DIR="${CERT_DIR:-/etc/letsencrypt/live/${DOMAIN}}"
ACME_EMAIL="${ACME_EMAIL:-}"
NGINX_CONTAINER="${NGINX_CONTAINER:-}"
ACME_ISSUE_EXTRA="${ACME_ISSUE_EXTRA:-}"   # e.g. --force, or --staging to test
DNS_PROVIDER="${DNS_PROVIDER:-namecheap}"
SKIP_NS_CHECK="${SKIP_NS_CHECK:-}"         # set to 1 to bypass the delegation preflight

ACME_SH="${HOME}/.acme.sh/acme.sh"

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "==> $*"; }
warn() { echo "WARNING: $*" >&2; }

# --- Provider wiring --------------------------------------------------------
# Each branch sets ACME_DNS_HOOK and exports the vars acme.sh expects, and
# declares the nameserver suffix the delegation preflight should expect.
case "${DNS_PROVIDER}" in
    namecheap)
        ACME_DNS_HOOK="dns_namecheap"
        EXPECTED_NS_SUFFIX="registrar-servers.com"   # Namecheap BasicDNS
        export NAMECHEAP_USERNAME="${NAMECHEAP_USERNAME:-}"
        export NAMECHEAP_API_KEY="${NAMECHEAP_API_KEY:-}"
        # acme.sh accepts a literal IP or a URL that echoes one. Namecheap
        # rejects any call from an IP that isn't on the API whitelist.
        if [ -z "${NAMECHEAP_SOURCEIP:-}" ]; then
            NAMECHEAP_SOURCEIP="$(curl -fsS --max-time 10 https://ifconfig.me 2>/dev/null || true)"
            [ -n "${NAMECHEAP_SOURCEIP}" ] \
                && info "NAMECHEAP_SOURCEIP auto-detected as ${NAMECHEAP_SOURCEIP}" \
                || die "Could not auto-detect the public IP. Set NAMECHEAP_SOURCEIP=<vps-ip>."
        fi
        export NAMECHEAP_SOURCEIP
        [ -n "${NAMECHEAP_USERNAME}" ] || die "NAMECHEAP_USERNAME is not set (Namecheap account username)."
        [ -n "${NAMECHEAP_API_KEY}" ]  || die "NAMECHEAP_API_KEY is not set (Namecheap → Tools → API Access)."
        warn "acme.sh's Namecheap hook rewrites the FULL host-record set on each"
        warn "renewal (Namecheap's API has no add-single-record call). Keep a"
        warn "screenshot of Advanced DNS before the first run."
        ;;
    cloudflare)
        ACME_DNS_HOOK="dns_cf"
        EXPECTED_NS_SUFFIX="ns.cloudflare.com"
        export CF_Token="${CF_Token:-}"
        [ -n "${CF_Token}" ] || die "CF_Token is not set (Cloudflare API token, scoped Zone:DNS:Edit)."
        ;;
    namecom)
        die "DNS_PROVIDER=namecom is dead: ${DOMAIN} left name.com in Aug 2026 and
       those nameservers now REFUSE the zone. Re-run with DNS_PROVIDER=namecheap
       (or cloudflare) and matching credentials."
        ;;
    *)
        die "Unknown DNS_PROVIDER='${DNS_PROVIDER}' (expected: namecheap | cloudflare)."
        ;;
esac

# --- Preflight --------------------------------------------------------------
command -v docker >/dev/null 2>&1 || die "docker not found on PATH."

if [ -z "${ACME_EMAIL}" ]; then
    ACME_EMAIL="admin@${DOMAIN}"
    info "ACME_EMAIL not set; using ${ACME_EMAIL}"
fi

# Delegation check. This is the exact failure that took xorder.io down in Aug
# 2026: the registry still delegated to name.com long after the zone moved, so
# the DNS-01 challenge had nowhere to land. Fail loudly instead of burning a
# Let's Encrypt rate-limit slot.
if [ -z "${SKIP_NS_CHECK}" ] && command -v dig >/dev/null 2>&1; then
    info "Checking that ${DOMAIN} is delegated to ${DNS_PROVIDER}…"
    LIVE_NS="$(dig +short "${DOMAIN}" NS 2>/dev/null | tr -d '\r' | sed 's/\.$//' | sort || true)"
    if [ -z "${LIVE_NS}" ]; then
        die "${DOMAIN} has no resolvable NS records — the zone is not delegated
       anywhere. Fix nameservers at the registrar first, wait for propagation,
       then re-run. (Bypass with SKIP_NS_CHECK=1.)"
    fi
    if ! echo "${LIVE_NS}" | grep -qi "${EXPECTED_NS_SUFFIX}"; then
        warn "${DOMAIN} is delegated to:"
        echo "${LIVE_NS}" | sed 's/^/         /' >&2
        warn "…which does not look like ${DNS_PROVIDER} (${EXPECTED_NS_SUFFIX})."
        warn "The DNS-01 challenge will likely fail. Bypass with SKIP_NS_CHECK=1."
    else
        info "Delegation OK: $(echo "${LIVE_NS}" | tr '\n' ' ')"
    fi
fi

# Auto-detect Operix's nginx container if not supplied.
if [ -z "${NGINX_CONTAINER}" ]; then
    info "NGINX_CONTAINER not set — trying to auto-detect an nginx container…"
    NGINX_CONTAINER="$(docker ps --filter ancestor=nginx --format '{{.Names}}' | head -n1)"
    if [ -z "${NGINX_CONTAINER}" ]; then
        # Fallback: any running container whose name contains 'nginx'.
        NGINX_CONTAINER="$(docker ps --format '{{.Names}}' | grep -i nginx | head -n1 || true)"
    fi
    [ -n "${NGINX_CONTAINER}" ] || die "Could not auto-detect nginx container. Set NGINX_CONTAINER=<name> (see: docker ps)."
    info "Detected nginx container: ${NGINX_CONTAINER}"
fi

# Confirm the container exists and that the vhost is installed in it.
docker inspect "${NGINX_CONTAINER}" >/dev/null 2>&1 \
    || die "Container '${NGINX_CONTAINER}' not found (docker ps)."
if ! docker exec "${NGINX_CONTAINER}" sh -c "grep -rqs 'server_name .*${DOMAIN}' /etc/nginx 2>/dev/null"; then
    cat >&2 <<EOF
WARNING: '${NGINX_CONTAINER}' has no server_name matching ${DOMAIN}.
         Install docker/nginx/xorder.io.conf into its conf.d/ and reload BEFORE
         (or right after) this script, otherwise the cert won't be served.
EOF
fi

RELOAD_CMD="docker exec ${NGINX_CONTAINER} nginx -s reload"

# --- Install acme.sh (idempotent) ------------------------------------------
if [ ! -x "${ACME_SH}" ]; then
    info "Installing acme.sh…"
    curl -fsSL https://get.acme.sh | sh -s -- -m "${ACME_EMAIL}"
fi
[ -x "${ACME_SH}" ] || die "acme.sh install failed (expected at ${ACME_SH})."

# Use Let's Encrypt as the default CA.
"${ACME_SH}" --set-default-ca --server letsencrypt >/dev/null 2>&1 || true

# --- Issue the wildcard cert (DNS-01) --------------------------------------
info "Issuing ${DOMAIN} + *.${DOMAIN} via ${DNS_PROVIDER} DNS-01…"
# shellcheck disable=SC2086
"${ACME_SH}" --issue --dns "${ACME_DNS_HOOK}" \
    -d "${DOMAIN}" -d "*.${DOMAIN}" \
    --server letsencrypt ${ACME_ISSUE_EXTRA}

# --- Install the cert where the nginx vhost points -------------------------
info "Installing cert to ${CERT_DIR} and wiring auto-reload…"
mkdir -p "${CERT_DIR}"
"${ACME_SH}" --install-cert -d "${DOMAIN}" \
    --key-file       "${CERT_DIR}/privkey.pem" \
    --fullchain-file "${CERT_DIR}/fullchain.pem" \
    --reloadcmd      "${RELOAD_CMD}"

# --- Verify -----------------------------------------------------------------
info "Reloading nginx now…"
eval "${RELOAD_CMD}"

info "Done. Cert SANs:"
openssl x509 -in "${CERT_DIR}/fullchain.pem" -noout -ext subjectAltName 2>/dev/null \
    || openssl x509 -in "${CERT_DIR}/fullchain.pem" -noout -text | grep -A1 'Subject Alternative Name' || true

cat <<EOF

Next checks (from anywhere):
  echo | openssl s_client -connect ${DOMAIN}:443 -servername demo.${DOMAIN} 2>/dev/null \\
    | openssl x509 -noout -ext subjectAltName     # expect *.${DOMAIN}
  curl -sI https://${DOMAIN}/up                    # expect 200
  curl -sI https://admin.${DOMAIN}/                # expect 200 (admin SPA)

Renewal is automatic (acme.sh cron). Force a dry-run renew with:
  ${ACME_SH} --renew -d ${DOMAIN} --force

NOTE: the acme.sh cron job stores whichever DNS credentials were used at issue
time in ~/.acme.sh/account.conf. After switching providers you MUST re-issue
once with --force so the cron job picks up the new ones — otherwise renewal
keeps calling the old (dead) API.
EOF
