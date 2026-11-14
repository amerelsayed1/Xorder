# REVISION — Online, Dashboard-Managed POS Licensing

**Status:** DESIGN / PROPOSED — not implemented. Spec only.
**Owner decision:** move licence management into Super Admin; the POS does an
**online licence check on the splash screen at every launch**, against a
server-side record (issue / suspend / renew / expire). Keep the offline
Ed25519-signed file **only** for the *islanded* deployment (a till that never
reaches a server). Add a short offline **grace window** (cache the last good
check ~72h) so a brief outage never bricks a connected till.

This document is additive to the shipped POS-BE-015 machinery. It does **not**
edit the existing coordination files (`BACKEND_TO_POS.md`, `POS_TO_BACKEND.md`,
`BACKOFFICE_TO_CLOUD.md`); it proposes the delta they will later absorb.

---

## 0. Where we are today (verified in code)

| Concern | Today | File |
|---|---|---|
| Licence record | `pos_licences`, one row per issued licence, cross-tenant (no `RestaurantScope`) | `apps/api/app/Models/PosLicence.php` |
| How the till trusts it | Ed25519-signed file verified **offline** with a public key compiled into the binary | `xorder-pos/lib/features/licensing/domain/license_verifier.dart` |
| Signing key | `LICENCE_SIGNING_KEY` (64-byte libsodium secret) **on the server**; public half in the POS binary | `apps/api/config/licence.php`, `LicenceKeygen.php` |
| Issue / renew / revoke | Super Admin, `LicenceIssuer` mints once at issuance, artifact stored verbatim | `apps/api/app/Services/LicenceIssuer.php` |
| Tenant-creation coupling | `RestaurantProvisioningService::provision()` mints a licence **in the same DB transaction** — this is what forces `LICENCE_SIGNING_KEY` on every server that can create a tenant | `apps/api/app/Services/RestaurantProvisioningService.php:139` |
| Till → server today | `POST /api/pos/licence/activate` (unauth, key = credential), `GET /api/pos/licence/current` (device token, returns the **signed file**), `POST /api/pos/terminals/heartbeat` (reports `licence_expires_at`) | `apps/api/app/Http/Controllers/Pos/LicenceController.php`, `routes/api.php:725-761` |
| Terminal identity | `pos_terminals` row (device token `xdt_…`, `device_token_hash`, `deployment_mode`, `fingerprint`, `last_seen_at`, `reported_licence_expires_at`); auth via `PosDeviceAuth` (`pos.device` middleware) | `apps/api/app/Models/PosTerminal.php`, `app/Http/Middleware/PosDeviceAuth.php` |
| POS deployment modes | Collapsed to **`cloud`** and **`offline`**; `max_offline_days` is the islanded check-in window | `xorder-pos/lib/core/config/deployment.dart`, `docs/pos/08-deployment-modes.md` |
| Splash gate | `StartScreen` re-reads `licenceEntitlementProvider` on every arrival; the licence gates **opening a shift only**, never mid-service, never cash-up | `xorder-pos/lib/features/start/start_screen.dart` |
| Client states | `LicenseState { valid, expiringSoon, inGrace, expired, notYetValid, missing, invalid, tenantMismatch, modeNotLicensed, terminalNotLicensed }` | `xorder-pos/lib/features/licensing/domain/license.dart` |

### Terminology reconciliation (owner's words → code)

The owner decision says *"connected modes (cloud, branch-server)"* vs
*"islanded (a till with no server ever)"*. The codebase collapsed
`branch_server`/`standalone` into `offline` + `DeploymentConfig.databaseHost`.
This spec uses one axis, **enforcement**, orthogonal to `deployment_mode`:

| This spec | = | `deployment_mode` | Licence enforcement |
|---|---|---|---|
| **Connected** | cloud till, or a branch-server till that can still phone the platform | `cloud`, or `offline` reachable | **Online check** (this revision) |
| **Islanded** | a till (or a branch box) that will never reach the platform | `offline` + declared islanded | **Offline signed file** (unchanged POS-BE-015 path) |

`deployment_mode` decides *where sales live*; **enforcement decides where the
licence verdict comes from**, and it is the new switch this revision adds.

---

## 1. Data model

Everything below is **additive-only** — the production DB is live and every
existing `pos_licences` row is a valid signed cloud licence that must keep its
meaning. No column is dropped, no NOT NULL is added, no existing value changes.

### 1.1 `pos_licences` — new columns

| Column | Type | Default | Meaning |
|---|---|---|---|
| `status` | `string(16)` indexed | `'active'` | **Dashboard-authoritative lifecycle:** `active` \| `suspended` \| `expired`. This is the field the online `/license/check` reads. `suspended` is *reversible* and *instant* (unlike `revoked_at`, which is permanent cleanup). `expired` is a manual force-expire that does not wait for `expires_at`. |
| `enforcement` | `string(16)` indexed | `'online'` | `'online'` (connected — verified by `/license/check`) or `'offline'` (islanded — verified by the signed file). Backfilled per §5. |
| `suspended_at` | `timestamp` nullable | `null` | When `status` moved to `suspended`; cleared on resume. Audit/telemetry only. |
| `suspended_reason` | `string(255)` nullable | `null` | Operator note shown on the till banner and dashboard. |

`status` is authoritative for the **online** path; the existing derived
`PosLicence::state()` (dates + `revoked_at` + `superseded_by_id`) stays as the
display/derivation helper and as the **only** signal the offline/islanded path
has. The two can legitimately disagree while an islanded till is out of contact
— that asymmetry is the whole point of keeping status server-side for connected
tills.

**Precedence** when computing the effective verdict (server side):
`revoked_at` → `superseded_by_id` → `status=suspended` → `status=expired` →
date arithmetic (`state()`: pending / expired / in_grace / expiring_soon /
active). Revocation and supersession still win; `status` sits above the date
math so an operator can suspend or force-expire a licence that is still "in
date".

### 1.2 `pos_terminals` — new columns (per-terminal binding + telemetry)

| Column | Type | Default | Meaning |
|---|---|---|---|
| `licence_id` | `foreignId` nullable, `nullOnDelete` | `null` | The licence this terminal is bound to. Set on first successful `/license/check` (or activation), so the dashboard can show status **per terminal**, not just per restaurant. Resolved today implicitly by `restaurant_id` + `live()`; this makes it explicit and queryable. |
| `last_licence_check_at` | `timestamp` nullable | `null` | Last successful online check. Powers "last seen a valid licence" in the fleet view and detects tills stuck on a stale grace cache. |

`fingerprint` and `reported_licence_expires_at` already exist on the terminal —
reused, not duplicated.

### 1.3 Migrations (each additive, one concern)

```
2026_09_2x_000100_add_status_to_pos_licences_table.php
  add: status (string16, default 'active', index), suspended_at, suspended_reason
2026_09_2x_000200_add_enforcement_to_pos_licences_table.php
  add: enforcement (string16, default 'online', index)
  data backfill (same migration or a follow-up command): set enforcement='offline'
    WHERE kind='offline' AND max_offline_days IS NOT NULL   (islanded)
    else 'online'                                            (§5 rules)
2026_09_2x_000300_add_licence_binding_to_pos_terminals_table.php
  add: licence_id (nullable FK -> pos_licences, nullOnDelete), last_licence_check_at
```

Postgres applies each as a catalogue update (no rewrite worth the name); SQLite
in dev rebuilds the table, which is why the constraint-free additions are kept
separate from any `->change()`. No `down()` restores a NOT NULL or drops data
that a sold entitlement depends on — the same discipline as the existing
`add_offline_licences` migration.

---

## 2. Super Admin dashboard

Screens live under `apps/web/src/pages/admin/pos/`, alongside the already-built
`LicencesList.vue`, `LicenceForm.vue`, `LicenceDetails.vue`,
`OfflineLicenceForm.vue`, `ClientKindChoice.vue`. This revision **extends** those
rather than replacing them; the issue/renew/offline flows already exist. Follow
the existing admin conventions (`AdminLayout.vue`, capability-gated actions,
axios via `packages/api-client`, bilingual labels).

### 2.1 Screens / flows

| Screen | Route (existing pattern) | What changes for this revision |
|---|---|---|
| **Licences list** | `admin/pos` → `LicencesList.vue` | Add a **Status** column driven by the new `status` field + derived `state`, and a status filter (`active` / `suspended` / `expired`). Add per-row **Suspend / Resume** action (instant). Keep existing search, `kind`, `live_only`, `expiring_within_days` filters. |
| **Issue** | `LicenceForm.vue` (cloud) / `OfflineLicenceForm.vue` (islanded) | Add an **Enforcement** choice: *Online-managed* (connected — the new default) vs *Signed file (islanded)*. Selecting islanded reveals `max_offline_days`; online hides it. |
| **Licence detail** | `LicenceDetails.vue` | Show `status`, `suspended_reason`, decoded claims (already shown), **and a per-terminal table**: each `pos_terminal` bound to this licence with `last_seen_at`, `last_licence_check_at`, `reported_licence_expires_at`, `deployment_mode`, revoked flag. This is the "status per restaurant/terminal" view. |
| **Suspend / Resume** | `POST …/licences/{id}/suspend`, `POST …/licences/{id}/resume` | Instant, reversible. A confirm dialog states plainly: *takes effect the next time each till checks in (grace window up to 72h for a connected till already open; immediate for a till launching now)*. |
| **Renew** | `LicenceForm` renew mode → existing `POST …/licences/{id}/renew` | Unchanged. Writes a new row, supersedes the old, reuses the key unless `rotate_key`. On the online path the till simply reads the new verdict at next check — no file to re-import. |
| **Force expire** | `POST …/licences/{id}/expire` | Sets `status='expired'` without waiting for `expires_at`. Distinct from **Revoke** (permanent, `revoked_at`) and **Delete** (cleanup of an already-dead row). |

### 2.2 API surface for the dashboard (all under `can:licences.manage`, SUPER_ADMIN via `Gate::before`)

New endpoints beside the existing `AdminLicenceController` actions
(`routes/api.php` `admin/pos/licences` group):

```
POST   /api/admin/pos/licences/{licence}/suspend   { reason?:string }   -> 200 PosLicenceResource
POST   /api/admin/pos/licences/{licence}/resume                          -> 200 PosLicenceResource
POST   /api/admin/pos/licences/{licence}/expire     { reason?:string }   -> 200 PosLicenceResource
GET    /api/admin/pos/licences/{licence}/terminals                       -> 200 [PosTerminalResource]  (per-terminal status)
```

`PosLicenceResource` gains `status`, `enforcement`, `suspended_at`,
`suspended_reason`. `suspend`/`resume`/`expire` audit via `AuditLogger`
(`pos_licence.suspended` / `.resumed` / `.expired`), mirroring the existing
`.issued` / `.renewed` / `.revoked` events.

---

## 3. The POS `/license/check` API contract

**This is the new online verdict endpoint.** It replaces `GET
/api/pos/licence/current` (which returns the signed *file*) for connected tills.
`current` and `activate` stay for the islanded/file path (§5).

### 3.1 Request

```
POST /api/pos/license/check
Authorization: Bearer xdt_<device-token>          # the DEVICE credential
Content-Type: application/json
Accept: application/json

{
  "fingerprint":     "<sha256 hex of machine id>",   # already computed by TerminalFingerprint
  "deployment_mode": "cloud" | "offline",            # this till's mode
  "app_version":     "1.4.0",                         # telemetry, optional
  "licence_expires_at": "2026-12-31T00:00:00+00:00"  # what the till currently believes, optional
}
```

- **Auth:** `pos.device:no-feature` middleware — the same device token used by
  the heartbeat. Restaurant is resolved from the terminal (`pos_terminal`
  attribute), **never** from request input, so there is no `restaurant_id` /
  `tenant_slug` in the body. No-feature mode on purpose: a till whose `feature:pos`
  lapsed must still be told *why* it cannot sell.
- **`fingerprint`** is verified against the licence's `fingerprints[]` (if
  non-empty) and recorded on the terminal.
- Throttled `throttle:60,1` (per token), matching `/current`.

### 3.2 Response (200)

```jsonc
{
  "status":       "valid",              // enum below — the SINGLE source of truth for the till
  "licence_ref":  "LIC-2026-0042",
  "expires_at":   "2026-12-31T00:00:00+00:00",   // null when lifetime
  "lifetime":     false,
  "grace_days":   14,                   // server's expiry-grace (distinct from the offline cache window)
  "warn_days":    30,
  "max_terminals": 2,
  "max_users":     null,
  "features":     ["pos"],
  "message":      null,                 // human string for suspended/expired (e.g. suspended_reason)
  "server_time":  "2026-09-27T10:00:00+00:00",   // clock-skew reference, as heartbeat already sends
  "grace_policy": { "cache_seconds": 259200 }    // 72h — how long the till may trust THIS answer offline
}
```

### 3.3 `status` enum (server-computed effective verdict)

| `status` | Server condition | Till reaction |
|---|---|---|
| `valid` | live, in date, not suspended | Launch normally |
| `expiring_soon` | valid but within `warn_days` | Launch + renewal banner |
| `in_grace` | past `expires_at`, within `grace_days` | Launch, warn; config changes gated (matches §2 of `09-licensing.md`) |
| `expired` | past grace, **or** `status='expired'` set in dashboard | **Blocks the *next* shift**, never the open one |
| `suspended` | `status='suspended'` in dashboard | Blocks new shift; `message` carries the reason |
| `unknown` | licence row exists but cannot be evaluated (should not happen) | Treat as the cached verdict; do not block on it alone |

**HTTP status codes / error bodies:**

| Case | HTTP | Body `{code}` | Till reaction |
|---|---|---|---|
| Found & evaluated | 200 | (status in payload) | per table above |
| No live licence for this tenant | 404 | `licence_not_found` | Block new shift; banner "no licence" |
| Device token invalid | 401 | `DEVICE_TOKEN_INVALID` | Re-pair (existing behaviour) |
| Terminal revoked | 403 | `TERMINAL_REVOKED` | "terminal orphaned" banner (existing `terminalRejectedProvider`) |
| Throttled | 429 | `TOO_MANY_ATTEMPTS` | Fall back to grace cache silently |

### 3.4 Offline / unreachable behaviour (the grace window)

The endpoint itself does nothing offline — the *client* does. When the POST
throws (timeout, DNS, no route) or returns 5xx, the till uses its **cached last
successful `/license/check` verdict** if that cache is younger than
`grace_policy.cache_seconds` (default **72h / 259200s**). See §4.3.

`/license/check` is **read-only and idempotent**; it also opportunistically
writes telemetry (`pos_terminals.last_licence_check_at`, `licence_id`,
`fingerprint`, `reported_licence_expires_at`) with `saveQuietly()`, exactly as
the heartbeat does — never an audited edit.

---

## 4. POS splash-check flow

### 4.1 When it runs

- **Every launch**, on the splash → `StartScreen` transition, before a shift can
  be opened. `StartScreen.initState` already invalidates
  `licenceEntitlementProvider` on every arrival; the online check hangs off that
  provider for a **connected** terminal.
- Again **before each new shift opens** (the existing `_start()` gate reads
  `licence.canOpenShift`). A renewal or suspend applied minutes ago is therefore
  visible without a restart.
- The check is **non-blocking on the UI**: the splash renders immediately; a
  slow or missing verdict is *treated as permitted* (`StartScreen` already does
  this — "a slow read must not look like a lapsed licence").

### 4.2 What blocks launch vs. warns (unchanged cardinal rule)

The verdict maps onto the **existing** `LicenseEntitlement` gate. No new
blocking shape is introduced — this preserves `docs/pos/09-licensing.md` §2:

| `status` | New shift | Sell in open shift | Config change | Cash-up · reprint · export |
|---|---|---|---|---|
| `valid` / `expiring_soon` | Yes | Yes | Yes | **Always** |
| `in_grace` | Yes | Yes | No | **Always** |
| `expired` | **No** | Yes | No | **Always** |
| `suspended` / `licence_not_found` | **No** | Yes (open shift finishes) | No | **Always** |

**Never brick a till mid-service.** A verdict of `expired`/`suspended`/`404`
arriving while a shift is open stops only the *next* shift. `canCashUp`,
`canReprint`, `canExportData` remain hard-coded `true`.

### 4.3 The grace-window cache rule (connected tills)

```
on splash / before-shift, for a CONNECTED terminal:
  verdict = await POST /license/check   (timeout ~10s)
  if verdict is a 200:
      store { verdict, checkedAt = now } in local cache (bootstrap.json, NOT the signed file)
      entitlement = fromStatus(verdict.status)
  else if network/5xx/timeout:
      if cache exists AND now - cache.checkedAt <= grace_policy.cache_seconds (72h):
          entitlement = fromStatus(cache.verdict.status)   # trust last good answer
          show subtle "working offline, licence last confirmed <t>" pill
      else:
          # outage longer than the grace window
          entitlement = valid-but-degraded: allow the OPEN shift, BLOCK a new shift,
          banner "cannot confirm licence — reconnect to open a new shift"
  else if 401/403:
      existing re-pair / terminal-rejected handling
```

- The cache lives in `bootstrap.json` (per POS-BE-027's "last platform contact"
  precedent) — **never** in `config.json` (which gates boot and must not be
  rewritten hourly) and **never** as a signed file (connected tills stop keeping
  one).
- `cache_seconds` is server-driven (`grace_policy.cache_seconds`) so the window
  can be tuned per fleet without shipping a build; the client clamps it to a
  sane max (e.g. 7 days) so a hostile/buggy value cannot grant forever.
- A wrong system clock is handled as today: `server_time` is compared to local
  time; large skew produces the honest "check the terminal's date and time"
  rather than a false expiry.

### 4.4 Islanded fallback (signed-file path kept ONLY here)

A terminal whose licence is `enforcement='offline'` (islanded) **does not call
`/license/check`**. It keeps the entire shipped POS-BE-015 path:

- Verifies the Ed25519-signed `.xlic` file offline against the embedded public
  key (`LicenseVerifier`).
- Renewal is by re-imported file or forced `activate` inside the
  `max_offline_days` window — unchanged.
- All ten offline `LicenseState` cases stay live for this path only.

The client picks the path from its own configuration (deployment mode +
enforcement flag delivered at activation/bootstrap), so a single binary serves
both. Connected is the default; islanded is the exception a customer is
explicitly sold.

---

## 5. Migration & back-compat

### 5.1 Decouple tenant creation from signing

Today `RestaurantProvisioningService::provision()` mints a signed licence inside
the tenant-creation transaction (`:139`), which is the sole reason every
tenant-creating server needs `LICENCE_SIGNING_KEY`.

**Change:** creating a tenant issues an **online-managed** licence row —
`enforcement='online'`, `status='active'` — **without signing**. Concretely:

- Add a `LicenceIssuer::issueOnline($restaurant, $data, $actor)` path that
  writes the row (term, features, modes, caps) but **skips `seal()`/`mint()`**:
  `payload`/`signature` stay empty (`''`, which the schema already allows) and
  `key_id` is left at its default. The online verdict is computed from columns,
  not from a signed artifact, so no signing key is touched.
- `RestaurantProvisioningService` calls `issueOnline` instead of `issue`. Tenant
  creation no longer requires `LICENCE_SIGNING_KEY` — a server that only creates
  cloud tenants can run without it.
- **Existing tenants are unaffected:** their rows already carry a valid
  `payload`/`signature`. The backfill sets `enforcement='online'` for them; the
  online path ignores the signature and reads columns, so the stale artifact is
  simply unused (kept for audit / possible islanded re-issue).

### 5.2 Backfill rules (data migration / one-off command)

| Existing row | `enforcement` | `status` |
|---|---|---|
| `kind='cloud'` | `online` | `active` if `state()` ∈ {active, expiring_soon, in_grace}; `expired` if past grace; unchanged if `revoked_at`/`superseded_by_id` set |
| `kind='offline'` **with** `max_offline_days` | `offline` (islanded) | derived from dates as today |
| `kind='offline'` **without** `max_offline_days` | `online` (treat as connected offline-mode till) | as above |

No signed file is regenerated; no key is read during backfill.

### 5.3 What happens to `LICENCE_SIGNING_KEY`

- **Retained, but demoted to islanded-only.** It is required *only* when issuing
  or renewing an `enforcement='offline'` (islanded) licence — i.e. inside
  `LicenceIssuer::seal()/mint()`, which is the only caller of `signingKey()`.
- The connected/online path (`issueOnline`, `/license/check`, renew of an online
  licence) never calls it. `signingKey()` already throws loudly when unset —
  that failure now surfaces **only** on the islanded issue path, which is the
  correct place for it.
- The POS binary keeps the embedded **public** key for the islanded path; the
  rotation rule (`config/licence.php` `key_id`: ship the new public key in a POS
  release *before* signing anything with it) is likewise now an islanded-only
  concern.
- Existing endpoints `POST /api/pos/licence/activate` and `GET
  /api/pos/licence/current` stay for the islanded/file path and for
  back-compat with tills not yet upgraded to `/license/check`.

---

## 6. Security notes

| Threat | Assessment | Mitigation |
|---|---|---|
| **Revocation latency** | Online suspend/revoke bites at the *next* check (immediate for a launching till; up to the 72h grace window for a till already open). This is *far* better than the offline signed file, which can never be recalled and relies on `max_offline_days`. | Keep the grace window short (72h default, server-tunable). For an urgent kill, revoking the **device token** (`pos_terminals` revoke → 403 `TERMINAL_REVOKED`) stops all writes immediately, independent of the licence cache. |
| **Replay / tamper of the online check** | The verdict travels over TLS on an authenticated (`xdt_` device token) channel; the response is not signed, so a MITM on a compromised network could forge a `valid`. | TLS is mandatory (production is HTTPS). The verdict is *commercial hygiene, not security* — real enforcement stays server-side on `feature:pos` at every money write (`PosDeviceAuth` feature gate), which a forged splash verdict cannot bypass. Optionally add an HMAC over the verdict keyed by a per-terminal secret if the threat model tightens (deferred). |
| **Terminal spoofing** | An attacker with a stolen `xdt_` token could pull a `valid` verdict for that tenant. | The token is hashed at rest, rotated (`ROTATION_OVERLAP_HOURS`), single-till, and revocable; a stolen token is the existing POS-BE-011 threat, not a new one. `fingerprint` is cross-checked against `fingerprints[]` when the licence pins machines. Terminal binding (`pos_terminals.licence_id`) makes an anomalous new terminal visible in the fleet view. |
| **Grace-cache abuse** | A user could pull the network to freeze a `valid` verdict. | The cache only *extends* a previously-granted verdict for ≤72h and never upgrades a bad one to good; after the window a new shift is blocked. The clamp on `cache_seconds` stops a tampered response granting forever. |
| **Clock manipulation** | Rolling the clock back to dodge expiry. | `server_time` skew check on every online verdict; the authoritative expiry lives server-side, not on the till, so a local clock change does not move it. |

Bottom line, unchanged from `09-licensing.md`: **the till gate is commercial
hygiene.** The online model materially improves revocation latency and removes
the "signed file can never be recalled" hole for the vast majority of tills,
while real enforcement remains the server-side `feature:pos` entitlement on
every write.

---

## 7. Phased rollout

**Phase 0 — Schema (additive, safe on live prod).**
Ship the three additive migrations (§1.3) + backfill. `status` defaults
`active`, `enforcement` defaults `online`. Nothing reads them yet. Extend
`PosLicenceResource` with the new fields. Green on `release-check`
(additive-only, no NOT NULL, no data loss).

**Phase 1 — Dashboard.**
Add Suspend/Resume/Expire endpoints + audit events, the per-terminal
(`/licences/{id}/terminals`) view, and the `apps/web` list/detail/form changes
(§2). Operators can now manage online licences even though no till reads the new
endpoint yet.

**Phase 2 — `/license/check` endpoint.**
Ship `POST /api/pos/license/check` behind `pos.device:no-feature` (§3). Keep
`current`/`activate` untouched. Add feature tests mirroring `PosLicenceTest` /
`OfflineLicenceTest`.

**Phase 3 — POS online path + grace cache.**
POS calls `/license/check` on splash + before-shift for connected terminals,
caches the verdict in `bootstrap.json` with the 72h window (§4). Islanded
terminals keep the signed-file path. Ship behind a client config flag; dogfood
on internal tills first.

**Phase 4 — Decouple tenant creation from signing.**
Switch `RestaurantProvisioningService` to `LicenceIssuer::issueOnline` (§5.1).
New tenants get unsigned online licences; `LICENCE_SIGNING_KEY` becomes
islanded-only. Verify a server with no signing key can create tenants (add a
test that asserts no `signingKey()` call on the cloud provision path).

**Phase 5 — Cleanup / hardening.**
Tune `cache_seconds` from fleet telemetry, add the optional verdict HMAC if
warranted, and document the islanded-only status of `LICENCE_SIGNING_KEY` in
`config/licence.php` and `09-licensing.md` (follow-up, not this doc).

Each phase is independently shippable and reversible up to Phase 4 (which
changes provisioning behaviour); Phases 0–3 leave the offline path fully intact.
