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
# The till is the workspace member packages/shared_module. `flutter pub get` there
# resolves the whole workspace (the lockfile is at the root), and the test
# database names are tagged from this folder, as tool/drop_test_databases.dart
# expects.
cd "$(dirname "$0")/../packages/shared_module"

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

# One member: analyse, then the two test passes. Two passes because every
# PostgreSQL suite shares ONE database per checkout (see
# packages/xorder_pos_test_support/lib/pg_fixture.dart): the ordinary tests run
# in parallel, the `integration` ones one at a time. Running them in parallel
# against the shared database brought back a fake "duplicate invoice number"
# failure. 79 is "no tests match the tag": a member or a path argument that
# selects no PostgreSQL suite is not a failure.
check_member() {
  echo "==> $1"
  (
    cd "$1"
    flutter analyze
    if [ -d test ]; then
      flutter test --exclude-tags integration "${@:2}"
      set +e
      flutter test --tags integration --concurrency=1 "${@:2}"
      status=$?
      set -e
      if [ "$status" -ne 0 ] && [ "$status" -ne 79 ]; then exit "$status"; fi
    fi
  )
}

# The shared till first, with any path arguments. Then the test-support
# package (analysis only: it has no tests of its own), the two till apps and
# the waiter handheld
# (pos-split-apps, stage 3: each carries its own code and tests — the back
# office in the offline app, the cloud sync in the cloud app). A path argument
# narrows the run to the shared package, where the paths are.
check_member . "$@"
if [ "$#" -eq 0 ]; then
  check_member ../xorder_pos_test_support
  check_member ../../apps/xorder_pos_offline
  check_member ../../apps/xorder_pos_cloud
  # The waiter handheld (waiter-app): its link package and the app. Neither
  # has PostgreSQL suites; the till's side of the link is tested in the
  # shared package, on both engines.
  check_member ../xorder_waiter_link
  check_member ../../apps/xorder_pos_waiter

  # The cloud till's engine (pos-cloud-single-till-sqlite): the same suites a
  # cloud till relies on, run again on an encrypted SQLite file instead of
  # PostgreSQL. Tests that need PostgreSQL itself (roles, migration replays,
  # disabled triggers) skip themselves here and say why.
  echo "==> SQLite (the cloud till's engine)"
  sqlite_suites=(
    order_lifecycle order_history order_history_paging sales_history
    refund_schema refund_history postgres_shift shift_history
    business_day_opening business_day_schema business_day_stamping
    parked_tickets_schema sync_queue print_queue_schema customers_repository
    order_customer discount_schema tender_types_schema receipt_profile_schema
    site_licence_postgres postgres_directory one_owner postgres_integration
    sqlite_schema sqlite_database sqlite_statement waiter_devices
  )
  files=()
  for suite in "${sqlite_suites[@]}"; do files+=("test/data/${suite}_test.dart"); done
  POS_TEST_ENGINE=sqlite flutter test --concurrency=1 "${files[@]}"
  (cd ../../apps/xorder_pos_cloud && POS_TEST_ENGINE=sqlite flutter test --concurrency=1 test/data)
fi
echo "All checks passed."
