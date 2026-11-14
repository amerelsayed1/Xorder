---
name: implement
description: Implement an approved description or a confirmed root cause: plan, wait for approval, build in small stages, test, review, and update the docs. Takes the output of /develop-feature (docs/features/<slug>/FEATURE.md) or /bug-investigation (a root-cause report), or an XORD-nnn, or "refactor <area>". Testing is mandatory for every change. Use whenever the user says to implement, build, fix, make the change, "go" on a plan, or run one phase (plan, implement, test, review, ready), in the cloud API, the Vue apps or the POS.
argument-hint: "<slug | report path | XORD-nnn>  |  plan|implement|test|review|ready <target>  |  refactor <area>"
---

# Implement

Input: `$ARGUMENTS`. If the first word is a phase name, run only that phase; if it is `refactor`, follow *Refactor mode*; otherwise run the whole flow below. Run from the workspace root so `CLAUDE.md` and `.claude/rules/` apply; the stack rules in `.claude/rules/{cloud-laravel-vue,pos-flutter,postgres-migrations,api-contracts,licences}.md` load by path.

**The input is the specification.** A feature comes from `docs/features/<slug>/FEATURE.md` (written by `/develop-feature`); a fix comes from a root-cause report in `docs/harness/investigations/` (written by `/bug-investigation`). If neither exists, or its acceptance criteria are missing or unclear, stop and say which command to run first; do not invent the specification here.

## The rules that always apply
1. **Testing is mandatory for every change**, feature, fix or refactor: new or updated tests that cover what changed, run, with the real output reported. Not test-first: write them in the order that suits the work. A change is not done without a test that was run. What a test cannot prove (a screen, a printer, PostgreSQL-only behavior on the SQLite suite) is said out loud, with the closest test added and the rest listed for a person.
2. **Approval before building.** The plan is shown and the user says go. Mandatory for migrations, payment or order-state changes, contract changes, permission changes that narrow access, and anything reaching `xorder-cloud` `main` (a push there deploys to production).
3. **Never** commit, push, merge, tag, deploy, run a migration on a real database, or read `db-backups/`, without explicit approval. Migrations are additive and written, not run.
4. **Minimal diffs.** Follow neighbouring patterns; no unrelated refactors or formatting; preserve documented rules (`BR-n`) unless the specification changes them. The server owns prices, tax, totals, permissions and order transitions.
5. **Check the tree first.** `git -C <repo> status --short` for every repo you will touch. Report unrelated dirty files, never revert them, and say when your edits will be mixed with uncommitted work.
6. **Tracker.** For an `XORD-nnn`, tick a box in `docs/qa/XORDER_QA_FINDINGS.md` only for a criterion an automated test that was run proves, with that test named beside the tick; update the status and section 8; number new findings from the next free `XORD-nnn`.
7. **Say what was not done.** Report in `.claude/rules/reporting.md` format: scope, files, exact commands and real output, what was deliberately not done, risks, next action.

## Flow
Load the specification → `/project-documentation context <slug> implement` (freshness, contracts, regressions to protect) → **plan** → **approval** → **implement** → **test** → **review** (fix blockers, re-test, re-review the change) → `/project-documentation update <slug>` (then `validate <slug>` against the final source) → `bash scripts/harness/verify.sh` → **ready** when shipping is the question.

## Phase: plan (no application edits)
1. Re-read the code behind the load-bearing claims in the specification (rules, endpoints, schema, permissions, tenant scope) and record any discrepancy. For a fix, confirm the root cause still holds on the current tree.
2. **Reuse:** the existing services, components, endpoints and related features to reuse or not regress.
3. **Impact:** files and modules per repo, API shape, schema, tenant isolation, money and order-state, POS offline and outbox, which app produces and consumes each contract, deploy order. Cloud and POS deploy independently: a contract change needs a compatibility window and a written rollout order (`api-contracts.md`).
4. **Domain lens:** which venue models the change serves or breaks (`docs/domain/FOOD_SERVICE_DOMAIN.md` section 6).
5. **Stages**, each with the repo and paths, the change, the tests that prove it, and the rollback. Order: backend contract first, additive schema first, consumers after producers.
6. **Verification commands:** cloud `cd apps/xorder-cloud/apps/api && php artisan test [--filter X]`; POS `cd apps/xorder-pos && flutter analyze && flutter test [path]` (`scripts/check.sh` for the PostgreSQL suites); Vue `cd apps/xorder-cloud && pnpm build` (there is no JS test framework; say so).
7. Save the plan in `docs/features/<slug>/TECHNICAL.md` and list the approvals needed and the open questions. **Wait.** Not approved until the user says so.

## Phase: implement
Preconditions: an approved plan and acceptance criteria.
1. Re-inspect the code you will touch; list regressions and compatibility impacts (other features, the other app, old clients) before the first edit.
2. Build stage by stage. After each stage run the plan's targeted tests and fix regressions before continuing.
3. Add or update the tests for the stage (rule 1) in the same stage, next to the tests of similar code.
4. Edit the docs the change makes wrong (`/project-documentation update <slug>`: FEATURE, TECHNICAL, API, DATABASE, CHANGELOG), recording the actual behavior and the source revision.
Read-only helper agents (`backend-engineer`, `frontend-engineer`, `flutter-engineer`) return findings and proposed diffs; the main session makes the edits.

## Phase: test
1. `/project-documentation context <slug> test`: acceptance criteria, rules, edge cases, existing tests, cross-application dependencies. Build the matrix in `TEST_PLAN.md` (criterion → test) and list criteria with no test as gaps. Verify documented behavior in source before encoding it in a test.
2. Cover the happy path, validation, authorization, **tenant boundary**, retries and idempotency, concurrency and regressions (`.claude/rules/testing.md`), plus locale (Arabic and English, RTL, digits) and offline behavior where they apply.
3. Existing frameworks only. Cloud: PHPUnit in `apps/api/tests/{Feature,Unit}` on SQLite `:memory:` (PostgreSQL-only behavior is not exercised; flag it). Vue: no test framework; do not install one without approval; propose manual steps and API-level tests. Flutter: `flutter test <path>`; PostgreSQL-backed suites need `POS_PG_*` and self-skip otherwise, reported as **not run**. Never touch real databases, `.env*` or production.
4. Run the targeted tests, then the repo's full suite, and compare with the baseline in `/project-testing`. A first run that overlaps edits from another session is not a result: re-run it and say so.
5. Fill `TEST_REPORT.md` (date, environment, exact commands, results, gaps). Planned tests live in `TEST_PLAN.md`, executed results only in `TEST_REPORT.md`. Use `test-engineer` for larger suites.

## Phase: review (read-only)
A separate pass, or a fresh `code-reviewer`, so the review is not anchored on the implementer's reasoning; add `security-reviewer` for auth, tenancy, money or orders and `database-reviewer` for schema.
1. Map each `AC-n` and `BR-n` to code and to a passing test; list the unmet ones and any documented rule broken without an approved requirement.
2. Correctness and regressions from `git -C <repo> diff`, cited `path:line`.
3. Security: server-side authorization and tenant ownership on every resource, no client-trusted totals, no secrets or PII in logs or docs, input validation, idempotency on order and payment endpoints.
4. Data: migration safety (additive, lock and backfill cost, rollback, constraints, indexes); PostgreSQL versus SQLite differences.
5. Contracts: no silent response-shape change; Laravel ↔ Flutter ↔ Vue compatibility against `API.md` and READY items.
6. Domain fit: would it work for a restaurant but break a café queue, an offline food truck, or a cloud kitchen with no tables?
7. Tests and docs: missing regression coverage, stale docs, a `TEST_REPORT` that overstates; list each documentation contradiction with `path:line`.
Findings ranked by severity. Do not call it ready while blockers remain; do not fix code in the review step.

## Phase: ready (read-only; never deploy, push, tag or migrate)
1. What ships per repo: `git -C <repo> log --oneline` and `diff` against the release base.
2. Cloud: run `/release-check` and carry its verdict. New migrations are additive and reviewed under `postgres-migrations.md`.
3. POS: a release is a green `scripts/check.sh` (analyze and all tests including PostgreSQL), then a tag, then the manual Windows installer workflow. Report whether `check.sh` actually ran; unit-only runs leave the PostgreSQL-tagged tests skipped.
4. Compatibility: contract IDs touched and their status in `docs/coordination/`; rollout order (normally cloud first, additive); old POS against new server and the reverse.
5. Docs: `/project-documentation status` shows nothing `stale` for the shipped features; `validate <slug>` ran on the final source; the changelog is current.
6. Go or no-go, with unresolved risks, the rollback strategy and what could not be verified.

## Refactor mode (no intended behavior change)
1. Baseline first: run the relevant tests and record the exact output (cloud `php artisan test`; POS `flutter analyze && flutter test`). No tests in the area → add characterization tests before changing anything.
2. Small, reversible steps. Preserve the public contract: API routes and response shapes (the POS depends on them and deploys independently), schema, `TicketEngine` money behavior, tenant scoping and permission gates.
3. Follow the neighbouring conventions; no unrelated formatting churn; no new tooling without approval.
4. Re-run the same tests after each step and compare with the baseline; any difference is a regression to explain or revert.
5. Document residual risk; update `docs/features/<slug>/TECHNICAL.md` if module boundaries moved.

## Routing (use only what the task needs; never all agents)
| Affected | Conventions | Helpers (read-only) |
|---|---|---|
| Laravel API and business rules | `cloud-laravel-vue.md` | `backend-engineer`, `database-reviewer` if schema |
| Vue SPAs | `cloud-laravel-vue.md` | `frontend-engineer` |
| Flutter POS | `pos-flutter.md` | `flutter-engineer` |
| Schema and SQL | `postgres-migrations.md` | `database-reviewer` |
| POS ↔ cloud contract | `api-contracts.md` | `feature-analyst` on both sides |
| Auth, tenancy, money, orders | `/security-audit` | `security-reviewer` |
| Pre-ship | phase `ready`; in `xorder-cloud` also `/release-check` | `code-reviewer` |
Independent helpers may run in parallel.
