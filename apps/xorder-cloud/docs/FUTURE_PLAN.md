# Future plan

Work the owner has decided to do **later**, with the design already discussed, so
it can be picked up without re-deriving it. Nothing here is approved for
implementation yet. Each item needs an explicit owner go.

Source: the GoSufra gap review (`docs/audits/2026-11-03-gosufra-gap-review.md`)
and the owner discussion of 2026-11-03.

| # | Item | Why it waits | Depends on |
|---|---|---|---|
| F1 | Kitchen steps in the order lifecycle | Revises a recorded POS-contract decision | — |
| F2 | Waiter app (with the "Served" step) | Owner plans it as its own app | F1 |
| F3 | Live order tracking for the diner | Small follow-up once F1 exists | F1 |

---

## F1 — Kitchen steps in the order lifecycle

**Today.** `App\Enums\OrderStatus` is `NEW → COMPLETED | CANCELLED`. The
2026-09-22 entry in `docs/coordination/BACKEND_TO_POS.md` ("The OrderStatus
decision (final)") records that the enum does not grow. Every "needs attention"
counter reads `status = NEW`: the pulse badge, the new-order alarm, Home stats,
Insights, the per-table counters.

**Proposal (as discussed).**
- Add `PREPARING` and `READY` between `NEW` and `COMPLETED`. `SERVED` belongs to
  F2. Staff may still jump straight from `NEW` to `COMPLETED`; cancel is
  allowed from any open state; terminal states never reopen.
- **Till orders are untouched.** Orders with `source = pos` keep
  `NEW → COMPLETED | CANCELLED`, and the dashboard shows no kitchen buttons on
  them. The till therefore never receives a status it doesn't know.
- **Dine-in table visits keep their own lifecycle.** The visit owns its running
  bill; closing it completes every open order. Per-round kitchen progress is
  part of F2.
- `NEW` keeps meaning "nobody has touched it", so the badge and alarm don't move.
- Add nullable `preparing_at` and `ready_at` timestamps for average prep
  time. `completed_at`/`completed_by` and `cancelled_at`/`cancelled_by` already
  exist (2026-11-03) and drive the Orders page's "time to complete".
- Code that today reads `status = NEW` as "open" must read "any open state":
  `TableController@live`, `TableVisitService::finish/expire`, and the open-order
  lookup in `PublicOrderController@store`.

**Needs before starting.**
- An owner go to revise the 2026-09-22 contract decision, plus an amendment row
  in `BACKEND_TO_POS.md`, mirrored to the `xorder-pos` repo copy.
- The alternative that keeps the contract untouched: a separate nullable
  `kitchen_step` column beside `status`. It was rejected in discussion because
  every screen would then reason about two fields.

**Unblocks.** The Home "waiting now / preparing now" tiles, completion rate
(gap-review A3), status-change notifications (A6), and F2/F3.

---

## F2 — Waiter app

**Owner intent (2026-11-03).** A dedicated waiter app rather than a step bolted
onto the dashboard. The "Served" order step belongs here, not in F1.

**Scope to define.**
- **Platform.** Native mobile (Flutter, alongside the POS) or a
  phone-first web app on the dashboard's existing auth and capabilities. The
  Live board (`LiveBoardView.vue`) already covers most of a waiter's floor
  view: tables, occupancy, new orders, and bill requests.
- **The `SERVED` step.** Dine-in only; it means "on the table, bill still open".
  Closing the table visit still turns it into `COMPLETED`. With a running
  dine-in bill made of rounds (`order_rounds`), "served" is most likely
  **per round**, not per order. Decide which before building.
- **Waiter actions.** Take an order at the table (a staff-side order on the
  table's visit), mark a round served, see bill requests, and close or cancel
  the visit.
- **Auth.** Staff sign-in with a per-restaurant role. Existing capabilities
  (`live.view`, `orders.update`, `tables.*`, `bills.*`) probably cover it; a
  dedicated `waiter` default role may help.
- **Push.** FCM is already wired for dashboard devices (`PushService`). A
  waiter device needs per-user or per-branch targeting, not per-restaurant.

**Depends on** F1 for the shared order steps.

---

## F3 — Live order tracking for the diner

**Today.** `GET /api/public/restaurants/{slug}/orders/{id}/status` returns only
the status. The menu app polls it only to decide when to show the review
prompt (`apps/menu/src/composables/useReviewPrompt.js`). It already ignores
statuses it doesn't know, so new values are safe.

**Proposal.** After checkout, show a small progress strip in the menu app:
received → preparing → ready (→ served, once F2 exists). It polls the same
endpoint and stops on a terminal state. No new endpoint, and no new data is
exposed.

**Depends on** F1.
