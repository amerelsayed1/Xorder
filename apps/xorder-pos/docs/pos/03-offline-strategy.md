# 03 — Offline Strategy

**Author:** Agent 1 (Flutter POS Desktop) · **Date:** 2026-08-25

> **The rule this whole document exists to enforce:**
> a transaction the cashier confirmed is durable *before* the UI moves on, and is
> never discarded — not on crash, not on 500, not on a permanent 422, not on
> reinstall-adjacent recovery. The worst permitted outcome is a dead-lettered
> record a supervisor must resolve by hand.

---

## 1. Failure model

What actually happens at a till, in descending order of frequency:

| Mode | Duration | Behaviour required |
|---|---|---|
| Wi-Fi flap | seconds | Invisible. Requests retry; the cashier notices nothing. |
| Router / ISP outage | minutes–hours | Full offline selling. Status indicator turns amber. |
| Backend 5xx / deploy | seconds–minutes | Same as an outage — the network is up but the API is not. Must be distinguished in the log, not in the UI. |
| Token expired | until re-auth | Keeps selling. Sync pauses with an explicit "sign in to sync" state. Queue is retained. |
| App crash / power loss | instant | Nothing in memory survives; everything durable does. Recovery is a normal start. |
| Clock skew | ongoing | Local timestamps are recorded but the server timestamp is authoritative on ack. |

**Explicitly not solved:** a terminal that is offline for longer than the catalog
cache is trustworthy (default 7 days). Past that the app warns loudly on every
sale that it is pricing from a stale catalog. It still sells.

---

## 2. Two-tier state

```
        ┌───────────────── REFERENCE (server-owned, read-only) ───────────────┐
        │  categories · items · option groups · combos · branches · tables    │
        │  tax config · tender types · customers · shortcuts · restaurant     │
        │  Replaced wholesale or incrementally. Never merged. Server wins.    │
        └────────────────────────────────────────────────────────────────────┘

        ┌───────────────── TRANSACTIONAL (client-authored) ───────────────────┐
        │  orders · order rounds · payments · refunds · shifts · cash moves   │
        │  Created locally, queued, acknowledged. Never deleted by sync.      │
        └────────────────────────────────────────────────────────────────────┘
```

Reference data has no conflict resolution because it has no client authorship.
Transactional data has no merge because the client is the sole author of a *new*
record and the server is the sole author of its *identity*.

---

## 3. Local persistence

**SQLite** via `sqflite_common_ffi` (Windows + macOS), file at
`<applicationSupportDirectory>/xorder_pos/pos.db`, WAL enabled.

Schema versioning is an explicit ordered migration list (`lib/core/database/migrations.dart`)
run inside a transaction with `PRAGMA user_version`. No ORM codegen — the schema
is small, hand-audited, and money-critical.

### Tables

**Reference cache** — `categories`, `menu_items`, `option_groups`, `options`,
`menu_item_option_groups`, `branches`, `dining_tables`, `tax_rules`,
`tender_types`, `customers`, `restaurant_config`. Each carries
`synced_at INTEGER` and `payload TEXT` (the raw JSON, so a server field the
client doesn't parse yet is not destroyed by a round-trip).

**Transactional**

```sql
CREATE TABLE pos_orders (
  client_transaction_id TEXT PRIMARY KEY,   -- UUID v4, immutable, forever
  server_id             INTEGER,            -- null until acknowledged
  invoice_number        TEXT,               -- authoritative, from server
  provisional_reference TEXT NOT NULL,      -- e.g. T3-000117, printed when offline
  terminal_id           TEXT NOT NULL,
  shift_id              TEXT NOT NULL,
  branch_id             INTEGER NOT NULL,
  cashier_user_id       INTEGER NOT NULL,
  status                TEXT NOT NULL,      -- draft|held|open|settled|voided
  sync_state            TEXT NOT NULL,      -- local|queued|in_flight|acked|conflict|dead
  order_type            TEXT NOT NULL,
  table_id              INTEGER,
  customer_id           INTEGER,
  currency              TEXT NOT NULL,
  currency_exponent     INTEGER NOT NULL,
  subtotal_minor        INTEGER NOT NULL,   -- every money column is minor units
  discount_minor        INTEGER NOT NULL,
  tax_minor             INTEGER NOT NULL,
  charges_minor         INTEGER NOT NULL,
  rounding_minor        INTEGER NOT NULL,
  total_minor           INTEGER NOT NULL,
  paid_minor            INTEGER NOT NULL,
  priced_offline        INTEGER NOT NULL,   -- 1 = priced from cache (POS-R082)
  catalog_synced_at     INTEGER NOT NULL,   -- how stale the prices were
  created_at            INTEGER NOT NULL,
  payload               TEXT NOT NULL       -- full immutable order envelope
);
CREATE INDEX idx_orders_sync  ON pos_orders(sync_state);
CREATE INDEX idx_orders_shift ON pos_orders(shift_id);

CREATE TABLE pos_order_lines (
  id TEXT PRIMARY KEY, client_transaction_id TEXT NOT NULL,
  round_id TEXT, menu_item_id INTEGER, variant_option_id INTEGER,
  name_snapshot TEXT NOT NULL, quantity INTEGER NOT NULL,
  unit_base_minor INTEGER NOT NULL, modifiers_minor INTEGER NOT NULL,
  discount_minor INTEGER NOT NULL, line_total_minor INTEGER NOT NULL,
  price_override_from_minor INTEGER, override_reason TEXT,
  note TEXT, options_json TEXT NOT NULL,
  FOREIGN KEY (client_transaction_id) REFERENCES pos_orders(client_transaction_id)
);

CREATE TABLE pos_payments (
  client_transaction_id TEXT PRIMARY KEY,   -- its OWN id; also the idempotency key
  order_client_id TEXT NOT NULL, server_id INTEGER,
  tender_code TEXT NOT NULL, amount_minor INTEGER NOT NULL,
  tendered_minor INTEGER, change_minor INTEGER,
  reference TEXT, sync_state TEXT NOT NULL, created_at INTEGER NOT NULL,
  FOREIGN KEY (order_client_id) REFERENCES pos_orders(client_transaction_id)
);

CREATE TABLE pos_shifts (
  client_transaction_id TEXT PRIMARY KEY, server_id INTEGER,
  terminal_id TEXT NOT NULL, branch_id INTEGER NOT NULL,
  opened_by INTEGER NOT NULL, opened_at INTEGER NOT NULL,
  opening_float_minor INTEGER NOT NULL,
  closed_by INTEGER, closed_at INTEGER,
  expected_cash_minor INTEGER, counted_cash_minor INTEGER, variance_minor INTEGER,
  variance_reason TEXT, status TEXT NOT NULL, sync_state TEXT NOT NULL
);

CREATE TABLE pos_cash_movements (
  client_transaction_id TEXT PRIMARY KEY, server_id INTEGER,
  shift_id TEXT NOT NULL, direction TEXT NOT NULL,  -- in|out
  amount_minor INTEGER NOT NULL, reason TEXT NOT NULL, reference TEXT,
  created_by INTEGER NOT NULL, created_at INTEGER NOT NULL, sync_state TEXT NOT NULL
);

CREATE TABLE sync_queue (
  id INTEGER PRIMARY KEY AUTOINCREMENT,     -- causal order within an aggregate
  client_transaction_id TEXT NOT NULL,      -- the idempotency key sent to the server
  aggregate_type TEXT NOT NULL,             -- order|payment|refund|shift|cash_movement
  aggregate_id   TEXT NOT NULL,             -- groups causally-dependent ops
  operation      TEXT NOT NULL,             -- create|update|void
  endpoint       TEXT NOT NULL,
  payload        TEXT NOT NULL,             -- frozen at enqueue; NEVER regenerated
  attempts       INTEGER NOT NULL DEFAULT 0,
  next_attempt_at INTEGER NOT NULL,
  last_error     TEXT,
  last_status    INTEGER,
  state          TEXT NOT NULL,             -- pending|in_flight|done|dead
  created_at     INTEGER NOT NULL
);
CREATE INDEX idx_queue_ready ON sync_queue(state, next_attempt_at);
CREATE INDEX idx_queue_agg   ON sync_queue(aggregate_id, id);
```

**`payload` is frozen at enqueue time and never regenerated.** Regenerating it on
retry from current app state is how a retry silently becomes a *different*
transaction. The row is an immutable intent.

### What is not stored locally

The access token. It lives in the OS secure store
(`flutter_secure_storage` → Keychain / DPAPI). The local DB contains no secret,
so a stolen `.db` file yields business data, not credentials.

---

## 4. `clientTransactionId`

- **UUID v4**, generated on the client at the moment the aggregate is created.
- Primary key locally, idempotency key on the wire (`Idempotency-Key` header
  **and** a body field, so it survives a proxy that strips headers).
- **Never regenerated.** Not on retry, not on app restart, not after a 500, not
  after a timeout with no response — the single case where an idempotency key
  actually earns its keep.
- Every aggregate has its own: an order, each payment, each refund, each shift,
  each cash movement. A split payment of three tenders is three keys under one
  order key.

The server contract that makes this work is `POS-BE-007`: five retries with the
same key must produce exactly one authoritative record, and every retry must
return the **same** response body as the first, including the assigned id and
invoice number — not a 409.

---

## 5. Sync engine

### 5.1 Ordering

Queue rows are processed in `id` order **within an aggregate**, and aggregates run
concurrently up to a small cap (4). A payment cannot be sent before its order —
enforced by both `aggregate_id` grouping and an explicit dependency check.

A failing operation blocks *its own* aggregate's successors and nothing else. One
poisoned order never stops the till from syncing the next fifty.

### 5.2 Triggers

- Connectivity restored
- App start (after DB migration, before the selling screen is interactive)
- Every 30 s while online with a non-empty queue
- Immediately on enqueue when online
- Manual "sync now"
- Shift close (blocking, with progress — the one place the cashier waits)

### 5.3 Backoff

`delay = min(2^attempts × 2s, 5min)` with ±20 % jitter. Jitter matters: a branch
with six tills coming back from one router reboot otherwise stampedes.

### 5.4 Response handling

| Result | Action |
|---|---|
| `2xx` | Bind `server_id` + `invoice_number`, `sync_state = acked`, queue row `done`. |
| `401` | Pause the **whole** queue. `SyncStatus.authRequired`. Nothing is dropped, nothing is retried until re-auth. |
| `403` `subscription_inactive` | Pause the whole queue, surface the tenant-level message. Selling continues. |
| `409` | Treat as a duplicate — fetch the canonical record by `clientTransactionId` and bind it. Never re-send. |
| `422` | **Dead-letter.** A validation failure will not fix itself. Supervisor review. |
| `404` | Dead-letter, with the note that on this backend 404 can also mean "not your tenant" (constraint C-6). |
| `408` `429` `5xx` | Retry with backoff. |
| Timeout / no response | Retry with the **same** key. This is the ambiguous case idempotency exists for. |
| Attempts > 10 | Dead-letter. |

**`dead` is a visible state, never a deletion.** The sync indicator turns red, the
count is shown, and the queue inspector lists each one with its error and payload.

### 5.5 Incremental reference sync

`GET …?updated_since=<iso8601>` returning changed rows plus a `deleted_ids[]`
(`POS-BE-012`). Until that exists, the client does a full catalog pull, which is
acceptable at restaurant catalog sizes (hundreds of items, not millions) and is
what Phase 3 ships.

Cadence: on login, on shift open, every 15 min while online and idle, and on
demand. **Never mid-sale** — a catalog swap while a cart is open is applied to the
*next* cart, not the current one, so prices cannot shift under the cashier's
fingers between "add item" and "checkout".

An item deleted server-side is marked `unavailable` locally rather than removed,
because a held order may still reference it.

### 5.6 Conflict handling

| Conflict | Resolution |
|---|---|
| Client total ≠ server total | Server wins. `sync_state = conflict`, both figures shown, supervisor acknowledges. The local record keeps its original figures for audit (POS-R081). |
| Item price changed during the outage | Server wins. The order was flagged `priced_offline = 1`, so this surfaces as a reviewable variance rather than a silent correction. |
| Item deleted during the outage | Order syncs with the name snapshot preserved. `POS-BE-006` must accept an order line whose `menu_item_id` no longer resolves. |
| Table closed by the dashboard during the outage | Order syncs; the table link is dropped and noted. Money is not held hostage to a floor-plan edit. |
| Shift closed elsewhere | Dead-letter and require supervisor resolution. Two closes on one shift is a real-world discrepancy, not something to auto-resolve. |
| Duplicate on the wire | Impossible to distinguish from the client, which is exactly why `clientTransactionId` is the contract. |

---

## 6. Connectivity detection

Not `connectivity_plus` alone — a laptop joined to a Wi-Fi network with a dead
uplink reports "connected". The truth is a **cheap authenticated probe**:
`GET /api/dashboard/pulse` (already ETag'd and already built for polling).

States: `online` · `degraded` (reachable, erroring) · `offline` · `authRequired`.
Transition to `offline` after 2 consecutive probe failures; back to `online` on 1
success. Probe interval 20 s online, 5 s while offline.

---

## 7. Status UI

Persistent in the shell header, always visible:

```
 ● Online · synced 12s ago                       (green)
 ◐ Syncing 3…                                    (blue, animated)
 ● Offline · 7 pending                           (amber)
 ▲ 2 failed · action needed                      (red)
 ▲ Sign in to sync · 12 pending                  (red)
```

Click → queue inspector: per-row aggregate, age, attempts, last error, and
`Retry` / `Retry all` / (with `pos.void` + reason) `Reverse`.

Additional surfacing:

- Selling screen shows an unobtrusive "offline — prices from cache (2 h old)"
  strip when offline.
- Receipts printed while offline carry a **PROVISIONAL** marker and the
  terminal-scoped reference.
- Closing the app with a non-empty queue warns (POS-R129).
- Shift close blocks on a full sync attempt and reports what is still outstanding
  rather than pretending the day balanced.

---

## 8. What the backend must provide

Summarised here; specified in `docs/coordination/POS_TO_BACKEND.md`.

| ID | Need |
|---|---|
| `POS-BE-006` | Authenticated POS order creation, server-priced from item + option ids. |
| `POS-BE-007` | Idempotency on every POS write: same `clientTransactionId` → one record, identical replayed response. |
| `POS-BE-008` | Per-branch invoice sequence, assigned server-side, distinct from the primary key. |
| `POS-BE-009` | Shifts, cash movements and a terminal registry, all accepting a client-supplied `opened_at` so an offline shift keeps its real time. |
| `POS-BE-012` | `updated_since` incremental catalog sync with tombstones. |
| `POS-BE-011` | A token lifetime story compatible with a till that is offline for hours. |

Until each is `READY`, the corresponding repository runs against its
`Fake` implementation and the sync engine targets an in-memory endpoint. **The
sync engine itself — queue, backoff, dead-letter, status UI — is built and tested
now**, because none of it depends on the endpoint's final shape.
