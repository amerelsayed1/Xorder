# ADR-008 — Full Offline-to-Cloud upgrade

**Status:** Accepted business rule, with pending data merge rules ([BE]). Technical design: Proposed.
**Source:** case report ADR-008; evidence `discovery/OPERATING_MODELS.md` Q4, `discovery/DATABASE_AND_SYNC.md` §6.

## Context

An offline restaurant that buys the cloud plan must bring its history. Today the only "switch" is a
terminal reset and a new wizard run, which neither backfills history nor protects the catalogue.

## Decision (accepted rules)

- An **XOrder technician performs the upgrade**.
- **All existing data** is transferred: historical orders, customers, inventory movements,
  financial and audit records, as permitted by the cloud schema.
- **Sales are stopped** during maintenance.
- Migration failures are handled **manually by XOrder support**; no promise of fully automatic rollback.

## Current code `[CODE]`

| Fact | Evidence |
|---|---|
| No in-place plan switch or migration; Reset clears `config.json`, secrets, progress — not the DB or device token | `providers.dart:2061-2094`, `management_terminal_pane.dart:60-102` |
| Offline sales were never enqueued; no backfill exists (`grep -i backfill lib`: schema backfills only) | `OPERATING_MODELS.md` Q4 |
| A cloud claim runs `BootstrapSeeder` with `force:true`, which deletes and rewrites catalogue tables → local product ids replaced | `cloud_provisioning_repository.dart:437-449`, `bootstrap_seeder.dart:530-543` |
| Cloud→offline strands undelivered outbox rows and hides the count (`pendingSyncCount` returns 0 in offline) | `postgres_orders_repository.dart:361-362` |
| Order upload carries no customer reference (R-SALE-6) | `outbox_drain.dart:140-170` |
| Backup/restore tooling exists and can be the "verified full backup" step | ADR-007 |

## Gaps

- No historical-import API on the platform (UNKNOWN); no tenant-scoped ID mapping.
- Catalogue precedence on upgrade undecided (**P0** product question).
- Naive switch is unsafe: the seeder would wipe the local menu referenced by history.

## Proposed design (not yet approved) — migration phases

1. **Preflight / schema inventory:** POS version, migration version, row counts and checksums per
   table; pending ETA receipts; open shifts/days.
2. **Lock writes, close shifts:** maintenance mode on all tills (ADR-004 fence); refuse sales.
3. **Verified full local backup** (ADR-007) kept until accepted cutover.
4. **Cloud tenancy and ID mapping:** create/attach tenant **[BE]**; mapping table
   `pos_migration_map(entity, local_id, cloud_id)` persisted locally.
5. **Import immutable history** through a historical-import API **[BE]** that accepts old dates and
   prices and is idempotent on `(tenant, client_transaction_id)`.
6. **Reconcile** finance, stock, customers, menu: counts and checksums compared and recorded.
7. **Activate cloud mode** and set the outbox baseline (nothing already imported is re-queued).
8. **Verify**, then **reopen sales**.

Built as a technician tool in the POS (`lib/features/admin/` migration pane or a `bin/` tool) on the
backup service and the Phase 4 contract. The original local DB stays recoverable until the technician
accepts the cutover; **never two live writers**.

## Acceptance tests

- Test migrations on realistic large datasets; dry-run reconciliation reports.
- Sale/payment/inventory totals and count parity between source and cloud.
- Receipts/attachments audit where applicable.
- Failure injection mid-import: original DB live, cloud inert, rerun idempotent.
- Cutover rollback rehearsal.

## Open questions

- GAPS §5 **Q3** (in-place switching — accepted: technician-managed with downtime; unsent/historical
  handling), **Q5** (authority — ADR-002).
- Case report **P0**: does the offline catalogue become the initial cloud catalogue, or does an
  existing cloud catalogue win? **P1**: cloud customer/staff source of truth. Open: manual support
  recovery workflow; proof of full reconciliation; backend import APIs and constraints **[BE]**.

## Related roadmap phase

**Phase 8** (last; after Phases 2, 4, 5). See [`../20-implementation-roadmap.md`](../20-implementation-roadmap.md).
