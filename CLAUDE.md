# Xorder engineering workspace

Workspace orchestration instructions (harness verified 2026-10-20; see `docs/harness/INITIALIZATION_REPORT.md`).
- `apps/xorder-cloud/` — pnpm/Turborepo monorepo: Laravel 13 API (`apps/api`) + three Vue 3 SPAs (`apps/web`, `apps/landing`, `apps/menu`) + `packages/*`. Prod DB is PostgreSQL; tests run on SQLite in-memory.
- `apps/xorder-pos/` — Flutter/Dart desktop POS (Windows/macOS), Riverpod + go_router, direct PostgreSQL on the branch server, cloud client via `lib/data/cloud/`.
- **This workspace is one Git monorepo** (root of this checkout). `apps/xorder-cloud` and `apps/xorder-pos` were imported from the former `Xorder-Menu` and `xorder-pos` repos with full history (old commits keep un-prefixed paths). CI lives in the root `.github/workflows/` (`cloud-deploy.yml`, `pos-windows-installer.yml`). No remote is configured yet.
- Each app keeps its own `CLAUDE.md` and `.claude/`. Those nested files are authoritative for their app; this file only adds cross-app rules. If they conflict, the stricter rule wins.

## Source of truth
1. Source code, actual migrations, and tests take priority over stale documentation.
2. Read `docs/architecture/repo-map.md` before cross-application tasks; update with verified paths only. POS↔cloud contract state lives in `docs/coordination/` of each repo (`BACKEND_TO_POS.md` is owned by the cloud/backend side; copies can drift — compare both before relying on one). Integrate against `READY` items only.
3. For each feature use `docs/features/<slug>/` and maintain FEATURE, TECHNICAL, API, DATABASE, TEST_PLAN, TEST_REPORT, CHANGELOG. Do not invent endpoints or behavior. Mark unverified details explicitly.
4. Before edits: inspect relevant implementation, write acceptance criteria and impact analysis. For risky migrations/payment/order-state changes ask approval.
5. After edits: run targeted tests, preserve real command output and failures, and update docs to match actual behavior.
6. QA backlog: `docs/qa/XORDER_QA_FINDINGS.md` is the owner's list of findings (XORD-001 onward) and what has been done about each. Read it before touching an area it names. A checkbox there is ticked only when an automated check that was actually run proves it, and the tick says which; never tick one because code was changed. Update the status and section 8 when you change an item, and number new findings from the next free `XORD-nnn`.

## Project knowledge (load on demand, never wholesale)
`docs/FEATURE_INVENTORY.md` maps every module/feature to its cloud and POS code, contracts, tables, tests, doc status and the source revision it was verified against; `docs/PROJECT_OVERVIEW.md`, `docs/architecture/`, `docs/modules/` and `docs/features/<slug>/` hold the detail. Before significant work, `grep` the inventory and use `/project-documentation context <feature> <plan|implement|test|bug|review>`, which opens only the needed sections and checks freshness against git. Docs are leads: verify critical behavior in current source, report missing/stale docs, and run `/project-documentation update <slug>` after approved changes. Rules: `.claude/rules/knowledge.md`.

## Non-negotiable safety
- Never access production or restore/export/read `db-backups/` without express authorization. Never delete backups.
- **`xorder-cloud` pushes to `main` auto-deploy to production (https://xorder.io), which runs `migrate --force`.** Never push, merge or tag there without explicit approval; run `/release-check` (repo skill) first.
- No destructive DB changes, migrations on non-test environments, force pushes, commits, deployments, credential reveals, or installing new tools without approval.
- Protect secrets, PII, customer records, payment details and multi-tenant boundaries. Do not paste them into docs or logs.
- Backend is authoritative for prices, discounts, taxes, totals, permissions and order transitions.
- Prefer idempotency and safe retry patterns for orders/payment requests. Do not assume offline POS exists; verify.
- Avoid silent changes to API response shapes or desktop compatibility; version and test contracts.
- Make minimal consistent changes; do not rewrite unrelated modules.

## Workflow
Three jobs, three skills. **`/develop-feature <what you want>`** writes what you pass it as one very good, verified description in `docs/features/<slug>/FEATURE.md` (no code). **`/bug-investigation <symptom>`** finds the root cause and writes a root-cause report in `docs/harness/investigations/` (no fix). **`/implement <slug | report | XORD-nnn>`** builds it: plan -> **approval** -> implement -> test (mandatory, every change) -> review -> update knowledge (`/project-documentation update`); one phase alone: `/implement plan|implement|test|review|ready <target>`; behavior-preserving refactors: `/implement refactor <area>`. Auth, tenancy, money and order integrity: `/security-audit`. Whole-project regression (not one feature): `/project-testing`, reports in `docs/testing/reports/`. Production gate before any push of `xorder-cloud` `main`: `/release-check`. Stack conventions are not skills but path-scoped rules that load when you touch the files: `.claude/rules/cloud-laravel-vue.md`, `pos-flutter.md`, `postgres-migrations.md`, `api-contracts.md`, `licences.md`; every skill reports in the format of `.claude/rules/reporting.md`. Only spawn the agents a task needs (`.claude/agents/`); never fan out all of them. Run `bash scripts/harness/verify.sh` to check the harness itself. Skill consolidation history: `docs/harness/SKILL_CONSOLIDATION_2026-10-22.md`.

## Repositories
`xorder-cloud` and `xorder-pos` now live in one repository but still deploy independently (cloud to the VPS, POS as a Windows installer). Check `git status --short -- apps/<app>` before modifying. Never assume both apps deploy together. For cross-app changes write an API compatibility and rollout plan. The production server's clone still tracks the old `Xorder-Menu` repo until it is switched (see `.github/workflows/cloud-deploy.yml`).

## Overlap with user-level skills
The only remaining personal Xorder skill is `xorder-audit` (drives the real app and dashboards to find defects); the former `xorder-backend-dev`, `xorder-web-dev` and `xorder-pos-dev` personas were deleted on 2026-10-22 and their still-valid conventions folded into the path rules above. Use `xorder-audit` only when asked, and let the repo `CLAUDE.md` and `.claude/rules/` win on any conflict.

## Repo-level Claude config included in this workspace
`apps/xorder-cloud/.claude/` and `apps/xorder-pos/.claude/` stay the source of truth; the workspace exposes them via symlinks in `.claude/` so they are available from the root: skill `release-check` (cloud production gate), agents `xorder-cloud` (cloud back office), `pos-dev` and `pos-pm` (POS). Edit the originals, never the links. Unlike the read-only harness agents, `xorder-cloud` and `pos-dev` can edit files: use them only for an approved, scoped item. Each repo's `settings.local.json` and `launch.json` remain local to that repo.
