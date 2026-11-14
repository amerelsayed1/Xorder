# Online orders and table requests on the POS — pos-incoming-cloud-orders

Status: proposed · 2026-11-06 (revised the same day after the owner moved table ordering to the waiter app) · Source: the owner's request, "I need to have all thing for ordering to be in pos app", following `docs/testing/reports/2026-11-06-scenario-table-order-production.md` · Verified against: xorder-cloud `775bf0f` (+ uncommitted guest-paging changes in `PublicOrderController.php`, `Order.php`, `Dashboard/OrderController.php`, `OrderResource.php`), xorder-pos `c67c754` (+ unrelated uncommitted UI changes) · Companion: `docs/features/waiter-app/FEATURE.md` (table ordering by waiters)

## 1. Summary

For a branch that runs the POS, everything diners send from the online menu arrives at the till instantly: **pickup and delivery orders**, and from a small **table QR**, **"request bill" and "call waiter"**. The cashier accepts or rejects each order; an accepted order becomes a normal POS ticket that is paid, printed and counted in the shift. Prices come from the server's menu, never from the diner's phone. Diners can no longer order food from the table — waiters do that on the waiter app — and online ordering is open only during the branch's working hours and while a till is online.

## 2. Why

- **Who is hurt today:** a restaurant, café or cloud kitchen that runs the POS. Online orders, bill requests and table visits appear only in the cloud dashboard (`/admin/orders`, `/admin/live`), so staff watch a second screen, re-key orders into the till to take payment, and the shift report misses that money (ORD-61 in the 2026-11-06 production test never touched the till).
- **Money risk:** diner line prices are written by the phone (`PublicOrderController.php:80-93`, `:299-307`).
- **Venue models:** café (pickup order-ahead) and cloud kitchen (delivery from its own menu) gain one queue at the till; restaurant gains bill/call-waiter at the till and waiter handhelds; food truck gains order-ahead but only while its till has signal (section 9).

## 3. Goal and success

- Every pickup/delivery order and every table request of a POS branch reaches the till within 1–2 seconds, with no dashboard needed.
- An online order is paid at the till like any POS sale and appears in the shift report and cash-up.
- The amount charged equals the server's menu price.
- Online ordering is never open outside the branch's working hours or while no till can receive it.
- Nothing is lost or charged twice when the till or the network drops.

## 4. Users, roles and permissions

| Actor | Can | Permission |
|---|---|---|
| Diner, online menu | place pickup or delivery orders during working hours | public routes |
| Diner at a table (table QR) | request the bill, call a waiter, cancel own request; **no ordering** | public routes, table session token |
| Cashier / waiter on the POS | see incoming orders and requests, accept/reject orders, mark requests handled | **new POS permission** (owner, 2026-11-06), e.g. `online_orders.accept`; name and default roles decided in the plan. Existing POS permissions: `lib/domain/models/permissions.dart:18-174` |
| POS device | read the branch's incoming events, post accept/reject/handled | device token (`PosDeviceAuth`, `bootstrap/app.php:63`); no route exists |
| Dashboard user | read-only for online orders and table requests of a POS branch | `orders.read` etc. (`routes/api.php:457-541`); write actions refused for POS branches |

Plan gate: `system_ordering` and `pos` (`Feature.php:37`). POS ships only inside the Restaurant and Business plans.

## 5. Today

| Area | Exists (evidence) | Missing |
|---|---|---|
| Online order create | `POST public/restaurants/{slug}/orders` (`api.php:887`); types pickup/delivery/dine_in (`StoreOrderRequest.php:28-33,64`) | item ids; server price |
| Line items | name, qty, variant, options (strings), note, `line_total` (`StoreOrderRequest.php:46-57`); stored with `unit_price = line_total / qty`, no `menu_item_id` (`PublicOrderController.php:299-307`) | menu item, variant and option ids |
| Working hours | branches store `business_hours` and `is_open` (`Branch.php:27-53`), shown in the menu's info modal (`apps/menu/src/components/RestaurantInfoModal.vue:18-24`); `WeeklyHours::isOpenAt` exists (`app/Support/WeeklyHours.php:28`) but is used only for category availability (`Category.php:58`) | ordering is **not** blocked outside hours today |
| Owner pause / plan | `accepts_orders` and plan-capped mode refuse orders (`PublicOrderController.php:47-69`) | — |
| Table QR | per-table token `menu/t/{token}`, session create (`api.php:924-926`), table orders bound to an OPEN visit (`PublicOrderController.php:115-167`) | a "requests only" table QR |
| Bill / call staff | one bill-request entity; "call staff" is a bill request with a note and suggestions Water, Napkins, Call waiter, Cutlery (`apps/menu/src/composables/useLocale.js:57,138`); statuses REQUESTED…CANCELLED (`BillRequestStatus.php:7-11`); routes `api.php:930-934` | typed request; device-side handling |
| POS ↔ cloud | POS pushes orders, payments, refunds, customers, shifts, cash movements, heartbeat (`lib/data/cloud/cloud_api.dart:194-244`); pulls only `GET pos/bootstrap` (`:190`); sync every 4 h idle / 30 min retry / ≥20 s after a sale (`cloud_sync.dart:78-104`) | inbound channel of any kind; nothing instant |
| POS orders on the cloud | `source='pos'`, `channel='pos'` (`PosOrderService.php:178,211`); idempotent on `(restaurant_id, client_transaction_id)` (`2026_09_02_000600_...:33-48`) | link from a POS ticket to the online order it settles |
| POS order model | statuses DRAFT…PARTIALLY_REFUNDED (`order_record.dart:28-55`); types dine_in/takeaway/delivery/drive_thru, pickup read as takeaway (`ticket.dart:14-40`); no origin field (`order_record.dart:246-319`) | origin and cloud order id |
| Contract ledger | POS-BE-001…032 have nothing inbound (`BACKEND_TO_POS.md:195-224`); copies drift on POS-BE-022 | new POS-BE item |
| Production server | Docker on a VPS co-hosting another product (`apps/xorder-cloud/CLAUDE.md`) | a push/websocket service — **UNVERIFIED** what the VPS can host |

## 6. Scope

**In:**
- Pickup and delivery orders from the online menu → POS, instantly (D8).
- Table QR reduced to "request bill" / "call waiter" → POS and waiter handhelds (D7).
- Accept / reject with reason; accepted order → POS ticket (takeaway queue / delivery queue with customer and address); settle syncs up linked to the online order.
- Server pricing from item ids (D2).
- Online ordering open only within the branch's working hours and while a till is online (D5).
- Dashboard read-only for these for POS branches; table QR ordering and the live table board retired for POS branches (D9).

**Out:**
- Ordering from the table by diners (removed for POS branches; waiters order on the waiter app — companion feature).
- Branches without a till: today's flow stays as is (D9).
- WhatsApp-mode restaurants, delivery aggregators, KDS, tips, order-ahead for a later time slot (Q12).

## 7. Behavior and business rules

- **BR-1 POS branches act on the POS (D1).** A branch with at least one paired, active till manages its online orders and table requests only on the POS. The dashboard shows them read-only; the server refuses dashboard status, bill and visit actions for that branch.
- **BR-2 Server prices (D2).** The menu sends item, variant and option ids; the server prices each line from the current menu and stores `price_source = 'server'` (column exists, `2026_09_02_000600_...:54`). Unknown, unavailable or foreign items reject the order (422) before anything is saved.
- **BR-3 Accept first (D4).** An incoming order rings and badges on the till; a person with the new permission accepts (it becomes a ticket and goes to the kitchen) or rejects with a reason the diner sees. Nothing reaches the kitchen before acceptance.
- **BR-4 Ticket and money (D3).** An accepted order is a POS ticket priced from the server's lines. Payment, receipt, invoice number, shift and cash-up follow existing POS rules. The synced POS order carries the online order's id so the cloud links them and counts the sale once.
- **BR-5 Table requests only (D6, D7).** For a POS branch, the table QR opens a page with "request bill" and "call waiter" (and the view-only menu — Q11). It cannot place orders. A request reaches the till and the waiter handhelds; the first to mark it handled closes it; the diner sees its status.
- **BR-6 When online ordering is open (D5).** The menu accepts a pickup or delivery order only if (a) the branch is inside its working hours by `WeeklyHours::isOpenAt` on `business_hours` (and `is_open` is on), (b) the owner has not paused orders, and (c) at least one of the branch's tills is online. Otherwise the menu shows ordering as closed with the reason in plain words (closed now / opens at …; temporarily unavailable), and `POST public/.../orders` refuses with the existing "ordering not available" reply. "Online" means connected to the instant channel; how long a drop is tolerated is Q9.
- **BR-7 Retired table board (D9).** For POS branches the dashboard stops issuing table QR codes for ordering and hides the live table board; existing printed table QR codes open the requests-only page.
- **BR-8 Existing rules kept.** Plan entitlement and `accepts_orders` still apply (`PublicOrderController.php:47-69`); branches without a till keep the current table flow.

## 8. Acceptance criteria

- **AC-1** Given a POS branch inside working hours with a till online, when a diner places a pickup order, then the till shows it as incoming within 2 seconds with server prices, total and note.
- **AC-2** Given a tampered `line_total`, when the order is saved, then each line has the menu price and `price_source = 'server'`.
- **AC-3** Given an item id from another restaurant or an unavailable item, then the API answers 422 and nothing is created.
- **AC-4** Given an incoming order, when a user with the new permission accepts it, then a takeaway (pickup) or delivery ticket exists with the customer and address, the lines go to the kitchen, and the diner sees "accepted".
- **AC-5** Given a user without the permission, then accept and reject are not offered and the device route refuses them.
- **AC-6** Given an incoming order, when it is rejected with a reason, then no ticket is created, the online order is CANCELLED with the reason, and the diner sees it.
- **AC-7** Given an accepted order, when it is settled, then the payment is in the shift, the order syncs up with the online order's id, the online order is COMPLETED, and the cloud sales total counts it once.
- **AC-8** Given a POS branch, when a diner scans a table QR, then the page offers request bill / call waiter and no way to order; a direct `POST public/.../orders` with that table's session is refused.
- **AC-9** Given a table request, then the till and waiter handhelds show it within 2 seconds; when one marks it handled, the others clear it and the diner sees "handled".
- **AC-10** Given the branch is outside working hours, or `is_open` is off, then the menu shows ordering closed with the next opening time, and a direct order POST returns 422.
- **AC-11** Given no till of the branch is online, then the menu shows ordering temporarily unavailable and a direct POST returns 422; when a till reconnects, ordering reopens.
- **AC-12** Given a POS branch, then dashboard write actions on its online orders, requests and visits are refused, and the live table board and table-QR ordering are hidden.
- **AC-13** Given a branch without a till, then today's table ordering, live board and dashboard actions are unchanged (regression).
- **AC-14** Given a reconnect after a drop, then events missed during the drop are delivered once; accepting twice (retry) creates one ticket.
- **AC-15** Given restaurant A's till, then it never receives restaurant B's or another branch's events (cross-tenant → 404).
- **AC-16** All new screens and messages in Arabic and English, RTL correct, digits per the existing setting (needs a person to look).

## 9. Edge cases and failure modes

- **Instant channel down but internet up:** the till must fall back to fetching missed events, and the server must count it offline only per Q9.
- **Till drops mid-order:** orders already placed wait on the cloud and are delivered on reconnect (AC-14); new ordering pauses (BR-6).
- **Two tills or handhelds:** first accept/handled wins under a server lock; others see who took it.
- **Working hours:** overnight windows (closing after midnight) and the branch timezone (`Africa/Cairo` in the test tenant) — `WeeklyHours` has spillover handling (`WeeklyHours.php:86`) to reuse; a closed day with no entry means closed.
- **Order placed one minute before closing:** accepted if the POST arrives inside hours; the cashier can still reject.
- **POS catalog older than the cloud menu:** the server's order price is charged (suggested; Q6).
- **Food truck with weak signal:** ordering pauses and reopens with the connection; the tolerance in Q9 decides how often.
- **Tenant boundary, plan and licence:** scoped by device token → restaurant → branch; lapsed licence behavior is Q7.
- **Abuse of table requests:** a requests-only QR can still be spammed; rate-limit per session (existing public rate limits UNVERIFIED for bill requests).
- **Arabic:** item names `name_ar`/`name_en` as POS lines (`2026_09_27_000100_add_name_ar_en_to_order_items_table.php`).

## 10. Impact

| Area | Change |
|---|---|
| Cloud API | instant channel for POS devices + catch-up feed; accept/reject/handled device routes; working-hours and till-online checks on order create; dashboard guards for POS branches; server pricing |
| Infrastructure | a push/websocket service on the production VPS (new service; **installing tools needs approval**) |
| Diner menu (`apps/menu`) | send item/variant/option ids; closed/unavailable states; requests-only table page; accepted/rejected status |
| Dashboard (`apps/web`) | read-only mode and hidden live board / table-QR ordering for POS branches |
| POS | instant connection while a shift is open, incoming list with sound, accept/reject, ticket from online order, table requests on the floor and handhelds, new permission |
| Contract | new `POS-BE-033+` (both copies of `POS_TO_BACKEND.md`), READY in `BACKEND_TO_POS.md` before POS integrates |
| Data | additive: accept/reject state and reason, online-order id on POS orders (cloud and POS local), request type on bill requests (if Q3), permission seed |
| Order state | new accepted/rejected transitions — **owner approval** |
| Permissions | dashboard narrowed for POS branches — **approval**; new POS permission |
| Deploy order | cloud channel and routes first (inactive), POS release reading them, then switch each branch to POS mode only when its till runs that version (Q8) |
| Docs | inventory rows `diner-orders`, `bill-requests`, `tables`, `qr-codes` become shared |

## 11. Dependencies, known gaps, risks

- **Companion:** `waiter-app` must ship before table ordering is retired for a branch, or that branch loses table ordering entirely.
- **Kitchen printing** on the POS (state `?`, domain handbook section 3).
- **Adjacent work:** `guest-paging` (proposed, uncommitted edits in the same controller).
- **Risks:** a new always-on service on a co-hosted production box; the till as the single gate for online ordering (BR-6); 3 cloud vs 10 POS order statuses to map; aggregators and KDS still absent for cloud kitchens.

## 12. How it will be tested

| AC | Test |
|---|---|
| AC-2, AC-3, AC-8, AC-10, AC-11 | cloud feature tests on order create (tampered price, foreign item, table session, outside hours incl. overnight, no till online) |
| AC-1, AC-9, AC-14, AC-15 | cloud tests on the channel/catch-up feed (cursor, once-only, cross-tenant 404) + POS unit tests of the inbound loop with a fake server; latency checked by a person on a staging stack |
| AC-4–AC-7 | cloud feature tests for accept/reject/settle (idempotent retry, two-till race) + POS integration test extending `integration_test/sale_to_settle_test.dart` |
| AC-12, AC-13 | cloud feature tests on dashboard routes with and without a paired till |
| AC-16, end-to-end | a person runs pickup, delivery and table-request flows on a staging stack with a real till and a handheld, Arabic and English |

SQLite cannot prove PostgreSQL locking for the two-till race; review by reading.

## 13. Decisions and open questions

**Decided (owner, 2026-11-06):**
- **D1** POS branches manage online orders and requests **on the POS only**; the dashboard is read-only for them.
- **D2** **Server re-prices from the menu**; the menu sends item ids.
- **D3** An accepted online order **becomes a POS ticket**.
- **D4** **The cashier accepts or rejects**, under a **new permission**.
- **D5** Online ordering **pauses and tells the diner** when no till is online, and **respects working hours**.
- **D6** Table ordering **moves to the waiter app** (the POS on a handheld) — separate feature `waiter-app`.
- **D7** Tables keep a **small QR for request bill / call waiter only**.
- **D8** Online orders reach the till **instantly (1–2 s)**.
- **D9** Table QR ordering and the live board are **retired for POS branches**; branches without a till keep today's flow.
- **D10** Split into two features: this one and `waiter-app`.
- Superseded the same day: the first draft's dine-in table orders on the POS, rounds from diners and the table-visit close from the POS.

**Open:**
- **Q2** Several tills in a branch: do all see every online order (first accepts wins), or one chosen till?
- **Q3** Make "call waiter" its own request type, separate from the bill? (Suggestion.)
- **Q6** If the till's catalog is older than the cloud menu, charge the server's order price? (Suggested.)
- **Q7** With a lapsed subscription or licence, do online orders still reach an open shift?
- **Q8** How the cloud knows a till runs a version that can receive orders before a branch switches to POS mode.
- **Q9** How long may the till's connection drop before ordering pauses (for example 30 s or 2 min)?
- **Q11** Does the requests-only table page also show the menu (view only)?
- **Q12** Order-ahead for a later time (pickup at 8 pm) — wanted, or only "now"?

Next: `/implement pos-incoming-cloud-orders` after `waiter-app` is described — needs approval for: a new push service on production, additive migrations (cloud and POS), a new POS-BE contract item and rollout order, new order-state transitions, narrowing dashboard access for POS branches, the menu payload change, the new POS permission, anything reaching `xorder-cloud` `main`.
