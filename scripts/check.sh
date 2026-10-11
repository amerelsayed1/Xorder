#!/usr/bin/env bash
# The checks CI's `verify` job runs, on this machine: analyse, then every test
# including the PostgreSQL suites. CI itself only runs when started by hand, so
# run this before pushing.
#
#   scripts/check.sh                 # everything
#   scripts/check.sh test/data       # extra args go to `flutter test`
#
# The PostgreSQL suites need a role that can CREATE DATABASE and CREATE ROLE.
# Defaults suit a Homebrew PostgreSQL, whose superuser is the login user; set
# POS_PG_HOST/PORT/USER/PASSWORD to point elsewhere. Each suite and each
# checkout gets its own database (test/data/pg_fixture.dart), so this is safe
# against a server other work also uses.
set -euo pipefail
cd "$(dirname "$0")/.."

export POS_PG_HOST="${POS_PG_HOST:-127.0.0.1}"
export POS_PG_PORT="${POS_PG_PORT:-5432}"
export POS_PG_USER="${POS_PG_USER:-$USER}"
export POS_PG_PASSWORD="${POS_PG_PASSWORD:-postgres}"

if ! pg_isready -q -h "$POS_PG_HOST" -p "$POS_PG_PORT"; then
  echo "PostgreSQL is not accepting connections on $POS_PG_HOST:$POS_PG_PORT." >&2
  echo "Start it (brew services start postgresql@16) or set POS_PG_HOST/POS_PG_PORT." >&2
  exit 1
fi

# The backup suites run pg_dump, which refuses a server newer than itself.
# Put the client tools that match the server's major version first on PATH
# when they are installed side by side (Homebrew's postgresql@N).
server_major="$(PGPASSWORD="$POS_PG_PASSWORD" psql -h "$POS_PG_HOST" -p "$POS_PG_PORT" \
  -U "$POS_PG_USER" -d postgres -tAc 'SHOW server_version_num' 2>/dev/null | cut -c1-2 || true)"
if [ -n "$server_major" ]; then
  for dir in "/opt/homebrew/opt/postgresql@$server_major/bin" \
             "/usr/local/opt/postgresql@$server_major/bin" \
             "/usr/lib/postgresql/$server_major/bin"; do
    if [ -x "$dir/pg_dump" ]; then export PATH="$dir:$PATH"; break; fi
  done
fi
echo "PostgreSQL server ${server_major:-unknown}; $(pg_dump --version 2>/dev/null || echo 'pg_dump not found')"

flutter pub get
flutter analyze
flutter test "$@"
echo "All checks passed."
