# Backend — POS Offline / Sync Proposal

# STATUS: PROPOSED — OWNER APPROVAL REQUIRED

**Author:** Agent 2 (Backend) · **Mode:** ANALYSIS-ONLY · **Date:** 2026-08-26
**Requirements covered:** POS-BE-006, POS-BE-007, POS-BE-008, POS-BE-009, POS-BE-012

> Nothing here exists in `apps/api` today. Verified: no idempotency key, no
> client-supplied identifier, no delta parameter, no dedupe mechanism anywhere.

---

## 1. The one rule everything else serves

> **If the POS retries an order five times with the same `client_transaction_id`,
> the backend creates exactly ONE authoritative order — and all five calls return
> the same 2xx body, including the same `id` and the same `invoice_number`.**

Agent 1 stated this precisely and the reasoning is worth preserving verbatim,
because it is the part implementations usually get wrong:

> A replay must **not** return `409`. The single case idempotency exists for is a
> request that timed out with no response, where the client cannot know whether
> the first attempt succeeded. A `409` on replay leaves that client with no way to
> learn the record's id — which is precisely the state the key was meant to prevent.

**Accepted without modification.** Every design choice below follows from it.

---

## 2. `clientTransactionId` — transport, storage, lifetime

| Aspect | Proposal |
|---|---|
| Format | UUID v4, generated on the terminal at the moment the user commits (not at sync time) |
| Transport | Body field `client_transaction_id` **and** header `Idempotency-Key`. Body is authoritative; the header is belt-and-braces because a proxy may strip it. If both are present and differ → `422`. |
| Storage | A real column on each POS aggregate — **not** a side table of request hashes |
| Uniqueness | `UNIQUE (restaurant_id, client_transaction_id)` per aggregate table |
| Lifetime | **Permanent.** It is part of the financial record's identity, not a cache entry. A till that has been in a drawer for six months and finally reconnects must still deduplicate. |
| Scope | Tenant-scoped, per Agent 1's request — two tenants may legitimately collide (astronomically unlikely, but the index should not be what discovers it) |

**Why a column, not a request-hash table:** a hash table answers "have I seen this
request?" The column answers "does this record already exist?" — which is the
question that actually matters, survives replay with a slightly different payload
(a client that retried after a clock adjustment), and needs no expiry policy.

---

## 3. The write path, precisely

Pseudocode for `POST /api/pos/orders`. Every POS write follows this shape.

```
BEGIN TRANSACTION
  existing = Order::where('client_transaction_id', $uuid)->lockForUpdate()->first()
  if existing:
      COMMIT
      return 200 with the SAME body the original returned      ← replay path
  validate + authorize (capabilities for discount/override)
  reprice every line from menu_item_id + option ids
  compare against asserted_totals → set totals_mismatch
  lock TableVisit / open Order  (dine-in only, existing discipline)
  invoice_number = InvoiceSequence::next(restaurant, branch, period)   ← inside the lock
  INSERT order + order_items + order_payments
COMMIT
AuditLogger::record('pos.order_created', …)
notify via app()->terminating()
return 201
```

**Three details that matter**

1. **The uniqueness check is inside the transaction and takes a row lock.** A
   `SELECT … then INSERT` outside a transaction races two concurrent retries into
   two orders. The unique index is the backstop; the lock is the mechanism.
2. **The invoice number is drawn after the replay check.** A replay must not
   consume a sequence value — that is how you get gaps in a legal sequence.
3. **The response body is reconstructed from the persisted record on replay**,
   not cached. Cached bodies go stale; the record is the truth.

**Concurrent-duplicate race:** two retries arriving genuinely simultaneously will
have one lose on the unique index. Catch the integrity violation, re-read by
`client_transaction_id`, and return the winner's body. **A `UniqueConstraintViolation`
on this column is a success path, not an error path.** This must be tested explicitly.

---

## 4. Batch sync — `POST /api/pos/sync/batch`

A till reconnecting after a four-hour outage has a queue: shift open, 40 orders,
3 cash movements, 2 refunds, a customer, shift close.

**Design rules**

1. **Max 100 operations per call.** The client paginates its own queue.
2. **Per-operation results, never all-or-nothing.**
   ```jsonc
   { "results": [
       { "client_transaction_id": "…", "status": "created",   "data": { … } },
       { "client_transaction_id": "…", "status": "duplicate", "data": { … } },
       { "client_transaction_id": "…", "status": "failed",
         "error": { "code": "menu_item_not_found", "message": "…", "retryable": false } }
   ]}
   ```
3. **One failure never blocks the rest.** Each operation is its own transaction.
   A batch-wide rollback on operation 7 discards six successful, real, paid
   transactions — the exact outcome the queue exists to prevent.
4. **Dependency order is resolved server-side**, not by trusting array order:
   `shift_open → customer → order → refund → cash_movement → shift_close`.
   A client whose queue is out of order still syncs correctly.
5. **`retryable` is explicit on every failure.** The client must be able to tell
   "the network hiccuped, try again" from "this item was deleted, escalate to a
   human". Guessing from an HTTP status is not good enough for money.
6. **Nothing is ever silently discarded.** An operation the server cannot accept
   comes back `failed` with a reason, and stays in the client's queue in an error
   state for a human to resolve.

---

## 5. Server acknowledgment and the client's contract

On a `created` or `duplicate` result the client may mark its local record synced —
**and only then.** The acknowledgment carries the server `id`, the authoritative
`invoice_number`, and `received_at`, which the client binds back to the local row.

Specifically for invoice numbers (POS-BE-008): the till prints a **provisional**,
terminal-scoped reference while offline (`T3-000117`) and marks the receipt
provisional. The authoritative number arrives on sync. **The server never honours a
client-proposed invoice number** — that would guarantee collisions across tills.
Agent 1 explicitly does not ask for this; recorded so it stays decided.

---

## 6. Backdated and out-of-order writes

| Field | Source | Rule |
|---|---|---|
| `created_at` / `occurred_at` / `opened_at` / `closed_at` | **client** | Authoritative. An order rung at 14:02 and synced at 18:40 is a 14:02 order. |
| `received_at` | server | Always `now()`. Never client-settable. |
| `updated_at` | server | Laravel default |

**Guards**

- Reject client times **> 24h in the future** → `422`. A till with a badly wrong
  clock would otherwise poison reporting, and a future-dated sale is never valid.
- Accept arbitrarily old times. A queue held for days is a support problem, not a
  data-integrity one, and rejecting it destroys the record.
- **Reporting reads `created_at`; sync-lag diagnostics read `received_at − created_at`.**
  Both must exist or the owner cannot tell "quiet Tuesday" from "till was offline".
- Shift totals are computed from orders whose `created_at` falls inside the shift
  window — **not** from arrival order.

---

## 7. Incremental catalog sync (POS-BE-012)

```
GET /api/pos/catalog?updated_since=2026-08-26T09:00:00Z
→ { data: { categories, items, option_groups },
    deleted: { categories: [id…], items: [id…], option_groups: [] },
    synced_at: "…", complete: true }
```

- Changed rows: `where('updated_at', '>', $since)`.
- Tombstones: `menu_items` and `categories` already use `SoftDeletes`, so
  `onlyTrashed()->where('deleted_at','>',$since)` gives deletions **with no new
  table** — Agent 1 spotted this correctly.
- **`option_groups` and `options` do NOT use `SoftDeletes`** (BE-A03). A deleted
  option group leaves no trace, so a delta sync cannot report it and the till would
  keep offering a removed modifier. Until `SoftDeletes` is added there, the response
  sets `complete: false` and the client falls back to a full pull for groups.
  **This is a correctness caveat, not an optimisation detail — it must not be
  quietly dropped.**
- `synced_at` is the **server's** clock, echoed back on the next call. The client
  never sends its own clock as the watermark — that is how records get skipped
  across a clock skew.
- Watermark is taken **before** the query runs, not after, so a row written during
  the query is re-sent next time rather than missed.

---

## 8. Conflict handling

A POS is append-only at the till, so true write-write conflicts are rare. The four
real cases:

| Conflict | Server behaviour | Client behaviour |
|---|---|---|
| **Price changed during the outage** | Re-price authoritatively; return `totals_mismatch: true` with both figures | Raise the reconciliation dialog (POS-R081). The customer already paid the printed amount. |
| **Menu item deleted during the outage** | Accept the line via `name_snapshot` + asserted price; `menu_item_id = null`; `warnings[]` entry | Show the order as synced-with-warnings |
| **Two tills, same table** | Existing `lockForUpdate()` on `TableVisit` serialises them; second joins the open order | Refresh the ticket |
| **Shift already closed server-side** | `failed`, `retryable: false`, explicit error code | Surface to a manager; never discard |

**Governing principle: the server is authoritative about *money owed*; the client
is authoritative about *what happened*.** The server may correct a total, and must
never refuse a record of a transaction that already occurred.

---

## 9. Token expiry mid-queue (POS-BE-011)

The failure Agent 1 names — a till holding real paid transactions, meeting a `401` —
is the worst state in the system.

**Recommended (Option A, per `02`):** a longer POS token TTL via a dedicated config
value, issued when the login carries a `terminal_id`. Cheap, no new surface.
**Sync-side hardening regardless of which option is chosen:**

- A `401` on a sync batch **never** clears the queue.
- The POS enters "sign in to sync", **keeps selling**, and drains after re-auth.
- After re-authentication the queue replays with the **same** `client_transaction_id`s,
  so any operation that did land before the `401` returns `duplicate` rather than
  double-charging.

This is precisely why idempotency keys are generated at commit time, not sync time.

---

## 10. Test obligations for the approved work

CI gates deploys on `apps/api` tests, so these are not optional extras:

1. Five identical submissions → one order, five identical bodies, one invoice number.
2. Two genuinely concurrent submissions → unique-violation caught → one order, both callers get the winner's body.
3. Replay after price change → same body as the original, **not** re-priced.
4. Batch with one poison operation → 99 succeed, 1 returns `failed`.
5. Batch in scrambled dependency order → resolves correctly.
6. Backdated order → `created_at` preserved, `received_at` = now.
7. Client time 48h in the future → `422`.
8. `updated_since` watermark → no row skipped across the boundary.
9. Deleted menu item mid-outage → line accepted with warning, never dropped.
10. Cross-tenant `client_transaction_id` collision → two separate orders, no leak.

---

> **BACKEND IMPLEMENTATION HAS NOT STARTED. OWNER APPROVAL IS REQUIRED.**
