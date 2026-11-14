---
name: vue-development
description: Build Vue cloud application features according to existing architecture.
---

# Vue Development

Knowledge: before significant changes follow `.claude/rules/knowledge.md` (`/project-documentation context <feature> <phase>`); verify critical behavior in current source, and report missing or stale docs.

## Procedure
Work in `xorder-cloud` (pnpm 9 + Turborepo; Vue 3.5, Vite 8). Apps: `apps/web` (Super Admin + Restaurant dashboards, dev port 5173), `apps/landing` (5174), `apps/menu` (diner ordering SPA, 5175); shared `packages/{ui,api-client,analytics}`. Read `apps/xorder-cloud/CLAUDE.md` first.
- Inspect neighbouring `src/{pages,components,stores,router,composables,lib}` before adding code; reuse `packages/ui` components, the shared axios/API client (JWT bearer) and the CSS-variable theme.
- Bilingual AR/EN with RTL is required; capability-gated UI must mirror the server's `Capability`/`TenantCapability` checks (the server stays authoritative).
- Cover loading, error and empty states, validation and accessibility. Never trust client totals or compute prices client-side as final.
- Verify: `cd apps/xorder-cloud && pnpm build` (or `pnpm --filter @xorder/<app> build`). **No unit/E2E test or lint scripts exist** in any `package.json`; do not install tooling without approval and state plainly that UI behavior was verified manually or not at all. For a dev server use `.claude/launch.json` in `xorder-cloud` (names `api`, `web`, `landing`, `menu`).
- Do not read `pnpm-lock.yaml` whole.

## Required output
Report scope, verified file paths, assumptions/unknowns, changed files (if any), exact tests run with outcomes, risks and next action. Follow workspace `CLAUDE.md` approval rules.
