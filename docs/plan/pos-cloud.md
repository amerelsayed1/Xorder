# POS cloud

The till working against XOrder Cloud: licence, pairing, menu and staff download, sales sent to the dashboard.

## Done

### The cloud's invoice number, and PROVISIONAL first (XORD-058)
**Status:** done (POS `development`, commit `db3c2cd`) · **Group:** [G1](README.md#features-grouped) · **Repo:** xorder-pos · **Closes:** XORD-058

- A cloud till's first receipt says "مبدئية" (provisional); its history and reprints show the number the cloud gave the sale. Offline tills print their own number as before.
- Tests: `provisional_invoice_test` (3, fail with the fix removed). Manual: receipt "مبدئية", cloud order 122 = `BR8-2026-000013`.

### End-to-end on the local stack
**Status:** done · **Group:** [G7](README.md#features-grouped) · licence activation, pairing by setup code, menu download (137 items), staff sync, PIN sign-in, table sale, payment → cloud order with the same transaction id. Report: [2026-11-07 manual test](../testing/reports/2026-11-07-manual-pos-cloud-till-local.md).

## Next

### The till sends the customer with a sale
**Status:** done (POS `development` `3052a53`, commit `90df643`); end-to-end check not run · **Group:** [G2](README.md#features-grouped) · **Repo:** xorder-pos · **Approval:** given 2026-11-07 ("Yes, build it") · **Closes:** XORD-001 "Remaining" · **Pairs with:** [business-admin-and-menu.md](business-admin-and-menu.md) "customer name and phone"

- **Today:** `OutboxDrain.buildOrderRequest` sends no customer, so a sale rung up for "عامر السيد" shows "—" on the dashboard. The cloud already accepts `customer_id` and refuses another business's customer (`origin/main` `e9f9233`).
- **Change:** send `customer_id` = the customer's `platform_id`. The outbox already sends customers before orders; a sale whose customer is not yet on the platform waits behind it, and never sends a local id.
- **AC:** a sale with a customer reaches the cloud with that customer's platform id; a walk-in sends none; a replay of a delivered sale is unchanged.
- **Tests:** `outbox_drain_test` (payload with and without a customer); manual: the test till's customer sale shows the name on `/admin/orders`.
- **Rollout:** cloud half first (it fills the name and phone), then POS. An old cloud already accepts `customer_id` (`e9f9233`) and just does not show the name.
- **As built:** a customer still queued holds the sale one pass (`CUSTOMER_NOT_YET_ON_PLATFORM`); a customer held for a person, or never queued, lets the sale go as a walk-in rather than hold the money. Tests: four in `outbox_drain_test` (three PostgreSQL), mutation-checked.

### XORD-058 follow-up
**Status:** done (POS `development` `3052a53`, commit `9f3d850`) · **Group:** [G1](README.md#features-grouped) · **Repo:** xorder-pos · **Approval:** given 2026-11-07 ("Yes, build it")

- The receipt dialog refreshes to the cloud's number when the outbox brings it back a second after the sale (a reprint already does).
- Before delivery, the till's history shows "provisional" rather than its own local number.
- **Test:** widget test with a fake drain.
- **Today (read 2026-11-07, POS `development` `db3c2cd`):** the dialog builds its slip once from `SubmitOrderResult.invoiceNumber` (`receipt_dialog.dart:70`) and never looks again; the drain writes `pos_orders.server_invoice_number` (`outbox_drain.dart:505`), and `applySyncOutcome` (`providers.dart:1323`) refreshes only the counts. History shows `coalesce(server_invoice_number, invoice_number)` (`postgres_order_history_repository.dart:81`), so before delivery a cloud till lists its local number.
- **Plan (approved 2026-11-07, built as written):**
  1. A `salesDeliveredProvider` counter, bumped in `applySyncOutcome` when `drain.delivered > 0`.
  2. `OrdersRepository.serverInvoiceNumber(orderId)` reads `pos_orders.server_invoice_number`.
  3. The receipt dialog, on a cloud till with no number yet, watches the counter and re-reads; once a number arrives it swaps the number and the "sent" note into the cached slip, keeping its time. A print after that prints the number.
  4. History: the query also returns whether the platform has numbered the row; on a cloud till an unnumbered row shows "PROVISIONAL / مبدئية" in the list and the detail header. Search by the local number still finds it. Offline tills are unchanged.
- **Tests:** widget test (fake repository, counter bumped → number shown; offline till never changes); PostgreSQL test for the history flag; history widget test (cloud + unnumbered → provisional; offline → its own number).
- **Not touched:** no migration, no contract change, no money or order state.
- **As built:** a record counts as numbered unless the PostgreSQL history says otherwise, so fakes and older callers show their number as before. Tests: `receipt_platform_number_test` (3), `provisional_invoice_test` (+3, PostgreSQL), `order_history_test` (+2); three mutation runs fail as expected. Not checked on a real till.

## Later

- (G5) **POS receives cloud orders** (`pos-incoming-cloud-orders`): pickup, delivery and table requests reach the till. On hold until guest paging is committed (same files). Plan: [TECHNICAL.md](../features/pos-incoming-cloud-orders/TECHNICAL.md).
- (G5, G6) **Table requests on handhelds** (waiter stage WS8): cloud mode only.

## Waiting on the owner

- (G3) **XORD-055** — how fast a staff change reaches a running till. Today a new cashier cannot sign in until the next sync (up to 4 hours idle) or until someone presses the sync pill. Options: tell the dashboard user, or have the till check soon after a staff change.
