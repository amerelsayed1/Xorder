# Dashboard shift details and force close

**Status:** built 2026-11-09, uncommitted, xorder-cloud branch `feat/dashboard-shift-details` (off `development` `c2191fb`). Not validated.

## What
1. Clicking the **Current shift** card on the dashboard Home opens a page for that shift (`/admin/shifts/{id}`): till, branch, who opened and closed it and when, the drawer figures, sales per payment method, its orders (each opens the order sheet) and its cash movements.
2. A shift whose **till was revoked while the shift was open** can be **force closed** from that page. The till can never close it itself (a revoked till cannot sync), so before this the shift stayed open for ever and kept showing on Home.

## Owner decisions (2026-11-09)
| Question | Decision |
|---|---|
| Which shifts can be force closed | **Revoked tills only.** The server still accepts a live till's sales into a closed shift, and the till's own later close would be refused (`SHIFT_NOT_OPEN`). |
| What the closer enters | **Counted cash and a reason, both required.** |
| Who | **Anyone whose role holds `pos.shift_close`** (owners hold every capability). |

## Rules
- Reading a shift needs `analytics.view` (the Home card's own gate) and the `pos` feature. Another restaurant's shift is a 404.
- Force close: `pos.shift_close` + `subscription.writable` + `pos` feature. Refused with `TERMINAL_NOT_REVOKED` if the till is not revoked, `SHIFT_NOT_OPEN` if already closed. Checked under a row lock on the shift.
- Expected cash and the difference are computed by the server with the till's own formula (A3); the closer never types the difference.
- Closed at the server's time, `closed_by` = the dashboard user, `closed_via = dashboard`, reason saved in `variance_reason`, audit event `pos_shift.force_closed`.

## Venue models
Helps every venue that runs a till (café, restaurant, food truck): a replaced or lost till no longer leaves a shift open for ever. Cloud kitchens without a till are unaffected (no `pos` feature, no card).

## Not included
A list of past shifts; force closing a live (not revoked) till's shift; any POS app change.
