# Round 9 validation report: `pos-shifts` core (first pass under the owner-approved criterion)

Date: 2026-10-20 · Command: `validate pos-shifts` (core only; full coverage categories (a)-(j) required by `references/validation-rules.md` *Criterion for `validated`*) · Repos: cloud `main 06bc8e3`, POS `main d592db8`
Freshness before validating: both HEADs unchanged, 0 committed changes since the documented revisions, same uncommitted files (10 cloud, 11 POS). Mechanical checks: `check-citations.py` 203 line citations, 0 shorthand, 0 problems; `check-docs.py` OK.
Validator: a fresh `code-reviewer` agent that did not read `docs/validation/` (about 150 tool calls, roughly 330k tokens). The author verified both class-B findings against source.

## Result: criterion NOT met
Reviewer: **class-B findings: 2**, class-N findings: 16. The author confirmed both class-B findings by reading the source, so the pass does not qualify and `pos-shifts` stays **`drafted`**. Per the criterion, a confirmed class-B finding requires a new pass even though it is now fixed.
Coverage the reviewer reported (all ten categories were covered): 22 BR/AC items read against code (20 correct); about 40 route/middleware/permission statements correct; about 85 schema items correct; about 35 error/validation items (34 correct, 1 class B); 12 contract claims correct; about 60 test locations opened, all attributions correct; 16 absence claims re-searched, all hold; headers and cross-file consistency correct except two wording items.

## Class-B findings (author-confirmed, fixed)
| # | Finding | Source evidence | Fix |
| --- | --- | --- | --- |
| B1 | BR-8/AC-5 said cash movements need an open shift on both sides (POS "shift_id NOT NULL"). On the POS the schema only requires a shift id and `record()` checks only the permission; the open-shift requirement is a UI check in the cash dialogs and a repository check only on the supplier pay-out path. Pattern: enforcement placed in the wrong layer (*Drafting errors* item 1). | `P:lib/data/postgres/postgres_cash_movements_repository.dart:139-218`; `P:lib/features/cash/presentation/cash_dialogs.dart:299-302,369-373`; `P:lib/data/postgres/postgres_supplier_invoices_repository.dart:793-801` | BR-8, AC-5 and WF text rewritten per side |
| B2 | "Error envelope for every 4xx under /api/pos/*": only `PosApiException`, validation failures on `api/pos/*` and the licence-check throttle have the `code` envelope; the shift group's own 429 and framework 404/401 do not. Pattern: intent taken as built behavior (item 6). | `C:bootstrap/app.php:75-85,90-99`; `C:app/Exceptions/PosApiException.php:30-39` | paragraph and API.md rewritten |

## Class-N findings (16, all fixed or recorded)
Stale pass counts in headers; stale "consumer unknown" wording; `PosCashMovement` also audited; pay-out ceiling `cash.pay_out_max_minor` and `cash.pay_out.max`; `openShiftIdFor` stamping; Vue consumers (`SupplierPaymentForm.vue`, `RoleForm.vue`); recorded searches for the consumer/Vue absence claims (added to the inventory "Absent" table); imprecise ranges (`ZReportView` from `:691`, `bootstrap/app.php:75-85`); the `IDEMPOTENCY_PAYLOAD_MISMATCH` line list (`:167`); uncited summary sentences (left; each is supported by the code the reviewer read); the close audit row; incomplete DATABASE column lists; tenant-wide open/movement replay lookups; Settlements pane gate; related tests not listed (heartbeat test sends but does not assert `shift_open`) — items N10, N13, N14 only partly addressed (see below).
Not applied: N10's uncited summary sentences and its FEATURE.md "422 ... drain quarantines" parenthetical (a multi-step trace; to be moved to the analysis file at the next edit); N13's FormRequest `authorize()` wording; N14's extra test list.

## Not checked
Runtime behavior; `BEHAVIORAL_ANALYSIS.md`; unprefixed short citations (not machine-checkable); Arabic strings; `ShiftReportDialog` internals; PostgreSQL behavior.

## Status decision
`drafted`. The qualifying-pass criterion has now been applied twice in spirit (round 8 had one unsupported behavioral statement; round 9 had two enforcement/envelope overstatements). Both round-9 class-B findings are the same families as errors found before (wrong enforcement layer, intent as built behavior), which shows the reviewers' wider checks keep finding another instance each time. A further pass would be expected to find a few more class-N items and possibly another class-B. Cost per pass: about 330k tokens.
Options: another qualifying pass (round 10); or keep `pos-shifts` at `drafted` and move on, using it with the freshness/spot-check protocol; the owner decides. No change to the criterion was made.
