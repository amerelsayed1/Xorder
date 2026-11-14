# Food-service domain handbook (cafés, restaurants, food trucks, cloud kitchens)

The shared domain reference for every Xorder skill and agent. Read the sections the task needs, not the whole file. Written 2026-10-22.

**Evidence marks.** `✔` verified in this repo (file named; re-check before relying on it for money, state or permissions). `◐` general industry knowledge, not in the repo: use it to ask better questions, never as a requirement. `✗` gap: confirmed absent in source or docs. `?` unverified.

## 1. What Xorder is, and where it sells

- ✔ Two products on one tenant model: the **cloud platform** (QR menu, WhatsApp or in-system ordering, dashboard, plans, licences, purchasing) and the **offline-first desktop POS** whose own PostgreSQL branch server is the primary record (`apps/xorder-pos/docs/pos/15-competitive-position.md`).
- ✔ Market is Egypt first, then MENA: Arabic and RTL are first-class, default tax is Egyptian VAT 14% with a 12% service charge as provisional device defaults (`apps/xorder-pos/lib/domain/models/ticket.dart`, `tax.dart`), and the ETA e-receipt mandate has been in force since 2025-09-15 (signed receipt, store-and-forward within 24 hours, ETA QR on the printed copy; see doc 15).
- ✔ The landing page names the audience: restaurants, cafés, dessert shops, cloud kitchens, takeaway spots, food trucks and local food brands (`apps/xorder-cloud/apps/api/app/Models/LandingContent.php`).
- ✗ **The platform has no venue-type field.** No `business_type`, cuisine or vertical column exists. A venue is shaped only by feature flags, plan, order types and branch settings (`app/Enums/Feature.php`). Never write code or copy that assumes a type exists; say "a tenant with dine-in enabled", not "a restaurant".
- ✔ Competitors named in the repo: Foodics (incumbent), Marn, POSRocket, Odoo POS (already ships ETA in Egypt), Loyverse, Sapaad, Syrve, TouchBistro, Lightspeed, Toast.

## 2. The four venue models

| | Café | Restaurant | Food truck | Cloud kitchen |
|---|---|---|---|---|
| ◐ Service style | Counter, pay first | Table service, pay last | Window, pay first | No customers on site |
| ◐ Ticket | Small, very high volume | Large, long-lived open check | Small, event spikes | Medium, 100% remote |
| ◐ Speed target | Seconds per sale | Minutes per round | Seconds per sale | Prep and handoff minutes |
| ◐ Order channels | Counter, takeaway, QR | Table, QR, phone | Window, QR/WhatsApp pre-order | Own channel plus delivery apps |
| ◐ What hurts most | Queue at the till, modifier errors, drawer shortages | Wrong splits, voids after send, slow bill | No signal, power, running out of items mid-service | Wrong or late orders, commissions, channel menu drift |
| ◐ Tables and bill requests | Rare | Core | None | None |
| ◐ Kitchen flow | Bar/ticket printer | Fire rounds, courses, stations | One crew, no formal flow | Central display or printer, dispatch handoff |
| ◐ Stock pressure | Milk, beans, bakery | Broad ingredient list | Small, tightly counted | Heavy purchasing, packaging |

## 3. How Xorder serves each model today (✔ unless marked)

| Capability | State | Evidence |
|---|---|---|
| Cloud order channels | dine-in, pickup, delivery flags; QR menu; WhatsApp XOR in-system ordering (exactly one) | `Feature.php`, `OrderingMode.php` |
| POS order types | dine-in, takeaway (pickup is a synonym), delivery, drive-thru | `lib/domain/models/ticket.dart` |
| Dine-in needs a table; delivery needs a customer with an address | enforced before checkout | SRS `POS-R072`, `POS-R181` |
| Tables, dining areas, live floor, bill requests, move table | built; table management requires dine-in | `Feature.php`, `router.dart` |
| Hold and resume a ticket | built | SRS `POS-R034` |
| Modifiers, option groups, combos, per-branch pricing | built (Wave M) | `docs/pos/14-progress.md` |
| Multiple tax groups, zero-rated and exempt lines, non-taxable charges | built; aggregator-collected charges stay out of the VAT base | `tax.dart`, `service_charge.dart`, `ticket.dart` |
| Split tender, quick-cash, refunds as reversing records, voids with reason | built | `docs/pos/12-design-brief.md` (split tender), SRS `POS-R094`, `POS-R160`, `POS-R165` |
| Shifts, blind cash-up, variance reasons | built | SRS `POS-R143`, `docs/pos/13-pattern-handoff-review.md` |
| Purchasing and stock, **standalone** (a café or cloud kitchen may buy it with no till) | built, owner decision 2026-09-12 | `Feature.php`, `docs/backend/CB-09-cloud-purchasing-design.md` |
| Kitchen printing | in scope; `SENT_TO_KITCHEN` status exists; current print state `?` (the 2026-09-09 readiness audit says nothing printed, ESC/POS paths landed later) | `docs/pos/production-readiness.md`, `order_record.dart` |
| Kitchen display screen (KDS) | ✗ SRS non-goal for v1 (kitchen printing is in scope) | `docs/pos/02-pos-requirements.md` |
| Delivery-app integration (Talabat, Elmenus, Breadfast) | ✗ "not on the roadmap at all"; competitors lead here | `docs/pos/14-progress.md`, doc 15 |
| Card terminal integration | ✗ SRS non-goal (assumption A-3); not on the roadmap | `02-pos-requirements.md`, `docs/pos/14-progress.md` |
| Tips or gratuity | ✗ no concept in POS or cloud (service charge exists, tips do not) | grep of `lib/` and `app/` |
| Recipes and ingredient-level stock depletion | ✗ SRS non-goal for v1; "there is no recipe model"; CB-09 plans it as a later purchasing feature | `02-pos-requirements.md`, `profit_report.dart`, CB-09 |
| Loyalty, gift cards, store credit | ✗ SRS non-goal for v1 | `docs/pos/02-pos-requirements.md` |
| Multiple virtual brands from one kitchen | ✗ no brand concept | grep |
| Food truck that changes location | `?` how a moving truck maps to branches, hours and the QR menu is undefined | none |

Read the table as: **café** is well served at the till but tips, loyalty and modifier speed are open; **restaurant** is the best-served model; **food truck** fits through offline-first and QR pre-order but location, power and stock-out handling are undefined; **cloud kitchen** is weakest, because aggregators, a kitchen display and multi-brand are all absent while purchasing is ready.

## 4. Rules a domain expert applies (✔ from source and SRS)

- **Fired is different from unfired.** Removing an unsent line is routine; voiding a sent line needs `pos.void` and a reason code, and is planned to raise a kitchen void ticket with Wave F (SRS `POS-R160`, `docs/pos/11-gap-closure-plan.md` Wave A).
- **Money never gets edited.** Refunds and voids are counter-records against the original; a refund goes back per tender respecting `refund_allowed` (SRS `POS-R165`, refund flow A5 in `docs/pos/12-design-brief.md`).
- **Tax base.** Service is added to the subtotal after discount, VAT is computed on subtotal minus discount plus service, rounding is half-up once at the VAT line, and per-line tax groups are retained for the e-receipt (`POS-R076`, `ticket.dart`).
- **The till must never stop selling.** Idempotency by `client_transaction_id`, an outbox, no silent discards, an expired licence blocks only the next shift, never the open one (SRS `POS-R122`, `docs/pos/09-licensing.md`).
- **Cash-up.** Expected = opening float + cash sales + cash in − cash out − refunds; counted comes from a denomination count; variance above a threshold needs a reason; blind mode hides the expected figure (`POS-R143`, `POS-R144`).
- **Provenance.** Every discount, void, override, refund and drawer opening names who did it and who approved it, enforced by database constraints (doc 15).
- **Server authority.** The backend owns prices, totals and permissions; the till computes locally only to keep selling offline.

## 5. Abuse patterns to design against (◐ industry knowledge, with Xorder's control ✔)

Void after send and discounts (reason codes, approver, per-capability grants); refunds paid to cash (per-tender refund rules, shift report); drawer opened with no sale (cash movements are records); price overrides (audited, capability-gated); a cashier hiding a shortage (blind count, variance reason); in cloud kitchens, orders that exist in a delivery app but not in the system (`?` no aggregator link, so reconciliation is manual).

## 6. Questions an expert asks (use in plan, review, bug and audit work)

1. Which venue models does this change touch, and does it assume a table, a customer address, a cashier standing at a counter, or a stable network?
2. What happens at peak, mid-service, with a retry or a half-sent kitchen round?
3. Who can do this, who must approve it, and does the money trail show both?
4. Does a mixed basket (food plus packaged goods, zero-rated plus standard) still total, round and file correctly?
5. Does a cloud kitchen or food truck, which has no tables, no bill requests and possibly no till, still get a coherent experience?
6. Would an owner reading the Arabic UI or the end-of-day report understand it without training?
7. Which of tips, loyalty, recipes, aggregators or multi-brand does this feature silently depend on, and is that a known gap (section 3)?

## 7. Open domain questions (answer from the owner, then record here)

- Tips and gratuity: in scope for cafés? Pooled or per cashier?
- Food truck: one branch per location, or one branch with a moving address? How does the public QR menu announce today's location?
- Cloud kitchen: is delivery-app integration (Talabat, Elmenus, Breadfast) a v1 commitment, and is a kitchen display screen reconsidered?
- Venue type: should the platform ever store it (for defaults, onboarding, reports), or stay flag-driven?
