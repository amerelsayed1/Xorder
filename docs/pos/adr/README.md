# Architecture decision records — XOrder POS

One file per case in `XORDER_ARCHITECTURE_CASE_REPORT.md` (ADR-001…009) plus ADR-010 for the
sales-floor scope the report did not cover. Each ADR separates the **accepted business rule** (product
owner) from the **proposed design** (engineering, not yet approved) and cites `[CODE]` evidence from
[`../discovery/`](../discovery/README.md) by file:line. Nothing here has been executed.

Phases referenced below are defined in [`../20-implementation-roadmap.md`](../20-implementation-roadmap.md).

| ADR | Title | Status | Roadmap phase |
|---|---|---|---|
| [ADR-001](ADR-001-operating-models.md) | Operating models and deployment (two modes: `cloud` · `offline`) | Accepted | cross-cutting (P0, Phase 1) |
| [ADR-002](ADR-002-data-authority.md) | Data ownership and conflicts (archive-not-delete catalogue; cloud already wins for staff/customers/tenders) | Accepted, entity rules pending | Phase 4 |
| [ADR-003](ADR-003-cloud-sync.md) | Cloud sync, queue, observability (5-min cadence; strict ack; held-row release; stock parity blocked on inventory scope) | Accepted, contracts pending [BE] | P0-1, P0-3, Phase 4 |
| [ADR-004](ADR-004-multi-pos.md) | Multi-POS, live updates, 10-minute ticket lock (direct PostgreSQL hardened) | Accepted, lock protocol pending | Phase 3 |
| [ADR-005](ADR-005-licensing.md) | Offline licensing, seats, updates (`.xlic` import UI; `build_date ≤ updates_until`) | Accepted, entitlement details pending [BE] | Phase 5 |
| [ADR-006](ADR-006-security.md) | Identity, permissions, secrets, LAN TLS (per-till roles; DB-side enforcement; audit tamper + diagnostics open) | Accepted, protocol details pending | Phase 1 |
| [ADR-007](ADR-007-backup-recovery.md) | Backups and recovery (daily + day-close; external destination; snapshot → extract → restore → replay) | Accepted, off-box policy pending | P0-2, Phase 2 |
| [ADR-008](ADR-008-offline-to-cloud-upgrade.md) | Offline→Cloud upgrade (technician migration tool) | Accepted, data merge pending [BE] | Phase 8 |
| [ADR-009](ADR-009-setup-wizard.md) | Technician-led setup UX (Arabic default; Settings → General → Language) | Accepted direction, flow to validate | P0-4, Phase 6 |
| [ADR-010](ADR-010-sales-floor-v1.md) | Sales floor v1: kitchen/KDS, merge/transfer/split, business-day auto-open, ETA; delivery out | Proposed | Phase 7 |

## Conventions

- **Status** values: *Accepted business rule* · *Proposed design* · *Open*. A rule can be accepted while
  its design is still proposed; both are stated per ADR.
- **Sections** in every ADR: Context · Decision · Current code `[CODE]` · Gaps · Proposed design (not
  yet approved) · Acceptance tests · Open questions · Related roadmap phase.
- Open questions cite `discovery/GAPS_AND_OPEN_QUESTIONS.md` §5 (Q1–Q25) and §7 (Q26–Q31) by number,
  plus the case report's P0/P1/P2 table where relevant.
- **[BE]** marks work that needs the `xorder-new` backend repository in a session.
- No secrets are reproduced; no claim that anything ran.
