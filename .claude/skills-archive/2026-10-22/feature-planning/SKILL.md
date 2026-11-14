---
name: feature-planning
description: Produce a staged feature implementation plan with risk and test coverage.
argument-hint: "<feature slug>"
---

# Feature Planning

No application edits. Input: `$ARGUMENTS`.

## Procedure
1. **Find the relevant documentation.** `/project-documentation context <slug or query> plan`: locate the feature in `docs/FEATURE_INVENTORY.md`, read its acceptance criteria, business rules, known limitations and cross-application dependencies (only those sections) and the discovery evidence. Stop and ask if criteria are missing or unclear; for a new feature draft them with `/feature-documentation`, labelled proposed.
2. **Identify existing behavior and verify it.** Re-read the source behind the load-bearing documented rules, endpoints, schema and permissions; documentation is a lead, not authority. Record discrepancies.
3. **Reuse.** List existing services, components, endpoints, patterns and related features (from the inventory's source references and neighbouring code) that the change should reuse or must not regress.
4. **Close documentation gaps.** If documentation is missing or stale on the task's path, run `/project-documentation feature <slug>` (or `update <slug>`) before relying on it; list what remains UNVERIFIED in the plan.
5. Write an **impact analysis** (include cross-application dependencies: which app consumes or produces each contract, shared entities, sync behavior): files/modules per repo, API shape changes, schema changes, tenant-isolation and money/order-state impact, POS offline/outbox impact, deploy ordering.
6. Produce stages, each with: repos/paths, change, tests that prove it, rollback. Order: backend contract first, additive schema first, consumers after producers. Cloud and POS deploy independently, so any contract change needs a compatibility window and rollout plan (see `/api-contracts`).
7. List approval gates: migrations, payment/order-state changes, contract changes, and anything that reaches `xorder-cloud` `main` (auto-deploys to production and migrates the live database).
8. Name the exact verification commands per repo:
   - Cloud: `cd apps/xorder-cloud/apps/api && php artisan test [--filter X]` (SQLite in-memory).
   - POS: `cd apps/xorder-pos && flutter analyze && flutter test [path]`; `scripts/check.sh` for PostgreSQL-backed suites.
   - Vue: `cd apps/xorder-cloud && pnpm build` (no JS test framework exists — say so and plan other verification).
9. Save the plan in `docs/features/<slug>/TECHNICAL.md` and surface open questions. The plan is not approved until the user says so; implementation must not start earlier. Use `implementation-planner` for large cross-repo work.

## Required output
Report scope, verified file paths, assumptions/unknowns, changed files (if any), exact tests run with outcomes, risks and next action. Follow workspace `CLAUDE.md` approval rules.
