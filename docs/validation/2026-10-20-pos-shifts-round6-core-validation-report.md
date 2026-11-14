# Round 6 validation report: `pos-shifts` core (after the core/analysis split)

Date: 2026-10-20 · Command: `validate pos-shifts` (core only; `BEHAVIORAL_ANALYSIS.md` excluded by rule) · Repos: cloud `main 06bc8e3`, POS `main d592db8`
Freshness before validating: both HEADs unchanged, 0 committed changes since the documented revisions, the same uncommitted files (10 cloud, 11 POS). Mechanical checks after the split: `check-docs.py` passes; 175 line-level citations resolve, 0 problems.
Validator: a fresh `feature-analyst` agent that did not read `docs/validation/`; it ran the mechanical checks, read the cited source and tests, and re-ran absence searches. The author verified every finding against source.

## Split performed before this pass
Multi-step traced conclusions were moved from `FEATURE.md`, `WORKFLOWS.md`, `TECHNICAL.md`, `DATABASE.md` and `TEST_PLAN.md` into `docs/features/pos-shifts/BEHAVIORAL_ANALYSIS.md` (sections A-L; section M added after this review): drain ordering and windows, multi-shift backlog, retry cadence and exceptions, lent permissions, variance-key holders, expected-cash divergences, `open` branch mismatch, concurrency, topology, supplier pay-out shift choice. Rule and template added to the skill (`references/documentation-standards.md` "Core versus behavioral analysis", `references/validation-rules.md` "Scope: core only", `templates/BEHAVIORAL_ANALYSIS.md`), and `check-harness.py` requires the template.

## Result
Reviewer verdict: **core has 4 wrong/stale statements, all low severity; no statement about shift, cash or sync behavior was found false.** Also 7 core statements that belonged in the analysis, 4 missing items, 7 style items. About 150 citations and all of BR-1..BR-12, AC-1..AC-10, the 5 routes, permission call sites, cloud and POS schema, tests, contract statuses and absence claims were confirmed correct. Because wrong statements were found, the core is **not promoted**; it stays `drafted`.

## Findings and disposition (all author-verified, all fixed)
| # | Severity | Finding | Source evidence | Disposition |
| --- | --- | --- | --- | --- |
| 1 | stale | trigger `pos_shifts_business_day` cited at its superseded definition | `P:lib/data/postgres/migrations.dart:3390-3393` (dropped and re-created with `pos_stamp_business_day('opened_at')`) | DATABASE fixed |
| 2 | wrong wording | `opened_with_approval_by` "no reader outside migrations": a test writes and reads it | `P:test/data/business_day_schema_test.dart:434-439` | DATABASE fixed |
| 3 | stale gap | "zero variance needs no reason" listed as a planned test; it is exercised | `C:tests/Feature/Pos/PosShiftsTest.php:60-68,191-198` | TEST_PLAN fixed |
| 4 | wrong description of a recorded search | `grep -in shift routes/api.php` does not find the stats tile; it finds the import, comments and 5 routes | `routes/api.php:65,227,667,749,814-818` | inventory "Absent" row fixed, second grep recorded |
| belongs in analysis (7) | | payment inheriting a closed shift; "delivery not guaranteed"; replay still gets 200; "any terminal can close"; "cannot depend on variance"; "never closes on the cloud"; terminal-delete inference | | reworded to facts; conclusions moved to analysis M |
| missing (4) | | tests not listed (`wave_b_repositories_test.dart:498,512`, `authorization_test.dart:241-293`, `drawer_open_flow_test.dart`, `shift_history_test.dart`); `Auditable` `deleted` event; supplier-payment create path (`SupplierLedgerService.php:275-359`, `StoreSupplierPaymentRequest.php:49`) | | added |
| style (7) | | `shift_history_providers.dart:38`, `PosOrderService.php:96` citation, BR-7 wording, exact dirty-file list, unknown count, `(+)` marker, TEST_REPORT header, blind-close writer in a test | | fixed |

## Not checked
`BEHAVIORAL_ANALYSIS.md` content (by design), `docs/validation/*`, runtime behavior (nothing executed), other features' rows, every one of about 190 distinct citations individually.

## Status decision
Core stays **`drafted`** (rule: promotion needs a pass that finds nothing wrong). The pass found only citation-level and wording errors, none about behavior, which is the convergence the split was meant to produce (earlier combined-document passes: 6, 7, 4, 3, 5 wrong claims about behavior). Remaining step: one final core pass focused on this round's edit set; promote the core to `validated` if it finds nothing wrong. The analysis file stays `unvalidated`.
