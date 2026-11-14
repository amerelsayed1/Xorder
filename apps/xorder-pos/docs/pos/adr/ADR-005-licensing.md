# ADR-005 — Offline licensing, device seats and updates

**Status:** Accepted business rule, with pending entitlement details ([BE]). Technical design: Proposed.
**Source:** case report ADR-005; evidence `discovery/LICENSING.md`, `discovery/MULTI_DEVICE.md` §7.

## Context

Licences are Ed25519-signed `.xlic` files verified in-app. Activation is online by key; the file
import path exists in code but has no UI. Seat counting is a wizard-time row count. The local clock is
the only time source.

## Decision (accepted rules)

- One-time purchase grants **perpetual use** of the entitled version(s).
- **Feature updates for one year**, bounded by the purchased **major version**; **critical security
  fixes remain free** beyond the year.
- Licence applies to a **restaurant plus a number of terminals**.
- **Replacing a damaged device requires XOrder support approval.**
- Internet may be used for initial activation; offline mode stays operational without routine sync.
- Updates are installed by a technician. Offline→Cloud upgrade is offered (ADR-008).

## Current code `[CODE]`

| Fact | Evidence |
|---|---|
| Ed25519 detached signature over the payload bytes; compiled-in public key; release build fails closed without the define | `license_verifier.dart:116-147`, `license_keys.dart` |
| Typed key is exchanged online at `POST /api/pos/licence/activate` | `platform_licence_api.dart:74-160` |
| **File import has no UI**; `activate(fileContents:)` reachable only from the bootstrap bundle and tests; controller takes the param but the pane never passes it | `licence_service.dart:140-185`, `setup_controller.dart:1096,1136,1381`, `setup_panes.dart:674` |
| No offline renewal flow; "Check for renewal" re-posts the typed key | `licence_screen.dart:75-105` |
| `max_terminals` checked only in child onboarding by `count(*)` of `pos_terminals`; no DB constraint; counts retired/never-claimed rows forever; no retire path | `setup_controller.dart:1742-1748`, `postgres_site_licence.dart:42-46` |
| `features`, `branch_ids`, `max_offline_days` parsed, **not enforced**; `max_users` UI-only | `LICENSING.md` §1 |
| Fingerprint = SHA-256 of a constant + random installation UUID from `config.json`; copyable | `file_license_store.dart:78-91`, `providers.dart:2123` |
| No clock-rollback protection; online verdict cache (`licence_check.json`) is unsigned and editable, `enforcement: offline` disables online revocation | `online_licence_service.dart:73`, `online_verdict.dart:27-31, 211-216` |
| Enforcement is one gate: opening a shift; `canSell` never read by sales code | `start_screen.dart:67-68,150`; grep `canSell` |
| Non-release builds trust an unsigned `issuer_public_key` in the file | `license_verifier.dart:86,112` |
| CLI issuer cannot set `max_users`, `max_offline_days`, `branch_ids`; production issuer (platform) UNKNOWN | `bin/pos_licence.dart` |

## Gaps

- **`.xlic` file-import UI is still required**: device replacement in an **air-gapped** site has no
  path today (reviewer correction — the file route is not optional).
- No `updates_until` claim; nothing checks update entitlement at all.
- Seat enforcement bypassable by direct INSERT; replaced devices consume seats forever.
- Clock rollback extends expired file licences; verdict cache editable.

## Proposed design (not yet approved)

- **File import UI** in the wizard licence step and `licence_screen.dart` (file picker + paste),
  calling the existing `activateLicence(fileContents:)`.
- New signed claims: `updates_until`, `major_version`, `security_channel`. **Update entitlement is
  checked as `build_date ≤ signed updates_until`** (the build date is compiled in), **not against the
  local clock**; a build newer than `updates_until` refuses to run the licence with a clear message; the
  last entitled build keeps working indefinitely. Security hotfix builds carry a flag honoured by the
  `security_channel` claim.
- **Seats:** `pos_terminals.install_id` (P0-4) + a DB-side constraint or `SECURITY DEFINER`
  registration function that refuses the N+1th active terminal; **retire-terminal** action frees the
  seat (`retired_at`), audited; seat transfer on replacement is a support-approved re-issue **[BE]**.
- **Monotonic clock guard:** persist the last-seen wall time (signed with the verdict cache); a clock
  earlier than last-seen is treated as the last-seen time for licence purposes.
- **Signed verdict cache** replacing editable `licence_check.json`; `enforcement: offline` only
  honoured when signed.
- `canSell` enforced at settle for deny states (today only shift open).

## Acceptance tests

- Signed entitlement checks without trusting mutable local timestamps alone (rollback test).
- Seat transfer audit; direct INSERT past `max_terminals` refused.
- Expired update entitlement does not disable the purchased build; newer build is refused with reason.
- Offline file validation through the UI with no network; garbage file rejected.
- Release/security hotfix policy tests (channel claim).

## Open questions

- GAPS §5 **Q1** (air-gapped — accepted: file import), **Q2** (`max_offline_days`), **Q4**
  (select vs permit), **Q14** (retire frees seat — accepted), **Q21** (issuer and enforced claims),
  **Q22** (tamper strength).
- Case report: final treatment of major updates within the year; fingerprint/anti-copy strategy;
  whether offline **re**-activation after first activation must work in total disconnection;
  entitlement issuance on the Laravel platform **[BE]**.

## Related roadmap phase

**Phase 5** (after P0-4). See [`../20-implementation-roadmap.md`](../20-implementation-roadmap.md).
