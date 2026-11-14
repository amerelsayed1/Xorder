---
name: feature-review
description: Independently review implementation against feature requirements and engineering risks.
argument-hint: "<feature slug>"
---

# Feature Review

Read-only. Input: `$ARGUMENTS`. Use a separate review pass or a fresh `code-reviewer` agent so the review is not anchored on the implementer's reasoning; add `security-reviewer` when auth, tenancy, money or orders are touched and `database-reviewer` when schema changes.

## Checklist
0. **Load knowledge**: `/project-documentation context <slug> review` (rules, ACs, API compatibility, DB constraints, security section). Documentation is a lead; check it against the diff and source.
1. **Acceptance criteria and business rules**: map each `AC-n` and `BR-n` to code and passing test evidence; list the unmet ones and any documented rule the change breaks without an approved requirement.
2. **Correctness/regressions**: read the diff per repo (`git -C <repo> diff`), cite `path:line`.
3. **Security**: server-side authz and tenant ownership on every resource, no client-trusted totals, no secrets/PII in logs or docs, input validation, idempotency on order/payment endpoints.
4. **Data**: migration safety (additive, lock/backfill cost, rollback, constraints, indexes); PostgreSQL vs SQLite differences.
5. **Contracts**: no silent response-shape changes; Laravel↔Flutter (and Vue) compatibility against `API.md` and the READY contract items; coordination doc status updated.
6. **Performance/maintainability**: N+1 queries, unbounded lists, duplicated logic, convention drift.
7. **Tests and docs**: missing tests and regression coverage, stale or incomplete docs, TEST_REPORT truthfulness.
8. **Documentation consistency**: list every place docs contradict the code or the change (wrong rule, missing endpoint/column, stale source revision, UNVERIFIED item now resolvable) as findings with `path:line` in both; do not fix them in the review step; recommend `/project-documentation update <slug>`.

Findings (code defects and documentation inconsistencies) are ranked by severity with `path:line`. Do not label ready while blocking issues remain. Do not fix code in the review step.

## Required output
Report scope, verified file paths, assumptions/unknowns, changed files (if any), exact tests run with outcomes, risks and next action. Follow workspace `CLAUDE.md` approval rules.
