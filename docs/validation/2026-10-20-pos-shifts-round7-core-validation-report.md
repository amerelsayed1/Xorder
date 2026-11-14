# Round 7 validation report: `pos-shifts` core (final-pass attempt)

Date: 2026-10-20 · Command: `validate pos-shifts` (core only; focus: the round-6 edit set; `BEHAVIORAL_ANALYSIS.md` excluded) · Repos: cloud `main 06bc8e3`, POS `main d592db8`
Freshness before validating: both HEADs unchanged, 0 committed changes since the documented revisions, the same uncommitted files (10 cloud, 11 POS). Mechanical checks: `check-docs.py` passes; 181 line-level citations resolve, 0 problems.
Validator: a fresh `code-reviewer` agent that did not read `docs/validation/`. The author verified each finding against source before acting.

## Result
Reviewer verdict: **core has 2 wrong/stale statements** (down from 4 in the previous core pass, and from 3-7 behavioral errors per pass in the combined-document passes). Also 3 belongs-in-analysis items, 1 imprecise test statement, 5 missing/incomplete items, 1 inconsistency, and style items. About 140 distinct claims, 90 opened-and-confirmed citations, all focus areas 1-10 and every re-run absence search were reported correct, including the shift attribution, phase order and 25-row reads, cash-policy and post-close mask claims, Actors paragraphs, classification and local-quarantine lists, test citations, contract statuses and the inventory "Absent" row. Because wrong statements were found, the core is **not promoted**.

## Findings and disposition (all author-verified, all fixed)
| # | Severity | Finding | Source evidence | Disposition |
| --- | --- | --- | --- | --- |
| W1 | wrong | `DATABASE.md` repeated the code comment that terminal deletion is limited to terminals "with no money history"; the guard only blocks on a closed/counted/floated shift or any order, and does not look at cash movements, which cascade with the shift | `C:app/Services/PosProvisioningService.php:393-409`; migration `2026_09_02_000900:53` | replaced by the exact guard conditions and test citations |
| S1 | stale | header sentence "core has not been through a validation pass since the split" contradicted the same line and the changelog | | reconciled; CHANGELOG entry added |
| A1-A3 | belongs in analysis | "dependency order", "serialised", and ordering stated without the pass bound (`wentOffline` stops a pass) | `P:lib/data/cloud/outbox_drain.dart:280-296` | reworded to the code facts with pointers |
| T1 | imprecise | `close_shift_blind_test.dart:164-173` described too narrowly; the conclusion "post-close mask has no test" is correct | | reworded |
| M1-M5 | missing | other prompt call sites (`sale_screen.dart:290-296`, `cash_dialogs.dart:358-362`); terminal-delete tests; `PosCashMovement` also audited; heartbeat flag persisted and exposed by the cloud; integration-tagged tests listed as domain/widget | | added |
| I1 | inconsistency | BR-12 said "names none", AC-10 "does not resolve" | `PosOrderService.php:444` | aligned |
| style | style | 21 shorthand citations (`C:PosShiftService.php:`) did not resolve under the prefix rules; `outbox_drain.dart:686` vs 687; test range 241-293 vs 241-290; unknown count | | all expanded/fixed; the mechanical check now flags shorthand citations (0 remain, 218 citations resolve) |

## Not checked
`BEHAVIORAL_ANALYSIS.md` (by design); runtime behavior (nothing executed); `SupplierLedgerService.php` beyond lines 328-351; the localized strings.

## Status decision and trend
Core stays **`drafted`**: the rule requires a pass that finds nothing wrong. Core-only passes found 4 and then 2 errors, none about shift, cash or sync behavior (the first was citation/wording, this one a copied code comment, a stale header sentence and missing coverage). The earlier combined-document passes found 6, 7, 4, 3 and 5 behavioral errors. Remaining defects are now of the kind a mechanical check can partly catch (shorthand citations are now detected). One more core pass on the round-7 edits is the way to reach `validated`; further passes should be expected to find a small number of coverage/wording items each time, so the owner may reasonably decide to accept `drafted` for the core as a reference with its report trail.
