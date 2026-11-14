# Technical plan — pos-incoming-cloud-orders

Status: **plan, not approved** · 2026-11-06 · Spec: `FEATURE.md` (D1–D10) · Verified against: xorder-cloud `775bf0f` + uncommitted guest-paging edits, xorder-pos `c67c754` + unrelated UI edits · Companion: `waiter-app` (table-ordering retirement, D9, stays switched off until it ships)

## 0. Discrepancies found while planning (the spec is updated by these)

| # | Finding | Evidence | Effect on the plan |
|---|---|---|---|
| P1 | An online pickup/delivery order has **no branch**: `branch_id` is set only from a table session | `PublicOrderController.php:141`; `StoreOrderRequest.php:46-67` has no branch field | the menu must send a branch for multi-branch restaurants, otherwise no till can be chosen — **decision A3** |
| P2 | The public menu does not expose **option ids** (only names and prices) | `Http/Resources/Public/MenuItemPublicResource.php:50-54` (item `id` is exposed at `:26`) | additive `id` on options/variants before the menu can send them |
| P3 | The menu computes every line price on the phone | `apps/xorder-cloud/apps/menu/src/App.vue:343` (`line_total: qty * price`) | replaced by ids; server prices |
| P4 | A server pricing engine for menu items, variants, add-ons, charges and tax already exists | `app/Services/PosPricingEngine.php:48` (`price(Branch, orderType, lines, discount, currency)`, lines keyed by `menu_item_id`, `quantity`, option ids; sets `price_source` `server`) | **reuse** it for diner orders, but refuse deleted/unavailable items instead of its outage fallback (`:79-92` honours a snapshot) |
| P5 | An ETag'd poll with bodyless 304 already exists for the dashboard | `Http/Controllers/Dashboard/PulseController.php:17,54-56` | reuse the pattern for the till's incoming feed — **decision A1** |
| P6 | Settling an online order at the till would today create a **second** cloud order (POS path always `new Order`, `source='pos'`) | `PosOrderService.php:52,170,178,211` | settle must **update the online order in place** so the sale counts once — **decision A2** (order-integrity change) |
| P7 | Business hours are display-only for ordering | `WeeklyHours::isOpenAt` used only at `Category.php:58` | new server check on order create |

## 1a. Decisions taken (owner, 2026-11-06) — these override section 1 where they differ

| | Decision | Effect on the stages |
|---|---|---|
| **A1** | **Firebase (FCM) nudge + fallback check.** The cloud sends an FCM "something changed" nudge to the branch's devices (the cloud already sends FCM web-push to dashboards, `NotificationService.php:10`, `kreait/laravel-firebase` `composer.json:13`). Android/iOS handhelds and macOS tills fetch the feed at once on the nudge; **Windows tills poll every 2 s** while a shift is open (FlutterFire messaging has no Windows support — re-check the plugin's platform list when building). The order is always read from `GET pos/incoming`, never from the push payload, so a lost or late nudge loses nothing. | S3 adds `pos_terminals.fcm_token` (nullable); S4 adds `POST pos/terminals/push-token` and sends the nudge after an order/request event (after the response, best-effort, like `PublicOrderController.php:178-195`); S7 adds the `firebase_messaging` plugin to the POS (Android/iOS/macOS builds only) — **a new dependency and a Firebase app config in the POS repo, needs approval** |
| **A2** | **Settle completes the same online order** (no second order). | S5 as written |
| **A3** | **Nearest branch by the diner's phone location, diner can change it.** The menu asks for location; the server picks the nearest **open, accepting** branch from `branches.latitude/longitude` (`Branch.php:29-30`); the menu shows it and lets the diner switch; location denied or no branch coordinates → the diner picks from a list. Single-branch restaurants skip all of this. | S2: `branch_id` on the order request (validated to the restaurant), a public "nearest branch" helper (distance computed server-side from coordinates the diner sends; the coordinates are used for the choice and **not stored**), menu UI. Branches without coordinates are listed but never auto-picked. |
| **A4** | **Admin switch + version check** per branch (`online_orders_on_pos`, default off). | S6 as written |
| **A5** | **Everyone refreshes.** From the release, an order without item ids is refused for **every** restaurant with "please refresh the menu" (422). No legacy window; the trusted-price hole closes on release day. | S1: no `client_asserted` fallback for diner orders; rollout step 5 removed. **Every restaurant is affected on release day** (a diner with an old tab must refresh once). |
| **A6** | **Working hours are enforced only for POS branches** (with the switch on). Other restaurants keep today's behavior. | S2: the hours check runs only when `online_orders_on_pos` is on |

## 1. Decisions this plan needs (recommendations first) — superseded by 1a

- **A1 Transport for "instant" (D8).** *Recommended:* the till polls `GET pos/incoming` every **2 s while a shift is open**, ETag/304 when nothing changed (P5 pattern); measured latency target ≤ 2 s at the 95th percentile on staging. No new server software. *Alternative:* a websocket service (Laravel Reverb) on the production VPS — true push, but a new always-on service on a box co-hosting another product; can be added later behind the same feed without changing the POS screens.
- **A2 Settle = update in place.** When the till settles an accepted online order, the POS posts its order with `online_order_id`; the server attaches the POS fields (invoice number, minor-unit totals, terminal, shift, `client_transaction_id`, payments) to the **existing** online order and completes it, instead of creating a new order. Idempotent on `client_transaction_id` as today.
- **A3 Branch of an online order.** *Recommended:* single-branch restaurants: the only branch, automatically. Multi-branch: the diner picks the branch in the menu before checkout (the menu already receives `branches`, `RestaurantPublicResource.php:29`); the server validates it belongs to the restaurant and is open.
- **A4 POS mode is switched per branch, by hand.** A new branch setting `online_orders_on_pos` (default **off**). While off, everything works as today. An admin turns it on only after the branch's till runs a POS version that reads the feed (answers Q8: the till reports its app version on each feed read; the switch is refused if no till of the branch reported a supporting version). D9 (retiring table ordering) is a **second** switch, refused until the waiter app is live for that branch.
- **A5 Old cached menus.** A browser tab loaded before the release sends no ids. For a branch with `online_orders_on_pos` on: 422 "please refresh the menu". For other branches during a transition window: accepted as today with `price_source = 'client_asserted'`, then removed in a later release (fixes the trusted-price finding for everyone once the window ends).

## 2. Reuse (do not rebuild)

`PosPricingEngine` (P4) · `PulseController` ETag pattern (P5) · `WeeklyHours::isOpenAt` with spillover (`WeeklyHours.php:28,86`) · `PosDeviceAuth` device group (`api.php:823`) · `TableVisitService` locks · `BillRequest` + statuses for table requests · POS outbox and idempotent resend (`outbox_drain.dart:45-59`) · POS `TicketEngine`/parked tickets for the accepted ticket · POS permission catalog (`permissions.dart:180`, `_risk`, `overridable`) · existing public order status route (`api.php:892`).

## 3. Stages

Order: cloud contract and additive schema first, consumers after; every stage keeps today's behavior when `online_orders_on_pos` is off.

| Stage | Repo · paths | Change | Tests that prove it | Rollback |
|---|---|---|---|---|
| **S1 Server pricing** | cloud · `Resources/Public/MenuItemPublicResource.php`, `Requests/Public/StoreOrderRequest.php`, `Controllers/Public/PublicOrderController.php`, new `Services/DinerOrderPricing.php` (wraps `PosPricingEngine`); `apps/xorder-cloud/apps/menu/src/App.vue` | additive option/variant `id` in the public menu; request accepts `menu_item_id`, `variant_id`, `option_ids[]` per line; server prices via the engine, refuses unknown/unavailable/foreign items (422) before any write; legacy payload per A5 | Feature: tampered `line_total` → menu price, `price_source=server` (AC-2); foreign/unavailable/deleted item → 422, nothing written (AC-3); legacy payload on a non-POS branch still 201 (A5); public menu shape is additive (existing keys unchanged) | revert code; no schema |
| **S2 When ordering is open** | cloud · `PublicOrderController.php`, `Services/PublicMenuService.php`, `RestaurantPublicResource`/`BranchPublicResource` (additive `ordering_open`, `next_open_at`, `closed_reason`); menu SPA branch picker (A3) and closed states | order create refuses outside `business_hours` / `is_open` off / (POS mode) no till online; branch required for multi-branch | Feature: inside/outside hours incl. overnight spillover and timezone (AC-10); no till online in POS mode → 422 (AC-11); POS mode off → unchanged; branch from another restaurant → 422 | revert code |
| **S3 Schema (additive)** | cloud · new migrations | `branches.online_orders_on_pos` bool default false; `orders`: `accepted_at`, `accepted_by_terminal_id` (nullable FK), `rejected_at`, `reject_reason` (nullable); `bill_requests`: `handled_by_terminal_id` (nullable); `pos_terminals`: `last_feed_at`, `app_version` (nullable); indexes on `(restaurant_id, branch_id, updated_at)` for the feed | migration runs on SQLite suite; PostgreSQL lock/rewrite review **by reading** (nullable/defaulted columns only, no backfill) | `down()` drops the new columns; not run on any real DB |
| **S4 Device feed and actions** (`POS-BE-033`) | cloud · `routes/api.php` device group, new `Controllers/Pos/PosIncomingController.php`, `Requests/Pos/*`, `Resources/Pos/IncomingEventResource.php`, `Services/OnlineOrderInbox.php` | `GET pos/incoming?cursor=` (ETag/304; orders and table requests of **this branch** changed since cursor; records `last_feed_at`, `app_version`); `POST pos/online-orders/{order}/accept` · `/reject {reason}` · `POST pos/table-requests/{billRequest}/handled` — each idempotent on a client id, first-writer-wins under `lockForUpdate` | Feature: cursor returns each event once (AC-14); 304 when idle; cross-tenant and cross-branch → 404 (AC-15); accept twice → one result; two tills race → second gets 409 "already accepted"; reject stores reason and diner status shows it (AC-6) | routes unused until POS ships; revert |
| **S5 Settle in place** (A2) | cloud · `PosOrderService.php`, `Requests/Pos/StorePosOrderRequest` | optional `online_order_id`: must be this branch's accepted online order; server re-prices lines with the engine as today and writes POS fields onto that order, completes it; a second order is never created | Feature: settle → one order, COMPLETED, sales stats count it once (AC-7); retry same `client_transaction_id` → same order; `online_order_id` of another tenant → 404; of a not-accepted order → 422; POS orders without the field unchanged (regression) | revert code; columns stay unused |
| **S6 Dashboard read-only for POS branches** | cloud · `Controllers/Dashboard/OrderController.php` (dirty — guest-paging WIP), `BillRequestController`, `TableController::finishVisit`; `apps/web` orders/live pages | when `online_orders_on_pos` is on: status/bill/visit writes → 403 with a clear message; UI shows read-only banner "managed on the POS"; admin toggle with version check (A4) | Feature: writes refused for POS branch, allowed otherwise (AC-12, AC-13); toggle refused without a supporting till version | switch the setting off |
| **S7 POS inbound** | POS · `lib/data/cloud/cloud_api.dart`, new `lib/data/cloud/incoming_feed.dart`, `lib/app/providers.dart`, new local table via `lib/data/postgres/migrations.dart` (`pos_incoming`: cloud id, kind, payload, state, cursor), fakes in `lib/data/fakes` | 2 s poll while a shift is open (A1), backs off on errors, never blocks selling; stores events locally so a restart keeps them | `flutter test`: loop with a fake cloud (304, events once, offline/backoff, restart); PostgreSQL suite for the local table (`scripts/check.sh`, throwaway DBs dropped) | ship POS without enabling; feed unused |
| **S8 POS screens and permission** | POS · `lib/domain/models/permissions.dart` (new `online_orders.accept`, risk, default roles), `lib/features/...` incoming panel + sound + badge, floor badge for table requests, `lib/core/l10n/app_strings.dart` (ar/en) | accept → ticket via `TicketEngine` (takeaway/delivery with customer and address); reject with reason; handled for requests; settle posts `online_order_id` through the outbox | widget tests for panel/permission gating (AC-5); unit tests accept→ticket lines and totals equal server lines (AC-4); integration test extending `integration_test/sale_to_settle_test.dart` incoming → accept → settle → outbox → fake cloud (AC-7) | hide behind the branch switch |
| **S9 Menu table page (requests only)** | cloud · `apps/menu` table route; `PublicOrderController` refuses orders on a table session when the branch is in table-retired mode | **built but switched off** until `waiter-app` (D9) | Feature: table session order → 422 only when retired (AC-8) | switch off |
| **S10 Docs and contract** | workspace `docs/features/pos-incoming-cloud-orders/{API,DATABASE,TEST_PLAN,TEST_REPORT,CHANGELOG}.md`; `docs/coordination/POS_TO_BACKEND.md` + `BACKEND_TO_POS.md` in **both** repos (reconcile the existing POS-BE-022 drift first) | POS-BE-033 PROPOSED → READY when S4–S5 pass | `bash scripts/harness/verify.sh` | — |

## 4. Rollout order (independent deploys)

1. Cloud S1–S6 (+S9 dark) — additive; with the switch off every branch behaves as today except: server prices (A5) and the working-hours check (S2). **That is a behavior change for every restaurant** (orders outside hours now refused) — confirm (A6 below).
2. POS release with S7–S8; tills start reporting `app_version` on feed reads.
3. Per branch: admin turns on `online_orders_on_pos` (A4).
4. After `waiter-app` is live in a branch: turn on table retirement (S9).
5. ~~Later release: end the A5 legacy window.~~ Removed by A5 (everyone refreshes from release day).

Old POS against new cloud: unaffected (new routes unused, `online_order_id` optional). New POS against old cloud: feed returns 404 → the POS hides the incoming panel and keeps selling.

## 5. Domain lens

Café and cloud kitchen: one queue at the till, server prices, hours respected. Restaurant: requests at the till now; table ordering moves with `waiter-app`. Food truck: works only while the till has signal; with A1 polling, ordering closes when the till drops (BR-6) — acceptable per D5. No dependency on tips, KDS, aggregators, recipes, loyalty or multi-brand; kitchen printing (`?`) is a dependency for "goes to the kitchen".

## 6. Verification commands

- Cloud: `cd apps/xorder-cloud/apps/api && php artisan test --filter 'DinerOrderPricing|OrderingAvailability|PosIncoming|PosOrder|PublicOrder|BillRequest|OrderTableAssociation'`, then `php artisan test` (SQLite `:memory:`; PostgreSQL-only behavior reviewed by reading).
- Vue: `cd apps/xorder-cloud && pnpm --filter @xorder/menu build && pnpm --filter @xorder/web build` (no JS test framework exists; screens checked by a person in the preview, both locales and themes).
- POS: `cd apps/xorder-pos && flutter analyze && flutter test`, then `scripts/check.sh` for PostgreSQL suites (needs `POS_PG_*`; reported as not run otherwise).
- Harness: `bash scripts/harness/verify.sh`.

## 7. Risks

- **Mixed working tree:** guest-paging edits are uncommitted in `PublicOrderController.php`, `Order.php`, `Dashboard/OrderController.php`, `OrderResource.php` — S1, S2, S6 touch the same files; commit or land that work first, or my edits mix with it.
- 2 s polling from many tills: ~30 requests/min per till, mostly 304; measure on staging before enabling widely.
- A2 changes how POS sales are recorded for online orders (order integrity) — reviewed with `security-reviewer`.
- S2 changes behavior for all restaurants (hours enforcement).
- SQLite tests cannot prove PostgreSQL row locking in the two-till race.

## 8. Approvals needed before building

Decided in 1a: A1–A6. Still to approve, as a whole, before the first edit:
1. Additive migrations S3 (cloud: branch switch, accept/reject fields, terminal `last_feed_at`/`app_version`/`fcm_token`, bill-request handler) and S7 (POS local `pos_incoming`).
2. The order-integrity change in `PosOrderService` (A2) and the new accept/reject order transitions.
3. New contract item POS-BE-033 and the rollout order in section 4 (step 5 removed by A5).
4. Narrowing dashboard writes for POS branches (S6) and the new POS permission (S8).
5. **New POS dependency** `firebase_messaging` plus a Firebase app config for the POS (A1).
6. Release-day behavior change for all restaurants: old menu tabs must refresh (A5).
7. Starting with S1–S2 while the guest-paging edits are still uncommitted in the same files — or wait until they land.
8. Nothing is committed or pushed; any later push to `xorder-cloud` `main` goes through `/release-check` and your explicit go.

Still open from FEATURE.md and not blocking S1–S6: Q2 (several tills), Q3 (call-waiter type), Q6, Q7, Q9 (drop tolerance — default 30 s of missed polls proposed), Q11, Q12.

## As built — S1 server pricing (2026-11-07, XORD-047)

Branch `fix/xord-047-server-priced-diner-orders` (`6e27fcd`, cloud), not pushed. Built in a separate worktree because the guest-paging edits are still uncommitted in `PublicOrderController::store` (merge by hand).
- **Deviation from the plan:** `DinerOrderPricing` does not wrap `PosPricingEngine`. It reproduces the menu's own arithmetic (`useCart.calculateLinePrice`) against `PublicMenuService::loadMenu()`, with no tax, service or discount, because diner orders carried none before and adding them would change every quoted total. Applying the engine belongs with the POS-ticket stages (S4–S5).
- Request: `items.*.kind` (item|combo), `menu_item_id` | `combo_id`, `option_ids[]`, `qty`, `note`, optional `lang`; `name`, `variant`, `options`, `line_total`, `total` accepted and ignored. No ids → 422 "please refresh" (A5).
- Stored line JSON: `kind`, id, `option_ids`, `name`, `qty`, `options`, `variant` (only when chosen), `note`, `unit_price`, `line_total`, `price_source: server`; `order_items` gets `menu_item_id`, `unit_price_minor`, `line_total_minor`, `price_source`.
- Public menu: option `id` and combo-choice `id` added (additive).
- Tests: `DinerOrderPricingTest` (9). Full suite 1157 passed.


## S4 detailed plan — POS-BE-033, cloud only (2026-11-09, plan, **not approved**)

Verified against: xorder-cloud `775bf0f` on `feat/finance-accounts-and-platform-updates-2026-10-26` with 45 uncommitted files (incl. `PublicOrderController.php`); S1 lives on `fix/xord-047-server-priced-diner-orders` (`6e27fcd`), not merged here.

### Findings from re-reading the code
| # | Finding | Evidence | Effect |
|---|---|---|---|
| F1 | **Contract id clash.** `POS-BE-033` is also claimed by `guest-paging` S5 (pickup endpoint, `pickup_token`/`receipt_number` on `POST pos/orders`). Neither is in either `BACKEND_TO_POS.md` ledger (last listed id there is 028; 029 is in `BACKOFFICE_TO_CLOUD.md`). | `docs/features/guest-paging/{FEATURE,TECHNICAL,API}.md`; this file §3 S4/S10 | Owner chose this feature for 033. guest-paging must be renumbered (suggest **POS-BE-034**) before either is written to a ledger. |
| F2 | **S3 schema does not exist anywhere.** No `online_orders_on_pos`, `accepted_at`, `reject_reason`, `handled_by_terminal_id`, `last_feed_at`, `app_version`, `fcm_token`. Newest migration is `2026_11_02_000100_add_guest_paging_to_orders_table.php`. | `grep` over `app/` and `database/` returns nothing | S4 cannot be written before S3. Plan builds S3's migration as stage 1. |
| F3 | Device group is `pos.device` + `throttle:240,1`; terminal is `$request->attributes['pos_terminal']`, `TenantContext` pinned to the restaurant. Branch scoping must be added by hand (`where branch_id = terminal->branch_id`); tenant scope is automatic. | `routes/api.php:823`, `Http/Middleware/PosDeviceAuth.php` | Cross-branch → 404 needs an explicit branch filter. |
| F4 | Order statuses are only `NEW / COMPLETED / CANCELLED`; bill request statuses `REQUESTED / SEEN / IN_PROGRESS / COMPLETED / CANCELLED`. | `Enums/OrderStatus.php`, `Enums/BillRequestStatus.php` | "Accepted" is **not** a status: it is `accepted_at IS NOT NULL` on a `NEW` order (no enum change, additive). Reject = `CANCELLED` + `rejected_at` + `reject_reason`. Table request "handled" = `COMPLETED` + `handled_by_terminal_id`. |
| F5 | No pending-orders feed exists for devices; the ETag/304 pattern is `PulseController` (`setEtag`, `isNotModified`). | `Dashboard/PulseController.php:54-56` | Reuse the pattern. |
| F6 | Online orders have no branch unless S2 lands (spec P1/A3). Until S2, the feed returns nothing for pickup/delivery orders. | `PublicOrderController.php:141` (per spec) | S4 is shippable dark; real use needs S2 (and S1 merged). |

### Endpoints (new, additive, device group; nothing existing changes shape)
- `GET pos/incoming?cursor=` → `{data:{events:[…],cursor}}`, `ETag`/304 when idle. Events = online orders (`source != 'pos'`, `branch_id = terminal branch`, `NEW`/`CANCELLED`, `online_orders_on_pos` on) and open/closed table requests of **this branch**, ordered by `(updated_at,id)`; cursor is an opaque `updated_at|id` pair so each change is returned once. Stamps `pos_terminals.last_feed_at`, `app_version` (from `X-App-Version` header or `?app_version`, UNVERIFIED which the POS will send — decide in the contract).
- `POST pos/online-orders/{order}/accept` (body `client_request_id`), `POST …/reject` (`client_request_id`, `reason` ≤ 255), `POST pos/table-requests/{billRequest}/handled` (`client_request_id`). All inside `DB::transaction` + `lockForUpdate`: first writer wins; same terminal repeating the same `client_request_id` → same 200 result; another terminal after the winner → 409 `ALREADY_ACCEPTED` / `ALREADY_REJECTED` / `ALREADY_HANDLED`; foreign tenant or branch → 404.
- Cashier permission (`online_orders.accept`, AC-5) is a POS-side permission today; the server check is `acting_user_id` holding it, as refunds do (`pos.refund`). **UNVERIFIED** how cloud tenant roles map to the POS permission catalog (S8 owns the seed); until then accept/reject require only the device token, which is weaker than AC-5. Needs your decision (Q-new-1).
- Reject sets the diner-visible status: verify `public/orders/status` returns `reject_reason` (not yet checked; AC-6).

### Stages
| Stage | Paths | Change | Tests (`apps/api/tests/Feature/Pos/PosIncomingTest.php`, new) | Rollback |
|---|---|---|---|---|
| **4.0 Schema (S3 subset)** | one new migration in `database/migrations/` | `branches.online_orders_on_pos` bool default false; `orders.accepted_at`, `accepted_by_terminal_id` (nullable FK), `rejected_at`, `reject_reason`, `accept_client_request_id`; `bill_requests.handled_by_terminal_id`, `handled_client_request_id`; `pos_terminals.last_feed_at`, `app_version`; index `(restaurant_id, branch_id, updated_at)` on orders and bill_requests. FCM token column/route **left out** (A1 nudge is a later stage). Nullable/defaulted only, no backfill. PostgreSQL index build on `orders` takes a write lock: review by reading, owner decides on `CONCURRENTLY` per `postgres-migrations.md`. | migration applies on SQLite | `down()` drops them; **not run on any real DB** |
| **4.1 Service** | new `app/Services/OnlineOrderInbox.php` | feed query, cursor, accept/reject/handled with locks and idempotency | unit-level via feature tests | revert |
| **4.2 HTTP** | new `Http/Controllers/Pos/PosIncomingController.php`, `Http/Requests/Pos/{AcceptOnlineOrder,RejectOnlineOrder,HandleTableRequest}Request.php`, `Http/Resources/Pos/IncomingEventResource.php`, 4 routes in `routes/api.php` device group | as above; errors via `PosApiException` | AC-14 (each event once, reconnect catch-up), 304 when idle, AC-15 (other tenant / other branch → 404), accept twice → one result, two-terminal race → 409, reject stores reason + order `CANCELLED`, handled closes request, validation, revoked terminal 403, **old orders untouched when switch off (feed empty)** | remove routes |
| **4.3 Contract/docs** | `docs/coordination/{POS_TO_BACKEND,BACKEND_TO_POS}.md` in **both** repos, feature API/DATABASE/TEST_PLAN/TEST_REPORT/CHANGELOG | POS-BE-033 **PROPOSED**; READY only after tests pass and cloud is deployed; reconcile the existing POS-BE-022 drift first; renumber guest-paging S5 | `bash scripts/harness/verify.sh` | — |

Not in this item: S1/S2 merge, S5 settle-in-place (`PosOrderService`), S6 dashboard read-only, FCM nudge, any POS code.

### Where to build (decision needed)
The main checkout is dirty (45 files, `PublicOrderController.php` among them, plus other sessions' work). S4 touches only **new files plus `routes/api.php`** (is `routes/api.php` among the 45 dirty? checked: not listed in the first 10 lines — re-check at implement time). Recommendation: **a new worktree off `775bf0f`** on `feat/pos-be-033-incoming-feed`, so nothing mixes with the uncommitted work; it needs the S1/S2 branches merged later by hand.

### Verification commands (cloud)
`cd apps/xorder-cloud/apps/api && php artisan test --filter PosIncoming`, then `php artisan test`. SQLite `:memory:` cannot prove `lockForUpdate` semantics or PostgreSQL index/lock behaviour: the two-terminal race is tested serially (second call sees the committed winner) and the rest is flagged for a person on PostgreSQL.

### Risks
Order-state change (accept/reject are new transitions) and a contract change → both need approval. Feed is empty until S2 gives online orders a branch. Without the permission mapping (Q-new-1) any paired till could accept. 2 s polling load is S7's concern, not S4's.

### Venue models
Café / cloud kitchen: this is the till's incoming queue (helps). Restaurant: table-request handling at the till. Food truck: needs signal to receive orders (feed polling); no change otherwise. Depends on no known gap except kitchen printing for "goes to the kitchen" (S8).

### Approvals needed
1. Additive migration 4.0 (and the PostgreSQL index-lock choice).
2. New order transitions accept/reject and the new contract POS-BE-033 (PROPOSED); renumber guest-paging S5 to POS-BE-034.
3. Q-new-1: server-side permission for accept/reject (`acting_user_id` + a cloud capability) — or device token only for now.
4. Build in a new worktree off `775bf0f`.

## As built — S4 device feed (POS-BE-033, 2026-11-09)

Branch `feat/pos-be-033-incoming-feed` in worktree `apps/xorder-cloud/.claude/worktrees/pos-be-033` (base `775bf0f`), **uncommitted, not pushed**. Cloud only; no POS code.
- **Schema** (`2026_11_09_000100_add_incoming_feed_to_orders_and_requests.php`, written not run): `branches.online_orders_on_pos` (default false); `orders.{accepted_at, accepted_by_terminal_id, accept_client_request_id, rejected_at, reject_reason, reject_client_request_id}`; `bill_requests.{handled_by_terminal_id, handled_client_request_id}`; `pos_terminals.last_feed_at` (`app_version` already existed); indexes `orders_feed_idx`, `bill_requests_feed_idx` on `(restaurant_id, branch_id, updated_at)`. **Deviation:** the FCM token column and nudge route are not built (separate stage).
- **Code:** `Services/OnlineOrderInbox.php`, `Controllers/Pos/PosIncomingController.php`, `Requests/Pos/{AcceptOnlineOrder,RejectOnlineOrder,HandleTableRequest}Request.php`, `Resources/Pos/IncomingEventResource.php`, 4 routes in the `pos.device` group, datetime casts on `Order`/`PosTerminal`, error strings (en/ar), additive `rejected: true` on `GET public/restaurants/{slug}/orders/{id}/status` (the free-text reason is not public).
- **Cursor:** per table, newest `updated_at` second plus fingerprints (id + state) of rows already delivered in that second, so two changes in the same second are neither lost nor repeated.
- **Not built:** server-side cashier permission on accept/reject (device token only; AC-5 open), feed gating on a till being online for S2's BR-6, S1/S2 (online orders have no branch yet, so the feed is empty for them), S5–S9, any POS work.
- Tests: `tests/Feature/Pos/PosIncomingTest.php` (16). See `TEST_REPORT.md`.
- **Review changes (2026-11-09):** database-reviewer: partial `hasColumn` guards removed, `id` added to both feed indexes, lock notes rewritten in the migration. security-reviewer: orders of an open table visit excluded from feed and actions; cursor `ts` validated (422, not a PostgreSQL 500) and `seen` capped; `reject_reason` removed from the unauthenticated status route. **Open (not fixed):** AC-6 "diner sees the reason" needs an unguessable per-order token; no `rejected_by_terminal_id` / audit actor on reject; accept/reject do not clear the dashboard's unread `order.created` notification; accept/reject need the cashier permission (AC-5); a 100+ rows-in-one-second burst could stall a cursor.
