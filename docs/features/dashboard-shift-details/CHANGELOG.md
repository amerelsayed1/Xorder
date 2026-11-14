# Changelog — dashboard-shift-details

## 2026-11-09 — built (xorder-cloud `feat/dashboard-shift-details`, uncommitted)
- Home's Current shift card opens a shift details page.
- Force close for a shift whose till was revoked: counted cash + reason, `pos.shift_close`, server-computed difference, audit event.
- New nullable column `pos_shifts.closed_via`.
- Orders page opens an order's sheet from `?order=ID`.
- Fix (same day, from the owner's first try on shift 6): the counted-cash field refused a grouped amount such as `4,995.00` (the format the page itself shows) with "Enter the counted cash". It now drops thousands separators (`,` with a point, `4,995`, spaces, Arabic `٬`) and reads Arabic digits and `٫`; a lone comma is still a decimal separator (`12,50`). The error now gives an example.
- Home's Current shift card shows the date as well as the time when the shift opened on an earlier day (`26 سبتمبر، 10:55 ص` / `Sep 26, 10:55 AM`), and the year when it is not this year; today's shift still shows the time alone.
