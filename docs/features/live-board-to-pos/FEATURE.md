# Live ordering moves to the POS; the dashboard keeps delivery and WhatsApp — live-board-to-pos

Status: implemented in the xorder-cloud working tree 2026-11-10 (uncommitted; AC-2, AC-3, AC-4 open; see TECHNICAL.md section 7) · 2026-11-10 · Source: the owner, "All ordering process should be inside the desktop pos app", then "for live orders it will be in pos not on dashboard — only will have delivery orders or whats app orders through dashboard, no need to have the live tables on dashboard" · Verified against: xorder-cloud `1ae5fd8` (main, clean), xorder-pos `c058837` (development, clean) · Revises decision D9 of `docs/features/pos-incoming-cloud-orders/FEATURE.md`; companion `docs/features/waiter-app/FEATURE.md`

## 1. Summary

Everything that is "live" in a restaurant's day — tables, dine-in orders, bill requests, the order queue a person watches and acts on — is handled in the desktop POS (and the waiter handheld). The web dashboard stops being an operations screen: its Live board (`/admin/live`) goes away, and it keeps only the **delivery orders** and the **WhatsApp orders** the owner reviews there, plus the usual back-office pages (reports, customers, menu, settings).

## 2. Why

- Staff today watch two screens: the POS and the dashboard Live board, which also lets a dashboard user act on orders, tables and bills (`LiveBoardView.vue:81,197,221`). The owner wants one place for ordering: the POS.
- Venue models: **restaurant** (tables, rounds) is helped most; **café** (counter, pickup) and **cloud kitchen** (delivery only, no front of house) are helped only if their orders reach a POS or stay reachable in the dashboard; **food truck** has no tables and unreliable signal (domain handbook sections 2 and 3).

## 3. Goal and success

- A restaurant that runs the POS never needs the dashboard to take, serve or close an order.
- The dashboard has no live tables board and no table or bill actions.
- Delivery and WhatsApp orders remain reachable on the dashboard (delivery in both places, D3; WhatsApp orders are pending until an employee confirms, D6).
- No order that arrives today is left with nowhere to be seen after the change.

## 4. Users, roles and permissions

| Actor | Can | Permission |
|---|---|---|
| Cashier, waiter | run tables, orders and requests in the POS / handheld | POS permissions (`lib/domain/models/permissions.dart`), new online-order permission from `pos-incoming-cloud-orders` |
| Owner / manager | review delivery and WhatsApp orders on the dashboard | `orders.read`, `orders.update` (`routes/api.php:459-469`) |
| Dashboard user with `live.view` | **loses** the Live board | `live.view` (`TenantCapability.php:37`); what happens to the grant and to roles that hold it is Q6 |

## 5. Today

| Area | Exists (evidence) | Missing / UNVERIFIED |
|---|---|---|
| Live board | page `apps/web/src/pages/dashboard/LiveBoardView.vue` (566 lines), route `dashboard.live` guarded by `live.view` (`router/index.js:123`), sidebar entry with a badge (`nav.config.js:38`), bell notifications link to it (`NotificationBell.vue:19`, `DashboardLayout.vue:132`) | |
| Its three columns | bill requests `GET dashboard/bill-requests` + status patch; table floor `GET dashboard/tables/live`; new orders `GET dashboard/orders?status=NEW` + status patch; finish a table visit `POST dashboard/tables/{id}/visit/finish` (`LiveBoardView.vue:72-221`) | |
| API gates | `orders.read` = `orders.view` OR `live.view` (`routes/api.php:459`, `AppServiceProvider.php:152`); `tables/live` behind `tables.live` and feature `table_management` (`api.php:493`); `bills.read` (`api.php:544`) | |
| Ordering mode | `OrderingMode` is `whatsapp` or `system`, mutually exclusive; **WhatsApp mode creates no order record**, checkout opens a pre-filled message (`app/Enums/OrderingMode.php`) | where a "WhatsApp order" could be reviewed on the dashboard: **UNVERIFIED** — a customer is captured for WhatsApp checkout (`api.php:440-442`), nothing else found |
| Dashboard order list | `orders` index/show/status/export for plans with `system_ordering` or `pos` (`api.php:456-469`); POS sales appear as `channel=pos` rows | |
| Features | `qr_menu`, `whatsapp_ordering`, `pickup`, `delivery`, `table_management`, `bill_requests`, `guest_paging` in `app/Enums/Feature.php` | which plans carry `system_ordering` without `pos`: **UNVERIFIED** |
| POS receives online orders | proposed, **not built**: `docs/features/pos-incoming-cloud-orders` (no inbound channel exists; POS only pulls `pos/bootstrap` and pushes sales) | contract POS-BE-0xx not READY |
| Table ordering by waiters | `waiter-app` WA1 built 2026-11-09, cloud wire built but not READY (POS-BE-033) | tables on the handheld complete? **UNVERIFIED** |

## 6. Scope

**In (the owner's words):**
- The live tables view leaves the dashboard.
- Live order handling happens in the POS.
- The dashboard keeps delivery orders and WhatsApp orders.

**Out until decided:** the wording of the WhatsApp message and its timing (Q7); aggregators, KDS, tips (known gaps).

## 7. Behavior and business rules

- **BR-1** Table state, dine-in orders, bill requests and "call waiter" are acted on only in the POS / handheld. The server refuses these actions from the dashboard once the board is retired (additive; the POS contract carries them).
- **BR-2** Delivery orders can be handled in the POS and on the dashboard (D3); the first status change wins and the other place updates.
- **BR-3** A WhatsApp order is saved as pending and becomes real only when an employee confirms it (D4, D6); a pending order is never sent to the kitchen or counted as a sale.
- **BR-4** The Live board is removed for every restaurant (D5). Because restaurants without a POS then have no live view, removal should wait until the dashboard order list and (for POS restaurants) the POS can replace it (Q4).
- **BR-5** Existing rules are kept: plan entitlement, `accepts_orders`, tenant isolation, subscription-lapse behavior for orders already received (`api.php:447-456`).

## 8. Acceptance criteria

- **AC-1** Given the change is live for a restaurant, when a dashboard user opens the app, then there is no Live entry in the sidebar, `/admin/live` redirects to a sensible page, and the notification bell no longer links to the board (frontend; person looks).
- **AC-2** Given a restaurant with the board retired, when a dashboard client calls the table-visit, bill-request status or table-floor endpoints, then it is refused and the POS routes still work (cloud feature tests, per tenant).
- **AC-3** Given a delivery order, when the owner opens the dashboard, then it appears in the delivery list (handled in both places, D3; two simultaneous status changes: the first wins).
- **AC-4** Given a table order or bill request, when it happens, then it is visible and actionable in the POS / waiter handheld (depends on `pos-incoming-cloud-orders` and `waiter-app`).
- **AC-5** Given a restaurant without a POS, when the board is removed, then it can still list, open and change the status of its orders from the dashboard order list (regression).
- **AC-6** Given WhatsApp ordering, when a diner checks out, then a pending order exists, is listed for employees, and only becomes a normal order after an employee confirms it; an unconfirmed one never reaches the kitchen or the sales totals (cloud feature tests).
- **AC-7** Arabic and English, RTL, nothing left with an orphaned translation key or nav badge (person looks).

## 9. Edge cases and failure modes

- A restaurant without a POS or with its till offline during service: where does it see incoming orders (D5 leaves only the dashboard order list; see `pos-incoming-cloud-orders` BR-6)?
- A manager who relied on watching the floor from a phone via the dashboard loses that view; the waiter app and POS replace it only if they show the same signals.
- Bookmarked `/admin/live` links and push notifications (`bill_request.created`) must not dead-end.
- Roles holding only `live.view` (Q6): they must not be left with an empty dashboard.
- Tenant boundary: the POS side sees only its restaurant and branch (existing device token rules).

## 10. Impact

| Area | Change |
|---|---|
| Dashboard (`apps/web`) | remove or redirect Live board, its nav entry and badge, bell link; keep delivery order list |
| Cloud API | refuse dashboard table / bill / visit actions for retired restaurants; no schema change expected (**UNVERIFIED** until the plan) |
| POS | must already handle tables, bill requests, online orders (other features) |
| Permissions | `live.view` retired or remapped — narrows access, **needs owner approval** |
| Contract | none new here; depends on the POS-BE items of `pos-incoming-cloud-orders` |
| Deploy order | POS and waiter-app capabilities READY and in use first; then dashboard retirement per restaurant; cloud and POS deploy independently |
| Docs | update `pos-incoming-cloud-orders` D9, inventory row `dashboard-orders`, `back-office-navigation` |

## 11. Dependencies, known gaps, risks

- Hard dependencies: `pos-incoming-cloud-orders` (not built) and `waiter-app` (partly built). **Removing the board before they ship would leave live restaurants with no order screen.**
- No restaurant runs the POS yet (owner, 2026-11-06); POS ships only inside Restaurant and Business plans (no POS-only plan, 2026-11-04). Lower plans have no POS to move to.
- Known gaps: KDS, aggregators, tips (domain handbook section 3).
- A restaurant's WhatsApp orders leave no record, so D6 (a pending record) is a new behavior, not a move of something that exists.

## 12. How it will be tested

| AC | Test |
|---|---|
| AC-2, AC-5 | cloud feature tests: retired vs not retired restaurant, cross-tenant refusal |
| AC-3 | cloud feature test on the dashboard order list for delivery orders |
| AC-1, AC-7 | person checks nav, redirect, bell, Arabic/RTL (no Vue test framework exists) |
| AC-6 | cloud feature tests: pending state, confirm, kitchen/sales exclusion, tenant boundary |
| AC-4 | covered by the tests of the two dependency features |

## 13. Decisions and open questions

**Decided (owner, 2026-11-10):**
- **D1** Live order handling and the live tables view are in the POS, not on the dashboard.
- **D2** The dashboard keeps delivery orders and WhatsApp orders only; no live tables board.
- This revises D9 of `pos-incoming-cloud-orders`, which kept the board for restaurants without a till.

- **D3** (2026-11-10) Delivery orders are handled **in both** the POS and the dashboard. This revises D1 of `pos-incoming-cloud-orders` (dashboard read-only for POS branches): the dashboard stays able to act on delivery orders. Both places must agree: the first accept or status change wins under a server lock, the other sees it.
- **D4** (2026-11-10) WhatsApp orders **need confirmation by an employee**. Recorded as the owner's words; my reading is that each WhatsApp order becomes a record an employee confirms (Q2).
- **D5** (2026-11-10) The Live board is **removed for everyone**, including restaurants without a POS. They are left with the dashboard order list. This replaces the "keep it for them" suggestion and makes BR-4 a hard dependency risk (section 11).

- **D6** (2026-11-10, answers Q2) A WhatsApp order is **saved as pending** and stays pending **until an employee confirms it**. This means WhatsApp mode creates an order record, which changes the documented rule in `OrderingMode` (WhatsApp creates no record) and its plan gate (`api.php:450-451`): **needs owner approval before building**. Open detail: Q7 (what the diner receives, and when).

- **D7** (2026-11-10, answers Q4) The Live board is **removed from the dashboard in general**: no per-restaurant switch, no waiting for each restaurant's replacement. My reading: one release removes it for everyone. This accepts the risk in section 11 (a restaurant whose POS cannot yet handle tables and bill requests has no screen for them); the order list is the only dashboard fallback.
- **D8** (2026-11-10, answers Q5) A new delivery order **rings and badges in both** the POS and the dashboard. The first accept or status change still wins under a server lock (D3).
- **D9** (2026-11-10, answers Q6) The `live.view` permission is **removed now**, not kept. Roles that held it are changed by a data migration. Consequence: `orders.read` and `bills.read` accept `live.view` today (`AppServiceProvider.php:152`), so a role holding only `live.view` would lose the order list unless it is mapped to `orders.view` and `bills.view` in the same migration (my proposal, not yet confirmed, see Q6a). **Narrows access: needs explicit approval.**
- **D10** (2026-11-10, answers part of Q7) The diner's WhatsApp message goes out **only after an employee confirms** the pending order, not at checkout. Until then the diner sees nothing from the restaurant; the checkout screen must say the order is waiting for confirmation (wording not decided).

- **D11** (2026-11-10, answers Q6a) Roles that held only `live.view` are **not** mapped to anything: they lose it and, with it, the order list and bill reads that `live.view` granted (`AppServiceProvider.php:152`). Consequence to accept: such a role may be left with an empty dashboard, which section 9 says must not happen; an owner who wants one of those roles to keep seeing orders must grant `orders.view` by hand. The migration should list the affected roles per restaurant before it runs.

- **D12** (2026-11-10, answers Q7a) A pending WhatsApp order **never expires**. It stays pending until an employee confirms it or cancels it by hand. Consequences to plan for: with D10 the diner hears nothing until confirmation, so an ignored order is silent forever; pending orders can pile up, so the dashboard needs a visible pending count and an employee must be able to cancel one (cancel is my addition, not yet confirmed); pending orders must stay out of kitchen and sales totals indefinitely (BR-3).

- **D13** (2026-11-10, answers Q7b and the "WhatsApp only in WhatsApp" alternative) WhatsApp orders **stay on the dashboard** as pending orders, each with an **Accept** button. I had recommended keeping them only in WhatsApp; the owner chose to keep D6. Confirmation is in the **dashboard** (POS not asked for, so out of scope). Accepting is what sends the diner's message (D10). A reject/cancel button is my addition, not confirmed (Q7c). D6, D10 and D12 therefore stand, with the rule change and migration approvals they need.

- **D14** (2026-11-10, answers Q7c, read from "for whats app") A pending WhatsApp order has an **Accept** and a **Reject** button on the dashboard. Reject applies to WhatsApp orders only. My reading of the owner's two words; confirm if Reject was meant differently.

- **D15** (2026-11-10, answers Q7d) After Accept or Reject, the employee taps a button that opens WhatsApp with a pre-filled message to the diner (a `wa.me` link built from the diner's phone). No WhatsApp Business API, no new provider. Limits accepted: the platform cannot know whether the message was actually sent, and the diner hears nothing until an employee taps. Unchanged from D12: an ignored pending order stays silent.

**Answered (kept for history):**
- **Q7d** How does the diner's message after Accept (D10) and after Reject (D14) actually get sent? Today checkout opens a pre-filled `wa.me` message **from the diner to the restaurant**; no code that sends a WhatsApp message to a diner was found (**UNVERIFIED**: search for a WhatsApp Business API integration before the plan). Options: the employee taps a button that opens a pre-filled WhatsApp message to the diner (no new service), or the platform sends it through a WhatsApp Business API (new provider, cost and approval needed).

Next: answer Q6a, Q7a and Q7b (Q4–Q7 otherwise answered as D7–D10), then `/implement live-board-to-pos` (after `pos-incoming-cloud-orders` is built). It will need approved: narrowing dashboard access (`live.view`, refusing dashboard table/bill actions), anything reaching `xorder-cloud` `main`, and the WhatsApp change of D6 (an order record and a pending state in a mode that has none today, an additive migration).
