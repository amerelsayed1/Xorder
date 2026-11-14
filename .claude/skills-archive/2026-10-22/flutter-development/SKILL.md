---
name: flutter-development
description: Build Flutter desktop POS features according to current project conventions.
---

# Flutter Development

Knowledge: before significant changes follow `.claude/rules/knowledge.md` (`/project-documentation context <feature> <phase>`); verify critical behavior in current source, and report missing or stale docs.

## Procedure
Work in `xorder-pos` (Flutter 3.47, Dart ^3.13; Windows and macOS desktop). Read `apps/xorder-pos/CLAUDE.md` first; it overrides older README/docs prose.
- Layers: `lib/core` → `lib/domain` (plain Dart models, repository contracts, pure `ticket_engine.dart`) → `lib/data/{postgres,cloud,fakes,unconfigured}` → `lib/features/<area>`. UI depends only on `lib/domain/repositories`; implementations are bound in `lib/app/providers.dart` (Riverpod). Routing is go_router.
- **Money is integer minor units, half-up rounding at the tax line; never `double`.** All ticket/money rules live in `TicketEngine`, not widgets. Tax is provisional device config until contract `POS-BE-013` is wired.
- Design: border-radius 0, no shadows, tokens from `lib/core/ui/tokens.dart`; keyboard-first (cashier speed), Arabic/English.
- Offline-first: sync goes through the `pos_outbox` table and `lib/data/cloud/outbox_drain.dart`. Integrate only against contracts marked `READY` in `docs/coordination/BACKEND_TO_POS.md`; never assume a backend change is deployed.
- Verify: `cd apps/xorder-pos && flutter analyze && flutter test [path]` (green with no database; `integration` suites self-skip without `POS_PG_HOST`). `scripts/check.sh` runs everything incl. PostgreSQL and needs a local server. CI does not run tests.

## Required output
Report scope, verified file paths, assumptions/unknowns, changed files (if any), exact tests run with outcomes, risks and next action. Follow workspace `CLAUDE.md` approval rules.
