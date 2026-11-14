# ADR-003 — Cloud synchronisation, queue and observability

**Status:** Accepted business rule, with pending contracts ([BE]). Technical design: Proposed.
**Source:** case report ADR-003; evidence `discovery/DATABASE_AND_SYNC.md` §5, §9, §10.

## Context

The outbox pattern is in place and transactional, but the drain trusts any 2xx, has no release path for
held rows, never uploads voids or stock, and runs on a 30-minute/4-hour cadence.

## Decision (accepted rules)

- Periodic sync **every 5 minutes** while connected; reconnection policy to be specified.
- Upload **all operational transaction types**: sales, payments, refunds, cash movements, shifts,
  stock movements, purchasing, voids where relevant.
- **Persist and review rejected operations**; never delete them.
- Error diagnostics and manual repair are **accessible to XOrder support only**. Whether a
  non-technical sync-status indicator is shown to the restaurant manager is **open** (case report P0).

## Current code `[CODE]`

| Fact | Evidence |
|---|---|
| Two queues: `pos_outbox` (orders), `pos_sync_outbox` (customer, shift open/close, cash movement, refund); rows never deleted | migrations 4, 6, 49; `outbox_drain.dart` |
| Idempotency key = `client_transaction_id` (body + header); payment keys UUIDv5 | `outbox_drain.dart:105-111`, `cloud_api.dart:243-254` |
| Cadence 4 h settled / 30 min otherwise; first pass 5 s after boot; kick after each settle | `cloud_sync.dart:72-82`, `outbox_drain.dart:1181-1220` |
| **2xx with non-JSON body → `{}` → marked delivered with null server ids (D4)** | `cloud_api.dart:256-270`, `outbox_drain.dart:372-426` |
| Six codes quarantine (`VALIDATION_FAILED`, `IDEMPOTENCY_PAYLOAD_MISMATCH`, `MENU_ITEM_NOT_FOUND`, `BRANCH_NOT_IN_TENANT`, `CUSTOMER_NOT_FOUND`, `REFUND_EXCEEDS_SOLD`); everything else defers forever; **no release path** | `outbox_drain.dart:119-131`; grep `quarantined_at = NULL`: none |
| Quarantined rows counted as pending forever (D8) | `postgres_orders_repository.dart:360-384`, `cloud_sync.dart:228-239` |
| No per-row lease, backoff or attempt cap; crash mid-send re-sends the same key (D5) | `outbox_drain.dart:307-456` |
| Voids written as `status='VOIDED'`, **not enqueued** (D12) | `postgres_orders_repository.dart:317-319` |
| Stock movements, PO receipts, supplier invoices: no queue, no endpoint | `DATABASE_AND_SYNC.md` §5.1 |
| Drain exception can stop the auto-reschedule timer (R-AVAIL-3, unverified) | `providers.dart:728-733` |
| Two main tills on one DB would both drain all rows (no terminal filter, no `SKIP LOCKED`) (D6) | `outbox_drain.dart:309-321` |
| Child-till sales are uploaded under the main device's token; order body has no terminal field | `outbox_drain.dart:140-170` |

## Gaps

- Strict acknowledgement missing (P0-1). Release/visibility missing (P0-3).
- **Stock-movement parity is blocked on inventory scope:** only `sale`, `receipt`, `opening` movements
  exist; no BOM, stocktake, waste or adjustment writers; refunds and voids do not restock
  (`FEATURE_INVENTORY.md` §3, R-SALE-7). Uploading what exists is possible; "parity" is not definable yet.
- Backend idempotency, re-pricing and error codes UNKNOWN.
- No log file, crash handler or support bundle for diagnostics (ADR-006 open items).

## Proposed design (not yet approved)

- `SyncSchedule`: 5-minute cadence when connected; immediate pass on connectivity change
  (`connectivity_plus` is already a dependency) and after each settle (exists).
- Strict ack parser (P0-1); per-record `attempts`-based backoff with a cap that moves the row to a
  **held** state with a code instead of retrying forever.
- Support-only "Held sync items" view with release/replay (P0-3), audited; manager-facing indicator
  limited to a count/age if Q8 is answered yes.
- New upload kinds in `pos_sync_outbox`: `order_void`, `stock_movement`, `purchase_receipt`
  (event id, product id, quantities, origin terminal, timestamp, schema version) **[BE]** endpoints.
- `SELECT … FOR UPDATE SKIP LOCKED` on the drain query so two drains cannot send the same row.
- Try/catch around the drain so the timer chain cannot die.
- No raw credentials or payment secrets in logs (already true in release; keep).

## Acceptance tests

- Offline → online transition drains within 5 minutes in deterministic phase order.
- Crash after send, before local ack → no duplicate (server idempotency) **[BE]**.
- 4xx / 409 / 422 / 5xx matrix: every outcome is either delivered, deferred with backoff, or held
  with a code; nothing is permanently invisible.
- 200 + HTML/empty body is **not** acknowledged (P0-1).
- Child-till sale is visible to the main worker and drains when the main device returns.
- Stock movement upload carries event id and dedupes on rerun **[BE]**.

## Open questions

- GAPS §5 **Q7** (voids/stock sync; inventory owner), **Q8** (who clears held rows; what the
  manager sees — case report P0), **Q9** (server behaviour — [BE]), **Q10** (several cloud tills on
  one DB), §7 **Q31** (refunds restock; BOM in v1).
- Reconnection trigger timing; recovery owner and credentials for support repair; ordering
  dependencies in the backend contract.

## Related roadmap phase

**P0-1, P0-3** then **Phase 4** (contract, cadence, voids/stock upload). See
[`../20-implementation-roadmap.md`](../20-implementation-roadmap.md).
