# Project knowledge

The knowledge layer is `docs/FEATURE_INVENTORY.md` (index), `docs/PROJECT_OVERVIEW.md`, `docs/architecture/`, `docs/modules/`, `docs/features/<slug>/`. Procedures live in `.claude/skills/project-documentation/` (`context`, `update`, `validate`); this file only states the rules every skill and agent follows.

1. **Look up before significant changes.** Find the feature with `grep -n -i` in `docs/FEATURE_INVENTORY.md`, then read only the sections the task needs (`references/knowledge-retrieval.md`). Never load all docs, and never load unrelated features or modules.
2. **Verify critical behavior in the current source** before relying on it: money rules, order and shift state, permissions, tenant boundaries, endpoints and schema. Check the doc's `Verified against` revision, and run the freshness check in `knowledge-retrieval.md` (the workspace is one git monorepo: run it from the root with `git diff --name-only <sha> HEAD:apps/xorder-cloud -- <paths>`, never `git -C apps/<app>`).
3. **Never invent undocumented functionality**, endpoints, columns or contracts. Mark what you could not confirm **UNVERIFIED**; integrate only with `READY` contract items.
4. **Prefer established patterns and reusable components** found through the inventory's source references and neighbouring code.
5. **Identify cross-application dependencies** (cloud API ↔ POS ↔ Vue) from the feature's *Cross-application dependencies* section and the contract ledger before planning a change.
6. **Preserve existing behavior** and documented business rules unless the approved requirements change them; list intended rule changes explicitly.
7. **Keep documentation aligned with implementation**: after an approved change, run `/project-documentation update <slug>` for the affected features and record the new source revision.
8. **Report missing or outdated documentation** (no inventory row, stale revision, UNVERIFIED items on the task's path) in the final output, with the proposed follow-up.
9. **Documentation is a lead, not authority.** Unverified, stale or contradicted documentation is never treated as fact; code, migrations and tests win and the contradiction is reported.
10. **Do not wait on documentation.** Missing docs never block a task; rely on the verified source, label the rest, and queue the documentation work. Only `/project-documentation validate` may mark documentation `validated`, and only after checking the final source.

Writers of documentation touch only the workspace `docs/` folder (never `apps/*/docs/`), merge instead of overwriting, and never record secrets, tokens, PII, payment data or backup contents.
