#!/usr/bin/env bash
# ===========================================================================
# One-command local dev for Xorder (SQLite, no Docker).
#
#   ./scripts/dev.sh
#
# Boots the Laravel API on :8000 and the two Vue dev servers (landing :5174,
# super-admin :5173). First run also installs deps, creates a SQLite .env,
# migrates + seeds (Super Admin + demo restaurant), and builds the public-menu
# CSS. Ctrl-C stops everything.
# ===========================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
API="$ROOT/apps/api"
cd "$ROOT"

say() { printf '\n\033[1;33m▶ %s\033[0m\n' "$1"; }
need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing required tool: $1"; exit 1; }; }

need php; need composer; need pnpm; need node

# --- API: install + first-time setup (idempotent) -------------------------
if [ ! -f "$API/vendor/autoload.php" ]; then
    say "Installing PHP dependencies"
    (cd "$API" && composer install)
fi

if [ ! -f "$API/.env" ]; then
    say "Creating apps/api/.env (SQLite)"
    cp "$API/.env.example" "$API/.env"
    # Switch to SQLite and drop the server-DB vars.
    sed -i.bak 's/^DB_CONNECTION=.*/DB_CONNECTION=sqlite/' "$API/.env"
    sed -i.bak '/^DB_HOST=/d;/^DB_PORT=/d;/^DB_DATABASE=/d;/^DB_USERNAME=/d;/^DB_PASSWORD=/d' "$API/.env"
    rm -f "$API/.env.bak"
    (cd "$API" && php artisan key:generate)
fi

if ! grep -q '^APP_KEY=base64:' "$API/.env"; then
    (cd "$API" && php artisan key:generate)
fi

touch "$API/database/database.sqlite"

# Migrate (always, safe) + seed only when the DB has no users yet.
say "Running migrations"
(cd "$API" && php artisan migrate --force)
if ! (cd "$API" && php artisan tinker --execute="exit(\App\Models\User::query()->exists() ? 0 : 1);") 2>/dev/null; then
    say "Seeding Super Admin + demo restaurant"
    (cd "$API" && php artisan db:seed --force && php artisan db:seed --class=DemoSeeder --force)
fi

# --- Front-end deps + public-menu assets ----------------------------------
if [ ! -d "$ROOT/node_modules" ]; then
    say "Installing workspace dependencies (pnpm)"
    pnpm install
fi
say "Building public-menu assets"
pnpm --filter @xorder/api build >/dev/null

# --- Launch everything ----------------------------------------------------
pids=()
cleanup() { echo; say "Stopping…"; for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done; }
trap cleanup EXIT INT TERM

say "API        → http://localhost:8000"
(cd "$API" && php artisan serve --host=127.0.0.1 --port=8000) & pids+=($!)
say "Landing    → http://localhost:5174"
pnpm --filter @xorder/landing dev & pids+=($!)
say "Super Admin→ http://localhost:5173"
pnpm --filter @xorder/web dev & pids+=($!)

cat <<EOF

────────────────────────────────────────────────────────
  Xorder is starting. Open in your browser:
    • Landing      http://localhost:5174
    • Super Admin  http://localhost:5173
    • Public menu  http://localhost:8000/r/xorderrest
  Login: the SUPER_ADMIN_EMAIL / SUPER_ADMIN_PASSWORD in apps/api/.env
  Press Ctrl-C to stop.
────────────────────────────────────────────────────────
EOF

wait
