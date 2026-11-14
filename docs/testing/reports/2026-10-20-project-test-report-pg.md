# Project test report — `pg` scope (POS PostgreSQL suites)

Supplements `2026-10-20-project-test-report.md` (scope `all`) and `2026-10-20-project-test-report-build.md` (scope `build`). Only `apps/xorder-pos/scripts/check.sh` was run in this pass. The cloud API, Vue build and harness were **not re-run** here.

## Date, scope and environment
- Date / time: 2026-10-20, run started ~07:40 EEST (script duration 485 s)
- Scope: `pg` — run with the user's explicit consent given in chat.
- Repo: `apps/xorder-pos` @ main `d592db8` (uncommitted changes: yes — same 11 files as the earlier report, including `lib/features/admin/presentation/management_screen.dart` and `test/features/cloud_purchasing_hidden_test.dart`). They were included in what was tested. Only that repo was exercised.
- Tool versions: Flutter 3.47.7 · Dart 3.13.5 · pg_dump 16.11 (Homebrew, matched to the server by the script)
- Database used: local PostgreSQL 16 at `127.0.0.1:5432` (`pg_isready`: accepting connections). `POS_PG_*` environment variables were unset, so the script's localhost defaults applied (host `127.0.0.1`, port `5432`, user = login user). Credentials were not printed or recorded. No remote or production host was involved.

## Summary
| Suite | Command | Result | Passed | Failed | Skipped | Duration |
| --- | --- | --- | --- | --- | --- | --- |
| POS PostgreSQL + full check | `cd apps/xorder-pos && scripts/check.sh` (runs `flutter pub get`, `flutter analyze`, `flutter test`) | PASS (exit 0, "All checks passed.") | 3739 | 0 | 1 | 485 s total |
| of which: `flutter analyze` | (inside check.sh) | PASS ("No issues found!") | n/a | 0 issues | n/a | 5.2 s |

## Failures and triage
None.

The one skip is a test in `test/data/postgres_wiring_test.dart`: "the wizard Test connection button, against a real database a wrong password is reported as a password problem, not a network one". The test's own message says the role (`POS_PG_USER`) authenticates with `trust`, so no password can be wrong; it needs a scram-authenticated role to run. **Environment skip**, not a defect. This means the wrong-password reporting path was not exercised against a real server.

## Baseline comparison
The baseline (2026-10-20) only covers the no-database run: 2670 passed / 69 skipped. With a database, the suite is larger.
- Deltas: 3739 passed vs. 2670 → **+1069 tests that the no-database run skips**, including the DB-backed suites under `test/data/`. Skips fell from 69 to 1. These are not new tests; they are the previously skipped DB-backed ones now running. The earlier report's gap "69 skipped tests only run with `pg`" is closed, except for the one skip above. I did not itemize how the +1069 divides among suites. 2670 + 69 = 2739; 3739 − 2739 = 1000 exactly, so the DB-run total is 1000 more than the no-DB total.
- Regressions: none.
- Side effects: `git status --short` for `apps/xorder-pos` shows only the same 11 pre-existing modified files, so `pub get` did not change tracked files. A check of `pg_database` on the local server found no leftover throwaway databases (only the `postgres` database matched `pos%`/`%test%`). Test roles were not separately listed.

## Not run
- Cloud API, Vue build, harness — not re-run in this pass (earlier reports: all green).
- POS `integration_test/` — needs a desktop device; not run (not part of `scripts/check.sh`).
- Any PostgreSQL-backed run of the **cloud** suite — cloud tests still run only on SQLite.
- The wrong-password test above (needs a scram-authenticated role).

## Coverage gaps (indicative; no coverage tool configured)
- The POS database layer is now exercised on local PostgreSQL 16. Other server versions, a server that requires password authentication (scram), and production-like latency/locks are not covered.
- POS↔cloud sync behavior over the network is not covered by this run.
- Unchanged from earlier reports: Vue apps have no automated tests (only a build), and cloud migrations are untested on PostgreSQL.

## Risks and next actions
- All three POS checks (analyze, no-DB tests, DB-backed tests) are green. No new risk found.
- Optional: re-run with `POS_PG_USER` set to a scram-authenticated role to cover the skipped wrong-password test (needs your decision on which role to use; I did not set one).
- Both repos still have uncommitted changes; no commits or pushes were made. Run `/release-check` before any push to `xorder-cloud` `main`.
