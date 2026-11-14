# Technical design: POS business day

## Architecture and modules
- Domain (pure, no Flutter or postgres imports): `P:lib/domain/services/business_day_service.dart`. `ensureBusinessDay({days, policy, now, by})` returns `BusinessDayResult{outcome: opened | reused | dateAlreadyClosed | failed, day, error}`; `dayNotice(...)` returns a `DayNotice{staleOpenDay | todayAlreadyClosed, date}` or null.
- DI: `P:lib/app/providers.dart`. `ensureBusinessDayProvider` is a function provider, so tests substitute it and both sign-in doors share one path; `dayNoticeProvider` derives the notice.
- UI: `P:lib/features/shift/presentation/shift_dialogs.dart:123`, `P:lib/features/lock/lock_screen.dart:125`, `P:lib/features/start/start_screen.dart:224,382`.
- Existing and unchanged: `BusinessDayRepository` (`P:lib/domain/repositories/repositories.dart:681-715`), `PostgresBusinessDayRepository`, `DayPolicy`, `DayCloseDialog`, migrations 35 and 36.

## Source references
See FEATURE.md "Confirmed source references".

## State and data flow
Shift dialog → `ensureBusinessDayProvider(staff)` → `ensureBusinessDay` → `days.current()` → (none) `days.open(date, by)` → committed (autocommit) → `shiftRepository.open` INSERT → trigger `pos_stamp_business_day('opened_at')` files the shift under the day whose window contains `opened_at`. Afterwards `ref.invalidate(businessDayProvider)`; `dayNoticeProvider` watches it, so the start screen, Home and the Close button refresh.
Lock screen: after `signInAs` succeeds and `shiftProvider` holds a shift, the same provider is called without awaiting.

## Dependencies
`DayPolicy` (`pos_settings.dart`), `PosStaff`, `shiftProvider`, `businessDayRepositoryProvider`. The Postgres day repository is bound only when a database is configured; otherwise `UnconfiguredBusinessDayRepository` throws on `open`, which the service reports as `failed`.

## Failure handling and observability
Never throws (BR-4). The service wraps everything; `ensureBusinessDayProvider` wraps again, covering `ref.read`, logging and invalidation (a provider-level test makes the policy provider throw and expects `failed`; the test fails if the guard rethrows). Failures are `debugPrint`ed, not shown. A race lost to the one-open-day index re-reads `current()`; a closed date is detected by asking `lastClosed(before: date + 1 day)` rather than by parsing the exception.

## Compatibility and rollout
POS only. No migration, no API or payload change, no cloud dependency. Old and new tills may share a branch database: the new one only files rows the existing trigger supports. Rollback: revert the commit; day rows already created are valid and harmless.
Visible changes after install: the start screen's "Close the day" button appears; restore is refused while a day is open; day-close totals become non-zero; the first day after upgrade can under-report (FEATURE.md edge cases).
