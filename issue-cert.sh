#!/usr/bin/env bash
# ============================================================================
# issue-cert.sh — issue & auto-renew the WILDCARD TLS cert for Xorder.
#
#   Domains:  xorder.io  +  *.xorder.io   (one cert, two SANs)
#   Method:   ACME DNS-01 via the name.com API (acme.sh dns_namecom)
#   Result:   cert installed where docker/nginx/xorder.io.conf expects it,
#             and Operix's nginx reloaded. acme.sh adds a cron job that
#             auto-renews + reloads from here on.
#
# Run this ON THE VPS (it talks to name.com + Let's Encrypt and reloads the
# live nginx). It does NOT touch operixhq.com or rakeezasolutions.com.
#
# ---------------------------------------------------------------------------
# Prerequisites (set as env vars, or edit the defaults below):
#   NAMECOM_USERNAME   name.com account username
#   NAMECOM_TOKEN      name.com API token  (Settings → API → production token:
#                      https://www.name.com/account/settings/api)
#   NGINX_CONTAINER    name of Operix's nginx container (docker ps) — used for
#                      the post-issue reload. Auto-detected if left unset.
#   ACME_EMAIL         contact email for Let's Encrypt expiry notices.
#
# Usage:
#   export NAMECOM_USERNAME=... NAMECOM_TOKEN=... ACME_EMAIL=you@xorder.io
#   ./issue-cert.sh
#   # or:  NGINX_CONTAINER=operix-nginx ./issue-cert.sh
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

# name.com credentials — acme.sh expects these exact variable names.
export Namecom_Username="${NAMECOM_USERNAME:-${Namecom_Username:-}}"
export Namecom_Token="${NAMECOM_TOKEN:-${Namecom_Token:-}}"

ACME_SH="${HOME}/.acme.sh/acme.sh"

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "==> $*"; }

# --- Preflight --------------------------------------------------------------
[ -n "${Namecom_Username}" ] || die "NAMECOM_USERNAME is not set (name.com account username)."
[ -n "${Namecom_Token}" ]    || die "NAMECOM_TOKEN is not set (name.com API token)."
command -v docker >/dev/null 2>&1 || die "docker not found on PATH."

if [ -z "${ACME_EMAIL}" ]; then
    ACME_EMAIL="admin@${DOMAIN}"
    info "ACME_EMAIL not set; using ${ACME_EMAIL}"
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

# --- Issue the wildcard cert (DNS-01 via name.com) -------------------------
info "Issuing ${DOMAIN} + *.${DOMAIN} via name.com DNS-01…"
# shellcheck disable=SC2086
"${ACME_SH}" --issue --dns dns_namecom \
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
EOF
