#!/usr/bin/env bash
# The project's verification, run on this machine rather than in CI: analyse,
# then every test including the PostgreSQL suites. CI only builds the Windows
# installer, and only when started by hand, so run this before pushing and
# before any release.
#
#   scripts/check.sh                 # everything
#   scripts/check.sh test/data       # extra args go to `flutter test`
#
# The PostgreSQL suites need a role that can CREATE DATABASE and CREATE ROLE.
# Defaults suit a Homebrew PostgreSQL, whose superuser is the login user; set
# POS_PG_HOST/PORT/USER/PASSWORD to point elsewhere. Every PostgreSQL suite
# shares ONE database per checkout (test/data/pg_fixture.dart), run one suite at
# a time, so a run leaves a single database behind instead of dozens and does not
# touch anyone else's. When the run ends (pass, fail or Ctrl+C) the databases and
# roles it made are dropped again, by tool/drop_test_databases.dart, which only
# ever matches THIS checkout's test names. KEEP_TEST_DBS=1 skips that, to look at
# what a failing suite left.
set -euo pipefail
# The till is the workspace member packages/xorder_pos. `flutter pub get` there
# resolves the whole workspace (the lockfile is at the root), and the test
# database names are tagged from this folder, as tool/drop_test_databases.dart
# expects.
cd "$(dirname "$0")/../packages/xorder_pos"

export POS_PG_HOST="${POS_PG_HOST:-127.0.0.1}"
export POS_PG_PORT="${POS_PG_PORT:-5432}"
export POS_PG_USER="${POS_PG_USER:-$USER}"
export POS_PG_PASSWORD="${POS_PG_PASSWORD:-postgres}"

if ! pg_isready -q -h "$POS_PG_HOST" -p "$POS_PG_PORT"; then
  echo "PostgreSQL is not accepting connections on $POS_PG_HOST:$POS_PG_PORT." >&2
  echo "Start it (brew services start postgresql@16) or set POS_PG_HOST/POS_PG_PORT." >&2
  exit 1
fi

# Remove what the PostgreSQL suites created, however the run ends. Never fails
# the run: a cleanup that cannot finish says so and leaves the rest to be run by
# hand (`dart run tool/drop_test_databases.dart --dry-run` shows what is left).
cleanup_test_databases() {
  if [ "${KEEP_TEST_DBS:-}" = "1" ]; then
    echo "KEEP_TEST_DBS=1: leaving the test databases in place."
    return 0
  fi
  echo "Removing this checkout's test databases..."
  dart run tool/drop_test_databases.dart \
    || echo "Test database cleanup did not finish; run: dart run tool/drop_test_databases.dart" >&2
}
trap cleanup_test_databases EXIT

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
# Two passes, because every PostgreSQL suite shares ONE database (see
# test/data/pg_fixture.dart): the ordinary tests run in parallel, the
# `integration` ones one at a time. Running them in parallel against the shared
# database brought back a fake "duplicate invoice number" failure.
flutter test --exclude-tags integration "$@"

# 79 is "no tests match the tag": a path argument that selects no PostgreSQL
# suite is not a failure.
set +e
flutter test --tags integration --concurrency=1 "$@"
status=$?
set -e
if [ "$status" -ne 0 ] && [ "$status" -ne 79 ]; then exit "$status"; fi

# The two apps (pos-split-apps stage 2). Each is an entry point plus platform
# folders over the shared package, so there is nothing to test in them yet —
# analysing proves they still compile against it. Skipped when a path argument
# narrows the run to part of the shared suite.
if [ "$#" -eq 0 ]; then
  for app in xorder_pos_offline xorder_pos_cloud; do
    echo "Analysing apps/$app"
    (cd "../../apps/$app" && flutter analyze)
  done
fi
echo "All checks passed."
