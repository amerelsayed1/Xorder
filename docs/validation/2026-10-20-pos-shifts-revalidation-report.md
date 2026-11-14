# Re-validation report: `pos-shifts`

Date: 2026-10-20 · Command: `validate pos-shifts` (second pass) · Repos: cloud `main 06bc8e3`, POS `main d592db8`
Freshness check before validating: both HEADs unchanged since the docs were written; the uncommitted files in both repos are the same as recorded (docs, agent and script files, plus `management_screen.dart` and `cloud_purchasing_hidden_test.dart` in the POS repo); no evidence file changed.
Validator: a fresh `feature-analyst` agent that had not seen the first validation report or the author's notes; it read the docs and the source and ran its own searches. The author verified every finding below against source before acting on it.
Previous pass: `docs/validation/2026-10-20-pos-shifts-validation-report.md` (6 wrong, all fixed).

## Result
**7 wrong, 4 unverifiable-but-resolvable, 6 missing groups, 5 style.** All were fixed in this pass. Status stays **`drafted`** (see decision below).

Mechanical checks run by the author after the fixes: `check-docs.py` (structure and inventory link) passes; 143 line-level citations in the pilot docs and inventory resolve to existing files and in-range lines, 0 problems. The reviewer found the citation quality high (about 150 citations spot-checked, all load-bearing ones and every BR/AC cite) and confirmed the five routes, middleware chain, validation rules, error codes, all cloud DATABASE columns, the test line numbers and test bodies, the TEST_REPORT numbers, and the absence claims.

## Findings and disposition
| # | Severity | Finding | Source evidence (author-verified) | Disposition |
| --- | --- | --- | --- | --- |
| W1 | wrong | BR-12/AC-10 said a payment counts only if its order named an open shift. A payment resolves its own `shift_client_id` to an open shift and otherwise inherits the order's `pos_shift_id`, which may be closed. Refunds resolve their shift with no open filter | `C:app/Services/PosOrderService.php:321,444,503-513`; `PosRefundService.php:330-340` | fixed (BR-12, AC-10, behavior item 6, Known limitations, TEST_PLAN) |
| W2 | wrong | Blind close exemption was `cash.variance.view`; while counting it is `shift.view_expected_cash`, `cash.variance.view` governs the reveal after the count | `P:lib/features/shift/presentation/shift_dialogs.dart:274-276,591-598`; `permissions.dart:77,87`; `close_shift_blind_test.dart:164-173` | fixed (Actors, POS behavior item 5). Origin: a claim relayed by an earlier agent and not re-read by the author |
| W3 | wrong | "`SHIFT_ALREADY_OPEN` on `shift_open` does not clear by itself" was an inference that is false: a deferred row does not block later phases. The real consequence is the multi-shift backlog (B's open deferred, B's orders unattributed, B's movements retried) | `P:lib/data/cloud/outbox_drain.dart:295,543-560`; `PosShiftService.php:63-69`; `PosOrderService.php:503-513` | fixed (Edge cases, WORKFLOWS WF-4, TEST_PLAN AC-9); the backlog is marked "from reading, not tested". Origin: author inference |
| W4 | wrong | "POS excludes voided orders from sales figures" holds for order/sales totals but not for the tender totals that feed expected cash | `P:lib/data/postgres/postgres_shift_repository.dart:440-447,457-466` | fixed (BR-2) |
| W5 | wrong | Inventory said no uncommitted evidence files; `FEATURE.md` correctly listed the dirty coordination docs | `git status --short` | fixed (inventory) |
| W6 | wrong | Test-gap row listed the cross-branch report as covered and as a gap | `C:tests/Feature/Pos/PosShiftsTest.php:214-249` | fixed (reworded) |
| W7 | wrong | `classify` tests were cited for the whole quarantine/defer list; they assert a subset by name | `P:test/data/outbox_drain_test.dart:245-279` | fixed (FEATURE, API) |
| U1 | resolved | `day_close_dialog` does not close shifts; the only closer is the shift repository | `day_close_dialog.dart:251`; `grep "UPDATE pos_shifts"` → `postgres_shift_repository.dart:379` and a backfill | Unknowns updated |
| U2 | resolved | `manager_approval_test.dart` tests the generic supervisor override only; AC-6 widget gap stands | reviewer read the file | TEST_PLAN, FEATURE |
| U3 | resolved | No migration adds a `pos_shifts(branch_id)` index | `grep -ln pos_shifts database/migrations` → 3 files, none adds it | DATABASE |
| U4 | resolved | No code writes `cash.blind_close` | `grep` in `lib`/`bin` → constant and reader only | FEATURE Unknowns |
| M1 | missing | POS schema items: `business_day_id`, `opened_with_approval_by`, trigger `pos_shifts_business_day`, `pos_orders_shift_idx`, `pos_refunds.shift_id`, partial unique indexes | `P:lib/data/postgres/migrations.dart:330,1151,1560,1566,3291-3293,4338-4346` | DATABASE |
| M2 | missing | `shift_close` queued only if the shift has a `client_transaction_id` | `postgres_shift_repository.dart:373-376` | FEATURE (limitations), TECHNICAL |
| M3 | missing | Refund shift attribution has no open filter | `PosRefundService.php:330-340` | FEATURE |
| M4 | missing | Dashboard panel hidden by `hasPos`; the endpoint has no `pos` gate; `HomeView.vue:38` is the flag, not `analytics.view` | `HomeView.vue:38,403`; `StatsController.php:75,132` | FEATURE (Actors) |
| M5 | missing | extra test evidence (terminal-delete guard tests, sibling capability tests) | reviewer-cited test lines; **not independently verified by the author** | not added to the docs; listed here as a lead |
| M6 | missing | closer without `shift.close` can proceed on an approval; pay-in/out entry gated on `cash.movement` in `sale_screen.dart:294`; drawer-payouts feature gate; throttle 429 | `authorization.dart:274-281`; others reviewer-cited | closer point and 429 added (marked "from reading"); the `sale_screen`/drawer-payouts gate details were **not** verified by the author and are not in the docs |
| S1-S5 | style | off-by-one citations (BR-10, BR-2 snapshot column), "stored as sent" wording in DATABASE/WORKFLOWS, delete-guard line range, DATABASE missing a "Shared entities" heading | `migrations.dart:291,293-298,2228`; `PosShiftService.php:79,121,195` | fixed (delete-guard range left as is, within tolerance) |

## Not checked (this pass)
PostgreSQL behavior (lock, concurrent replay, malformed reference) — reading only, still UNVERIFIED in the docs. Every citation in the docs was not re-opened by the reviewer (about 150 spot-checked). `management_shifts_pane.dart`, `shift_history_providers.dart`, the `ShiftActivity`/`ShiftHistory` read paths, local-staff-id reconciliation, `pos_audit` content, `AuditLogger` internals. No tests were run.

## Status decision
Rule: only a validation with no open `wrong`/`stale` item may set `validated`. This pass found seven, so the feature could not be promoted at its start; they are fixed and re-checked by the author, but the corrected text has not been reviewed again. Status after this pass: **`drafted`**, `last validated 2026-10-20 (round 2: 7 wrong, fixed; round 3 pending)`.

## What this shows
Two independent passes found 6 and then 7 wrong statements in a document that passed the mechanical citation check each time. Two of the seven (W2, W3) came from claims the author or a helper agent carried forward without reading the code, and one (W1) from reading one of two resolver paths. The process is converging (round 2 findings are narrower than round 1), but a feature should not be promoted on author fixes alone. Recommendation: one more independent pass, ideally focused on the edit set of this round (BR-2, BR-12, AC-9/AC-10, Edge cases, Actors), before `validated`.
