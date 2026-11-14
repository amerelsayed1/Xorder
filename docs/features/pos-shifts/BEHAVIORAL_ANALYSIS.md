# Behavioral analysis: POS shifts and cash movements

Status: **UNVALIDATED (from reading).** Excluded from `/project-documentation validate`; it can never make `pos-shifts` `validated`. Every entry is a lead: re-trace the code before relying on it and say so in any plan or review that uses it. Nothing here was executed; no test was run.
Written against: cloud `main 06bc8e3` · POS `main d592db8`. Five earlier validation passes (`docs/validation/2026-10-20-pos-shifts-*.md`) repeatedly found errors in exactly this kind of statement, so expect more.
Path prefixes: `C:` = `apps/xorder-cloud/apps/api/`, `P:` = `apps/xorder-pos/`.

## A. Drain ordering is a phase order, not a delivery guarantee
- Claim: within a pass the phases run customers → shift opens → orders → cash movements + refunds → shift closes, but nothing guarantees earlier phases were fully delivered before a shift's close is sent.
- Trace: phases `P:lib/data/cloud/outbox_drain.dart:280-296`; every phase reads at most 25 rows ordered by `enqueued_at` (`passLimit` `:74`, orders `:309-321`, lifecycle `:459-468`); the queries exclude only delivered and quarantined rows, so deferred rows stay; only refunds have a wait guard (`_Waiting`, `:869-880`); `_shiftCloseEvent` (`:726-772`) checks no prerequisite; only going offline stops a pass (`:295,363-370,503-510`), a deferral continues (`:543-560`).
- Consequences: with more than 25 pending orders, or a deferred order, a close can reach the cloud first and the remaining orders are stored unattributed because the cloud attributes only to an open shift (`C:app/Services/PosOrderService.php:503-513`). Cash movements for a shift the cloud has not opened or has already closed are refused `SHIFT_NOT_OPEN` (`C:app/Services/PosShiftService.php:173-180`) and deferred on every pass, so they are missing from the cloud's expected cash and can fill the 25-row window shared by movements and refunds, starving newer rows. A quarantined or never-accepted `shift_open` also leaves its close to be quarantined (422 "Unknown shift", `PosShiftService.php:309-313`).
- Confidence: medium-high. Would be confirmed by: a drain test with >25 pending orders and a closed shift.

## B. Multi-shift backlog
- Claim: if the till opens A, closes A and opens B before a drain, the cloud ends up with a stuck or wrongly attributed B.
- Scenario 1 (B still open): pass 1: A's open is created; B's open is refused `SHIFT_ALREADY_OPEN` (A is open on the cloud, `PosShiftService.php:63-69`) and deferred; B's orders are sent and, finding no open B, are stored unattributed (`PosOrderService.php:503-513`); B's movements are refused `SHIFT_NOT_OPEN` and retried; B's refunds are accepted unattributed because an unknown shift resolves to null (`C:app/Services/PosRefundService.php:330-340`); A is closed. A later pass opens B (the terminal now has no open shift).
- Scenario 2 (B also closed before the drain): pass 1 as above, but B's close is sent for a shift the cloud does not have: 422 `VALIDATION_FAILED` ("Unknown shift", `PosShiftService.php:309-313`), classified quarantine (`outbox_drain.dart:119-130`). Pass 2: B's open succeeds and B's movements are accepted onto the now-open B, but B is never closed, so every later open from that terminal is refused and deferred, the dashboard tile keeps showing B (`C:app/Http/Controllers/Dashboard/StatsController.php:132-157`), B's sales are never attributed, and B's float and movements appear in the dashboard expected cash.
- A deferred open clears only when the terminal has no open shift on the cloud.
- Confidence: medium (each step read, the whole sequence not executed). Would be confirmed by: a cloud feature test of the sequence plus a POS drain test.

## C. Retry cadence and exceptions
- Claim: passes run automatically only under the automatic sync policy; the first runs 5 seconds after start-up; the next is 30 minutes after an unsettled pass and 4 hours after a settled one; a nudge runs 2 seconds after an enqueue but never closer than 20 seconds to the previous pass. A backlog larger than the 25-row window with no deferrals therefore drains one window per 4 hours unless new enqueues nudge the drain. An uncaught exception in `OutboxDrain.run()` stops the self-rescheduling cadence until the provider is rebuilt.
- Trace: `P:lib/data/cloud/cloud_sync.dart:30-43` (`settled` = heartbeat ok, token not rejected, not offline, no deferred rows; quarantined rows do not count), `:74,77,85,90` (4 h, 30 min, 2 s, 20 s); `P:lib/app/providers.dart:721-747` (automatic policy, rescheduling with `SyncSchedule.after(outcome)`, first pass 5 s); no try/catch around `run()` in `cloud_sync.dart:173,202` or the timer closure `providers.dart:741-743`; a past case is recorded at `providers.dart:711-715`; no global error zone found by grep.
- Confidence: medium. Would be confirmed by: a unit test of `SyncSchedule` and a drain run that throws.

## D. Supervisor-lent permissions are not honoured by the cloud
- Claim: closes and cash movements done on a supervisor's lent permission are not carried to the cloud as such, so the cloud judges the cashier's own capability and defers the rows indefinitely.
- Trace: the POS sends the acting cashier as `acting_user_id` (`outbox_drain.dart:754` close, `:810` movement) and no approver; the cloud checks that user's `pos.shift_close` / `pos.cash_movement` (`PosShiftService.php:107,182,334-336`) and answers 403 `POS_CAPABILITY_MISSING`, which falls to the defer arm with no attempt cap (`outbox_drain.dart:119-130`).
- Consequences: the cloud shift never closes; a later open B is refused `SHIFT_ALREADY_OPEN` and deferred; B's close is sent for an unknown shift and quarantined; B's orders are unattributed and B stays unopened while A is stuck; the stuck movement stays in the 25-row window. `cash.open_without_sale` concerns `drawer_open`, which is never sent.
- Confidence: medium-high. Would be confirmed by: a drain test where the closer lacks the cloud capability.

## E. Who can hold the variance keys on a cloud till
- Claim: staff who arrive from the cloud hold `shift.view_expected_cash` and `cash.variance.view` only through a local role, an extra role or a per-person allow override; on a cloud till without one, the post-close Z report is masked for everyone.
- Trace: no cloud capability has those names; the bootstrap sends the user's tenant capabilities minus `purchase.manage` (`C:app/Services/PosBootstrapService.php:326-331`); the seeder stores them as direct capabilities without a role and rewrites them at every seed (`P:lib/data/cloud/bootstrap_seeder.dart:465-487`); direct-grant edits return `ManagedByPlatform` on a cloud till (`P:lib/data/postgres/postgres_admin_repositories.dart:539-548`); the post-close mask is `!can(cashVarianceView)` (`shift_dialogs.dart:598`).
- Confidence: medium.

## F. Closer who lacks `shift.close`
- Claim: a closer who lacks `shift.close` can proceed on a valid approval from a different person who holds it.
- Trace: `P:lib/domain/services/authorization.dart:267-313`, `postgres_shift_repository.dart:350-360`. Confidence: medium. Not tested.

## G. Shift attribution divergences and expected-cash differences
- Claim: cloud and till expected cash can disagree: the cloud counts untyped payments as cash regardless of order status and attributes payments only through the open shift named in the request; the till uses the snapshotted `counts_as_cash` flag with `bool_or` per label and tender type; an order held locally for `TENDER_NOT_FROM_PLATFORM` never reaches the cloud, so its cash is missing there.
- Trace: `C:app/Services/PosShiftService.php:253-268`; `P:lib/data/postgres/postgres_shift_repository.dart:457-468`; `outbox_drain.dart:90,335-338`; `PosOrderService.php:444,503-513`.
- Also: refunds resolve their shift without an open filter (`PosRefundService.php:330-340`), so a late refund naming a closed shift changes that shift's refund figures while `report()` returns the stored `expected_cash_minor` of a closed shift (`PosShiftService.php:242`), so the report's refund figures and expected cash can disagree. Confidence: medium.
- A voided order cannot affect POS expected cash today because a `VOIDED` order is written with no payment rows (`P:lib/data/postgres/postgres_orders_repository.dart:260,322-330`) although the tender query has no status filter (`postgres_shift_repository.dart:457-468`). Confidence: high.

## H. `open` with another branch of the tenant
- Claim: a shift opened with a `branch_id` that is not the terminal's branch cannot be closed or reported from that terminal and keeps the terminal blocked by `SHIFT_ALREADY_OPEN`.
- Trace: `PosShiftService.php:49-53` (any branch of the tenant), `:303` (`resolve()` filters by the terminal's branch), `:63-69`. Confidence: medium-high (the POS always sends its own branch id, `outbox_drain.dart:687`).

## I. Concurrency details
- A concurrent replay of the same open can be refused `SHIFT_ALREADY_OPEN` instead of returning 200 because the replay lookup (`PosShiftService.php:39-47`) is outside the transaction (`:57-69`). A concurrent duplicate insert caught only by the unique constraint is not handled (would surface as a database error). The SQLite test suite cannot show lock behavior. Confidence: medium.
- A non-digit, non-uuid `{shift}` reference reaches a uuid column comparison (`PosShiftService.php:305-307`); on PostgreSQL this may raise a database error instead of 422. Confidence: low.

## J. Close writes two audit records
- Claim: because `PosShift` uses the `Auditable` trait (`C:app/Models/Concerns/Auditable.php:24-25`) and the service also calls `AuditLogger::record('pos_shift.closed')` (`PosShiftService.php:131-142`), a close writes two audit records. The content of the trait's records was not read. Confidence: medium.

## K. Topology: several tills on one cloud main device
- Claim: a child till of a cloud main device writes into the main device's database and the main device's drain carries its rows under the main device's token; the drain has no terminal filter and the cloud allows one open shift per cloud terminal, so a second till's concurrent shift would be deferred with `SHIFT_ALREADY_OPEN`, its orders left unattributed and its movements refused.
- Trace: `P:lib/core/config/deployment.dart:24-26,201-204,321-323`; `P:lib/app/providers.dart:600-602,661-662`; `outbox_drain.dart:309-321,459-468`; `PosShiftService.php:63-69,173-176`. Confidence: low-medium.

## L. Supplier pay-outs booked on another terminal's shift
- Claim: a drawer pay-out from the supplier flow is booked on a shift chosen by branch, so a pay-out booked on another terminal's shift would be refused by the cloud with `SHIFT_NOT_OPEN` (the cloud looks the shift up by the draining terminal) and stay deferred.
- Trace: `P:lib/data/postgres/postgres_supplier_invoices_repository.dart:780-790,826-828,1009-1034`; `PosShiftService.php:173-180`. Confidence: low (reported by a reviewer, not re-read by the author).

## M. Moved from the core after the round-6 review
- A payment that names no resolvable shift gets the order's `pos_shift_id` (`C:app/Services/PosOrderService.php:444`); if the order's shift has since closed, the payment counts toward a closed shift (needs the sequence order → shift closes → later payment; no POS client sends that payment today).
- Replays return before the capability checks for open, close and movement, so a replay by a user lacking the capability still gets 200 (`PosShiftService.php:39-47,99-107,163-171` vs `:55,107,182`). Not tested.
- Any paired terminal of a branch can close or read another terminal's shift of that branch by id, because `resolve()` filters by branch only (`PosShiftService.php:301-316`).
- A shift opened outside sync mode, or without a `client_transaction_id`, never closes on the cloud (`P:lib/data/postgres/postgres_shift_repository.dart:373-376`; follows from there being no other close path, `grep "UPDATE pos_shifts"`).
- The POS always sends a `variance_reason` so the cloud's 422 cannot strand a shift (`outbox_drain.dart:694-724`).
- By reading, terminal deletion in `C:app/Services/PosProvisioningService.php:393-409` is not blocked by a never-closed zero-float shift that has cash movements.
