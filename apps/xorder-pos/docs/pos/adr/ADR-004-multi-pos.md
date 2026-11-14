# ADR-004 — Multi-POS, live updates and order locking

**Status:** Accepted business rule, with pending lock protocol. Technical design: Proposed (direct
PostgreSQL hardened boundary chosen in the engineering plan).
**Source:** case report ADR-004; evidence `discovery/MULTI_DEVICE.md`.

## Context

Tills share one PostgreSQL over the LAN with no API layer. Parked tickets are last-writer-wins and
loaded once; nothing tells a till that another till changed the floor.

## Decision (accepted rules)

- Primary cashier hosts PostgreSQL; secondary cashiers share it over the LAN.
- **Real-time push** informs tills about ticket/table changes.
- One editor holds a lock on an active ticket for **10 minutes** (renewal/expiry details pending).
- A child that loses LAN/database connectivity **blocks sales** on that child.
- Temporary full outage when the primary fails is **acceptable for the first release** (no failover).

Engineering decision (plan): the multi-till boundary stays **direct PostgreSQL, hardened** — per-till
roles, TLS on by default (ADR-006), `LISTEN/NOTIFY`, lease table. No local API process.

## Current code `[CODE]`

| Fact | Evidence |
|---|---|
| Every till opens its own pool (max 4) straight to PostgreSQL; no HTTP layer, no discovery | `pos_database.dart:273-296`; `MULTI_DEVICE.md` §1 |
| One shared role `pos_till` for all tills; `terminal_id` is client-asserted | `deployment.dart:211`, `providers.dart:2178-2201` |
| Parked tickets: `INSERT … ON CONFLICT (restaurant_id, table_id) DO UPDATE` — **last writer wins**; no version column, no lock | `postgres_parked_tickets.dart:~75-95` |
| Hydrated once at `OpenTicketsController` build; no polling, no `LISTEN/NOTIFY` | `providers.dart:900-925`; grep `LISTEN|NOTIFY|Timer.periodic` |
| Settle deletes whatever is parked on that table, including another till's newer ticket | `postgres_parked_tickets.dart:~110-125`, `providers.dart:970-990` |
| Nothing prevents two tills selling the same table concurrently | `postgres_orders_repository.dart` (no occupancy check) |
| Invoice numbers serialised by `FOR UPDATE` on the sequence row — correct | `postgres_orders_repository.dart:391-440` |
| Stock issue locks the level row `FOR UPDATE`; first-sale race when no row exists (D16) | `postgres_orders_repository.dart:716-830` |
| DB down: sale fails, ticket restored; park returns false; probe pill refreshes only on tap | `payment_screen.dart:175-195`, `providers.dart:933-945, 475-483` |
| No failover, replica or second host setting | `DeploymentConfig` |

## Gaps

- No lock, no row version, no live refresh, no fencing of other tills during a restore (R-23).
- Terminal identity is not tied to the connecting role (ADR-006).
- Pool reconnect semantics after a server restart unverified (R-15); no retry in `runTx`.

## Proposed design (not yet approved)

- **Lease table** `pos_ticket_locks(table_id, terminal_id, staff_id, acquired_at, expires_at)`:
  10-minute lease, renewed by the editing till while the ticket is open, released on park/settle;
  expired leases are reclaimable; **force-release** is permission-gated and audited.
- **Row `version`** on `pos_parked_tickets`; write is `UPDATE … WHERE version = @expected`; mismatch
  is surfaced as "reload, someone else changed this table". Settle deletes by `client_transaction_id`
  only, never by table alone.
- **`LISTEN/NOTIFY`** on a per-restaurant channel for parked-ticket and lock changes; a dedicated
  listening connection per till; events are hints — on reconnect the till reloads from the database.
- **DB-unavailable state** on child tills: a blocking screen driven by a periodic probe; no sale UI
  until the probe succeeds.
- Per-till roles (ADR-006) make `terminal_id` in the lock row trustworthy.

## Acceptance tests

- Two-till race: second editor sees busy state and editor identity; cannot write.
- Row-version protection: stale write refused, no silent overwrite.
- Lock expiry after 10 idle minutes and re-entry by another till; renewal while editing.
- Forced unlock produces an audit row with actor and reason.
- Reconnect after a missed notification shows the authoritative floor.
- No double-settlement of one ticket; one settle does not delete another till's ticket.
- Sales disabled while the database is unreachable; recovery without restart.

## Open questions

- GAPS §5 **Q11** (failover — accepted none), **Q12** (exclusive tables, live refresh — accepted),
  **Q13** (per-till credential — accepted via ADR-006).
- Case report P1: lock fixed vs renewable (proposal: renewable); who may force-release.
- Push mechanism (`LISTEN/NOTIFY` proposed), optional dedicated server for larger sites (not baseline).

## Related roadmap phase

**Phase 3** (after Phase 1 roles). See [`../20-implementation-roadmap.md`](../20-implementation-roadmap.md).
