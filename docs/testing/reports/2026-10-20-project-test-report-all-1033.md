# Project test report — scope `all`

## Date, scope and environment
- Date: 2026-10-20 (run via `/project-testing`, default scope `all` = cloud + POS + harness)
- Repos: `apps/xorder-cloud` @ main 06bc8e3 (10 uncommitted files: doc/agent/sync-script text edits) · `apps/xorder-pos` @ main d592db8 (11 uncommitted files: docs, `CLAUDE.md`, sync script, 2 comment-only code edits)
- Tools: PHP 8.3.19, Composer 2.8.8, Node v23.11.0, pnpm 9.15.9, Flutter 3.47.7, Dart 3.13.5
- Database: cloud = SQLite `:memory:` (verified in `phpunit.xml`: `APP_ENV=testing`, `DB_CONNECTION=sqlite`); POS = none (`POS_PG_HOST` unset)

## Summary
| Suite | Command | Result | Passed | Failed | Skipped | Duration |
| --- | --- | --- | --- | --- | --- | --- |
| Cloud API | `cd apps/xorder-cloud/apps/api && php artisan test` | PASS (exit 0) | 1024 (4966 assertions) | 0 | 0 | 49 s |
| POS analyze | `cd apps/xorder-pos && flutter analyze` | PASS, "No issues found" (exit 0) | n/a | 0 issues | n/a | 10 s |
| POS unit + widget | `cd apps/xorder-pos && env -u POS_PG_HOST flutter test` | PASS, "All tests passed!" (exit 0) | 2670 | 0 | 69 | 157 s |
| Harness | `bash scripts/harness/verify.sh` | PASS (exit 0): 19 skills, 12 agents, docs structure OK, 489 line citations resolve | n/a | 0 | n/a | <5 s |

## Failures and triage
None. No failing, flaky or environment-blocked tests.

## Baseline comparison
Baseline 2026-10-20: cloud 1024 passed / 4966 assertions; POS analyze clean, 2670 passed + 69 skipped.
- Deltas: none — identical counts.
- Regressions: none.

## Not run
- POS PostgreSQL-backed suites (`scripts/check.sh`) and the 69 skipped tests: scope `pg` was not requested (needs a local PostgreSQL and consent). An earlier `pg` report exists in this folder.
- Vue apps `pnpm build`: scope `build` not requested. The Vue apps have no unit/E2E/lint scripts, so they have no automated tests.
- POS `integration_test/`: needs a desktop device and database.
- Anything against PostgreSQL for the cloud API (the suite is SQLite-only).

## Coverage gaps (indicative; no coverage tool configured)
- Vue apps (`apps/web`, `landing`, `menu`, `packages/*`): no tests.
- Cloud migrations/queries are never exercised on PostgreSQL, the production database.
- POS offline-sync and datastore paths are covered only by the 69 PostgreSQL-tagged tests that skip here.
- Route-to-test mapping was not analysed in this run.

## Risks and next actions
- Green result covers only what is listed above; production-database and UI behaviors remain untested by automation.
- Both repos have uncommitted (text-only) changes that were included in this run.
- Next: run `/project-testing pg` (with consent) and `/project-testing build` for the remaining scopes.
