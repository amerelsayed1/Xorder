# Scenario test — table order, happy path (production)

- **Date:** 2026-11-06
- **Environment:** production, https://scenario-cafe.xorder.io (owner's express authorization in chat). Built-in browser of the Claude desktop app.
- **Cloud source revision read alongside:** `xorder-cloud` `775bf0f` (the deployed build was not checked against it — UNVERIFIED that production runs this revision).
- **Tenant:** "Scenario Café" (slug `scenario-cafe`), created by the owner from Super Admin. Test data only: diner "Test Diner", phone 01000000001.
- **Kind of test:** manual end-to-end through the real UIs. No automated test was written or run.

## Scope

Super Admin creates a client with full features → restaurant admin prepares menu, dining area, tables, QR → diner orders from a table (2 rounds) → restaurant receives it → diner asks for the bill → staff close the visit.

## Results

| # | Step | Actor | Result | Evidence |
|---|---|---|---|---|
| 1 | Create restaurant + its admin | Owner (Super Admin) | DONE by owner (Claude does not create accounts or type passwords) | restaurant exists, `GET /api/public/restaurants/scenario-cafe/menu` → 200 |
| 2 | Full-feature plan | Owner | PASS (by observation) | public menu: `ordering_mode: system`, `order_types: [dine_in, pickup, delivery]`, `internal_reviews: true`; dashboard nav shows live, orders, tables, inventory, purchasing, team, reports. Feature list itself not read. |
| 3 | Admin sign-in | Owner | DONE by owner | dashboard loaded at `/admin` |
| 4 | Categories | Admin | PASS | مشروبات, أطباق رئيسية created |
| 5 | Items + option group | Admin | PASS | قهوة تركي 40 (+ group إضافات: شوت إضافي +10), عصير برتقال 55, برجر لحم 150, مكرونة بالفراخ 120; categories page: 2 + 2 items |
| 6 | Dining area | Admin | PASS | الصالة الرئيسية (indoor, main branch) |
| 7 | Tables (bulk) + QR | Admin | PASS | T1–T5 created in one bulk save, all active/available; T3 QR = `/menu/t/6A7DNYWMNK` |
| 8 | Staff user | — | NOT RUN | needs account creation, which Claude does not do on a live site; owner to do or skip |
| 9 | Diner opens table QR | Diner | PASS | banner "طاولة T3 – الصالة الرئيسية"; `GET public/tables/{token}` 200, `POST .../sessions` 201 |
| 10 | Round 1 | Diner | PASS | 2× coffee + extra shot (2×50=100) + burger 150 = 250; `POST public/.../orders` 201; success "ORD-61" |
| 11 | Restaurant receives | Admin | PASS | Orders: ORD-61, dine-in, 250.00, NEW, tab title "(1)"; Live: T3 "1 active order" |
| 12 | Round 2 merges | Diner | PASS | juice 55 → `POST orders` 201, same ORD-61, live total 305.00, still one order on T3 |
| 13 | Bill request | Diner | PASS | Call staff → طلب الحساب → `POST public/sessions/{t}/bill-requests` 201; T3 red "طلب الحساب" on live board, bell count up |
| 14 | Staff acknowledges bill | Admin | PASS | "تم الاستلام" on the bill card cleared it |
| 15 | Close table visit | Admin | PASS | Live → T3 → إغلاق زيارة الطاولة → confirm; ORD-61 = تم الاستلام (completed) by Admin, today's sales 305.00, T3 free, board empty |
| 16 | Diner after close | Diner | PASS | reload → `GET orders/61/status` 200 → review prompt "كيف كانت تجربتك؟" (not submitted) |

Invoice in the order details matches line by line: 100 + 150 + 55 = 305.00 EGP.

## Findings (logged 2026-11-07 as XORD-047 to XORD-053, in this order)

1. **Diner-supplied line prices are trusted (security / money, from source, not exploited on production).** `PublicOrderController::store` sums the submitted `line_total`s; items carry no ids to re-price against (comment at the total computation). A modified request can set any price. Contradicts "backend is authoritative for prices". Severity: high. Verify with a local feature test, not on production.
2. **Order details do not show the table.** Orders list and the ORD-61 details sheet show type "داخل المكان" but not "T3"; only the live board ties the order to the table. Severity: low (enhancement).
3. **Complete is hidden for table orders on the Orders page, with no hint.** By design (`OrdersView.vue` `advanceActions` returns `[]` when `table_visit_id` is set; completion happens by closing the visit on the live board), but staff on the Orders page see no action and no pointer to the live board. Severity: low (UX).
4. **Dining areas are only reachable through Settings.** Tables page says "أنشئ منطقة جلوس أولاً" and disables Create; the sidebar has no Dining areas entry (route `/admin/dining-areas` redirects to `/admin/settings/dining-areas`). Whether the hint is a link was not checked — UNVERIFIED. Severity: low (UX).
5. **Diner menu category pill out of sync.** After scrolling back to the top, "أطباق رئيسية" stayed highlighted while Drinks was shown. Seen once. Severity: low.
6. **RTL punctuation in the table-service sheet.** "كيف نقدر نساعدك في الطاولة T3؟" renders as "؟T3". Severity: cosmetic.
7. **Send-order button looks disabled while enabled.** In round 1 the "إرسال الطلب" button was pale although `disabled=false` and the form was valid. Severity: cosmetic; cause UNVERIFIED.

## Not done / not covered

- Account creation (restaurant admin, staff user) and sign-in were done or left to the owner.
- POS: diner QR orders do not reach the till today (no POS client for them was found), so POS was out of scope.
- No tampered-price request was sent to production (finding 1 is from code).
- Feature flags were inferred from the public menu and the navigation, not read from the plan.

## Data left on production

Restaurant Scenario Café with 2 categories, 4 items, 1 option group, 1 dining area, 5 tables, 1 completed order ORD-61 (305.00 EGP, counted in today's sales and platform stats), 1 completed bill request, a customer record "Test Diner / 01000000001". Nothing was deleted.

## Next actions

- Owner: change the restaurant admin password shared in chat.
- Findings 1–7 are logged as XORD-047…053 (XORD-044…046 went to the POS parked-check bugs).
- Finding 1: `/bug-investigation` then `/implement`, with a local feature test for a tampered `line_total`.
- Optional: automate this scenario as a Laravel feature test so it runs in CI without touching production.
