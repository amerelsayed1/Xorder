# Technical design: POS shifts and cash movements

Verified against: 2026-10-20 · cloud `main 06bc8e3` · POS `main d592db8`. Prefixes: `C:` = `apps/xorder-cloud/apps/api/`, `P:` = `apps/xorder-pos/`, `W:` = `apps/xorder-cloud/apps/web/`.

## Architecture and modules
The till writes shifts to the branch PostgreSQL, queues events in `pos_sync_outbox`, and a drain posts them to the cloud phase by phase in the order listed under Offline operation (`P:lib/data/cloud/outbox_drain.dart:280-290`). The cloud recomputes the cash position from the orders and refunds it holds.
```
Cashier -> shift_dialogs -> ShiftRepository -> PostgresShiftRepository -> pos_shifts + pos_sync_outbox
OutboxDrain.run -> CloudApi -> POST /api/pos/shifts ... -> PosShiftService -> pos_shifts (cloud)
```

## Cloud implementation
| Layer | Files and symbols | Responsibility |
| --- | --- | --- |
| Routes and middleware | `C:routes/api.php:787,814-818` | device-authenticated group |
| Controller | `C:app/Http/Controllers/Pos/ShiftController.php` | thin; 201 vs 200 on replay |
| Requests | `C:app/Http/Requests/Pos/{OpenShiftRequest,CloseShiftRequest,StoreCashMovementRequest}.php` | shape validation |
| Service | `C:app/Services/PosShiftService.php` (`open`, `close`, `current`, `cashMovement`, `report`, `expectedCash`, `resolve`, `actor`) | rules, idempotency, lock, audit |
| Models | `C:app/Models/PosShift.php` (`forceFill` only, `$fillable = []`), `PosCashMovement.php` | persistence, tenant scope |
| Resource | `C:app/Http/Resources/PosShiftResource.php` | response shape |
| Capabilities | `C:app/Enums/TenantCapability.php:98-100` | cashier checks |
| Audit | `AuditLogger::record('pos_shift.closed')` (`PosShiftService.php:131`) plus the `Auditable` trait's `created`/`updated` events (`C:app/Models/Concerns/Auditable.php:24-25`) | audit trail |

## Web frontend implementation
| App | Pages and components | Stores / composables | API calls |
| --- | --- | --- | --- |
| `apps/web` | `W:src/pages/dashboard/HomeView.vue:36,179-190` (current shift tiles) | none specific | `GET stats` via the dashboard (`current_shift` from `StatsController.php:75`) |
No shift history page exists (searched `W:src` for `shift`; hits unrelated or the tiles above).

## Desktop POS implementation
| Layer | Files and symbols | Responsibility |
| --- | --- | --- |
| Screens | `P:lib/features/shift/presentation/shift_dialogs.dart`, `P:lib/features/cash/presentation/{cash_dialogs,day_close_dialog}.dart`, `P:lib/features/admin/presentation/management_shifts_pane.dart` | open, close/count, cash in/out, history |
| Providers | `P:lib/app/providers.dart`, `P:lib/app/shift_history_providers.dart` | bind `ShiftRepository` |
| Domain | `P:lib/domain/models/shift.dart` (`PosShift`, `ShiftSummary.expectedCash`, `ShiftClose`), `P:lib/domain/services/authorization.dart` | model and rules |
| Repository | `P:lib/domain/repositories/repositories.dart:851-900`; `P:lib/data/postgres/postgres_shift_repository.dart`; `P:lib/data/postgres/postgres_cash_movements_repository.dart` (writer of `pos_cash_movements` and of the `cash_movement` outbox row) | persistence, outbox enqueue, `cash.movement` check |
| Cloud client | `P:lib/data/cloud/cloud_api.dart:191-210`; `P:lib/data/cloud/outbox_drain.dart` | delivery |

## Source references
See `FEATURE.md` "Confirmed source references".

## State and data flow
Status moves `open → closed` only (cloud `PosShift::STATUS_OPEN/CLOSED`, `PosShift.php:20-22`; POS: `closed_at IS NULL`). Prices, totals and permissions on the cloud are authoritative for the dashboard figures; the till's figures drive its own Z report.

## Local persistence and caching
POS: `pos_shifts`, `pos_cash_movements`, `pos_sync_outbox` in branch PostgreSQL (`DATABASE.md`). No separate cache found.

## Offline operation and synchronization
- Shift open/close are written locally first; events are enqueued in the same transaction, only when the deployment mode syncs sales to the platform (`syncsSalesToPlatform`, `postgres_shift_repository.dart:77-80`); the close event is queued only if the shift also has a `client_transaction_id` (`:373-376`).
- `OutboxDrain.run` returns immediately if that mode is off and stops a pass when it goes offline (`outbox_drain.dart:276-296`).
- Phase order: customer, shift_open, order, cash_movement + refund, shift_close (`outbox_drain.dart:277-290`).
- For a server reply, only `VALIDATION_FAILED`, `IDEMPOTENCY_PAYLOAD_MISMATCH`, `MENU_ITEM_NOT_FOUND`, `BRANCH_NOT_IN_TENANT`, `CUSTOMER_NOT_FOUND`, `REFUND_EXCEEDS_SOLD` quarantine a record; all other codes defer (`outbox_drain.dart:119-130`). Pass scheduling and its consequences: `BEHAVIORAL_ANALYSIS.md` C (constants in `P:lib/data/cloud/cloud_sync.dart:74,77,85,90`).
- A close always carries a `variance_reason` because the cloud answers 422 to a non-zero variance without a reason (`outbox_drain.dart:694-724`, `PosShiftService.php:113-117`).

## Dependencies
Cloud: `AuditLogger`, `TenderType` kinds, `OrderPayment`, `PosRefund`/`PosRefundTender`, `PosTerminal` (lock row). POS: `uuid`, `postgres` pool, `Authorization`. Contracts POS-BE-009, POS-BE-010 (refunds in cash maths), POS-BE-021 (APPROVED, not built: the drain is the "serial form" of its documented batch ordering, `P:lib/data/cloud/outbox_drain.dart:273`; `apps/xorder-cloud/docs/coordination/BACKEND_TO_POS.md:215`).

## Failure handling and observability
Cloud: `PosApiException` codes and the validation envelope (API.md); `pos.device` errors (401/403); audit rows on close; request logging not reviewed. POS: `StateError` for double close; network log in `lib/core/network` not traced here.

## Platform-specific behavior
None found: `grep -rn "Platform\.\|dart:io"` over `P:lib/features/shift`, `P:lib/features/cash` and `P:lib/data/postgres/postgres_shift_repository.dart` returned no matches (2026-10-20).

## Compatibility and rollout
Additive API only. Cloud first, POS after, for any new field. The cloud accepts a null `acting_user_id` (`C:app/Services/PosShiftService.php:320-322`); the POS drain always sends one (`P:lib/data/cloud/outbox_drain.dart:687,754,810`).
