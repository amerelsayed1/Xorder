---
name: feature-documentation
description: Generate or update feature documentation from requirements and verified source.
argument-hint: "<feature slug>"
---

# Feature Documentation

Input: `$ARGUMENTS` (kebab-case slug).

## Procedure
1. Determine existing vs proposed feature. Check `docs/features/<slug>/`; **never overwrite** existing docs — merge, preserving human content and decision history.
2. Create the seven files from `docs/templates/` — `FEATURE.md`, `TECHNICAL.md`, `API.md`, `DATABASE.md`, `TEST_PLAN.md`, `TEST_REPORT.md`, `CHANGELOG.md` — keeping the template headings. For existing, shared features prefer the richer superset templates in `.claude/skills/project-documentation/templates/` (same headings in the same order, plus cross-application, security and workflow sections).
3. For existing behavior fill from verified source (`/feature-discovery` output); label proposed behavior as proposed.
   - FEATURE: business rules and numbered, testable **acceptance criteria** (`AC-1`, `AC-2`…), actors/permissions, cloud vs POS flows, unknowns.
   - API: method/path from route files, auth + capability middleware, request/response shapes (redacted), error format, POS contract IDs with their READY/APPROVED/PROPOSED status, backward-compatibility notes.
   - DATABASE: tables/columns/constraints from actual migrations, tenant column, transactions, index needs, rollback plan. Production is PostgreSQL; cloud tests run on SQLite — note Postgres-only behavior.
   - TEST_PLAN: map every acceptance criterion to a test (existing file or planned).
   - TEST_REPORT: leave "not run" until `/feature-testing` fills it with real output.
4. Mark anything not confirmed in source as **UNVERIFIED**; link evidence as `path:line`. Do not write invented contracts.
5. Run `python3 scripts/harness/check-docs.py` (all seven files present for every feature).
6. Register the feature in `docs/FEATURE_INVENTORY.md` (summary row and block: module, entry points, evidence files, contracts, tables, tests, source revision `git log --oneline -1` per repo, verification status `drafted`) and in `docs/DOCUMENTATION_PROGRESS.md`. Never set `validated` here; only `/project-documentation validate` does.

## Update rule
Whenever implementation changes behavior, update FEATURE/API/DATABASE/TECHNICAL and append to CHANGELOG in the same task. Docs describe as-built behavior, not intent.

## Never include
Secrets, tokens, real customer/PII data, payment details, backup contents.

## Required output
Report scope, verified file paths, assumptions/unknowns, changed files (if any), exact tests run with outcomes, risks and next action. Follow workspace `CLAUDE.md` approval rules.
