# Where XOrder POS stands against the market

**8 September 2026.** Written after Wave B. It answers two questions: what the
competition already does that we do not, and — more urgently — whether we can
legally be sold in our own target market.

The short answer to the second question is **not yet**, and that finding
reorders the plan.

---

## 1. The finding that matters

Egypt's Tax Authority B2C **e-receipt mandate has been in force since 15
September 2025**. It is not a forthcoming rule to plan around; it is a live
obligation on every named taxpayer, applying to *"every branch and every point
of sale."*

For a POS it requires four concrete things:

| | Requirement | We have |
|---|---|---|
| 1 | Every receipt digitally signed with the taxpayer's **e-seal (X.509)** | ✗ |
| 2 | Submitted to ETA in its **structured format**, over authenticated HTTPS | ✗ |
| 3 | Printed customer copies carry an **ETA QR code** linking to the record | ✗ |
| 4 | Transmitted **within 24 hours** of the ticket | ✗ |

A restaurant on the ETA list cannot legally run its tills on this build. That is
a harder gate than any feature on any competitor's brochure: a missing feature
loses a deal, this one makes the sale unlawful for the buyer.

### Our own documents saw it coming, and mis-rated it

`01-existing-system-analysis.md` carries it as risk **R-8**, rated *Medium*:

> *Tax/e-invoicing (Egypt ETA, KSA ZATCA) turns out to be in scope.* Out of
> scope for v1 and stated as such. The money model carries a `tax_lines[]`
> breakdown from day one so a compliance layer has something to attach to.

Two things have gone wrong with that entry.

**The risk is no longer conditional.** "Turns out to be in scope" describes
something that might happen. It has happened, on a date that has passed. R-8
should be re-rated **Critical**, and it is the only risk in that table that can
stop the product being sold rather than merely making it worse.

**The mitigation was never built.** There is no `tax_lines[]` anywhere in
`lib/`. `TaxConfig` carries two scalars — `serviceBp` and `vatBp` — and
`pos_orders` stores `service_minor` and `vat_minor` to match. That is enough for
a receipt and not enough for a filing: it cannot express two VAT rates on one
ticket, a zero-rated line, or a tax-exempt item, and those are ordinary in a
restaurant that sells both food and packaged goods. The thing that was supposed
to make a compliance layer attachable is the thing that is missing.

### One piece of good news, and it is architectural

The mandate permits **store-and-forward within 24 hours**. It does not require
real-time clearance the way Saudi ZATCA Phase 2 does for B2B.

`08-deployment-modes.md` worried about exactly this:

> *E-invoicing may not permit it.* Egypt's ETA e-receipt and Saudi ZATCA Phase 2
> both involve clearing receipts with the tax authority. An offline-only till
> cannot.

**It does permit it.** A till that sells through a network outage and submits
when the line returns is compliant — and that is precisely the machine we have
built. The outbox, the idempotency on `client_transaction_id`, the
"never silently discarded" rule on `OrdersRepository.submit`: all of it is the
right shape for an ETA queue. What is missing is a second destination and a
signature, not an architecture.

So the offline-first bet was correct, and the compliance work is smaller than
that document feared. It is still work nobody has started.

---

## 2. The competitive landscape

| | Model | Pricing | Position |
|---|---|---|---|
| **Foodics** | Cloud + own hardware | ~$53–106/mo/branch, hardware ~$930 | The incumbent. 36,000+ branches across GCC, Egypt and Jordan; acquired POSRocket in 2022 |
| **Marn** | Cloud | — | Saudi-native, leaning hardest into ZATCA, Mada and Arabic |
| **POSRocket** | Cloud, BYOD | ~$41–83/mo | Jordan; now inside Foodics |
| **Odoo POS** | Cloud or self-host | Module pricing | Present in Egypt **with ETA e-receipt** support |
| **Loyverse / Sapaad / Syrve / TouchBistro** | Cloud | Varies | Present but not Egypt-specialised |
| **Lightspeed / Toast** | Cloud | $0–189/mo + per-transaction | Global, thin MENA localisation |

### Where we are genuinely differentiated

**True offline-first, on the restaurant's own PostgreSQL.** Competitors list
"offline mode" as a degraded fallback — a cache that syncs back. Ours is the
primary datastore: the branch server *is* the record, and cloud is an optional
second destination. For an Egyptian restaurant on unreliable connectivity that
is a different product, not a better version of the same one.

**The money model.** Integer minor units throughout, half-up rounding applied
once, a golden-test suite pinning every total, and an append-only ledger where
voids and refunds are records rather than deletions. This is not marketing
surface — it is the part that survives an audit, and it is unusually strong.

**Arabic and RTL as a first-class citizen, not a translation.** Numbers stay
LTR by construction, currency sits on the correct side, and the design system
enforces it. Marn competes on exactly this ground in Saudi; we are at least its
equal for Egypt.

**Provenance.** Every discount, void, price override, refund and drawer opening
names who did it and who approved it, enforced by database constraints rather
than by application code. Most of the market records far less.

### Where we are behind

| Gap | Weight | Note |
|---|---|---|
| **ETA e-receipt** | **Blocking** | Section 1. Odoo already ships this in Egypt |
| Payment terminal integration | High | No Mada/Meeza/card-terminal integration. Competitors bundle it and take a cut |
| Delivery aggregators | High | Talabat, Elmenus, Breadfast. Egypt's restaurants live on these |
| KDS / kitchen printing | High | Wave F. Foodics's own weakness is being *POS-centric*, which is where we are too |
| Online ordering / QR menu link | Medium | XOrder's own QR product exists; the POS does not join to it yet |
| Inventory | Medium | Wave L, P1 |
| Multi-branch reporting | Medium | Wave G |

Foodics's stated weaknesses — POS-centric, no unified order stream, hardware
lock-in, per-transaction fees — describe openings. We do not currently exploit
any of them: we are more POS-centric than Foodics is, and we have no order
stream at all.

---

## 3. What this changes about the plan

The gap-closure plan sequences C → D → E → F → G, with §113 P0 complete at the
end of Wave G. That ordering is sound against the SRS and wrong against the
market, for one reason: **Wave C makes the product better; ETA makes it
sellable.**

### Recommended reordering

**Insert a Wave B½ — ETA e-receipt — before Wave C.** It is roughly Wave B's
size and it needs:

1. `tax_lines[]` on the ticket, the order and the receipt — the mitigation R-8
   promised. It must land *before* anything is filed, because retrofitting a tax
   breakdown onto orders already submitted is not possible.
2. E-seal certificate storage and per-receipt signing. The secret store and the
   keychain work already exist to build on.
3. An ETA submission queue. The outbox is the right shape; this is a second
   destination beside the platform, with its own retry and its own idempotency.
4. The QR code on the printed slip. `ReceiptPaper` is already the single place
   both the live receipt and the reprint go through.
5. A submission state on the order, and a screen that shows what has not cleared
   — because "which receipts has ETA not accepted" becomes a question somebody
   asks daily, and a queue growing where nobody looks is the failure mode this
   codebase has already been bitten by once.

**Then Wave C**, unchanged.

### One thing to confirm before building

The ETA mandate applies to **taxpayers named on a published list**, not to every
restaurant. Which of the target customers are on it decides whether this is a
gate on the first sale or on the tenth. That is a commercial question, and it is
worth answering this week rather than after the work is scoped — it is the
difference between reordering the plan and merely adding to it.

---

## 4. The missing-feature list, in full

Ordered by what stops a sale, not by what is hardest.

### Blocking — cannot sell without it

| | Gap | Note |
|---|---|---|
| B1 | **ETA e-receipt** | Section 1. e-seal signing, ETA format, QR on the slip, 24-hour queue |
| B2 | **`tax_lines[]`** | Prerequisite to B1, and cannot be retrofitted onto orders already filed |

### Table stakes — every competitor has these

| | Gap | Why it costs deals |
|---|---|---|
| T1 | **Combos / meal deals** | Ubiquitous in Egyptian QSR. A menu that cannot express "sandwich + fries + drink at one price" cannot price half the market's best-selling item |
| T2 | **Per-branch and per-channel pricing** | Delivery prices differ from dine-in almost universally. Foodics calls these Location Rules |
| T3 | **Payment terminal integration** | Meeza, Mada, card terminals. Competitors bundle it |
| T4 | **Delivery aggregators** | Talabat, Elmenus, Breadfast. Egyptian restaurants live on these |
| T5 | **KDS / kitchen printing** | Wave F. Currently a round is "sent" to nothing |
| T6 | **Branch-scoped user access** | Section 6 |
| T7 | **Product images** | The grid is text tiles. Every competitor shows pictures |

### Competitive — differentiates, does not gate

| | Gap |
|---|---|
| C1 | Inventory and recipes (Wave L) |
| C2 | Multi-branch consolidated reporting (Wave G) |
| C3 | Customer accounts and loyalty (Wave H) |
| C4 | Online ordering joined to XOrder's own QR menu |
| C5 | Time-based menus (breakfast until 11) |
| C6 | Menu engineering / profitability analytics — Foodics ships "Menuhat" |

### Already planned, unchanged

Waves C through L cover most of C1–C3. **Nothing in the plan covers B1, B2, T1,
T2, T3, T4 or T7.** That is the real result of this comparison: seven of the
gaps that decide a sale are not on the roadmap at all.

---

## 5. Menus — how they do it, how we do it

### Foodics

Categories → products → modifier groups → modifiers, plus three things we have no
equivalent for:

* **Combos.** A combo belongs to one category but can sit in several *menu
  groups*, each offering a choice. An `Include Modifiers` switch folds option
  prices into the combo price.
* **Modifier economics.** Per-link `Maximum Options`, **`Free Options`** (take
  two at no charge, then start charging) and **`Default Options`** (pre-selected).
* **Location Rules.** Products, prices, modifiers and availability are authored
  once and published per branch — and out to delivery channels — rather than
  every branch being identical.

### Ours

```
Category → Product → ModifierGroup → Modifier
```

`Product` carries `nameEn/nameAr`, `price`, `discountedPrice`, `sku`, `barcode`,
`isAvailable`, `sortOrder`. `ModifierGroup` carries `isRequired`, `maxSelect`,
`isVariant`. `Modifier` carries `priceDelta`.

Authored in **Management › Menu**, and **only on an offline terminal** — a cloud
till's catalogue is a cache the bootstrap seeder overwrites, so authoring there
would silently lose whatever was typed.

### The differences that matter

| | Foodics | Ours |
|---|---|---|
| Combos | ✓ | ✗ |
| Free / default modifier options | ✓ | ✗ |
| Minimum selection per group | ✓ | ✗ — only `isRequired` + `maxSelect` |
| Per-branch price or availability | ✓ | ✗ — one price per product per restaurant |
| Per-channel price (delivery vs dine-in) | ✓ | ✗ |
| Time-based menus | ✓ | ✗ |
| Product images | ✓ | ✗ |
| Publish to delivery channels | ✓ | ✗ |
| Per-product tax treatment | ✓ | ✗ — one VAT rate for the whole ticket |
| Barcode / SKU | ✓ | ✓ |
| Arabic name per item | ✓ | ✓ |
| Variant groups | ✓ | ✓ (`isVariant`) |

**The two that hurt most are combos (T1) and per-branch pricing (T2).** Both are
schema changes, and per-product tax treatment is quietly a *third*: it is a
prerequisite for `tax_lines[]`, so B2 and the menu model have to be designed
together rather than in sequence.

---

## 6. Permissions — how they do it, how we do it

### Foodics

Roles group **authorities** across roughly nine categories — Customer,
Inventory, Menu, Reports, Dashboard, Admin, Cashier App and others. A user is
assigned **roles *and* branches**, and privileges can be edited per user on top.
Two separate credentials: a console login for the back office, and a **5-digit
PIN** for the cashier app.

### Ours

**24 capability keys** in four groups (selling, money and corrections, the
drawer, back office), stored as `text[]` on both roles and people.

```
effectiveCapabilities = role.capabilities ∪ staff.capabilities
```

Four seeded roles — owner, manager, supervisor, cashier — per restaurant, with
the owner holding everything by an invariant the code enforces. Sign-in is a
**4-digit PIN**, PBKDF2-hashed with a per-person salt.

Two things here are genuinely stronger than the market:

* **Supervisor override.** A denied act can be approved once, at the till, and
  the record names *both* people. Most competitors have "you may or may not";
  this is "you may, with somebody watching", which is what actually happens in a
  restaurant at 8 p.m. on a Friday.
* **Enforcement in the database.** Column-scoped GRANTs mean a recovered till
  credential can void a sale and still cannot reprice one. The permission model
  is not the only thing standing between a cashier and the money.

### Where we are behind

| | Foodics | Ours |
|---|---|---|
| Permission count | ~9 categories, fine-grained | **24 keys** — the SRS asks for ~50 |
| Multiple roles per person | ✓ | ✗ — one `role_id` |
| Per-person **DENY** | ✓ (privilege editing) | ✗ — per-person keys are **additive only** |
| **Branch-scoped access** | ✓ | ✗ — `pos_staff.branch_id` exists and **nothing enforces it** |
| Per-person limits | ✓ | ✗ — discount ceilings are per *role* |
| Back-office login | Role-based console login | **A PostgreSQL password** |

### The one worth arguing about

**Management is gated on a database credential, not a permission.** A manager
who holds `staff.manage` still cannot open it without the `pos_admin` password.

That design is defensible and deliberate: the till's own role holds `SELECT` and
nothing more, so nothing a cashier can reach can write to staff or the menu even
if they get past a screen. It is stronger than the market's model.

It is also the reason "add an account" was hard to find, and it does not scale
to a restaurant group: sharing one Postgres password among branch managers is
the failure mode it was built to prevent, arriving by a different door.

**Wave C is where this gets decided.** The options are (a) keep the DB
credential and accept that the back office is an owner-only surface, or (b) move
to role-based back-office access and rely on the column-scoped grants, which are
already doing most of the work. Worth choosing on purpose rather than by
default — and note that (b) is what every competitor does, which is evidence
about expectations rather than about correctness.

---

## Sources

- [Egypt B2C e-Receipt Mandate 2025 — Flick Network](https://www.flick.network/en-eg/egypt-b2c-e-receipt-mandate)
- [Egypt E-Receipt Requirements: ETA Guide 2026](https://invoicedataextraction.com/blog/egypt-e-receipt-requirements)
- [KPMG — Egypt taxpayers required to comply with B2C electronic receipts mandate](https://kpmg.com/us/en/taxnewsflash/news/2025/01/tnf-egypt-taxpayers-required-comply-mandate-electronic-receipts-b2c-transactions.html)
- [Odoo Arabic POS Egypt: ETA E-Receipt](https://www.2b-cs.com/blog/2b-1/odoo-arabic-pos-egypt-55)
- [Top 5 Restaurant Platforms in MENA 2026 — Nexara](https://nexaratech.io/blog/top-5-restaurant-platforms-mena-2026.html)
- [Foodics vs Marn — KSA 2026 comparison](https://onlineemenu.com/foodics-vs-marn-vs-online-emenu-ksa-2026.html)
- [Foodics acquires POSRocket](https://www.foodics.com/press/foodics-acquires-posrocket-and-becomes-the-dominant-restaurant-tech-provider-in-mena/)
- [Foodics 2026 company profile — Tracxn](https://tracxn.com/d/companies/foodics/__R_zx5F2iPfMysLqTKKq2aKbnJManfVDv23k0mPI436w)
- [Foodics — Getting Started with Menu](https://help.foodics.com/hc/en-us/articles/5760241465884-Getting-Started-with-Menu)
- [Foodics — Creating Combos](https://help.foodics.com/hc/en-us/articles/4404645953938-Creating-Combos)
- [Foodics — Linking Modifiers to Products](https://help.foodics.com/hc/en-us/articles/4404348413202-Linking-Modifiers-to-Products)
- [Foodics — Creating Roles](https://help.foodics.com/hc/en-us/articles/4406747372178-Creating-Roles)
- [Foodics — Creating Users for Employees](https://help.foodics.com/hc/en-us/articles/8160626160924-Creating-Users-for-Employees)
- [Foodics — Adding Branches to Users](https://help.foodics.com/hc/en-us/articles/4406606302482-Adding-Branches-to-Users)
- [Foodics — Cashier user login PIN](https://help.foodics.com/hc/en-us/articles/6753435391516-Creating-Changing-the-Cashier-User-Login-Pin)
- [Menu management across delivery apps — LYNNC](https://lynnc.io/blog/menu-management)
