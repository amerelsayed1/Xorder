# ADR-001 — Operating models and deployment

**Status:** Accepted business rule (product owner, 2026-10-25). Technical design: Proposed where marked.
**Source:** `XORDER_ARCHITECTURE_CASE_REPORT.md` ADR-001; evidence `discovery/OPERATING_MODELS.md`,
`discovery/MULTI_DEVICE.md`. All code claims are `[CODE]` (read, not run).

## Context

One POS product must serve a subscription **Cloud** plan that keeps selling offline, and a one-time
**Offline-Only** plan with no operational cloud sync. Target customers are small and medium restaurants
and cafés. Older documents (including `CLAUDE.md` until this change) described three modes
(cloud / branch-server / islanded); the code has two.

## Decision (accepted rules)

- **Plan A `cloud`:** local PostgreSQL receives every sale first; an outbox uploads operating
  transactions; the cloud owns menu and settings; offline sales continue while the internet is absent.
- **Plan B `offline`:** menu, staff, inventory, reporting and cash management are local; no
  operational cloud synchronisation. Internet is permitted for first activation.
- The **primary cashier PC hosts PostgreSQL**; additional tills connect over the restaurant LAN. If the
  primary or its database is unavailable, a temporary outage is accepted (no failover in first release).
- A **technician installs and provisions**. The licence governs permitted plan(s) and device count.

## Current code `[CODE]`

| Fact | Evidence |
|---|---|
| `DeploymentMode` has exactly two values, `cloud` and `offline`; legacy wire strings `branch_server`/`standalone` parse to `offline`; "islanded" appears only in a comment | `lib/core/config/deployment.dart:10-57` |
| Sales commit to local PostgreSQL first, with the outbox row in the same transaction (cloud only) | `lib/data/postgres/postgres_orders_repository.dart:73-193, 337-340` |
| Cloud sync runs only on the main cloud terminal; children get no cloud client | `lib/app/providers.dart:655-664, 688-755` |
| Offline mode enqueues nothing and `OutboxDrain.run` returns immediately | `deployment.dart:67`, `outbox_drain.dart:277` |
| Licence `modes[]` restricts which wizard tiles are offered and vetoes opening a shift; the chosen mode lives in `config.json` | `setup_state.dart:166-169`, `setup_controller.dart:311-353`, `license_verifier.dart:227-232` |
| Unconfigured / unknown mode value reads as `cloud` | `deployment.dart:164, 411-414` |
| No local fallback store on child tills; DB down = no sale, ticket restored to pre-tender state | `payment_screen.dart:175-195`, `MULTI_DEVICE.md` §4 |
| No in-place plan switch; only Reset + wizard | `providers.dart:2061-2094`, `management_terminal_pane.dart:60-102` |
| `requiresPeriodicCheckIn` and `max_offline_days` are declared/parsed but never read | `providers.dart:735-752`; `license.dart:126,168` |

## Gaps

- Cloud backend behaviour unverified (every `/api/pos/*` call is client-side only).
- Plan conversion unsupported (ADR-008); device seat enforcement partial (ADR-005).
- No LAN failover or discovery (accepted for first release; discovery is open).
- Unknown mode silently becomes `cloud` — should be "unconfigured", not a default plan.
- Stale docs claiming three modes (`CLAUDE.md` corrected alongside this ADR; `docs/pos/08-deployment-modes.md` still historical).

## Proposed design (not yet approved)

- Treat an unknown/absent `deployment.mode` as **unconfigured** (wizard), never as `cloud`.
- Mode-specific test matrix in `test/` asserting: no cloud client built in `offline`; no outbox rows
  written in `offline`; cloud main device builds the client, children never do.
- Keep the two-value `DeploymentMode`; do not reintroduce a "branch" value — a branch server is
  `offline` (or `cloud`) with a LAN `databaseHost`.

## Acceptance tests

- Mode-specific API calls and outbox creation (cloud writes rows; offline writes none).
- Sell during an internet outage in cloud mode; rows drain after reconnect.
- No cloud traffic in offline operational mode (only licence activation).
- Primary outage inhibits writes on every till with a clear state; no pretend recording.
- Seat registration idempotency (P0-4) and mode claim enforcement at shift open.

## Open questions

- GAPS §5 **Q2** (`max_offline_days` in A? in B?), **Q4** (licence selects vs permits a plan),
  **Q6** (cloud tills have no in-app back office — intended?), **Q10** (several cloud tills on one DB),
  **Q11** (failover/acceptable downtime — accepted: none yet).
- Exact installer-vs-wizard responsibilities for PostgreSQL; DB restart/reconnect behaviour
  (`pos_database.dart` has no retry in `runTx`); device discovery feasibility.

## Related roadmap phase

Cross-cutting; mode tests land with **P0** and **Phase 1**; discovery/failover are not scheduled.
See [`../20-implementation-roadmap.md`](../20-implementation-roadmap.md).
