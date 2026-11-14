# Test plan: POS shifts and cash movements

Verified against: 2026-10-20 · cloud `main 06bc8e3` · POS `main d592db8`. Prefixes: `C:` = `apps/xorder-cloud/apps/api/`, `P:` = `apps/xorder-pos/`. This is the plan and the mapping of acceptance criteria (`FEATURE.md`) to tests. Results live in `TEST_REPORT.md`; nothing here claims a test passed.

## Test environments
- Cloud: `cd apps/xorder-cloud/apps/api && php artisan test --filter PosShiftsTest` (PHPUnit 12, SQLite `:memory:`; PostgreSQL behavior and `lockForUpdate` are not exercised).
- POS unit/widget: `cd apps/xorder-pos && env -u POS_PG_HOST flutter test test/domain test/features`.
- POS PostgreSQL: `cd apps/xorder-pos && scripts/check.sh test/data/postgres_shift_test.dart` (needs local PostgreSQL, consent required by `/project-testing`).

## Acceptance criteria to tests
| AC | Existing test | Status of coverage | Planned addition |
| --- | --- | --- | --- |
| AC-1 | `C:tests/Feature/Pos/PosShiftsTest.php:73` (one open per terminal); `P:test/data/postgres_shift_test.dart:191` (DB refuses second open) | covered cloud + POS (POS needs PostgreSQL) | concurrent open race on PostgreSQL (cloud SQLite cannot show the lock) |
| AC-2 | `PosShiftsTest.php:73` (open replay, asserts 200 and same id only), `:184` (close replay) | open/close covered; no row-count assertion | cash-movement replay and payload-mismatch (422); open replay with a changed float |
| AC-3 | `PosShiftsTest.php:93`; `C:tests/Feature/Pos/PosRefundsTest.php:404` (cash handed back lowers expected cash); `P:test/data/postgres_shift_test.dart:246` | covered | mixed-tender refund; untyped payment/refund as cash (BR-3); refund attributed to its own shift (sale in A, refund in B) |
| AC-4 | `PosShiftsTest.php:155-168` (inside `:93`): 422 `VALIDATION_FAILED` without a reason, 200 with variance 500 | covered on the cloud | standalone test; negative variance (zero variance without a reason is exercised at `PosShiftsTest.php:60-68,191-198`) |
| AC-5 | `PosShiftsTest.php:173` | covered | |
| AC-6 | `P:test/data/postgres_shift_test.dart:371` (needs PostgreSQL), `P:test/domain/shift_ownership_test.dart:24,29` | covered POS at repository/domain level | widget test of the approval prompt: `close_shift_dialog_test.dart` tests only the parked-tickets warning; `P:test/features/manager_approval_test.dart` tests only the generic supervisor-override dialog; no shift-specific widget test of the approval prompt |
| AC-7 | `PosShiftsTest.php:214-249` (report across branches by id → 422) | covered for report by id | report by uuid across branches; close across branches; shift id from another tenant |
| AC-8 | `PosShiftsTest.php:40` (client `opened_at` instant preserved), `:93`/`:184` (report and close by client uuid) | partial | open with a past client time, close later, assert `closed_at`/`opened_at`/`received_at` |
| AC-9 | none for shift phases. `P:test/data/cloud_refunds_test.dart:482-509` covers refund-after-sale in one pass and `:510-551,580-646` the local hold paths for refunds and `:552-579` the `REFUND_EXCEEDS_SOLD` quarantine (integration-tagged); `shift_close_drain_test.dart` stubs only open/close and tests the reason text | gap for shift phases | POS drain test asserting phase order; scenarios listed in `BEHAVIORAL_ANALYSIS.md` A and B (planned tests, not yet written) |
| AC-10 | partial: `PosShiftsTest.php:93` (an order naming an open shift is counted), `C:tests/Feature/Pos/PosOrdersTest.php:350` (no shift named → unattributed) | partial | not tested: an order naming a closed or unknown shift, a payment inheriting the order's shift (no test sends `shift_client_id` to the payments endpoint), a refund naming a closed shift |

## Unit tests
POS: `P:test/domain/cash_movement_test.dart` (kinds, signs, totals), `P:test/domain/shift_ownership_test.dart`.

## Integration and API tests
Cloud feature tests above. Gaps to add: validation matrix (negative float, `amount_minor` 0, bad direction, 51 denominations, 256-character reason) including the 422 envelope; `pos.device` errors (no token, revoked terminal, feature off; `PosRefundsTest.php:395-399` asserts the feature gate for refunds); capability refusal 403 `POS_CAPABILITY_MISSING` for each of the three capabilities; null `acting_user_id` relaxation (documents current behavior); shift id from another tenant or branch → "Unknown shift".

## Flutter/Vue UI tests
Gap: no test asserts the post-close Z-report mask or that the closed dialog's subtitle (`shift_dialogs.dart:576-579`) shows the variance to a closer lacking `cash.variance.view` (`blind: !can(cashVarianceView)`, `shift_dialogs.dart:598`); `close_shift_blind_test.dart` covers only the pre-count view. The over/short mask is tested only for the Finance › Settlements pane (`P:test/features/shift_history_panes_test.dart:475-498`); the People › Shifts pane mask (`management_shifts_pane.dart:101-115`) is not tested.
POS widget: `P:test/features/close_shift_{blind,dialog,note}_test.dart`, `P:test/features/cash_dialogs_test.dart`, `P:test/features/shift_history_panes_test.dart`. Vue: no framework; the home tiles (`HomeView.vue:179-190`) have no test — plan a manual check. The API side of the tile has `C:tests/Feature/DashboardStatsTest.php:138` (null case).

## Security and tenancy
Cross-tenant isolation of shifts and cash movements via device tokens of two restaurants; branch scope on `report`/`close`; device-token required (401/403 without); `throttle` behavior not tested.

## Order/pricing/payment invariants
Expected cash with card/wallet payments and refunds (non-cash must not enter expected cash); money stays integer minor units.

## Regression and manual QA
Manual: open on a till, sell cash and card, pay-out, close short and over, restart the till mid-shift, take the cloud offline and reconnect, check dashboard tiles.

## Test data/fixtures
Cloud: `PosTestCase` base (`C:tests/Feature/Pos/PosTestCase.php`). POS: `P:test/data/pg_fixture.dart` (throwaway databases) and `lib/data/fakes` for UI tests.
