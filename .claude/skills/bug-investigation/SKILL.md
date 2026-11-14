---
name: bug-investigation
description: Investigate a defect and find its root cause, with evidence, then write a root-cause report. Investigation only; it never fixes anything (that is /implement). Use whenever the user reports something broken, a wrong total, a failing test, an error or crash, a screen that behaves wrongly, or asks "why does X happen", in the cloud API, the Vue apps or the POS.
argument-hint: "<symptom, app, steps>  |  XORD-nnn"
---

# Bug Investigation — find the root cause

Input: `$ARGUMENTS`. **Your job is to find why it happens and prove it. You do not change application code.** Reproduction uses existing tests, commands and throwaway test files in the scratchpad directory; nothing is left in the repository. When the cause is known, the report is the hand-off: `/implement <report path>` makes the fix and its tests.

## Procedure
1. **Capture the symptom.** App (`xorder-cloud` API or Vue, or `xorder-pos`), environment, exact steps, expected versus actual, how often, since when. For an `XORD-nnn`, read its entry in `docs/qa/XORDER_QA_FINDINGS.md`. Run `git -C <repo> status --short` and read recent `git log` for the area; report unrelated dirty files. Never use production data or the live site to reproduce.
2. **Locate the feature and its documented behavior.** `grep -n -i` the inventory (`docs/FEATURE_INVENTORY.md`), then `/project-documentation context <slug> bug`. A reference, not truth: confirm the expected behavior in source and tests and note where the docs are wrong or silent.
3. **Reproduce locally.** Cloud: an existing PHPUnit test or a throwaway feature test on SQLite `:memory:` (`cd apps/xorder-cloud/apps/api && php artisan test --filter X`). POS: `flutter test <path>`; pure money or ticket bugs reproduce in `TicketEngine` unit tests. If it cannot be reproduced, say so and what was tried. Note when the bug may be PostgreSQL-specific, which the cloud suite cannot show.
4. **Think like the operator.** Use `docs/domain/FOOD_SERVICE_DOMAIN.md`: what the cashier, owner or kitchen was doing (peak rush, mid-round, offline, shift close), and which venue model it affects. Many defects appear in only one.
5. **Isolate the root cause with evidence**: the code path (`path:line`), the log line, the failing assertion. Separate the **cause** from the **symptom** and from **contributing conditions**. Test your explanation by predicting something it implies and checking it; rule out the alternatives you considered. Do not guess; state your confidence (confirmed, likely, unproven) and what would confirm it.
6. **Find the blast radius.** Other call sites of the same code, related features from the inventory, other apps (cloud ↔ POS ↔ Vue), data already written wrongly (without touching a real database), and which tests should have caught it and why they did not.
7. **Write the root-cause report** to `docs/harness/investigations/<id-or-slug>.md` (merge if it exists) and summarize it in chat with the link.

## Root-cause report (every section present)
```
# <id or slug> — <one-line title>
Status: investigated · <date> · Confidence: confirmed | likely | unproven · Verified against: <repo> <sha> (+ uncommitted changes noted)
1. Symptom — what the user saw; steps; environment; expected vs actual.
2. How it was reproduced — exact command and real output, or why not reproducible.
3. Root cause — the mechanism, in plain words, with path:line. Cause vs symptom vs contributing conditions.
4. Evidence and alternatives ruled out.
5. Impact — who and what is affected: venue models, apps, data already wrong, permissions or tenant exposure, money or order integrity.
6. Fix options — the narrowest first, with the trade-off of each; what must NOT change (contracts, schema, money rules).
7. Tests the fix needs — the regression test that would have caught it, and where it belongs; which existing suites to run.
8. Approvals the fix needs — migration, payment or order-state change, contract change, anything reaching xorder-cloud main.
9. Open questions and what could not be verified.
```

## Rules
- No fix, no refactor, no edit to application code, tests or docs outside the report. If the user asks for the fix in the same message, finish the report first, then continue with `/implement`.
- Never run `migrate:fresh`, `migrate:rollback`, restores, or anything against a non-test database; never read `db-backups/`.
- An unproven cause is reported as unproven. A wrong confident answer costs more than an honest "likely".
- Security, tenancy, money or order-integrity findings are also routed to `/security-audit`.

Output format: `.claude/rules/reporting.md`. Follow workspace `CLAUDE.md` approval rules.
