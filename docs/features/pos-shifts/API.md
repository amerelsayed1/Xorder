# API contract: POS shifts and cash movements

Verified against: 2026-10-20 · cloud `main 06bc8e3` · POS `main d592db8`
Prefixes: `C:` = `apps/xorder-cloud/apps/api/`, `P:` = `apps/xorder-pos/`. Contract POS-BE-009, status READY (`apps/xorder-cloud/docs/coordination/BACKEND_TO_POS.md:203`; same line in the POS copy).

## Producers and consumers
| Endpoint group | Producer | Consumers |
| --- | --- | --- |
| `pos/shifts*`, `pos/cash-movements` | `C:app/Http/Controllers/Pos/ShiftController.php` | POS `P:lib/data/cloud/cloud_api.dart:191-210` via `P:lib/data/cloud/outbox_drain.dart`. No Vue consumer found. |
| Dashboard current shift (not a shift endpoint) | `C:app/Http/Controllers/Dashboard/StatsController.php:75,132-157` (`GET /api/dashboard/stats`, `can:analytics.view`, `C:routes/api.php:341-342`) | `W:src/pages/dashboard/HomeView.vue:181` |

## Verified endpoints (method/path)
No `/v1` prefix; paths are under `/api` (the POS calls `/api/pos/shifts`, `P:lib/data/cloud/cloud_api.dart:192`).
| Method | Full path | Middleware | Controller@method | Route |
| --- | --- | --- | --- | --- |
| GET | `/api/pos/shifts/current` | `pos.device`, `throttle:240,1` | `Pos\ShiftController@current` | `C:routes/api.php:814` |
| POST | `/api/pos/shifts` | same | `@open` | `:815` |
| POST | `/api/pos/shifts/{shift}/close` | same | `@close` | `:816` |
| GET | `/api/pos/shifts/{shift}/report` | same | `@report` | `:817` |
| POST | `/api/pos/cash-movements` | same | `@cashMovement` | `:818` |
`{shift}` accepts the server id (digits) or the shift's `client_transaction_id` uuid (`C:app/Services/PosShiftService.php:301-308`).

## Authentication and authorization
| Endpoint | Guard | Gate | Tenant boundary |
| --- | --- | --- | --- |
| all five | device token (`pos.device`, `C:bootstrap/app.php:63`) | the `pos` feature IS gated through `pos.device` (403 `POS_FEATURE_DISABLED`, plus 401 `DEVICE_TOKEN_INVALID` and 403 `TERMINAL_REVOKED`; `C:app/Http/Middleware/PosDeviceAuth.php:45,64,68,71-72`); `subscription.writable` is absent by decision D2 (`C:routes/api.php:774-776`); per-cashier capability checked in the service only when `acting_user_id` is sent: `pos.shift_open`, `pos.shift_close`, `pos.cash_movement` (`PosShiftService.php:55,107,182,318-341`); none on `current`/`report` (the contract lists `pos.operate`/`pos.shift_close`) | restaurant from the terminal; shifts resolved within the terminal's branch (`PosShiftService.php:301-304`) |

## Request and response examples (redacted)
### `POST /api/pos/shifts`
Validation (`C:app/Http/Requests/Pos/OpenShiftRequest.php:17-23`):
```
client_transaction_id: required|uuid
branch_id: required|integer
acting_user_id: nullable|integer
opened_at: required|date
opening_float_minor: required|integer|min:0
```
Response 201 (200 on replay), `data` = `PosShiftResource` (`C:app/Http/Resources/PosShiftResource.php:14-29`):
```json
{"data":{"id":1,"client_transaction_id":"00000000-0000-4000-8000-000000000001","branch_id":1,"status":"open","opened_at":"2026-01-01T08:00:00+00:00","closed_at":null,"opened_by_id":5,"closed_by_id":null,"opening_float_minor":50000,"counted_cash_minor":null,"expected_cash_minor":null,"variance_minor":null,"variance_reason":null,"denominations":null}}
```
(Example values are fake; the key set is taken from the resource.)

### `POST /api/pos/shifts/{shift}/close`
Validation (`CloseShiftRequest.php:21-30`): `client_transaction_id` uuid, `acting_user_id` nullable int, `closed_at` date, `counted_cash_minor` int ≥ 0, `denominations` nullable array ≤ 50 of `{value_minor ≥ 1, count ≥ 0}`, `variance_reason` nullable string ≤ 255. Extra rule in the service: reason required when counted ≠ expected (`PosShiftService.php:113-117`). Response 200 `data` = `PosShiftResource`.

### `POST /api/pos/cash-movements`
Validation (`StoreCashMovementRequest.php:17-26`): `client_transaction_id` uuid, `shift_client_id` uuid, `direction` in `in,out`, `amount_minor` int ≥ 1, `reason` ≤ 120, `reference` nullable ≤ 255, `acting_user_id` nullable int, `occurred_at` date. Response 201 (200 on replay): `data` with `id`, `client_transaction_id`, `direction`, `amount_minor`, `reason`, `occurred_at` (`ShiftController.php:68-77`).

### `GET /api/pos/shifts/{shift}/report`
Response `data`: `shift`, `orders_count`, `sales_by_tender[]` (`tender_type_id`, `name`, `kind`, `amount_minor`, `payments`), `cash_in_minor`, `cash_out_minor`, `refunds_minor`, `refunds_count`, `cash_refunds_minor`, `expected_cash_minor`, `server_time` (`PosShiftService.php:224-244`).

### `GET /api/pos/shifts/current`
Response `data`: the open shift resource or `null` (`ShiftController.php:37`).

## Error formats
Codes raised as `PosApiException` by the service: `IDEMPOTENCY_PAYLOAD_MISMATCH` (422), `BRANCH_NOT_IN_TENANT` (404), `SHIFT_ALREADY_OPEN` (422), `SHIFT_NOT_OPEN` (422), `VALIDATION_FAILED` (422, with `details.errors`; also for "Unknown shift." and "Unknown user."), `POS_CAPABILITY_MISSING` (403, with `capability`) — `PosShiftService.php:43,52,68,104,114,167,179,310,329,335`. From the device middleware: `DEVICE_TOKEN_INVALID` (401), `TERMINAL_REVOKED` (403), `POS_FEATURE_DISABLED` (403). Envelope for `PosApiException`, validation failures on `api/pos/*` and the licence-check throttle (not for the shift group's own 429 or framework 404/401): `{"code","message","details"?}` with the exception's HTTP status (`C:app/Exceptions/PosApiException.php:30-39`, rendered via the exception's own `render()`); the POS contract fixes this as POS-BE-019 (`PosApiException.php:9`). FormRequest validation failures use the same envelope: `ValidationException` on `api/pos/*` is mapped to `{"code":"VALIDATION_FAILED","message":...,"details":{"errors":...}}` with status 422 (`C:bootstrap/app.php:71-86`). POS drain policy (`P:lib/data/cloud/outbox_drain.dart:119-130`): for a server reply, quarantined = `VALIDATION_FAILED`, `IDEMPOTENCY_PAYLOAD_MISMATCH`, `MENU_ITEM_NOT_FOUND`, `BRANCH_NOT_IN_TENANT`, `CUSTOMER_NOT_FOUND`, `REFUND_EXCEEDS_SOLD`; every other code (including `SHIFT_ALREADY_OPEN`, `SHIFT_NOT_OPEN`, `POS_CAPABILITY_MISSING`, `TERMINAL_REVOKED`, `POS_FEATURE_DISABLED`) is deferred and retried (`classify` tests at `P:test/data/outbox_drain_test.dart:245-279` assert a subset by name; behavior for the rest is from the code).

## Idempotency, retries and concurrency
- Open/close/movement are idempotent on `client_transaction_id` with a sha256 payload hash; the POS also sends it as the `Idempotency-Key` header (`P:lib/data/cloud/cloud_api.dart:251`, passed at `:191-210`). The cloud does not read the header (no match in `C:app`, `routes`, `bootstrap`, `config`); the service keys on the body field (`PosShiftService.php:39`).
- Unique `(restaurant_id, client_transaction_id)` on `pos_shifts` and `pos_cash_movements` (migration lines 45, 66).
- The open path takes `lockForUpdate` on the terminal row (`PosShiftService.php:61`); effect under PostgreSQL not tested. What "same payload" means: open hashes `client_transaction_id`, `opening_float_minor`, `opened_at`; close hashes `client_transaction_id`, `counted_cash_minor`, `closed_at`; movement hashes `client_transaction_id`, `direction`, `amount_minor`, `reason` (`PosShiftService.php:37,97,158`). Differences in other fields on a replay are accepted and ignored. Throttling (`throttle:240,1`) returns 429; not covered by tests.

## POS and other client usage
| Client call site | Endpoint | Request model | Contract |
| --- | --- | --- | --- |
| `P:lib/data/cloud/outbox_drain.dart:667-692` (`_shiftOpenEvent`) | `POST /api/pos/shifts` | `client_transaction_id, branch_id, acting_user_id, opened_at (UTC ISO), opening_float_minor` | POS-BE-009 READY |
| `P:lib/data/cloud/outbox_drain.dart` (`_shiftCloseEvent`, from line 726) | `POST /api/pos/shifts/{client uuid}/close` | `client_transaction_id, acting_user_id, closed_at, counted_cash_minor, variance_reason (always), …` | POS-BE-009 READY |
| `P:lib/data/cloud/outbox_drain.dart:774-810` (`_cashMovementEvent`) | `POST /api/pos/cash-movements` | `direction` from POS kind: `pay_in`,`float_adjust` → in; `pay_out` → out; `drawer_open` has no client id or outbox row so it is never sent (`postgres_cash_movements_repository.dart:165-170`); `reason` is the reason code, `reference` is the movement note, `acting_user_id` is the staff id; supplier pay-outs also produce this event (`postgres_supplier_invoices_repository.dart:848,1029,1125-1140`) | POS-BE-009 READY |
| (none; searched `P:lib`, `P:test` and the Vue sources) | `GET /api/pos/shifts/current`, `GET /api/pos/shifts/{shift}/report` | — | no consumer; the POS reads its own database |

## Contract divergences (POS-BE-009 text vs built code)
`apps/xorder-cloud/docs/coordination/BACKEND_TO_POS.md:744-810`: capabilities `pos.operate`/`pos.shift_close` are listed for `GET current`/`GET report` but not applied; a report for another branch's shift is described as 404, built as 422 "Unknown shift" (`PosShiftsTest.php:214`); the close response is described as including report figures, built as `PosShiftResource` only; POS-BE-021 (`POST /api/pos/sync`) is APPROVED (`BACKEND_TO_POS.md:215`), not built, and the drain posts events one by one. The cloud `POS_TO_BACKEND.md:507-509` still says "implementation not started" for POS-BE-009.

## Backward compatibility
Report keys `refunds_minor`, `refunds_count`, `cash_refunds_minor` were added by POS-BE-010 as additive keys (`PosShiftService.php:236-241`). Changes must stay additive; the POS ships separately from the cloud. The cloud and POS copies of the coordination files differ (compare with `diff`), so confirm READY status in both before relying on it.

## Contract tests
| Test | Endpoint | Covers | Gaps |
| --- | --- | --- | --- |
| `C:tests/Feature/Pos/PosShiftsTest.php:40` | open/current/close | lifecycle | response key set not reviewed in detail |
| `:73`, `:184` | open/close replay | idempotency | cash-movement replay, payload-mismatch cases |
| `:93` | close/report | expected cash formula | |
| `:173` | cash-movements | needs open shift | |
| `:214` | report | branch scope | |
