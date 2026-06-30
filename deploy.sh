#!/usr/bin/env bash
# =============================================================================
# Xorder — Production Deploy Script   (xorder.io, co-hosted on the Operix VPS)
# Run ON THE SERVER from the repo dir (e.g. /opt/xorder/deploy.sh).
#
# Usage:
#   ./deploy.sh              — interactive deploy (asks for confirmation)
#   ./deploy.sh --ci         — non-interactive (for CI / GitHub Actions)
#   ./deploy.sh --rollback   — roll back to the previous git commit
#
# NOTE: the FIRST bring-up + the wildcard cert (issue-cert.sh) are one-time
# steps in CO-HOST-PREP.md. This script is for subsequent deploys once the site
# is already live.
#
# Stability guarantees (this is the whole point):
#   ✓ Operates ONLY on the xorder compose project — Operix + Rakeeza untouched.
#   ✓ NEVER reloads or edits Operix's nginx (TLS/routing stay stable).
#   ✓ Takes a DB backup BEFORE any change (aborts if the backup fails).
#   ✓ NEVER runs `down -v` — the Postgres volume is protected.
#   ✓ Health-gated: auto-rollback to the previous commit if the app doesn't
#     come back healthy, so a bad build can't leave the site down.
#   ✓ Blocks concurrent deploys (lock file); everything logged to ./logs.
# =============================================================================

set -euo pipefail

# ─── Config (override via environment) ───────────────────────────────────────
DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${XORDER_COMPOSE_FILE:-$DEPLOY_DIR/docker-compose.cohost.yml}"
ENV_FILE="${XORDER_ENV_FILE:-$DEPLOY_DIR/.env.production}"
BACKUP_DIR="$DEPLOY_DIR/backups"
LOG_FILE="$DEPLOY_DIR/logs/deploy.log"
LOCK_FILE="/tmp/xorder-deploy.lock"
# Internal, cert-independent health check — proves xorder itself serves without
# depending on Operix's nginx or the TLS cert. (web binds 127.0.0.1:8082.)
HEALTH_URL="${XORDER_HEALTH_URL:-http://127.0.0.1:8082/up}"
HEALTH_TIMEOUT=120

# Service names (must match docker-compose.cohost.yml)
APP_SVC="app"
WEB_SVC="web"
DB_SVC="db"

# ─── Flags ───────────────────────────────────────────────────────────────────
CI_MODE=false
ROLLBACK_MODE=false
for arg in "$@"; do
  case $arg in
    --ci)       CI_MODE=true ;;
    --rollback) ROLLBACK_MODE=true ;;
    --help|-h)  echo "Usage: $0 [--ci] [--rollback]"; exit 0 ;;
  esac
done

# ─── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'

# ─── Logging ─────────────────────────────────────────────────────────────────
log() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
  echo -e "$msg"
  echo "$msg" >> "$LOG_FILE"
}
log_step() { log "${BLUE}${BOLD}▶ $*${RESET}"; }
log_ok()   { log "${GREEN}✓ $*${RESET}"; }
log_warn() { log "${YELLOW}⚠ $*${RESET}"; }
log_fail() { log "${RED}✗ FATAL: $*${RESET}"; }

# ─── Compose wrapper: pins compose + env file, blocks any volume wipe ─────────
safe_compose() {
  for arg in "$@"; do
    if [[ "$arg" == "-v" || "$arg" == "--volumes" ]]; then
      log_fail "BLOCKED: 'docker compose $*' — -v/--volumes would DELETE the Postgres volume."
      exit 1
    fi
  done
  docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"
}

# ─── Lock: prevent concurrent deploys ────────────────────────────────────────
acquire_lock() {
  if [ -f "$LOCK_FILE" ]; then
    local LOCK_PID; LOCK_PID=$(cat "$LOCK_FILE")
    if kill -0 "$LOCK_PID" 2>/dev/null; then
      log_warn "Another deploy is running (PID $LOCK_PID). Waiting up to 10 min..."
      local waited=0
      while kill -0 "$LOCK_PID" 2>/dev/null && [ "$waited" -lt 600 ]; do
        sleep 10; waited=$((waited + 10))
      done
      kill -0 "$LOCK_PID" 2>/dev/null && { log_fail "Deploy still running after 10 min. Aborting."; exit 1; }
    fi
    rm -f "$LOCK_FILE"
  fi
  echo $$ > "$LOCK_FILE"
}
release_lock() { rm -f "$LOCK_FILE"; }
trap release_lock EXIT

# ─── DB Backup (Postgres) ────────────────────────────────────────────────────
backup_database() {
  log_step "Backing up database before deploy..."
  mkdir -p "$BACKUP_DIR"
  local TS; TS=$(date +%Y%m%d_%H%M%S)
  local BACKUP_FILE="$BACKUP_DIR/pre_deploy_${TS}.sql.gz"

  if ! safe_compose exec -T "$DB_SVC" \
       pg_dump -U "${DB_USERNAME:-xorder}" "${DB_DATABASE:-xorder}" | gzip > "$BACKUP_FILE"; then
    log_fail "Database backup FAILED. Deploy aborted — your data is safe."
    exit 1
  fi
  if [ ! -s "$BACKUP_FILE" ]; then
    log_fail "Backup file is empty. Deploy aborted."
    rm -f "$BACKUP_FILE"; exit 1
  fi
  log_ok "Backup created: $BACKUP_FILE ($(du -sh "$BACKUP_FILE" | cut -f1))"

  # Keep only the last 30 pre-deploy backups.
  ls -t "$BACKUP_DIR"/pre_deploy_*.sql.gz 2>/dev/null | tail -n +31 | xargs rm -f || true
  export LAST_BACKUP_FILE="$BACKUP_FILE"
}

# ─── Health checks ───────────────────────────────────────────────────────────
wait_for_health() {
  log_step "Waiting for app container (max ${HEALTH_TIMEOUT}s)..."
  local elapsed=0
  until safe_compose exec -T "$APP_SVC" php -r "echo 1;" >/dev/null 2>&1; do
    sleep 3; elapsed=$((elapsed + 3))
    [ "$elapsed" -ge "$HEALTH_TIMEOUT" ] && { log_fail "App not healthy within ${HEALTH_TIMEOUT}s."; return 1; }
  done
  log_ok "App container is healthy."
}
smoke_test() {
  log_step "Smoke test: $HEALTH_URL (max ${HEALTH_TIMEOUT}s)"
  # Poll, don't single-shot: right after a recreate the app needs a few seconds.
  local elapsed=0
  until curl -sf --max-time 15 "$HEALTH_URL" >/dev/null 2>&1; do
    sleep 3; elapsed=$((elapsed + 3))
    [ "$elapsed" -ge "$HEALTH_TIMEOUT" ] && { log_fail "Smoke test FAILED after ${HEALTH_TIMEOUT}s ($HEALTH_URL)."; return 1; }
  done
  log_ok "Smoke test passed."
}

# ─── Rollback ────────────────────────────────────────────────────────────────
do_rollback() {
  log_warn "ROLLBACK MODE"
  cd "$DEPLOY_DIR"
  local PREV; PREV=$(git log --oneline -2 | tail -1 | awk '{print $1}')
  log_step "Rolling back to: $PREV"
  git reset --hard "$PREV"
  safe_compose up -d --build --remove-orphans
  wait_for_health || { log_fail "Rollback failed. Manual intervention required. Last backup: ${LAST_BACKUP_FILE:-none}"; exit 1; }
  safe_compose exec -T "$APP_SVC" php artisan optimize:clear || true
  log_ok "Rollback complete: $PREV"
  exit 0
}

PREVIOUS_COMMIT=""
save_current_commit() { cd "$DEPLOY_DIR"; PREVIOUS_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo ""); }
auto_rollback() {
  log_fail "Deploy failed. Initiating automatic rollback..."
  if [ -n "$PREVIOUS_COMMIT" ]; then
    cd "$DEPLOY_DIR"
    git reset --hard "$PREVIOUS_COMMIT"
    safe_compose up -d --build --remove-orphans || true
    log_warn "Rolled back to: $PREVIOUS_COMMIT"
  fi
  log_warn "Last backup: ${LAST_BACKUP_FILE:-none taken yet}"
  log_fail "Deploy aborted. Check logs: $LOG_FILE"
  exit 1
}

# ─── Main ────────────────────────────────────────────────────────────────────
main() {
  mkdir -p "$(dirname "$LOG_FILE")"; touch "$LOG_FILE"
  log ""; log "═══════════════════════════════════════════════════"
  log " Xorder Deploy — $(date '+%Y-%m-%d %H:%M:%S')"
  log "═══════════════════════════════════════════════════"

  [ -f "$ENV_FILE" ] || { log_fail "Missing $ENV_FILE — copy .env.production.example and fill it in."; exit 1; }
  # Load DB_* (and OPERIX_PROXY_NETWORK) for the backup + compose steps.
  set -a; . "$ENV_FILE"; set +a

  [ "$ROLLBACK_MODE" = true ] && do_rollback

  acquire_lock
  cd "$DEPLOY_DIR"

  log_step "Fetching origin/main..."
  git fetch origin main 2>&1 | tee -a "$LOG_FILE"
  log "${BOLD}Changes to be deployed:${RESET}"
  git log HEAD..origin/main --oneline 2>/dev/null | tee -a "$LOG_FILE" || echo "(none)"

  if [ "$CI_MODE" = false ]; then
    echo -e "${YELLOW}${BOLD}Deploy these changes to PRODUCTION? [y/N]${RESET} "
    read -r CONFIRM
    [[ "$CONFIRM" == "y" || "$CONFIRM" == "Y" ]] || { log_warn "Cancelled."; exit 0; }
  fi

  save_current_commit
  trap auto_rollback ERR

  backup_database

  log_step "Pulling latest code..."
  git reset --hard origin/main
  log_ok "Code at: $(git rev-parse --short HEAD)"

  log_step "Building and starting containers (app + web + db)..."
  safe_compose up -d --build --remove-orphans
  log_ok "Containers started."

  wait_for_health

  # The entrypoint already migrates on boot; run again explicitly to be safe.
  log_step "Running migrations..."
  safe_compose exec -T "$APP_SVC" php artisan migrate --force 2>&1 | tee -a "$LOG_FILE"

  log_step "Warming caches..."
  safe_compose exec -T "$APP_SVC" php artisan optimize 2>&1 | tee -a "$LOG_FILE"

  # NOTE: no proxy reload. Operix's nginx owns 80/443 and is NOT ours to touch;
  # it keeps proxying to xorder-web across the recreate via the shared network.

  smoke_test

  trap release_lock EXIT
  log ""; log "═══════════════════════════════════════════════════"
  log_ok " Deploy SUCCESSFUL — $(git rev-parse --short HEAD)"
  log_ok " Backup: $LAST_BACKUP_FILE"
  log "═══════════════════════════════════════════════════"; log ""
}

main "$@"
