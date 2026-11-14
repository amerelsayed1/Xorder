# Changelog — pos-terminal-delete-visibility

## 2026-11-03 — XORD-042 (uncommitted)
- API: both terminal lists add `has_money_history` (boolean), computed by `PosProvisioningService::withMoneyHistory` with the same traded-shift predicate `delete()` uses. Additive; other terminal responses unchanged. Server rule unchanged.
- Web: dashboard Settings › POS devices and the Super Admin tenant page show Delete for a revoked terminal only when it has no money history, otherwise "Kept: has money history" (en, ar). A refused delete on the dashboard is titled "Not deleted".
- Review: no blockers. Open: index on `orders.pos_terminal_id` (owner decision); cash-movement gap logged as XORD-043.
