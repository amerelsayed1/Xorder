# Business Admin + menu

The business's own dashboard (`<slug>.xorder.io/admin`) and the diner-facing menu (QR and online ordering).

## Done

### Diner orders are priced by the server (XORD-047, P1)
**Status:** done (cloud `development`, commit `6e27fcd`) · **Group:** [G4](README.md#features-grouped) · **Repo:** xorder-cloud · **Closes:** XORD-047

- Each line names its item or combo and the option ids; `App\Services\DinerOrderPricing` prices it from the menu the diner was shown, with the menu's own arithmetic, in minor units. Names come from the menu in the diner's language.
- Refused before anything is written (422): old menu tab without ids ("please refresh", decision A5), another business's item, unavailable / hidden / deleted / off-hours items, unknown options, wrong choice counts.
- The menu shows a refused order instead of a false success and keeps the basket (system-only mode).
- Tests: `DinerOrderPricingTest` (9, fail with pricing removed). Not checked in a browser. **Release-day effect:** every diner with an old tab refreshes once.

## Next

### Dashboard order sheet matches the cashier's receipt
**Status:** done (cloud `development` `c2191fb`, commit from `feat/xord-048-order-sheet`) · **Group:** [G1](README.md#features-grouped) · **Repo:** xorder-cloud · **Approval:** given 2026-11-07 ("start") · **Closes:** XORD-048 · **Spec:** [`dashboard-order-receipt-parity`](../features/dashboard-order-receipt-parity/FEATURE.md)

- **Already on `origin/main` (`db25e21`):** branch, payment-status word, "handled by", completed time, cancellation reason.
- **Still missing, to add to `OrderResource` on the details request only:**

| Field | From |
|---|---|
| `invoice_number` | `orders.invoice_number` (the cloud's number, decision XORD-058) |
| `terminal_name` | `pos_terminals.name` via `pos_terminal_id` |
| `cashier_name` | `users.name` via `acting_user_id` |
| `table_label`, `dining_area_name` | via `table_id`, `dining_area_id` |
| `subtotal`, `discount`, `service`, `tax`, `total` | the `*_minor` columns |
| `payments[]` | `order_payments`: tender name in the viewer's language + amount |

- **Sheet (`OrdersView.vue`):** invoice number as the title (with `ORD-n`); date and time; cashier · till; type · table · area; lines; the money breakdown; each payment. Rows with no value are hidden (diner orders show no cashier, till or payments).
- **AC:** a till sale's sheet equals its stored values; a diner order invents nothing; another business's order is 404; every existing API key unchanged; the list request loads no payments (no N+1); Arabic RTL and English.
- **Tests:** Feature tests (till sale with split payment, diner order, cross-tenant 404, key set); `pnpm --filter @xorder/web build`; browser check on the local stack. No migration.

### Customer name and phone on till orders (cloud half)
**Status:** done (cloud `development` `c2191fb`, commit `e134d9e`) · **Group:** [G2](README.md#features-grouped) · **Repo:** xorder-cloud · **Approval:** none (additive) · **Pairs with:** [pos-cloud.md](pos-cloud.md) "the till sends the customer"

- **Was:** the cloud stored `customer_id` on a POS order but never `customer_name` / `customer_phone`, which the dashboard column reads (checked: `e9f9233` only refuses another business's customer).
- **Now:** `PosOrderService` copies the customer's name and phone onto the order when it is created (a snapshot, like a diner's order); a walk-in has neither; a replay returns the stored order unchanged.
- **Tests:** `PosOrdersTest` — the name and phone reach the dashboard list; a walk-in has none (mutation run fails the first). Full suite 1186 passed.
- **Still needed:** the POS half — the till does not send `customer_id` yet.

### Findings to fix
| ID | What | Status | Severity | Group |
|---|---|---|---|---|
| XORD-049 | Table orders have no Complete action on the Orders page and no hint why — add a note with a link to the Live board | ready | P3 | G6 |
| XORD-050 | Dining areas are reachable only through Settings — the Tables page's hint links there | ready | P3 | G6 |
| XORD-051 | Menu category pill out of sync after scrolling back up (seen once) | ready, reproduce first | P3 | G4 |
| XORD-052 | "؟T3": isolate the Latin table label in the table-service sheet | ready | P4 | G4 |
| XORD-053 | The diner's Send button looks disabled while enabled | ready, cause unverified | P4 | G4 |
| XORD-057 | A branch with no code — require one before a till can register (dashboard branch form + claim) | ready | P4 | G7 |

Each needs a person to look at the screen as well as its build.

## Waiting on the owner

- (G9) **Docker images:** 102 GB of local images no container uses — prune or keep (local machine only).
