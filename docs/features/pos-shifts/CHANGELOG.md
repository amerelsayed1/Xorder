# Feature changelog: POS shifts and cash movements

## 2026-10-20 — documentation created
- Status: documented from existing implementation (no code change).
- Changes: initial FEATURE, TECHNICAL, API, DATABASE, TEST_PLAN, TEST_REPORT, WORKFLOWS written by the `/project-documentation` integration dry run, against cloud `06bc8e3` and POS `d592db8`.
- Compatibility notes: none; documentation only.
- Verification: citations mechanically checked in the dry run; see `docs/harness/KNOWLEDGE_INTEGRATION_REPORT.md`. Tests: not run for this feature (see TEST_REPORT).

## 2026-10-20 — corrected after independent validation
- Status: documentation corrected (no code change).
- Changes: fixed 6 wrong claims (permission enforcement layers, `pos.device` feature gate, validation envelope, drain quarantine/defer policy, test-gap claims, header dirty-file note); added BR-12/AC-10, contract divergences, cash policy, handover approval being local only, other consumers of cash movements, DATABASE completeness. Details: `docs/validation/2026-10-20-pos-shifts-validation-report.md`.
- Compatibility notes: none; documentation only.
- Verification: author re-checked each fix against source; independent re-validation pending. Tests: not run for this feature.

## 2026-10-20 — corrected after second independent validation
- Status: documentation corrected (no code change).
- Changes: fixed 7 wrong claims (payment/refund shift attribution paths, blind-close permission keys, deferred `shift_open` behavior and the multi-shift backlog case, voided-order handling in POS expected cash, inventory dirty-file note, test-gap wording, `classify` test citation); added dashboard `hasPos` gate, POS schema items, `shift_close` queuing condition and other resolved unknowns. Details: `docs/validation/2026-10-20-pos-shifts-revalidation-report.md`.
- Compatibility notes: none; documentation only.
- Verification: author re-checked each fix against source; a third independent pass is pending. Tests: not run for this feature.

## 2026-10-20 — corrected after third independent validation
- Status: documentation corrected (no code change). Not promoted to `validated`.
- Changes: fixed 4 wrong claims (voided-order cash divergence that cannot occur; "drain sends the close last" overstated as a guarantee; incomplete multi-shift backlog case; drain policy missing local quarantine/wait paths) and 2 stale items (AC-10 test row, a migration listed as touching `pos_shifts`); added the 25-row window and missing close-after-orders check, absent-key behavior, supplier pay-out gate, replay-before-capability for all three writes. Details: `docs/validation/2026-10-20-pos-shifts-round3-validation-report.md`.
- Compatibility notes: none; documentation only.
- Verification: author re-checked each fix against source; a fourth independent pass is pending. Tests: not run for this feature.

## 2026-10-20 — corrected after fourth independent validation
- Status: documentation corrected (no code change). Not promoted to `validated`.
- Changes: fixed 3 wrong claims (post-close Z-report mask is independent of the blind-close policy; deferred `shift_open` clears when the terminal has no open shift on the cloud; movement starvation also applies to a shift already closed) and added supervisor-lent permissions not honoured by the cloud, who holds `shift.view_expected_cash`/`cash.variance.view` on a cloud till, pass timing, wider local-quarantine scope, `drawer_open` storage, supplier pay-out gate details, refund-drain tests. Details: `docs/validation/2026-10-20-pos-shifts-round4-validation-report.md`.
- Compatibility notes: none; documentation only.
- Verification: author re-checked each fix against source; a fifth pass is pending. Tests: not run for this feature.

## 2026-10-20 — corrected after fifth independent validation
- Status: documentation corrected (no code change). Not promoted to `validated`.
- Changes: fixed 5 wrong claims (drain retry cadence; multi-shift scenario 2 contradiction; where a lent-permission approver is stored and which keys the cloud rejects; how cloud-arrived staff can hold the variance keys; the shared child-till topology) and added exception-in-run behavior, history-pane masking detail, wider local-quarantine scope, supplier reversal and branch-shift caveats, missing post-close mask test. Details: `docs/validation/2026-10-20-pos-shifts-round5-validation-report.md`.
- Compatibility notes: none; documentation only.
- Verification: author re-checked each fix against source. Tests: not run for this feature.

## 2026-10-20 — split into validated-scope core and unvalidated behavioral analysis
- Status: documentation restructured (no code change). Core: `drafted`, awaiting a validation pass; analysis: `unvalidated`.
- Changes: multi-step traced conclusions (drain ordering and windows, multi-shift backlog, retry cadence and exceptions, lent permissions, variance-key holders, expected-cash divergences, `open` branch mismatch, concurrency, topology, supplier pay-out shift choice) moved from `FEATURE.md`, `WORKFLOWS.md`, `TECHNICAL.md`, `DATABASE.md` and `TEST_PLAN.md` into `BEHAVIORAL_ANALYSIS.md`; the core keeps single-location facts, tests, absences and unknowns and points to the analysis. Rule added to `.claude/skills/project-documentation/references/documentation-standards.md` and `validation-rules.md`.
- Compatibility notes: none; documentation only.
- Verification: mechanical checks pass (175 citations resolve); independent validation of the core pending. Tests: not run for this feature.

## 2026-10-20 — corrected after sixth and seventh independent validation (core only)
- Status: documentation corrected (no code change). Core not promoted to `validated`.
- Changes: round 6 (core only, after the split): fixed a superseded trigger citation, an `opened_with_approval_by` reader claim, a stale test-gap row and a misdescribed recorded grep; moved seven conclusions to `BEHAVIORAL_ANALYSIS.md`. Round 7 (core only): replaced the terminal-delete "no money history" sentence by the exact guard conditions (`PosProvisioningService.php:393-409`), reconciled the header state, removed ordering/concurrency guarantees from `TECHNICAL.md`, `API.md`, `WORKFLOWS.md` and the module doc, expanded 21 shorthand citations to full paths, listed missing call sites, tests and consumers, aligned BR-12 with AC-10. Details: `docs/validation/2026-10-20-pos-shifts-round6-core-validation-report.md`, `...-round7-core-validation-report.md`.
- Compatibility notes: none; documentation only.
- Verification: author re-checked each fix against source. Tests: not run for this feature.

## 2026-10-20 — corrected after eighth independent validation (core only)
- Status: documentation corrected (no code change). Core not promoted to `validated`.
- Changes: corrected the pane attribution of the over/short mask test, the `shift.close` prompt citations, the post-close subtitle omission; added the licence gate on opening, `pos.shift_required`, the tenant-context line in the device middleware, history-list visibility, precise terminal-delete test descriptions; reworded two ordering sentences in `WORKFLOWS.md`. Details: `docs/validation/2026-10-20-pos-shifts-round8-core-validation-report.md`.
- Compatibility notes: none; documentation only.
- Verification: author re-checked each fix against source. Tests: not run for this feature.

## 2026-10-20 — corrected after ninth independent validation (first qualifying pass)
- Status: documentation corrected (no code change). Core not promoted to `validated` (2 class-B findings).
- Changes: BR-8/AC-5 rewritten per side (cloud enforces an open shift; POS enforces it in the cash dialogs and the supplier pay-out repository, not in `record()` or the schema); error-envelope scope narrowed (PosApiException, validation on `api/pos/*`, licence-check throttle); added pay-out ceiling, `openShiftIdFor` stamping, close audit row, tenant-wide replay lookups, Vue consumers, recorded absence searches, column additions. Details: `docs/validation/2026-10-20-pos-shifts-round9-qualifying-pass-report.md`.
- Compatibility notes: none; documentation only.
- Verification: author re-checked each fix against source. Tests: not run for this feature.

## 2026-10-24 — amended for the business-day change (code change, not re-verified)
- Status: BR-13 and AC-11 added to FEATURE.md. The shift-open dialog (`P:lib/features/shift/presentation/shift_dialogs.dart`) and the lock screen now call the business-day service; both are evidence files of this feature, so the rest of this folder is **`needs verification`** against the new source.
- Compatibility notes: no contract, payload or migration change; the shift row is now filed under the open day by the existing trigger (migration 36).
- Verification: see `docs/features/pos-business-day/TEST_REPORT.md`.
