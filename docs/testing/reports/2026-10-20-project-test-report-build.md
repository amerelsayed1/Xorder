# Project test report — `build` scope (Vue apps)

Supplements `2026-10-20-project-test-report.md` (scope `all`, same day). Only the Vue build was run in this pass; the cloud API, POS and harness results are in that earlier report and were **not re-run** here.

## Date, scope and environment
- Date / time: 2026-10-20, shortly after the `all` run (~06:10 EEST)
- Scope: `build` (adds `pnpm build` of the Vue apps)
- Repos: `apps/xorder-cloud` @ main `06bc8e3` (uncommitted changes: yes — 10 docs/coordination/agent/script files, no Vue or PHP product code, same as the earlier report) · `apps/xorder-pos` not touched in this pass
- Tool versions: Node v23.11.0 · pnpm 9.15.9 · Vite 8.1.0 (as printed by the build)
- Database used: none

## Summary
| Suite | Command | Result | Passed | Failed | Skipped | Duration |
| --- | --- | --- | --- | --- | --- | --- |
| Vue build (web, landing, menu) | `cd apps/xorder-cloud && pnpm build` (`turbo run build`) | PASS (exit 0) | 3 of 3 turbo tasks successful | 0 | n/a | turbo 8.3 s (27 s wall, includes pnpm start-up); `@xorder/landing` 1.31 s, `@xorder/menu` 1.51 s, `@xorder/web` 2.71 s; 0 of 3 tasks cached |

"Passed" here means the production bundle compiled. This is not a test result: no unit, E2E or lint scripts exist for these apps.

## Failures and triage
None. All three apps built.

Warning (not a failure): `@xorder/web` prints "Some chunks are larger than 500 kB after minification". The chunks in the output above 500 kB are `index-BHPlmH4u.js` (617.80 kB, 166.61 kB gzip) and `apexcharts.esm-DEyjUNHV.js` (777.26 kB, 217.13 kB gzip). It is a Vite advisory about code-splitting, not a regression; I have no earlier build to compare with.

## Baseline comparison
The baseline (2026-10-20) has no Vue build figures, so there is nothing to compare against. This run becomes the first recorded Vue build result.
- Deltas: n/a
- Regressions: none known
- Side effects: `git -C apps/xorder-cloud status --short` was identical before and after the build (the `dist/` output is gitignored).

## Not run
- Cloud API, POS analyze/test and harness — not re-run in this pass (see the earlier report, all green).
- POS PostgreSQL suites (`scripts/check.sh`, scope `pg`) — needs your consent for local throwaway databases.
- POS `integration_test/` — needs a desktop device and a database.
- Vue unit/E2E/lint — no such scripts exist.

## Coverage gaps (indicative; no coverage tool configured)
- A successful build proves the Vue apps compile and bundle. It does not prove runtime behavior, routing, RTL/i18n rendering, capability gating or API contract compatibility of `apps/web`, `apps/landing` or `apps/menu`, since they have no automated tests.
- All other gaps are unchanged from the earlier report (PostgreSQL vs. SQLite for cloud migrations, POS DB-backed suites skipped without the `pg` scope).

## Risks and next actions
- No new risk found. Build output is gitignored and no tracked files changed.
- Consider a code-splitting pass or a deliberate `chunkSizeWarningLimit` for `@xorder/web` (apexcharts is the largest chunk). Optional; product code was not touched.
- Next: `/project-testing pg` if you consent to local throwaway PostgreSQL databases, and `/release-check` before any push to `xorder-cloud` `main`.
