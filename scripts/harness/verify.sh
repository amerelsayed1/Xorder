#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
failed=0
printf 'Xorder safe local checks (no migrations/deployment/push/backup access)\n'
python3 -I "$ROOT/scripts/harness/check-harness.py" || failed=1
python3 -I "$ROOT/scripts/harness/check-docs.py" || failed=1
python3 -I "$ROOT/scripts/harness/check-citations.py" || failed=1
if [ -f "$ROOT/apps/xorder-cloud/apps/api/artisan" ] && command -v php >/dev/null 2>&1; then
  echo 'Laravel app detected (apps/xorder-cloud/apps/api). Tests use SQLite :memory: (phpunit.xml): (cd apps/xorder-cloud/apps/api && php artisan test)'
fi
if [ -f "$ROOT/apps/xorder-cloud/package.json" ]; then
  echo 'Vue/pnpm monorepo detected (xorder-cloud). No JS test/lint scripts are defined; build: (cd apps/xorder-cloud && pnpm build). Nothing auto-executed.'
fi
if [ -f "$ROOT/apps/xorder-pos/pubspec.yaml" ] && command -v flutter >/dev/null 2>&1; then
  echo 'Flutter project detected. Recommended: (cd apps/xorder-pos && flutter analyze && flutter test); full check incl. PostgreSQL: apps/xorder-pos/scripts/check.sh'
fi
exit "$failed"
