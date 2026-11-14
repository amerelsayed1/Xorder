# Skill consolidation — 2026-10-22

The workspace went from 19 skills to 6. Stack conventions became path-scoped rules (they load automatically when the matching files are touched, no slash command needed). Old skill folders are kept, unloaded, under `.claude/skills-archive/2026-10-22/` for reference; Claude Code only loads `.claude/skills/*/SKILL.md`.

## Mapping

| Before (`/skill`) | Now |
|---|---|
| `develop-feature` | `develop-feature` (full pipeline, unchanged order) |
| `feature-discovery` | `develop-feature discover <slug>` |
| `feature-planning` | `develop-feature plan <slug>` |
| `feature-implementation` | `develop-feature implement <slug>` |
| `feature-testing` | `develop-feature test <slug>` |
| `feature-review` | `develop-feature review <slug>` |
| `release-readiness` | `develop-feature ready <slug>` |
| `feature-documentation` | `project-documentation feature <slug>` (the seven-file rules moved into that skill) |
| `project-documentation` | unchanged |
| `bug-investigation` | unchanged |
| `refactoring` | `bug-investigation refactor <area and goal>` |
| `security-audit` | unchanged |
| `project-testing` | unchanged |
| `release-check` | unchanged (symlink to `apps/xorder-cloud/.claude/skills/release-check`) |
| `laravel-development`, `vue-development` | rule `.claude/rules/cloud-laravel-vue.md` (paths `apps/xorder-cloud/**`) |
| `flutter-development` | rule `.claude/rules/pos-flutter.md` (paths `apps/xorder-pos/**`) |
| `postgres-management` | rule `.claude/rules/postgres-migrations.md` (migration paths in both repos) |
| `api-contracts` | rule `.claude/rules/api-contracts.md` (routes, Pos controllers/resources/requests, api-client, `lib/data/cloud`, coordination docs) |
| the repeated "Required output" footer | rule `.claude/rules/reporting.md` (always loaded) |

Personal skills in `~/.claude/skills`: `xorder-backend-dev`, `xorder-web-dev` and `xorder-pos-dev` were deleted; their still-valid conventions (non-fillable role/tenant columns, gate stack, `useCaps`/`confirm()`, both locales + RTL, basis-point rates, refusals as data, licence never bricks a till, …) were verified against the current source and folded into the two stack rules. `xorder-audit` stays (it drives the real app) with its repo paths corrected to `apps/xorder-cloud` and `apps/xorder-pos`.

## What changed in the harness checker
`scripts/harness/check-harness.py` now expects exactly the six skills (an extra skill is a warning, a missing one an error), checks that `develop-feature` documents the six phases and references only existing skills, and requires the three new rule files. Older reports in this folder still name the retired skills; read them with the mapping above.
