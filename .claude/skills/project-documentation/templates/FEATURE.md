# Feature specification: <feature title>

Status: implemented / partially implemented / proposed / partially verified
Slug: `<slug>` · Module: `<module>` · Footprint: cloud-only / pos-only / shared / shared-model
Verified against: <date> · cloud `<HEAD>` · POS `<HEAD>`

Headings below keep the order of `docs/templates/FEATURE.md`; the sections marked (+) are added by `/project-documentation`. Mark unverified statements **UNVERIFIED** and cite `path:line` for everything else.

## Summary
(Feature overview and purpose: who uses it, what problem it solves.)

## Scope and exclusions
(What is implemented and what is not. State Implemented / Partial / Proposed for each capability.)

## Actors and permissions
| Actor | Permission / capability / role key | Enforced by (gate, middleware, POS permission) | Evidence |
| --- | --- | --- | --- |

## Current implemented behavior (+)
(What the system does today, step by step, from the code. Separate cloud and POS where they differ.)

## User journeys and workflows (+)
(Short numbered journeys per actor; long or branching ones go in `WORKFLOWS.md`.)

## Cloud flow
(Routes → middleware → controller → service → models; Vue pages and stores. Cite.)

## Desktop POS flow
(Screens → providers → domain services → repositories → cloud client. "Not applicable" if cloud-only. Cite.)

## Business rules
| ID | Rule (testable) | Where implemented | Evidence |
| --- | --- | --- | --- |
| BR-1 | | | |

## Validation and error handling (+)
| Input / situation | Validation or check | Result shown (message key / HTTP code / POS failure type) | Evidence |
| --- | --- | --- | --- |

## Edge cases and failure handling
(Rounding, empty and boundary values, concurrent edits, duplicate submissions and idempotency, permission changes mid-session, network or branch-database failure, time zones, Arabic/English and RTL where behavior depends on it.)

## Cross-application dependencies (+)
(Endpoints the POS uses, shared entities, sync mode and direction, contract IDs and status, authority for prices/totals/transitions, rollout order. "None" if cloud-only or pos-only, with evidence.)

## Security considerations (+)
(Authentication, authorization and tenant isolation, input validation, rate limiting, audit logging, secrets and PII handling, known weaknesses as evidenced findings.)

## Existing automated tests (+)
| Layer | File and test name | Covers | Gaps |
| --- | --- | --- | --- |
(Results only from real runs in `docs/testing/reports/*`; otherwise "not run".)

## Known limitations (+)
(Behavior that is deliberately or knowingly incomplete: relaxations, missing capabilities, accepted risks, with evidence. Bug investigators and reviewers read this first.)

## Acceptance criteria
- AC-1: 

## Confirmed source references
(Relevant source references — the evidence index for this feature: routes, controllers, services, models, migrations, Vue files, POS files, contract documents. One bullet each, `path:line` plus the symbol.)

## Unknowns and assumptions
(UNVERIFIED items, contradictions between prose docs and code, questions for the owner.)
