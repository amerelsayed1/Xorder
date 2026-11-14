# Round 5 validation report: `pos-shifts`

Date: 2026-10-20 · Command: `validate pos-shifts` (fifth pass; requested focus: the round-4 additions) · Repos: cloud `main 06bc8e3`, POS `main d592db8`
Freshness before validating: both HEADs unchanged, 0 committed changes since the documented revisions, the same uncommitted files (10 cloud, 11 POS). Mechanical checks: `check-docs.py` passes; 158 line-level citations resolve, 0 problems.
Validator: a fresh `code-reviewer` agent that did not read `docs/validation/`. The author verified each finding it used against source (`cloud_sync.dart` settled rule, `providers.dart` scheduling, `postgres_cash_movements_repository.dart` `approved_by_id`, `ManagedByPlatform` guard, child-device topology, run() exception path).

## Result
**5 wrong, 2 unverifiable, 5 missing/under-stated, style.** All fixed. Area verdicts from the reviewer: A (actors and absent-key text) not clean; B (cash movements, policy) nearly clean; C (edge cases, scenarios, timing, unknowns) not clean; D (BR-2, BR-12, AC-9/AC-10) clean with two style notes. Because wrong statements were found, the feature stays **`drafted`**.

## Findings and disposition
| # | Severity | Finding | Source evidence (author-verified) | Disposition |
| --- | --- | --- | --- | --- |
| W1 | wrong | Retry cadence: 30 minutes applies only after an unsettled pass (platform unreachable, token rejected, offline, or at least one deferred row); otherwise 4 hours; automatic policy only; first pass 5 s after start | `P:lib/data/cloud/cloud_sync.dart:30-43`; `P:lib/app/providers.dart:721-747` | fixed (FEATURE, TECHNICAL) |
| W2 | wrong | Scenario 2 said a deferred open "never" clears; B's open clears in pass 2, what never clears is any later open because B stays open | `PosShiftService.php:63-69` | fixed |
| W3 | wrong | "Approver kept in the local audit only": true for a close, but for a lent cash movement it is also stored on the movement row; `cash.open_without_sale` covers only `drawer_open`, which is never sent, so the cloud consequences concern `shift.close` and `cash.movement` | `postgres_cash_movements_repository.dart:154-160,185`; `postgres_shift_repository.dart:379-399`; `outbox_drain.dart:119-130` | fixed; consequence list extended |
| W4 | wrong (imprecise) | "Local role or grant": on a cloud till direct grants are managed by the platform and overwritten at each bootstrap, so only local roles, extra roles or per-person overrides apply | `P:lib/data/postgres/postgres_admin_repositories.dart:539-548`; `bootstrap_seeder.dart:467-470` | fixed |
| W5 | wrong | Multi-till premise: a child till of a cloud main device is a designed topology whose sales are carried by the main device's drain; the inference about concurrent shifts is documented as an inference | `P:lib/core/config/deployment.dart:24-26,201-204,321-323`; `providers.dart:600-602,661-662` | fixed |
| U1 | resolved | an exception in `OutboxDrain.run()` is uncaught and stops the self-rescheduling cadence until the provider is rebuilt | `cloud_sync.dart:173,202`; `providers.dart:711-715,741-743` | documented "from reading" |
| U2 | stale | inventory unknown count | | fixed |
| M1-M5 | missing | post-close mask has no test; history-pane masking detail; local quarantine for id mismatches and null shift ids; scenario 2 movements in pass 2; supplier reversal and branch-chosen shift caveats | `shift_dialogs.dart:598`; `management_shifts_pane.dart:101-127`; `outbox_drain.dart:637,680,741,791`; `postgres_supplier_invoices_repository.dart:826-828,1009-1034` | added |
| style | style | AC-10 "only" plus exception; BR-2 `bool_or` effect | | reworded |

## Status decision and process note
Stays **`drafted`**: a fifth pass found five wrong statements. The sequence of wrong-claim counts across five independent passes is 6, 7, 4, 3, 5. It has not converged: each correction adds more inference-heavy text (drain ordering, supervisor approvals, multi-till topology, exceptions) that the next reviewer re-derives and sometimes refutes, while the structural facts (routes, validation rules, tables, error codes, permissions call sites, BR-1 to BR-11 cores) were confirmed in every pass.
Options for the owner: (a) accept `drafted` with the full findings trail; (b) split the document into a factual core (validated to zero findings) and a clearly separated "behavioral analysis (from reading)" section excluded from validation; (c) another pass on the round-5 additions (expected cost about 200k subagent tokens, no guarantee of zero).
