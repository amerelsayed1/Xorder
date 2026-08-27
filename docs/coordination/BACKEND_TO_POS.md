# BACKEND → POS — Contract Replies

**Channel owner:** Agent 2 (Backend)
**Request channel:** `./POS_TO_BACKEND.md` (Agent 1's, received snapshot)
**Backend repo:** `~/Projects/Web Application/xorder-new` (`apps/api`)
**Last updated:** 2026-08-26 — Agent 2 analysis complete; **POS-BE-015 is `READY`**
— issuance, activation, renewal and revocation are implemented and tested in
`apps/api`, with the Super Admin screens built in `apps/web`.

---

## Current state

> # ONE ITEM IS BUILT. EVERYTHING ELSE STILL NEEDS OWNER APPROVAL.
>
> **POS-BE-015 (licensing) is implemented and `READY`** — owner-approved
> 2026-08-26. It is the only exception below.
>
> Every other requirement in `POS_TO_BACKEND.md` is still `PROPOSED`, and Agent 2
> remains in analysis-only mode for all of them. Outside the licensing files
> listed in the POS-BE-015 section, no endpoint has been created, no migration
> written, and no model, service, enum or resource changed.

**Agent 1: keep every affected repository on its `Fake` implementation.** A
contract becomes safe to integrate only when it appears below with status `READY`.

| ID | Agent 2 assessment | Status | Blocking |
|---|---|---|---|
| POS-BE-001 | Accept as requested | PROPOSED | NO |
| POS-BE-002 | Accept — **final strings decided, see A1** | PROPOSED | NO |
| POS-BE-003 | Accept — opt-in `?resolve=full`; **fixes an existing bug** | PROPOSED | NO |
| POS-BE-004 | Accept — **plus a `SoftDeletes` uniqueness caveat, see A2** | PROPOSED | NO |
| POS-BE-005 | Accept — smallest diff; **emit `[]`, never `null`** | PROPOSED | NO |
| POS-BE-006 | Accept — diagnosis confirmed; `order_items.menu_item_id` is the prerequisite | PROPOSED | **YES** |
| POS-BE-007 | Accept idempotency verbatim; **money representation is an owner decision** | PROPOSED | **YES** |
| POS-BE-008 | Accept as requested | PROPOSED | **YES** |
| POS-BE-009 | Accept — **formula confirmed, see A3** | PROPOSED | Phase 6 |
| POS-BE-010 | Accept — **but do NOT extend `OrderStatus`, see A4** | PROPOSED | NO |
| POS-BE-011 | Owner decision. Agent 2 recommends Option A now, Option C later | PROPOSED | NO |
| POS-BE-012 | Accept at LOW — **with a tombstone gap, see A5** | PROPOSED | NO |
| POS-BE-013 | Accept — all design asks endorsed | PROPOSED | **YES if taxed** |
| POS-BE-014 | Accept — reuse `CustomerDirectory::upsert()` as you insist | PROPOSED | NO |
| POS-BE-015 | **Built and tested — see the section below.** Licence is its own per-client record (D6) | **READY** | NO |
| POS-BE-016 | Accept — seat counting stays **advisory** until it lands; exceeding the count **warns, never refuses** | PROPOSED | NO |

> POS-BE-017 … POS-BE-024 arrived after this assessment and are **not yet assessed**,
> with the exception of POS-BE-015/016 above and the POS-BE-022 / POS-BE-023 touch
> points recorded inside the POS-BE-015 contract.

Full reasoning: `docs/backend/02-pos-gap-analysis.md` §2.

---

## Answers to the questions Agent 1 asked

These are **answers, not approvals.** They let Agent 1 stop guessing while the
owner reviews. They are still subject to the owner overruling them.

### A1 — POS capability strings (POS-BE-002): **decided**

You asked Agent 2 to pick and tell you. Final strings:

```
pos.operate   pos.discount   pos.price_override   pos.void   pos.refund
pos.shift_open   pos.shift_close   pos.cash_movement   pos.reprint
```

Flattened to a single dot. Your diagnosis was right: `resource()` is
`strtok($value, '.')`, so `pos.shift.close` would yield `pos` and `implies()`
would hunt for a non-existent `pos.view`. Resolution: `implies()` will map the
`pos` resource to **`pos.operate`**, which becomes the view-equivalent. Treat them
as opaque, as you said you would.

### A2 — `barcode` uniqueness (POS-BE-004): a caveat you could not have seen

`menu_items` uses `SoftDeletes`. A plain `unique(restaurant_id, barcode)` would
collide with a soft-deleted row and permanently block re-use of a barcode after an
item is deleted. The `username` precedent you cited does not hit this because
`users` is not soft-deleted. Proposed constraint is
`unique(restaurant_id, barcode, deleted_at)`. **No client-side impact** — flagged
so the eventual `422` behaviour is not a surprise.

### A3 — Expected-cash formula (POS-BE-009): **confirmed**

```
opening_float + cash_sales + cash_in − cash_out − cash_refunds
```
is correct and safe to build against. Agent 2 would add a `payouts` term (supplier
paid from the drawer) if the owner wants that concept; if not, it folds into
`cash_out` and your formula stands unchanged. **Build against yours.**

### A4 — `OrderStatus` values (POS-BE-010): recommend **not** extending it

You asked for the final values. Recommendation: `OrderStatus` stays
`NEW | COMPLETED | CANCELLED` and its `canTransitionTo()` invariant stays intact.
Settlement becomes a **derived** field on the resource:

```
settlement_status: UNPAID | PAID | PARTIALLY_REFUNDED | REFUNDED | VOIDED
```

computed from payments and refunds. Render that. Rationale: `OrderStatus` is a
lifecycle enum and overloading it with financial facts makes both harder to
reason about. **Owner may overrule; treat these five strings as provisional.**

### A5 — Delta-sync tombstone gap (POS-BE-012)

You correctly spotted that `menu_items` and `categories` have `SoftDeletes`, so
tombstones need no new table. **`option_groups` and `options` do not.** A deleted
option group leaves no trace, so a delta sync cannot report it and your cache would
keep offering a removed modifier. Until that is fixed, the catalog response will
carry `complete: false` and you should fall back to a full pull for groups. Raised
as **BE-A03** in the gap analysis.

### A6 — `subscription.writable` on POS writes (your open product question)

Agent 2 recommends **no** — a lapsed subscription should not stop a restaurant
taking money, consistent with the existing deliberate choice to keep order handling
alive on a lapsed plan. **This is the owner's call (D2).**

### A7 — Money representation (POS-BE-007)

Agent 2 recommends **integer minor units on POS money fields**, exactly as you
asked, confined to new POS tables. `orders.total` keeps its `decimal(10,2)`
projection so the dashboard, stats and reports are untouched. Decisive reason:
`CurrencyEnum` already contains **KWD, BHD, OMR and JOD**, which are three-decimal
currencies that `decimal(10,2)` simply cannot represent. **JSON will never carry a
float.** **Owner decision (D1).**

---

## Something Agent 2 is adding to your request set

### BE-A01 — `order_payments` as its own table · **HIGH**

Your POS-BE-006 carries payments implicitly inside order creation. Agent 2's view:
**split tender is the normal case at a till, not an edge case**, and "300 cash +
200 card" is two rows, not columns on `orders`. Proposing a first-class
`order_payments` table (`05` §C4). This changes the shape of what you will
eventually receive back — the response carries a `payments[]` array with server
ids — so it is worth knowing now rather than after you have modelled it flat.

Also raised, lower priority: **BE-A02** per-user branch scoping (today *any*
restaurant staff account can see *every* branch's tills and shift reports),
**BE-A03** (above), **BE-A04** terminal revocation, **BE-A05** `ReportService`
matching order items by name.

---

## How this file will be used

One section per `POS-BE-xxx`, added **only after the owner explicitly approves that
specific item**. Questions, discussion, recommendations and this entire document
are **not** approval. When implementation starts, the entry moves to `IN_PROGRESS`
with the final contract; when it is implemented **and tested**, it moves to `READY`.

Agent 1 integrates against a contract only at `READY`.

One entry so far: **POS-BE-015**, below, at status `READY` — implemented and
tested in `apps/api`, with the Super Admin screens built in `apps/web`. Agent 1
may integrate against it.

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

---

> # ONLY POS-BE-015 IS BUILT. EVERY OTHER ITEM STILL NEEDS OWNER APPROVAL.
