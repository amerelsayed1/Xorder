# Feature specification: POS business day (opening it, and saying when it is wrong)

Status: **drafted** (not validated). Documented against POS `main f78bfa7` **plus uncommitted work** (the business-day change itself; see TEST_REPORT.md) · 2026-10-24 · cloud not involved. Paths are workspace-relative, `P:` = `apps/xorder-pos/`.

## Summary
A trading day ("business day") is the unit Home, day close, the automatic backup and the restore guard work in. The schema, the day-close dialog, the date rule and the stamping trigger already existed, but **nothing in the product opened a day** (found driving the real till offline, report `docs/testing/reports/2026-10-24-project-test-report-pos-backoffice-offline.md`, F-3). This feature adds the missing caller: the first shift opened or resumed opens the day, and the start screen says when a day was left open or was already closed.

## Scope and exclusions
- In: opening/reusing the day on shift open and on lock-screen sign-in with a shift open; a start-screen notice; both languages.
- Out (separate items): sending the business day to the platform (CB-10, PROPOSED, `P:docs/coordination/BACKOFFICE_TO_CLOUD.md:347-352`); a back-office screen for `day.start_time`; a "reopen day" action; changing day-close blockers; any migration.

## Actors and permissions
- Whoever opens a shift or signs in on an open shift opens the day on their behalf (`pos_business_days.opened_by`); no new capability. Closing keeps `PosCapability.dayClose` / `dayForceClose` with approval (`P:lib/features/cash/presentation/day_close_dialog.dart:318`).

## Cloud flow
None. No request, response or payload carries the day (`grep P:lib/data/cloud`: only the branch-sales query parameter).

## Desktop POS flow
1. Open-shift dialog: after the person is verified, `ensureBusinessDayProvider(staff)` runs **before** the shift row is inserted (`P:lib/features/shift/presentation/shift_dialogs.dart:123`), then the shift opens regardless of the outcome.
2. Lock screen: after a successful PIN sign-in, when a shift is open, the same call runs, not awaited (`P:lib/features/lock/lock_screen.dart:125`).
3. The start screen derives a notice from current state and shows it (`P:lib/features/start/start_screen.dart:224,382`).

## Business rules (as built)
| ID | Rule | Evidence |
| --- | --- | --- |
| BR-1 | One open day per branch, held by the database. | `P:lib/data/postgres/migrations.dart:1486` (`pos_business_days_one_open`) |
| BR-2 | A day opens for `DayPolicy.dateFor(now)`: local time, rolling over at `day.start_time` (default 06:00), so 02:00 belongs to yesterday. | `P:lib/domain/models/pos_settings.dart:179-205`; `P:lib/app/providers.dart:524` (`dayPolicyProvider`) |
| BR-3 | An open day of any date is reused; a second day is never opened. | `P:lib/domain/services/business_day_service.dart:58-70` |
| BR-4 | The till never stops selling because of the day: the service and the provider closure return a result and never throw; the shift opens whatever the outcome. | `business_day_service.dart:58-95`; `P:lib/app/providers.dart:559-593` |
| BR-5 | If another till wins the race (the one-open-day index), the winner's day is taken. | `business_day_service.dart:75-82` |
| BR-6 | A date whose day is already closed is reported (`dateAlreadyClosed`); `open()` refuses to resurrect it, and selling continues unfiled. | `P:lib/data/postgres/postgres_business_day_repository.dart:86-118`; `business_day_service.dart:84-90` |
| BR-7 | A row (order, refund, shift) is filed under the day whose time window contains its own time (`occurred_at` / `opened_at`), else left NULL. **Migration 36 replaced migration 35's "whichever day is open".** | `P:lib/data/postgres/migrations.dart:3343-3392` |
| BR-8 | Notices: an open day dated before today's business date → `staleOpenDay`; no open day, a shift open and today's date closed → `todayAlreadyClosed`. Derived each time, never stored. | `business_day_service.dart:118-137`; `P:lib/app/providers.dart:595` |
| BR-9 | Day close (existing): needs `dayClose`/`dayForceClose`, lists blockers (open shift, parked ticket, unpaid order), totals orders **by `business_day_id`**, takes the automatic backup. | `P:lib/data/postgres/postgres_business_day_repository.dart:121-200`; `day_close_dialog.dart:62-76` |
| BR-10 | Restore from a backup is refused while a day is open. | `P:lib/data/backup/backup_service.dart:378-396` |

## Edge cases and failure handling
- A day left open from an earlier date keeps collecting sales until someone closes it, so its gross spans several calendar dates; the start screen says so.
- Close the day, then trade again on the same business date: the next shift opens, rows stay unfiled, the notice appears. Expected to happen in real use (a café closing early); say so in release notes.
- A shift already open when the change is installed keeps `business_day_id` NULL (the trigger fires on INSERT only); sales made before the day's `opened_at` stay unfiled. One-time under-reporting on the first day after upgrade.
- The notice is computed once; a start screen left idle across 06:00 shows it only after something invalidates it.
- An unconfigured till (no database) logs one `debugPrint` per sign-in; harmless.

## Acceptance criteria (approved 2026-10-24: Q1 auto with the first shift, Q2 open the shift with a notice, Q3 keep using a stale day with a banner)
- AC-1 Opening or resuming a shift with no open day opens one for `DayPolicy.dateFor(now)`, by the person opening.
- AC-2 An open day of any date is used; no second day is opened.
- AC-3 Orders, refunds and the shift written while a day is open are filed under it (existing trigger, migration 36).
- AC-4 A failed or refused day never blocks a shift or a sale; the outcome is returned, not thrown.
- AC-5 A day open from an earlier date is still used and the start screen says so, in both languages.
- AC-6 Closing, its blockers and the backup hook behave as before.
- AC-7 Offline and cloud-mode tills behave the same; no payload, contract or migration change.

## Confirmed source references
`P:lib/domain/services/business_day_service.dart`; `P:lib/app/providers.dart:524,550,559,595`; `P:lib/features/shift/presentation/shift_dialogs.dart:123`; `P:lib/features/lock/lock_screen.dart:125`; `P:lib/features/start/start_screen.dart:224,382`; `P:lib/core/l10n/app_strings.dart` (`dayStillOpenFrom`, `dayClosedTodayNotice`); `P:lib/data/postgres/postgres_business_day_repository.dart`; `P:lib/data/postgres/migrations.dart:1448-1486,3246-3392`.

## Venue models
Café and food truck (counter, pay first, unreliable signal, seconds per sale): no extra tap, works offline, never blocks (BR-4). Restaurant: the 06:00 roll-over keeps a 2 a.m. close on the evening's date. Cloud kitchen / 24-hour trade: a fixed 06:00 roll-over can cut a night in two; no screen to change it was found. **Known domain gap, not worked around.** No dependency on tips, loyalty, recipes, aggregators or multi-brand.

## Unknowns and assumptions
- **UNVERIFIED:** whether any back-office pane writes `day.start_time` (only the reader `pos_settings.dart:191` was found).
- **UNVERIFIED:** the till uses device local time as the branch's time zone; not checked for cloud tills.
- **UNVERIFIED:** all PostgreSQL behaviour of the new tests (`P:test/data/business_day_opening_test.dart`, not run).
- First real use of day close, backup-on-close and the restore guard may surface latent bugs: that code was tested but never reachable in an install.

## Amended 2026-10-27 by `pos-signin-first-home`
- The day is still opened by the person opening the **first shift** (`shift_dialogs.dart`, `_open`) and, with a shift already open, on sign-in. The second caller moved: after a restart the person now signs in at **Start** (`SignInDialog`, `OpenShiftDialog(signInOnly: true)`), which runs `ensureBusinessDayProvider` (unawaited) when a shift is open, exactly as the lock screen does. Lock-screen sign-in is unchanged (`lock_screen.dart:183`).
- Signing in with **no** shift open opens no day. "Close the day" is therefore absent from Home until a shift has opened one (decision Q6, default).
- The close dialog records the closer from the **acting** person (`actingStaffProvider`), not only the till's (`day_close_dialog.dart:331`); proved by `test/features/cash_dialogs_test.dart` ("the closer is the person at the till", "…the administrator is the closer, not nobody").
- "Close the day" left the Start screen; it is on Home for holders of `day.close`.
