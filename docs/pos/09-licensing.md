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
| `modes` | which deployment modes it covers — a cloud licence need not cover a branch server |
| `fingerprints` | machine pins; empty means unpinned |
| `branch_ids` | empty means all branches |

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

## 5. Renewal — how a licence is updated

Renewal is the **common** case; first activation is the rare one. A till is set up
once and renewed every year, so renewal has its own screen rather than living
inside the setup wizard.

`Settings → Licence` (`lib/features/licensing/presentation/licence_screen.dart`)

| Path | Mode | Staff action |
|---|---|---|
| **Automatic** | Cloud | **None.** Renew on the platform; the till re-reads at start-up and before each shift opens. |
| **Key re-entry** | Any | Type the new key → *Activate key* |
| **File import** | Branch server · standalone | Import the `.xlic` from your supplier → *Import licence file* |
| **Forced check** | Cloud only | *Check for renewal*. On a branch server or standalone till this says plainly that there is nobody to ask, rather than spinning. |

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
- **Server issuance and activation** — POS-BE-015 is now **`READY`**: Super Admin
  issues, renews, revokes and downloads licences, and `POST /api/pos/licence/activate`
  exchanges a typed key for the signed file. Two things remain on this side before
  the swap: read `max_offline_days` (below), and compile the real Ed25519 public key
  into the binary in place of the development issuer. Until both land,
  `licenceServiceProvider` stays on `FakeLicenceService`.
- **`max_offline_days`.** The server now emits it; `LicenseClaims` does not read
  it. It is the single mechanism POS-BE-022 relies on for the islanded check-in
  window, and must be added tolerantly (absent → null → unlimited) so a newly
  minted licence stays readable by an older till. A till that ignores it simply
  does not enforce the window, so this does not block integration.
  *(The sibling risk — an empty `modes[]` parsing to an empty set and failing
  every mode, which reads to a cashier as a bricked till — is now rejected at
  validation by the issuer.)*
