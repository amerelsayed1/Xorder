# Test execution report: POS shifts and cash movements

Verified against: 2026-10-20 · cloud `main 06bc8e3` · POS `main d592db8` (test reports cited below were produced on the same revisions).

## Date and environment
No feature-targeted run has been recorded for this feature. Whole-project runs exist and are cited below; they are not a substitute for a targeted `/feature-testing pos-shifts` run.

## Commands executed
None for this feature specifically.

## Results (passed / failed / blocked / not run)
| Evidence | Result | Scope |
| --- | --- | --- |
| `docs/testing/reports/2026-10-20-project-test-report.md` | cloud suite 1024 passed (includes `PosShiftsTest`); POS 2670 passed, 69 skipped | whole project, SQLite / no database. Per-test results for the shift tests were not extracted. |
| `docs/testing/reports/2026-10-20-project-test-report-pg.md` | POS with local PostgreSQL: 3739 passed, 1 skipped | whole POS suite including `test/data/postgres_shift_test.dart` (per-test result not extracted) |
Feature-level status: **not run** (targeted).

## Evidence and logs (redacted)
See the two reports above.

## Known gaps and release risks
See `TEST_PLAN.md` gaps for AC-2 (cash movements), AC-4, AC-8, AC-9, the 403 capability refusals, and the PostgreSQL-only lock behavior on the cloud.
