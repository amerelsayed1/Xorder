# Test plan — dashboard-shift-details

Automated (`apps/api/tests/Feature/Pos/DashboardShiftTest.php`):
1. The page reads the same figures as the till report (float, A3 expected cash, sales, cash in/out, orders, movements).
2. Another tenant's shift: 404 on read and on force close; shift stays open.
3. Reading needs `analytics.view` (403 without, 200 with).
4. Force close on a revoked till: closed, `closed_via=dashboard`, counted/expected/variance from the server, reason, closed_by, no payload hash.
5. A live till's shift is refused (`TERMINAL_NOT_REVOKED`), stays open.
6. A closed shift is not closed twice (`SHIFT_NOT_OPEN`), first count kept.
7. Counted cash and reason both required; negative count refused.
8. Force close needs `pos.shift_close` (403 with only `analytics.view`; 200 with it).

Manual (Docker `:8080`): card opens the page; figures; order link opens the sheet; dialog validation; Arabic RTL. Still to do by hand: an actual force close, English locale, dark theme, phone width.

Not covered: two simultaneous force closes (the row lock is reviewed by reading; SQLite cannot exercise it).
