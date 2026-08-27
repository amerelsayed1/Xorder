# POS Deployment Modes — cloud, branch server, on-premises

**Status:** implemented in the client · **Backend packaging is `PROPOSED`** (POS-BE-017)
**Code:** `lib/core/config/deployment.dart`
**Question this answers:** can XOrder POS run entirely on-premises?

---

## 1. Recommendation

**Yes — but not as a separate product.** On-premises is a *configuration choice*,
not a second codebase.

| Mode | Shape | Sold to |
|---|---|---|
| **Cloud** | Terminals → the hosted platform. Outages absorbed by each terminal's own queue. | Default. Most tenants. |
| **Branch server** | A box in the branch runs the *same* `docker-compose.yml`. Tills → it over the LAN. It **must** sync upstream. | Multi-till sites and poor connectivity. |
| **Islanded** | No server. One till, local database, periodic check-in. | Single-till kiosk, food truck. |

All three speak the same API, over the same contracts, against the same schema.
The only differences are `base_url` and how often the platform hears from the till.

**Every mode is offline-first.** There is no online-required variant: a desktop
till always has a disk, so refusing to sell without a connection would buy the
restaurant nothing. What varies is *when the queue drains* — `SyncPolicy` is
`automatic` or `manual`, and it is a separate question from where the server is.

**Every mode is tracked from Super Admin.** That is an owner requirement
(POS-BE-022), and it is what withdrew two configurations that used to be on
offer: a branch server with no upstream, and a terminal that never contacts the
platform at all. An islanded till still sells offline indefinitely — it just has
to check in within the window its licence grants, and missing that window blocks
the *next* shift rather than the open one.

## 2. Why this shape rather than a fork

`apps/api` already ships everything a branch box needs:

- `docker-compose.yml` — `app` + `scheduler` + `web` + `postgres:16-alpine`
- `config/database.php` defaults to **SQLite** with **pgsql** alongside, so the
  same Eloquent code runs on either
- `RestaurantScope` isolates tenants structurally; a branch box simply holds one
- `Dockerfile` and `deploy.sh` already exist for the hosted product

**A branch server is therefore packaging, not new engineering.** That is the whole
argument: it converts a frightening architectural fork into a deployment artifact.

## 3. The honest reason to choose a branch server

Not "offline support" — the terminal queue already provides that.

> The per-terminal offline queue solves **single-till** outages. It does **not**
> solve **multi-till consistency** during one.

Two tills offline can both seat table 12, and both sell the last portion of a dish.
Nothing on the client can prevent that, because neither till can see the other. A
branch server is the answer to that specific problem — it is a source of truth
inside the building.

**If a restaurant has one till, a branch server buys almost nothing** the queue
does not already give them. Say so, rather than selling a box they will then have
to look after.

## 4. Where it costs you

Recorded so nobody is surprised after the first ten installs.

- **The QR menu needs a public URL.** It is XOrder's core product. A restaurant
  with no internet has no menu for diners to scan. The realistic split is
  on-premises *POS* plus cloud *menu* — not an air-gapped site. The upstream field
  is now mandatory for exactly this reason.
- **You own uptime on every box.** Fifty restaurants is fifty servers to update,
  back up and support. They will call you, not their IT supplier.
- **Backups are the real risk.** A mini-PC under the counter with no backup is how
  a restaurant loses a year of sales. Islanded mode says this out loud in the
  wizard: *"there is no second copy."*
- **E-invoicing may not permit it.** Egypt's ETA e-receipt and Saudi ZATCA Phase 2
  both involve clearing receipts with the tax authority. An offline-only till
  cannot. **Confirm the current rules for each target market** — if clearing is
  mandatory it constrains this decision more than anything else here.

## 5. Client implementation

`DeploymentConfig` carries `mode`, `baseUrl`, `upstreamUrl`, `tenantSlug`,
`verifyTls` and `syncPolicy`. Chosen once in the setup wizard (step 2), then read
by everything that needs to know whether a server exists to talk to.

Three rules worth knowing:

**`canReachPlatform`** is true only for cloud. Branch-server and islanded tills
must tolerate a licence that can never be re-validated online — which is why
offline licence import is a first-class path (see `09-licensing.md`).

**`requiresPeriodicCheckIn`** is true only for islanded. The other two are
continuously visible: one writes to the platform, the other forwards through its
mandatory upstream. `isConfigured` enforces that upstream — a branch server with
nowhere to forward to is not a configuration, it is an invisible restaurant.

**TLS can only be relaxed on a private host.** A branch box on a LAN often has no
certificate, so the wizard offers to trust it — but `allowsInsecureTransport`
returns false for any public host, so a mistyped hostname cannot silently put the
till on plaintext. `isPrivateHost` checks RFC 1918 ranges plus loopback and
`.local`.

**`ConnectivityProbe` asks "can I reach *my* server", not "is there internet".** A
branch till on an islanded LAN has no internet and is perfectly healthy; a till
with four bars of WiFi and a dead branch server is not.

## 6. What the backend would need — none of it approved

| Request | For |
|---|---|
| **POS-BE-015** | Licence issuance and activation endpoints |
| **POS-BE-016** | Terminal registration against a licence, so `max_terminals` is enforced somewhere real |
| **POS-BE-017** | Branch-server packaging: single-tenant provisioning, seed, backup, update path, licence distribution to tills |
| **POS-BE-018** | Upstream sync — branch → cloud, reusing the idempotency contract of POS-BE-007 |

All `PROPOSED`. Agent 2 remains analysis-only until specific ids are approved.

## 7. Recommended commercial position

Keep **cloud** the default. Sell **branch server** to multi-till sites and to
places with genuinely bad connectivity, priced to cover the support you are taking
on. Offer **islanded** only where a single till and a documented backup routine
are both true.
