# Workflows: POS shifts and cash movements

Verified against: 2026-10-20 · cloud `main 06bc8e3` · POS `main d592db8`. Prefixes: `C:` = `apps/xorder-cloud/apps/api/`, `P:` = `apps/xorder-pos/`.

## Workflow index
| ID | Name | Actor | Trigger | Applications |
| --- | --- | --- | --- | --- |
| WF-1 | Open a shift | Cashier | start of service | POS, then cloud |
| WF-2 | Sell and move cash | Cashier | during service | POS, then cloud |
| WF-3 | Close and cash-up | Cashier (opener) or manager | end of service | POS, then cloud |
| WF-4 | Offline open, later sync | System | connectivity returns | POS, cloud |
| WF-5 | Dashboard view | Restaurant admin | opens the dashboard home | cloud web |

## WF-1: Open a shift
**Actor and permission:** cashier with `shift.open` (checked in the sign-in dialog only, `P:lib/features/shift/presentation/shift_dialogs.dart:86`; the repository does not check it). **Preconditions:** the licence must allow opening a shift (`P:lib/features/start/start_screen.dart:71-72`);  signed in; no open shift on this terminal (otherwise the open one is returned). **Postconditions:** row in `pos_shifts`; `shift_open` outbox row in sync modes.
| Step | System | Action | Code | Result | Failure branch |
| --- | --- | --- | --- | --- | --- |
| 1 | POS | `current()` | `P:lib/data/postgres/postgres_shift_repository.dart:54-76` | existing open shift returned | none |
| 2 | POS | insert shift with float; generate uuid in sync modes | `postgres_shift_repository.dart:77-96` | shift created | DB unique index refuses a second open |
| 3 | POS | enqueue `shift_open` | `postgres_shift_repository.dart:100-107` | outbox row | |
| 4 | POS drain | `POST /api/pos/shifts` | `P:lib/data/cloud/outbox_drain.dart:667-692` | cloud shift (201) or replay (200) | 422 `SHIFT_ALREADY_OPEN` / `IDEMPOTENCY_PAYLOAD_MISMATCH` → quarantined for `IDEMPOTENCY_PAYLOAD_MISMATCH`; deferred (retried) for `SHIFT_ALREADY_OPEN` (`outbox_drain.dart:119-130`) |
**Tests:** `C:tests/Feature/Pos/PosShiftsTest.php:40,73`; `P:test/data/postgres_shift_test.dart:169,178,191`.

## WF-2: Sell and move cash
Sales are stamped with the open shift (`P:test/data/postgres_shift_test.dart:543`). Pay in/out: POS `pos_cash_movements` row (`kind`) written by `postgres_cash_movements_repository.dart` (requires `cash.movement`; `cash.open_without_sale` for a drawer opening), later `POST /api/pos/cash-movements` with `direction` (`outbox_drain.dart:774-810`); needs an open shift on the cloud (`C:app/Services/PosShiftService.php:173-180`); on the POS the cash dialogs refuse without an open shift (`P:lib/features/cash/presentation/cash_dialogs.dart:299-302,369-373`). `drawer_open` gets no client id and no outbox row, so it is never sent (`postgres_cash_movements_repository.dart:165-170`); supplier pay-outs from the drawer also enqueue `cash_movement` events. **Tests:** `PosShiftsTest.php:173`; `P:test/domain/cash_movement_test.dart`.

## WF-3: Close and cash-up
| Step | System | Action | Code | Result | Failure branch |
| --- | --- | --- | --- | --- | --- |
| 1 | POS | require `shift.close`; manager approval if not the opener | `postgres_shift_repository.dart:350-360` | allowed (approver must be a different person holding `shift.close`) | permission refused (`PermissionRefused`) |
| 2 | POS | summarise and compute variance in one transaction | `postgres_shift_repository.dart:366-372` | expected, variance | |
| 3 | POS | update `WHERE closed_at IS NULL`; enqueue `shift_close` with a fresh uuid | `postgres_shift_repository.dart:377-415` | closed (a handover approval is audited locally as `shift.close.handover`, not synced) | already closed → `StateError` (`:423-428`) |
| 4 | POS drain | `POST /api/pos/shifts/{uuid}/close` last phase of a drain pass, see `BEHAVIORAL_ANALYSIS.md` A | `P:lib/data/cloud/outbox_drain.dart:280-290,726-772` | cloud recomputes expected and variance | 422 `VALIDATION_FAILED` if reason missing (the POS always sends one) |
**State machine:** `open → closed` only; guard on the POS `closed_at IS NULL`, on the cloud `isOpen()` (`PosShiftService.php:99-105`). **Tests:** `PosShiftsTest.php:184`; `P:test/data/postgres_shift_test.dart:319,334,362,371,416`; `P:test/data/shift_close_drain_test.dart:107-133`.

## WF-4: Offline open, later sync
The till works against its branch PostgreSQL regardless of the cloud; events wait in `pos_sync_outbox`. A drain pass attempts the phases customers, shift opens, orders, movements and refunds, closes in that order, each phase reading at most 25 rows (see `BEHAVIORAL_ANALYSIS.md` A) (`outbox_drain.dart:277-290`). Client times are kept as the same instant, normalised to the app time zone (`C:app/Services/PosShiftService.php:79`), and the close uses the shift's client uuid (`PosShiftService.php:296-300`). Backlogs that span more than one shift, and the 25-row window per phase: `BEHAVIORAL_ANALYSIS.md` A and B. What happens to the till if the **branch** database is down is **UNVERIFIED** here. **Tests:** cloud close-by-uuid is exercised in `PosShiftsTest.php:93`; no test opens a shift with a past client time and closes it later (AC-8 partial); no test of phase order (AC-9).

## WF-5: Dashboard view
Admin opens the home page; `GET stats` returns `current_shift` and the page shows sales, orders, expected cash and average (`C:app/Http/Controllers/Dashboard/StatsController.php:75`, `W:src/pages/dashboard/HomeView.vue:179-190`). The data source is the tenant-wide latest open shift by `opened_at`: one shift even when several tills are open; sales = all payments of that shift, expected cash from `PosShiftService::expectedCash` (`C:app/Http/Controllers/Dashboard/StatsController.php:132-157`). The route needs `can:analytics.view` (`C:routes/api.php:341-342`).

## Gaps
- No workflow for cloud-side shift review (no endpoint).
- `GET /api/pos/shifts/current` and `/report` have no client in the repos (searches recorded in `docs/FEATURE_INVENTORY.md` "Absent").
