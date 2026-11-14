# Project test report

## Date, scope and environment
- Date / time: 2026-10-22
- Scope: `pos` (cloud, Vue build, harness and PostgreSQL suites were not part of this run)
- Repos: `apps/xorder-pos` @ main d592db8 (uncommitted changes: yes, 11 files, of which 2 are source: `lib/features/admin/presentation/management_screen.dart` and `test/features/cloud_purchasing_hidden_test.dart`, 1 line each; the rest are docs, `CLAUDE.md` and `scripts/sync-coordination.sh`) · `apps/xorder-cloud` @ main 06bc8e3 (not tested in this run)
- Tool versions: Flutter 3.47.7 (stable, revision abaf9c5237), Dart 3.13.5. PHP 8.3.19, Node v23.11.0 and pnpm 9.15.9 were recorded but are not used by this scope. composer was not recorded.
- Database used: none. `POS_PG_*` variables are unset and the run used `env -u POS_PG_HOST`.

## Summary
| Suite | Command | Result | Passed | Failed | Skipped | Duration |
| --- | --- | --- | --- | --- | --- | --- |
| POS static analysis | `cd apps/xorder-pos && flutter analyze` | No issues found | n/a | 0 issues | n/a | 4.9 s |
| POS unit + widget | `cd apps/xorder-pos && env -u POS_PG_HOST flutter test --reporter expanded` | All tests passed | 2670 | 0 | 69 | about 2 min 12 s |

Test output ended with `+2670 ~69: All tests passed!` and exit code 0. `flutter analyze` ran `pub get` first and printed that 48 packages have newer versions incompatible with the constraints; that is informational, not an analyzer finding.

## Failures and triage
None. No test failed, so there was nothing to re-run or classify.

## Baseline comparison
Baseline 2026-10-20: cloud 1024 passed / 4966 assertions; POS analyze clean, 2670 passed + 69 skipped.
- Deltas: POS analyze unchanged (clean). POS tests unchanged: 2670 passed, 69 skipped, no tests added, removed or newly skipped. The two uncommitted source edits changed one line each and did not change the counts. The 69 skips are the `integration`-tagged PostgreSQL suites; the skip reason was not itemised in this run, so that attribution rests on the project's documented behaviour (suites self-skip without `POS_PG_HOST`).
- Regressions: none.

## Not run
- Cloud API suite — outside the `pos` scope (it was run separately earlier today: 1024 passed, 4966 assertions).
- Vue build — outside scope (also built earlier today).
- Harness verify — outside scope (it passed earlier today, before this run).
- POS PostgreSQL suites (`scripts/check.sh`) — requires user consent and a local PostgreSQL; `pg` scope was not requested. These cover the 69 skipped tests, the outbox, shifts, refunds and migrations against a real database.
- POS `integration_test/` — needs a desktop device and a database; not run by default.

## Coverage gaps (indicative; no coverage tool configured)
- The 69 skipped tests mean POS behaviour that depends on PostgreSQL (migrations, constraints, order and shift persistence, outbox drain) is unproven in this run.
- Nothing here exercises the POS against the cloud API; contract compatibility rests on the coordination ledger and cloud feature tests.
- Domain gaps recorded in `docs/domain/FOOD_SERVICE_DOMAIN.md` section 3 (tips, aggregators, KDS, recipes, loyalty, multi-brand, a moving food truck) have no tests because the features do not exist.

## Risks and next actions
- Low: the green result covers the pure domain, widget and fake-backed logic, which is where the money rules live (`TicketEngine`).
- Medium: before a POS release, run `apps/xorder-pos/scripts/check.sh` on a local PostgreSQL to turn the 69 skips into results. It creates and drops throwaway databases and roles, so it needs your go-ahead.
- Housekeeping: the POS working tree has 11 uncommitted files, including `CLAUDE.md` and two source lines, that were part of what was tested. Commit them deliberately, separately from any release.
