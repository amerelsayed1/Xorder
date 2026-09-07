# POS Licensing

**Status:** implemented in the client · **backend issuance is `READY`**
(POS-BE-015 — built and tested in `apps/api`; the final contract is in
`docs/coordination/BACKEND_TO_POS.md`)
**Code:** `lib/features/licensing/`
**Tests:** `test/features/licensing_test.dart`, `test/features/licence_renewal_test.dart`

---

## 1. What this is — and what it is not

This is **commercial hygiene, not security.**

The verification key ships inside the binary, so anyone willing to patch the
binary can defeat every check described here. That is true of every offline
licence system ever built. It is not a reason to skip it — it is a reason not to
rely on it for anything that actually matters.

Where real enforcement lives:

| Concern | Enforced by |
|---|---|
| Can this tenant use the POS at all | The server's existing `feature:pos` entitlement, on every write |
| Plan limits | `PlanLimitService`, server-side |
| How many terminals are running | Only a server can see sibling terminals — the offline `max_terminals` check is **advisory** (POS-BE-016) |
| Has this customer paid | Your billing system, not the till |

The licence file exists so an honest customer knows when to renew, and so an
on-premises install has *something* to check when it can never phone home.

## 2. The cardinal rule

> **Never brick a till mid-service.**

A POS that refuses to sell during Friday dinner because a licence lapsed does not
collect the renewal. It loses the customer, and possibly their unsynced takings
with it.

So the policy degrades in stages rather than switching off:

| State | New shift | Sell in an open shift | Change config | Cash up · reprint · export |
|---|---|---|---|---|
| `valid` | ✅ | ✅ | ✅ | ✅ |
| `expiringSoon` (within `warn_days`) | ✅ | ✅ | ✅ | ✅ |
| `inGrace` (within `grace_days` past expiry) | ✅ | ✅ | ❌ | ✅ |
| `expired` (past grace) | ❌ | ✅ | ❌ | ✅ |
| `missing` · `invalid` · `tenantMismatch` · `modeNotLicensed` · `terminalNotLicensed` | ❌ | ❌ | ❌ | ✅ |

Two carve-outs are non-negotiable and hard-coded:

1. **An expired licence stops the *next* shift, never the open one.** Staff finish
   the service and cash up correctly; the till simply will not start tomorrow.
2. **Cash-up, X/Z, reprint and export are never gated in any state.** Recovering
   your own money records is not a licensable feature.

`LicenseEntitlement.canCashUp` / `canReprint` / `canExportData` are getters that
return a literal `true`. That is deliberate — it means no future edit can gate
them by accident.

## 3. File format

A detached Ed25519 signature over a JSON payload:

```json
{
  "payload":   "<base64url of the claims JSON>",
  "signature": "<base64url of the Ed25519 signature>",
  "key_id":    "v1"
}
```

Shaped like a JWS but **deliberately not a JWT**: there is no `alg` field, so
there is no `alg: none` class of bug. The algorithm is fixed at Ed25519 in code
and cannot be selected by the file.

### Claims

| Field | Meaning |
|---|---|
| `license_id` | issuer's reference |
| `tenant_slug` · `tenant_name` | who it was issued to; the slug is checked against the terminal's configured tenant |
| `issued_at` · `expires_at` | term |
| `grace_days` | trade continues this long past expiry (default 14) |
| `warn_days` | renewal banner appears this long before expiry (default 30) |
| `max_terminals` | **advisory offline** |
| `features` | feature keys, mirroring the server's `Feature` enum |
| `modes` | which deployment modes it covers — a cloud licence need not cover an offline terminal. The setup wizard reads this to decide which modes it offers at all. Legacy `branch_server` / `standalone` values still parse, to `offline`. |
| `fingerprints` | machine pins; empty means unpinned |
| `branch_ids` | empty means all branches |

> ### Amendment — 2026-08-28: three claims proposed, and the "offline certificate" declined
>
> Three additive keys are requested as **POS-BE-027**, all tolerant, none
> requiring any existing licence to be re-signed — the signature covers the
> payload bytes and this change only reads more of them.
>
> | Claim | Absent → | Note |
> |---|---|---|
> | `max_offline_days` | `null` = unlimited | The server already emits it. §6 below lists it as not built; POS-BE-027 is what closes that |
> | `license_version` | `1` | Claims-schema version. If it exceeds what the client understands, **evaluate what you understand and attach a notice — never deny** |
> | `server_id` | `null` = not site-pinned | Pins a licence to a *site's database* rather than to a box. Same semantics as an empty `fingerprints[]` |
>
> This adds two `LicenseState` cases — `offlineWindowExpired` and `siteMismatch`
> — and four `LicenceNotice` cases. The entitlement for `offlineWindowExpired` is
> **byte-identical to `expired`**, so §2's cardinal rule needs no new shape: the
> next shift is blocked, the open one is never cut off.
>
> **A separate signed "offline certificate" was requested by the owner and is
> declined here.** Seven of its nine proposed fields are already claims above;
> these three cover the rest. A second document would mean two expiry dates to
> reconcile, two revocation paths, and POS-BE-022's own instruction says not to
> build a second enforcement path. Recorded as a disagreement, not a silent
> substitution — see POS-BE-027 and `docs/pos/10-setup-architecture.md` §13.
>
> `evaluateClaims` gains two optional parameters, `lastPlatformContactAt` and
> `siteServerId`, both nullable and both meaning *cannot judge, do not deny*, so
> it stays pure and testable without keys. "Last platform contact" is stored in
> `bootstrap.json` — never in the signed file, which is not rewritten, and never
> in `config.json`, which gates boot and must not be rewritten hourly.

## 4. Verification

`LicenseVerifier` does signature-then-policy, and the two halves are separable:

- `verifySignature()` — Ed25519 over the payload bytes.
- `evaluateClaims()` — **pure**, takes `now` as a parameter. Every expiry, grace
  and scope rule is unit-tested without generating keys or waiting a year.

`evaluate()` composes them. Malformed input returns a state, never an exception:
a damaged file must not crash a till.

The clock is injected rather than read from `DateTime.now()` at the point of use,
so a wrong system clock produces the honest message *"check the terminal's date
and time"* rather than a baffling "not yet valid".

## 4a. Test licences

**There is one key pair, and it belongs to the platform.** `LicenceIssuer::mint`
in `apps/api` signs every licence the dashboard hands out, so the POS embeds the
public half of the API's `LICENCE_SIGNING_KEY` and nothing else. A POS-side pair
would mean the till rejected every licence the dashboard issued.

Derive the public half from the API's secret key — this prints only the public
half, never the secret:

```bash
php -r '$e = file(".env"); foreach ($e as $l) if (str_starts_with($l, "LICENCE_SIGNING_KEY=")) $k = trim(substr($l, 20));
  echo base64_encode(sodium_crypto_sign_publickey_from_secretkey(base64_decode($k))), PHP_EOL;'
```

To sign locally with the same pair, `bin/pos_licence.dart` wants the **seed** —
the first 32 bytes of that 64-byte libsodium secret key — in `POS_LICENCE_KEY`:

```bash
export POS_LICENCE_KEY=<private-key-b64>
dart run bin/pos_licence.dart issue --tenant mahsoub --name "Mahsoub Restaurant" \
  --days 365 --out licences/valid.xlic
```

`--issued` and `--expires` take ISO-8601 dates and override `--days`. They exist
so every state a till has to handle can be produced as a real signed file rather
than only reasoned about in a unit test:

| State | How to mint it |
| --- | --- |
| `valid` | the default |
| `expiringSoon` | `--days 12` — anything inside `--warn-days`, default 30 |
| `inGrace` | `--expires` a past date inside `--grace-days`, default 14 |
| `expired` | `--expires` a past date beyond the grace window |
| `notYetValid` | `--issued` a future date — what a wrong terminal clock looks like |
| `tenantMismatch` | `--tenant` something other than the terminal's |
| `modeNotLicensed` | `--modes cloud` installed on an offline till, or the reverse |
| `invalid` | edit a byte of the payload in any file above |

`licences/` and `*.xlic` are git-ignored, so a signed file cannot be committed
by accident.

Read one back — including whether it verifies against a given key — with:

```bash
dart run bin/pos_licence.dart inspect --file licences/valid.xlic \
  --public-key "$(grep -o "currentB64 = '[^']*" lib/features/licensing/data/license_keys.dart | cut -d"'" -f2)"
```

**Before release**, run `keygen` again for the release channel, embed that public
key, and keep its private half off shared drives. A build that ships the
development key is a build anyone with this repository can license.

## 5. Renewal — how a licence is updated

Renewal is the **common** case; first activation is the rare one. A till is set up
once and renewed every year, so renewal has its own screen rather than living
inside the setup wizard.

`Settings → Licence` (`lib/features/licensing/presentation/licence_screen.dart`)

| Path | Mode | Staff action |
|---|---|---|
| **Automatic** | Cloud | **None.** Renew on the platform; the till re-reads at start-up and before each shift opens. |
| **Key re-entry** | Any | Type the new key → *Activate key* |
| **File import** | Any | Import the `.xlic` from your supplier → *Import licence file*. The only path that needs no internet at all. |
| **Forced check** | Any | *Check for renewal*. **Offline terminals included** — the mode decides where *sales* go, not where the licence comes from, and this check-in is the mechanism behind the offline window. Only a build with no licence transport says there is nobody to ask. |

**Renewal must never require the internet.** That is why the signed-file path is
first class, not a fallback: an on-premises till may never see the internet in its
working life, and its licence still has to be replaceable.

Two implementation notes that matter:

- Activation and renewal are **the same code path** (`LicenceActivation.activate`),
  so a renewal cannot drift from an activation.
- `licenceEntitlementProvider` is **invalidated** after every activation and
  re-read when the start screen is reached. A renewal applied five minutes ago is
  visible without restarting the till.
- `LicenceActivationResult.succeeded` keys on `canOpenShift`, **not** `canSell`.
  An expired licence still permits selling in an open shift, so `canSell` would
  report a failed renewal as a success — precisely the case the operator is
  trying to fix. `installed` reports separately that *something* was stored, so
  the status panel can show what they actually have.

### In branch-server mode, renew once per branch

The branch box holds the licence and the tills read it from there, so a renewal is
applied once per site rather than once per till. Six tills in a branch is one
renewal, not six. This is part of POS-BE-017.

## 6. What is not built

- **Real key distribution.** `FakeLicenceService` self-signs at runtime so the
  wizard is walkable before a licence server exists. Development keys containing
  `EXPIRED`, `GRACE` or `SOON` mint those terms, which is how the states above are
  demonstrated. `DefaultLicenceService` is the production binding and holds the
  real public key.
- **A file picker.** The offline import currently takes pasted contents; the
  native picker lands with the desktop packaging work.
- **Hardware fingerprinting.** `TerminalFingerprint` is an interface with a fake.
  The real implementation must hash before anything leaves the device — the
  licence server has no business knowing the operator's machine name.
- **Server issuance and activation** — POS-BE-015 is **`READY`**: Super Admin
  issues, renews, revokes and downloads licences, and `POST /api/pos/licence/activate`
  exchanges a typed key for the signed file. `licenceServiceProvider` is bound to
  `DefaultLicenceService`; `FakeLicenceService` is a test double only. **One thing
  remains before a release build: the real Ed25519 public key** (below).
- ~~**`max_offline_days`.**~~ **Read since 2026-08-28.** `LicenseClaims` parses it
  tolerantly — absent, null or wrongly typed all mean unlimited, which is the
  correct value for cloud and the only safe reading for a licence minted before
  the claim existed. `license_version` landed alongside it, defaulting to 1, with
  the rule that a version above `LicenseClaims.supportedVersion` is **evaluated,
  never denied**. Covered by the *offline window and claims version* group in
  `test/features/licensing_test.dart`, including a signed fixture proving no
  existing licence needs re-signing.
  **The window is parsed but not yet enforced** — enforcement needs a durable
  "last reached the platform" timestamp, which arrives with the configuration
  cache (`docs/pos/10-setup-architecture.md` §7, §13). A till that ignores the
  window simply does not enforce it, so this does not block integration.
  *(The sibling risk — an empty `modes[]` parsing to an empty set and failing
  every mode, which reads to a cashier as a bricked till — is now rejected at
  validation by the issuer.)*

> **Release blocker: the shipped public key is still the development one.**
> `LicenseKeys.currentB64` holds the public half of the `apps/api` development
> pair. A release build must not ship it. Run `php artisan licence:keygen` for
> the release channel, embed that public half **before** anything is signed with
> it, and keep the secret with the issuer. This cannot be done from the POS
> repository — the issuer owns the pair.
