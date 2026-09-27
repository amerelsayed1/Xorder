# BACKEND → POS — Agreed Contracts

**Channel owner:** Agent 2 (Backend)
**Request channel:** `./POS_TO_BACKEND.md` (Agent 1's; the authoritative copy lives in
`~/Projects/Xorder/xorder-pos/docs/coordination/POS_TO_BACKEND.md`)
**Backend repo:** `~/Projects/Xorder/xorder-new` (`apps/api`)
**Last updated:** 2026-09-22 (POS-BE-010 refunds built → `READY`; §023 bundle gains
`receipt_profiles[]`) · 2026-09-11 (CB-00: both repos' copies reconciled) ·
2026-09-04 — **Cloud Wave 1 implemented, tested and smoke-verified; 16 items
`READY`** (see the banner and change log). Deferred items stay `APPROVED`.
Nothing committed or deployed.

---

## Cloud coordination review — 2026-09-27 (PROGRESS, PROPOSED)

The cloud side reviewed two owner revision specs against the live `apps/api` +
`apps/web` code and reconciled the cloud→POS wire shapes below. **Both specs were
cross-checked and are accurate**; nothing here is built, committed or deployed —
these are `PROPOSED` amendments awaiting the owner's go.

- **R1 — order-line bilingual name freeze** (spec: `docs/coordination/REVISION_ORDER_ITEM_ID.md`).
  Amends §006 / §010 / §023. New section **R1** below.
- **R2 — dashboard-managed online licence + `POST /api/pos/license/check`**
  (spec: `docs/coordination/REVISION_POS_LICENSING.md`). Amends §015 / §022.
  New section **R2** below.

**Verified against code (2026-09-27):** POS-BE-006's `StorePosOrderRequest`
already accepts `lines[].menu_item_id` (nullable) + `name_snapshot`
(`required_without`); `PosPricingEngine::price()` resolves by id and today lets
the client `name_snapshot` **win** (L93); `order_items` has **no** `name_ar`/
`name_en` yet. `PosLicence` has **no** `status`/`enforcement`/`suspended_*`
columns and **no** `RestaurantScope`; it already carries `kind` (cloud/offline),
`lifetime`, `max_users`, and `PosLicenceResource` already emits a computed
`state`. `LicenceController` has only `activate()` + `current()` (returns the
signed file); there is **no** `/license/check` endpoint and **no**
`LicenceIssuer::issueOnline()`. `pos.device` is a route-middleware alias that
supports `:no-feature`. Provisioning mints the licence inside the tenant-creation
transaction (`RestaurantProvisioningService::provision()`), which is exactly what
R2 §5.1 decouples. Full evidence in the two specs' "verified in code" tables,
re-confirmed.

**Open reconciliation items (need the desktop side / owner):** see the "Asks for
the desktop side" list at the end of R1 and R2.

---

## Current state

> # CLOUD WAVE 1 IS BUILT. `READY` ITEMS ARE SAFE TO INTEGRATE.
>
> **Owner go, 2026-09-02 ("make the POS work with cloud for now"):** the
> cloud-path slice was implemented in `apps/api` and is `READY` below —
> **740 backend tests green; smoke-verified end-to-end by Agent 1 on
> 2026-09-04** (claim → bundle → order → replay → heartbeat, real Flutter
> parser, 0 products dropped). Implementation notes + recorded deviations:
> `docs/backend/CLOUD_WAVE1_PROGRESS.md`.
>
> `APPROVED` items remain contract-final but UNBUILT (deferred from this
> wave): POS-BE-004, 012, 014, 017, 018, 021, 025, 026, 027, 028.
>
> **2026-09-22 — POS-BE-010 (refunds) is built and `READY`**, and the §023
> bundle gained `receipt_profiles[]`. Both were the owner's "hand A3 and A7 to
> xorder-cloud". The whole `apps/api` suite is green; not deployed.

**Agent 1: integrate against `READY` items only; keep `Fake` implementations
for everything still `APPROVED`.**

**As-shipped amendments folded in during the wave (agreed in-channel 2026-09-02/04):**
- **§024 PIN hash is PBKDF2-HMAC-SHA256** (120000 iterations, 16-byte salt,
  32-byte key, base64 pair) — NOT bcrypt as first written. The client ships a
  tested PBKDF2 verifier; wire shape in §024.
- **§023 bundle gains `tables`** (the terminal's branch floor) and the frozen
  normalized catalog shape: items carry integer `price_minor` /
  `discounted_price_minor` + resolved `option_group_ids`; deduplicated groups
  in `catalog.option_groups.data` with per-option `price_delta_minor`.
- **§006 v1 relaxations:** `acting_user_id` and `shift_client_id` are
  nullable — null actor ⇒ terminal-only attribution, per-user capability
  checks skipped (device token + `feature:pos` still gate); unknown shift ⇒
  stored null. A line's variant may arrive inside `option_ids[]`; two variant
  options of one group → `422 VALIDATION_FAILED`. The deleted-item fallback's
  asserted price field is `lines[].unit_price_minor`.
- **Timestamps:** client event times are stored with the INSTANT preserved
  exactly, serialised in UTC (the original utc-offset digits are not kept);
  `received_at` beside every one.
- **POS-BE-015 `GET /api/pos/licence/current`** was tightened from the
  provisional jwt gating to the device credential (no-feature mode), exactly
  as its shipped contract said it would be.

| ID | Contract | Status |
|---|---|---|
| POS-BE-001 | `Feature::POS` + `plans.max_terminals` | **READY** |
| POS-BE-002 | `pos.*` tenant capabilities — final strings in §001/002 | **READY** |
| POS-BE-003 | `?resolve=full` on `/dashboard/items` | **READY** |
| POS-BE-004 | `sku` + `barcode` on menu items | **APPROVED** |
| POS-BE-005 | `code` + `supported_order_types` on `BranchResource` | **READY** |
| POS-BE-006 | `POST /api/pos/orders` — server-priced | **READY** |
| POS-BE-007 | Idempotency + integer minor units | **READY** |
| POS-BE-008 | Per-branch invoice sequence | **READY** |
| POS-BE-009 | Shifts, cash movements, terminal registry | **READY** (registry itself lives in §023) |
| POS-BE-010 | Refunds as reversing records | **READY** (2026-09-22) |
| POS-BE-011 | **Option C decided** — device token issued at claim | **READY** |
| POS-BE-012 | Incremental catalog sync, `complete` per collection | **APPROVED** |
| POS-BE-013 | Money config — authored in dashboard, delivered in bundle | **READY** |
| POS-BE-014 | `POST /api/pos/customers` via `CustomerDirectory::upsert()` | **APPROVED** |
| POS-BE-015 | Licence issuance + activation | **READY** |
| POS-BE-016 | Seat counting — warns, never refuses | **READY** (warning on claim/register) |
| POS-BE-017 | Branch-server packaging | **APPROVED** |
| POS-BE-018 | Upstream sync — reuses POS-BE-007 verbatim | **APPROVED** |
| POS-BE-019 | Canonical error-code vocabulary (one list, §019) | **READY** |
| POS-BE-020 | Server time on every config-shaped response | **READY** |
| POS-BE-021 | `POST /api/pos/sync` — bounded at **100** elements | **APPROVED** |
| POS-BE-022 | Fleet registry + heartbeat — **response specified** | **READY** (fleet API only; web UI later; `stale` needs §026) |
| POS-BE-023 | Provisioning, pairing-code claim, `GET /api/pos/bootstrap` | **READY** |
| POS-BE-024 | POS PIN — **PBKDF2-SHA256 120k** (amended from bcrypt, see §024) | **READY** |
| POS-BE-025 | Pre-auth setup config + monotonic `config_version` | **APPROVED** |
| POS-BE-026 | Site registration + `ServerId` | **APPROVED** |
| POS-BE-027 | Three additive licence claims | **APPROVED** |
| POS-BE-028 | Terminal rename decoupled from identity | **APPROVED** |
| POS-BE-030 | Bundle withholds `purchase.manage`; cloud tills hide buying and stock | **READY** (platform half, CB-09 slice a) |

Nothing is `BLOCKED`. Every open question from Agent 1's 2026-08-26/28 replies is
answered below with a decision, not a discussion.

---

## Points of disagreement / counter-proposals — Agent 1, please respond

These are the only places this document deviates from, or adds to, what
`POS_TO_BACKEND.md` requested. Everything else is accepted as asked.

### DIS-1 · POS-BE-025 — no database connection details on the unauthenticated path

> **Accepted by Agent 1, 2026-09-02.** The wizard's manual-entry fallback covers
> the branch-server edge; `docs/pos/10-setup-architecture.md` will be updated.

The requested pre-auth `endpoints` block includes `database_host`,
`database_name`, `database_user`, `database_port`. That is internal topology and
a credential-adjacent hint, served to **anyone who knows the tenant slug**, on an
endpoint whose whole design accepts that it will be scraped. Counter-proposal:

- Pre-auth `GET /api/pos/setup/config/{slug}` carries `endpoints: { "base_url",
  "verify_tls" }` **only**.
- The database block moves to the **authenticated** bootstrap bundle
  (device credential), where a branch-server till legitimately needs it.
- Everything else in the pre-auth shape stands as requested, `printers` included.

The wizard flow this supports: pre-auth config gets the machine talking to the
right server; the claim gets it a credential; the bootstrap gets it the LAN
database details. One extra round-trip on branch-server setup, zero on cloud.

### DIS-2 · POS-BE-026 — site registration should present `licence_ref`

> **Accepted by Agent 1, 2026-09-02** — by first contact a site always holds a
> licence (the wizard requires one before trade). Error codes reconciled at
> Agent 1's request: the register ref check is `LICENCE_TENANT_MISMATCH`
> (uppercase — see §019 for the deliberate casing collision with the
> grandfathered lowercase activation code); `LICENCE_SITE_MISMATCH` is reserved
> solely for a licence's `server_id` claim naming a different site.

`POST /api/pos/sites/register` as requested is unauthenticated and resolved from
slug + branch. Rate limiting stops brute force but not pollution: anyone can
register phantom sites into a tenant's fleet view. Counter-proposal, costing the
honest path nothing: the request also carries **`licence_ref`** (the
`license_id` claim from the licence file the site already holds — by first
contact it always holds one, since it cannot trade without it). Server checks
the ref belongs to the resolved tenant; mismatch → `422 LICENCE_TENANT_MISMATCH`.
A site registered with a valid ref is `verified`; the field is required, not
optional, so the fleet view never carries unverifiable rows. Registration
remains **never a precondition** for the site to work.

### DIS-3 · POS-BE-027 — the "separate offline certificate": backend concurs with the declination

> **Acknowledged by Agent 1, 2026-09-02** — jointly declined by both agents; it
> stays on the owner's desk. No change needed.

Agent 1 declined the owner's request for a second signed document and recorded it
as a disagreement with the owner, not a silent substitution. **Agent 2's position:
Agent 1 is right.** Seven of the nine requested fields are already licence
claims; POS-BE-027's three additions cover the rest. A second signed document
means two expiry dates, two revocation paths, two verification code paths, and a
support call that opens with "which one is wrong" — and it contradicts
POS-BE-022's own instruction to build one enforcement path. Both agents now hold
the same position; the disagreement on record is **jointly with the original
request**, for the owner to overrule if the commercial need is real.

### DIS-4 · POS-BE-019 — licence activation codes stay lowercase, grandfathered

> **Accepted by Agent 1, 2026-09-02** — the client's switch tables carry both
> casings knowingly.

The shipped POS-BE-015 emits `licence_not_found`, `licence_revoked`,
`licence_tenant_mismatch`, `licence_superseded` — lowercase, unlike the
SCREAMING_SNAKE vocabulary everywhere else. That contract is `READY` and
installed clients may parse it; it will **not** be migrated. The canonical list
in §019 carries them as-is, marked grandfathered. Everything new is
SCREAMING_SNAKE. Flagged so the client's code-switch tables carry both casings
knowingly.

### DIS-5 · BE-A01 — settling payments later needs one endpoint Agent 1 did not request

> **Accepted by Agent 1, 2026-09-02**, and welcomed — per-payment keys were the
> POS recommendation. Client-side commitment recorded: `Tender` gains
> `clientId`, generated in `TicketEngine.addTender` at the moment the tender is
> added, never at sync time.

Accepting per-payment idempotency keys (decision **(a)** below) implies a way to
add a payment to an existing order: `POST /api/pos/orders/{id}/payments`. Small,
but it is new surface beyond the request set, so it is flagged here rather than
smuggled into §006. Shape in §006-P.

---

## Agreed defaults — owner may overrule

Both sides already concurred on these. They are **adopted as the agreed
default**; each is a single line for the owner to reverse if desired.

| # | Decision | Agreed default |
|---|---|---|
| **D1** | Money representation | **Integer minor units** on every POS wire field and every new POS table. `orders.total` keeps its `decimal(10,2)` projection for the dashboard. JSON never carries a float. Decisive: `CurrencyEnum` holds KWD/BHD/OMR/JOD, three-decimal currencies `decimal(10,2)` cannot represent. |
| **D2** | `subscription.writable` on POS writes | **Does NOT gate POS writes.** A lapsed plan never stops a till taking or reporting money — consistent with the existing deliberate choice for order handling. `SUBSCRIPTION_LAPSED` is **reserved in the vocabulary anyway** (§019), so reversing this later is a config change, not a contract change. |
| **Q1** | Renewal key | **Renewal reuses the activation key.** `key_hash` indexed non-unique; activation resolves to the newest non-revoked, non-superseded row for the hash. A six-till site retypes nothing. |
| **Q2** | Who issues licences | **SUPER_ADMIN only in v1.** `licences.manage` granted to no staff role; widen later if needed. (Already shipped this way.) |
| **Q3** | `branch_ids` claim | **Always `[]` in v1.** Field ships, UI does not. |
| **A4** | Settlement | `OrderStatus` untouched (`NEW/COMPLETED/CANCELLED`, invariant intact). `settlement_status` is **derived**, on both `OrderResource` and every POS order response: the five strings `UNPAID · PAID · PARTIALLY_REFUNDED · REFUNDED · VOIDED` are now **final**, not provisional. Unrecognised values render as *unknown* per the client's stated rule. |

---

## Cross-cutting conventions (apply to every `/api/pos/*` contract below)

1. **Money.** Every wire money field is an **integer in minor units**, suffixed
   `_minor`. Every rate is **integer basis points** (`1400` = 14%). `currency`
   (ISO 4217) and `exponent` are delivered in the setup config and bootstrap
   bundle; the client never assumes an exponent. JSON never carries a float.
2. **Idempotency** is POS-BE-007's contract, everywhere: replay of the same
   `client_transaction_id` returns the same 2xx body, never a 409. Same key with
   a **different payload** → `422 IDEMPOTENCY_PAYLOAD_MISMATCH` (the one case
   that is a genuine client bug).
3. **Errors.** Every 4xx/5xx from `/api/pos/*` carries
   `{ "code": "SNAKE_CASE", "message": "…", "details": {}? }`. Canonical list
   in §019. Unrecognised codes are retried, never discarded (client rule).
4. **Timestamps.** Client-supplied event times (`created_at`, `opened_at`,
   `occurred_at`) are stored **as sent**; the server independently stores
   `received_at`. Nothing is rejected or rewritten for skew (POS-BE-020);
   reporting decides which to trust.
5. **Auth tiers.** Three: **(i)** user JWT (`auth:jwt`, dashboard + Path B
   setup); **(ii)** **device token** (`auth:pos-device`, POS-BE-011 Option C —
   the till's own credential, defined in §011); **(iii)** unauthenticated +
   throttled (setup config, licence activate, claim, site register).
6. **Attribution.** Writes under a device token carry `acting_user_id` — the
   cashier who did the thing, verified locally by PIN (§024). Audit rows record
   both terminal and user.
7. **Tenancy.** `restaurant_id` comes from the device token / JWT / pairing
   code / slug resolution — never from request input (the sole exception stays
   the `/api/admin/*` licence issuance, documented in POS-BE-015). Unauthenticated
   paths pin the tenant via `TenantContext::overrideId()` released in `finally`.
   Cross-tenant reads stay 404.
8. **Audit.** Claim, revoke, rename, site register/replace, licence lifecycle,
   refunds, shift close: all `AuditLogger::record()` events.

---

## Decisions on the open questions (a–l)

Each is stated here once, then baked into the item sections.

- **(a) Payment idempotency — BOTH keys. Agent 1 adds `Tender.clientId`.**
  The order envelope carries `client_transaction_id` (dedupes order creation,
  inline payments included). **Each payment row additionally carries its own
  `client_transaction_id`**, generated when the tender is added
  (`TicketEngine.addTender`), because settling an open bill later — possibly
  from another terminal — is a real flow and needs its own dedupe key.
  Uniqueness: `(restaurant_id, client_transaction_id)` on `order_payments`.
- **(b) Tombstone flag — named `complete`, boolean, placed PER COLLECTION.**
  Not on the envelope: `items` and `categories` have `SoftDeletes` and can
  always report tombstones (`complete: true`); `option_groups`/`options` cannot
  until tombstones exist, so only *they* carry `complete: false`. An envelope
  flag would force a full pull of everything to cure a gap in one collection.
- **(c) Heartbeat response — accepted as proposed**, five fields exactly:
  `server_time`, `site_last_contact_at` (nullable), `licence_expires_at`
  (nullable), `config_version`, `terminal_status: active|stale|revoked`. §022.
- **(d) POS-BE-025 — accepted** with one carve-out (DIS-1): redacted projection
  of the bootstrap bundle; shared monotonic `config_version`; ETag/timestamp
  advisory only; `modules[]` never empty (validated at emit); `currency` +
  `exponent` mandatory; the POS-BE-013 money block lives **in the bundle**, and
  there is **no separate `/api/pos/config`**.
- **(e) POS-BE-026 — accepted**: idempotent on `(restaurant_id, branch_id,
  server_id)`; a different `server_id` for a taken branch → `409
  SITE_ALREADY_REGISTERED` carrying the existing `server_id` + `registered_at`;
  registration is never a precondition. Plus DIS-2 (`licence_ref` required).
- **(f) POS-BE-027 — confirmed additive, nothing re-signed.** Verified in code:
  `LicenceIssuer::claims()` already emits `max_offline_days`; `license_version`
  and `server_id` are added to **newly minted** payloads only. Stored payloads
  are verbatim and untouched; the client's tolerant `fromJson` defaults make old
  and new files mutually readable. Offline-certificate position: DIS-3.
- **(g) POS-BE-028 — accepted.** Rename never touches `terminal_id`,
  `server_id` or any credential; audited; per-branch uniqueness is advisory.
- **(h) POS-BE-011 — Option C.** A **device token** is issued at claim (Path A)
  or register (Path B): opaque `xdt_`-prefixed 64-hex bearer, stored
  HMAC-SHA256-hashed, **no TTL** — its lifecycle is terminal revocation, with a
  rotation endpoint. Cashiers never hold API credentials; they are identified by
  `acting_user_id`, verified locally by PIN. User JWTs stay 7-day and are used
  only for dashboards and Path B's initial call. No refresh token is built.
  Full wire shape in §011.
- **(i) POS-BE-019 — one canonical list confirmed**, including all 2026-08-28
  additions plus pairing/device/batch codes the new contracts need. §019.
- **(j) POS-BE-021 — batch bound is 100 elements** (all arrays combined,
  counted per element). Over → `413 BATCH_TOO_LARGE`, nothing processed.
  Idempotency is per element, exactly POS-BE-007; partial success is normal.
- **(k) POS-BE-017/018 — accepted at contract level.** 017 is packaging with
  three named deliverables (§017); 018 reuses POS-BE-007's idempotency contract
  **verbatim** — the branch server is just another client draining a
  `client_transaction_id`-keyed queue through §021's endpoint under its own
  device credential.
- **(l) POS-BE-023/024 — final bundle shape in §023** (money block, branch
  fields, staff + `pin_hash`, licence embed, catalog, `config_version`,
  `server_time`). Pairing codes: 8 Crockford chars `XXXX-XXXX`, HMAC-hashed at
  rest, single-use, **24 h TTL**, claim throttled per IP + per slug, idempotent
  within the TTL (encrypted response cached against the code, purged at
  expiry). **PIN hash: PBKDF2-HMAC-SHA256, 120k iterations** (amended
  2026-09-02 from the earlier bcrypt pick — the client ships a tested PBKDF2
  verifier); 4–6 digits; the salt+hash pair never `$fillable`, never in
  `UserResource`, only in the bootstrap `staff[]` behind the device
  credential. §024.

---

# The contracts

Sections are final wire contracts. JSONC comments are commentary, not payload.

---

## POS-BE-001 — `Feature::POS` + plan wiring · **READY**

- `Feature` gains `case POS = 'pos';`. `requires()` → `[]` (POS does not depend
  on QR features). `defaultSet()` → **off**; `resolve()` therefore yields
  `false` for every existing tenant. Sellable via `plans.feature_keys` exactly
  like the twelve existing flags.
- `plans` gains nullable `max_terminals` (unsigned smallint), following the
  `max_staff` precedent; `PlanLimitService` gains the matching check (returns
  the exceeded limit or null). Enforced at **claim** time as a **warning**, per
  POS-BE-016.
- All `/api/pos/*` write routes and the dashboard provisioning routes stack
  `feature:pos`. Failure code: `403 POS_FEATURE_DISABLED`.
- `UserResource.restaurant.features` gains `"pos": bool` automatically (it
  already serialises the resolved map).

**Schema:** additive `plans.max_terminals` nullable. No other change.

---

## POS-BE-002 — POS tenant capabilities · **READY**

Final strings (A1, unchanged — the client already adopted them):

```
pos.operate   pos.discount   pos.price_override   pos.void   pos.refund
pos.shift_open   pos.shift_close   pos.cash_movement   pos.reprint
```

Plus two new verbs this contract set needs:

```
pos.provision      # dashboard: create terminals, issue pairing codes, revoke
customers.create   # POS-BE-014 — the first write verb on customers
```

- Single-dot names throughout — `resource()` is `strtok($value, '.')`, so two
  dots are structurally forbidden.
- `implies()`: every `pos.*` verb implies `pos.operate`, which is the
  view-equivalent for the `pos` resource. `customers.create` implies
  `customers.view`.
- `group()` gains `'pos'`; the role editor picks the new verbs up with zero
  frontend work. Owner (`RESTAURANT_ADMIN`) bypasses all of them, as ever.
- Capability failure on a POS write: `403 POS_CAPABILITY_MISSING` with
  `details.capability` naming the missing verb.

**Schema:** none (enum only).

---

## POS-BE-003 — complete option groups on `/dashboard/items` · **READY**

- `GET /api/dashboard/items?resolve=full` — **opt-in**, existing callers keep
  their payload. With the flag, items are loaded through the same
  `withAutoOptionGroups()` path `PublicMenuService` uses, so `option_groups[]`
  includes `apply_scope = 'categories'` / `'all'` groups, merged and
  de-duplicated by `orderedOptionGroups()`, N+1-free.
- Response shape unchanged; the array is simply complete. Each entry carries
  `id`, `is_global`, `is_required`, `is_variant`, `max_select`, `options[]`
  as today.
- Permissions `can:menu.view`, `RestaurantScope` — both unchanged.
- Also honoured by the bootstrap `catalog` (always fully resolved there; the
  bundle has no lazy callers to protect).

**Schema:** none.

---

## POS-BE-004 — `sku` + `barcode` on menu items · APPROVED

- `menu_items` gains nullable `sku` (string 64) and `barcode` (string 64).
- Uniqueness **per tenant**, and because `menu_items` soft-deletes:
  `unique(restaurant_id, barcode, deleted_at)` and
  `unique(restaurant_id, sku, deleted_at)` (A2 — a plain two-column unique
  would let a soft-deleted row block barcode re-use forever).
- `POST/PUT /api/dashboard/items` accept `{ "sku": "BRG-001", "barcode":
  "6221031492818" }` — trimmed, nullable, `422 VALIDATION_FAILED` on duplicate
  with the standard Laravel error bag.
- Exposed on `MenuItemResource`; included in CSV/XLSX import/export columns.
- Permissions `can:menu.create` / `can:menu.update`, unchanged.

**Schema:** two nullable columns + two composite unique indexes. Additive.

---

## POS-BE-005 — `code` + `supported_order_types` on `BranchResource` · **READY**

`BranchResource` (verified: currently omits both, both already `$fillable` and
cast on the model) gains:

```jsonc
{ "code": "MAADI",                                  // nullable string
  "supported_order_types": ["dine_in", "takeaway", "delivery"] }  // [] never null
```

- `supported_order_types` is emitted as `[]` when unset — never `null`.
- Additive keys; every existing consumer unaffected. Permissions unchanged
  (`can:branches.list`). Same two fields appear on the branch objects in the
  setup config and bootstrap bundle.

**Schema:** none.

---

## POS-BE-006 — `POST /api/pos/orders` · **READY**

**The blocking contract.** Server-priced order creation on the existing `Order →
OrderRound → OrderItem` graph — one order history, distinguished by channel.

**Prerequisite schema (T0.2):** `order_items.menu_item_id` — nullable FK, no
behaviour change on the public path, and it independently fixes BE-A05
(`ReportService` matching by name) for the live QR product.

**Endpoint:** `POST /api/pos/orders`
**Auth:** device token (`auth:pos-device`) + `feature:pos`; `acting_user_id`
must hold `pos.operate` (and `pos.discount` / `pos.price_override` when those
fields are present). `subscription.writable` does **not** apply (D2).

**Request:**

```jsonc
{ "client_transaction_id": "uuid-v4",          // envelope idempotency key
  "branch_id": 3,                              // validated as belonging to tenant
  "order_type": "dine_in",                     // must be in branch.supported_order_types
  "table_id": 12,                              // dine_in only; lockForUpdate() on TableVisit
  "customer_id": null,                         // or client ref, POS-BE-014
  "shift_client_id": "uuid-v4",                // the open shift this sale belongs to
  "acting_user_id": 9,
  "created_at": "2026-09-02T13:05:00+02:00",   // client-supplied, stored as sent
  "priced_offline": true,
  "catalog_synced_at": "2026-09-02T08:00:00Z",
  "lines": [
    { "client_line_id": "L1",                  // 2026-09-22, POS-BE-010: the TILL'S name for
                                               // this line. Optional, ≤64 chars, unique within
                                               // the order, stored verbatim, echoed back, and
                                               // NOT part of the idempotency hash. It is how a
                                               // refund built offline addresses a line.
      "menu_item_id": 101,
      "variant_option_id": 555,                // nullable
      "option_ids": [710, 712],
      "quantity": 2,
      "note": "no onions",
      "name_snapshot": "Classic Burger",       // what the till displayed & printed
      "discount": { "amount_minor": 500, "reason": "manager_comp" },       // optional, needs pos.discount
      "price_override": { "unit_price_minor": 9000, "reason": "damaged" }  // optional, needs pos.price_override
    } ],
  "order_discount": { "amount_minor": 0, "reason": null },  // optional
  "asserted_totals": {                          // an assertion, never an instruction
    "subtotal_minor": 25000, "discount_minor": 500, "tax_minor": 3430,
    "charges_minor": 2500, "total_minor": 30430 },
  "payments": [                                 // BE-A01 — rows, split tender normal
    { "client_transaction_id": "uuid-v4",       // per-payment key (decision a)
      "tender_type_id": 1, "amount_minor": 20000,
      "received_at": "2026-09-02T13:06:00+02:00" },
    { "client_transaction_id": "uuid-v4",
      "tender_type_id": 2, "amount_minor": 10430,
      "received_at": "2026-09-02T13:06:10+02:00" } ] }
```

**Behaviour:**

- Every line is re-priced from `menu_item_id` + `variant_option_id` +
  `option_ids` via `displayPricing()` / `defaultVariantOption()` /
  `orderedOptionGroups()` + `VariantPricingService`, then tax/charges applied
  from the POS-BE-013 rules. **Client prices are compared, never used** —
  except:
- A line whose `menu_item_id` no longer resolves (deleted during an outage) is
  accepted from `name_snapshot` + asserted unit price, stored with
  `price_source: "client_asserted"` and the order flagged.
- Server totals ≠ `asserted_totals` → order is **still created** (money was
  taken); response carries `totals_mismatch: true` with both figures for the
  reconciliation dialog (POS-R081). A mismatch is never an error status.
- `orders.channel = 'pos'` (new column, default `'qr'` backfills existing rows).
- Inline `payments[]` are created as `order_payments` rows in the same
  transaction; sum may be less than total (partially settled bill).
- Invoice number assigned per POS-BE-008, inside the same transaction.
- Dine-in reuses the existing `TableVisit` `lockForUpdate()` discipline.

**Response `201` (and byte-identical on idempotent replay):**

```jsonc
{ "data": {
    "id": 8814,
    "client_transaction_id": "uuid-v4",
    "invoice_number": "MAADI-2026-001042",
    "status": "NEW",
    "settlement_status": "PAID",               // derived (A4) — PAID | UNPAID |
                                               // PARTIALLY_REFUNDED | REFUNDED (§010)
    "refunded_minor": 0,                       // 2026-09-22, POS-BE-010
    "channel": "pos",
    "totals": { "subtotal_minor": 25000, "discount_minor": 500,
                "tax_minor": 3430, "charges_minor": 2500,
                "total_minor": 30430, "currency": "EGP", "exponent": 2 },
    "totals_mismatch": false,                  // when true: "asserted_totals": {…} echoed
    "lines": [ { "id": 1, "menu_item_id": 101, "name": "Classic Burger",
                 "client_line_id": "L1",       // as sent, or null (§010)
                 "refunded_quantity": 0,       // 2026-09-22, POS-BE-010
                 "quantity": 2, "unit_price_minor": 9500,
                 "line_total_minor": 19000, "price_source": "server" } ],
    "payments": [ { "id": 51, "client_transaction_id": "uuid-v4",
                    "tender_type_id": 1, "amount_minor": 20000 } ],
    "created_at": "2026-09-02T13:05:00+02:00", // as sent
    "received_at": "2026-09-02T13:07:41Z" } }
```

**Errors:** `401 DEVICE_TOKEN_INVALID` · `403 POS_FEATURE_DISABLED /
POS_CAPABILITY_MISSING / TERMINAL_REVOKED` · `404 BRANCH_NOT_IN_TENANT` (as a
404, preserving the no-existence-leak rule) · `422 VALIDATION_FAILED /
MENU_ITEM_NOT_FOUND / SHIFT_NOT_OPEN / IDEMPOTENCY_PAYLOAD_MISMATCH`. Replay is
never 409 (POS-BE-007).

**Recovery lookup:** `GET /api/pos/orders/by-client-id/{uuid}` → the same `200`
body, `404` if unknown.

### §006-P — settle later: `POST /api/pos/orders/{id}/payments` (DIS-5)

```jsonc
// request — one payment, its own key (decision a)
{ "client_transaction_id": "uuid-v4", "tender_type_id": 1,
  "amount_minor": 10430, "acting_user_id": 9,
  "shift_client_id": "uuid-v4",
  "received_at": "2026-09-02T14:31:00+02:00" }
// 201 → the payment row + the order's recomputed settlement_status
{ "data": { "id": 52, "client_transaction_id": "uuid-v4",
            "amount_minor": 10430, "order_id": 8814,
            "settlement_status": "PAID" } }
```

`{id}` accepts the server id **or** the order's `client_transaction_id` (UUID
detected by format) — a second terminal settling a bill may only know the
server id from a lookup; the originating terminal may only know its own key.
Overpayment beyond the outstanding balance → `422 VALIDATION_FAILED` (change is
a client-side concern, not a stored negative payment).

**Amendment 2026-09-22 (POS-BE-010).** `lines[].client_line_id` is accepted and
stored on `order_items.client_line_id` under `unique(order_id, client_line_id)`;
the order response echoes it plus `refunded_quantity` per line, and
`refunded_minor` on the envelope. `settlement_status` gains
`PARTIALLY_REFUNDED` and `REFUNDED`; it never emits `PARTIALLY_PAID` or
`VOIDED`, and `status` still never carries refund state. Full reasoning in §010.

**Schema:** `orders`: + `channel` (string, default `'qr'`), +
`client_transaction_id` (uuid, nullable, `unique(restaurant_id,
client_transaction_id)`), + `invoice_number` (string, nullable, indexed), +
minor-unit total columns (`subtotal_minor` … `total_minor`, nullable — POS
orders fill them; `orders.total` decimal projection maintained for the
dashboard), + `branch_id` if absent, + `pos_terminal_id`, `pos_shift_id`,
`acting_user_id` (nullable FKs), + `received_at`. `order_items`: +
`menu_item_id` (nullable FK), + minor-unit price columns + `price_source`.
New table `order_payments`: `id, restaurant_id, order_id, pos_shift_id?,
pos_terminal_id?, acting_user_id?, client_transaction_id
(unique(restaurant_id, client_transaction_id)), tender_type_id, amount_minor,
currency, received_at, received_server_at, timestamps`. All additive,
nullable/defaulted.

---

## POS-BE-007 — idempotency + integer minor units · **READY**

Adopted **verbatim as requested**, as the cross-cutting convention:

- Transport: `Idempotency-Key: <uuid>` header **and** `client_transaction_id`
  body field; the body field is authoritative and is what gets persisted and
  indexed. If both present and different → `422 VALIDATION_FAILED`.
- Storage: `client_transaction_id` column on each POS aggregate
  (`orders`, `order_payments`, `pos_shifts`, `pos_cash_movements`,
  `pos_refunds`, POS-created `customers`), unique-indexed
  `(restaurant_id, client_transaction_id)` — tenant-scoped, so two tenants
  generating the same UUID never collide in the index.
- **Five submissions, one record, five identical 2xx bodies** — including id
  and invoice number. Replay is never `409`.
- Same key, different payload → `422 IDEMPOTENCY_PAYLOAD_MISMATCH` (compared on
  a canonical hash of the money-bearing fields, stored alongside the key).
- Money: **D1 adopted** — integer minor units, basis-point rates, discoverable
  currency + exponent, never a JSON float.
- Recovery: `GET /api/pos/orders/by-client-id/{uuid}` (§006); shifts and
  refunds are recoverable through their own `client_transaction_id`-addressable
  paths (§009, §010 — the refund one is
  `GET /api/pos/refunds/by-client-id/{uuid}`, live since 2026-09-22).

**Schema:** the columns/indexes listed per aggregate in their own sections.

---

## POS-BE-008 — per-branch invoice sequence · **READY**

- Format: `{branch.code}-{YYYY}-{NNNNNN}` (e.g. `MAADI-2026-001042`).
  Per-tenant configurable: prefix source (branch code | fixed string), padding
  (default 6), reset rule (`never | yearly | monthly`, default `yearly`).
  Config lives in restaurant settings, delivered read-only in the bundle.
- Concurrency: dedicated `invoice_sequences` table
  `(restaurant_id, branch_id, period, next_value)`, incremented under
  `lockForUpdate()` **inside** the order-creation transaction. Never
  `MAX()+1`.
- The sequence is **not** the primary key and never will be; `Order::code()`
  remains untouched for the QR path.
- Idempotency: a replayed `client_transaction_id` returns the **same** invoice
  number — the number is stored on the order at creation, and replays read,
  never increment.
- Offline: the till's provisional terminal-scoped reference (`T3-000117`) is a
  client-side concern; the server never honours a client-proposed number.

**Schema:** new `invoice_sequences` table; `orders.invoice_number` (§006).

---

## POS-BE-009 — shifts, cash movements, terminal registry · **READY**

The terminal registry itself is defined by POS-BE-023 (provision → claim);
POS-BE-009's registration endpoint is subsumed by claim/register there.

**Endpoints** (all device token + `feature:pos`; capability per row):

| Method | Endpoint | Capability | Purpose |
|---|---|---|---|
| `POST` | `/api/pos/shifts` | `pos.shift_open` | open a shift |
| `GET` | `/api/pos/shifts/current` | `pos.operate` | open shift for **this terminal** |
| `POST` | `/api/pos/shifts/{id}/close` | `pos.shift_close` | close with counted cash |
| `GET` | `/api/pos/shifts/{id}/report` | `pos.shift_close` | X/Z figures |
| `POST` | `/api/pos/cash-movements` | `pos.cash_movement` | cash in / out |

`{id}` accepts server id or the shift's `client_transaction_id` (UUID by
format), because an offline-opened shift has no server id yet at close time —
open and close may arrive in the same drain.

**Open request:**

```jsonc
{ "client_transaction_id": "uuid-v4", "branch_id": 3,
  "acting_user_id": 9, "opened_at": "2026-09-02T08:00:00+02:00",
  "opening_float_minor": 100000 }
```

**Close request:**

```jsonc
{ "client_transaction_id": "uuid-v4",       // the CLOSE action's own key
  "acting_user_id": 9, "closed_at": "2026-09-02T23:30:00+02:00",
  "counted_cash_minor": 412550,
  "denominations": [ { "value_minor": 20000, "count": 18 } ],  // optional
  "variance_reason": null }                  // required when |variance| > 0
```

**Close response:** the shift with server-computed `expected_cash_minor`
(formula **confirmed as A3**: `opening_float + cash_sales + cash_in − cash_out −
cash_refunds`; a future `payouts` concept arrives as another cash-movement
reason, never a new term), `variance_minor`, and the report figures.

**Amendment 2026-09-22 (POS-BE-010): `cash_refunds` is live.** A cash refund is
a refund tender whose POS-BE-013 tender kind is `cash` (an untyped tender counts
as cash, the same conservative rule a payment obeys), attributed to the shift
that **issued** the refund and never to the original sale's shift — the drawer
that paid it out is the drawer that is short. `GET /shifts/{id}/report` gains
three additive keys: `refunds_minor`, `refunds_count`, `cash_refunds_minor`,
each `0` on a shift with no refunds.

**Cash movement request:**

```jsonc
{ "client_transaction_id": "uuid-v4", "shift_client_id": "uuid-v4",
  "direction": "out", "amount_minor": 5000, "reason": "supplier",
  "reference": "invoice 4471", "acting_user_id": 9,
  "occurred_at": "2026-09-02T15:00:00+02:00" }
```

**Rules:**

- `opened_at` / `closed_at` / `occurred_at` are client-supplied and stored as
  sent; `received_at` stored separately (convention 4).
- **One open shift per terminal**, enforced server-side:
  `422 SHIFT_ALREADY_OPEN`. Writes requiring a shift without one open →
  `422 SHIFT_NOT_OPEN`.
- Report scoping (Agent 1's ask under BE-A02): `GET /shifts/{id}/report`
  resolves only shifts of **the requesting terminal's branch** — 404 otherwise,
  regardless of the user's capability. Cross-branch reporting is a dashboard
  feature, not a till feature.
- Full lifecycle must work offline and drain as a batch via §021 — shifts are
  processed before the orders that reference them.

**Schema:** `pos_shifts` — `id, restaurant_id, branch_id, pos_terminal_id,
client_transaction_id (unique per tenant), opened_by_id, closed_by_id,
opened_at, closed_at, received_at, opening_float_minor, counted_cash_minor?,
expected_cash_minor?, variance_minor?, variance_reason?, denominations json?,
status (open|closed), timestamps`. `pos_cash_movements` — `id, restaurant_id,
branch_id, pos_shift_id, pos_terminal_id, client_transaction_id (unique per
tenant), acting_user_id, direction (in|out), amount_minor, reason, reference?,
occurred_at, received_at, timestamps`. Both `BelongsToRestaurant` + `Auditable`.

---

## POS-BE-010 — refunds as reversing records · **READY**

**Built and tested 2026-09-22** (owner go: "hand A3 and A7 to xorder-cloud").
The contract below is the as-shipped one; where it refines the 2026-09-02
`APPROVED` text, the refinement is called out inline and the reason is given.

- `POST /api/pos/refunds` — device token (`pos.device`) + `feature:pos`.
  `acting_user_id`, when named, must hold **`pos.refund`** for `kind: refund`
  and **`pos.void`** for `kind: void`. Supervisor override above a configurable
  amount stays a client-side gate; the server records who authorised via
  `authorized_by_user_id` (validated as a real, active account of this tenant,
  never gated on a capability).
- A refund is a **new record referencing the original order** — the original is
  never mutated or deleted. `OrderStatus` and its `canTransitionTo()` invariant
  are untouched (A4).
- `GET /api/pos/refunds/by-client-id/{uuid}` is the POS-BE-007 recovery lookup:
  same `200` body, `404` if unknown.

### The OrderStatus decision (final)

**The platform's `OrderStatus` enum does not grow.** It stays
`NEW | COMPLETED | CANCELLED`, because it is the live QR product's lifecycle
column and `canTransitionTo()` is what protects the "new orders" badge and
order history. Refund state is carried entirely by the **derived**
`settlement_status`, which a POS response has always emitted:

| `settlement_status` | when |
|---|---|
| `UNPAID` | nothing taken, or taken in part, and nothing refunded |
| `PAID` | `paid >= total`, `total > 0`, nothing refunded |
| `PARTIALLY_REFUNDED` | `refunded > 0` and `refunded < paid` |
| `REFUNDED` | `refunded > 0` and `refunded >= paid` |

This is the till's own rule, verbatim — `paymentStatusFromSums` in
`xorder-pos/lib/domain/services/payment_status.dart` — so `PaymentStatus.fromWire`
parses every value the platform emits with the enum the till already ships.
Two deliberate narrowings of that enum:

- **`PARTIALLY_PAID` is never emitted.** The shipped §006 contract answers
  `UNPAID` for every incompletely settled bill; changing an existing value is
  not something a refund wave gets to do. A till wanting the finer word derives
  it from `totals.total_minor` and the `payments[]` it already has.
- **`VOIDED` is never emitted** — the 2026-09-02 text listed it. A settlement
  status answers "where is the money"; voidness is a property of the *refund*,
  and it is on the refund record as `kind: "void"`. Emitting `VOIDED` here would
  hand the till a word its `PaymentStatus` enum cannot parse, for a fact it can
  already read off the refund.

Two counters carry it, both additive, both **counters and not SUMs** — they are
what the *next* refund checks, inside the same transaction, under the same row
lock (the till's own reasoning, xorder-pos migration 12):
`orders.refunded_minor` and `order_items.refunded_quantity`.

### Addressing a line — the thing that was blocking this entirely

An offline till builds a refund against its **own** `pos_order_lines.id`; the
order being refunded may still be sitting in its outbox, so the till has never
seen `order_items.id`. `outbox_drain.dart` therefore refused to enqueue a refund
at all. The cure is additive and lands on BOTH endpoints:

- **`POST /api/pos/orders` accepts `lines[].client_line_id`** (string, ≤64,
  optional) — the till's own name for the line. Stored verbatim on
  `order_items.client_line_id` under `unique(order_id, client_line_id)`, echoed
  back in the order response's `lines[]`, and **deliberately excluded from the
  idempotency hash** (it carries no money, so a till that starts sending it must
  not get `IDEMPOTENCY_PAYLOAD_MISMATCH` on an order it already delivered
  without one).
- **A refund line names itself with exactly one of `order_item_id` or
  `client_line_id`.** Both, or neither, is `422 VALIDATION_FAILED`.

> **`client_line_id` must be unique within the order, and the till's `line_key`
> is not.** `TicketLine.keyFor` is `productId:sortedModifierIds` and
> `TicketEngine` merges only lines that are *draft, same key AND same note* —
> so one order legitimately holds two `pos_order_lines` rows with the same
> `line_key` (a sent line plus a new draft of the same dish; or the same dish
> with and without a note). `PostgresOrdersRepository._insertLines` already
> collapses those into one `Map<String,int>` entry, so the till has a latent
> ambiguity of its own here. **Recommended value: the till's local
> `pos_order_lines.id` as a string** — it is unique by construction, it is what
> `OrderRecordLine.id` already carries, and it is what `pos_refund_lines.order_line_id`
> references, which makes the drain a straight projection. `'L1'`-style keys are
> accepted too; the database index will refuse a duplicate within one order.

**Request:**

```jsonc
{ "client_transaction_id": "uuid-v4",
  "order_id": "8814",                       // server id OR the order's client_transaction_id (UUID by format); string on the wire
  "kind": "refund",                         // refund | void — optional, defaults to "refund"
  "reason": "cold food",                    // optional, ≤255
  "acting_user_id": 9,                      // optional (v1 relaxation: null ⇒ terminal-only attribution)
  "authorized_by_user_id": 4,               // optional, recorded not gated
  "shift_client_id": "uuid-v4",             // optional; unknown ⇒ stored null, never a rejection
  "occurred_at": "2026-09-02T14:00:00+02:00",   // client's event time, stored as sent
  "lines": [ { "client_line_id": "L1",      // …or "order_item_id": 1 — exactly one
               "quantity": 1, "amount_minor": 9500 } ],
  "tenders": [ { "tender_type_id": 1,       // platform ids, per POS-BE-013
                 "amount_minor": 9500 } ] }     // how the money went back — required, ≥1 row
```

**Response `201`** (byte-identical `200` on replay):

```jsonc
{ "data": {
    "id": 12,
    "client_transaction_id": "uuid-v4",
    "credit_note_number": "CN-MAADI-2026-000001",   // own CN- series (see below)
    "kind": "refund",
    "reason": "cold food",
    "order": { "id": 8814, "client_transaction_id": "uuid-v4",
               "invoice_number": "MAADI-2026-001042",
               "total_minor": 20000, "refunded_minor": 9500,
               "settlement_status": "PARTIALLY_REFUNDED" },
    "totals": { "total_minor": 9500, "currency": "EGP", "exponent": 2 },
    "lines": [ { "id": 5, "order_item_id": 1, "client_line_id": "L1",
                 "name": "Classic Burger", "quantity": 1,
                 "unit_price_minor": 9500, "amount_minor": 9500 } ],
    "tenders": [ { "id": 3, "tender_type_id": 1, "amount_minor": 9500 } ],
    "acting_user_id": 9, "authorized_by_user_id": 4,
    "occurred_at": "2026-09-02T14:00:00+02:00",     // as sent
    "received_at": "2026-09-02T14:02:11Z" } }
```

**Credit note numbers** are drawn from the same `invoice_sequences` mechanism as
an invoice, under the same `lockForUpdate()` inside the same transaction, in
their **own `CN-` period bucket** (`CN-2026`): a refund therefore never consumes
an invoice number, and a gap in the invoice series still means what an auditor
thinks it means. A replayed `client_transaction_id` reads the stored number back
and consumes nothing.

**Validation, all server-authoritative:**

| Rule | Failure |
|---|---|
| cumulative refunded quantity per line ≤ sold quantity | `422 REFUND_EXCEEDS_SOLD`, `details` = `{order_item_id, client_line_id, sold_quantity, already_refunded_quantity, requested_quantity}` |
| cumulative refunded money ≤ the order's `total_minor` | `422 REFUND_EXCEEDS_SOLD`, `details` = `{order_total_minor, already_refunded_minor, requested_minor}` |
| refund tender total **equals** refund line total | `422 VALIDATION_FAILED` |
| tender ids are this tenant's own (POS-BE-013) | `422 VALIDATION_FAILED` |
| a line is on that order, named exactly one way | `422 VALIDATION_FAILED` |
| unknown / foreign / non-POS order | `422 VALIDATION_FAILED` (same answer either way — no existence leak) |
| named actor lacks the verb | `403 POS_CAPABILITY_MISSING`, `details.capability` |
| replay, same money | `200`, identical body |
| replay, different money | `422 IDEMPOTENCY_PAYLOAD_MISMATCH` |

**No new error code was invented.** §019's rule is that an unrecognised code is
*retried, never discarded* — so a brand-new code for a permanent refusal would
be retried forever by a till that predates it. Money-over-the-total therefore
reuses `REFUND_EXCEEDS_SOLD` (the client's reaction is identical: stop, this
refund is not valid) and everything else uses vocabulary §019 already carries.

**Cash-up.** A refund is attributed to the shift that **issued** it, never the
original sale's, and the A3 formula's `cash_refunds` term is now live:
`opening_float + cash_sales + cash_in − cash_out − cash_refunds`, where a cash
refund is a refund tender whose tender kind is `cash` (an untyped tender counts
as cash, the same conservative rule a payment obeys). `GET /shifts/{id}/report`
gains three additive keys: `refunds_minor`, `refunds_count`,
`cash_refunds_minor` — all `0` on a shift with no refunds.

**Audit:** `pos_refund.created`, carrying the credit note number, kind, total,
order, reason, authoriser and terminal.

**Schema (all additive, nullable/defaulted, reversible):**
`orders.refunded_minor` (default 0); `order_items.client_line_id` (nullable,
`unique(order_id, client_line_id)` — NULL is not unique on either engine, so
every existing row and every QR order is untouched) and
`order_items.refunded_quantity` (default 0); new tables `pos_refunds`,
`pos_refund_lines`, `pos_refund_tenders` — `BelongsToRestaurant`, and
`pos_refunds` is `Auditable`. There are **no negative `order_payments` rows**:
that column is unsigned on purpose and a refund is not a payment with a minus
sign.

**Recorded deviations from the 2026-09-02 text:** (1) `VOIDED` is not a
settlement status, per the reasoning above. (2) `kind: void` asks for `pos.void`
rather than `pos.refund` — the till's own permission model keeps the two acts
apart, and a person trusted to hand money back is not automatically the person
trusted to make a sale disappear. (3) `tenders[]` is **required** and must
balance the lines: this endpoint records money that physically went back, so a
"void" of a bill nothing was ever taken on does not belong here at all (the till
voids that locally and the platform's order simply has no payments). (4) The
platform's `kind` axis (`refund | void`) is **not** the till's
`pos_refunds.kind` (`full | partial`) — the platform derives full-vs-partial
itself from the counters and reports it as the order's `settlement_status`.

---

## POS-BE-011 — device credential (Option C) · **READY**

**Decision:** Option C — the *terminal* is authenticated, the *cashier* is
identified. POS-BE-023's claim flow is the issuance point, exactly as Agent 1
observed; with provisioning in the contract set anyway, "Option A now, C later"
would mean building the issuance point twice. Superseded recommendation
withdrawn.

**The contract:**

- **Issued at:** `POST /api/pos/terminals/claim` (Path A) and
  `POST /api/pos/terminals/register` (Path B). Shown once in that response;
  the server stores only `HMAC-SHA256(token, APP_KEY)` in
  `pos_terminals.device_token_hash` (same discipline as licence keys —
  deterministic, indexable, useless in a stolen dump).
- **Format:** `xdt_` + 64 lowercase hex chars. Sent as
  `Authorization: Bearer xdt_…` and resolved by a new `auth:pos-device` guard
  (`Auth::viaRequest`, beside the `jwt` guard). The `xdt_` prefix is what lets
  the guard and the till distinguish it from a JWT at a glance.
- **TTL: none.** The lifecycle is terminal revocation (BE-A04): revoke the
  terminal → the token dies with it. No refresh token exists or is planned.
- **Rotation:** `POST /api/pos/terminals/rotate-token` (device token) returns a
  new token; the **old token remains valid for 24 h** after rotation so a crash
  between receiving and persisting the new one cannot brick the till.
- **Scope:** the token pins `(restaurant_id, terminal_id)`. It authenticates
  every `/api/pos/*` terminal route: orders, payments, shifts, cash movements,
  refunds, sync, heartbeat, bootstrap, licence `current`, rename (own row).
  It can never call `/api/dashboard/*` or `/api/admin/*`.
- **Cashiers:** hold no API credential. `acting_user_id` on each write names
  the cashier, verified locally by PIN (§024); the server validates the user
  belongs to the tenant, is active, and holds the required `pos.*` capability.
- **User JWTs** stay exactly as they are (7-day TTL, no refresh,
  `password_changed_at` invalidation) and are used by the till only for Path B's
  initial register call. A mid-shift JWT expiry no longer matters: the device
  token does the selling.

**Errors:** `401 DEVICE_TOKEN_INVALID` (unknown/rotated-out token) ·
`403 TERMINAL_REVOKED` (known token, revoked terminal — distinct, because the
client's reactions differ: re-pair vs. tell the manager).

**Schema:** `pos_terminals.device_token_hash` char(64) indexed,
`device_token_rotated_at` nullable, `previous_token_hash` nullable char(64)
(the 24 h overlap). Additive; table defined in §023.

---

## POS-BE-012 — incremental catalog sync · APPROVED

- `?updated_since=<iso8601>` on `GET /api/dashboard/items`, `/categories`,
  `/option-groups`, `/combos` (all `can:menu.view`, unchanged).
- Response per endpoint: `{ "data": [...], "deleted_ids": [...], "synced_at":
  "…", "complete": true|false }`.
- **`complete` sits per collection (decision b).** `items` and `categories`
  soft-delete, so their tombstones come from `deleted_at` and `complete` is
  `true`. `option_groups` / `options` / `combos` have no tombstones (BE-A03),
  so their delta responses carry `complete: false` until that lands — the
  client full-pulls exactly those collections and nothing else.
- `synced_at` is server time; the client passes it back as the next
  `updated_since` (never its own clock — POS-BE-020).
- The bootstrap `catalog` carries the same per-collection `complete` flags.

**Schema:** none for v1 (`complete: false` is the honest gap). When option-group
tombstones land later, the flag flips to `true` — additive, no client change
needed beyond what is already specified.

---

## POS-BE-013 — money configuration · **READY**

The server authors everything that decides how much money is owed. All design
asks accepted: basis points, explicit inclusive/exclusive, scoping, taxable
charges, tender `kind`.

**Authoring (dashboard, `feature:pos`, `can:settings.view` /
`can:settings.update`):**

| Method | Endpoint |
|---|---|
| `GET/POST/PUT/DELETE` | `/api/dashboard/tax-rules` |
| `GET/POST/PUT/DELETE` | `/api/dashboard/charges` |
| `GET/POST/PUT/DELETE` | `/api/dashboard/tender-types` |

`tax_registration_number` joins the existing restaurant profile
(`RestaurantProfileController`), nullable string.

**Delivery: there is NO separate `GET /api/pos/config`** (decision d). The
`money` block lives in the bootstrap bundle and, redacted-not-at-all (it holds
no secrets), in the pre-auth setup config. One document, one `config_version`,
one thing to invalidate. Every write to these tables bumps `config_version`.

**Wire shapes (inside the bundle):**

```jsonc
"money": {
  "tax_rules": [
    { "id": 1, "name": "VAT", "rate_bp": 1400,        // 14.00% — basis points
      "mode": "exclusive",                             // inclusive | exclusive
      "applies_to": { "order_types": [], "branch_ids": [],
                      "category_ids": [], "item_ids": [] },  // [] = all
      "sort_order": 1 } ],
  "charges": [
    { "id": 1, "name": "Service", "kind": "percent",   // percent | fixed
      "rate_bp": 1000, "amount_minor": null,           // exactly one non-null
      "taxable": true,
      "applies_to": { "order_types": ["dine_in"], "branch_ids": [] } } ],
  "tender_types": [
    { "id": 1, "name": "Cash", "kind": "cash",         // cash | card | external | other
      "is_active": true, "sort_order": 1 },
    { "id": 2, "name": "Card (bank terminal)", "kind": "card",
      "is_active": true, "sort_order": 2 } ] }
```

- Rates are **integer basis points**; fixed amounts are **integer minor units**.
- `currency` + `exponent` accompany the bundle (`restaurant` block) — mandatory.
- Server-side pricing in §006 applies these same rules; the client's offline
  computation from the cached block must agree, and `totals_mismatch` is the
  detector when it does not.
- Deleting a tender type in use soft-deactivates (`is_active: false`) rather
  than removing the row — historical payments keep their FK.

**Schema:** three new tenant-scoped tables (`tax_rules`, `charges`,
`tender_types`, all `BelongsToRestaurant`), `restaurants.tax_registration_number`
nullable. Additive.

**Amendment, 2026-09-11: the tender-id defect** (owner go 2026-09-11: "fix
the tender-id mismatch now as a defect"). **This is an amendment to POS-BE-013,
not new surface.** No endpoint, bundle key, field or error code is added, and
the wire shape above is unchanged, so there is no POS-BE-030. It writes down
rules the shape already implied, which a cloud till was breaking:

1. **`payments[].tender_type_id` MUST be an `id` from this bundle's
   `money.tender_types`.** That goes for §006 and §006-P alike. The platform
   checks it against the requesting terminal's own tenant, and an id from
   anywhere else is `422 VALIDATION_FAILED` (`errors.payments`: "Unknown tender
   type."). A till's local tender ids mean nothing to the platform. On a cloud
   terminal the till seeds its tender table from this list, keyed by the
   platform id, and pays with those ids.
2. **A POS restaurant's list is never empty.** When the restaurant's first
   terminal is created (dashboard or Super Admin provision, or Path B
   register) and it has **zero** tender types, active or inactive, the
   platform creates two:
   `{ "name": "Cash", "kind": "cash", "is_active": true, "sort_order": 0 }` and
   `{ "name": "Card", "kind": "card", "is_active": true, "sort_order": 1 }`.
   Names are in the restaurant's default language (`نقدي` / `بطاقة` for an
   Arabic restaurant); `name` is still a single column. A claim runs the same
   check, as a backstop for a terminal provisioned before this change. It is
   idempotent: a restaurant that already has any tender gets nothing, and so
   does a second terminal. Seeding bumps `config_version` like any tender
   write. The owner renames, adds or deactivates tenders in the dashboard as
   before. The ids are ordinary platform ids, **not** 1 and 2. Match on `id`,
   or on `kind`, never on the name.
3. **`tender_type_id: null` means "unspecified". It is not a fallback.** The
   field stays nullable on the wire, and a null payment is still accepted. But
   the §009 shift report counts an untyped payment **as cash** in expected cash.
   A card payment sent as null inflates the drawer's expected cash and hides a
   real short. Clients MUST NOT send null in place of an id they couldn't map.
   A payment with no matching id is a client defect: fix the mapping, don't
   null it.
4. The platform does not overrule an owner who deactivated **every** tender.
   The list is then non-empty but has nothing active, and an inactive id is
   still accepted on a payment (historical FKs, the rule above). What the till
   shows in that state is the till's decision.

---

## POS-BE-014 — authenticated customer creation · APPROVED

- `POST /api/pos/customers` — device token + `feature:pos` +
  `customers.create` (new verb, §002) on `acting_user_id`.
- **Implemented over `CustomerDirectory::upsert()`** — the exact same code path
  and phone normalisation (`NormalizesPhoneNumbers`) as the public diner path,
  so POS-created and diner-created customers deduplicate to one identity.

**Request:**

```jsonc
{ "client_transaction_id": "uuid-v4",
  "name": "…", "phone": "+2010…",
  "address": "…", "latitude": null, "longitude": null, "note": "…",
  "acting_user_id": 9 }
```

**Response `201`:** `CustomerResource`. Replay-safe twice over: the
idempotency key, and the phone upsert underneath it. Offline flow as requested:
the order references the customer by its `client_transaction_id` until the
server id returns; §021 processes `customers` before `orders`.

**Schema:** `customers.client_transaction_id` nullable uuid,
`unique(restaurant_id, client_transaction_id)`. Additive.

---

# POS-BE-015 — Licence issuance and activation · **READY**

**Status:** READY — implemented and tested.
**Agreed and built:** 2026-08-26. **Owner decision D6.**
**Client half:** built and tested — `lib/features/licensing/`, `docs/pos/09-licensing.md`.

> **Agent 1 may integrate.** The contract below is what shipped, not a proposal.
> The one client-side prerequisite is §6 gap 1 — `LicenseClaims` still does not
> read `max_offline_days`, which the server now emits. A till that ignores it
> simply does not enforce the check-in window, so this does not block the swap
> from `FakeLicenceService` to `DefaultLicenceService`.
>
> **What shipped in `apps/api`:**
> `config/licence.php` · `database/migrations/2026_08_26_000100_create_pos_licences_table.php` ·
> `app/Models/PosLicence.php` · `app/Support/LicenceKey.php` ·
> `app/Services/LicenceIssuer.php` · `app/Services/LicenceActivator.php` ·
> `app/Console/Commands/LicenceKeygen.php` ·
> `app/Http/Controllers/{Admin,Pos}/LicenceController.php` ·
> `app/Http/Requests/Admin/{Store,Renew}LicenceRequest.php` ·
> `app/Http/Requests/Pos/ActivateLicenceRequest.php` ·
> `app/Http/Resources/PosLicenceResource.php` ·
> `Capability::LICENCES_MANAGE` · the `licence-activate` rate limiter ·
> `tests/Feature/Admin/PosLicenceTest.php` (14 tests).
>
> **What shipped in `apps/web`:** `src/pages/admin/pos/{LicencesList,LicenceForm,LicenceDetails}.vue`,
> routed at `/pos/licences` behind `meta.capability: 'licences.manage'`, with
> `licence.*` strings in `en` and `ar`.
>
> **Before issuing anything for real:** run `php artisan licence:keygen`, put
> `LICENCE_SIGNING_KEY` in the API environment, and compile the printed public
> key into the Flutter binary.

---

## D6 — a licence is its own record, issued per client

**Owner's decision:** a licence is a standalone row created by Super Admin
against one restaurant. It is **not** derived from the tenant's subscription or
plan.

The alternative considered — a *Download licence* button on the restaurant page
that signs claims straight from the current plan and subscription end date —
was rejected because:

- an on-premises customer may have **no subscription row at all**, and that is
  precisely the customer who most needs a signed file;
- deals have bespoke terms (a four-till branch server on a two-year term is not
  a plan tier), and a derived licence can only express what the plan expresses;
- a licence is a **historical document**. Deriving it means it silently changes
  meaning whenever the plan is edited, which destroys the record of what the
  customer was actually sold.

`plan_id` is kept as a **prefill** for `features[]`, not as the source of truth.

---

## 1. Key material

Ed25519, one key pair per `key_id`.

| | |
|---|---|
| Private key | `LICENCE_SIGNING_KEY` in the API `.env` — base64 of the 64-byte libsodium secret key. Never in git, never in a migration, never in an audit log, never in a response. |
| Public key | The 32-byte verify key, compiled into the Flutter binary as `LicenseVerifier.publicKeyBytes`. |
| Generation | `sodium_crypto_sign_keypair()` — the API already has ext-sodium via Laravel. |
| `key_id` | Names the pair. `v1` today; the client defaults to `v1` when the field is absent. |

**Rotation rule — the one that can strand a fleet:** ship the new public key in a
POS release **before** signing anything with it. A till that cannot verify has no
way of being told to update, and it will report `invalid`, which the operator
reads as "my licence is broken". Keep signing with the old `key_id` until the
fleet is confirmed on the new build. `key_id` exists so both keys can be live at
once; use it that way.

## 2. What is signed — exactly

- `payload` is base64url of the **UTF-8 claims JSON**.
- `signature` is Ed25519 over the **decoded payload bytes** — not over the
  base64 string, and not over a canonical re-serialisation.

Verified against `LicenseVerifier.verifySignature()`
(`lib/features/licensing/domain/license_verifier.dart:79`), which does
`base64Url.decode(payload)` and passes those bytes as the message.

**Consequence for the issuer:** build the JSON **once**, keep the byte string,
sign those bytes, base64url-encode those same bytes. Do not re-encode from a
decoded structure at any point — a re-serialisation that reorders keys or
changes whitespace produces a file that will not verify. Base64 padding is
tolerated on the client (`_pad`), so `=` may be stripped or kept.

The file, as distributed:

```json
{ "payload": "…", "signature": "…", "key_id": "v1" }
```

**No `alg` field. Ever.** The algorithm is fixed in the client and cannot be
selected by the file; that absence is the whole reason this is not a JWT, and
adding the field would reintroduce the `alg: none` bug class the format exists
to avoid. Distributed as a `.xlic` file, `application/json`.

## 3. Table — `pos_licences`

Additive. No existing table is altered. Sits alongside the `pos_terminals`
proposed in POS-BE-009 / POS-BE-023.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint pk | internal only |
| `restaurant_id` | fk → `restaurants`, cascade, **not null**, indexed | a licence always names exactly one client (D6) |
| `licence_ref` | string(32), unique | the public reference, emitted as the `license_id` claim — e.g. `LIC-2026-0007`. **Not** the primary key wearing a prefix; that is the `Order::code()` mistake and it is not repeated here |
| `key_hash` | char(64), **indexed, not unique** | HMAC-SHA256 of the normalised activation key, keyed with `APP_KEY`. See §5 for why HMAC and not bcrypt, and §11 Q1 for why not unique |
| `key_last_four` | char(4) | so the list view can show `…7K2Q` without holding the key |
| `plan_id` | fk → `plans`, nullable | prefills `features[]` at issue time; a bespoke on-prem licence may have no plan |
| `issued_at` | timestamp, not null | start of term |
| `expires_at` | timestamp, not null | end of term |
| `grace_days` | unsigned smallint, default 14 | trade continues this long past expiry |
| `warn_days` | unsigned smallint, default 30 | renewal banner window |
| `max_terminals` | unsigned smallint, default 1 | **advisory offline** until POS-BE-016 |
| `max_offline_days` | unsigned smallint, **nullable** | POS-BE-022 check-in window. Null = unlimited, which is the correct value for cloud |
| `features` | json, default `[]` | array of `Feature` enum values |
| `modes` | json, default `["cloud"]` | subset of `cloud` · `branch_server` · `standalone` |
| `branch_ids` | json, default `[]` | `[]` means every branch of the tenant |
| `fingerprints` | json, default `[]` | `[]` means unpinned |
| `payload` | text, not null | the minted artifact, stored **verbatim** |
| `signature` | text, not null | ditto — so re-activation returns identical bytes without re-signing |
| `key_id` | string(8), default `v1` | which pair signed this row |
| `superseded_by_id` | nullable self-fk | set when a renewal replaces this row |
| `revoked_at` | nullable timestamp | |
| `revoked_reason` | string, nullable | operator-facing, never sent to the till |
| `activated_at` | nullable timestamp | first successful activation |
| `notes` | text, nullable | Super Admin's commercial note. **Never signed, never sent to the till** |
| `created_by_id` | fk → `users`, nullable | which platform user issued it |
| timestamps | | |

**Model discipline:** `restaurant_id`, `key_hash`, `payload`, `signature`,
`licence_ref` and `key_id` are **not `$fillable`**. They are set only by
`App\Services\LicenceIssuer` via `forceCreate`, following the same rule that
already protects `users.role` and `users.restaurant_id`.

**Renewal creates a new row.** It does not mutate the term in place. The old row
gets `superseded_by_id`. Reason: the signed artifact is a record of what the
customer was sold, and overwriting it erases that. It also means a support
question — *"what were they actually entitled to in March?"* — has an answer.

**No money column.** A licence records entitlement, not price. Billing stays
where it is.

## 4. Endpoints

New `Capability::LICENCES_MANAGE = 'licences.manage'`, registered as a Gate
ability in `AppServiceProvider`, granted to `SUPER_ADMIN` through the existing
`Gate::before` bypass and to **no other role by default** (see §11 Q2). The
route group sits inside the existing `admin` prefix, beside the `plans.manage`
group at `routes/api.php:123`.

| Method | Endpoint | Gate | Purpose |
|---|---|---|---|
| `GET` | `/api/admin/pos/licences` | `can:licences.manage` | list; filter by restaurant, state, expiry window |
| `POST` | `/api/admin/pos/licences` | `can:licences.manage` | issue. Returns the activation key **once** |
| `GET` | `/api/admin/pos/licences/{licence}` | `can:licences.manage` | detail + decoded claims |
| `POST` | `/api/admin/pos/licences/{licence}/renew` | `can:licences.manage` | new row, new term, same restaurant |
| `POST` | `/api/admin/pos/licences/{licence}/revoke` | `can:licences.manage` | sets `revoked_at` |
| `GET` | `/api/admin/pos/licences/{licence}/download` | `can:licences.manage` | the `.xlic` file, for on-premises delivery |
| `POST` | `/api/pos/licence/activate` | **none** — the key is the credential; throttled | exchange a key for the file |
| `GET` | `/api/pos/licence/current` | device credential (POS-BE-023) or `pos.operate` | newest non-revoked licence for this tenant |

The `/api/admin/pos/` prefix deliberately matches POS-BE-022's
`/api/admin/pos/terminals`, so the Super Admin POS surface is one namespace.

**The admin reads are cross-tenant on purpose** — same posture POS-BE-022 asks
for on the fleet list. Make that explicit and audited in the controller rather
than incidental, since `RestaurantScope` is what everything else here relies on.

`EnsureSubscriptionAllowsWrites` **does not apply** to activation. A lapsed
subscription must not stop a till installing a licence the customer already paid
for; that converts a collections problem into an outage, which is the same
reasoning as D2.

## 5. Wire shapes

### Issue — `POST /api/admin/pos/licences`

```jsonc
{ "restaurant_id": 42,
  "plan_id": 3,
  "issued_at": "2026-09-01",
  "expires_at": "2027-09-01",
  "grace_days": 14,
  "warn_days": 30,
  "max_terminals": 4,
  "max_offline_days": 7,
  "features": ["qr_menu", "dine_in", "multi_branch"],
  "modes": ["cloud", "branch_server"],
  "branch_ids": [],
  "fingerprints": [],
  "notes": "3-year deal, reissued annually" }
```

> `restaurant_id` arrives in request input **here and only here**. This is an
> `/api/admin/*` route where the actor is platform staff acting deliberately
> across tenants — exactly like `PATCH admin/restaurants/{restaurant}/subscription`.
> It is not the `RestaurantScope` rule being bent, and the same input on any
> `/api/dashboard/*` route remains forbidden.

**Response `201`:**

```jsonc
{ "data": {
    "id": 7,
    "licence_ref": "LIC-2026-0007",
    "restaurant": { "id": 42, "name": "…", "slug": "demo" },
    "state": "active",
    "issued_at": "2026-09-01T00:00:00Z",
    "expires_at": "2027-09-01T00:00:00Z",
    "max_terminals": 4,
    "key_last_four": "7K2Q",
    "activation_key": "XO4T-9WQM-2K7H-BR5N",
    "file": { "payload": "…", "signature": "…", "key_id": "v1" } } }
```

**`activation_key` appears in this one response and never again.** Same
discipline as a personal access token: the dashboard must force the operator to
copy it before the modal closes, because the server keeps only the HMAC.

### Key format

16 Crockford base32 characters in four groups: `XO4T-9WQM-2K7H-BR5N`.

Crockford because it **excludes `I`, `L`, `O` and `U`** — which is what makes a
key readable down a phone line to an installer standing at a till in a noisy
restaurant. That is the actual delivery channel for the on-premises case, so it
governs the alphabet.

Normalise on input before hashing or comparing: uppercase, strip hyphens and
whitespace, fold Arabic-Indic digits (the API already folds them elsewhere; the
web side has `enDigits.js`).

**Why HMAC-SHA256 and not `Hash::make`:** activation must *find* the row from the
key alone. A bcrypt/argon hash is salted per row and therefore not searchable —
you would have to load every licence and verify against each, which is both slow
and a timing oracle. HMAC keyed with `APP_KEY` is deterministic, indexable, and
still not reversible by anyone who steals a database dump without the key.

### Activate — `POST /api/pos/licence/activate`

```jsonc
{ "key": "XO4T-9WQM-2K7H-BR5N",
  "tenant_slug": "demo",
  "deployment_mode": "cloud",
  "fingerprint": "sha256:…",
  "terminal_id": null }
```

**Response `200` — the bare file, nothing else:**

```json
{ "payload": "…", "signature": "…", "key_id": "v1" }
```

`LicenseFile.tryParse` reads exactly these three keys and ignores any others, but
keeping the response minimal means the activation response and the downloaded
`.xlic` are **the same bytes**, which is what makes the two delivery paths
impossible to drift apart.

**Errors** use POS-BE-019 codes: `licence_not_found`, `licence_revoked`,
`licence_tenant_mismatch`, `licence_superseded`. The operator-facing message must
**not** distinguish "wrong key" from "no such key" — that difference is an
enumeration oracle and is worth nothing to an honest installer.

`fingerprint` is recorded, not enforced, unless the licence was issued with a
non-empty `fingerprints[]`.

### Bootstrap embed

POS-BE-023's bundle carries the same object under `licence`:

```jsonc
"licence": { "payload": "…", "signature": "…", "key_id": "v1" }
```

so a provisioned terminal is licensed without anyone typing anything.

## 6. Claims mapping — the exact contract

Payload keys on the left of the client boundary must match
`LicenseClaims.fromJson` (`lib/features/licensing/domain/license.dart:84`)
exactly.

> **The payload keys use the American spelling `license_id`**, while every
> identifier in both codebases says `licence`. That is not a typo awaiting a fix
> — it is what installed tills parse. Changing it breaks every licence already
> issued.

| `pos_licences` column | Payload key | `LicenseClaims` field | Note |
|---|---|---|---|
| `licence_ref` | `license_id` | `licenseId` | required |
| `restaurant.slug` | `tenant_slug` | `tenantSlug` | **the client refuses a mismatch** → `tenantMismatch` |
| `restaurant.name` | `tenant_name` | `tenantName` | display only |
| `issued_at` | `issued_at` | `issuedAt` | ISO-8601. A clock before this yields `notYetValid` |
| `expires_at` | `expires_at` | `expiresAt` | ISO-8601 |
| `grace_days` | `grace_days` | `graceDays` | absent → 14 |
| `warn_days` | `warn_days` | `warnDays` | absent → 30 |
| `max_terminals` | `max_terminals` | `maxTerminals` | absent → 1 |
| `features` | `features` | `features` | `Feature` enum values |
| `modes` | `modes` | `modes` | **`DeploymentMode.wire` values** — `cloud`, `branch_server`, `standalone`. Not enum names, not labels |
| `branch_ids` | `branch_ids` | `branchIds` | `[]` = every branch |
| `fingerprints` | `fingerprints` | `fingerprints` | `[]` = unpinned |
| `plan.slug` | `plan` | `plan` | display only, nullable |
| `max_offline_days` | `max_offline_days` | **not read yet** | POS-BE-022 — see below |

**Two client-side gaps this contract creates. Both are Agent 1's to close before
integration, not the backend's:**

1. **`LicenseClaims` has no `max_offline_days`.** It must be added with the same
   tolerant `fromJson` treatment as its neighbours (absent → null → unlimited),
   so a licence minted after this lands is still readable by a till built before
   it. This is the single mechanism POS-BE-022 asked for; there must not be a
   second enforcement path.
2. **`modes` must never be emitted empty.** An empty array parses to an empty
   `Set<DeploymentMode>`, every mode then fails, and the terminal reports
   `modeNotLicensed` — which reads to the operator as a bricked till with no
   explanation. If a licence covers everything, emit all three explicitly. The
   issuer should reject an empty `modes[]` at validation.

## 7. Rules that are not negotiable

- **Idempotency.** Re-activating the same key returns the **byte-identical**
  stored `payload` and `signature`. Signing happens **once, at issuance** —
  never on activation. That is the reason the artifact is stored rather than
  minted on demand, and it is what makes the file, the download and the
  activation response provably the same document.
- **Revocation is weak, and the contract says so out loud.** A licence verified
  entirely offline cannot be recalled. `revoked_at` bites only when the till next
  reaches `/current` or `/bootstrap`; an islanded till keeps trading until its
  `max_offline_days` window closes. Real enforcement stays server-side on
  `feature:pos`, exactly as `docs/pos/09-licensing.md` §1 already states. **The
  dashboard copy must not imply a kill switch.**
- **Seat counting stays advisory** until POS-BE-016. The form sets
  `max_terminals`; nothing counts against it yet.
- **Exceeding the count warns, never refuses.** Restated here because refusing to
  register the sixth till mid-service is the "brick a POS" failure mode wearing a
  different hat.
- **Audit everything.** Issue, renew, revoke and **every activation attempt** are
  `AuditLogger::record()` events. Log `licence_ref` and `key_last_four`; **never**
  log the key or the hash.
- **Throttle `activate`** per IP *and* per key, mirroring the existing `login`
  limiter, which already caps per-IP and per-(identifier, IP).
- **The private key never leaves the issuer.** Not to a branch server, not to a
  till, not into an audit row.

## 8. Delivery — three paths, one artifact

| Mode | How the licence arrives | Renewal |
|---|---|---|
| Cloud | `POST /api/pos/licence/activate`, or embedded in the POS-BE-023 bootstrap bundle | automatic — the till re-reads at start-up and before each shift |
| Branch server | the box holds it; tills on the LAN read it from there | **once per site, not once per till** (POS-BE-017) — six tills is one renewal |
| Islanded | Super Admin downloads the `.xlic`; it travels by whatever means the site allows | re-import the file |

The third path is why the format is a signed file rather than an API response.
**It must work with no network at any point in its life.** That constraint is the
origin of every other decision in this document.

## 9. Super Admin UI (`apps/web`)

`src/pages/admin/pos/LicencesList.vue` + `LicenceForm.vue`, following the
`PlansList.vue` / `PlanForm.vue` anatomy exactly — `withMinDuration` +
`ListSkeleton`, `FormError` for server validation, `confirm()` for revoke,
`theme-indigo` tokens, `licence.*` i18n keys in **both** `en` and `ar`, route
gated with `meta.capability: 'licences.manage'`.

The only unusual element is the **shown-once key modal**: it must require an
explicit acknowledgement before it can be dismissed, because the key is
unrecoverable afterwards.

## 10. What flips on the POS side when this reaches `READY`

`lib/app/providers.dart:351` — `FakeLicenceService()` becomes
`DefaultLicenceService(...)` with the real `publicKeyBytes` and a `remote`
closure hitting `/api/pos/licence/activate`. Everything downstream —
verification, the grace policy, the renewal screen, the entitlement provider
invalidation — is already built and tested.

`FakeLicenceService` stays, for tests and for the `EXPIRED` / `GRACE` / `SOON`
demo keys that make the state table walkable without waiting a year.

## 11. Open questions for the owner

**Q1 — does a renewal reuse the activation key, or issue a new one?**
*Recommendation: reuse it.* A six-till site should not retype anything at renewal
— the till re-fetches and receives the new term. This is why `key_hash` is
indexed but **not unique**: a renewal writes a new row carrying the same
`key_hash`, and activation resolves to *the newest non-revoked, non-superseded
row for that hash*. (A partial unique index would express this better but is
engine-specific, and this codebase runs SQLite in dev and PostgreSQL in
production.) The `.xlic` path still needs a fresh file either way.

**Q2 — who besides `SUPER_ADMIN` may issue a licence?**
*Recommendation: nobody, for v1.* `SALES` is the obvious candidate later, but
issuing commercial entitlement is not a reversible action and the capability is
cheap to widen afterwards.

**Q3 — does anyone actually use `branch_ids` in v1?**
*Recommendation: always `[]`.* The column and the claim exist so the format never
has to change, but per-branch licensing is a commercial model nobody has asked
for yet. Ship the field, do not ship the UI for it.

*(2026-09-02 note: Q1, Q2 and Q3 are now adopted as agreed defaults — see the
"Agreed defaults" table at the top. Owner may still overrule.)*

---

## POS-BE-016 — seat counting · **READY**

- Counted server-side against the newest non-revoked licence's
  `max_terminals` (and `plans.max_terminals` where a plan governs, POS-BE-001).
- The unit counted is **claimed terminals per site** where a site exists
  (POS-BE-026), per tenant otherwise. `provisioned` rows do **not** count —
  only claimed ones (POS-BE-023's ask) — but they always appear in the fleet
  list.
- **Exceeding the count warns, never refuses.** The claim/register response
  carries `warnings: ["MAX_TERMINALS_EXCEEDED"]` with
  `details: { "licensed": 4, "claimed": 5 }`; the fleet views and the tenant
  dashboard surface the overage; nothing is blocked, ever, mid-service.
- Revoking a terminal frees its seat immediately.

**Schema:** none beyond `pos_terminals` (§023).

---

## POS-BE-017 — branch-server packaging · APPROVED

Contract-level agreement; this is an ops deliverable, not an endpoint. Agent 1's
reading — packaging, not new engineering — is confirmed: `docker-compose.yml`,
`Dockerfile` and dual SQLite/pgsql support already exist. The deliverables:

1. **Single-tenant provisioning profile** — a compose profile + seed path that
   stands up `apps/api` holding exactly one restaurant, seeded from the
   platform (never from `DatabaseSeeder`'s demo path).
2. **Backup routine** — scheduled `pg_dump` to a second medium with retention
   and a documented restore drill. Named the largest real risk in the request;
   agreed — it ships with the package, not after it.
3. **Update path** — versioned images, migrate-on-boot, documented rollback.
4. **Licence distribution** — the box holds the `.xlic`; LAN tills read licence
   state from it (POS-BE-015 §8): one renewal per site.

Per POS-BE-022: an **islanded branch server (no upstream) is not an offered
configuration** — `upstreamUrl` is required at setup. The regulatory question
(ETA / ZATCA clearing) stays flagged to the owner, unassessed by either agent;
it constrains packaging, not this contract.

---

## POS-BE-018 — upstream sync: branch server → platform · APPROVED

- The branch server drains to the platform through **the same
  `POST /api/pos/sync` as any till** (§021), authenticated by its **own device
  credential** issued when the site's main terminal claims (§011/§023), carrying
  orders, payments, shifts, cash movements and refunds.
- **Idempotency is POS-BE-007's contract, verbatim, on the same key.** The
  platform dedupes on `(restaurant_id, client_transaction_id)` — the identical
  index the branch box already enforces locally (`UNIQUE (restaurant_id,
  client_transaction_id)`, verified by Agent 1 against real PostgreSQL). No
  second mechanism exists on either side.
- Records forwarded upstream keep their original `client_transaction_id`,
  `acting_user_id`, timestamps and terminal attribution — the branch server is
  a relay, not an author. Invoice numbers assigned by the branch box are
  honoured upstream as-is (the box owns the branch's sequence; the platform
  does not re-issue for branch-server tenants).
- Wire shapes: **identical to §006/§009/§010/§021.** A branch database and the
  platform cannot diverge because they share one schema contract: integer minor
  units, `payments[]` as rows (BE-A01), one key.

**Schema:** none beyond what the other items define.

---

## POS-BE-019 — canonical error vocabulary · **READY**

Envelope on every `/api/pos/*` 4xx/5xx:
`{ "code": "…", "message": "…", "details": {}? }`. The client switches on
`code`; **an unrecognised code is retried, never discarded** — so this list can
grow freely and additions are never breaking.

**The one canonical list:**

| Code | HTTP | Meaning |
|---|---|---|
| `VALIDATION_FAILED` | 422 | request invalid; Laravel error bag in `details` |
| `IDEMPOTENCY_PAYLOAD_MISMATCH` | 422 | same key, different payload — client bug |
| `POS_FEATURE_DISABLED` | 403 | tenant lacks `feature:pos` → hold queue, retry later |
| `POS_CAPABILITY_MISSING` | 403 | `acting_user_id` lacks the verb (`details.capability`) → stop, tell manager |
| `SUBSCRIPTION_LAPSED` | 403 | **reserved** (D2 default: never emitted) → hold queue, billing banner |
| `BRANCH_NOT_IN_TENANT` | 404 | branch not resolvable in this tenant → quarantine record |
| `TERMINAL_REVOKED` | 403 | device known, revoked → refuse next sign-in/shift; **queued records still accepted for drain** (BE-A04) |
| `TERMINAL_NOT_FOUND` | 404 | unknown `terminal_id` |
| `DEVICE_TOKEN_INVALID` | 401 | unknown / rotated-out device token → re-pair |
| `SHIFT_NOT_OPEN` | 422 | write requires an open shift |
| `SHIFT_ALREADY_OPEN` | 422 | second open on one terminal |
| `CATALOG_STALE` | 422 | reserved — server may demand a catalog refresh before accepting a priced-offline order |
| `MENU_ITEM_NOT_FOUND` | 422 | line references an id that never existed in this tenant (deleted-during-outage lines use the `name_snapshot` fallback instead, §006) |
| `CUSTOMER_NOT_FOUND` | 422 | order references an unknown customer |
| `REFUND_EXCEEDS_SOLD` | 422 | cumulative refund quantity over sold quantity — **and, since 2026-09-22, cumulative refund MONEY over the order's total.** One code for both because the client's reaction is identical (stop; this refund is not valid) and because §019's own "retry an unrecognised code" rule makes a brand-new code for a permanent refusal a retry loop on any till that predates it. `details` names which check failed |
| `BATCH_TOO_LARGE` | 413 | §021 — over 100 elements; nothing processed |
| `PAIRING_CODE_INVALID` | 422 | unknown code (deliberately indistinguishable from wrong) |
| `PAIRING_CODE_EXPIRED` | 422 | known, past TTL → reissue from dashboard |
| `PAIRING_CODE_USED` | 422 | single-use code already consumed by a different device → *"this code was already used"* |
| `SETUP_SLUG_UNKNOWN` | 404 | no such tenant (honest 404 — never emitted for a transient fault) |
| `SETUP_SLUG_SUSPENDED` | 403 | tenant suspended |
| `SETUP_RATE_LIMITED` | 429 | setup-config / claim throttle |
| `CONFIG_VERSION_STALE` | 409 | client presented a `config_version` newer than the server's — split-brain signal, client keeps its cache |
| `SITE_ALREADY_REGISTERED` | 409 | branch has a different `server_id`; `details.server_id` + `details.registered_at` carry the existing one |
| `SITE_NOT_FOUND` | 404 | unknown `server_id` on `replace` |
| `TERMINAL_NAME_INVALID` | 422 | §028 — empty/overlong name |
| `LICENCE_TENANT_MISMATCH` | 422 | DIS-2's register check — the presented `licence_ref` does not belong to the resolved tenant; a setup mistake, the wizard tells the operator to check the licence/slug. **Uppercase — deliberately collides in name with the grandfathered lowercase `licence_tenant_mismatch` on activation (the DIS-4 situation); the client carries both casings knowingly** |
| `LICENCE_SITE_MISMATCH` | 422 | licence's `server_id` claim names a different site — a site-pin violation (§027), never emitted for the register ref check |
| `licence_not_found` / `licence_revoked` / `licence_tenant_mismatch` / `licence_superseded` | 4xx | **grandfathered lowercase** — shipped in POS-BE-015, never migrated (DIS-4). Note `licence_tenant_mismatch` (activation) and `LICENCE_TENANT_MISMATCH` (site register, above) are distinct codes differing only in case |

`TOTALS_MISMATCH` is **not** an error code: a mismatched order is created and
the marker rides the `201` (§006).

---

## POS-BE-020 — server time · **READY**

`server_time` (ISO 8601, UTC) is emitted on: the bootstrap bundle, the setup
config and its `/version` probe, the heartbeat response, and `POST
/api/pos/sync` responses. The `Date` header is additionally reliable on every
`/api/pos/*` response.

Agreed storage rule, restated as contract: **client timestamps are never
silently overwritten.** `occurred_at`-class fields are stored as sent;
`received_at` is stored beside them; reporting decides. A till with measured
skew stamps outgoing records with `clock_offset_seconds` in its heartbeat, and
the server records it on `pos_terminals` — correction is a reporting concern,
never a mutation.

---

## POS-BE-021 — bulk drain: `POST /api/pos/sync` · APPROVED

**Auth:** device token + `feature:pos`.

**Request:**

```jsonc
{ "customers": [ … ],        // §014 shapes
  "shifts": [ … ],           // §009 open/close shapes (close carries its own key)
  "orders": [ … ],           // §006 shapes
  "payments": [ … ],         // §006-P shapes (settle-later rows)
  "cash_movements": [ … ],   // §009 shapes
  "refunds": [ … ] }         // §010 shapes
```

**Rules:**

- **Bound: 100 elements per request**, counted across all arrays combined
  (decision j). 101+ → `413 BATCH_TOO_LARGE`, **nothing processed** — the bound
  is checked before any element, so the client chunks deterministically.
- Processing order inside one request: `customers → shifts(open) → orders →
  payments → cash_movements → refunds → shifts(close)` — every reference a
  later element makes to an earlier one (by `client_transaction_id`) resolves
  within the batch.
- **One element failing never fails the batch.** Each element succeeds or fails
  alone, with POS-BE-007 idempotency per element.

**Response `200`** (always 200 when the batch itself was processable):

```jsonc
{ "server_time": "…",
  "results": [
    { "client_transaction_id": "…", "type": "order", "status": "created",
      "id": 8814, "invoice_number": "MAADI-2026-001042",
      "settlement_status": "PAID" },
    { "client_transaction_id": "…", "type": "order", "status": "duplicate",
      "id": 8813, "invoice_number": "MAADI-2026-001041" },   // same body as first time
    { "client_transaction_id": "…", "type": "refund", "status": "rejected",
      "code": "REFUND_EXCEEDS_SOLD", "message": "…" } ] }
```

- `duplicate` carries the **same id and invoice number** as the original
  response — a replayed batch is harmless.
- `rejected` carries a §019 code; the client re-queues or quarantines per that
  code's rule and re-submits only what was rejected.
- Serial single-POST drain remains fully supported; this endpoint is an
  optimisation, not a requirement.

**Schema:** none beyond the aggregates' own.

---

## POS-BE-022 — fleet registry + heartbeat · **READY**

**Heartbeat** — `POST /api/pos/terminals/heartbeat`, **device token** (Option C
makes the `pos.operate` alternative unnecessary: the terminal authenticates
itself, no cashier needs to be signed in for a till to be alive). Not queued,
not replayed; last write wins; carries no money.

**Request:** accepted exactly as proposed:

```jsonc
{ "terminal_id": "…uuid…", "app_version": "1.4.2", "platform": "windows",
  "deployment_mode": "cloud", "sync_policy": "manual",
  "pending_count": 37, "oldest_pending_at": "2026-08-26T09:14:00Z",
  "shift_open": true, "licence_expires_at": "2026-12-31",
  "clock_offset_seconds": -4, "last_catalog_sync_at": "2026-08-26T08:02:00Z" }
```

**Response `200`** — decision (c), accepted as Agent 1 proposed, five fields:

```jsonc
{ "server_time": "2026-09-02T09:00:01Z",
  "site_last_contact_at": "2026-09-02T08:55:00Z",   // null when no site (cloud)
  "licence_expires_at": "2027-09-01T00:00:00Z",     // null when no licence on record
  "config_version": 7,
  "terminal_status": "active" }                      // active | stale | revoked
```

One heartbeat therefore serves clock skew (POS-BE-020), the offline window,
the renewal banner, config-change detection (replaces polling POS-BE-025's
`/version`), and revocation discovery. `terminal_status: "revoked"` follows
BE-A04: refuse next sign-in and next shift, never cut the open one, keep
accepting queued records for drain.

**Fleet views** (Super Admin, `Capability`-gated — a new
`Capability::POS_FLEET_VIEW = 'pos_fleet.view'`, SUPER_ADMIN via `Gate::before`,
grantable to `SUPPORT` later):

| Method | Endpoint | Purpose |
|---|---|---|
| `GET` | `/api/admin/pos/terminals` | cross-tenant list; filter/sort by restaurant, branch, last seen, pending count, licence status |
| `GET` | `/api/admin/pos/terminals/{id}` | one terminal + heartbeat history |
| `GET` | `/api/admin/pos/sites` | site tier (POS-BE-026) |

These reads are **deliberately cross-tenant** — same posture as the licence
admin reads, stated in the controller and audited, never incidental.
`pending_count` + `oldest_pending_at` surface as the headline columns: unsynced
money per till, in real time.

Deployment consequences recorded 2026-08-26 (mandatory check-in window via the
`max_offline_days` claim, `upstreamUrl` required, no online-required mode,
catalog authored in the cloud only) are **accepted as constraints on the
backend contracts** — one enforcement path, through the licence.

**Amendment 2026-09-06 — "catalog authored in the cloud only" now reads "on a
cloud terminal".** `DeploymentMode.offline` authors its menu, floor and money
rules locally, because an offline restaurant has no dashboard to author them in.
**Nothing on the backend changes:** an offline till never sends a catalogue and
the platform is never asked to reconcile one. The constraint still holds for
every terminal the fleet views can see, which is every cloud terminal.

**Schema:** `pos_terminals` heartbeat columns — `last_seen_at, app_version,
platform, deployment_mode, sync_policy, pending_count, oldest_pending_at,
shift_open, clock_offset_seconds, last_catalog_sync_at,
reported_licence_expires_at` — plus an optional `pos_terminal_heartbeats`
history table (retention-pruned). Additive.

---

## POS-BE-023 — provisioning, claim, bootstrap · **READY**

Registration direction inverted, as the owner required: **the platform
provisions, the till claims.** Path A (pairing code) is the default; Path B
(manual credentials) is the fallback — Agent 1's security recommendation is
adopted, including that **Path B accepts any staff account holding
`pos.provision`**, not only the owner.

**Endpoints:**

| Method | Endpoint | Auth | Purpose |
|---|---|---|---|
| `POST` | `/api/dashboard/pos/terminals` | JWT + `feature:pos` + `can:pos.provision` | provision (state `provisioned`) |
| `POST` | `/api/dashboard/pos/terminals/{id}/pairing-code` | same | issue / regenerate code (regenerating kills the old one) |
| `DELETE` | `/api/dashboard/pos/terminals/{id}` | same | revoke (BE-A04 semantics) |
| `GET` | `/api/dashboard/pos/terminals` | JWT + `feature:pos` + `can:pos.provision` | tenant's own fleet |
| `POST` | `/api/pos/terminals/claim` | **none** — code is the credential; throttled | Path A |
| `POST` | `/api/pos/terminals/register` | JWT (staff with `pos.provision`) + `feature:pos` | Path B |
| `GET` | `/api/pos/bootstrap` | device token | the full bundle |

**Amendment, owner decision 2026-09-05 — the platform-side front door.** The
same provisioning path is now reachable by a Super Admin standing on a client's
page, because creating a client creates the client and its licence and **no
terminal at all**. Nothing on the wire changes: these rows are byte-identical
to dashboard-provisioned ones, go through the same `PosProvisioningService`, and
claim through the same unauthenticated `POST /api/pos/terminals/claim`.

| Method | Endpoint | Auth | Purpose |
|---|---|---|---|
| `GET` | `/api/admin/restaurants/{restaurant}/terminals` | JWT + `can:pos_fleet.view` | one client's fleet |
| `POST` | `/api/admin/restaurants/{restaurant}/terminals` | JWT + `can:pos_fleet.manage` | provision (state `provisioned`) |
| `POST` | `/api/admin/restaurants/{restaurant}/terminals/{terminal}/pairing-code` | same | issue / regenerate code |
| `POST` | `/api/admin/restaurants/{restaurant}/terminals/{terminal}/revoke` | same | revoke (BE-A04 semantics) |

**What Agent 1 must not assume:** a tenant that exists, is licensed, and has
**zero terminals** is a normal, expected state — it is what every newly created
client looks like until someone installs a till. A setup wizard must treat an
empty fleet as "nothing paired yet", never as a broken or half-provisioned
tenant.

**Pairing code (decision l):** 8 Crockford base32 characters, displayed
`XXXX-XXXX` (same alphabet and normalisation as licence keys — uppercase, strip
hyphens, fold Arabic-Indic digits). **HMAC-SHA256 hashed at rest** (keyed with
`APP_KEY`), **single-use**, **TTL 24 h**, never logged. `claim` is throttled per
IP **and** per slug, mirroring the `login` limiter's two-axis pattern →
`429 SETUP_RATE_LIMITED`.

**Claim — `POST /api/pos/terminals/claim`:**

```jsonc
// request
{ "tenant_slug": "demo", "pairing_code": "7K2Q9WXM",
  "platform": "windows", "app_version": "1.4.2",
  "fingerprint": "sha256:…" }
// 200
{ "device_token": "xdt_…64 hex…",                    // §011 — shown here and at rotation only
  "terminal": { "id": "…uuid…", "name": "Bar 1", "branch_id": 3,
                "deployment_mode": "cloud", "sync_policy": "dynamic",
                "state": "active" },
  "warnings": [],                                     // e.g. ["MAX_TERMINALS_EXCEEDED"] (§016)
  "bootstrap": { … the full bundle below … } }
```

- Tenant resolved **from the code**, never from input beyond the slug
  disambiguator; `TenantContext::overrideId()` released in `finally`.
- **Idempotent per code within its TTL:** the full response (device token
  included) is stored encrypted (`Crypt::encryptString`) against the code row
  and returned byte-identically on replay, then purged at code expiry. A timed-
  out claim that retries gets the same terminal and the same credential, never
  a second terminal.
- Distinct failures: `PAIRING_CODE_INVALID` / `PAIRING_CODE_EXPIRED` /
  `PAIRING_CODE_USED` (§019) — "already used" is only emitted to a *different*
  device (fingerprint mismatch); the same device replaying gets the cached
  success.
- Claim and revoke are `AuditLogger::record()` events. Claiming flips
  `provisioned → active` and starts counting toward seats (§016).

**Register (Path B) — `POST /api/pos/terminals/register`:** authenticated staff
call; creates the terminal row (state `active`) and returns the identical
response shape, device token included, idempotent on a client-supplied
`client_transaction_id`. The staff JWT is used for this one call and never
stored by the till.

**The bootstrap bundle — `GET /api/pos/bootstrap`** (final shape, decision l;
supersedes any separate `/api/pos/config`):

```jsonc
{ "config_version": 7, "synced_at": "…", "server_time": "…",   // POS-BE-020/025
  "terminal":  { "id", "name", "branch_id", "deployment_mode", "sync_policy" },
  "restaurant": { "id", "name", "slug", "tax_registration_number",
                  "currency": "EGP", "exponent": 2,            // mandatory (A7)
                  "timezone", "default_language" },
  "branches":  [ { "id", "code", "name", "supported_order_types" } ],   // POS-BE-005
  "tables":    [ { "id", "branch_id", "label", "seats", "area_name",
                   "is_active" } ],          // terminal's branch floor (2026-09-02 amendment)
  "receipt_profiles": [ { … one per ACTIVE branch … } ],  // A3, 2026-09-22 — new key, see below
  "catalog":   {                             // POS-BE-003/012 (b) — frozen normalized shape:
                 // items: integer price_minor / discounted_price_minor + the
                 // COMPLETE resolved option_group_ids; groups deduplicated in
                 // option_groups.data, options carry integer price_delta_minor.
                 "categories": { "data": [], "deleted_ids": [], "complete": true },
                 "items":      { "data": [], "deleted_ids": [], "complete": true },
                 "option_groups": { "data": [ /* populated */ ], "deleted_ids": [], "complete": false } },
  "money":     { "tax_rules": [], "charges": [], "tender_types": [] },  // POS-BE-013
  "invoice":   { "prefix_source": "branch_code", "padding": 6, "reset": "yearly" }, // POS-BE-008
  "endpoints": { "base_url", "verify_tls",
                 "database_host", "database_name", "database_user",
                 "database_port" },                            // DIS-1: HERE, not pre-auth
  "pos":       { "sync_policy", "rounding", "lock_after_seconds", "shift_required" },
  "modules":   ["pos"],                                        // never empty
  "printers":  [ { "role", "transport", "host", "port", "copies" } ],
  "branding":  { "display_name", "logo_url", "accent_hex" },
  "staff":     [ { "id", "name", "username", "role_id", "capabilities": [],
                   "is_active": true,
                   "pin": { "algorithm": "pbkdf2_sha256", "iterations": 120000,
                            "salt": "…", "hash": "…" } } ],             // POS-BE-024 (null when unset)
  "licence":   { "payload", "signature", "key_id" } }                   // POS-BE-015
```

- `staff[]` is scoped **by hand** (`User` has no `RestaurantScope`) following
  the `Dashboard\StaffController` pattern; only active staff; `pin_hash` is
  `null` for staff with no PIN set (they cannot sign in offline).
- Supports `If-None-Match` → `304`; emits `ETag` and `X-Config-Version` —
  advisory, `config_version` is the sole precedence signal (§025).
- The bundle is complete enough to open, sell, authenticate cashiers and close
  a shift with no further contact — that is its acceptance test.

### Amendment 2026-09-22 (A3) — `receipt_profiles[]`, a new frozen key

The bundle carried `invoice{}` and `branding{}` but nothing that said **who the
receipt says sold the food**, so every cloud till printed with compiled-in
defaults. The platform is now the author of that (CB-08's platform half), and it
travels as its own key. Frozen bundle keys are additive, so this is a new key
and nothing existing changed shape.

```jsonc
"receipt_profiles": [
  { "branch_id": 3,
    "trade_name": "Koshary House LLC",  // '' ⇒ never: falls back to the restaurant's name
    "registration_number": "123456789", // the TAXPAYER's — restaurants.tax_registration_number
    "activity_code": "5610",            // ETA's four-digit activity code
    "branch_code": "0042",              // ETA's branch code — NOT branches.code / the invoice prefix
    "country": "EG",                    // two-letter ISO, never blank
    "governate": "Cairo",               // ETA's spelling, deliberately
    "region_city": "Maadi",
    "street": "Road 9",
    "building_number": "12",
    "postal_code": "", "floor": "", "room": "", "landmark": "",
    "additional_info": "",              // the till's column name, not "additional_information"
    "phone": "+201000000001",           // '' ⇒ falls back to branches.phone
    "header_note": "Welcome",           // nullable — genuinely absent, not empty
    "footer_note": "Wifi: guest",       // nullable
    "revision": 3 } ]                   // 0 = nobody has authored this branch yet
```

- **The field names are the till's `pos_receipt_profiles` columns, one for one**
  (`xorder-pos/lib/data/postgres/migrations.dart`), in snake_case, so the
  bootstrap seeder is a straight mapping with no translation table.
- **One row per ACTIVE branch, authored or not.** A branch nobody has typed yet
  is projected from what the platform knows (restaurant name, restaurant tax
  registration number, `country: "EG"`, empty strings, `revision: 0`) — a
  missing row would send that till back to its defaults, which is the whole bug.
  Inactive branches are omitted, exactly like the `branches` block.
- **Empty strings, not nulls**, on every text field except the two notes: the
  till's columns are `NOT NULL DEFAULT ''`, so the seeder needs no null
  handling. `header_note` / `footer_note` are nullable on both sides.
- **`registration_number` is the restaurant's, not the branch's.** One taxpayer
  has one number; a per-branch copy would be a second author of one row. It is
  stored on `restaurants.tax_registration_number` (the same value the bundle's
  `restaurant.tax_registration_number` has always carried) and projected into
  every profile.
- **`branch_code` is not `branches.code`.** `branches.code` is the invoice
  prefix and the restaurant chooses it; `branch_code` is what the tax authority
  registered. They are allowed to differ and usually do. The dashboard form says
  so in both languages.
- **Authored on the dashboard** at `GET /api/dashboard/receipt-profiles` and
  `PUT /api/dashboard/receipt-profiles/{branch}`, gated
  `feature:pos` + `can:settings.view` (+ `can:settings.update` and
  `subscription.writable` to write) — the same gate pair as the POS money
  config, because the legal identity on a slip is settings work of exactly the
  same class as the tax registration number `settings.update` already authors.
  Cross-tenant branch → **404**. Page: `apps/web/.../PosReceiptView.vue`, under
  Settings → Point of sale → Receipt details, EN + AR.
- **Every write bumps `pos_config_version`** (a `PosConfigVersion` model hook on
  `ReceiptProfile`, plus an explicit bump when the restaurant's tax registration
  number changes), so the next heartbeat tells every till to re-pull.
- **`revision` is server-managed**: it increments on each save, and the PUT
  accepts an optional `revision` so a stale save is refused with `409` instead
  of overwriting whoever saved first — the same guard the till has for an office
  and a counter editing one profile.
- **What the platform does NOT decide:** whether a profile is complete enough to
  print or to file. The till's `ReceiptProfile.printProblems` /
  `.filingProblems` keep that judgement, where the receipt and the submission
  are; the platform validates shape only (four-digit activity code, two-letter
  country) and lets a half-typed profile save, because that is how one is filled
  in.
- **Print LAYOUT preferences are not here.** CB-08's ruling splits the legal
  identity (platform) from how a given printer lays it out (till). This key is
  the identity half only.

**Schema:** `pos_terminals` — `id, restaurant_id, branch_id, terminal_id (uuid,
unique(restaurant_id, terminal_id)), name, state
(provisioned|active|revoked), platform?, app_version?, fingerprint?,
deployment_mode, sync_policy, device_token_hash?, previous_token_hash?,
device_token_rotated_at?, pos_site_id?, claimed_at?, revoked_at?, heartbeat
columns (§022), timestamps` — `BelongsToRestaurant`, `Auditable`.
`pos_pairing_codes` — `id, restaurant_id, pos_terminal_id, code_hash (indexed),
expires_at, used_at?, used_fingerprint?, response_cache (text, encrypted,
purged at expiry), created_by_id, timestamps`. Additive.

---

## POS-BE-024 — POS PIN credential · **READY**

Every ask adopted, with the algorithm decided:

- **`users.pos_pin_salt` + `users.pos_pin_hash`** — nullable strings (base64
  pair), **never in `$fillable`**, set only via `forceFill` in the PIN
  controller, the same discipline as `users.role` and `users.restaurant_id`;
  `UserResource` never serialises them.
- **Hash algorithm: PBKDF2-HMAC-SHA256, 120000 iterations, 16-byte salt,
  32-byte key** (amended 2026-09-02 from the earlier bcrypt pick, at Agent
  1's request — the Flutter client ships a tested PBKDF2 verifier and stores
  (salt, hash) base64 pairs; bcrypt would have added a Dart dependency for no
  security gain at a 4–6 digit keyspace). Wire shape inside `staff[]`:

  ```jsonc
  "pin": { "algorithm": "pbkdf2_sha256", "iterations": 120000,
           "salt": "…base64…", "hash": "…base64…" }   // null when no PIN set
  ```
- **PIN:** 4–6 ASCII digits, validated server-side on set. Stated plainly: a
  digit PIN is offline-brute-forceable from a stolen hash regardless of
  algorithm — the containment is that it opens *only the till*: it is never
  accepted by login, never opens the dashboard, and clearing it (set to null)
  locks the cashier out of every till at that till's next sync without touching
  dashboard access.
- **Set / reset:** dashboard staff form — `PUT /api/dashboard/staff/{staff}/pin`
  `{ "pin": "482913" }` and `DELETE …/pin` to clear; `can:staff.update`, or any
  user on their own row. Write-only: the API returns `pin_set: true|false` and
  nothing else, ever. Both are audited (action, never the PIN) and both bump
  `config_version` so tills refresh.
- **Delivery:** exactly one path — the bootstrap `staff[].pin_hash`, behind the
  device credential (§023). Not in the setup config (§025 explicitly excludes
  the staff block), not in any dashboard response.
- **Till behaviour** (recorded as agreed): local verify, rate-limited attempts,
  lockout after 5 failures, attribution by user id; the PIN itself never
  travels on any wire, in either direction, after being set.

**Schema:** one nullable column on `users`. Additive.

---

## POS-BE-025 — pre-auth setup config · APPROVED

Accepted as **a redacted projection of the bootstrap bundle** (decision d) —
same document, same `config_version`, different auth, different moment. One
carve-out: **DIS-1** (no database block pre-auth).

**Endpoints** (unauthenticated, throttled per IP **and** per slug →
`429 SETUP_RATE_LIMITED`):

| Method | Endpoint | Purpose |
|---|---|---|
| `GET` | `/api/pos/setup/config/{slug}` | the redacted bundle |
| `GET` | `/api/pos/setup/config/{slug}/version` | ~80-byte probe |

```jsonc
// GET /api/pos/setup/config/{slug}/version
{ "config_version": 7, "last_updated_at": "2026-09-02T09:00:00Z",
  "server_time": "2026-09-02T09:00:01Z" }
```

```jsonc
// GET /api/pos/setup/config/{slug}
{ "config_version": 7, "last_updated_at": "…", "server_time": "…",
  "tenant":   { "id", "slug", "name", "tax_registration_number",
                "currency": "EGP", "exponent": 2,               // mandatory
                "timezone", "default_language" },
  "branches": [ { "id", "code", "name", "supported_order_types" } ],
  "endpoints":{ "base_url", "verify_tls" },                     // DIS-1 — no database_*
  "pos":      { "sync_policy", "rounding", "invoice_prefix_source" },
  "modules":  ["pos"],                                          // NEVER emitted empty — validated at emit
  "features": { "pos": true },
  "money":    { "tax_rules": [], "charges": [], "tender_types": [] },  // POS-BE-013 lives here too
  "printers": [ { "role", "transport", "host", "port", "copies" } ],
  "app":      { "lock_after_seconds", "shift_required" },
  "branding": { "display_name", "logo_url", "accent_hex" },
  "licence":  { "payload", "signature", "key_id" } }            // ONLY if fingerprint-bound to the caller
```

**Redaction, restated as contract:** **no `staff` block ever** (therefore no
`pos_pin_hash` on this path), no device credential, no licence unless the
licence's non-empty `fingerprints[]` matches the `terminal_fingerprint` query
parameter presented.

**`config_version` — the agreed semantics:**

- One **monotonically increasing, never-reused, never-reset** unsigned integer
  per tenant: `restaurants.pos_config_version`, incremented in exactly one
  service method, called by every write that changes the bundle: branches,
  tax rules / charges / tender types, printers/pos/branding settings, PIN
  set/clear, staff role changes, terminal provision/revoke/rename, licence
  issue/renew/revoke, currency or tax-id change.
- It is the client's **sole precedence signal**: accept iff
  `incoming > cached`; a lower value is a rollback and is refused.
- `last_updated_at` and `ETag` are **advisory only**; `If-None-Match` → `304`
  honoured; `ETag` + `X-Config-Version` headers emitted on both this endpoint
  and `/api/pos/bootstrap`.

**Errors:** `SETUP_SLUG_UNKNOWN` (404 — emitted **only** when the slug truly
does not resolve, never for a transient fault; an internal error is a 500, so
the client's two-consecutive-404s "slug renamed" heuristic stays safe),
`SETUP_SLUG_SUSPENDED` (403), `SETUP_RATE_LIMITED` (429).

**Schema:** `restaurants.pos_config_version` unsigned bigint default 1;
settings storage for `pos`/`printers`/`branding` blocks (tenant-scoped
`pos_settings` json or columns — implementation's choice, wire shape is the
contract). Additive.

---

## POS-BE-026 — site registration + `ServerId` · APPROVED

Accepted with the identity model as designed: `server_id` names the **site's
database**, `server_installation_id` names the box currently hosting it —
hardware replacement changes one column, never a licence. Plus **DIS-2**
(`licence_ref` required on register).

**Endpoints:**

| Method | Endpoint | Auth | Purpose |
|---|---|---|---|
| `POST` | `/api/pos/sites/register` | none — throttled per IP + per slug; carries `licence_ref` (DIS-2) | claim a site |
| `POST` | `/api/pos/sites/{server_id}/replace` | device token of the site's main terminal, or JWT + `can:settings.update` | move to new hardware — audited |
| `GET` | `/api/admin/pos/sites` | `can:pos_fleet.view` | Super Admin, cross-tenant (§022) |

```jsonc
// POST /api/pos/sites/register
{ "tenant_slug": "demo", "branch_id": 3,
  "server_id": "…uuid…", "server_installation_id": "…uuid…",
  "licence_ref": "LIC-2026-0007",                    // DIS-2
  "app_version": "1.4.2", "platform": "macos" }
// 201 (or 200 on idempotent replay)
{ "site": { "server_id": "…uuid…", "branch_id": 3,
            "registered_at": "2026-09-02T10:00:00Z" },
  "allowed_terminal_count": 4, "server_time": "…" }
```

**The agreed semantics (decision e):**

- **Idempotent on `(restaurant_id, branch_id, server_id)`** — a timed-out
  registration that retries returns the same site (`200`), never a second row.
- A call with a **different** `server_id` for an already-registered branch →
  `409 SITE_ALREADY_REGISTERED` with `details.server_id` and
  `details.registered_at`, so the wizard can say *"this branch already has a
  main device, registered …"*. Replacing hardware is the deliberate, audited
  `replace` call — never an accident of retyping.
- **Registration is never a precondition.** A site with no uplink at install
  finishes setup and registers at first contact; nothing anywhere in this
  contract set requires a registered site to function.
- **Two distinct licence failures, two distinct codes (agreed 2026-09-02):**
  the presented `licence_ref` not belonging to the resolved tenant →
  `422 LICENCE_TENANT_MISMATCH` (a setup mistake — check the licence/slug);
  a licence whose `server_id` claim names a different site →
  `422 LICENCE_SITE_MISMATCH` (a site-pin violation, §027). Never conflated.
- `register` and `replace` are `AuditLogger::record()` events.
- Seat counting (§016) counts claimed terminals per site where a site exists.

**Schema:** `pos_sites` — `id, restaurant_id, branch_id, server_id (uuid,
unique(restaurant_id, branch_id, server_id)), server_installation_id,
licence_ref?, app_version?, platform?, registered_at, replaced_at?,
last_contact_at?, timestamps` — `BelongsToRestaurant`, `Auditable`;
`pos_terminals.pos_site_id` nullable FK. Additive.

---

## POS-BE-027 — three additive licence claims · APPROVED

Amends POS-BE-015 (`READY`); nothing else about it changes. Verified against
`LicenceIssuer::claims()` before agreeing:

| Claim | Status in code today | Contract |
|---|---|---|
| `max_offline_days` | **already emitted** (int or null; null = unlimited) | no backend change; the client now reads it (closed 2026-08-28) |
| `license_version` | not emitted | added to newly minted payloads, literal `1`. **Schema version of the claims object, not a generation counter.** Absent → 1 |
| `server_id` | not emitted | added to newly minted payloads when the issuing form pins a site; else `null`. Absent/null = not site-pinned (same semantics as empty `fingerprints[]`) |

- **Nothing is re-signed and nothing may be invalidated.** Stored `payload` /
  `signature` are verbatim and untouched; only *newly minted* payloads carry
  the new keys. The client's tolerant `fromJson` defaults make every
  combination of old/new file and old/new till mutually readable — confirmed
  compatible with the signed-fixture test Agent 1 added 2026-08-28.
- Client semantics recorded as agreed: window elapsed →
  `offlineWindowExpired` ≡ `expired` (next shift blocked, open one never cut,
  cash-up/reprint/export never gated — the single POS-BE-022 mechanism);
  `server_id` mismatch → `siteMismatch` (`LICENCE_SITE_MISMATCH` server-side);
  unknown higher `license_version` → evaluate what is understood, attach a
  notice, **never deny**.
- Issuer form gains optional `max_offline_days` (already has it) and optional
  `server_id` pin; `licence.*` i18n strings extended in both languages.
- **Separate offline certificate: declined by both agents — DIS-3.** On the
  owner's desk, jointly.

**Schema:** `pos_licences.server_id` nullable uuid column (so the pin is
queryable, not only inside the payload). Additive.

---

## POS-BE-028 — terminal rename · APPROVED

`PATCH /api/pos/terminals/{terminal_id}` `{ "name": "Bar 2" }` → `200` with the
terminal object.

- **Auth:** JWT + `feature:pos` + `can:pos.provision` (dashboard), **or** the
  device token **for its own row only**.
- **Validation:** free text, trimmed, non-empty, ≤ 60 chars →
  `422 TERMINAL_NAME_INVALID`. Uniqueness per branch is **advisory**: a
  duplicate succeeds and the response carries
  `warnings: ["NAME_NOT_UNIQUE_IN_BRANCH"]` — untidy is not an error.
- **Renaming never touches `terminal_id`, `server_id`, the device token, or any
  credential or history.** That is the entire point of the item, and it is a
  contract guarantee: no code path may regenerate identity on rename.
- `AuditLogger::record()` on every rename.

**Schema:** none (`pos_terminals.name` already exists in §023).

---

## POS-BE-030 — purchasing and stock on cloud are platform-authored · **READY** (platform half)

Agreed as filed in `POS_TO_BACKEND.md`; owner go 2026-09-13, "finish all phases"
(CB-09).

- **Bundle:** `PosBootstrapService::staff()` removes `purchase.manage` from
  every `staff[].capabilities`, unconditionally. That includes the owner, and
  it doesn't depend on whether the client has the `purchasing` feature.
  `/api/auth/me` still returns it, because the capability is real on the
  dashboard. Test: `tests/Feature/Pos/PosPurchaseCapabilityWithheldTest.php`.
- **Authoring:** suppliers, units, stock items, purchase orders, receiving,
  supplier invoices and supplier payments are written only through the
  dashboard, under `feature:purchasing` + `can:purchase.manage` (CB-09 slices
  a–c). `purchasing` is a plan feature of its own and does not require `pos`.
- **Wire:** unchanged. The platform reads nothing from till purchasing.
- **Where it lives:** `feat/cb-09-purchasing` in xorder-new (slice a `dd9a530`
  and later). Not deployed; it follows Cloud Wave 1 to production.

**Schema:** none for this contract. The purchasing tables are dashboard-only
and are never sent to a till.

---

## REVISION R1 — order-line bilingual name freeze · **PROPOSED** (amends §006, §010, §023)

**Spec:** `docs/coordination/REVISION_ORDER_ITEM_ID.md`. **Owner decision being
specced:** the POS sends the item **id** (it already does); the backend resolves
the item at order-creation time and **freezes both `name_ar` and `name_en`** onto
the line as a snapshot; the dashboard localises by the current UI locale.
Additive-only, deploy-safe, no live rows rewritten.

### R1.1 What is true today (verified 2026-09-27)

- The POS wire **already carries** `lines[].menu_item_id` (nullable) and
  `lines[].name_snapshot` (`required_without:menu_item_id`) — §006 is unchanged
  on the request side.
- `PosPricingEngine::price()` resolves the item by id (`MenuItem::withTrashed()
  ->whereIn('id', …)`) and today sets a **single** `name` where the client
  `name_snapshot` **wins** over the resolved item, else `name_en ?: name_ar`.
- `order_items` stores one `name` string; **no `name_ar`/`name_en` columns
  exist**. The catalog the till holds is already bilingual and keyed by the real
  `menu_items.id` (POS-BE-023 bootstrap emits `id` + `name_en` + `name_ar`).
- The public/QR path stores only `name` (diner-locale) and **no** `menu_item_id`.

### R1.2 Agreed cloud→POS wire shape

**Request line — no accepted-field change.** `name_snapshot` is **downgraded to a
fallback**: used only when `menu_item_id` does not resolve. It stays
`required_without:menu_item_id`.

```jsonc
"lines": [
  { "client_line_id": "L1",
    "menu_item_id": 101,                 // == menu_items.id; nullable
    "variant_option_id": 555,
    "option_ids": [710, 712],
    "quantity": 2,
    "note": "no onions",
    "name_snapshot": "Classic Burger",   // FALLBACK ONLY now — ignored for naming
                                         // when menu_item_id resolves (server freezes
                                         // name_ar/name_en from the item).
    "unit_price_minor": 9500,            // asserted; used only in client_asserted fallback
    "discount": { … }, "price_override": { … } } ]
```

**Response line — expanded.** Every `lines[]` element in the §006 order response,
the §010 refund response, `PosOrderResource`, `OrderRoundResource`, and the legacy
`orders.items` JSON gains `name_ar` + `name_en`; **`name` is kept** for back-compat.

```jsonc
"lines": [
  { "id": 1, "menu_item_id": 101, "client_line_id": "L1",
    "refunded_quantity": 0,
    "name":    "Classic Burger",         // back-compat (EN-preferred, or the snapshot fallback)
    "name_ar": "برجر كلاسيك",             // NEW — frozen from the resolved item at creation
    "name_en": "Classic Burger",         // NEW — frozen from the resolved item at creation
    "quantity": 2, "unit_price_minor": 9500,
    "line_total_minor": 19000, "price_source": "server" } ]
```

**Freeze rule (server = naming authority for resolvable items):**

| Case | `name_ar` | `name_en` | `name` (legacy) | `price_source` |
|---|---|---|---|---|
| item resolves (`!null && !trashed`) | `item->name_ar` | `item->name_en` | `name_en ?: name_ar` | `server` |
| id null / trashed (deleted in outage, open-price, combo) | `name_snapshot ?? __('xorder.pos.unknown_item')` | same | same | `client_asserted` |

On the `client_asserted` fallback `name == name_ar == name_en == name_snapshot`
(the single string the till printed). This is **English-only today** because the
till sends only `Product.nameEn` as `name_snapshot` — see the desktop ask R1-A1.

**Fallback is accept, never reject.** A line whose `menu_item_id` no longer
resolves is still recorded from `name_snapshot` (money was taken at the counter),
flagged `client_asserted` — unchanged §006 behaviour. `MENU_ITEM_NOT_FOUND` stays
reserved for an id that never existed in this tenant.

**Public / QR path (Minimum, this revision):** without a menu-SPA change, write
the single diner-provided `name` into **all three** columns (`name = name_ar =
name_en`). The fuller unification (menu SPA sends `menu_item_id`) is a separate
follow-up, not this revision.

### R1.3 Schema (additive-only)

- `order_items`: add `name_ar` (string, nullable), `name_en` (string, nullable).
  New migration, e.g. `2026_09_2x_000000_add_name_ar_en_to_order_items_table.php`.
  `menu_item_id` already exists (`2026_09_02_000100`). No `NOT NULL`, no backfill.
- Legacy `orders.items` JSON (cast `array` on `Order`): each element gains
  `name_ar` + `name_en` alongside `name`. No schema change (JSON column).

### R1.4 Ordered CLOUD implementation plan (each step independently shippable)

1. **Migration** — add `order_items.name_ar` + `name_en` (nullable). Add both to
   the `OrderItem` write path consistently with `menu_item_id` (i.e. via the same
   `forceFill` block, or add to `$fillable`). No behaviour change on deploy.
2. **`PosPricingEngine::price()`** — on the resolved branch, set
   `name_ar = $item->name_ar`, `name_en = $item->name_en`, `name = $item->name_en
   ?: $item->name_ar`; **drop** the `$line['name_snapshot'] ??` precedence for the
   resolved case. On the unresolved branch, write the snapshot (or
   `unknown_item`) into all three. Add `name_ar`/`name_en` to the returned line
   array.
3. **`PosOrderService::create()`** — persist `name_ar`/`name_en` on the
   `order_items` row (next to `name`) and in the legacy `orders.items` JSON
   projection (L183-189 map).
4. **`PublicOrderController`** — Minimum: write `$line['name']` into all three
   columns on `recordRound()` and the `orders.items` merge.
5. **Resources** — `PosOrderResource` (lines map), `OrderRoundResource` (items
   map), and the §010 refund line output gain `name_ar`/`name_en` (keep `name`).
   `OrderResource.items` carries them automatically once the JSON has them.
6. **Frontend `apps/web`** — add one `itemName(it)` resolver using the app idiom
   `locale === 'ar' ? name_ar || name_en : name_en || name_ar`, ending
   `|| it.name || ''`. Route `OrdersView.vue` `itemTitle()` (L203) and the receipt
   sheet (L441) through it. Grep other order/line render sites and apply the same.
7. **Feature tests** — extend `PosOrdersTest` (resolved line freezes both names;
   `client_asserted` fallback fills all three) and a resource test asserting the
   two keys appear. `ReportService` name-matching still works because `name` is
   retained on every path (regression-guard test).

### R1.5 Back-compat

`name` is retained everywhere; historical rows and public "Minimum" rows leave
`name_ar`/`name_en` null (frontend falls through to `name`). No backfill.
`ReportService` (keys products by `name`, `lineName()`) is unaffected.

### R1.6 Asks for the desktop side

- **R1-A1 (optional, restores bilingual fidelity on the fallback path).** The till
  sends only `Product.nameEn` as `name_snapshot`. Consider also sending
  `name_ar_snapshot` (from `Product.nameAr`) so the backend can freeze a real
  Arabic name on unresolved / open-price / combo lines. Not required to ship R1;
  today those lines get the English string in both slots. If accepted, the cloud
  adds `lines.*.name_ar_snapshot` (nullable) to `StorePosOrderRequest` and uses it
  on the `client_asserted` branch.
- **R1-A2 (doc sync).** `xorder-pos/docs/coordination/POS_TO_BACKEND.md` still says
  `order_items` has no `menu_item_id` and POS-BE-006 is "APPROVED, not started."
  That is stale: the migration exists and §006 is `READY`. Please sync when R1
  lands (desktop owns that file).
- **R1-A3 (confirm consumer).** The response `name_ar`/`name_en` are primarily for
  the **dashboard**; the till renders from its own local catalog. Confirm whether
  the POS consumes the response line `name`/`name_ar`/`name_en` anywhere (e.g. a
  server-order reprint), so we know if the expanded response matters to the client.

---

## REVISION R2 — dashboard-managed online licence + `POST /api/pos/license/check` · **PROPOSED** (amends §015, §022)

**Spec:** `docs/coordination/REVISION_POS_LICENSING.md`. **Owner decision being
specced:** move licence lifecycle management into Super Admin; a **connected** POS
does an **online licence check on the splash screen at every launch** (and before
each shift) against a server-side record (issue / suspend / renew / force-expire).
Keep the Ed25519-signed file **only** for **islanded** tills. Add a short offline
**grace window** (~72h) so a brief outage never bricks a connected till.
Additive-only; the entire POS-BE-015 offline path stays intact.

### R2.1 What is true today (verified 2026-09-27)

- `pos_licences` has **no** `status`/`enforcement`/`suspended_at`/
  `suspended_reason`. It already has `kind` (`cloud`|`offline`), `lifetime`,
  `max_users`, and a derived `state()` (revoked → superseded → pending → expired →
  in_grace → expiring_soon → active). No `RestaurantScope` (deliberate).
- `pos_terminals` uses `BelongsToRestaurant` (scoped); column is **`fingerprint`
  (singular)**; the plural `fingerprints[]` lives on `PosLicence`. **No**
  `licence_id`, **no** `last_licence_check_at`.
- `LicenceController` has only `activate()` (unauth, throttled, key = credential)
  and `current()` (device credential, returns the **signed file**). **No**
  `/license/check`.
- `LicenceIssuer` has `issue/renew/revoke/mint/claims`; **no** `issueOnline`.
  `signingKey()` is called only in `mint()`.
- `RestaurantProvisioningService::provision()` mints the licence **inside** the
  tenant-creation `DB::transaction`, so every tenant-creating server needs
  `LICENCE_SIGNING_KEY` today (change-log 2026-09-05).
- `pos.device` is a route-middleware **alias** (not an `auth:pos-device` guard)
  and supports `:no-feature` (used by `current` and `heartbeat`).
- Admin licence routes: `index/store/storeOffline/show/renew/revoke/destroy/
  download`. **No** suspend/resume/expire. `AuditLogger` emits `pos_licence.issued/
  .renewed/.revoked` (no `.suspended/.resumed/.expired`).

### R2.2 Agreed cloud→POS wire shape — `POST /api/pos/license/check`

The **new online verdict endpoint** for connected tills. It replaces `GET
/api/pos/licence/current` (the signed *file*) for connected tills; `current` and
`activate` stay for the islanded/file path and back-compat.

**Request** — `pos.device:no-feature` (same device token as the heartbeat),
`throttle:60,1`, restaurant resolved from the terminal (never from body):

```jsonc
POST /api/pos/license/check
Authorization: Bearer xdt_<device-token>
{ "fingerprint": "<sha256 hex>",                 // verified vs licence fingerprints[] if pinned; recorded
  "deployment_mode": "cloud" | "offline",
  "app_version": "1.4.0",                          // telemetry, optional
  "licence_expires_at": "2026-12-31T00:00:00+00:00" }  // what the till believes, optional
```

**Response `200`** — the `status` field is the single source of truth for the till:

```jsonc
{ "status": "valid",                               // enum below
  "licence_ref": "LIC-2026-0042",
  "expires_at": "2026-12-31T00:00:00+00:00",       // null when lifetime
  "lifetime": false,
  "grace_days": 14,                                 // server expiry-grace (≠ the offline cache window)
  "warn_days": 30,
  "max_terminals": 2,
  "max_users": null,
  "features": ["pos"],
  "message": null,                                  // human string for suspended/expired
  "server_time": "2026-09-27T10:00:00+00:00",       // clock-skew reference
  "grace_policy": { "cache_seconds": 259200 } }     // 72h — how long the till may trust THIS answer offline
```

**`status` enum (server-computed effective verdict) and its mapping to the code
that exists today:**

| `status` | Server condition | Derived from |
|---|---|---|
| `valid` | live, in date, not suspended | `state()==active` |
| `expiring_soon` | valid, within `warn_days` | `state()==expiring_soon` |
| `in_grace` | past `expires_at`, within `grace_days` | `state()==in_grace` |
| `expired` | past grace **or** `status='expired'` set in dashboard | `state()==expired` OR new `status` col |
| `suspended` | `status='suspended'` set in dashboard | new `status` col |
| `unknown` | row exists but cannot be evaluated (should not happen) | — |

**Effective-verdict precedence (server):** `revoked_at` → `superseded_by_id` →
`status=suspended` → `status=expired` → `state()` date math. Since `current()`
already resolves via `->live()` (excludes revoked + superseded), a revoked or
superseded licence surfaces as **404 `licence_not_found`**, not as a 200 verdict.

**HTTP / error bodies** (lowercase `licence_not_found` is intentionally consistent
with the grandfathered §015 codes, DIS-4; the others are the existing SCREAMING
device codes from §019):

| Case | HTTP | `code` | Till reaction |
|---|---|---|---|
| found & evaluated | 200 | (status in payload) | per table above |
| no live licence for tenant | 404 | `licence_not_found` | block new shift; "no licence" banner |
| device token invalid | 401 | `DEVICE_TOKEN_INVALID` | re-pair |
| terminal revoked | 403 | `TERMINAL_REVOKED` | "terminal orphaned" banner |
| throttled | 429 | `TOO_MANY_ATTEMPTS` | fall back to grace cache silently |

**Idempotent + read-only.** It opportunistically writes telemetry
(`pos_terminals.last_licence_check_at`, `licence_id`, `fingerprint`,
`reported_licence_expires_at`) with `saveQuietly()`, exactly as the heartbeat does
— never an audited edit.

### R2.3 Schema (additive-only; production DB is live)

```
2026_09_2x_000100_add_status_to_pos_licences_table.php
  + status (string16, default 'active', indexed) : active | suspended | expired
  + suspended_at (timestamp, nullable)
  + suspended_reason (string255, nullable)
2026_09_2x_000200_add_enforcement_to_pos_licences_table.php
  + enforcement (string16, default 'online', indexed) : online | offline
  + backfill (§R2.6)
2026_09_2x_000300_add_licence_binding_to_pos_terminals_table.php
  + licence_id (foreignId, nullable, nullOnDelete)
  + last_licence_check_at (timestamp, nullable)
```

`status` is authoritative for the **online** path only; `state()` stays the
display/derivation helper and the **only** signal the offline/islanded path has.
The two may legitimately disagree while an islanded till is out of contact — that
asymmetry is the point. No column dropped, no `NOT NULL`, no existing value
changed.

> **Reconciliation flag (owner):** the new `enforcement` (online|offline) largely
> overlaps the existing `kind` (cloud|offline). We keep `enforcement` as the
> explicit orthogonal switch the spec asks for (it decides *where the verdict comes
> from*, independent of where sales live), backfilled from `kind`. If the owner
> prefers not to carry two near-parallel columns, `enforcement` can instead be
> derived from `kind` — flagged, not decided here.

### R2.4 Super Admin (`apps/web` + admin API)

New endpoints beside `AdminLicenceController` (all `can:licences.manage`,
SUPER_ADMIN via `Gate::before`; cross-tenant reads audited, matching §015/§022):

```
POST  /api/admin/pos/licences/{licence}/suspend   { reason?:string }  -> 200 PosLicenceResource
POST  /api/admin/pos/licences/{licence}/resume                         -> 200 PosLicenceResource
POST  /api/admin/pos/licences/{licence}/expire     { reason?:string }  -> 200 PosLicenceResource   // force-expire, distinct from revoke/delete
GET   /api/admin/pos/licences/{licence}/terminals                      -> 200 [PosTerminalResource]  // per-terminal status
```

- `PosLicenceResource` gains `status`, `enforcement`, `suspended_at`,
  `suspended_reason` (it already emits `state`, `days_remaining`, `grace_ends_at`,
  `lifetime`, `max_users`, `kind`).
- Audit via `AuditLogger`: `pos_licence.suspended` / `.resumed` / `.expired`
  (mirroring `.issued/.renewed/.revoked`).
- `apps/web/src/pages/admin/pos/`: `LicencesList.vue` gains a Status column +
  filter and per-row Suspend/Resume; `LicenceForm.vue`/`OfflineLicenceForm.vue`
  gain an **Enforcement** choice (Online-managed default vs Signed-file/islanded,
  which reveals `max_offline_days`); `LicenceDetails.vue` gains a per-terminal
  table (each bound `pos_terminal` with `last_seen_at`, `last_licence_check_at`,
  `reported_licence_expires_at`, `deployment_mode`, revoked flag).

### R2.5 Decouple tenant creation from signing

- Add `LicenceIssuer::issueOnline($restaurant, $data, $actor)` — writes the row
  (`enforcement='online'`, `status='active'`, term/features/modes/caps) but
  **skips `seal()`/`mint()`**: `payload`/`signature` stay `''` (schema already
  allows), `key_id` default. The verdict is computed from columns, not a signed
  artifact, so `signingKey()` is never touched.
- `RestaurantProvisioningService::provision()` calls `issueOnline` instead of
  `issue`. A server that only creates cloud tenants then needs **no**
  `LICENCE_SIGNING_KEY`. Existing tenants are unaffected (their signed artifact is
  kept but unused on the online path).
- `LICENCE_SIGNING_KEY` is **retained but demoted to islanded-only** — required
  only when issuing/renewing an `enforcement='offline'` licence (i.e. inside
  `mint()`). `activate`/`current` stay for the islanded/file path.

### R2.6 Backfill rules (data migration / one-off command; no key read, no re-sign)

| Existing row | `enforcement` | `status` |
|---|---|---|
| `kind='cloud'` | `online` | `active` if `state()`∈{active,expiring_soon,in_grace}; `expired` if past grace; unchanged if revoked/superseded |
| `kind='offline'` **with** `max_offline_days` | `offline` (islanded) | derived from dates |
| `kind='offline'` **without** `max_offline_days` | `online` | derived from dates |

### R2.7 Ordered CLOUD implementation plan (phased, each independently shippable)

- **Phase 0 — schema (safe on live prod).** Three additive migrations (R2.3) +
  backfill (R2.6). Extend `PosLicenceResource` with the four fields. Nothing reads
  them yet. Must pass `release-check` (additive-only, no `NOT NULL`, no data loss).
- **Phase 1 — dashboard.** Suspend/Resume/Expire endpoints + audit events + the
  `/licences/{id}/terminals` view; the `apps/web` list/detail/form changes (R2.4).
  Operators manage online licences before any till reads the new endpoint.
- **Phase 2 — `/license/check`.** Ship `POST /api/pos/license/check` behind
  `pos.device:no-feature` (R2.2). Keep `current`/`activate` untouched. Feature
  tests mirroring `PosLicenceTest`/`OfflineLicenceTest`, covering each status,
  404/401/403/429, telemetry write, and precedence (revoked/superseded → 404).
- **Phase 3 — POS online path + grace cache** (desktop; see asks). Cloud only
  needs `grace_policy.cache_seconds` to be server-driven.
- **Phase 4 — decouple provisioning.** `issueOnline` (R2.5); add a test asserting
  the cloud provision path makes **no** `signingKey()` call and works without
  `LICENCE_SIGNING_KEY`.
- **Phase 5 — cleanup/hardening.** Tune `cache_seconds` from telemetry; optional
  verdict HMAC if the threat model tightens; document the islanded-only status of
  `LICENCE_SIGNING_KEY`.

Phases 0–3 leave the offline path fully intact; Phase 4 changes provisioning
behaviour (the one non-trivially-reversible step).

### R2.8 Security posture (unchanged bottom line)

The till gate is **commercial hygiene**, not security: the verdict is unsigned and
travels over TLS on the authenticated device channel; real enforcement stays
server-side on `feature:pos` at every money write (`PosDeviceAuth` feature gate),
which a forged splash verdict cannot bypass. Online suspend/expire bites at the
*next* check (immediate for a launching till, up to 72h for one already open) —
far better than the offline file, which can never be recalled. For an urgent kill,
revoking the **device token** (→ 403 `TERMINAL_REVOKED`) stops all writes
immediately, independent of the licence cache.

### R2.9 Asks for the desktop side

- **R2-A1 (splash-check behaviour).** For a **connected** terminal, call `POST
  /api/pos/license/check` on the splash→StartScreen transition and before each new
  shift. Cache the last good 200 verdict in `bootstrap.json` (not the signed file,
  not `config.json`) with `checkedAt`; on network/5xx/timeout trust the cache while
  `now - checkedAt <= grace_policy.cache_seconds` (default 72h), clamped client-side
  to a sane max (e.g. 7 days). Beyond the window: allow the open shift, block a new
  one. Non-blocking UI (a slow verdict is treated as permitted). Map the six
  `status` values onto the **existing** `LicenseEntitlement` gate — never brick a
  till mid-service (`canCashUp`/`canReprint`/`canExportData` stay `true`).
- **R2-A2 (path selection + where the enforcement flag is delivered).** The client
  picks online vs islanded from its own config (deployment mode + an **enforcement
  flag**). The cloud must deliver that flag somewhere the client can read at
  activation/bootstrap. **Decision needed:** do you want `enforcement`
  (`online`|`offline`) added to the POS-BE-023 bootstrap `licence` object, to the
  `activate` response, or as a top-level bundle field? Name the shape and the cloud
  will emit it. An `enforcement='offline'` (islanded) terminal must **not** call
  `/license/check` and keeps the whole POS-BE-015 signed-file path.
- **R2-A3 (deployment-mode terminology).** The licence `modes` claim still uses
  `cloud`/`branch_server`/`standalone` (POS-BE-015 §6), while the POS collapsed
  deployment modes to `cloud`/`offline`. R2 treats *enforcement* as orthogonal to
  *deployment_mode* (per the spec §0). Confirm the client determines
  connected-vs-islanded from the **enforcement flag**, not from `deployment_mode`,
  so the two axes don't get conflated.
- **R2-A4 (status enum coverage).** The `/license/check` enum is
  {`valid`,`expiring_soon`,`in_grace`,`expired`,`suspended`,`unknown`}. It does
  **not** carry `not_yet_valid` (a licence with a future `issued_at`, `state()==
  pending`) or the client-only `tenantMismatch`/`modeNotLicensed`. Confirm the
  client maps these six onto its `LicenseEntitlement` without needing a
  `pending`/`not_yet_valid` verdict — or tell us to add one. `server_time` is
  provided for the client's existing clock-skew handling.

---

## How this file is used from here

`APPROVED` = contract final under the owner's 2026-09-02 instruction; either
side may build against the *shape*, but Agent 1 integrates real transport only
at `READY`. When implementation of an item starts it moves to `IN_PROGRESS`;
when implemented **and tested** it moves to `READY`. POS-BE-015 is `READY`
today; everything else awaits the owner's go for implementation.

---

## Change log

| Date | Change |
|---|---|
| 2026-08-26 | Agent 2 analysis of POS-BE-001…014 + 016 complete; A1–A7 answered; BE-A01…BE-A05 raised. |
| 2026-08-26 | Owner decision D6; POS-BE-015 contract frozen, then **implemented and tested** (`READY`): `pos_licences`, Ed25519 issuance, key activation, renewal-supersedes-in-place, revocation, `.xlic` download, `licences.manage`, 14 feature tests, Super Admin screens at `/pos/licences`. |
| 2026-09-02 | **Owner instructed full contract agreement (docs only, no code).** Every item POS-BE-001…028 assessed and moved to `APPROVED`; POS-BE-015 stays `READY` with its shipped section preserved verbatim. Decisions recorded: BE-A01 dual idempotency keys (envelope + per-payment; Agent 1 adds `Tender.clientId`); A5 `complete` flag per collection; POS-BE-022 heartbeat response accepted as proposed; POS-BE-011 resolved as **Option C** (device token at claim, no TTL, rotation with 24 h overlap); POS-BE-021 bounded at 100 elements; POS-BE-024 PIN hash fixed as **bcrypt cost 10**; POS-BE-025/026/027/028 accepted with DIS-1/DIS-2 counter-proposals; canonical §019 error list consolidated (lowercase licence codes grandfathered, DIS-4); agreed defaults adopted for D1, D2, Q1, Q2, Q3, A4 (five `settlement_status` strings now final). Five disagreements/counter-proposals recorded at the top for Agent 1 / the owner. **No migration, controller, or code of any kind written.** |
| 2026-09-02 | **Agent 1 accepted DIS-1…DIS-5** (DIS-3 jointly declined, on the owner's desk). Error-code inconsistency fixed: uppercase `LICENCE_TENANT_MISMATCH` added to §019 for the site-register ref check, with a grandfather-collision note against the lowercase activation code; `LICENCE_SITE_MISMATCH` now solely the `server_id` claim mismatch; DIS-2, §019 and §026 agree. Client commitment recorded: `Tender.clientId` generated in `TicketEngine.addTender`. **Contracts closed.** No code written. |
| 2026-09-04 | **Cloud Wave 1 implemented and tested** under the owner's 2026-09-02 go ("make the POS work with cloud for now"). READY: POS-BE-001, 002, 003, 005, 006 (+§006-P), 007, 008, 009 (registry subsumed by §023), 011, 013, 016 (claim/register warning), 019, 020, 022 (API; web UI later; `stale` awaits §026), 023, 024. Deferred, still APPROVED: 004, 010, 012, 014, 017, 018, 021, 025, 026, 027, 028. As-shipped amendments recorded in the banner: PBKDF2 PIN hash (supersedes bcrypt), bundle `tables` block + frozen normalized catalog, §006 v1 relaxations, UTC-instant timestamp rule, licence `current` tightened to the device credential. 740 backend tests green; end-to-end smoke by Agent 1 2026-09-04 (real Flutter parser, 0 products dropped). Implementation journal: `docs/backend/CLOUD_WAVE1_PROGRESS.md`. Nothing committed or deployed. |
| 2026-09-05 | **Tenant creation split from terminal creation** (owner decision). Creating a client now mints the client **and its POS licence in one transaction** — a licence failure rolls the whole tenant back, so there is no such thing as an unlicensed client created through the wizard. Creating a client still creates **no terminal of any kind**; terminals are provisioned one at a time afterwards, and a licensed tenant with zero terminals is a valid resting state. New platform-side routes under `/api/admin/restaurants/{restaurant}/terminals` (§023 amendment), new `pos_fleet.manage` capability. **No POS-facing wire contract changed.** |
| 2026-09-11 | **CB-00 — the two repos' copies reconciled** (`xorder-cloud`, docs only). They had drifted in both directions. xorder-new (2026-09-05) alone had the §023 "Amendment, owner decision 2026-09-05 — the platform-side front door" (the four `/api/admin/restaurants/{restaurant}/terminals` routes and the "zero terminals is a normal state" note) and the 2026-09-05 "tenant creation split from terminal creation" change-log row. xorder-pos (2026-09-06) alone had the §022 "Amendment 2026-09-06 — 'catalog authored in the cloud only' now reads 'on a cloud terminal'" (which carried no change-log row of its own). Both are kept; they touch different passages, so nothing conflicted. Change-log rows re-sorted into date order (no row removed or reworded). No contract status changed (the two copies agreed on every status). Both copies are now byte-identical. |
| 2026-09-11 | **POS-BE-013 amended: the tender-id defect is fixed** (owner go 2026-09-11, `xorder-cloud`). A cloud till had been paying with its own local tender ids (1–4), and the platform validates `tender_type_id` against its own tenant-scoped `tender_types`. Platform side: `PosProvisioningService::ensureDefaultTenders()` creates Cash + Card at a POS restaurant's first terminal (provision or register, with claim as the backstop) when the restaurant has no tender types. It is idempotent, scoped per tenant, and bumps `config_version`. The rules added to §013 are that `tender_type_id` MUST come from `money.tender_types`, the list is never empty, and null means "unspecified" (counted as cash) and is never a fallback. This is an amendment, not new surface, so there is no POS-BE-030, and POS-BE-013 stays `READY`. Tests: `tests/Feature/Pos/PosDefaultTendersTest.php` (11). No migration. Till side (`pos-dev`, in parallel): seed `pos_tender_types` from the bundle on cloud and pay with platform ids. Nothing committed or deployed. |
| 2026-09-22 | **§023 bundle gains `receipt_profiles[]`** (owner go: "hand A3 and A7 to xorder-cloud", item A3). A new frozen key, one row per active branch, field names copied one for one from the till's `pos_receipt_profiles` columns so its seeder is a straight mapping. An unauthored branch is projected from the restaurant rather than omitted — a missing row is exactly what made every cloud till print with compiled-in defaults. `registration_number` is the restaurant's single copy (one taxpayer, one number); `branch_code` is ETA's, **not** `branches.code`. Authored at `GET`/`PUT /api/dashboard/receipt-profiles[/{branch}]` under `feature:pos` + `settings.view`/`settings.update` + `subscription.writable`, with a `revision` guard (stale save → 409) and a `pos_config_version` bump on every write. New dashboard page `PosReceiptView.vue` (EN + AR, RTL). **CLOUD_WAVE1 deviation 6 is closed:** `UpdateRestaurantProfileRequest` finally accepts `tax_registration_number`, and changing it bumps `config_version`. Tests: `tests/Feature/Pos/PosReceiptProfileTest.php` (10). Migration additive: new `receipt_profiles` table. Branch `pos/cloud-refunds-receipt-profile`, not pushed, not deployed. |
| 2026-09-22 | **POS-BE-010 built and tested → `READY`** (owner go: "hand A3 and A7 to xorder-cloud"). `POST /api/pos/refunds` + `GET /api/pos/refunds/by-client-id/{uuid}`, device token + `feature:pos`, `pos.refund` (or `pos.void` for `kind: void`), credit notes in their own `CN-` sequence bucket, cumulative quantity AND money checks under the order's row lock, idempotent per POS-BE-007 (201 first / 200 replay / never 409). **The blocker is cleared:** `POST /api/pos/orders` now accepts `lines[].client_line_id` and stores it under `unique(order_id, client_line_id)`, so a refund built offline addresses lines by `(order client_transaction_id, client_line_id)` and never needs a platform order-item id. **OrderStatus decision: the enum does not grow** — `NEW \| COMPLETED \| CANCELLED` stands, and refund state rides the derived `settlement_status` (`PARTIALLY_REFUNDED` / `REFUNDED`, the till's own `PaymentStatus` words; `VOIDED` and `PARTIALLY_PAID` are never emitted). A3's `cash_refunds` term went live and the shift report gained `refunds_minor`, `refunds_count`, `cash_refunds_minor`. No new §019 code. Tests: `tests/Feature/Pos/PosRefundsTest.php` (19). Migrations additive: `orders.refunded_minor`, `order_items.client_line_id` + `refunded_quantity`, `pos_refunds` / `pos_refund_lines` / `pos_refund_tenders`. Branch `pos/cloud-refunds-receipt-profile`, not pushed, not deployed. |
| 2026-09-27 | **Cloud coordination review of two owner revision specs → two `PROPOSED` amendments** (cloud side; no code, nothing committed/deployed). Both specs cross-checked against live `apps/api`+`apps/web` and confirmed accurate. **R1 — order-line bilingual name freeze** (amends §006/§010/§023): `order_items` gains nullable `name_ar`/`name_en`; `PosPricingEngine` freezes both from the resolved item and demotes `name_snapshot` to fallback-only; resources + legacy `orders.items` JSON expose both; dashboard resolves by locale with the app idiom; public/QR "Minimum" writes the single name into all three. `name` retained everywhere; no backfill. **R2 — dashboard-managed online licence + `POST /api/pos/license/check`** (amends §015/§022): additive `pos_licences.status/enforcement/suspended_at/suspended_reason` + `pos_terminals.licence_id/last_licence_check_at`; new `pos.device:no-feature` verdict endpoint (status enum mapped onto the existing `state()` + new `status` col); Super Admin suspend/resume/expire + per-terminal view + audit events; `LicenceIssuer::issueOnline` decouples tenant creation from `LICENCE_SIGNING_KEY` (demoted to islanded-only); the Ed25519 signed-file path kept for islanded tills. Phased 0–5, additive/deploy-safe. Desktop asks recorded (R1-A1..A3, R2-A1..A4). Statuses stay **PROPOSED** — owner's go pending. |
| 2026-09-13 | **POS-BE-030 agreed; platform half `READY`** (CB-09; owner go "finish all phases"). `PosBootstrapService::staff()` withholds `purchase.manage` from every bundle, owner included, and `PosPurchaseCapabilityWithheldTest` covers it. Purchasing is authored only on the dashboard under `feature:purchasing` + `can:purchase.manage`, and `purchasing` does not require `pos`. No wire change. Built on `feat/cb-09-purchasing` in xorder-new, not deployed. The till half, hiding the panes by deployment, is on xorder-pos `feat/cb-09-slice-e` @ `1adb17f`, not merged. |
