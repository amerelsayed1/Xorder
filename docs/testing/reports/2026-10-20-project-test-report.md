# Project test report

## Date, scope and environment
- Date / time: 2026-10-20 ~06:00 EEST
- Scope: `all` (cloud + pos + harness). `build` and `pg` were not requested.
- Repos:
  - `apps/xorder-cloud` @ main `06bc8e3` "fix(licences): renewal says when the new term starts (audit S2-3)" (uncommitted changes: **yes** — 10 files, all docs/coordination/agent/script: `.claude/agents/xorder-cloud.md`, `CO-HOST-PREP.md`, `docs/RESEARCH_RBAC_AND_POS.md`, `docs/backend/01-…`, `docs/backend/CB-09-…`, `docs/coordination/{BACKEND_TO_POS,BACKOFFICE_TO_CLOUD,POS_TO_BACKEND,REVISION_ORDER_ITEM_ID}.md`, `scripts/sync-coordination.sh`; no PHP/Vue product code)
  - `apps/xorder-pos` @ main `d592db8` "fix(pos): the shift label follows the till's language, and 0% lines are not printed (audit S4-2)" (uncommitted changes: **yes** — 11 files: `CLAUDE.md`, 6 docs files, `scripts/sync-coordination.sh`, and two Dart files: `lib/features/admin/presentation/management_screen.dart`, `test/features/cloud_purchasing_hidden_test.dart`). These were included in what was tested.
- Tool versions: PHP 8.3.19 · Composer 2.8.8 · Node v23.11.0 · pnpm 9.15.9 · Flutter 3.47.7 (stable, rev abaf9c5237) · Dart 3.13.5
- Database used: SQLite `:memory:` (cloud, confirmed in `apps/xorder-cloud/apps/api/phpunit.xml:26,29`). POS run with `POS_PG_HOST` unset: no database. `.env*` files were not read.

## Summary
| Suite | Command | Result | Passed | Failed | Skipped | Duration |
| --- | --- | --- | --- | --- | --- | --- |
| Cloud API | `cd apps/xorder-cloud/apps/api && php artisan test` | PASS | 1024 (4966 assertions) | 0 | 0 | 36 s (38 s wall) |
| POS static analysis | `cd apps/xorder-pos && flutter analyze` | PASS ("No issues found!") | n/a | 0 issues | n/a | 5.5 s (8 s wall, includes an implicit `pub get`) |
| POS unit + widget | `cd apps/xorder-pos && env -u POS_PG_HOST flutter test --reporter expanded` | PASS | 2670 | 0 | 69 | 2 m 24 s |
| Harness | `bash scripts/harness/verify.sh` | PASS ("Harness structure OK", "Feature documentation structure OK"; 18 skills, 12 agents) | n/a | 0 | n/a | not timed |

## Failures and triage
None. No test failed, so no reruns or classification were needed. No flaky or environment-related failures were observed.

## Baseline comparison
Baseline 2026-10-20: cloud 1024 passed / 4966 assertions; POS analyze clean, 2670 passed + 69 skipped.
- Deltas: **none**. Cloud 1024 / 4966, POS 2670 passed / 69 skipped and a clean analyze are identical to the baseline. No tests were added, removed or newly skipped.
- Regressions: none.
- Note: the 69 POS skips are the `integration`-tagged suites that skip without a database. The skip output names files under `test/data/` (for example `branch_pricing_test.dart`, `cloud_refunds_test.dart`, `backup_restore_test.dart`); I did not map every skip to a reason beyond that.
- Note: the working trees were not clean (see above), unlike the baseline's "clean trees". Counts still match exactly, so the uncommitted `management_screen.dart` / `cloud_purchasing_hidden_test.dart` edits did not change the pass/skip totals.

## Not run
- Vue build (`pnpm build`) — scope `build` not requested; the Vue apps (`apps/web`, `apps/landing`, `apps/menu`) were therefore not exercised at all in this run.
- POS PostgreSQL suites (`scripts/check.sh`) — scope `pg` not requested and requires the user's consent (creates and drops throwaway databases/roles on a local PostgreSQL).
- POS `integration_test/` — needs a desktop device and a database; not run by default.
- Any PostgreSQL run of the cloud suite — the cloud tests only run on SQLite.
- Migrations, `migrate:*`, deploy/release scripts: never run.

## Coverage gaps (indicative; no coverage tool configured)
- **Vue apps** (`apps/web`, `apps/landing`, `apps/menu`): no unit, E2E or lint scripts exist; the only automated check is `pnpm build`, which was not run here.
- **Cloud migrations on PostgreSQL**: 1024 tests run on SQLite `:memory:`, so locks, indexes, constraints and PostgreSQL-specific SQL are not proven. They must be reviewed by reading.
- **POS PostgreSQL and sync paths**: the 69 skipped tests (`test/data/*`, e.g. refunds, tenders, business-day, ETA queue, backup/restore, branch sales) exercise the database layer and only run with the `pg` scope.
- **Cloud routes vs. tests (name-level check only)**: `tests/Feature/` has ~79 entries plus `Admin/` and `Pos/` subfolders. The capability groups in `routes/api.php` (menu, tables, staff, branches, orders, analytics, audit, leads, landing, plans, subscriptions, pos_fleet/pos.provision, reviews, customers) each have an apparently related test file by name. I did not map routes to tests one by one, so per-endpoint gaps are unknown. Possible weaker spots by name only: `reviews.view` (only `InternalReviewTest`), `settings.view`, `platform_users.manage` (`Admin/PlatformUserTest` exists). Treat this as a lead, not a finding.
- No code-coverage numbers are available; none were invented.

## Risks and next actions
- All automated suites that were run are green and identical to the baseline; no regressions.
- Both repos have uncommitted changes (including two POS Dart files). Commit status is the owner's call; this run made no commits, pushes or edits to product code.
- Residual risk is in what the green run cannot see: Vue apps, PostgreSQL behavior for cloud migrations, and POS DB-backed suites.
- Suggested next actions: run `/project-testing build` to cover the Vue build, and `/project-testing pg` (needs your consent for local throwaway PostgreSQL databases) to run the 69 skipped POS DB-backed tests. Run `/release-check` before any push to `xorder-cloud` `main`.
