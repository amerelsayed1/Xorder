---
name: refactoring
description: Improve internal structure without intended behavior changes.
argument-hint: "<area and goal>"
---

# Refactoring

Knowledge: before significant changes follow `.claude/rules/knowledge.md` (`/project-documentation context <feature> <phase>`); verify critical behavior in current source, and report missing or stale docs.

## Procedure
1. Establish the baseline first: run the relevant tests and record the exact output (cloud `php artisan test`; POS `flutter analyze && flutter test`). If the area has no tests, add characterization tests before changing anything.
2. Make small, reversible steps. Preserve the public contract: API routes and response shapes (POS depends on them; deploys are independent), database schema, `TicketEngine` money behavior (integer minor units, half-up rounding), tenant scoping and permission gates.
3. Follow the neighbouring conventions of the repo (Laravel controller→request→service→resource layering; POS domain/data/features layering and the `lib/app/providers.dart` seam). No unrelated formatting churn; no new tooling without approval.
4. Re-run the same tests after each step and compare with the baseline; any difference is a regression to explain or revert.
5. Document residual risk and update `docs/features/<slug>/TECHNICAL.md` if module boundaries moved.

## Required output
Report scope, verified file paths, assumptions/unknowns, changed files (if any), exact tests run with outcomes, risks and next action. Follow workspace `CLAUDE.md` approval rules.
