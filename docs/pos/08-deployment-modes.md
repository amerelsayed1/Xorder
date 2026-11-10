# POS Deployment Modes — cloud and offline

> **Superseded in part, 2026-11-08 (pos-split-apps, owner decision D0).** The
> recommendation below — one product, the mode a configuration choice — is
> replaced by **one codebase, two apps**: "XOrder POS - Cloud"
> (`apps/xorder_pos_cloud`) and "XOrder POS - Offline"
> (`apps/xorder_pos_offline`), sharing `packages/shared_module`. Each app runs
> one mode, fixed in its `main`; a licence covers one mode. What still holds:
> one schema, one API contract, no forked business rules (§3). The design is
> `docs/features/pos-split-apps/` in the workspace.

**Status:** implemented in the client · **Backend packaging is `PROPOSED`** (POS-BE-017)
**Code:** `lib/core/config/deployment.dart`
**Question this answers:** can XOrder POS run entirely on-premises?

---

## 1. Recommendation

**Yes — but not as a separate product.** On-premises is a *configuration choice*,
not a second codebase.

| Mode | Shape | Sold to |
|---|---|---|
| **Cloud** | Local PostgreSQL on the till, synced to the hosted platform. Outages absorbed by the local database and the outbound queue. | Default. Most tenants. |
| **Offline** | PostgreSQL is the source of truth. Sales never leave the building; only the licence goes out. | Poor connectivity, or a customer who will not put sales in the cloud. |

There used to be three. `branch_server` and `standalone` were **the same mode
with the database in a different place** — one on a LAN box, one on the till —
and modelling that difference as a mode meant every consumer had to know about a
distinction that only ever changed one string. It is now
`DeploymentConfig.databaseHost`, and the licence's `max_terminals` decides which
of the two an operator may choose.

**Every mode is offline-first, and every mode has a local PostgreSQL.** There is
no online-required variant: a desktop till always has a disk, so refusing to sell
without a connection would buy the restaurant nothing. What varies is *whether
sales leave the building at all* — `syncsSalesToPlatform` — and, for cloud, *when
the queue drains*, which is `SyncPolicy.automatic` or `manual`.

**Every mode is tracked from Super Admin.** That is an owner requirement
(POS-BE-022). A cloud till is continuously visible because it writes there; an
offline till is visible when it renews its licence, and its licence carries the
window inside which it must. Missing that window blocks the *next* shift rather
than the open one.

## 2. What the mode actually decides

Not "where is my data" — that is always a local or LAN PostgreSQL. The mode
answers exactly one question: **is there a platform to send money to?**

| | Cloud | Offline |
|---|---|---|
| Local PostgreSQL | ✅ | ✅ |
| `databaseHost` | `localhost` | `localhost`, or a LAN address if `max_terminals > 1` |
| Sends sales upstream | ✅ | ❌ |
| Reaches the platform for its licence | ✅ | ✅ |
| `SyncPolicy` offered | ✅ | ❌ — nothing to drain |
| Visible in Super Admin | Continuously | On each licence check-in |

## 3. Why this shape rather than a fork

`apps/api` already ships everything a shared branch box needs:

- `docker-compose.yml` — `app` + `scheduler` + `web` + `postgres:16-alpine`
- `config/database.php` defaults to **SQLite** with **pgsql** alongside, so the
  same Eloquent code runs on either
- `RestaurantScope` isolates tenants structurally; a branch box simply holds one
- `Dockerfile` and `deploy.sh` already exist for the hosted product

**A branch box is therefore packaging, not new engineering.**

## 4. The honest reason to put the database on a shared box

Not "offline support" — the local database and queue already provide that.

> A per-terminal database solves **single-till** outages. It does **not** solve
> **multi-till consistency** during one.

Two tills with separate databases can both seat table 12, and both sell the last
portion of a dish. Nothing on the client can prevent that, because neither till
can see the other. One shared PostgreSQL is the answer to that specific problem.

**If a restaurant has one till, a shared box buys them nothing** — which is why
the wizard does not offer the choice at all on a one-terminal plan. Say so, rather
than selling a box they will then have to look after.

## 5. Where it costs you

Recorded so nobody is surprised after the first ten installs.

- **The QR menu needs a public URL.** It is XOrder's core product. A restaurant
  with no internet has no menu for diners to scan. The realistic split is
  on-premises *POS* plus cloud *menu* — not an air-gapped site.
- **You own uptime on every box.** Fifty restaurants is fifty servers to update,
  back up and support. They will call you, not their IT supplier.
- **Backups are the real risk.** A mini-PC under the counter with no backup is how
  a restaurant loses a year of sales. The wizard says this out loud on any
  single-machine install: *"there is no second copy."*
- **E-invoicing — confirmed, and the answer is favourable.** Egypt's ETA
  e-receipt mandate permits **store-and-forward within 24 hours**; it does not
  require real-time clearance the way Saudi ZATCA Phase 2 does for B2B. A till
  that sells through an outage and submits when the line returns is compliant,
  which is exactly the machine this document describes. The worry recorded here
  — *"an offline-only till cannot"* — was wrong for Egypt.
  **What is still missing is the submission itself**: e-seal signing, the ETA
  format, the QR code on the slip and a queue with its own retry. None of it is
  built. See [15-competitive-position.md](15-competitive-position.md).

## 6. Client implementation

`DeploymentConfig` carries `mode`, `baseUrl`, `tenantSlug`, `verifyTls`,
`syncPolicy` and `databaseHost`. Chosen in the setup wizard, then read by
everything that needs to know whether a platform exists to talk to.

**The licence step now runs *before* the connection step**, and the order is
load-bearing in two directions:

- the licence carries `tenant_slug`, so it **supplies** the tenant the account
  step signs into rather than being checked against one the terminal guessed;
- it carries `modes` and `max_terminals`, so the connection step offers only what
  the customer bought — instead of accepting a choice and rejecting it two
  screens later.

Activation therefore cannot depend on `baseUrl`, which does not exist yet. It
goes to `PlatformEndpoint.licenceActivation` — a **build constant**, deliberately
not device config, because an operator being able to point licence activation at
their own machine would defeat the one check that must not be configurable. The
other path is importing a signed `.xlic` file, and it is the only one that works
with no internet at all.

Four rules worth knowing:

**`hostFor()` never reads the mode.** Every terminal has a database; only its
address varies. A null means *not set up yet*, not *cloud*.

**`requiresPeriodicCheckIn`** is true only for offline. `max_offline_days` on the
licence is the mechanism (POS-BE-022).

**TLS can only be relaxed on a private database host.** A LAN box often has no
certificate, so the wizard offers to trust it — but `allowsInsecureTransport`
returns false for any public host, so a mistyped hostname cannot silently put the
till on plaintext. `isPrivateHost` checks RFC 1918 ranges plus loopback and
`.local`.

**`ConnectivityProbe` asks "can I reach *my* platform", not "is there internet".**
In offline mode it has nothing to reach and says so; what has to answer there is
PostgreSQL, and `PosDatabase.probe` is what asks it.

> ### Amendment — 2026-08-28: a site role, and a bootstrap step
>
> Neither mode changes. Two things are added around them; full design in
> `docs/pos/10-setup-architecture.md`.
>
> **A site role, which is not a third mode.** `TerminalRole.mainDevice` /
> `clientTerminal` records *which box runs the site's PostgreSQL* — the same
> distinction §1 collapsed `branch_server` and `standalone` for, kept out of the
> mode where it belongs. The role is chosen inside the existing `deployment`
> step, gated on `max_terminals > 1`, and on a one-terminal plan it is never
> asked. The rule in §6 holds unchanged: **`hostFor()` still never reads the
> mode**, and now it does not read the role either.
>
> What the role actually decides is narrow and worth stating plainly, because it
> is tempting to invent a tier here and there is not one: who runs the migrations
> at install, who touches the `pos_admin` credential, who mints `server_id`, and
> **who owns the backups** — which is the main device's real second job, and the
> risk §5 already names as the biggest one on an offline site. Both roles sell.
>
> **Check-in stays per terminal.** A main device does *not* check in on behalf of
> its site; that would make a dead client terminal invisible, and POS-BE-022
> exists to require per-terminal `last_seen_at`. What the site may share is
> `pos_branches.last_platform_contact_at`, so `max_offline_days` is judged
> against `max(local, site)` and a client is not blocked because only the
> manager's PC has an uplink.
>
> **A bootstrap step.** The wizard gains `SetupStep.bootstrap` between `licence`
> and `deployment`, which downloads the tenant's configuration and turns the
> deployment step into a confirmation with one blank field — the password. It
> **never blocks**: a terminal being installed with no internet degrades to the
> wizard described above. The ordering rule in §6 is therefore extended rather
> than replaced — the licence constrains the deployment step first, the bundle
> fills it second, and operator edits win over both.
>
> **`max_offline_days` is the outstanding piece of `requiresPeriodicCheckIn`**
> and is requested as POS-BE-027; §8's table gains POS-BE-025 … POS-BE-028.

## 7. Migration from the three-mode model

The old wire values are **still parsed**, and must stay that way:

| Old wire value | Parses to |
|---|---|
| `branch_server` | `offline`, with `databaseHost` recovered from the old `base_url` |
| `standalone` | `offline`, with `databaseHost` = `localhost` |
| `cloud` | `cloud`, with `databaseHost` = `localhost` |

Two reasons this cannot be dropped. **Already-signed licences carry these strings
in their `modes[]` claim and cannot be re-signed** — a terminal that rejected one
would refuse to sell. And a terminal upgrading in place reads a `config.json`
written by the old build; recovering the database host from `base_url` is what
saves an engineer retyping the LAN address into every till on the site.

Covered by the `legacy wire values` group in `test/features/licensing_test.dart`.

## 8. What the backend would need — none of it approved

| Request | For |
|---|---|
| **POS-BE-015** | Licence issuance and activation endpoints — **`READY`**, now called by `PlatformLicenceApi` |
| **POS-BE-016** | Terminal registration against a licence, so `max_terminals` is enforced somewhere real |
| **POS-BE-017** | Branch-box packaging: single-tenant provisioning, seed, backup, update path, licence distribution to tills |
| **POS-BE-018** | Upstream sync — local → cloud, reusing the idempotency contract of POS-BE-007 |
| **POS-BE-025** | Pre-auth tenant setup config by slug, with a monotonic `config_version` |
| **POS-BE-026** | Site registration and `ServerId` — the fleet registry gains a site tier |
| **POS-BE-027** | `max_offline_days`, `server_id`, `license_version` on the licence — this is the mechanism `requiresPeriodicCheckIn` has been waiting for |
| **POS-BE-028** | Terminal display-name update, so renaming a till never re-registers it |

**POS-BE-018 has half a client.** The local outbox exists: migration 4 adds
`pos_outbox`, and a cloud sale claims a row in it **inside the same transaction
that writes the order** — one commit or neither, because an outbox row lost to a
crash between two commits is money the platform never hears about. `SyncPill`
reads the real backlog from that table, so it survives a restart.

What does not exist is the **drain**, and it cannot until POS-BE-007 is `READY`:
the queue deliberately stores no payload, only a reference to the order and the
`client_transaction_id` that is the idempotency key. Snapshotting a wire format
nobody has approved would mean rewriting every queued row when the real one
lands. `syncPolicy` therefore remains stored configuration that nothing reads at
runtime.

`pos_till` already holds `SELECT, INSERT, UPDATE` on the table (`bin/pos_migrate.dart`)
so that landing the drain is not also a database migration on every site.

## 9. Recommended commercial position

Keep **cloud** the default. Sell **offline** to places with genuinely bad
connectivity or a policy against cloud-held sales, priced to cover the support you
are taking on. The one-till-versus-many decision is the plan's job, not a
conversation: `max_terminals` already decides it, and the wizard follows.
