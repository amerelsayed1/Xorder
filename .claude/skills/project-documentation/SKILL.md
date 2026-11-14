---
name: project-documentation
description: Master orchestrator that discovers, documents, validates and maintains documentation for every module and feature of the whole Xorder platform (cloud Laravel/Vue and Flutter POS), incrementally and resumably. Also the shared knowledge layer of the engineering harness: the planning, implementation, testing, bug and review skills call its read-only `context` command to load only the verified documentation relevant to their task. Use for scan, plan, all, module, feature, update, validate, status and context runs; `feature <slug>` writes or merges one feature's seven-file folder.
argument-hint: "scan | plan | all | module <name> | feature <name> | update [feature] | validate [target] | status | context <feature or query> [phase]"
---

# Project Documentation (whole platform)

Input: `$ARGUMENTS`. The first word is the command, the rest is its target. With no argument, or an unknown command, print the command table below plus the output of `status`, and stop.

This skill **coordinates** existing capabilities; it does not replace them. Per-feature code tracing is the `discover` phase of `/develop-feature` (the description writer); the seven-file feature folder is written by this skill's `feature` command (rules below). This skill adds the part they lack: a platform-wide inventory, module grouping, cross-application analysis, progress tracking, staleness detection, validation, and a cheap retrieval path (`context`) so other skills use the knowledge without loading it all. It is **not** a second orchestrator: the lifecycle order stays in `/develop-feature`; this skill only supplies and updates knowledge at each phase.

## Commands
| Command | What it does | Writes |
|---|---|---|
| `scan` | Discover every module and feature in both apps, build the inventory and the cross-application map | `docs/FEATURE_INVENTORY.md`, `PROJECT_OVERVIEW.md`, `DOCUMENTATION_PROGRESS.md` |
| `plan` | Turn the inventory into an ordered, batched documentation plan (needs a prior `scan`) | the plan section of `DOCUMENTATION_PROGRESS.md` |
| `all` | Document the whole platform incrementally, module by module, resuming from the progress file | module docs + feature folders + progress |
| `module <name>` | Document one module and every feature in it | `docs/modules/<module>.md` + its feature folders + progress |
| `feature <name>` | Document one feature (slug or title; resolved through the inventory) | `docs/features/<slug>/` + progress |
| `update [feature]` | Find documentation made stale by source changes and refresh only that; with a feature slug, refresh just that feature after an approved change | the affected docs + progress |
| `validate [target]` | Check documentation against the source and report drift (target: a feature, a module, or empty for what is not yet validated); changes no feature doc | `docs/validation/<date>-validation-report.md` + statuses in progress |
| `status` | Show progress, pending work, stale items and blockers | nothing (read-only) |
| `context <feature or query> [phase]` | Return a knowledge brief for the task: which docs to read, the business rules and acceptance criteria, freshness verdict, gaps. Phase is one of `plan`, `implement`, `test`, `bug`, `review` | nothing (read-only) |

`scan`, `plan`, `status` and `validate` never create feature folders. A command that needs an inventory which does not exist yet runs `scan` first and says so.

## Ground rules (workspace `CLAUDE.md` and `.claude/rules/*` win on any conflict)
1. **Source over prose.** Code, migrations, routes and tests are the truth; READMEs, `ARCHITECTURE.md`, `docs/pos/*` and the repo `CLAUDE.md` files are leads only. Where they disagree with code, document the code and record the contradiction under *Unknowns and assumptions*. Example already seen: the cloud `CLAUDE.md` mentions a `Policies/` directory, but `apps/xorder-cloud/apps/api/app/Policies/` does not exist and authorization is Gates plus middleware.
2. **Do not invent.** Every behavioral claim carries a `path:line` (workspace-relative) or a test reference; otherwise it is marked **UNVERIFIED**. Never describe planned or `PROPOSED` contract items as implemented. Integrate only with `READY` items of `docs/coordination/*`.
3. **Verify the layout first.** Before every `scan`, re-check the real directories; the workspace names differ from older prose (the cloud repo is `apps/xorder-cloud`, the POS repo is `apps/xorder-pos`). Details: `references/discovery-workflow.md`.
4. **Documentation only.** Read-only on all product code, config, migrations and tests. Write only under the workspace `docs/` folder (the indexes `docs/PROJECT_OVERVIEW.md`, `docs/FEATURE_INVENTORY.md`, `docs/DOCUMENTATION_PROGRESS.md`, plus `docs/modules/`, `docs/features/`, `docs/validation/`). Never write into the nested repos' own `docs/`; they own those files. Never edit `docs/coordination/*`.
5. **Never overwrite.** If a doc exists, merge: keep human-written content and decision history, change only what the source contradicts, and append to that feature's `CHANGELOG.md`. The workspace root is **not a git repository**, so there is no undo; edit in place with the Edit tool rather than rewriting files. Details: `references/documentation-standards.md`.
6. **Protected data.** Never read `.env*`, key files (`*.pem`, `*.key`), `db-backups/` or customer data; never write secrets, tokens, PII or payment details into docs (redact examples). Do not run migrations, `artisan` commands, installers, deploy scripts or anything that boots the app against a database; analysis is static reading plus `git log/diff/status`, `grep` and the test runs already defined in `/project-testing`.
7. **No commits, pushes, tags or deploys.** `xorder-cloud` `main` auto-deploys to production; documentation never needs git writes.
8. **Honest status.** A feature is only `validated` when the criterion in `references/validation-rules.md` is met (owner-approved 2026-10-20: the last independent pass found no behavioral error, with a promotion record). Never mark something done that was not checked, and never write "passed" for tests that were not run.

9. **Cost control.** `scan` and `all` run only when the user asks for them. `context` and `update <slug>` touch one feature; `update` without a slug is driven by `git diff` from the recorded revisions and refreshes only the mapped features. Never run a platform-wide scan because code was edited, and never rewrite the knowledge base for a source change that maps to no documented feature (record it as *uncovered* instead).

## Procedure per command
Read the matching reference before running a command, and the templates in `templates/` when writing.

### `scan`
Follow `references/discovery-workflow.md`. Output: module list, feature list per module with the cloud and POS entry points, shared and one-sided features, evidence index, and the cross-application findings from `references/cross-application-analysis.md`. Seed `DOCUMENTATION_PROGRESS.md` with every feature as `pending`, recording `git -C <repo> log --oneline -1` and `status --short` for both repos.

### `plan`
Read the inventory. Group into batches (one module per batch, split a module of more than about 8 features), order by dependency and risk: foundations first (auth, tenancy, roles), then money and order flows, then POS↔cloud sync and licensing, then the rest. For each batch list the features, the agents it needs (see *Delegation*), the unknowns that need a human answer, and any blocker. Present the plan; `all` may start without further approval because it writes docs only, but report the plan first.

### `all`
Resume from `DOCUMENTATION_PROGRESS.md` (first `pending`/`stale`/`blocked`-resolved batch). For each module in plan order: run the `module` procedure, update the progress file, run `python3 scripts/harness/check-docs.py`, then continue. Stop and report when context runs short, a gate is blocked, or an unknown needs the user; the progress file makes the next `all` resume exactly there.

### `module <name>`
1. Resolve the module in the inventory (exact slug, else closest match; if ambiguous list candidates and stop).
2. Write or merge `docs/modules/<module>.md` from `templates/MODULE.md`.
3. For each feature run the `feature` procedure. Independent features may be analysed in parallel (see *Delegation*); files are written by the main session.
4. Update the module's rows in the progress file and the inventory.

### `feature <name>`
1. Resolve through the inventory; unknown names run a targeted discovery first.
2. Gather evidence for both apps (the `/develop-feature` discover trace; `feature-analyst` for broad sweeps). Cloud: routes → middleware → controller → request → service → model/migration → resource; Vue pages, stores, composables. POS: `lib/features` → providers → domain services/repositories → `lib/data/{postgres,cloud}`. Contract: coordination docs. Tests for both.
3. Write or merge `docs/features/<slug>/` with the seven standard files (`FEATURE`, `TECHNICAL`, `API`, `DATABASE`, `TEST_PLAN`, `TEST_REPORT`, `CHANGELOG`) following the *Seven-file rules* below, using this skill's richer templates for `FEATURE`, `TECHNICAL`, `API`, `DATABASE`, plus `WORKFLOWS.md` from `templates/WORKFLOWS.md` when the feature has multi-step journeys, and `BEHAVIORAL_ANALYSIS.md` from `templates/BEHAVIORAL_ANALYSIS.md` for traced conclusions (ordering, timing, concurrency, failure cascades), which stay out of the core and out of `validate`. `TEST_REPORT` stays "not run" unless real output from `/project-testing` or `/develop-feature test` is cited with its report path.
3b. In `FEATURE.md` record which venue models the feature serves (café, restaurant, food truck, cloud kitchen) and any known domain gap it depends on, per `docs/domain/FOOD_SERVICE_DOMAIN.md`; mark it UNVERIFIED if not traced.
4. Self-check against `references/validation-rules.md` (citations, routes, tables, tests), set the status to `drafted`, update progress and inventory.

#### Seven-file rules (apply to every feature folder)
- Never overwrite: merge, preserving human content and decision history; append to `CHANGELOG.md`.
- Base templates are `docs/templates/` (`FEATURE`, `TECHNICAL`, `API`, `DATABASE`, `TEST_PLAN`, `TEST_REPORT`, `CHANGELOG`, same headings in the same order); this skill's `templates/` are the richer supersets for shared features.
- FEATURE: business rules and numbered, testable acceptance criteria (`AC-1`…), actors/permissions, cloud vs POS flows, unknowns. API: method/path from route files, auth and capability middleware, redacted request/response shapes, error format, POS contract IDs with READY/APPROVED/PROPOSED status, backward-compatibility notes. DATABASE: tables/columns/constraints from actual migrations, tenant column, transactions, index needs, rollback plan, Postgres-only behavior. TEST_PLAN maps every criterion to a test; TEST_REPORT stays "not run" until real output exists.
- Proposed behavior is labelled proposed; anything not confirmed in source is **UNVERIFIED** with `path:line` evidence elsewhere. Never invent contracts. Never include secrets, tokens, PII, payment data or backup contents.
- After writing: `python3 scripts/harness/check-docs.py`; register the feature in `docs/FEATURE_INVENTORY.md` and `docs/DOCUMENTATION_PROGRESS.md` with the source revision (`git -C <repo> log --oneline -1`) and status `drafted`. Only `validate` may set `validated`.

### `update`
Follow `references/progress-management.md` (*Staleness*): diff each repo from its recorded HEAD plus uncommitted changes, map changed files to features through the evidence index, mark them `stale`, re-run the `feature` procedure for those only, add `CHANGELOG.md` entries, refresh the recorded HEADs. Report new routes, models, screens or migrations that belong to no feature as *uncovered* and add them to the inventory.

### `validate`
Follow `references/validation-rules.md`. Prefer a pass that is not anchored on the writer's reasoning: use a fresh `feature-analyst` (or `code-reviewer`) agent per module with the doc and the source but not your notes. Spot-check its claims yourself. Write the report with severity-ranked findings (wrong, stale, unverifiable, missing), classify findings as behavioral (B) or non-behavioral (N), set features to `validated` only under the criterion (with a promotion record), `drafted` or `stale` otherwise, and list what was not checked.

### `context <feature or query> [phase]`
Read-only and cheap; this is what the other skills call. Follow `references/knowledge-retrieval.md`: resolve the target through `docs/FEATURE_INVENTORY.md` (never load all docs), read only the sections the phase needs, check freshness against the recorded source revision with a bounded `git diff` of that feature's evidence files, and return a brief: doc paths, rules and acceptance criteria, freshness verdict (`fresh`, `needs verification`, `stale`, `missing`), related features, gaps. For `needs verification` or `stale`, spot-check the load-bearing claims against the source before the caller relies on them; if the caller is allowed to write docs, `feature <slug>` or `update <slug>` repairs them. Documentation is a lead, never authority: an UNVERIFIED or stale item is reported as such, not used as a fact.

### `status`
Read-only. Print: counts per status, per-module table, stale and blocked items with reasons, open unknowns needing a human, uncovered source areas, the recorded vs current HEAD of each repo, and the recommended next command.

## Where this fits in the lifecycle (called by the other skills; do not duplicate their work)
| Skill and phase (`/develop-feature` writes the description, `/implement` builds it) | Calls | Result |
|---|---|---|
| `/develop-feature` discover and load knowledge | `context <feature> plan` | brief with rules, contracts, dependencies, freshness |
| `/implement` verify source | caller re-reads the load-bearing source cited by the brief | confirmed or corrected facts |
| `/implement` plan | uses the brief; reports gaps | plan cites docs and source |
| `/implement` implement | `context <feature> implement` | files, contracts, regressions to protect |
| `/implement` test | `context <feature> test` | acceptance criteria, edge cases, coverage gaps |
| `/implement` review | `context <feature> review` | rules to check, documentation inconsistencies to report |
| `/implement` update knowledge | `update <slug>` (then `validate <slug>` once the code is final) | docs match as-built, inventory row refreshed |
Bug work: `/bug-investigation` uses `context <feature> bug` first; the fix is `/implement`, which runs `update <slug>` only if behavior or a known limitation changed.

## Delegation (use only what the task needs; never fan out all agents)
| Need | Use |
|---|---|
| Broad sweep of one module's code | `feature-analyst` (read-only; at most 3 in parallel, each with an explicit scope and the output format wanted) |
| POS↔cloud contract and shared entities | rule `.claude/rules/api-contracts.md` plus `feature-analyst` on each side |
| Schema and PostgreSQL behavior | `database-reviewer`, only for modules with migrations or Postgres-only SQL |
| Auth, tenancy, money, orders security sections | `security-reviewer`, only for those modules |
| Independent validation | fresh `feature-analyst` or `code-reviewer` |
| Real test facts | cite existing `docs/testing/reports/*`; run `/project-testing` only when asked |

The harness agents have no Write tool, so the main session writes every file. Agent output is a claim, not evidence: open the cited lines before relying on them.

## Required output
Report the command run, scope, repos and HEADs inspected, verified file paths, assumptions and UNVERIFIED items, files created or changed (full paths), checks run with their real output (`python3 scripts/harness/check-docs.py`, `bash scripts/harness/verify.sh` after writing docs), what was **not** done, risks, and the next command to run. No commits or pushes.
