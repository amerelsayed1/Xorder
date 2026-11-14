# Audit Review — POS / ERP Expert Assessment

**Reviewer role:** POS & ERP systems expert (independent review)
**Date:** 2026-09-01
**Scope reviewed:**

| Document set | Location |
|---|---|
| POS programme docs 01–09 | `xorder-pos/docs/pos/` |
| Coordination channel | `xorder-pos/docs/coordination/{POS_TO_BACKEND,BACKEND_TO_POS}.md` |
| Pre-launch security audit (2026-07-25) | `Xorder-Menu/docs/XORDER_PRE_LAUNCH_SECURITY_AUDIT.md` |
| QA 10×12 handoff (2026-08-22) | `Xorder-Menu/QA_CLAUDE_REVIEW.md` |
| Code cross-checks | `Xorder-Menu/apps/api`, `xorder-pos/lib` + `test/` |

Every load-bearing factual claim in the audits was checked against the code in
both repositories, not taken on faith. Results below.

---

## 1. Verdict

**The analysis quality is unusually high — the execution state does not match
the documents, and two findings are serious.**

The POS requirement set, offline strategy, idempotency contract, money model
and licensing design are genuinely at or above commercial POS product standard.
The gap analysis of the backend is accurate: every "verified absent" claim I
re-checked is in fact absent, and every "exists" claim exists.

However:

1. **The coordination protocol's one hard guarantee is broken.** `POS-BE-015`
   is declared `READY — implemented and tested in apps/api` with a named file
   list. **None of those files exist in the backend repository** (finding F-1).
2. **The owner's Postgres-primary decision silently deleted the product's #1
   stated non-negotiable** — "the till never stops selling" — and the offline
   queue that seven of the nine docs are built around was never implemented
   (finding F-2).

Neither invalidates the audit documents as *analysis*; both invalidate them as
a *statement of what exists*. They must be reconciled before anyone plans
against them.

---

## 2. Claim verification matrix

| # | Claim (doc) | Checked against | Result |
|---|---|---|---|
| 1 | `order_items` has no `menu_item_id`, only a `name` string (01 §3, POS-BE-006) | `2026_08_19_000100_create_table_visits_and_order_rounds.php` | ✅ **Confirmed** — `name`, `quantity`, `options` json, `unit_price`, `line_total`. No FK to `menu_items`. |
| 2 | Public order path recomputes `total` from client `line_total`s with float math (01 C-2/C-3) | `PublicOrderController.php:78-91,283` | ✅ **Confirmed** — `(float)` sum of client `line_total`, clamped to `99999999.99`. |
| 3 | `Order::code()` is `'ORD-'.$id` (POS-BE-008) | `app/Models/Order.php` | ✅ **Confirmed.** |
| 4 | `BranchResource` omits `supported_order_types` / `code` (POS-BE-005) | `Branch.php` (`$fillable`+cast present) vs `BranchResource.php` (absent) | ✅ **Confirmed.** |
| 5 | No `pos.*` capabilities, no tax model, no payments/shift/terminal/licence concept in backend | grep across `app/Enums`, `app/Services`, migrations | ✅ **Confirmed** for capabilities, tax, payments, shifts, terminals. ❌ **Licence claim inverted — see F-1.** |
| 6 | JWT TTL default 7 days, no refresh token (C-4, POS-BE-011) | `config/jwt.php:29` | ✅ **Confirmed** (`60*24*7`). |
| 7 | Client money is integer minor units, exponent-aware, no doubles (POS-R073) | `lib/core/money/money.dart` | ✅ **Confirmed** — int minor units, per-currency exponent, string parse that never routes through a double. |
| 8 | Postgres idempotency + invoice sequence implemented and tested (08 decision box) | `lib/data/postgres/postgres_orders_repository.dart` (`ON CONFLICT (restaurant_id, client_transaction_id)`, `FOR UPDATE` on sequence row), `test/data/postgres_integration_test.dart` (concurrent-settlement test present) | ✅ **Confirmed in client code.** |
| 9 | POS-BE-015 backend "implemented and tested in `apps/api`", Super Admin screens in `apps/web` | `Xorder-Menu` repo | ❌ **NOT PRESENT** — see F-1. |
| 10 | SQLite write-ahead + sync queue per docs 02/03/04/07 | `xorder-pos/lib` | ❌ **NOT BUILT** — no `sync_queue`, no queue engine, no dead-letter, no `Local*Repository`. Only `postgres/`, `fakes/`, `unconfigured/` implementations exist. See F-2. |
| 11 | Client "still on `FakeLicenceService` pending the real public key" (09 §6, BACKEND_TO_POS §10) | `lib/app/providers.dart:365` | ⚠️ **Stale** — the client already wires `DefaultLicenceService` with a compiled key and local `bin/pos_licence.dart` issuance, `remote: null`. `max_offline_days` is still unread (grep: zero matches) — that acknowledged gap is real and still open. |

---

## 3. Critical findings

### F-1 · CRITICAL (process integrity) — `READY` status is not backed by code in the repo

`BACKEND_TO_POS.md` declares POS-BE-015 **READY**, states "implemented and
tested", and lists the shipped artifacts:
`config/licence.php`, `2026_08_26_000100_create_pos_licences_table.php`,
`app/Models/PosLicence.php`, `LicenceIssuer`, `LicenceActivator`,
`Admin/Pos LicenceController`s, `Capability::LICENCES_MANAGE`, 14 feature
tests, and `apps/web/src/pages/admin/pos/{LicencesList,LicenceForm,LicenceDetails}.vue`.

**Verified: none of these exist in `Xorder-Menu`.** No `licence`/`license`
match anywhere in `app/`, `routes/`, `config/`, or `database/migrations/`; no
`apps/web/src/pages/admin/pos/` directory; `Capability.php` has no
`LICENCES_MANAGE`.

Why this is critical rather than an inventory nit: the entire two-agent
coordination model rests on one rule — *"Agent 1 integrates against a contract
only at `READY`"*. `READY` is the single trusted word in the channel. Here it
is attached to work that is absent from the repository under review. Possible
explanations (work done in an unpushed `xorder-cloud` checkout; a lost branch;
or the status was written ahead of the work) — but **every one of them means
the channel can no longer be trusted without repo evidence**.

**Required actions**
1. Locate or re-do the POS-BE-015 implementation; until it is on a pushed
   branch with its 14 tests green in CI, demote the status to `IN_PROGRESS`.
2. Amend the coordination protocol: a `READY` entry must cite a commit hash in
   the shared repository, and CI must be the arbiter — not prose.
3. Re-audit any other "done" claims the same way (the client-side ones checked
   here — Postgres layer, licensing client, Money — do all exist).

### F-2 · CRITICAL (product architecture) — the offline-first guarantee was deleted, not amended

Doc 02 opens with three non-negotiables; #1 is *"The till never stops selling.
Network loss degrades features, never the sale path."* Docs 03 and 07 design a
SQLite write-ahead + causal sync queue + dead-letter machinery around it; risk
R-4 ("offline order lost on crash") is rated High.

The owner decision recorded in doc 08 (Postgres on the branch server is the
**primary and only** datastore; "SQLite is not the primary store") reverses
this, and the code confirms the reversal is total:

- **No sync queue, no `LocalXRepository`, no write-ahead exists in `lib/`.**
- The only real `OrdersRepository` is `PostgresOrdersRepository`; the
  alternatives are `fakes/` and `unconfigured/`.
- Doc 08 itself records cost #2 honestly: *"No local write-ahead means no
  selling when the branch box is down."*

Consequences the audit set does not state plainly enough:

1. **A branch-server till today violates the product's own cardinal rule.** A
   rebooting switch, a sleeping host, or a mini-PC power cycle stops every
   till in the building mid-service. For a restaurant POS this is the
   headline failure mode — it is the reason the offline strategy document
   exists.
2. **Cloud mode currently has no real write path at all.** With POS-BE-006
   unbuilt and no queue, a `DeploymentMode.cloud` till can only run on
   `FakeOrdersRepository`. The three deployment modes in doc 08-deployment
   are a client-side configuration matrix, of which exactly one (branch
   server, LAN up) can take real money.
3. Docs 02, 03, 05 §22, 06 (Phase 7) and 07 describe machinery that was never
   built. A new engineer reading the set in order will design against a
   system that does not exist.

**Required actions**
1. Owner must either (a) reinstate the local write-ahead (doc 08's own listed
   mitigation — "the local outbound queue, still unbuilt, which would restore
   the write-ahead without changing this decision"), or (b) formally retire
   POS-R120–R130 and the doc-03 guarantee, and accept "branch box down = no
   sales" in writing. Option (a) is strongly recommended; it is the industry
   floor for restaurant POS.
2. Until then, stamp docs 02/03/07 with a superseded-by-08 banner the way 08
   stamps its own reversal. Doc drift in a money system is itself a defect.

### F-3 · HIGH (fiscal/ERP) — pricing authority currently lives on the till, and the DB grants can't contain it

With POS-BE-006 unbuilt, `TicketEngine` on each till is the pricing authority
(doc 08, accepted cost #3). In branch-server mode every till holds a
`pos_till` Postgres credential with `INSERT` on `pos_orders`/`pos_order_lines`
/`pos_payments`. The role model (no `DELETE`, no `UPDATE` on settled orders)
is good containment for *tampering with history* — but **nothing constrains
what an INSERT asserts**: a compromised or modified client can write any
totals, any discount, any tax figure, and they become the branch's books.
Server-side re-pricing (POS-BE-006) is the only real control, and it is the
one item everything already agrees is the blocking request. The audit says
"defensible but not centrally auditable"; from an ERP control standpoint it
should say **"unauditable revenue until BE-006 lands — approve it first."**

Interim hardening if BE-006 stays unapproved: move the money-path INSERTs
behind SQL functions (`SECURITY DEFINER`) that re-derive line totals from the
reference tables the till can already read, and revoke direct table INSERT
from `pos_till`. That gives branch-local re-pricing without waiting for the
cloud endpoint, and it reuses the schema unchanged.

### F-4 · HIGH (security design) — the offline PIN scheme is brute-forceable by construction

POS-BE-024 is correctly motivated (never distribute dashboard password hashes
to tills) and most of its asks are right. But the design ships `pin_hash` for
**every staff member** in the bootstrap bundle, stored on the till, verified
locally. A PIN keyspace is tiny (4–6 digits ≈ 10⁴–10⁶); any offline hash of it
falls to a laptop in seconds regardless of algorithm, and the requested
client-side rate limiting does not bind an attacker who has the disk. The
request's own threat model — "the blast radius of a stolen till should be the
till" — is met only if PINs are assumed burned the moment a till is stolen.

**Asks to add to POS-BE-024:** (a) key-stretch (Argon2id) so casual extraction
is annoying, but state in the contract that a stolen-device PIN is
*compromised, not protected* — the mitigation is revocation-at-next-sync plus
the PIN authorising nothing but the till (already asked); (b) encrypt the
bootstrap bundle at rest with a device-bound key (DPAPI/Keychain — the
machinery already used for the JWT); (c) per-user PIN lockout counters stored
server-side too, so a revoked PIN cannot be reinstated by wiping local state.

### F-5 · MEDIUM (fiscal) — provisional receipt numbering needs a jurisdiction ruling, not a design ruling

The provisional-then-authoritative invoice model (POS-BE-008, POS-R101) is
correct distributed-systems design and normal in Western markets. But the
declared target markets include Egypt and KSA. Egypt's ETA e-receipt regime
and ZATCA Phase 2 both constrain what may be *printed and handed to a
customer* at sale time — a renumbered-later provisional receipt may simply be
non-compliant where receipt clearing is mandatory. R-8 and POS-BE-017 flag
e-invoicing as out of scope/unverified, which is honest — but invoice
*numbering* is in scope and shipping now. This needs a per-market legal
answer **before** the numbering scheme hardens, because gap-free-at-print
requirements would invalidate the provisional design in that market, and the
fix (branch-local authoritative sequence — which the Postgres decision
incidentally already provides) changes POS-BE-008's shape.

### F-6 · MEDIUM (ERP completeness) — the audit set covers POS operations, not the ERP seam

For a system described as heading toward ERP territory, the following are
absent from all 24 requests and worth raising as explicit future items so
their absence is a decision (the doc set's own standard):

- **Business-date / EOD close.** Shifts are per-terminal; there is no branch
  business-day close, no "trading date" distinct from calendar date for a
  shift crossing midnight, and no consolidation point an accountant can
  reconcile to. X/Z per terminal does not aggregate to a day-close.
- **GL export / journal mapping.** Tender totals, tax lines, discounts and
  cash variance all exist in the model but nothing defines their mapping to
  accounts or an export (even CSV) for an accounting system.
- **Cash variance workflow.** Over/short is captured with reason (good), but
  there is no approval/write-off trail beyond the shift row.
- **Price-change audit.** `VariantPricingService` keeps prices in sync, but
  no history of *who changed a price when* exists — the first thing a
  franchise auditor asks for.
- Inventory/BOM is explicitly out of scope (correctly, with the
  `menu_item_id` prerequisite noted). Fine — but note that `order_items.
  menu_item_id` is also the prerequisite for all four bullets above, which
  strengthens the audit's own "approve this one item first" conclusion.

### F-7 · LOW (staleness) — the security audit predates the RBAC rework

The 2026-07-25 security audit states "XOrder has two roles only" and "no
staff/read-only role". The 2026-08-22 RBAC work (`roles` table,
`TenantCapability`, `RESTAURANT_STAFF`) supersedes that; §7's role matrix and
the "branch isolation not applicable" verdict need re-auditing against the
new per-verb model — in particular BE-A02's observation (any staff account
can see every branch's tills) is a *new* finding class the July audit could
not have seen. Its M-01 (client-trusted totals) remains open and is the same
root cause as POS-BE-006 — the three documents agree, which is a point in
favour of all of them.

---

## 4. What is genuinely strong (keep, and hold the line on)

Credit where due — these are better than most shipping POS products:

1. **The idempotency contract is stated exactly right** (POS-BE-007): same
   key ⇒ one record ⇒ *identical replayed 2xx body, never a 409*. Most teams
   get the 409 wrong and strand the ambiguous-timeout client. The Postgres
   implementation honours it (`ON CONFLICT … DO NOTHING` + read-back,
   replay does not consume an invoice number).
2. **Integer minor units with per-currency exponent**, three-decimal Gulf
   currencies handled, "never a JSON float", basis-point rates. Correct and
   rare.
3. **The never-brick-a-till doctrine** applied uniformly: licence expiry
   blocks the *next* shift, cash-up/reprint/export hard-coded ungateable,
   terminal revocation stops future trade but never erases queued money,
   seat overage warns rather than refuses. This is mature commercial
   thinking.
4. **Refunds as reversing counter-records**, settlement as a derived field
   (A4) rather than overloading the lifecycle enum, invoice number decoupled
   from the PK — all textbook-correct.
5. **POS-BE-019 (error taxonomy) and POS-BE-022's `pending_count` /
   `oldest_pending_at`** — "unsynced money per till, in real time" is exactly
   the fleet metric a platform operator needs, and few vendors have it.
6. **The pairing-code provisioning flow** (POS-BE-023) with hashed
   single-use codes, claim idempotency, and the recommendation against
   putting an admin password on a till.
7. **The licence format** — Ed25519 detached signature, deliberately not JWT,
   no `alg` field, byte-identical replay, honest "this is commercial hygiene,
   not security" framing, and the key-rotation stranding warning.
8. The **cross-checking discipline** between the two agents (A1–A7,
   BE-A01–A05 exchanges) caught real defects: soft-delete barcode
   uniqueness, tombstone gap on option groups, `implies()` dot-parsing,
   empty-`modes[]` brick. This channel works — which is exactly why F-1's
   broken `READY` matters so much.

---

## 5. Priority actions

| # | Action | Owner | Why first |
|---|---|---|---|
| 1 | Resolve F-1: produce the POS-BE-015 code on a pushed branch or demote to `IN_PROGRESS`; require commit hashes on every future `READY` | Backend | The channel's trust model is broken until then |
| 2 | Approve **`order_items.menu_item_id`** (T0.2) and POS-BE-006 | Owner | Unanimous conclusion of all three audits; unlocks server pricing, honest reporting, and every ERP item in F-6 |
| 3 | Decide F-2 explicitly — reinstate the local write-ahead queue (recommended) or retire the offline guarantee in writing; banner docs 02/03/07 either way | Owner | The flagship promise is currently false in code |
| 4 | Get a per-market ruling on provisional receipt numbering (Egypt ETA / ZATCA) before POS-BE-008 hardens | Owner | Cheapest now, very expensive after receipts are in the field |
| 5 | Amend POS-BE-024 with the stolen-till PIN reality (Argon2id + encrypted bundle + server-side lockout) | POS + Backend | Design-stage fix; retrofit is a fleet migration |
| 6 | Interim branch-mode control: SQL-function write path with server-side (branch-side) re-pricing, revoke raw INSERT | Backend/POS | Contains F-3 without waiting on BE-006 |
| 7 | Re-run the security audit's §7 role matrix against the new RBAC + BE-A02 | Security | Stale conclusions in a signed-off audit |
| 8 | Add F-6's ERP items (business-date close, GL export, price-change audit) as `POS-BE-xxx` entries so their absence is a decision | POS | The doc set's own stated standard |

---

*Method note: all ✅/❌ verdicts in §2 are from direct inspection of the two
repositories on 2026-09-01, branch `claude/audit-review-pos-erp-pz1pg5`. The
review deliberately did not assume any statement in any audit; where a claim
could not be checked (e.g. the live VPS items in the security audit's §15) it
is not counted for or against.*
