---
name: feature-implementation
description: Implement an approved Xorder feature with coordinated cloud and desktop changes.
argument-hint: "<feature slug>"
---

# Feature Implementation

Input: `$ARGUMENTS`. Preconditions: documented acceptance criteria and an **approved** plan. If either is missing, stop and run `/feature-documentation` / `/feature-planning`.

## Procedure
1. Read the approved plan, then `/project-documentation context <slug> implement` (feature and architecture docs, only the needed sections; freshness verdict). Re-inspect the code you will touch and verify the APIs, database models and services it names; follow neighbouring patterns and the target repo's own `CLAUDE.md`. List regressions and compatibility impacts (other features, the other app, old clients) before the first edit.
2. Run `git -C <repo> status --short`. If the tree has unrelated changes, do not mix them in; tell the user.
3. Implement stage by stage with minimal diffs; no drive-by refactors. Preserve the documented business rules (`BR-n`) unless the approved requirements explicitly change them. Coordinate backend and POS changes in the order of the plan. Track each stage as completed in the task list as you go.
   - **Laravel** (`apps/xorder-cloud/apps/api`): thin controller → `Requests/` validation → `Services/` → `Resources/`. Tenant scoping through `RestaurantScope`/`BelongsToRestaurant`; never read `restaurant_id` from input; cross-tenant access is 404. Gate routes with `role:` + `feature:` + `can:` as neighbouring routes do. The server computes prices, tax and totals.
   - **Vue** (`apps/web|menu|landing`, `packages/*`): script-setup components, existing stores/router/api-client, AR/EN i18n with RTL, capability-gated UI.
   - **Flutter** (`xorder-pos`): money in integer minor units; rules in `TicketEngine`; UI depends only on `lib/domain/repositories` interfaces; implementations are chosen in `lib/app/providers.dart`; zero-radius, no-shadow design tokens.
   - **PostgreSQL**: additive, reversible migrations only (see `/postgres-management`). Write migration files but do **not** run them against any non-test database.
4. After each stage run the targeted tests from the plan; fix regressions before continuing.
5. Update knowledge: `/project-documentation update <slug>` so FEATURE/TECHNICAL/API/DATABASE/CHANGELOG record the actual behavior, implementation decisions, new source references and source revision. Do not mark documentation `validated` until `/project-documentation validate <slug>` has checked the final source.
6. No commit, push, merge or deploy without explicit approval.

Read-only helper agents (`backend-engineer`, `frontend-engineer`, `flutter-engineer`) return findings and proposed diffs; the main session performs the edits.

## Required output
Report scope, verified file paths, assumptions/unknowns, changed files (if any), exact tests run with outcomes, risks and next action. Follow workspace `CLAUDE.md` approval rules.
