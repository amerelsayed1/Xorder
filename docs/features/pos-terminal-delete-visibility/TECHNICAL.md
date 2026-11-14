# Delete only offered when the server would accept it — technical plan (XORD-042)

Status: approved 2026-11-03 (owner: "Yes, log and fix", option 1) · Repo: xorder-cloud, branch `feat/finance-accounts-and-platform-updates-2026-10-26` at `775bf0f` (36 unrelated uncommitted files; none of the files below were dirty before this work)

## Specification
`docs/qa/XORDER_QA_FINDINGS.md` › XORD-042. The server rule is unchanged: `PosProvisioningService::delete` refuses an active terminal (`TERMINAL_STILL_ACTIVE`) and one with money history (`TERMINAL_HAS_HISTORY`): any order on it, or a shift that closed, was counted, or opened with a float.

## Acceptance criteria
- AC-1. Both terminal lists (`GET api/dashboard/pos/terminals`, `GET api/admin/restaurants/{r}/terminals`) carry `has_money_history` (boolean) per terminal.
- AC-2. It is true exactly when `delete()` would answer `TERMINAL_HAS_HISTORY`: an order, or a traded shift; false for no shift or only an untraded open shift.
- AC-3. The flag is computed in the list query (constant number of queries, no per-row lookup).
- AC-4. Other responses that use `PosTerminalResource` keep their shape (field omitted when not computed).
- AC-5. The dashboard and Super Admin pages show Delete for a revoked terminal only when `has_money_history` is not true, and otherwise a note that the record is kept because it has sales history (en + ar).
- AC-6. If a delete is still refused, the dashboard titles the message "Not deleted" instead of the generic error title.

## Stages
1. **API** `app/Services/PosProvisioningService.php`: extract the traded-shift predicate into one private method used by `delete()` and by a new `withMoneyHistory(Builder)` that adds an `EXISTS … OR EXISTS …` column. Engine-neutral SQL (SQLite and PostgreSQL). `withoutGlobalScopes()` as in `delete()`.
   `Dashboard\PosTerminalController::index`, `Admin\RestaurantTerminalController::index`: wrap the query.
   `Http/Resources/PosTerminalResource.php`: `has_money_history` via `when()` only when the column was selected.
   Tests: `tests/Feature/Pos/PosProvisioningTest.php` (dashboard list: none, untraded shift, traded shift, order; query count constant), `tests/Feature/Admin/TenantCreationTest.php` (admin list).
2. **Web** `apps/xorder-cloud/apps/web/src/pages/dashboard/PosTerminalsView.vue`, `apps/xorder-cloud/apps/web/src/pages/admin/RestaurantDetails.vue`, `apps/xorder-cloud/packages/ui/src/i18n/index.js` (two keys, en + ar). No JS test framework exists; verified by `pnpm build` and by reading.
Rollback: revert the files; no schema or data change.

## Compatibility
Additive field on two dashboard-only endpoints; the POS does not call them. API and web deploy together from the same repo. Nothing reaches `main` without the owner and `/release-check`.

## Domain
Neutral for every venue model: it changes only which button the back office shows.
