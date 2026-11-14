# XORD-001 — send the order's customer to the platform (PLAN, NOT APPROVED)

Written 2026-10-25 by `/develop-feature implement Master tracking checklist` after the owner chose "close gaps on built items". **Status: proposed. No code has been changed.** Source revisions: `xorder-cloud` 06bc8e3, `xorder-pos` 2e7e612, both with large uncommitted working trees (other sessions are editing).

## Gap being closed
`docs/qa/XORDER_QA_FINDINGS.md` XORD-001, criterion 5: the POS records a customer on the sale (`pos_orders.customer_id`, migration 51) but the order uploaded to the platform does not name them.

## Verified in source (path:line)
| Claim | Evidence |
|---|---|
| POS never sends a customer with an order | `apps/xorder-pos/lib/data/cloud/outbox_drain.dart:166` `buildOrderRequest` has no customer parameter; the pending-orders query (`:329`) does not select `o.customer_id` |
| Customers are uploaded before orders, and the platform id is written back | `outbox_drain.dart:296-312` phase order `customer → shift_open → order`; `_customerEvent` (`:690`) stores `pos_customers.platform_id` |
| Cloud already accepts `customer_id` (integer, nullable) | `apps/xorder-cloud/apps/api/app/Http/Requests/Pos/StorePosOrderRequest.php:29`, stored at `app/Services/PosOrderService.php:180` |
| **Cloud does not check that customer belongs to the till's restaurant** | the only `customer` code in `PosOrderService.php` is line 180; no `exists` rule on the request; `CUSTOMER_NOT_FOUND` is listed in `docs/coordination/BACKEND_TO_POS.md:1706` but `grep -rn CUSTOMER_NOT_FOUND app tests` finds nothing. No test names `customer_id` under `tests/Feature/Pos` |
| `customer_id` is not in the idempotency hash, so a retry of an order first sent without it is not a mismatch | `PosOrderService.php:537-558` (`orderPayloadHash` covers branch, type, lines, discount, payments only) |
| `Customer` is tenant-scoped | `app/Models/Customer.php:12` `BelongsToRestaurant` |

**Why this matters:** today the hole is dormant because no POS build sends `customer_id`. The moment the POS does, an order could name another restaurant's customer unless the cloud checks first. So the cloud check ships **first**.

## Stages
**Stage 1 — cloud, no schema (approval needed: order endpoint behaviour).**
- In `PosOrderService` (or the request), resolve `customer_id` through the tenant-scoped `Customer` model for `$terminal->restaurant_id`; unknown or foreign id → `PosApiException('CUSTOMER_NOT_FOUND', 422)` (the code the contract already lists). `null` stays valid (walk-in).
- Tests in `tests/Feature/Pos/PosOrdersTest.php`: own customer accepted and stored; foreign customer refused and nothing written; unknown id refused; null still works; replay of an order first sent without a customer is not a payload mismatch.
- Rollback: revert the check; no data change.

**Stage 2 — POS (approval needed: order payload; after stage 1 is deployed).**
- `buildOrderRequest` gains `customerId` (platform id); `_drainOrders` selects `c.platform_id` via `LEFT JOIN pos_customers`.
- Order whose customer has no `platform_id` yet: **defer** (not quarantine) until the customer event is delivered, then send the order with the customer. **Owner decision D1 (2026-10-25): an order that has a customer always goes up with that customer. It is never sent without one and the customer is never dropped.** If the customer's upload is stuck, the order waits and shows up in the existing stuck-queue reporting; it is not silently sent as a walk-in.
- Tests: pure `buildOrderRequest` unit test (key present when set, omitted/null when not); PostgreSQL drain test for deferral and for the quarantined-customer fallback (needs `POS_PG_HOST`, otherwise it self-skips and must be reported as **not run**); one widget/unit test that the required-field rule of the customer dialog is unchanged (the remaining half of criterion 4).
- Rollback: older POS builds simply omit the field.

**Stage 3 — docs.** Record the behaviour in `docs/coordination/BACKEND_TO_POS.md` of both repos (compare both copies first; they can drift), `/project-documentation update customers`, and tick XORD-001 criteria only where a run test proves them.

## Rollout order
Cloud stage 1 → deploy → POS stage 2 build. Old POS + new cloud: unaffected (field absent). New POS + old cloud: field accepted unchecked, which is today's exposure, so POS must not ship before the cloud. No migration on either side.

## Venue models
Café and food truck: the walk-in path (no customer) is untouched; a food truck offline keeps working because the order is deferred only when it names a customer whose upload is still pending. Cloud kitchen: this link is what delivery needs (the cloud `orders` table already has `customer_id`, name, phone and address columns; the POS path fills only `customer_id`, so name/phone/address snapshots on the order remain empty: **reported, out of scope**). Restaurant: nothing table-specific.

## Decisions needed from the owner
- **D1 — decided 2026-10-25:** the customer always travels with the order (see stage 2). No "send without customer" fallback.
- **D2 — awaiting an explicit "go":** the cloud check returning 422 for a foreign or unknown `customer_id` (contract-listed code; no current client sends the field). Under D1 a correctly working till only ever sends an id the platform gave it, so this fires only on a wrong or tampered id.

## Not in this plan (and why)
- **XORD-005 POS dialogs:** another session, "XORD-005 feature development", is editing them now (files modified 19:47–19:54 today, new `content_languages_dialogs_test.dart`). The QA file's "still show both fields" is already out of date. Not touched here.
- **XORD-022 / 022-A..F:** another session is busy on navigation restructuring.
- **XORD-007 POS Back Office bulk categories:** needs `management_menu_pane.dart`, which the XORD-005 session is editing. Sequence it after that session ends; needs a batch method on `CatalogAdminRepository` (all-or-nothing, audited, row-keyed errors).
- **XORD-002:** the remaining unticked criteria are policy decisions (drive-thru entitlement, order-time check, POS Home buttons), not missing code.
- **Vue screens (006, 007, 009, 016, 018):** the open boxes are "not seen in a browser". There is no JS test framework and installing one needs approval; a look in the built-in browser against the local Docker stack would show the screens but, by the tracker's own rule, would not justify a tick.
