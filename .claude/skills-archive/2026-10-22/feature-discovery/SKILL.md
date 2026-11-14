---
name: feature-discovery
description: Discover and document existing Xorder behavior and code paths.
argument-hint: "<feature or area>"
---

# Feature Discovery

Read-only. Input: `$ARGUMENTS`.

## Procedure
1. Read `CLAUDE.md`, `docs/architecture/repo-map.md`, the target repo's own `CLAUDE.md`, and look the feature up in `docs/FEATURE_INVENTORY.md` (`grep -n -i`); open its `docs/features/<slug>/` only through `/project-documentation context <slug> plan`. Use the inventory's entry points and evidence list as the starting trace, then verify them. Treat repo code, migrations and tests as truth over prose docs (the repo CLAUDE.md files themselves say some README/ARCHITECTURE text is stale, e.g. Sanctum vs JWT).
2. Trace the feature end to end with Grep/Glob (use `feature-analyst` for broad sweeps):
   - Cloud: `apps/api/routes/*.php` → middleware stack → controller → `Requests/` → `Services/` → `Models/` and migrations → `Resources/`. Vue: `apps/*/src/{router,pages,stores,components}`, `packages/api-client`.
   - POS: `lib/features/<area>` → `lib/app/providers.dart` → `lib/domain/{services,repositories}` → `lib/data/{postgres,cloud}`.
   - Contract: `docs/coordination/*.md` (`POS-BE-xxx`, `CB-xx` IDs and READY/APPROVED/PROPOSED status) in both repos.
3. Collect the tests that cover it (cloud `apps/api/tests/{Feature,Unit}`; POS `test/`, `integration_test/`).
4. Record: actors/permissions, business rules, endpoints (method/path from route files only), tables/columns from migrations, tenant/money/order invariants, failure modes, unknowns.
5. Write findings to `docs/features/<slug>/` via `/feature-documentation` (or `/project-documentation feature <slug>` when the inventory should be updated too), or report inline if asked not to write. For a whole-system map, update `docs/architecture/repo-map.md` with verified paths only.

## Rules
Every claim carries a `path:line` or test reference; otherwise mark **UNVERIFIED**. Never read `.env*`, key files, the backups folder, or customer data. Do not modify application code.

## Required output
Report scope, verified file paths, assumptions/unknowns, changed files (if any), exact tests run with outcomes, risks and next action. Follow workspace `CLAUDE.md` approval rules.
