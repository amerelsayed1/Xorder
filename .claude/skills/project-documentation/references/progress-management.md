# Progress management

State lives in `docs/DOCUMENTATION_PROGRESS.md` (template: `templates/DOCUMENTATION_PROGRESS.md`). It is the only memory between runs, so update it after **every** feature and module, not at the end.

## Statuses
| Status | Meaning |
|---|---|
| `pending` | In the inventory, no documentation yet |
| `discovered` | Evidence gathered and recorded in the inventory, docs not written |
| `drafted` | Docs written and self-checked, not independently validated |
| `validated` | the criterion in `validation-rules.md` (*Criterion for `validated`*) is met: the latest qualifying independent pass found no class-B (behavioral) error, class-N items are fixed, a promotion record exists |
| `stale` | Source changed since the recorded HEAD (or validation found drift); needs `update` |
| `blocked` | Cannot proceed; the reason and who must answer are recorded |
| `removed` | Source no longer exists; docs kept and marked |

Statuses describe the **core** documentation. The optional `BEHAVIORAL_ANALYSIS.md` is tracked separately as `analysis: none | unvalidated` and never reaches `validated`.

A feature moves forward one step at a time. Only `validate` may set `validated`, and only under that criterion. Any later source change in its evidence files sets it back to `stale`; a core edit that changes a behavioral statement sets it back to `drafted`.

## What is recorded
- Header: date, command run, for each repo the branch, HEAD (`git log --oneline -1`) and the `status --short` list (uncommitted work is part of what was documented).
- Per feature row: slug, module, status, **source HEAD per repo at documentation time**, docs date, last validation date, open unknowns count, doc path, blocker.
- Per module row: counts by status and the doc path.
- Plan section: ordered batches, agents planned, notes. A batch is complete only when all its features are at least `drafted`.
- Uncovered source: files/routes/screens that belong to no feature yet.
- Run log: one line per run (date, command, result, what changed).

## Resuming `all`
1. Read the progress file; if absent run `scan`.
2. Compare current repo HEADs with the recorded ones; if changed, run the staleness procedure below first so `all` does not document against old assumptions.
3. Take the first batch that has `pending`, `discovered` or `stale` features, resolved `blocked` ones included.
4. After each feature: update its row, then the module row, then the run log. After each module: run `python3 scripts/harness/check-docs.py`.
5. Stop conditions: a blocker needing the user, context nearly exhausted, a check failing. Write the stop reason into the run log and the final report.

## Staleness (`update`)
1. For each repo and recorded HEAD `H`:
   - `git -C <repo> diff --name-only H..HEAD` (committed changes since the docs)
   - `git -C <repo> status --short` (uncommitted)
   If `H` is not an ancestor of HEAD (rebase), fall back to comparing the evidence files' modification via `git log -1 --format=%H -- <file>`.
2. Map every changed file to features through the **evidence index** in `FEATURE_INVENTORY.md` (each feature lists its evidence files). Files in migrations, routes, `Capability`/`TenantCapability`, `permissions.dart`, `providers.dart`, `router.dart` or coordination docs touch many features; map them by content (grep for the table, route or permission) rather than by directory.
3. Mark mapped features `stale` with the changed files listed. Changed files that map to no feature are **uncovered**: add to the inventory as a candidate (new feature, new module, or an extension of an existing one) and say so in the report.
4. Re-run the `feature` procedure only for stale features, merging per `documentation-standards.md`. Add `CHANGELOG.md` entries. Record the new HEADs only for features actually refreshed.
5. Report: stale found, refreshed, still stale (and why), new uncovered areas, removed sources.

Docs-only changes in the repos (`docs/`, `*.md`) are not stale triggers unless a contract document in `docs/coordination/` changed; those trigger the cross-application features.

## `status` output
Counts per status; a per-module table (features, drafted/validated/stale/blocked); the stale and blocked lists with reasons; unknowns that need a human, ranked; uncovered areas; recorded vs current HEADs; and one recommended next command (`scan`, `plan`, `all`, `update` or `validate`).

## Integrity
- Never mark progress ahead of the files: write the docs first, then the row.
- If the progress file and `docs/features/` disagree (a folder with no row, or a row with no folder), report it and repair the row; never delete the folder.
- If the file is corrupted or missing, rebuild it from `docs/features/*` and a fresh `scan`, and say it was rebuilt.
