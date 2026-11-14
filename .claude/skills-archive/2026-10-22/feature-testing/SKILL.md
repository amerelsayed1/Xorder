---
name: feature-testing
description: Design, write, execute and report targeted automated and manual tests.
argument-hint: "<feature slug>"
---

# Feature Testing

Input: `$ARGUMENTS`.

## Procedure
1. `/project-documentation context <slug> test`: read the acceptance criteria, business rules, edge cases and existing-tests table in `docs/features/<slug>/FEATURE.md`, plus `WORKFLOWS.md` and cross-application dependencies. Build the matrix in `TEST_PLAN.md` (criterion → test), derive unit, integration, API and UI scenarios from the rules and edge cases, include cross-application behavior (POS↔cloud contract, idempotency, sync), and list criteria with no test as coverage gaps. Verify the documented behavior in source before encoding it in a test; if source and docs disagree, report it. Cover happy path, validation, authz, **tenant boundary**, retries/idempotency, concurrency and regressions (`.claude/rules/testing.md`); locale and offline behavior only where applicable.
2. Use existing frameworks and fixtures only:
   - Cloud API: PHPUnit 12 in `apps/xorder-cloud/apps/api/tests/{Feature,Unit}`. `phpunit.xml` forces SQLite `:memory:`. Run `cd apps/xorder-cloud/apps/api && php artisan test --filter <Name>`. PostgreSQL-specific behavior is NOT exercised by this suite — flag it.
   - Vue: no unit/E2E framework is configured. Do not install one without approval; propose manual steps and API-level tests instead.
   - Flutter: `flutter test <path>`. PostgreSQL-backed suites need `POS_PG_*` and a local server (`apps/xorder-pos/scripts/check.sh`); they self-skip otherwise — report skips as **not run**.
3. Write new tests next to similar ones; never touch real databases, `.env*` files, or production.
4. Execute and keep the **exact command and real output** (pass/fail/skip counts, failure messages). Compare against the baseline to identify regressions.
5. Fill `TEST_REPORT.md` with date, environment (tool versions), commands, results, redacted evidence and gaps. Planned tests live in `TEST_PLAN.md`, executed results only in `TEST_REPORT.md`; never mix them, and never write "passed" for anything not run.
6. Use `test-engineer` for execution and triage on larger suites.

## Required output
Report scope, verified file paths, assumptions/unknowns, changed files (if any), exact tests run with outcomes, risks and next action. Follow workspace `CLAUDE.md` approval rules.
