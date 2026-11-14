# Round 3 validation report: `pos-shifts`

Date: 2026-10-20 · Command: `validate pos-shifts` (third pass, requested focus: the round-2 edit set — BR-2, BR-12, AC-9/AC-10, Edge cases, Actors) · Repos: cloud `main 06bc8e3`, POS `main d592db8`
Freshness before validating: both HEADs unchanged, no committed changes since the documented revisions, the same 10 (cloud) and 11 (POS) uncommitted files as recorded. Mechanical checks: `check-docs.py` passes; 143 line-level citations resolve, 0 problems.
Validator: a fresh `code-reviewer` agent that did not read `docs/validation/` and had not seen the earlier findings. The author verified each finding against source before acting on it.

## Result
**4 wrong, 2 stale, 3 missing groups, 5 style.** All were fixed. Because the validator found wrong statements, the rule forbids promotion: the feature stays **`drafted`**.
Clean areas (reviewer, with the author's agreement on the reviewed lines): BR-12 and AC-10 logic, the Actors table's call sites and permission keys, the concurrent-open note, the offline-open, short/over and `drawer_open` edge-case bullets, the classify list and its tests, the secondary docs (API routes/middleware/validation/error codes, cloud DATABASE columns and POS migration lines, inventory block, TEST_REPORT numbers), the header/dirty-file statements.

## Findings and disposition
| # | Severity | Finding | Source evidence (author-verified) | Disposition |
| --- | --- | --- | --- | --- |
| W1 | wrong | BR-2/limitations said cash on voided orders stays in the POS expected cash. A voided order is inserted as `VOIDED` with no payment rows and is not queued for the cloud, so the divergence cannot occur | `P:lib/data/postgres/postgres_orders_repository.dart:260,322-330`; `grep "UPDATE pos_orders"` finds only the refund trigger, invoice number and a backfill | fixed (BR-2, limitations, CHANGELOG wording) |
| W2 | wrong | "The drain sends the close last, which is why…" and AC-9 read as a guarantee. Each phase reads at most 25 rows by `enqueued_at`, deferred rows stay in the query, and nothing checks a shift's orders were delivered before its close (only refunds have a wait guard) | `P:lib/data/cloud/outbox_drain.dart:74,309-321,459-468,862-876` | fixed (AC-9 reworded to phase order; new "Drain window and ordering" bullet marked from reading) |
| W3 | wrong (incomplete) | The multi-shift backlog covered only "B still open". If B was also closed before the drain, B's close is sent for a shift the cloud does not have (422, quarantined), B is opened on pass 2 and never closed on the cloud, blocking later opens | `PosShiftService.php:63-68,309-313`; `outbox_drain.dart:119-130`; trace by reading | fixed (Edge cases, WORKFLOWS); marked from reading, not tested |
| W4 | wrong (incomplete) | Drain policy omitted the local quarantine paths (`LOCAL_SOURCE_MISSING`, `SALE_NEVER_QUEUED`, `REFUND_HAS_NO_LINES`, `TENDER_NOT_FROM_PLATFORM`) and the refund-only wait; "only … quarantine" needed "for a server reply" | `outbox_drain.dart:90-103,335-338,606-614,861,862-876` | fixed (FEATURE, API, TECHNICAL) |
| S1 | stale | TEST_PLAN said AC-10 had no tests; the open-shift attribution is exercised in `PosShiftsTest.php:93` and the no-shift case in `PosOrdersTest.php:350` | tests read by the reviewer | fixed (partial; untested paths listed) |
| S2 | stale | DATABASE listed `2026_09_13_000300` as mentioning `pos_shifts`; it mentions only `pos_cash_movements` | `grep -c pos_shift` → 0 | fixed |
| M1 | missing | Behavior when a key is absent (overridable vs not, 403 only when `acting_user_id` sent, POS always sends it) | `permissions.dart:168-196`, `shift_dialogs.dart:84-103,376-387`, `outbox_drain.dart:687,754,810`, `User.php:115-126` | added to Actors; `shift.view_expected_cash`/`cash.variance.view` holders on a cloud till marked UNVERIFIED |
| M2 | missing | supplier pay-out gate and `reports.view` gate on the history pane | `postgres_supplier_invoices_repository.dart:655,957`; `management_shifts_pane.dart:31` | added |
| M3 | missing | replay-before-capability applies to open, close and movement | `PosShiftService.php:39-47,99-107,163-171` | fixed |
| style | style | `shift_dialogs.dart:364` vs 363, `_implied` at 256 vs 257, offline-return lines, "no writer" wording for `cash.blind_close` | | wording fixed; the 1-line citation offsets are within tolerance and the exact lines are used where changed |

## Not checked (this pass)
PostgreSQL behavior (lock, malformed reference); `Auditable` row content; Vue beyond the cited lines; BR-6/8/9 hash fields beyond reading the service; whether an unhandled exception in the drain can abort `run()`; retry timing. W2 and W3 are inferences from reading and are labelled so in the docs. No tests were run.

## Status decision
**`drafted`**, unchanged. Three passes found 6, 7 and 4 wrong claims; the corrections after each pass were re-checked by the author but the text after round 3 has not been reviewed independently. Promotion rule: a pass that finds nothing wrong.
Observation for planning: the findings per pass are narrowing, and round 3's findings were about concurrency/ordering semantics and one impossible-state divergence, which are the hardest things to document from reading. Each pass cost roughly 200k subagent tokens. A fourth pass on the round-3 edit set is the way to reach `validated`; for the remaining 63 features, consider validating only the high-risk ones (money, order state, permissions, sync) at this depth. `references/validation-rules.md` now lists three more failure modes found here (ordering described as a guarantee, divergences the data model forbids, claims carried forward unread).
