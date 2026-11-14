# ADR-002 — Data ownership and conflicts

**Status:** Accepted business rule, with pending per-entity rules (customers, staff). Technical design:
Proposed where marked.
**Source:** case report ADR-002; evidence `discovery/DATABASE_AND_SYNC.md` §5–§7, §10.

## Context

"Cloud authoritative" is too broad for immutable financial operations. Authority must be defined per
entity, and the bootstrap re-apply must never cost local money or leave a stale menu.

## Decision (accepted rules)

- In Plan A the **cloud is authoritative for catalogue/menu and centrally managed settings**.
- **Sales, tenders, refunds and audit events originate locally** and must never be discarded
  automatically because of a disagreement.
- Plan B is **local-authoritative for all operating data**.

| Entity | Authority | Conflict handling to formalise |
|---|---|---|
| Menu, categories, modifiers, prices | Cloud in A; local in B | Versioned snapshots; preserve references used by historical orders |
| Device/branch operational settings | Cloud in A where centrally managed | Define which settings stay device-local (e.g. printer port) |
| Sale / payment / refund | Local event accepted before upload | Immutable ids, idempotent ingestion, explicit reconciliation on rejection |
| Stock movements | Local source events; cloud projection in A | Dedupe by event id; reconcile ordering and product mapping |
| Customers | **Not decided** | Owner, matching, dedupe rules |
| Staff / permissions | **Not decided** for A | Central vs local authority; offline login behaviour |

## Current code `[CODE]`

| Fact | Evidence |
|---|---|
| Bootstrap seeder never touches `pos_orders`, `pos_order_*`, `pos_outbox`, `pos_sync_outbox`, `pos_shifts`, `pos_stock_*`; whole apply is one transaction | `lib/data/cloud/bootstrap_seeder.dart:53-104` |
| **Cloud already wins for staff, customers and tenders today:** staff upserted by platform id incl. PIN hash/capabilities (absent → `is_active=false`); tenders upserted by `(restaurant_id, platform_id)`, others retired; customers upserted by phone | `bootstrap_seeder.dart:459-507` (staff), `:329-413` (tenders), `:429-457` (customers) |
| **Catalogue is delete-and-reinsert:** `DELETE` all products/categories/modifiers/tables for the restaurant, then re-insert platform rows | `bootstrap_seeder.dart:509-646, 648-676` |
| `DELETE FROM pos_products` is blocked by `pos_stock_movements.product_id … ON DELETE RESTRICT` and `pos_combo_options` RESTRICT; the seed transaction rolls back and the failure is **swallowed** → stale menu indefinitely (D9) | `migrations.dart:2620, 1909`; `cloud_sync.dart:162-177` |
| `pos_stock_levels` CASCADE-deleted on product delete (D10) | `migrations.dart:2678` |
| Order lines carry `name_snapshot`, `unit_price_minor`, `menu_item_id` with **no FK** to `pos_products`; payments have no FK to tenders — history survives replacement | `migrations.dart:77-92, 100-110` |
| Server re-prices uploads (`priced_offline:true`, `asserted_totals`); `totals_mismatch` is written and **read nowhere** (D14) | `outbox_drain.dart:139-218, 397-399` |
| No transactional conflict resolution; rejections only classified by `code` | `outbox_drain.dart:119-131` |
| No cloud order pull, no stock sync in either direction | `cloud_api.dart` path grep; `bootstrap_bundle.dart` |

## Gaps

- Catalogue reseed can fail silently on stocked products (D9) and can silently drop stock levels (D10).
- `totals_mismatch` has no reader; no reconciliation view.
- Customer and staff authority undecided, although the seeder already behaves as "cloud wins".
- Staff upsert on a cloud till means the `pos_till` role can write `pos_staff` (see ADR-006 R-09).
- Customer created at the counter is upserted and enqueued in **two statements**, not one transaction (D11, `postgres_customers_repository.dart:85-143`).

## Proposed design (not yet approved)

- **Catalogue: archive, never delete.** Seeder sets `is_active=false` / `archived_at` on rows missing
  from the bundle and upserts the rest by platform id. No cascade touches stock levels; RESTRICT FKs can
  no longer roll the seed back. Products keep their local id across reseeds.
- Record and surface `totals_mismatch` (role to be decided with GAPS Q8).
- Formalise the matrix above as a signed-off document; implement staff/customer handling as
  "cloud wins, local rows deactivated, never deleted" until decided otherwise (matches today's code).
- Wrap customer upsert + enqueue in one transaction.

## Acceptance tests

- Reseed over a database with stock movements and combos succeeds; historical orders still resolve
  product names and prices; stock levels unchanged.
- No data loss on bootstrap/reseed for orders, outbox, shifts, refunds (test with pending rows — none exists today).
- Server tests for duplicate keys and mismatch responses **[BE]**.
- Reconciliation trace and audit records for every rejected or mismatched upload.

## Open questions

- GAPS §5 **Q5** (per-entity authority; confirm pending sales are never discarded), **Q7** (inventory
  owner in A), **Q9** (server semantics for duplicate/mismatch/unknown items — [BE]).
- Case report P1: staff/customer authority and merge policy; how offline menu merges into Cloud on
  upgrade (ADR-008, P0).

## Related roadmap phase

**Phase 4** (archive-not-delete, `totals_mismatch`, authority matrix). P0-3 provides the release path
for quarantined rows. See [`../20-implementation-roadmap.md`](../20-implementation-roadmap.md).
