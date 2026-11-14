# Validation rules (`validate`, and the self-check at the end of `feature`)

Validation compares documentation with source. It does not edit feature docs; it reports, and sets statuses. Corrections are made by `update` or `feature <name>`.

Prefer a validator that did not write the docs (a fresh `feature-analyst` or `code-reviewer` agent given the doc and the source, not your notes). Open the cited lines yourself for every finding you report; an agent's claim alone is not evidence.

## Scope: core only
`validate` checks the core files of a feature. `BEHAVIORAL_ANALYSIS.md` is excluded: do not validate it and do not count its content toward `validated`. Check that no core file restates an analysis conclusion as fact and that core statements do not depend on a multi-step trace (see `documentation-standards.md`, *Core versus behavioral analysis*). The inventory records the two states separately (`core: validated`, `analysis: unvalidated`).

## Criterion for `validated` (owner-approved decision, 2026-10-20)
**Decision record.** Proposed by Claude after eight independent passes on the first documented feature (`pos-shifts`; combined document: 6, 7, 4, 3 and 5 behavioral errors, core only: 4, 2 and 3 errors; reports in `docs/validation/`) showed that "no finding at all" is not a stable target: every fresh reviewer extends the checks (test bodies, expanded citations, other call sites) and finds a few new defects, almost all in citations, test attributions and omissions. Approved by the owner in chat on 2026-10-20 (instruction: propose a precise change, write it into the skill rules as an explicit owner-approved decision, apply it to `pos-shifts`). It replaces the earlier wording "no open wrong/stale finding". Any further change to this criterion needs the owner.

**Finding classes.** The reviewer classifies; the author confirms each finding by reading the source and records the reason for any reclassification (the owner may contest it).
- **B, behavioral:** a statement about what the system does, enforces, stores, exposes, rejects or promises (rules, permissions and where they are enforced, routes and middleware, error behavior, schema and constraints, state transitions, sync and contract behavior, an absence claim that a search shows to be false) that the source contradicts, or that is unsupported but stated as fact.
- **N, non-behavioral:** a wrong or imprecise citation (line range, prefix, symbol); a wrong attribution of a test or of its coverage; missing coverage (an omitted fact, test, consumer or call site); a statement that belongs in the analysis file (reworded or moved); wording, counts, headers and style.

**`validated` (core) requires all of:**
1. A qualifying pass: a fresh independent reviewer who did not write the docs, core scope, covering every BR and AC, every route/middleware/permission statement, schema statement, error behavior, contract status, test citation and absence claim of the feature (focus on recent edits plus a lighter pass elsewhere does not qualify unless the report shows all those categories were covered). The report is stored in `docs/validation/`.
2. After the author's source check, that pass has **zero class-B findings**. A reviewer finding that the author shows to be false does not count; a confirmed class-B finding does, even if fixed afterwards (then a new pass is needed).
3. All class-N findings of that pass are fixed, and `python3 scripts/harness/check-citations.py` and `python3 scripts/harness/check-docs.py` pass (0 broken citations, 0 shorthand citations).
4. After the pass, new behavioral statements may be added only if each is a single-location fact that the author read at the cited line and lists in the promotion record as "not independently reviewed". Changing or removing an existing behavioral statement, or adding anything that needs a trace, requires a new pass.
5. A promotion record `docs/validation/<date>-<slug>-promotion-record.md` states: the criterion version, the qualifying pass, its findings with class and author confirmation, the post-pass additions, the mechanical-check output, and the sentence "the last independent pass found no wrong or stale statement about system behavior; this does not claim zero residual errors".
The inventory and progress file then show `validated` together with the date, the report names and the number of unreviewed post-pass additions.

**`validated` is lost** (the feature returns to `drafted`, or `stale` when the source changed) when: a core edit changes or removes a behavioral statement, or adds one that is not a listed single-location fact, without a new qualifying pass; evidence files change in either repo; or a later pass finds a class-B error. Class-N-only edits keep `validated` while the mechanical checks pass. `BEHAVIORAL_ANALYSIS.md` is never validated.

## Mechanical checks (run for every feature in scope)
1. **Structure.** The seven files exist (`python3 scripts/harness/check-docs.py`); required headings from the templates are present; the header has `Verified against:` with repo HEADs.
2. **Citations.** Run `python3 scripts/harness/check-citations.py` (existence, line range, shorthand). Every `path:line` points to a file that exists and a line within its length. The cited symbol, route or table name occurs on that line or within 5 lines. Report moved (found elsewhere in the file) vs gone.
3. **Routes.** Every method+path in `API.md` exists in `routes/api.php` or `web.php` with the documented middleware and controller. Conversely, routes of the feature's controllers that are missing from `API.md` are findings (completeness). Resolve group prefixes before comparing.
4. **Permissions.** Every capability, role, feature key or POS permission named exists in `Capability`, `TenantCapability`, `RoleEnum`, `Feature` or `permissions.dart`, and the middleware/gate named is actually applied to that route.
5. **Tables and columns.** Every table and column in `DATABASE.md` is created or altered by an existing migration (cloud `database/migrations`, POS `lib/data/postgres/migrations.dart`). Types, nullability, FKs and unique constraints match. Dropped or renamed columns are findings.
6. **Tests.** Every test file or test name cited exists. Tests listed as covering an `AC-n` actually exercise it (read the assertion). Report acceptance criteria with no test.
7. **Contracts.** Contract IDs (`POS-BE-xxx`, `CB-xx`) exist in the coordination docs with the stated status; documented behavior is not taken from a `PROPOSED` item. Where the two copies of a coordination doc disagree, say which copy was used.
8. **Cross-application claims.** Every "POS calls X" has the call site in `lib/data/cloud/*` (or elsewhere in `apps/xorder-pos/lib`) and the matching cloud route; every "Vue calls X" has the call in `apps/*/src` or `packages/api-client/src`.
9. **Absence claims.** "No X exists" claims (no policies, no queue, no offline order storage) are re-checked with a search whose command is recorded.
10. **Safety.** Grep the docs for secret-looking strings (`JWT_SECRET`, `password`, `Bearer ey`, `-----BEGIN`, 16+ digit numbers, real emails/phones) and for text copied from `.env*` or `db-backups`. Any hit is a finding.
11. **Inventory.** Every cloud route group and POS feature folder belongs to a feature or is listed as uncovered; every inventory row has a doc path that exists.

## Judgment checks (sample, do not skip)
- Business rules: for the 3 riskiest rules per feature (money, order state, permissions) read the implementing code and confirm the wording. Check boundary conditions (rounding, zero, null, rejected states).
- Workflows: walk each documented journey through the code path; flag steps with no implementation and implemented steps that are undocumented.
- Edge cases and error handling: confirm the listed errors really occur (validation rules, exceptions, HTTP codes) and look for obvious unlisted ones.
- Cloud vs POS differences: confirm a stated difference by reading both sides.

## Severity
| Level | Meaning |
|---|---|
| wrong | Doc contradicts the source (wrong route, rule, table, permission) |
| stale | Was right at the recorded HEAD, source has since changed |
| unverifiable | No evidence found either way; must be marked UNVERIFIED or removed |
| missing | Source behavior with no documentation (route, rule, screen, test gap) |
| style | Heading, format or citation hygiene |

`wrong` and `stale` set the feature to `stale`; features with none of these and with every unverifiable item correctly marked UNVERIFIED become `validated`.

## Report (`docs/validation/<date>-validation-report.md`)
Scope and repo HEADs; what was checked and **what was not**; a summary table (feature, checks passed/failed by number above, findings by severity, new status); findings ranked by severity each with doc `path:line`, source `path:line`, and the expected fix; commands used for greps; rate of agent claims confirmed vs rejected by your spot-checks. Never write "valid" for a check that was not performed.

## Drafting errors found in practice (check for these first)
Found by the independent review of the first documented feature (`docs/validation/2026-10-20-pos-shifts-validation-report.md`): 6 wrong claims in a draft that had passed the mechanical citation check.
1. **Enforcement placed in the wrong layer.** A permission was said to be enforced in a repository when the call exists only in a dialog, or in another repository. Grep for the check (`Authorization.`, `Gate::`, `can:`, `authorize`) and cite the call site, not the layer you assume.
2. **Gate "absent" stated without reading the middleware.** A route group said to have no feature gate was gated inside its middleware alias. Open the middleware class for every alias in the stack.
3. **Behavior marked UNVERIFIED that one grep resolves.** Error-envelope mapping, header usage, consumers of an endpoint. Search before leaving an UNVERIFIED marker.
4. **"No test" by test name only.** A test covered the criterion inside a differently named test. Read the test bodies of the feature's test file before declaring a gap, and search sibling features' tests (refunds, orders, stats) for the same behavior.
5. **Over-general failure handling** ("the drain quarantines rejections"). Cite the classification table and list both sides.
6. **Contract text taken as built behavior.** Compare the contract section with the code and list divergences; check the status of every referenced contract ID (READY vs APPROVED).
7. **Header facts about uncommitted files.** Say exactly which files were dirty, from `git status --short`.
8. **Ordering described as a guarantee.** "The drain sends X before Y" was written as if Y could not overtake X. Trace what bounds a pass (row limits, deferred rows kept in the query, missing prerequisite checks) before calling an order a guarantee, and write multi-step failure scenarios for every combination of states, not only the first one you think of.
9. **Divergences between two implementations that the data model forbids.** Check that the state that would create the difference can occur (for example whether voided orders can have payment rows) before documenting it.
10. **Claims relayed from another agent or from your own inference.** Two round-2 errors were carried forward unread. Open the code before copying a claim into a doc, and mark inferences "from reading, not tested".
11. **A rule stated for both applications but enforced on one.** For every business rule, find the enforcement call site on each side; the schema, a UI check and a repository check are three different layers. Say which one holds the rule on each side.
12. **"Every" and "all" in prose.** "Every 4xx has the envelope" was false because of framework defaults. Replace universal quantifiers by the list of cases that were checked.
Citations that exist and are in range prove nothing about meaning; the mechanical check is necessary, not sufficient.
