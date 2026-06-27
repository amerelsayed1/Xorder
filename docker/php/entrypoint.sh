#!/bin/sh
set -e

cd /var/www/html

# ---------------------------------------------------------------------------
# Wait for the database to accept connections (only when using a DB server).
# ---------------------------------------------------------------------------
if [ "${DB_CONNECTION:-pgsql}" != "sqlite" ]; then
    echo "Waiting for database ${DB_HOST}:${DB_PORT}…"
    until php -r '
        try {
            new PDO(
                getenv("DB_CONNECTION").":host=".getenv("DB_HOST").";port=".getenv("DB_PORT").";dbname=".getenv("DB_DATABASE"),
                getenv("DB_USERNAME"), getenv("DB_PASSWORD")
            );
            exit(0);
        } catch (Throwable $e) { exit(1); }
    ' 2>/dev/null; do
        sleep 2
    done
    echo "Database is up."
fi

# ---------------------------------------------------------------------------
# One-time app preparation.
# ---------------------------------------------------------------------------
# Public storage symlink (idempotent).
php artisan storage:link 2>/dev/null || true

if [ "${RUN_MIGRATIONS:-true}" = "true" ]; then
    php artisan migrate --force
fi

# Seed the Super Admin (idempotent updateOrCreate) when requested.
if [ "${SEED_ON_START:-false}" = "true" ]; then
    php artisan db:seed --force
fi

# Cache framework config for production performance.
php artisan config:cache
php artisan route:cache
php artisan view:cache

exec "$@"
