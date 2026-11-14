# Xorder Claude Engineering Harness — Initialization Report

Date: 2026-10-20 · Claude Code 2.1.303 · Workspace root: `/Users/amerelsayed/Projects/Xorder` (not a Git repo)

> The initialization request was cut off mid-sentence at section 7 ("4. Validati…"). This report covers items 1–3 as specified plus validation results, open issues and recommendations.

## 1. Actual workspace architecture

The original harness package assumed an older name for the cloud repo. **No such directory exists**; the cloud repo is `apps/xorder-cloud/`.

| Workspace | Verified technology | Git |
|---|---|---|
| `apps/xorder-cloud/` | pnpm 9 + Turborepo monorepo. `apps/api`: Laravel 13 (PHP ^8.3, PHPUnit ^12.5). `apps/web`, `apps/landing`, `apps/menu`: Vue 3 + Vite 8. `packages/{ui,api-client,analytics}`. Stateless JWT guard (not Sanctum). Tenant isolation via `RestaurantScope`. | Own repo, `main`, remote `amerelsayed1/Xorder-Menu`, clean at start and end |
| `apps/xorder-pos/` | Flutter 3.47 / Dart ^3.13 desktop (Windows/macOS), Riverpod, go_router, `postgres` (pure Dart) to a branch PostgreSQL, `dio` cloud client, offline outbox | Own repo, remote `amerelsayed1/xorder-pos`, clean at start and end |
| `docs/`, `.claude/`, `scripts/harness/`, `app-instructions/` | Harness (this package) | Workspace root has no `.git` |
| `db-backups/` | Confidential | **Never inspected** |

Key facts (details in `docs/architecture/repo-map.md`):
- **Production risk:** a push to `xorder-cloud` `main` auto-deploys to https://xorder.io and runs `migrate --force` against live PostgreSQL. Cloud tests run on SQLite `:memory:` (`apps/api/phpunit.xml`), so Postgres-specific behavior is not covered by tests.
- The cloud API has no `/v1` prefix; POS↔cloud compatibility is governed by `docs/coordination/*.md` (`POS-BE-xxx` IDs, READY/APPROVED/PROPOSED).
- Test infrastructure: cloud PHPUnit (102 test files, 111 migrations); POS `flutter test` (263 test files) + `integration_test/` + `scripts/check.sh` (needs local PostgreSQL). **No JS unit/E2E framework, no JS lint scripts, no PHP formatter/static analyser** found.
- POS CI only builds the Windows installer, run manually. Cloud CI (`deploy.yml`) gates on API tests then deploys.

## 2. Discovered skills and agents

**Harness skills (16, `.claude/skills/*/SKILL.md`)** — all have valid frontmatter, name = directory, and appear in this session's skill list:
`develop-feature` (orchestrator), `feature-discovery`, `feature-documentation`, `feature-planning`, `feature-implementation`, `feature-testing`, `feature-review`, `api-contracts`, `laravel-development`, `vue-development`, `flutter-development`, `postgres-management`, `bug-investigation`, `refactoring`, `release-readiness`, `security-audit`.

**Harness agents (9, `.claude/agents/*.md`)** — valid frontmatter, all listed as available agent types: `feature-analyst`, `implementation-planner`, `backend-engineer`, `frontend-engineer`, `flutter-engineer`, `database-reviewer`, `security-reviewer`, `code-reviewer`, `test-engineer`. All have tools `Read, Grep, Glob, Bash` (no Edit/Write) by design: they report and propose; the main session edits.

**Pre-existing repo-level config (preserved, untouched):**
- `apps/xorder-cloud/.claude/`: skill `release-check` (auto-discovered when working under `apps/xorder-cloud/`), agent `xorder-cloud`, `launch.json`, `settings.local.json`, two leftover `worktrees/` dirs.
- `apps/xorder-pos/.claude/`: agents `pos-dev`, `pos-pm`, `settings.local.json`.
- Repo-level `CLAUDE.md` in both repos (authoritative for their repo).

**User-level skills overlapping the harness** (outside the project, not modified): `xorder-backend-dev`, `xorder-web-dev`, `xorder-pos-dev`, `xorder-audit`, plus unrelated Operix skills.

## 3. Configuration changes made

Only harness configuration and docs; no application code, migrations or git history touched.

| File | Change |
|---|---|
| `CLAUDE.md` | cloud repo renamed to `xorder-cloud` throughout; verified stack summary; precedence of nested repo CLAUDE.md; production auto-deploy warning; contract-ledger pointer; `/develop-feature` routing note |
| `.claude/settings.json` | Kept all 5 original deny rules; added deny for edits to `db-backups`, any Bash command mentioning `db-backups`, `git push`, `git reset --hard`, `git clean`, destructive `artisan migrate:*`/`db:wipe`, `migrate` with `--force`, `pg_restore`, `dropdb`, `deploy.sh`, `go-live.sh` |
| `.claude/skills/*` (12 files) | Rewrote the 7 workflow skills (`develop-feature`, `feature-{discovery,documentation,planning,implementation,testing,review}`) and 5 technology skills (`laravel-`, `vue-`, `flutter-development`, `postgres-management`, `api-contracts`) from 12-line stubs into concrete procedures using verified paths/commands; frontmatter name/description unchanged (added `argument-hint` to workflow skills). Follow-up pass also rewrote `bug-investigation`, `refactoring`, `release-readiness`, `security-audit`, so all 16 skills are now concrete |
| `.claude/rules/` | **New**: `cloud-laravel-vue.md` and `pos-flutter.md` (path-scoped), `production-safety.md`; originals unchanged |
| `apps/xorder-pos/scripts/sync-coordination.sh`, `apps/xorder-cloud/scripts/sync-coordination.sh` | Sibling name now `xorder-cloud` (uncommitted; only edits made inside the app repos) |
| `CLAUDE.md` (follow-up) | Added precedence note for overlapping user-level skills |
| `scripts/harness/check-harness.py` (follow-up) | Now also requires the three new rules; warns on skill bodies under 800 chars |
| `docs/architecture/repo-map.md` | Replaced "pending verification" table with verified map |
| `README.md`, `scripts/harness/verify.sh` | Renamed to `xorder-cloud`; real paths; verify.sh now runs harness + docs checks |
| `scripts/harness/check-harness.py` | **New**: validates skill/agent frontmatter, tool names, settings.json, rules, templates, orchestrator references, stale names |
| `app-instructions/` | old-name example renamed to `xorder-cloud.CLAUDE.example.md`; both examples now verified cross-references (they do not replace repo CLAUDE.md) |
| `docs/harness/INITIALIZATION_REPORT.md` | This file |

Conflicts resolved: root vs repo CLAUDE.md (stricter rule wins, stated in root file); generic "assumed" architecture replaced by verified facts; harness "no commits/pushes" now enforced by deny rules, not only prose. `.claude/rules/*.md` were reviewed and kept unchanged (generic, no conflict).

## 4. Validation results (actual output)

| Check | Result |
|---|---|
| `bash scripts/harness/verify.sh` | Exit 0: "16 skills, 9 agents checked", "Harness structure OK", "Feature documentation structure OK" (no features exist yet, so the docs check is vacuous) |
| `.claude/settings.json` | Valid JSON; deny rules loaded (a Bash heredoc containing `migrate`+`--force` and `db-backups` text was blocked, confirming rules are enforced — and that they match anywhere in a command line) |
| Skill discovery | All 16 harness skills + `release-check` appear in the session skill list; agents appear as Agent types. **A full `/develop-feature` run was not executed** (it would start a real feature lifecycle) |
| Cloud: `cd apps/xorder-cloud/apps/api && php artisan test` | PASS — 1024 tests, 4966 assertions, 43 s, exit 0 (SQLite in-memory) |
| POS: `flutter analyze` | PASS — "No issues found", exit 0 |
| POS: `flutter test` (no `POS_PG_HOST`) | PASS — 2670 passed, 69 skipped (PostgreSQL-tagged suites self-skip), exit 0 |
| Git status after all runs | `xorder-cloud` and `xorder-pos` both clean |

Not run: POS PostgreSQL suites / `scripts/check.sh` / `integration_test`; `pnpm build`; any Postgres-specific cloud testing; deploy or CI workflows.

## 5. Open issues and unverified items

1. **Coordination docs have drifted** (`--check` reports DRIFT on `POS_TO_BACKEND.md` and `BACKEND_TO_POS.md`; `BACKOFFICE_TO_CLOUD.md` in sync). The sync script was fixed to find `xorder-cloud` in **both** repos (`scripts/sync-coordination.sh`, 8 lines each, uncommitted, copies identical). The sync itself has **not** been run; review the differences first, since it overwrites the non-owner copy.
2. Stale references to the old cloud repo name inside the app repos were replaced with `xorder-cloud` in a later pass (see §9).
3. No JS tests/lint and no PHP linter: `feature-testing` for Vue relies on manual verification until you approve adding tooling.
4. Harness agents cannot edit; names like `backend-engineer` ("Implement…") are advisory. Intentional per `CLAUDE.md`; change `tools:` if you want agents to write.
5. Deny patterns are glob-style over the whole command text: they can false-positive (as seen) on commands that merely mention e.g. `db-backups`. `git push` is fully denied for Claude; push manually after review.
6. Overlap with user-level `xorder-*-dev` skills (whose text may predate the `xorder-cloud` name): resolved by precedence note in root `CLAUDE.md`; the personal skills themselves are not modified.
7. The workspace root is not under Git, so the harness itself is unversioned; `.gitignore.harness.example` is unused. No hooks are configured (opt-in only).
8. Content of `settings.local.json` files and `db-backups/` was not read.
9. Path-scoped rules (`paths:` frontmatter in `cloud-laravel-vue.md`, `pos-flutter.md`) rely on Claude Code's rules-file support; I did not verify in a live session that they load only for matching paths.
10. `docs/features/` contains no features yet; the feature-documentation workflow is unexercised on real code.

## 6. Recommended next step

```
/feature-discovery Pick one small existing feature (e.g. POS shift close) and document it end to end in docs/features/<slug>/ without modifying application code.
```

## 7. Follow-up: workspace re-layout (apps/)

At the user's request both repos were moved to `apps/xorder-cloud/` and `apps/xorder-pos/` (plain `mv`; Git history, remotes and working trees intact). Harness paths, rules (`paths:` globs), skills, `verify.sh`, README and the repo map were updated. Checked afterwards: `verify.sh` exit 0; `sync-coordination.sh --check` still finds both repos (it resolves siblings relative to itself); cloud `AuthTest` 14/14 passed; POS `flutter analyze` clean. The full suites were not re-run after the move. Not updated: the sync script's header comment example path, a few generated Flutter files under `apps/xorder-pos/ios/Flutter/` with old absolute paths (regenerated by Flutter), the two stale cloud worktrees (already pointed at a non-existent old location), and open IDE projects (`.idea`) or Claude project settings keyed to the old paths, which may need reopening.

## 8. Follow-up: repo-level `.claude/` included in the workspace

`.claude/agents/{xorder-cloud,pos-dev,pos-pm}.md` and `.claude/skills/release-check` are symlinks to the originals under `apps/*/.claude/` (single source of truth, no copies to drift). `develop-feature` routing and root `CLAUDE.md` now reference them. Two stale lines in `apps/xorder-cloud/.claude/agents/xorder-cloud.md` (the old repo name, an old `~/Projects/Mobile Application/...` path) were corrected (uncommitted). `settings.local.json`, `launch.json` and `worktrees/` were intentionally not linked (local, personal or stale). Caveats: the symlinked agents `xorder-cloud` and `pos-dev` have Edit/Write; when working inside a repo, Claude Code may also list `release-check` under its nested name; whether symlinks are followed by every Claude Code version was verified only by the structure check (`verify.sh`), not by invoking the agents.

## 9. Follow-up: old cloud repo name replaced with `xorder-cloud`

On request, every remaining mention of the old name was replaced with `xorder-cloud`: in the harness files, and in the tracked files of both app repos (cloud: 10 files, 37 lines; POS: 11 files, 34 lines; all uncommitted). Changes in app code are two comments only (`management_screen.dart`, `cloud_purchasing_hidden_test.dart`); the rest are docs, `CLAUDE.md`, the sync scripts and the cloud agent. One absolute path in `REVISION_ORDER_ITEM_ID.md` was rewritten to `.../Xorder/apps/xorder-cloud/...`. Historical text now reads as if the repo had always been called `xorder-cloud` (e.g. "work done in an unpushed `xorder-cloud` checkout"); Git history is unchanged and still has the old name. The harness checker now warns if the old name reappears. After the change: `verify.sh` OK, `sync-coordination.sh --check` unchanged (same two drifted files), POS `flutter analyze` clean; no tests were re-run.
