# API — dashboard-shift-details

Both under `/api/dashboard`, JWT, tenant roles, `feature:pos`.

## `GET pos/shifts/{shift}` — `can:analytics.view`
404 for another tenant's shift. Response `data`:
`id, status (open|closed), closed_via (null|dashboard), branch {id,name_ar,name_en}, terminal {id,name,revoked}, opened_by, closed_by, opened_at, closed_at, opening_float_minor, counted_cash_minor, expected_cash_minor, variance_minor, variance_reason, can_force_close, summary {orders_count, sales_minor, sales_by_tender[{tender_type_id,name,kind,amount_minor,payments}], cash_in_minor, cash_out_minor, refunds_minor, refunds_count, cash_refunds_minor}, orders[{id,code,invoice_number,status,total_minor,created_at}], cash_movements[{id,direction,amount_minor,reason,occurred_at}]`.
`expected_cash_minor` is live for an open shift, stored for a closed one (same as the till report). `can_force_close` is a hint; the server re-checks.

## `POST pos/shifts/{shift}/force-close` — `can:pos.shift_close`, `subscription.writable`
Body: `{ counted_cash_minor: int ≥ 0, reason: string 3–500 }`, both required (422 `errors.*` otherwise).
- 200 `{ message, data }` (same shape as GET).
- 422 `code: TERMINAL_NOT_REVOKED` — the till is not revoked.
- 422 `code: SHIFT_NOT_OPEN` — already closed (also the second of two simultaneous requests).
- 403 without the capability; 404 for another tenant's shift.
Not idempotent by key: a retry after success gets `SHIFT_NOT_OPEN`, and the page reloads to show the closed shift.
