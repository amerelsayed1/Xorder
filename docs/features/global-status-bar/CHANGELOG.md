# Changelog — global-status-bar

## 2026-10-26 — built (xorder-pos, uncommitted)
- New `lib/app/till_status_bar.dart`: `TillStatusBar` (moved from `management_screen.dart`'s private `_StatusBar`) and `BackOfficeConnectionPill` (moved, name unchanged). Keys renamed `back-office-status-*` → `till-status-*`. The person comes from `actingStaffProvider`, is `Flexible` and ellipsizes, and is not drawn when `showPerson` is false. The bar has a `Material` of its own, because it now sits above every screen's Scaffold.
- `lib/app/app.dart`: mounted once, under the router, as the last child of a `Column` in the settings bar's child. Not on `/welcome`, `/setup` or before the router has a path; the person is hidden on `/` (Start) and `/lock`.
- `management_screen.dart`: its own mount, class and unused import removed.
- `pos_top_bar.dart` (sale): the connection pill and `branch · terminal` removed; the tenant tile and name, order-type switch, drawer, shift, Lock, Close shift and the operator's name stay.
- Tests: new `till_status_bar_test.dart` (9); `back_office_shell_test.dart` loses its status-bar group and now asserts Management draws none; `admin_entry_test.dart` uses the header as its "inside" marker.
- Behavior changes to know about: the sale screen no longer prints the till's *code* (only the till's *name*, in the bar); every screen is 44 px shorter.
