# Test plan: POS business day

## Test environments
Flutter unit and widget tests with no database (`env -u POS_PG_HOST flutter test`). PostgreSQL-backed tests need `POS_PG_HOST` and **a dedicated server** (see TEST_REPORT.md: the shared development server is in doubt after an unexplained loss of databases; do not point these at it).

## Unit tests
| Criterion | Test |
| --- | --- |
| AC-1 date for the moment, 06:00 roll-over | `P:test/domain/business_day_service_test.dart`: *opens the day the moment belongs to*, *02:00 is still last evening* |
| AC-2 reuse any open day | same file: *a day that is already open is used*, *a day left open from yesterday is still used* |
| AC-4 never throws | same file: *a database failure is reported and never thrown*, *an open that fails with nothing to take is a failure*, *a date that was already closed is reported, not thrown*; `P:test/features/business_day_providers_test.dart`: *nothing inside the glue can throw into the shift dialog* |
| BR-5 race | *losing a race to another till takes the day it opened* |
| BR-8 notices | `dayNotice` group: stale day, today's day open, closed today with a shift open, yesterday closed, no shift open |

## Integration and API tests
`P:test/data/business_day_opening_test.dart` (**written, not run**): day opened for the person and the shift filed under it, shift with no day stays NULL, asking twice opens one day, stale day reused without a second row, four tills on one date, tills straddling 06:00 (different dates, one-open-day index), closed date reported and nothing reopened.

## Flutter/Vue UI tests
`P:test/features/business_day_opening_ui_test.dart`: the day opens **before** the shift (`['day:rana','shift','start']`); a failed or already-closed day does not stop the shift; lock-screen sign-in on an open shift opens the day, with no shift it does not; stale-day and closed-today banners in English; stale-day banner in Arabic; no banner when there is nothing to say; both sentences worded with the date. `P:test/features/business_day_providers_test.dart` runs the **real** providers: opened on behalf of the person (`openedBy == [4]`), `businessDayProvider` refreshed after opening, stale notice only for an old open day.

## Security and tenancy
No new capability, endpoint or tenant-scoped query. Existing day close and restore guards are unchanged and keep their own tests.

## Order/pricing/payment invariants
No total, tax, rounding or tender calculation changes. Gap: the stamping of orders and refunds by the trigger is covered only by existing tests (`P:test/data/business_day_stamping_test.dart`, PostgreSQL-backed).

## Regression and manual QA
Manual walk on a **throwaway** database as owner and cashier (not done yet): first shift opens a day → first sale → Home shows it → Close the day → automatic backup → restore guard; then a late shift on the closed date shows the notice; a day left open overnight shows the stale banner.

## Test data/fixtures
`P:test/support/fake_business_days.dart` (`FakeBusinessDays`, `testDay`): one open day, closed-date refusal, race winner, failure switches, records who opened.
