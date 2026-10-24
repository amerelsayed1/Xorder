# ADR-007 — Backups and disaster recovery

**Status:** Accepted business rule, with pending off-box policy. Technical design: Proposed.
**Source:** case report ADR-007; evidence `discovery/DATABASE_AND_SYNC.md` §8, `discovery/SECURITY_AND_RECOVERY.md` §10, §12.5.

## Context

`pg_dump -Fc` runs at day close or by hand, to the same disk as the database, verified by
`pg_restore --list` and a read-through. Restore blocks only on an open shift or business day and takes
no safety copy.

## Decision (accepted rules)

- Backup **every day and at day close**; keep the **last 14 days**.
- Primary local backup stays on the same computer; **an external backup destination is configured and
  verified during installation**.
- **Only an XOrder technician can run a restore.**
- Cloud plan: **block restore while unsynced transactions exist** until resolved. Offline plan: show
  the impact warning (newer local records lost) and require technician confirmation.
- Backup failures are visible locally to technician/support; **no unsolicited cloud telemetry** in the
  offline plan.

## Current code `[CODE]`

| Fact | Evidence |
|---|---|
| `pg_dump --format=custom` as read-only `pos_backup`; `.part` then rename; SHA-256; `pg_restore --list` + read-back; row in append-only `pos_backups` | `pg_archive.dart:157-220`, `backup_service.dart:123-132, 254-283` |
| **No scheduler**; automatic copy only inside the day-close dialog | `day_close_dialog.dart:55-76`; dialog comment "a restaurant that never closes its day never gets a copy" |
| Default folder on the **same disk** as the database; manual `copyTo` USB with checksum | `backup_service.dart:654-689, 531-561` |
| Retention newest 14 `.dump`, pruned only after a restorable new copy | `backup_service.dart:49, 285-298` |
| Restore guard: `backup.manage` + open shift / open business day only; **ignores the outbox** (D3); blockers branch-scoped but restore is database-wide | `backup_service.dart:345-402, 424-480`; R-06 |
| **No pre-restore snapshot**; `pg_restore --clean --single-transaction` | `pg_archive.dart:230-262`; grep `pre-restore|snapshot`: none |
| Restore does not fence other LAN tills (R-23) | `providers.dart:3134-3138` |
| Backups unencrypted; contain PIN hashes and customer data; not `secrets.json` | §10 |
| Cloud tills: Backup pane absent from `CloudBackOfficeScreen` | `cloud_back_office_screen.dart` grep |
| No `--data-checksums`, no WAL archiving/PITR (R-16) | `provision.ps1:141-144` |

## Gaps

- Daily schedule, external destination step, outbox-aware restore, pre-restore snapshot all missing.
- **Restore deadlock in cloud plan:** a hard block on pending outbox rows with no procedure means a
  damaged database can never be restored while sales are unsent — the exact P0 question in the case
  report.
- "Technician-only" is unenforceable while `pos_admin` is in `secrets.json` (ADR-006).

## Proposed design (not yet approved)

- **Scheduler:** daily timer in `BackupService` (configurable hour) plus day-close; on launch, if the
  last verified copy is older than 24 h, take one (missed-day catch-up).
- **External destination:** wizard step that requires a path (USB/NAS), writes a test file, checksums
  it and refuses to finish setup otherwise; later unavailability shows a persistent local warning and
  retries when it returns. Whether copies continue automatically is **open** (case report P1).
- **Restore deadlock resolution (proposed):** before any restore,
  1. take a **pre-restore snapshot** (`BackupService.backUp`, label `pre-restore`; failure aborts),
  2. **extract** unsent/held outbox rows and any orders (with lines, payments, refunds, shifts, cash
     movements) newer than the backup being restored into a sidecar file,
  3. run the restore,
  4. **replay** the extracted rows into the restored database (idempotent on
     `client_transaction_id`; invoice numbers re-issued where they collide and the mapping recorded),
     then let the drain upload them.
  In cloud mode the hard block stays for the ordinary path; this replay path is the technician
  escalation. In offline mode the extract/replay is offered as the default with a confirmation showing
  the exact lost window. Builds on P0-2.
- Fence other tills during restore (ADR-004 `NOTIFY` + lock table).
- Encryption: age/`pgcrypto`-style file encryption with technician-held key — **design only** until
  key custody is decided.
- Record backup failures in `pos_backups` (exists) and a technician view; offline plan never
  phones home.

## Acceptance tests

- Schedule tests including missed days and a restaurant that never closes a day.
- Restore rehearsal on an isolated DB; integrity checks; retention after many day-closes in 14 days.
- **No outbox loss:** pending rows exist after restore+replay and drain afterwards.
- External destination permission/disk-space errors surface and do not delete the last known-good copy.
- Recovery time / recovery point measured and recorded.

## Open questions

- GAPS §5 **Q15** (off-box mandatory — accepted; automatic vs technician export open), **Q16**
  (restore with unsent sales — accepted: block/warn).
- Case report: encryption and key custody; retention if 14 days contains several day-close copies;
  exceptional restore with pending outbox (**P0** — the proposal above); support notification without
  internet.

## Related roadmap phase

**P0-2** then **Phase 2**. See [`../20-implementation-roadmap.md`](../20-implementation-roadmap.md).
