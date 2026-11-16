# Project test report

## Date, scope and environment
- Date / time: 2026-11-16
- Scope: `all` (cloud + POS + harness) plus the Vue build
- Repo: monorepo `Xorder-mono` @ branch `fix/live-view-no-data-rewrite`, HEAD `5e3e4fce`, **uncommitted changes: yes** (14 paths: the `live.view` fixes, new `StaleLiveViewCapabilityTest`, doc edits). They are part of what was tested.
- Tool versions: PHP 8.3.19, Composer 2.8.8, Node v24.22.0, pnpm 12.16.1, Flutter 3.47.7, Dart 3.13.5. Host OS: macOS (Darwin 25.6.0).
- Database used: SQLite `:memory:` for cloud (`phpunit.xml` sets `DB_CONNECTION=sqlite`, `DB_DATABASE=:memory:`, checked before the run). POS: no database (`POS_PG_HOST` unset; integration-tagged suites skip).
- Cloud tests were run through `make test-cloud`, which injects Doppler `prd` secrets (`APP_KEY`, `JWT_SECRET`) as environment variables. Tests never touch a real database.

## Summary
| Suite | Command | Result | Passed | Failed | Skipped | Duration |
| --- | --- | --- | --- | --- | --- | --- |
| Cloud API | `make test-cloud` (= `cd apps/xorder-cloud/apps/api && doppler run -- php artisan test`) | **pass** | 1300 (6789 assertions) | 0 | 0 | 78.7 s |
| Vue build (web, landing, menu) | `cd apps/xorder-cloud && pnpm build --force` (clean rebuild) | **pass** | 3 of 3 tasks | 0 | n/a | 2.2 s |
| POS static analysis | `cd apps/xorder-pos && flutter analyze` | **pass** | no issues | 0 | n/a | 5.8 s |
| POS `packages/shared_module` | `env -u POS_PG_HOST flutter test` | pass | 2670 | 0 | 79 | n/m |
| POS `apps/xorder_pos_cloud` | same | pass | 127 | 0 | 9 | n/m |
| POS `apps/xorder_pos_offline` | same | pass | 861 | 0 | 1 | n/m |
| POS `apps/xorder_pos_waiter` | same | **2 failures** | 18 | 2 | 0 | n/m |
| POS `packages/xorder_waiter_link` | same | pass | 26 | 0 | 0 | n/m |
| Harness | `bash scripts/harness/verify.sh` | structure OK, doc checks list 419 problems | n/a | n/a | n/a | n/m |

POS totals: 3702 passed, 2 failed, 89 skipped. `n/m` = duration not measured.

The first POS attempt (`flutter test` at `apps/xorder-pos`) found no `test/` directory, because the POS is now a multi-package workspace; the numbers above come from running each package separately. Counts were taken from the Flutter JSON reporter and exclude hidden setup entries.

## Failures and triage
Both failures are in `apps/xorder_pos_waiter/test/waiter_flow_test.dart`. Each was rerun once alone with `--plain-name`, and both failed again, so both are deterministic.

| Test | Class | Likely cause | Evidence |
| --- | --- | --- | --- |
| address, name and PIN; a table, an item and a round — on a phone, in Arabic | deterministic, **environment** (host OS) | The test hard-codes the registered device name `mona · linux`; on this macOS host the app reports `mona · macos`. Expected `mona · linux`, actual `mona · macos`. Product behaviour looks right, the test is not portable. | `waiter_flow_test.dart:53` |
| a wrong PIN is worded; a revoked phone is told, then registers itself again | deterministic, **environment** (host OS) | Same hard-coded `linux` in the device name. | `waiter_flow_test.dart:236` |

Neither test was edited. UNVERIFIED: that they pass on a Linux host (the CI runner for the POS is Windows or Ubuntu, per `.github/workflows`).

## Baseline comparison
Baseline 2026-10-20: cloud 1024 passed / 4966 assertions; POS analyze clean, 2670 passed + 69 skipped.
- Deltas: cloud +276 tests and +1823 assertions. The previous cloud run of this release candidate was 1298, so the net effect of this session's work is +2 tests (3 new `StaleLiveViewCapabilityTest` cases plus 1 more, minus the 2 removed `RemoveLiveViewMigrationTest` cases). `flutter analyze` is still clean. The POS baseline of 2670 passed matches `shared_module` exactly; `shared_module` skips went from 69 to 79 (+10 newly skipped, cause not investigated), and the other four packages are not in the baseline.
- Regressions: none found in the cloud suite, the Vue build or `flutter analyze`. The 2 waiter failures are host-OS dependent and are not counted as regressions, though they cannot be compared with the baseline because the baseline predates those packages.

## Not run
- POS PostgreSQL suites (`pg` scope, `scripts/check.sh`): need consent and a local PostgreSQL; not requested.
- POS `integration_test/`: needs a desktop device and a database; not requested.
- Any test on Windows or Linux hosts.
- PostgreSQL-specific behaviour of cloud code and migrations (the cloud suite runs on SQLite only).
- Cloud production behaviour; no migration was run anywhere.

## Harness result
Structure OK (7 skills, 12 agents). The doc check lists **419 problems**: 412 are "missing file" references and 7 are line ranges outside the file. The missing files are POS paths written as `lib/...` (for example `lib/data/cloud/bootstrap_seeder.dart`, `lib/domain/models/permissions.dart`) that now live under `apps/xorder_pos_*/lib` and `packages/*/lib` after the POS was split into packages. Most are in `docs/features/pos-shifts/FEATURE.md` (98), `docs/FEATURE_INVENTORY.md` (36), `pos-business-day` (23), `tax-rules` (22) and `tenant-roles` (16). Several feature folders are also missing required files (for example `customers`, `back-office-navigation`). These are stale documentation, not code failures. There is no baseline for this count.

## Coverage gaps (indicative; no coverage tool configured)
- The Vue apps (`web`, `landing`, `menu`) have **no tests at all**: 0 test files. The build is the only automated check.
- Cloud route groups were not matched against feature test names in this run.
- POS PostgreSQL and offline-sync paths are covered only when the `pg` run is done, which was not done here.
- Cloud migrations are exercised on SQLite only, so Postgres lock, index and constraint behaviour is unverified.
- No coverage tool is configured; no coverage percentages are claimed.

## Risks and next actions
- The two waiter tests fail on macOS only because of a hard-coded `linux` device name. Make the tests read `Platform.operatingSystem`, or run them on Linux, then confirm. Needs approval because it edits test code.
- Decide whether to refresh the POS paths in the knowledge docs (`/project-documentation update`), which would clear most of the 412 harness problems.
- Investigate why `shared_module` skips rose from 69 to 79.
- Run the `pg` scope before any POS release (needs a local PostgreSQL and your consent).
- Cloud work in this branch is not committed; the report reflects the uncommitted tree.
