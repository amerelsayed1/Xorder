# Knowledge retrieval (`context`)

Purpose: give any skill or agent the verified project knowledge relevant to its task **without** loading the documentation set. Documentation is a lead to the code, not the authority; the retrieval result says how far to trust it.

## Hard limits
- Never read all of `docs/features/`, `docs/modules/` or the whole inventory into context. Search first, then open only what the phase needs.
- One brief covers one feature (or at most the 3 closest related ones). A task touching more than 3 features gets a brief per feature, produced one at a time.
- Read-only. The only commands run are `grep`, `git diff --name-only`, `git log`, `git status --short` and reading files.

## Steps
1. **Resolve the target.** Search `docs/FEATURE_INVENTORY.md` with `grep -n -i` on the slug, title words and likely code names (controller, service, screen, table, route fragment, contract ID like `POS-BE-009`). Use the summary table to pick candidates; open only the matching per-feature block. No match: report `missing` (see step 6), and fall back to code search with `feature-analyst`.
2. **Read the feature block.** It lists module, footprint, cloud and POS entry points, evidence files, rules/workflow IDs, contracts, tables, related features, tests, doc status, the source revision documented against and the verification status.
3. **Open only the sections the phase needs** from `docs/features/<slug>/`:

| Phase | Read | Skip unless needed |
|---|---|---|
| `plan` | `FEATURE.md` (Summary, Business rules, Acceptance criteria, Known limitations, Cross-application dependencies, Unknowns), `TECHNICAL.md` (Source references, Offline and sync, Compatibility), `API.md` (Verified endpoints, Backward compatibility), `DATABASE.md` (Tables, Shared entities), related features' Summary only | `WORKFLOWS.md`, TEST_REPORT |
| `implement` | `TECHNICAL.md`, `API.md`, `DATABASE.md`, Business rules and Edge cases from `FEATURE.md`, the approved plan | Summary prose |
| `test` | `FEATURE.md` Acceptance criteria, Business rules, Edge cases, Existing automated tests; `TEST_PLAN.md`; `WORKFLOWS.md` | API/DATABASE prose except contract shapes |
| `bug` | `FEATURE.md` Business rules, Edge cases, Known limitations, Validation and error handling; `WORKFLOWS.md` for the failing journey; `TEST_PLAN.md` | the rest |
| `review` | `FEATURE.md` rules and ACs, `API.md` compatibility, `DATABASE.md` constraints, Security considerations, `TEST_PLAN.md`, `CHANGELOG.md` | WORKFLOWS unless a journey changed |

   Use the module doc (`docs/modules/<module>.md`) only for architecture questions, and `docs/PROJECT_OVERVIEW.md` only for cross-application or platform-wide questions.
4. **Freshness check (bounded, cheap).** Take from the inventory block the revision per repo (`cloud <sha>`, `pos <sha>`) and the evidence file list. For each repo:
   - **Monorepo (one git repo at the workspace root).** Recorded shas come from the former per-app repos and are still in history, but those commits use un-prefixed paths. Run from the monorepo root and diff the sha against the app's subtree, with paths stripped of the `apps/xorder-cloud/` or `apps/xorder-pos/` prefix: `git diff --name-only <sha> HEAD:apps/xorder-cloud -- <evidence paths>` (use `HEAD:apps/xorder-pos` for pos). Do NOT use `git -C apps/<app> diff ...` for this: the pathspec is prefixed, matches nothing, and reports a false `fresh`.
   - Uncommitted work: `git status --short -- apps/xorder-cloud/<evidence paths>` (workspace-relative paths, from the root).
   - Legacy layout (separate per-app repos): `git -C <repo> diff --name-only <sha>..HEAD -- <evidence paths>` and `git -C <repo> status --short -- <evidence paths>`, paths stripped of the app prefix.
   If the recorded sha is not an ancestor of HEAD, use `git log -1 --format=%h -- <path>` per file (from the root, with the prefixed path in the monorepo) and compare dates with the doc date.
   Verdict:
   - `fresh`: no evidence file changed and the verification status is `validated` or `drafted` with all load-bearing claims cited.
   - `needs verification`: an evidence file changed or is uncommitted, the status is not `validated`, or UNVERIFIED items touch the task.
   - `stale`: a changed file contradicts a claim you checked, or `validate` marked it stale.
   - `missing`: no inventory row or no doc folder.
5. **Spot-check load-bearing claims.** Whatever the verdict, open the cited `path:line` for the 2 to 5 claims the task depends on most (money rules, state transitions, permissions, endpoint shapes, constraints). If one is wrong, the verdict is at least `needs verification` and the discrepancy goes in the brief. A `fresh` doc is still not a substitute for reading the code you are about to change.
6. **Repair or report.**
   - Callers allowed to write documentation (planning, implementation, documentation skills): run `feature <slug>` or `update <slug>` for `stale`, `missing` or `needs verification` items that the task depends on, then re-run the check. Keep it narrow: only the affected feature.
   - Read-only callers (review, testing, agents without Write): report the gap and continue with source-verified facts only, marking everything else UNVERIFIED.
   - Never block a task solely because documentation is missing; say so, rely on the source, and list the documentation work as a follow-up.

## Brief format (what `context` returns)
```
Feature: <slug> (<module>, <footprint>)   Docs: <paths opened>
Freshness: fresh | needs verification | stale | missing   (documented against cloud <sha> / pos <sha>; changed since: <files or none>)
Verified now: <claims re-checked in source, with path:line>
Rules and ACs: <BR-/AC- ids with one-line text>
Contracts and data: <endpoints with READY/PROPOSED status; tables; shared entities>
Cross-application: <what the other app does, sync/idempotency, authority>
Related features: <slugs and why>
Tests: <existing files; known gaps>
Known limitations / UNVERIFIED: <list>
Documentation gaps: <what to write or fix, and who>
```

## Keeping the retrieval cheap
- The inventory is the only index. If a feature cannot be found through it, fix the inventory (via `update` or `feature`), not the caller.
- Prefer the inventory's evidence index over directory searches for "which files belong to this feature".
- Cache nothing between sessions except what is in the docs; the freshness check is the cache invalidation.
