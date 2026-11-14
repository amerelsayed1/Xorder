# Documentation standards

## Where things live
| Artifact | Path (workspace root) |
|---|---|
| Platform overview, cross-application map | `docs/PROJECT_OVERVIEW.md` |
| Feature inventory (single index of modules and features) | `docs/FEATURE_INVENTORY.md` |
| Progress, plan, staleness data | `docs/DOCUMENTATION_PROGRESS.md` |
| One doc per module | `docs/modules/<module>.md` |
| Per-feature folder | `docs/features/<slug>/` |
| Validation reports | `docs/validation/<YYYY-MM-DD>-validation-report.md` |

Each feature folder keeps the **seven files** required by `scripts/harness/check-docs.py`: `FEATURE.md`, `TECHNICAL.md`, `API.md`, `DATABASE.md`, `TEST_PLAN.md`, `TEST_REPORT.md`, `CHANGELOG.md`, plus the optional `WORKFLOWS.md`. The skill's `FEATURE`, `TECHNICAL`, `API` and `DATABASE` templates extend `docs/templates/*` (every original heading is kept, in order, with extra sections added); `TEST_PLAN`, `TEST_REPORT` and `CHANGELOG` use `docs/templates/*` unchanged.

Create `docs/`, `docs/modules/` and `docs/validation/` when missing. Never write into `apps/*/docs/`.

## Evidence rules
- Cite as `apps/xorder-cloud/apps/api/routes/api.php:123` or a range `:123-140`, workspace-relative, with a symbol name when helpful (`...PosOrderService.php:88 (createOrder)`). Cite the narrowest lines that prove the claim.
- A claim without evidence is written as **UNVERIFIED: ...** and listed under *Unknowns and assumptions*. No "probably", no inferred endpoints.
- Distinguish three states and label them: **Implemented** (code present and reachable), **Partial** (present, incomplete or unreachable from UI/route), **Proposed** (only in docs or `PROPOSED` contract items). Document proposed items only in a clearly marked block.
- Tests: cite file and test name. State what the tests *do not* cover. Test results come only from real runs documented in `docs/testing/reports/*`; otherwise "not run".
- Record the date and the HEAD of each repo in the doc header (`Verified against:`).

## Content rules
- Describe **as-built** behavior. Intent, wishes and design docs belong in *Unknowns* with the discrepancy stated.
- Business rules are written as testable statements and numbered (`BR-1`...). Acceptance criteria are `AC-1`... and each maps to code or a test in `TEST_PLAN.md`.
- Roles use the real names from code: platform roles from `RoleEnum`, platform `Capability`, restaurant `TenantCapability`, tenant plan `Feature` entitlements, POS permissions (`permissions.dart`, `permission_resolver.dart`). List the exact gate / middleware / permission key.
- Money: say whether amounts are minor units or decimals, where rounding happens and who is authoritative (the backend is authoritative for prices, discounts, taxes, totals, permissions and order transitions).
- Tenancy: for every cloud resource state how the tenant boundary is enforced and where cross-tenant access is tested.
- Database: tables, columns, types, nullability, defaults, FKs, unique/indexes, tenant column, state enums, written from migrations (not from models). Note PostgreSQL vs SQLite differences. POS local database means the branch PostgreSQL schema in `lib/data/postgres/migrations.dart`.
- API: method and full path with prefix, middleware, request validation rules (from the FormRequest), response shape (redacted example taken from a Resource or a test), error format, idempotency behavior, and every consumer (Vue file, POS file).
- Security section per feature: authn/authz, tenant isolation, input validation, rate limits, secrets handled, PII handled, audit logging, known weaknesses (as findings, with evidence, not as speculation).
- Redact: tokens, passwords, keys, real phone numbers, emails, card or account numbers. Use obviously fake values (`rest_123`, `user@example.com`).

## Merge rules (existing docs)
1. Read the existing file first. Keep its headings and any content the source does not contradict.
2. Change only the sections whose claims no longer match the source; mark them `Updated: <date>`.
3. Text a human wrote that cannot be verified stays, tagged **UNVERIFIED (carried over)**.
4. Content between `<!-- manual:start -->` and `<!-- manual:end -->` is never edited.
5. Every change to an existing feature folder appends an entry to its `CHANGELOG.md` (date, what, why, evidence).
6. Never delete a doc. Obsolete features are marked `Removed in source <date>` in the inventory and the doc header.

## Style
Plain English, short sentences, tables for matrices (routes, permissions, tables). Arabic/English UI strings are quoted only where behavior depends on them. No marketing language. One idea per bullet. Keep each file focused; link between docs with relative paths.

## Core versus behavioral analysis
Experience with the first documented feature (five validation passes, 6, 7, 4, 3 and 5 wrong claims, `docs/validation/`) showed that facts tied to one location converge to correct, while multi-step traces keep producing errors. Therefore a feature's documentation has two parts:
- **Core** (`FEATURE.md`, `TECHNICAL.md`, `API.md`, `DATABASE.md`, `WORKFLOWS.md`, `TEST_PLAN.md`, `TEST_REPORT.md`, `CHANGELOG.md`): only single-location facts with `path:line` (what a route, function, constant, table, rule or test does or asserts), absences established by a recorded search, contract statuses, and open unknowns. No multi-pass sequences, ordering or timing guarantees, concurrency outcomes, failure cascades, consequences of divergences, or "can/would" predictions.
- **Behavioral analysis** (`BEHAVIORAL_ANALYSIS.md`, template `templates/BEHAVIORAL_ANALYSIS.md`): those traced conclusions, each with its trace, confidence and what would confirm it. It is labelled UNVALIDATED, is excluded from `validate`, and can never be cited as fact by other documents or skills. The core may point to it ("see BEHAVIORAL_ANALYSIS.md") but must not restate its conclusions.
When a reviewer finds a core statement that needs a trace to be true, move it to the analysis file instead of hedging it in place.
