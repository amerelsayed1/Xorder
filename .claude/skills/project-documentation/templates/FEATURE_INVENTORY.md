# Feature inventory

Index of the platform knowledge layer. Looked up by `/project-documentation context` and by every lifecycle skill. Keep it greppable: one summary row and one block per feature, slug always in backticks.
Maintained by `/project-documentation scan`, `feature`, `update`, `validate`. Status values: `references/progress-management.md`. Live progress: `docs/DOCUMENTATION_PROGRESS.md`.

Scan depth: <seed (directory level) | route level | full>  ·  Last scan: <date>  ·  Baseline: cloud `<branch> <sha>` · POS `<branch> <sha>`

Footprint: `cloud-only` · `pos-only` · `shared` (talk through the API) · `shared-model` (same entity, no direct API) · `UNVERIFIED` (not yet traced).
Verification: `UNVERIFIED` (not documented) · `drafted` (written, self-checked) · `validated` (checked by `validate` against the revision shown) · `stale` (source changed or validation found drift).

## Modules
| Module | Description (one line) | Features | Module doc |
| --- | --- | --- | --- |

## Features (summary)
| Slug | Module | Title | Footprint | Doc status | Verification | Cloud rev | POS rev | Docs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |

## Feature blocks
One block per feature. Paths are workspace-relative. A seed block may hold only entry points and `Verification: UNVERIFIED`.

### `<slug>`
- **Module / title / footprint:** 
- **Cloud implementation:** routes (`<METHOD> <path>` with `routes/api.php:<line>`), controllers, requests, services, models, enums/capabilities, commands, Vue pages/stores
- **Desktop implementation:** features/screens, providers, domain services, repositories, cloud client files
- **Relevant source files (evidence list, used by freshness checks):** 
- **Business rules and workflows:** `FEATURE.md` BR-/AC- ids; `WORKFLOWS.md` WF- ids
- **API contracts:** endpoints, contract IDs and status (READY / APPROVED / PROPOSED)
- **Database dependencies:** cloud tables; POS tables; shared entities
- **Related features:** `<slug>` (why)
- **Existing tests:** cloud files; POS files; integration; known gaps
- **Documentation status:** `docs/features/<slug>/` (files present), module doc
- **Source revision:** cloud `<sha>` · POS `<sha>` (uncommitted evidence files at that time: none / list) · documented `<date>`
- **Verification status:** core `<status>` · analysis `<none | unvalidated>` · last validated `<date or never>` · open unknowns `<n>`

## Uncovered source
| Path or route | Kind (route / page / screen / command / table) | Candidate feature | Note |
| --- | --- | --- | --- |

## Absent (searched, not found)
| Looked for | Search used | Result |
| --- | --- | --- |
