# Test execution report: Tenant isolation (restaurant scope)

Verified against: 2026-10-20 · cloud `main 06bc8e3` · POS `main d592db8` (uncommitted files in both repos are documentation, agent/script files and two POS files outside this feature; none is cited as evidence unless stated). Core state: `drafted` (author self-check, mechanical citation check; no independent validation pass). Path prefixes: `C:` = `apps/xorder-cloud/apps/api/`, `P:` = `apps/xorder-pos/`, `W:` = `apps/xorder-cloud/apps/web/`, `K:` = `apps/xorder-cloud/packages/`, `A:` = `apps/xorder-cloud/apps/`.

## Date and environment
No feature-targeted run has been recorded for this feature. Whole-project runs from 2026-10-20 are cited below; they are not a substitute for a targeted `/feature-testing tenant-isolation` run.

## Commands executed
None for this feature specifically.

## Results (passed / failed / blocked / not run)
| Evidence | Result | Scope |
| --- | --- | --- |
| `docs/testing/reports/2026-10-20-project-test-report.md` | cloud suite 1024 passed (4966 assertions); POS 2670 passed, 69 skipped (no database) | whole project; per-test results for this feature were not extracted |
| `docs/testing/reports/2026-10-20-project-test-report-pg.md` | POS with local PostgreSQL 3739 passed, 1 skipped | whole POS suite |
Feature-level status: **not run** (targeted).

## Evidence and logs (redacted)
See the two reports above.

## Known gaps and release risks
See the gaps column of the tests table in `FEATURE.md` and `TEST_PLAN.md`.
