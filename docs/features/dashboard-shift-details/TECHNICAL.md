# Technical — dashboard-shift-details

Paths are in `apps/xorder-cloud/` (worktree `.claude/worktrees/shift-details`, branch `feat/dashboard-shift-details`).

## API
- `app/Http/Controllers/Dashboard/PosShiftController.php` — `show`, `forceClose`, `present()` (dashboard-only shape).
- `app/Http/Requests/Dashboard/ForceCloseShiftRequest.php` — `counted_cash_minor` integer ≥ 0, `reason` 3–500 chars, both required.
- `app/Services/PosShiftService.php`
  - `summary(PosShift)` — the till report's figures, extracted from `report()` (which now calls it), so the till and the dashboard read the same numbers.
  - `forceClose(PosShift, User, int, string)` — transaction, `lockForUpdate` on the shift row, re-checks open + terminal revoked, `expectedCash()`, variance, `closed_via=dashboard`, `AuditLogger::record('pos_shift.force_closed')`.
- `app/Models/PosShift.php` — `CLOSED_VIA_DASHBOARD`, `branch()`, `closedBy()` relations.
- `routes/api.php` — two routes inside the dashboard `feature:pos` group.
- `lang/{en,ar}/xorder.php` — `errors.pos_shift_not_open`, `errors.pos_shift_terminal_not_revoked`, `messages.pos_shift_force_closed`.

## Web
- `apps/web/src/pages/dashboard/ShiftView.vue` — page + force-close dialog (counted cash parsed with `amountToMinor`, never a float).
- `apps/web/src/router/index.js` — `dashboard.shift` (`shifts/:id`, `capability: analytics.view`).
- `apps/web/src/pages/dashboard/HomeView.vue` — the card's heading is a link stretched over the card (one link for keyboard and screen readers) + "Open shift details" hint.
- `apps/web/src/pages/dashboard/OrdersView.vue` — `?order=ID` opens that order's sheet from the details request.
- `packages/ui/src/i18n/index.js` — `shift.*` strings, English and Arabic.

## POS impact
None. The till-facing `PosShiftResource` is unchanged; `closed_via` is not sent to tills. A revoked till never syncs again.

## Cross-app
Dashboard-only. No POS contract change, no `BACKEND_TO_POS.md` entry needed.
