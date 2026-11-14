---
name: release-readiness
description: Evaluate feature readiness for cloud and desktop release.
argument-hint: "<feature slug or release scope>"
---

# Release Readiness

Read-only; never deploy, push, tag or migrate.

## Procedure
1. Establish what ships: `git -C <repo> log --oneline` / `git diff` against the release base for each repo involved.
2. **Cloud** (`xorder-cloud`): a push to `main` auto-deploys to https://xorder.io and migrates the live PostgreSQL database. Run the repo's own `/release-check` skill for the database-safety gate and per-item PASS/FAIL, and add its verdict here. Confirm new migrations are additive, reversible, and reviewed with `/postgres-management`.
3. **POS** (`xorder-pos`): a release is a green `scripts/check.sh` (analyze + all tests incl. PostgreSQL), then a tag, then a manual Windows installer workflow run. CI does not run tests. Report whether `scripts/check.sh` was actually run; unit-only runs leave the 69 PostgreSQL-tagged tests skipped.
4. **Compatibility**: cloud and POS deploy independently. List contract IDs touched and their READY/APPROVED/PROPOSED status in `docs/coordination/`; define rollout order (normally cloud first, additive) and what an old POS does against the new server and vice versa.
5. Check docs: `/project-documentation status` shows no `stale` item for the shipped features, `validate <slug>` was run on the final source, the seven feature docs match as-built behavior, TEST_REPORT has real output, CHANGELOG updated.
6. Provide go/no-go with unresolved risks, rollback strategy and what could not be verified.

## Required output
Report scope, verified file paths, assumptions/unknowns, changed files (if any), exact tests run with outcomes, risks and next action. Follow workspace `CLAUDE.md` approval rules.
