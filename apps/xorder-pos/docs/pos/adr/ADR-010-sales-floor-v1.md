# ADR-010 — Sales floor v1 scope: kitchen/KDS, merge/transfer/split, business day, ETA

**Status:** Proposed design (scope fixed in the engineering plan; not in the case report). Product
answers to GAPS §7 Q26–Q30 are recorded as accepted scope decisions; the mechanisms are proposed.
**Source:** engineering plan (Phase 7); evidence `discovery/FEATURE_INVENTORY.md` Part 1,
`discovery/GAPS_AND_OPEN_QUESTIONS.md` §7.

## Context

The case report covers platform concerns only. Four sales-floor capabilities were absent from it yet
decide whether a restaurant can run a dinner service on the POS: kitchen output, table operations, the
business day, and e-invoicing. Delivery is explicitly out of v1.

## Decision (scope)

| Capability | v1 | Notes |
|---|---|---|
| Kitchen ticket / KDS / station routing | **In** | Q26 |
| Table merge / transfer / split-bill | **In** | Q27 (merge/transfer/split) |
| Delivery (driver, zone, fee, status) | **Out** | Q27 (delivery) |
| Business-day auto-open | **In** | Q28 |
| ETA e-invoicing signing + submission in this repo | **In** | Q30; card/wallet terminal integration **out** |

## Current code `[CODE]`

| Fact | Evidence |
|---|---|
| **No kitchen output of any kind:** `sendRound` flips `LineStage` in memory and shows a toast; print queue CHECK allows only `receipt`/`reprint` | `ticket_engine.dart:494`, `sale_screen.dart:496`, `migrations.dart:3191` (`pos_print_jobs.kind`) |
| No persistent open order: `pos_orders` written only at PAID/VOIDED; `DRAFT/OPEN/SENT_TO_KITCHEN/READY/CLOSED/CANCELLED` never written | `FEATURE_INVENTORY.md` §1 headline 1 |
| Merge, transfer, split-bill: zero hits in `lib/`; split *payment* exists | `FEATURE_INVENTORY.md` §2 |
| Parked tickets last-writer-wins, no lock (ADR-004) | `postgres_parked_tickets.dart` |
| **Business day never opened**: `BusinessDayRepository.open` has no caller; day-close "unpaid orders" blocker is always 0 | `postgres_business_day_repository.dart:148`; grep |
| ETA: compile-time flag off; documents built and hash-chained into `pos_eta_receipts`; `markSigned/markAccepted/markRejected` never called; only `UnconfiguredEtaSigner`; no HTTP client; slip QR never populated in production | `eta_filing.dart:34`, `eta_filer.dart:49`, `eta_signer.dart:107`; §13, §17 |
| Refunds/voids do not restock; no BOM (R-SALE-7) | `FEATURE_INVENTORY.md` §3 |

## Gaps

Everything in scope is NOT_IMPLEMENTED or PARTIAL. Merge/transfer need a trustworthy lock (Phase 3).
ETA needs a signing decision (certificate/HSM/SDK) outside this repo's evidence.

## Proposed design (not yet approved)

- **Kitchen / KDS:** extend `pos_print_jobs.kind` CHECK with `'kitchen'` (additive migration);
  `pos_kitchen_stations(id, branch_id, name, printer)` and `pos_categories.station_id`; **send round
  persists** the round's lines to a new `pos_open_orders` / `pos_order_rounds` record (giving the
  persistent open order the schema already anticipates with `SENT_TO_KITCHEN`), writes one kitchen job
  per station; a KDS view (another till in kitchen role) reads jobs via `LISTEN/NOTIFY` and marks
  `READY`. Re-fire and void-after-send are audited. `TicketEngine` stays pure: routing is a repository
  concern driven by category→station.
- **Merge / transfer / split-bill** as `TicketEngine` operations (pure, unit-tested to the minor
  unit): `merge(a, b)` concatenates lines and keeps both table references for the floor; `transfer`
  re-keys the table under the Phase 3 lock; `split` produces N child tickets (by item, by seat, or equal
  shares with half-up remainder assignment) each settled as its own `pos_orders` row sharing a
  `group_id`. Parked-ticket writes go through the version/lock protocol of ADR-004.
- **Business-day auto-open:** `BusinessDayRepository.open` called on first shift open (or first sale)
  for the branch, trading-day boundary from branch settings; day-close blockers then count real open
  orders.
- **ETA:** implement `EtaReceiptSigner` against the chosen method (certificate decision open),
  submission client in `lib/data/eta/`, `EtaReconciler` drives pending → signed → submitted → accepted
  and calls the existing `mark*`; populate `ReceiptData.etaQrPayload`; flag on for the pilot once
  signing exists. Credit notes for refunds already built (`filing_refunds_repository.dart`).
- **[BE]:** kitchen stations and split-bill `group_id` in the order upload contract if the platform
  must see them (Phase 4 contract).

## Acceptance tests

- Send round → one kitchen job per station with the right lines; KDS shows and acknowledges it;
  re-fire/void after send leave audit rows; a seated ticket survives restart with its rounds.
- Engine tests: merge/transfer/split preserve subtotal, discounts, service, tax and total to the
  minor unit across the children; equal split distributes the remainder deterministically.
- Opening a shift with no business day opens one; day-close refuses with real unpaid-order counts.
- ETA receipt moves pending → accepted against a sandbox; QR printed on the slip; flag-off build
  unchanged.

## Open questions

- GAPS §7 **Q26–Q28, Q30** answered as scope above; **Q29** (who authors named discounts and price
  overrides), **Q31** (refunds restock; BOM in v1) remain open.
- ETA signing method and certificate custody; whether the KDS is a POS build in kitchen role or a
  separate device; station assignment for modifiers/combos.

## Related roadmap phase

**Phase 7** (after Phase 3; [BE] half with Phase 4). See
[`../20-implementation-roadmap.md`](../20-implementation-roadmap.md).
