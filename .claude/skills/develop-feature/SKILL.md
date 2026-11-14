---
name: develop-feature
description: Turn whatever the user passes — a sentence, a list, a pasted ticket, an XORD-nnn — into one very good, verified, implementable description of the feature or change, saved to docs/features/<slug>/FEATURE.md. Writes the description only; it does not plan the build or touch application code (that is /implement). Use whenever the user says what they want built, changed or improved ("I want", "add", "make it", "we need"), shares a requirement or ticket, or asks to specify or describe a feature, in the cloud API, the Vue apps or the POS.
argument-hint: "<what you want, in your own words | XORD-nnn | pasted ticket>"
---

# Develop Feature — write the description

Input: `$ARGUMENTS`. **Your job is to write what the user passed as a very good description, nothing more.** Read-only on application code; the only file written is `docs/features/<slug>/FEATURE.md`. Planning, building and testing are `/implement`; finding why something is broken is `/bug-investigation`.

## What "very good" means
- **Faithful.** Restate what the user asked in one or two sentences first and keep their decisions in their words. Never add features, endpoints, fields or behavior they did not ask for; extra ideas go under open questions, labelled as suggestions.
- **Verified.** Say what exists today from the current source (`path:line`), and what is missing. Anything not confirmed is marked **UNVERIFIED**. Documentation is a lead, not authority (`.claude/rules/knowledge.md`).
- **Testable.** Every acceptance criterion can be proven by a named kind of test, or is marked as needing a person to look.
- **Specific to Xorder.** Roles and permissions, venue models, offline behavior, tenant isolation, Arabic and RTL, plan and licence limits, and the POS/cloud contract are covered or explicitly not applicable.
- **Short enough to read.** Plain language, tables for lists, no filler.

## Procedure
1. **Capture.** Restate the request. If it is an `XORD-nnn`, read its entry in `docs/qa/XORDER_QA_FINDINGS.md` and keep its numbering rule. Choose a slug; check `git -C <repo> status --short` for each repo the description may concern and report unrelated dirty files.
2. **Load knowledge.** `grep -n -i` the feature in `docs/FEATURE_INVENTORY.md`, then `/project-documentation context <slug> plan`: freshness, related features, contracts, gaps. Missing or stale on the task's path is reported, never blocking.
3. **Discover** (below), as much as the description needs.
4. **Domain lens.** Read the matching sections of `docs/domain/FOOD_SERVICE_DOMAIN.md` and apply its section 6 questions: which of café, restaurant, food truck and cloud kitchen it serves, what it assumes about tables, addresses, counters and connectivity, and which known gap (tips, aggregators, KDS, recipes, loyalty, multi-brand) it leans on.
5. **Write the description** with the template below. Save or merge it into `docs/features/<slug>/FEATURE.md` (keep existing content; status `proposed`; record the date and the source revision of each repo), and show the user a summary in chat with the file link.
6. **Ask only what changes the description.** Use `AskUserQuestion` with a recommended option; otherwise write the assumption down. Record each answer as a decision, with the date.
7. **Hand off.** End with `Next: /implement <slug>` and list what that will need approved (migrations, contract changes, payment or order-state changes, permission changes that narrow access, anything reaching `xorder-cloud` `main`).

## Template (every section present; write "none" or "not applicable, because…" rather than omit)
```
# <Title> — <slug>
Status: proposed · <date> · Source: the user's request (quoted) · Verified against: xorder-cloud <sha>, xorder-pos <sha>
1. Summary — two or three sentences, plain language.
2. Why — who is hurt, when, in which venue model.
3. Goal and success — how we will know it worked.
4. Users, roles and permissions — who may do it; which existing permission identifiers apply.
5. Today — what exists now (path:line), what is missing, what is UNVERIFIED.
6. Scope — in; and explicitly out.
7. Behavior and business rules — BR-1…; preserve existing rules unless the user changed them.
8. Acceptance criteria — AC-1…, Given/When/Then, each testable.
9. Edge cases and failure modes — offline and retry, idempotency, tenant boundary, concurrency, Arabic/RTL and digits, plan and licence limits, empty and very large data.
10. Impact — apps and repos, API and contract (READY items only), data and migrations, permissions, localization, documentation, deploy order.
11. Dependencies, known gaps, risks.
12. How it will be tested — the test that proves each AC; what needs a person to look.
13. Decisions and open questions — decided (with date); still open.
```

## Phase: discover (read-only)
1. Read `docs/architecture/repo-map.md` and the target repo's `CLAUDE.md`. Repo code, migrations and tests win over prose.
2. Trace what exists, end to end. Cloud: `apps/api/routes/*.php` → middleware → controller → `Requests/` → `Services/` → `Models/` and migrations → `Resources/`; Vue `apps/*/src/{router,pages,stores,components}`, `packages/api-client`. POS: `lib/features/<area>` → `lib/app/providers.dart` → `lib/domain/{services,repositories}` → `lib/data/{postgres,cloud}`. Contract: `docs/coordination/*.md` in both repos (`POS-BE-xxx`, `CB-xx`; READY/APPROVED/PROPOSED). Use `feature-analyst` for a broad sweep, at most three at once.
3. Collect the tests that already cover it (cloud `apps/api/tests/{Feature,Unit}`; POS `test/`, `integration_test/`).
4. Record actors and permissions, rules, endpoints (from route files only), tables and columns (from migrations), tenant, money and order invariants, failure modes, unknowns. Every claim carries `path:line` or a test reference, or is **UNVERIFIED**.
5. If the work spans modules, the whole-system map belongs in `docs/architecture/repo-map.md` (verified paths only); the seven-file folder is written by `/project-documentation feature <slug>`.

Output format: `.claude/rules/reporting.md`. Follow workspace `CLAUDE.md` approval rules; no commits, pushes or migrations.
