# Round 4 validation report: `pos-shifts`

Date: 2026-10-20 · Command: `validate pos-shifts` (fourth pass; requested focus: the round-3 edit set — BR-2, AC-9, Edge cases drain bullets, Actors absent-key text) · Repos: cloud `main 06bc8e3`, POS `main d592db8`
Freshness before validating: both HEADs unchanged, 0 committed changes since the documented revisions, the same uncommitted files (10 cloud, 11 POS). Mechanical checks: `check-docs.py` passes; 151 line-level citations resolve, 0 problems.
Validator: a fresh `feature-analyst` agent that did not read `docs/validation/`. The author verified each finding it used against source.

## Result
**3 wrong, 6 missing groups, 5 wording/unverifiable, plus style.** All fixed. A validator that finds wrong statements blocks promotion: the feature stays **`drafted`**.
The reviewer traced both multi-shift scenarios step by step and found nothing impossible; BR-2 (cash definitions, voided-order statement, `counts_as_cash`, refunds), the phase list, the 25-row window and the Actors table call sites were confirmed (about 46 items checked correct across the three focus areas).

## Findings and disposition
| # | Severity | Finding | Source evidence (author-verified) | Disposition |
| --- | --- | --- | --- | --- |
| W1 | wrong | The post-close variance "reveal" was described as part of the blind-close policy. The Z report shown after the close is masked for anyone lacking `cash.variance.view` regardless of the policy; the policy only gates the pre-count hiding | `P:lib/features/shift/presentation/shift_dialogs.dart:274-276,598`; `cash.blind_close` is never written in `lib`/`bin` | fixed (Actors row, POS item 5) |
| W2 | wrong | "A deferred open clears only if nothing else is pending for that shift" — the cloud refuses an open while any other shift of the terminal is open | `C:app/Services/PosShiftService.php:63-69` | fixed (edge cases; second scenario: never clears) |
| W3 | wrong (understated) | Movements for a shift the cloud has already closed are refused `SHIFT_NOT_OPEN` and deferred forever, not only for a never-opened shift | `PosShiftService.php:173-180`; `outbox_drain.dart:119-130` | fixed (Drain window bullet) |
| M1 | missing | Supervisor-lent `shift.close`/`cash.movement` are not sent to the cloud (the acting cashier is); the cloud answers 403, which is deferred indefinitely | `outbox_drain.dart:754,810`; `shift_dialogs.dart:364`; `PosShiftService.php:107,182,334-336` | added to Actors (marked from reading, not tested) |
| M2 | missing | history pane hides over/short without `cash.variance.view` | `management_shifts_pane.dart:41` | added |
| M3 | resolved | who holds `shift.view_expected_cash`/`cash.variance.view` on a cloud till (only via a local role/grant); drain pass timing (4 h idle, 30 min while queued, 2 s nudge, 20 s floor) | `C:app/Services/PosBootstrapService.php:326-331`; `bootstrap_seeder.dart:465-486`; `cloud_sync.dart:74,77,85,90` | UNVERIFIED markers replaced |
| M4 | missing | test coverage statement incomplete: refund-after-sale ordering and local hold paths are covered by `cloud_refunds_test.dart` (integration-tagged); nothing covers shift phases | `P:test/data/cloud_refunds_test.dart:482-646` (test names read) | FEATURE and TEST_PLAN updated |
| M5 | missing | scenario 1 omitted B's refunds (accepted unattributed) | `PosRefundService.php:330-340` | added |
| M6 | missing | local-quarantine scope wider (customer rows, refund client id, unknown event type, null close fields, unmappable kinds) | `outbox_drain.dart:601,606-614,637,740-749,797-802,854` | widened |
| U1-U5 | wording | null-relaxation callers ("none exist"); `bool_or` of `counts_as_cash` and the id-1 backfill; `drawer_open` is a stored row and client ids exist only in sync mode; supplier gates (`:655` pay-out, `:957` reversal, plain checks, `purchase.manage`, branch-chosen shift); payment-add path has no POS client | `postgres_shift_repository.dart:459-465`; `migrations.dart:2238-2239`; `postgres_cash_movements_repository.dart:162-170`; `postgres_supplier_invoices_repository.dart:655,957` | fixed |
| style | style | `_Waiting` at `:869-880`; offline-return lines `:363-370,503-510`; `permissions.dart:221-258`; module doc phase-order caveat | | fixed |

## New open questions (recorded, not answered)
Several tills sharing one cloud-mode database could drain each other's rows (the drain query has no terminal filter); whether an exception inside `OutboxDrain.run()` aborts a pass; both added to FEATURE.md Unknowns. Product questions for the owner added to `docs/DOCUMENTATION_PROGRESS.md` (lent permissions not reaching the cloud; how `cash.blind_close` is set; who can hold the variance keys on a cloud till).

## Not checked (this pass)
Test execution; PostgreSQL behavior; the POS-BE-009 contract text against the build (status lines only); remaining line numbers in DATABASE/API (spot-checked); multi-till behavior (unverified); exception handling around `run()`.

## Status decision
**`drafted`** (rule: only a pass finding nothing wrong may set `validated`). Four passes found 6, 7, 4 and 3 wrong claims. The remaining errors concentrate in code paths that are hard to settle by reading (drain ordering, concurrency, multi-till). The text after the round-4 corrections has not been reviewed independently.
Recommendation: do not spend a fifth pass on this feature unless it matters for a release; ship it at `drafted` with its UNVERIFIED list, and reserve zero-finding validation for money, order-state, permission and sync features. If a fifth pass is wanted, scope it to the round-4 additions.
