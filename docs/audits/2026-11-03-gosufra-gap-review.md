# GoSufra vs Xorder — feature gap review and plan

**Date:** 2026-11-03 · **Source:** 23 screenshots of the GoSufra restaurant dashboard
(`app.gosufra.com`, Starter plan, Arabic UI) supplied by the owner · **Compared against:**
this repo at `7611b0e` (branch `claude/loving-hawking-wdbcet`).

Two iPhone-simulator screenshots in the same archive (an unrelated app, TRANSFLO) were ignored.

Legend: ✅ done in Xorder · 🟡 partial, needs enhancement · ❌ missing · ⭐ Xorder is ahead

---

## 1. Scorecard

| # | Area (as seen in GoSufra) | Xorder | Verdict |
|---|---|---|---|
| 1 | Shell: grouped sidebar, bell, logout, AR/EN toggle | `nav.config.js`, `SakaiLayout`, `NotificationBell` | ✅ |
| 2 | Shell: plan badge, "upgrade" banner, help button, page search, branch selector | Only an *expired* banner with WhatsApp CTA | 🟡 |
| 3 | 13-step onboarding tour | 3-step "setup guide" card on Home | 🟡 |
| 4 | Home: revenue today, orders today, vs yesterday | `StatsController` (sales/orders today, change %) | ✅ |
| 5 | Home: "pulse" (waiting now / preparing now), order-type distribution, completion & cancel rate | Only NEW/COMPLETED/CANCELLED exist, no mid-states, no type chart on Home | 🟡 |
| 6 | Orders: status tabs with counts, search by customer/phone/order no. | `OrdersView` + `OrderController` summary | ✅ |
| 7 | Orders: 6-state lifecycle (pending → in progress → ready → served → completed / cancelled) | `OrderStatus` has 3 states | ❌ |
| 8 | Orders: date-range filter, CSV export, payment / team / timing columns | None of these | ❌ |
| 9 | Tables: map with seats, search, filters | `TablesView`, dining areas, per-table QR, live occupancy via `TableVisit` | ✅ ⭐ |
| 10 | Tables: available / occupied / reserved status filter | Filter is active/inactive; occupancy only on Live board; no "reserved" | 🟡 |
| 11 | Menu: products / categories / add-ons tabs | Items, Categories, Extras (option groups), Combos, variants, CSV import/export, bulk delete | ✅ ⭐ |
| 12 | Menu: SKU, unit, cost, modifier count per product; "out of stock" vs "available" | Items have none of these; SKU/unit live on `StockItem`; no cost/recipe | 🟡 |
| 13 | Restaurant can pick brand colour, accent colour, theme | `brand_color`, `secondary_color`, `menu_layout` exist but are only editable by the **Super Admin** (`admin/RestaurantForm.vue`) | 🟡 |
| 14 | Website: per-restaurant subdomain, copy link, open | `slug.<menu_domain>/menu/` via `Restaurant::publicUrl()`; QR + link on Home | ✅ |
| 15 | Website: gallery of 8+ visual themes | 3 layouts (photo / text-grid / text-list) | 🟡 |
| 16 | General: 10 UI languages | ar / en only (`LanguageEnum`) | 🟡 (by design for now) |
| 17 | General: currency, tax %, service fee %, prices-include-tax toggle | Currency ✅ (11). Tax rules + charges exist **for POS only** (`TaxRule`, `Charge`); online orders carry no tax/service; no inclusive toggle | 🟡 |
| 18 | General: loyalty (points per EGP, referral points, packaging-return points) | Nothing | ❌ |
| 19 | General: scheduled & recurring orders (max days ahead, min lead minutes, slot interval) | Nothing | ❌ |
| 20 | General: delivery fee model (free / fixed / per km / fixed + per km) | Nothing; `delivery_time_min/max` + `minimum_order` only | ❌ |
| 21 | Notifications: durable centre + push | `Notification` table, `NotificationService`, FCM web push, bell with unread count | ✅ |
| 22 | Notifications: per-event toggles (order created / status / cancelled / payment; low stock / adjustment; shift open-close; cash drawer; new staff) and channel selection | No preferences at all. Events that fire today: `order.created`, `bill_request.created`, `review.created` | ❌ |
| 23 | Branches: list with delivery radius, working hours, language, currency, plan limit, map pin | Branch has hours, map URL, lat/lng, geofence (table-presence), Wi-Fi gate, order types; `max_branches` enforced. No delivery radius, no per-branch language/currency | 🟡 ⭐ |
| 24 | Purchasing: suppliers, raw materials (name, unit, cost/unit) | Suppliers, stock items, units, POs, **supplier invoices, supplier payments, drawer payouts, stock ledger, adjustments** | ✅ ⭐ |
| 25 | Purchasing: goods-received note vs PO (ordered vs received, partial) | `ReceivingService` (partial receipts, short close) | ✅ |
| 26 | Inventory: low-stock alert, cost per unit on the material | No threshold / alert; cost is derived from PO lines, not editable on the item | 🟡 |
| 27 | Customers: list, count, join date | `CustomersView` (orders & addresses count), detail view | ✅ |
| 28 | Customers: loyalty points, referral codes, offers, recurring orders (gated to higher plan) | Nothing | ❌ |
| 29 | Staff (HR) | Staff + per-restaurant roles with granular capabilities + POS PIN | ✅ ⭐ |
| 30 | Settings: Firebase config per restaurant, white-label app builds (customer / kitchen / waiter / driver / POS exe) | Platform-level FCM for dashboard push; POS is a separate Flutter till. No kitchen / waiter / driver / customer apps | ❌ (strategic) |
| 31 | Settings: support-team access log (vendor impersonation audit) | No impersonation feature | ❌ |
| 32 | Settings: data transfer (import / export all data) | Menu CSV import/export, report export only | 🟡 |
| 33 | Settings: Privacy / GDPR page, data-deletion requests | Nothing | ❌ |
| 34 | Settings: tenant-facing activity log | `AuditLog` rows carry `restaurant_id` but only the Super Admin can view them (`admin/AuditLogsView.vue`); CB-13 in `BACKOFFICE_TO_CLOUD.md` is still PROPOSED | 🟡 |
| 35 | AI assistant page | Nothing | ❌ |
| 36 | Subscription plans page inside the restaurant dashboard, self-serve upgrade | Plans exist (admin side), public signup with trial, no in-dashboard plan page | 🟡 |

Where Xorder is clearly **ahead** of what the screenshots show: Live board, bill requests, internal
reviews, product/area analytics reports, dining areas + per-table QR with presence checks, supplier
invoices/payments ledger, role capabilities, POS licensing fleet, combos and variants, menu import.

---

## 2. Detail per area

### 2.1 Shell and onboarding (rows 1–3)
- **Done:** sidebar groups driven by plan features + capabilities, bell + pulse polling, AR/EN toggle,
  expired-subscription banner.
- **Enhance:**
  - Plan badge in the top bar (plan name + trial days left) and a persistent "upgrade" banner for
    TRIAL / free tiers, not only EXPIRED. Data is already on `auth.restaurant.subscription_*`.
  - Help entry (link to a help page / WhatsApp) next to the bell.
  - Page search ("ابحث في الصفحات") over the resolved nav tree. Pure front-end, `nav.config.js`
    already has i18n labels and routes.
  - Guided tour: extend the Home setup guide into a dismissible step-by-step tour (driver.js or
    similar) that remembers completion per user (`localStorage` is fine, as the guide does today).
  - Branch selector: only meaningful once orders/tables are filterable by branch. See 2.3.

### 2.2 Home dashboard (rows 4–5)
- **Done:** sales today, orders today, change vs yesterday, views, featured items, current shift,
  quick actions.
- **Enhance:** add "waiting now / preparing now" tiles and completion / cancel rate — these need the
  richer order lifecycle (2.3). Add an order-type donut (dine-in / pickup / delivery / POS) to Home;
  `InsightsController` already aggregates orders, only the group-by is missing.

### 2.3 Orders (rows 6–8)
- **Done:** tabs with live counts, search (name / phone / ORD-id), order-type filter, table filter,
  receipt dialog, POS provenance tag, incremental polling.
- **Missing, highest business impact:**
  1. **Order lifecycle.** `OrderStatus` is NEW → COMPLETED / CANCELLED. GoSufra has pending →
     in progress → ready → served → completed / cancelled. Add `ACCEPTED`, `PREPARING`, `READY`,
     `SERVED` (served only for dine-in). Touch points: enum + `canTransitionTo`, `OrderController`
     summary counts, `OrdersView` tabs and advance buttons, Live board, public order status endpoint
     (`/public/restaurants/{slug}/orders/{id}/status`) and the menu app's success modal, POS bundle
     contract (`BACKEND_TO_POS.md`), notification "order.status_changed".
  2. **Date range** (`from` / `to`, restaurant-local day) on `OrderController@index` + a picker in
     the toolbar.
  3. **CSV export** of the filtered list, same pattern as `MenuExportController` / `ReportController@export`.
  4. Extra columns: payment state (from `OrderPayment` when POS, "unpaid" otherwise), branch, handled
     by (acting staff), timing (created → completed duration).
  5. **Branch filter** (`branch_id`) on orders, tables and stats, surfaced as the top-bar branch
     selector for multi-branch tenants.

### 2.4 Tables (rows 9–10)
- **Done:** areas, tables, seats, bulk create, per-table QR + bulk ZIP, occupancy via `TableVisit`.
- **Enhance:** show occupancy on the Tables page itself (the API already returns `occupied` in
  `TableController@index`) with an available / occupied filter, and add a simple `RESERVED` flag or a
  reservations table if the owner wants booking.

### 2.5 Menu (rows 11–13, 15)
- **Done:** items, categories (with availability hours), option groups (global/variant), combos,
  import/export, bulk actions, grid/list views.
- **Enhance:**
  - Columns on the Items list: modifier-group count, linked stock item SKU/unit, and a "cost" column
    once recipes exist. Keep `MenuItem` clean; read SKU/unit through `StockItem.menu_item_id`.
  - Distinguish **out of stock** (temporary, auto-resets or expires) from **unavailable** (hidden).
  - Move brand colour, accent colour and `menu_layout` into the restaurant's own Profile page
    (`ProfileView.vue` + `UpdateRestaurantProfileRequest`), gated by `settings.update`. Today the
    restaurant cannot change its own look.
  - Theme gallery: `MenuLayout` has 3 values. Add 4–6 named themes (palette + typography + card
    style) as presets over the existing `brand_color` / `secondary_color` CSS variables in
    `apps/menu/src/app.css`, previewed as cards like GoSufra.

### 2.6 General settings (rows 16–20)
- **Done:** currency, timezone, bilingual flag, accepts-orders switch, delivery time, minimum order.
- **Missing:**
  - **Tax & service fee for online orders.** Reuse `TaxRule` / `Charge` (currently POS-only) in
    `PublicOrderController` and the menu cart; add a `prices_include_tax` flag on `restaurants`.
  - **Delivery fee** model: `delivery_fee_mode` (free / fixed / per_km / fixed_plus_km),
    `delivery_fee_fixed`, `delivery_fee_per_km`, `delivery_radius_km` on `branches`. Distance from
    branch lat/lng to the customer address (addresses already store coordinates via `MapLinkResolver`).
  - **Scheduled / recurring orders:** `scheduled_for` on `orders`, settings (max days ahead, min lead
    minutes, slot interval), slot picker in the cart, and a "scheduled" tab in Orders. Recurring is a
    later layer on top (template + cron).
  - **Loyalty:** `loyalty_settings` (points per currency unit, referral bonus, packaging-return
    bonus), `customer_points_ledger`, redemption at checkout. Needs `customer_tracking` feature.
  - More UI languages only if a market needs it; the i18n layer (`packages/ui/src/i18n`) already
    supports adding locales, but every string is authored twice today.

### 2.7 Notifications (rows 21–22)
- **Done:** durable centre, unread count, FCM web push, loud new-order alarm.
- **Missing:** `notification_preferences` (per restaurant, per event, per channel) checked inside
  `NotificationService::toRestaurant`. New events to raise: `order.status_changed`, `order.cancelled`,
  `payment.received` (POS), `stock.low`, `stock.adjusted`, `shift.opened` / `shift.closed`,
  `cash.movement`, `staff.created`. Shift and cash services already exist (`PosShiftService`), so
  those are one-line hooks.

### 2.8 Branches (row 23)
- **Done:** hours, map, geofence, Wi-Fi presence gate, order types, open/closed, plan limit.
- **Enhance:** delivery radius (see 2.6), per-branch phone already there; per-branch language /
  currency are not needed unless a tenant spans countries. Add the plan-limit notice inline on the
  Branches page like GoSufra ("you reached the limit (1), upgrade").

### 2.9 Purchasing & inventory (rows 24–26)
- **Done and ahead:** suppliers, units, stock items, POs with send/cancel/receive/short-close,
  supplier invoices + payments + allocations, drawer payouts, stock ledger, adjustments.
- **Enhance:** `reorder_level` on `stock_items` + a low-stock notification and a badge on the Stock
  page; an editable "standard cost" on the stock item for tenants that do not run POs; and, later,
  recipes (BOM) so a product's cost and margin can be shown on the Items list.

### 2.10 Customers (rows 27–28)
- **Done:** list, search, detail with orders and addresses.
- **Missing:** loyalty points balance and history, referral code per customer, offers. All depend on
  the loyalty work in 2.6; the "recurring orders" column depends on scheduled orders.

### 2.11 Settings: data, privacy, activity (rows 31–34)
- **Enhance:** tenant-facing Activity log — expose `AuditLog` filtered by `restaurant_id` under
  `can:settings.view` (this is CB-13 in `BACKOFFICE_TO_CLOUD.md`, still awaiting an owner go).
- **Missing:** full data export (orders, customers, menu as a ZIP of CSVs), a Privacy page, and a
  data-deletion request flow (customer asks → owner approves → anonymise `customers` row and
  `orders.customer_*`). Support-access log only matters if the platform adds "log in as
  restaurant" for the support role; if that is added, audit it from day one.

### 2.12 Strategic items (rows 30, 35, 36)
- **White-label mobile apps** (customer / kitchen / waiter / driver) are a product decision, not a
  gap to patch. A browser-based KDS and waiter view can be delivered far cheaper as routes of the
  existing dashboard (the Live board is already most of a waiter screen).
- **AI assistant:** out of scope until the data it would answer over (sales by hour, stock, costs) is
  complete.
- **Self-serve plan page:** show the current plan, limits used (items / categories / branches / staff /
  terminals from `PlanLimitService`), and an upgrade CTA. Billing itself stays manual (WhatsApp) until
  a payment gateway is chosen.

---

## 3. Plan

Priority is by owner value for an Egyptian QR-ordering restaurant on a Starter-like plan, then by
how much other work unblocks. Sizes: S ≤ 1 day, M 2–4 days, L 1–2 weeks.

### Phase A — close the visible gaps (P0)
| ID | Item | Size | Depends on |
|---|---|---|---|
| A1 | Order lifecycle. **Split 2026-11-03:** optional cancellation reason (with who/when) **done**. Kitchen steps → `docs/FUTURE_PLAN.md` F1; Served step → F2 (waiter app); diner tracking → F3 | M | — |
| A2 | Orders: date range + CSV export + payment / branch / handled-by / duration details — **done 2026-11-03** (completion is now stamped with who/when, so duration did not need A1) | M | — |
| A3 | Home: waiting-now / preparing-now tiles, completion & cancel rate, order-type donut | S | A1 |
| A4 | Restaurant edits its own brand colour and menu layout from Profile — **done 2026-11-03** (second colour left admin-only: the public menu doesn't use it yet) | S | — |
| A5 | Plan badge + trial/upgrade banner + in-dashboard "My plan" page with limit meters — **My plan page done 2026-11-10**; badge and trial banner still open | S–M | — |
| A6 | Notification preferences (per event, per channel) + the new events listed in 2.7 | M | A1 for status events |
| A7 | Tables page: occupancy badge + available / occupied filter — **done 2026-11-03** (same rules as the live board; reserved state not built) | S | — |
| A8 | Sidebar regrouping: section headings (Main, Menu, Inventory & purchasing, Customers & marketing, Reports, Team, Settings), page search, tabbed Purchasing and Stock screens, Staff/Roles to Team, Branches/Dining areas into Settings, old URLs redirected — **done 2026-11-03** | S | — |

### Phase B — money and fulfilment (P1)
| ID | Item | Size | Depends on |
|---|---|---|---|
| B1 | Tax % and service fee on online orders, prices-include-tax flag, shown in cart and receipt | M | — |
| B2 | Delivery fee model + delivery radius on branch, computed at checkout | M | B1 (same cart totals work) |
| B3 | Branch filter on orders / tables / stats + top-bar branch selector | M | — |
| B4 | Low-stock threshold + alert + badge; standard cost on stock item | S | A6 |
| B5 | Tenant Activity log page (CB-13) | S | owner go |
| B6 | Page search + help entry + guided tour | S–M | — |

### Phase C — growth features (P2)
| ID | Item | Size | Depends on |
|---|---|---|---|
| C1 | Scheduled orders (settings, slot picker, scheduled tab, reminders) | L | A1, A6 |
| C2 | Loyalty: points ledger, earn on completed orders, redeem at checkout, referral codes | L | `customer_tracking` |
| C3 | Theme gallery (4–6 presets) for the public menu | M | A4 |
| C4 | Data export ZIP, Privacy page, deletion-request flow | M | — |
| C5 | Recipes / BOM → product cost and margin on Items | L | B4 |
| C6 | Browser KDS + waiter routes in the dashboard (instead of native apps) | L | A1 |

### Not planned (decide separately)
White-label native apps and per-restaurant Firebase projects; AI assistant; 10-language UI;
vendor impersonation and its access log.

---

## 4. Implementation notes for Phase A (so the next session can start cold)

- **A1** — `app/Enums/OrderStatus.php` (cases + `canTransitionTo`), `Dashboard/OrderController`
  (`summary()` counts, `updateStatus` validation), `web/pages/dashboard/OrdersView.vue` (`STATUSES`,
  `nextActions`, `badgeClass`), `LiveBoardView.vue`, `Public/PublicOrderController@status`,
  `apps/menu` `OrderSuccessModal.vue`, lang files `lang/{ar,en}/xorder.php` and
  `packages/ui/src/i18n`. Migration: none needed for a string enum column, but add a normalisation
  migration if any rows carry legacy values (see `normalize_confirmed_order_status.php`). Record the
  new states in `docs/coordination/BACKEND_TO_POS.md` since the till reads order status.
- **A2** — add `from` / `to` to `OrderController@index` validation, convert with
  `$restaurant->localTimezone()` as `StatsController::salesFor` does; export via a streamed CSV
  controller under `can:orders.view`.
- **A4** — add `brand_color`, `secondary_color`, `menu_layout` to
  `Http/Requests/Dashboard/UpdateRestaurantProfileRequest` and `ProfileView.vue`; `BrandImageService`
  already handles logo/cover. Bump `PosConfigVersion` only if the till renders colours (it does not
  today).
- **A5** — `auth.restaurant` already carries `subscription_plan`, `subscription_status`,
  `subscription_end_date`; limits come from `PlanLimitService` — expose a small
  `GET /api/dashboard/plan` returning plan + usage.
- **A6** — new table `notification_preferences (restaurant_id, event, channel, enabled)`; check in
  `NotificationService::toRestaurant` before saving / pushing; settings page under
  `settings/settings.config.js` → account group.

Tests: every Phase A backend item gets a feature test next to the existing ones in
`apps/api/tests/Feature` (79 files today), including the tenant-isolation negative case.
