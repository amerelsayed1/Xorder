# Dashboard order sheet matches the cashier's receipt — dashboard-order-receipt-parity

Status: implemented (uncommitted, cloud branch `feat/xord-048-order-sheet`) · 2026-11-07 · Source: the owner, comparing ORD-121 on the local dashboard with the till's receipt: "this should be same as cashier recipet" · Verified against: xorder-cloud `775bf0f` (+ another session's uncommitted guest-paging edits in `OrderResource.php`), xorder-pos `effdffb`

## 1. Summary
When a manager opens an order on the dashboard (Orders → تفاصيل), the sheet should carry what the customer's receipt carried: the invoice number, date and time, cashier, till, order type with table, every line with its quantity and price, subtotal, discount, service, VAT, total, and how it was paid. Today the sheet shows the time, type, customer, status, lines and total only.

## 2. Why
A manager answering "the customer says they paid 2,089 by card at table 3 at 10:24" has to match a paper receipt to a dashboard row. With no invoice number, cashier, till, table, tax lines or payment on the sheet, they cannot. It hurts every venue that sells through a till: cafés (counter, many small receipts), restaurants (table, rounds), food trucks and cloud kitchens (their only record of a sale is the till's). Diner orders from the online menu have no till receipt; for them the sheet shows what exists and leaves the rest out.

## 3. Goal and success
For a till sale, every field printed on its receipt can be read on the dashboard sheet, with the same values. For a diner order, nothing on the sheet is invented: no cashier, till or payment where none exists.

## 4. Users, roles and permissions
Whoever can open order details today: dashboard route `/admin/orders`, `RESTAURANT_ADMIN` or staff with `orders.view` (`TenantCapability`), under `feature:orders`. No new permission. Tenant isolation as today (`RestaurantScope`; another restaurant's order → 404).

## 5. Today
- **Receipt (POS)** `apps/xorder-pos/lib/features/receipt/receipt_document.dart`: business name and logo, date, time, order number, cashier, till, order type · table, lines (name, qty, price), subtotal, VAT with its rate, total, payment method, paid, a queued/provisional note, footer.
- **Cloud has the facts** for a till sale (verified on local `orders.id = 121`): `invoice_number`, `subtotal_minor`, `discount_minor`, `tax_minor`, `charges_minor`, `total_minor`, `table_id`, `dining_area_id`, `pos_terminal_id`, `acting_user_id`, `pos_shift_id`, `branch_id`; payments in `order_payments` (`tender_type_id`, `amount_minor`); lines in `order_items` / `items`.
- **API** `apps/xorder-cloud/apps/api/app/Http/Resources/OrderResource.php` returns `code`, `status`, `items`, `total`, `customer_*`, `table_id`, `order_type`, `source`, timestamps — none of the money breakdown, invoice number, cashier, till, table label or payments.
- **Sheet** `apps/xorder-cloud/apps/web/src/pages/dashboard/OrdersView.vue` details dialog: time (relative), type, customer, status, lines, total.
- **Related, already logged:** XORD-058 (the till prints its own number, the cloud uses another); XORD-048 (the table is not shown); the customer is not sent with a till sale (XORD-001 "Remaining").
- UNVERIFIED: how the branch's receipt profile (`PosReceiptView.vue`, header/footer) should appear on the sheet, if at all.

## 6. Scope
**In:** the order details sheet and the order API fields it needs, for till sales and diner orders. Read-only.
**Out:** printing or re-printing from the dashboard (suggestion, Q2); editing an order; refunds and voids on the sheet beyond showing that they happened (Q3); fixing XORD-058 itself (the number shown follows whatever that fix decides); sending the customer from the till (separate change, needs approval).

## 7. Behavior and business rules
- **BR-1** The sheet's money figures come from the stored order (`*_minor`), never recomputed in the browser.
- **BR-2** The invoice number shown is the cloud's (`orders.invoice_number`), the one the till's reprint shows (`coalesce(server_invoice_number, invoice_number)`). If XORD-058 changes what the receipt prints, both must agree.
- **BR-3** Cashier = `acting_user_id`'s name; till = `pos_terminal_id`'s name; table = `table_id`'s label with its dining area — each shown only when the order has it.
- **BR-4** Payments are listed as recorded (method name in the viewer's language, amount); a sale paid by two methods shows both.
- **BR-5** VAT and service are shown with their amounts; the rate is shown only if the order stores it (UNVERIFIED that it does; otherwise amount only).
- **BR-6** Arabic and English, RTL, digits as the dashboard already renders money.

## 8. Acceptance criteria
- **AC-1** Given a paid till sale, when its details open, then the sheet shows invoice number, date and time, cashier, till, order type and table, each line with qty and price, subtotal, discount, service, VAT, total, and each payment — equal to the stored order.
- **AC-2** Given a diner order from the menu, when its details open, then no cashier, till or payment rows appear, and nothing shows an invented value.
- **AC-3** Given an order of another restaurant, when its details are requested, then 404 (unchanged).
- **AC-4** Given the API, when an order is returned, then the new fields are additive and every existing key is unchanged.
- **AC-5** Given the Arabic dashboard, the sheet reads right to left with the same fields.

## 9. Edge cases and failure modes
Split payment; zero tax; discounted sale; refunded sale (`refunded_minor` > 0, Q3); a till or cashier since deleted (show the stored id's last known name or "—", never fail); a table since deleted; very long orders (20+ lines, the sheet already scrolls); an order from before these columns existed (fields absent → rows hidden).

## 10. Impact
Cloud only: `OrderResource` (additive fields, eager loads for user, terminal, table, area, payments with tender type — watch N+1 on the list), `Dashboard\OrderController::show`/index loading, `OrdersView.vue` sheet, `packages/ui` i18n (en, ar). No schema change expected. No POS change. **Overlap:** `OrderResource.php` and `Dashboard/OrderController.php` carry another session's uncommitted guest-paging edits — build in a worktree or after they land.

## 11. Dependencies, known gaps, risks
Depends on XORD-058's decision for which number is "the" number. Tips are a known gap (domain handbook §3): none shown because none exist. Risk: loading payments and names for the list view could slow `/admin/orders`; load them on the details request only.

## 12. How it will be tested
Feature tests on the order API: a seeded till sale returns every AC-1 field with stored values (AC-1, AC-4); a diner order returns none of the till-only fields (AC-2); cross-tenant 404 (AC-3); split payment returns two payments. Vue: `pnpm --filter @xorder/web build`; the sheet itself (AC-1 layout, AC-5 RTL) needs a person to look, or a browser check on the local stack.

## 13. Decisions and open questions
- **Decided (2026-11-07, owner):** the dashboard sheet should match the cashier's receipt.
- **Decided (2026-11-07, owner) — Q1:** the cloud's invoice number is the one shown on the sheet and on reprints; a cloud till's first print says PROVISIONAL (XORD-058).
- **Q2** (suggestion) A "print receipt" button on the sheet, using the branch's receipt profile?
- **Q3** Show refunds and voids on the sheet (what was refunded, by whom, when)?
- **Q4** Show the customer (needs the till to send it — separate approved change)?

Next: `/implement dashboard-order-receipt-parity` — needs approval of the API fields (additive); Q1 is decided; no migration, no POS change.

## 14. As built (2026-11-07, cloud branch `feat/xord-048-order-sheet` from `development` `d5bb5cb`, uncommitted)
- **API:** new `GET /api/dashboard/orders/{order}` (numeric id; `feature:system_ordering|pos`, `can:orders.read`). Another business's order is 404 through the tenant scope on the route binding, before the plan check. Returns every list key plus, only on this request: `invoice_number`, `terminal_name`, `cashier_name`, `dining_area {name_ar, name_en}`, `subtotal_minor`, `discount_minor`, `charges_minor` (service), `tax_minor`, `total_minor`, `refunded_minor`, `payments[] {tender_name, tender_kind, amount_minor, received_at}` (in recorded order). A diner order returns these as null and `payments: []`.
- **List:** each row gains `table_label` (one extra eager load, `table:id,label`, which the CSV export already used). No payments are loaded on the list.
- **Sheet (`OrdersView.vue`):** opens at once with the row, then swaps in the details request; on failure the row stays. Title = invoice number (subtitle `ORD-n · receipt`), date and time, type, table · area, customer, status, branch, cashier, till, payment word, handled by, lines, subtotal / discount / service / VAT, total, each payment, refunded. A row with no value is hidden.
- **BR-4 deviation:** tender types store one `name`, so the payment line shows that name as typed, not per language.
- **BR-5:** the rate is not stored on the order; the sheet shows the VAT amount only.
- **Not answered:** Q2 (print from the sheet), Q3 (refund detail beyond the refunded amount), Q4 (customer — group G2).
- **Tests:** `tests/Feature/Pos/OrderReceiptSheetTest.php` (5). Screen checked in the built-in browser against a stubbed API only.

