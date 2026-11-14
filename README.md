# Xorder multi-repository Claude Code harness

Unpack **contents of this folder** into the parent workspace containing `apps/xorder-cloud/`, `apps/xorder-pos/`, `docs/` and `db-backups/`. Merge; do not replace existing documentation, CLAUDE.md, or settings blindly. The package deliberately contains no application source or database files.

## Setup
1. Back up existing root `CLAUDE.md`, `.claude/`, and project-local `CLAUDE.md` files if present.
2. Merge this package into the **workspace root**. Review `.claude/settings.json` before adopting permissions/hooks; preserve your existing settings.
3. Open a terminal at that root and run `claude`. Seven skills: `/develop-feature` (writes what you ask for as a verified description), `/bug-investigation` (finds the root cause, no fix), `/implement` (plan, build and test it; one phase with `plan|implement|test|review|ready <target>`, or `refactor <area>`), `/project-documentation`, `/security-audit`, `/project-testing`, `/release-check`. Stack conventions are path-scoped rules in `.claude/rules/` (mapping from the older 19 skills: `docs/harness/SKILL_CONSOLIDATION_2026-10-22.md`).
4. Start with `/develop-feature Map the actual repos, commands, API integration, and existing docs.` (it writes a description and changes no application code).
5. Run `bash scripts/harness/verify.sh` to validate harness structure (skills, agents, settings, docs) and list the available app checks. Scripts never deploy, migrate, push or read backups. Full status: `docs/harness/INITIALIZATION_REPORT.md`.

## Workspace layout
- `apps/xorder-cloud/`: Laravel 13 + Vue 3 monorepo (verified).
- `apps/xorder-pos/`: Flutter desktop POS (verified).
- `docs/`: shared feature docs and architecture.
- `db-backups/`: confidential; do not read or modify without specific permission.

## Operational notes
- Claude Code skills: `.claude/skills/<name>/SKILL.md` with YAML frontmatter; slash invocable.
- Agents: `.claude/agents/*.md`; tools and delegation subject to Claude Code version/settings.
- Scoped root rules are kept concise and in `.claude/rules/`; application notes in `app-instructions/` are cross-references only; each repo's own `CLAUDE.md` stays authoritative.
- **Run from workspace root** for shared instructions. Nested independent Git repos have separate status, commits, and CI; never assume atomic commits.
- Requirements and credentials are not invented. No generated docs claim tests passed unless executed.
- Suggested hooks are opt-in examples. No unconditional formatting, destructive changes, production access, or commits.
