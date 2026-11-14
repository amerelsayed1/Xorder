# Feature changelog: POS business day

## Unreleased

## 2026-10-24: the business day is opened
- Status: implemented in the working tree of `apps/xorder-pos` (branch `fix/offline-audit-2026-10-24`, **uncommitted**); documented as `drafted`.
- Changes: new `ensureBusinessDay` / `dayNotice` (`P:lib/domain/services/business_day_service.dart`); `ensureBusinessDayProvider` and `dayNoticeProvider` (`P:lib/app/providers.dart`); the shift-open dialog opens the day before inserting the shift; lock-screen sign-in on an open shift ensures the day; the start screen shows a notice for a day left open or already closed (English and Arabic).
- Why: no code path opened a business day, so Home said "no business day opened yet", sales stayed unfiled and "Close the day" could never appear (offline audit F-3).
- Decisions (approved): open automatically with the first shift; open the shift with a notice if the date is already closed; keep using a day left open and say so.
- Compatibility notes: no migration, no API or payload change. Visible after install: the "Close the day" button appears; restore is refused while a day is open; day-close totals become non-zero.
- Verification: see TEST_REPORT.md. PostgreSQL tests written, not run.
