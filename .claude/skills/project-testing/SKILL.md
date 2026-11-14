---
name: project-testing
description: Run and report the whole Xorder test suite across cloud API, Vue build and Flutter POS (not tied to one feature), compare with the baseline and list coverage gaps.
argument-hint: "[all | cloud | pos | build | pg]  (default: all)"
---

# Project Testing (whole project)

Full regression pass for the test engineer. Use `/implement test <slug>` instead when testing one feature. Scope from `$ARGUMENTS`:
`all` = cloud + pos + harness (default) · `cloud` · `pos` · `build` = also `pnpm build` of the Vue apps · `pg` = also the POS PostgreSQL suites (needs consent, see below).

Read-only on product code: this skill finds and reports problems, it does not fix them. Delegate execution and triage to the `test-engineer` agent when helpful (it has no Write; the main session writes the report).

## 1. Preflight
1. `git -C apps/xorder-cloud status --short` and `git -C apps/xorder-pos status --short`; record branch + HEAD (`git log --oneline -1`) and any uncommitted changes (they are part of what is being tested).
2. Record tool versions: `php -v`, `composer -V`, `node -v`, `pnpm -v`, `flutter --version`, `dart --version`.
3. Safety check before running cloud tests: `apps/xorder-cloud/apps/api/phpunit.xml` must still set `DB_CONNECTION=sqlite` and `DB_DATABASE=:memory:`. If not, stop. Do not read `.env*` files. Never run tests against production or a shared database.

## 2. Run (independent suites may run in parallel)
| Suite | Command | Notes |
|---|---|---|
| Cloud API | `cd apps/xorder-cloud/apps/api && php artisan test` | PHPUnit 12 on SQLite `:memory:`; PostgreSQL-only behavior is NOT covered |
| Vue build (`build` scope only) | `cd apps/xorder-cloud && pnpm build` | only automated check for `apps/web|landing|menu`; writes gitignored `dist/` output; no unit/E2E/lint scripts exist |
| POS static analysis | `cd apps/xorder-pos && flutter analyze` | must be clean |
| POS unit + widget | `cd apps/xorder-pos && env -u POS_PG_HOST flutter test` | `integration`-tagged suites skip without a database; count and report the skips |
| POS PostgreSQL suites (`pg` only) | `cd apps/xorder-pos && scripts/check.sh` | **Ask the user first.** It creates and drops throwaway databases/roles on a *local* PostgreSQL (defaults `127.0.0.1:5432`). Refuse any `POS_PG_HOST` that is not localhost |
| POS `integration_test/` | not run by default | needs a desktop device and a database; ask first |
| Harness | `bash scripts/harness/verify.sh` | structure/doc checks |

Never run: migrations, `migrate:*`, deploy/release scripts, installers, anything that writes outside the repos' ignored build directories.

## 3. Triage failures
For each failure re-run that single test once (`php artisan test --filter X` / `flutter test path -n "name"`) to classify: **deterministic failure**, **flaky** (passes on rerun), or **environment** (missing tool/service). Then give a likely cause: product bug, outdated test, or environment — with `path:line` evidence. Do not edit code or tests to make them pass.

## 4. Compare with baseline
Baseline recorded 2026-10-20 (clean trees): cloud **1024 passed / 4966 assertions**; POS `flutter analyze` clean, `flutter test` **2670 passed, 69 skipped**. Report deltas in test counts (new, removed, newly skipped) and any new failures as regressions.

## 5. Coverage gaps (indicative, say so)
List, without inventing numbers: cloud route groups in `routes/api.php` with no matching feature test name; the Vue apps (no tests at all); POS PostgreSQL/offline-sync paths only covered when the `pg` run is done; Postgres-vs-SQLite risk for cloud migrations. No coverage tool is configured; do not install one without approval.

## 6. Report
Write `docs/testing/reports/<YYYY-MM-DD>-project-test-report.md` from `docs/templates/PROJECT_TEST_REPORT.md` (create `docs/testing/reports/` if missing; never overwrite an existing report — add a time suffix). Include exact commands, real pass/fail/skip counts, durations, failing test names with trimmed output, triage, baseline delta, gaps and what was **not run**. Redact secrets/PII. Never write "passed" for anything not executed.

## Required output
Summary table (suite, command, result, counts), regressions, flaky/environment items, not-run items, risks and next action. Follow workspace `CLAUDE.md` approval rules; no commits or pushes.
