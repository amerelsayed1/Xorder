# Back office → cloud — handoff

**From:** XOrder POS (Flutter, `xorder-pos`) · **To:** `xorder-cloud` agent
(platform, `xorder-new`) · **Written:** 2026-09-11 · **Last updated:** 2026-09-22

Kept identical in both repos' `docs/coordination/`. The `xorder-cloud` agent owns
this file's statuses. `pos-dev` may append questions at the bottom.

---

## 1. What is being handed off, and why

The till's back office was built **offline-first**: on an offline install the
desktop is the only back office there is, so 15 Management panes were built on
the till. The plan was always that the cloud restaurant's back office lives on
the platform (`xorder-pos/docs/pos/17-sales-and-payments-plan.md` §6: *the till
never becomes the cloud dashboard*). Doc 16 §5 left the question of what the
cloud story actually looks like open. This handoff answers it with a backlog.

**Everything below is handed off.** The offline panes stay as they are. They are
the offline product and are not changing. Your job is the cloud counterpart.

**Status of every item: `PROPOSED`**, except CB-00 (`DONE` 2026-09-11),
CB-01 (`DRAFTED — awaiting owner`, see §4a), CB-09 (`BUILT — slices a–e;
on feature branches, not merged to main, not deployed`, 2026-09-13), and —
since the owner's 2026-09-22 go ("hand A3 and A7 to xorder-cloud") — CB-08's
platform half and CB-10's refunds bullet, both `BUILT` on the xorder-new branch
`pos/cloud-refunds-receipt-profile`, not pushed and not deployed. Nothing else
here authorises implementation. Each `CB-xx` needs an explicit owner go.

---

## 2. The one rule that shapes all of it: one author per row

From `16-back-office-scope.md` §1 and the 2026-09-06 owner ruling in
`POS_TO_BACKEND.md`: on a **cloud** terminal the platform authors and
`BootstrapSeeder` overwrites (it DELETEs and re-inserts `pos_categories`,
`pos_products`, modifiers and `pos_dining_tables`, and upserts `pos_staff`,
deactivating anyone the bundle doesn't name). On an **offline** terminal the till
authors and the platform never sees it. There is no merge path, and none should
be designed.

What the till does today on a cloud terminal (`management_screen.dart`):

| Pane | Area | On a cloud till today | Who owns the rows on cloud |
|---|---|---|---|
| Staff | People | shown; identity comes from the platform | platform: name, username, PIN, capabilities, active |
| Roles | People | shown | **two authors, additive** (corrected 2026-09-11, §4a Q3): platform grants are the floor, and till-local roles can only add to them |
| Menu | Menu | **hidden** (`_authoringPanes`) | platform |
| Floor | Menu | **hidden** | platform |
| Taxes | Money | **whole pane** gated off (corrected 2026-09-11) | platform (POS-BE-013); see the §4a Q1 caveat on `pos_tax_groups` |
| Service charges | Money | shown, editable | **two authors** (confirmed 2026-09-11): the platform's first percent charge applies until the till has any local row, and then the local rows win |
| Payment methods | Money | shown, but edits silently do nothing (the till fix is in progress 2026-09-11, `pos-dev`) | **platform** (POS-BE-013, amended 2026-09-11 when the owner's go fixed the tender-id defect): the till seeds `pos_tender_types` from `money.tender_types` and pays with platform ids; the platform never delivers an empty list. Before the fix: nobody, just the seeded four, with the platform's list ignored |
| Order types | Money | shown read-only ("comes from the platform") | **split** (corrected 2026-09-11): the platform picks which types a branch offers, and the rules are frozen at the seeded defaults with no author |
| Purchasing | Buying | shown if `purchase.manage` | **till-local only**; suppliers, POs, supplier invoices, supplier payments |
| Receipt | Compliance | shown | **till-local** (`pos_receipt_profiles`) |
| ETA | Compliance | shown | till (e-receipt submission is a till job) |
| Activity | System | shown | till-local `pos_audit_events`; not synced |
| Backup | System | shown if `backup.manage` | till; on cloud the platform is the durable copy |
| Items (stock) | Inventory | **hidden** (seeder deletes products) | nobody on cloud today |
| Units | Inventory | shown if `purchase.manage` | **till-local** (`pos_units`, commit `4417b6c`) |

**The contradictions this table exposes are the first thing to decide** (§5).

> **Corrected 2026-09-11 by the CB-01 draft (§4a), from reading the code.** The
> original text said service charges, payment methods and order-type rules were
> each "authored locally on a cloud till *and* sent by the platform". That is
> true of **service charges only**. **Payment methods have no author on cloud:**
> the till never reads `money.tender_types`, and its own editor is disabled
> there. **Order-type rules have no author on cloud either:** the pane is
> read-only, and the platform sends no rules. **Roles *are* a second
> two-author case** that the table missed: a till-local role adds to what the
> platform granted, and it survives every reseed.
>
> **Updated 2026-09-11 (owner go: fixed as a defect).** Payment methods now have
> an author on cloud: the platform, per POS-BE-013. See §4a Q1.

---

## 3. What the platform already has

Verified in `apps/api` on 2026-09-11. "Present" means the code is in the tree.
Whether it's deployed to xorder.io is a separate question: Cloud Wave 1 was
smoke-verified locally, and its production deploy was pending the owner's go.

| Concept | Platform |
|---|---|
| Staff + roles (TenantCapability incl. `pos.*`), POS PIN | present: `StaffController`, `RoleController`, `PosPinController`, POS-BE-024 READY |
| Menu, categories, option groups, combos, dining areas, tables | present |
| Tax rules, charges, tender types | present: POS-BE-013 READY, `PosMoneyView.vue`, delivered in the bootstrap `money` block |
| Terminals, pairing, fleet, licences | present: POS-BE-022/023 READY, `PosTerminalsView.vue`, admin licence pages |
| Orders + payments from the till, shifts, cash movements | present: POS-BE-006/007/008/009 READY |
| Refunds from the till | present since 2026-09-22: POS-BE-010 **READY** (`PosRefundService`, `pos_refunds`), on a branch, not deployed |
| Customers | present on the web (`CustomerController`); POS-BE-014 APPROVED, not built |
| Reports | present for QR orders (`ReportController`, product/areas pages); not POS-aware |
| Receipt profile | present since 2026-09-22: `receipt_profiles` + `PosReceiptView.vue`, delivered as the bundle's `receipt_profiles[]` (A3); on a branch, not deployed |
| Order-type rules, units, stock items, suppliers, purchasing, expenses, POS audit sync | **absent**, no models |
| Branch sales read for a cloud till | **absent**: POS-BE-029 PROPOSED |

Uncommitted in the tree right now (staged, not yours to discard):
`apps/api/database/migrations/2026_09_06_000200_add_max_users_to_pos_licences_table.php`.

---

## 4. Backlog

Sizes: S/M/L. "Contract" means a `POS-BE-xxx` is needed before the till can use
it, and the next free number is **030**.

### CB-00: Reconcile the coordination files · S · do first, no go needed · **`DONE` 2026-09-11**

> **Done 2026-09-11 (`xorder-cloud`).** `POS_TO_BACKEND.md`: the xorder-pos copy
> was a superset, except for one passage. xorder-new still had the 2026-08-26
> wording of the "catalog stays authored in the cloud dashboard" bullet, and it
> is superseded by the 2026-09-06 narrowing ("on a CLOUD terminal"), which is
> kept. xorder-new gained POS-BE-029 and the 09-06 and 09-10 log rows.
> `BACKEND_TO_POS.md`: xorder-new's §023 "platform-side front door" amendment
> and its 09-05 log row, and xorder-pos's §022 2026-09-06 amendment, are both
> kept. They touch different passages, so nothing conflicted. No status
> differed. Both change logs were re-sorted by date, and a 2026-09-11 row was
> added to each. `diff` of each pair is empty.

The two repos' copies have drifted. The POS copy of `POS_TO_BACKEND.md` is newer
(1827 vs 1698 lines, carrying the 2026-09-06 offline-authoring ruling and
POS-BE-029). `BACKEND_TO_POS.md` differs in **both** directions (each side has an
amendment the other lacks). Merge them into one text, and write it to both repos.
*Accepted when* `diff` of each pair is empty and no amendment was lost.

### CB-01: Decide and document the cloud ownership map · S · docs only · **`DRAFTED — awaiting owner`**

> Draft with recommendations: §4a. **Not a ruling.** Nothing is recorded in
> `BACKEND_TO_POS.md` until the owner rules.

Turn §2's table into a ruling for each row: platform-authored or till-local on
cloud. Put it to the owner with a recommendation. Everything below depends on
it. Record the ruling in `BACKEND_TO_POS.md` and here.

### CB-02: Payment methods and service charges, one author · M · contract

> **Payment methods settled 2026-09-11 (owner go: fixed as a defect).** Tender
> ownership on cloud follows POS-BE-013: the platform authors, and the till
> seeds `pos_tender_types` from the bundle and pays with platform ids. This
> went in as an amendment to POS-BE-013, not a new contract. The platform
> creates default Cash + Card at a POS restaurant's first terminal, so the
> list is never empty. **What is left of CB-02 is service charges** (owner
> question 1). The richer tender fields in the §4a map (`code`, `name_ar`,
> `counts_as_cash`, `opens_drawer`, `requires_reference`, `refund_allowed`,
> one `kind` vocabulary) were not part of the fix. They'd need their own
> contract if the owner wants them.

The original brief follows. Today the till authors both locally on cloud *and*
the platform sends `charges` and `tender_types`. Recommendation: the platform authors them on cloud (it
already has the models, controllers and `PosMoneyView`). The till's panes then go
read-only on cloud, exactly as the tax half already does. Needs the owner (CB-01).
The till side is `pos-dev`'s work, triggered by your contract.

### CB-03: Order-type rules on the platform · M · contract

Till commits `dbf8d21`, `66e72b1` and `8e8ecdd` (§31): each order type carries
its own rules (what it requires, on/off per row, what counts as seated).
Platform has only `branches.supported_order_types`. Build the authoring page and
a bundle block; bump `pos_config_version` on write.

### CB-04: Named tax rates and per-product tax assignment · M · contract

Till commits `15d7be7` and `7e1a8e0`: products can sit on a named rate
(`pos_tax_groups`). The platform has `TaxRule` with `applies_to`. Verify whether
it expresses "this product is on rate X". If not, extend it additively and carry
the assignment in the bundle's catalogue.

### CB-05: Catalogue parity in the bundle · S–M · verify first

Verify what `PosBootstrapService::catalog()` sends against what the till's
offline menu supports: per-branch prices (`pos_product_prices`), combos, barcode
and SKU (POS-BE-004 APPROVED, not built), tax groups (CB-04). List the gaps and
file contracts for any the owner wants.

### CB-06: POS roles on the platform, or not · M · owner decision

Wave C built rich till-local roles (multiple roles, per-person overrides,
numeric ceilings, risk levels, no-escalation). The platform has per-restaurant
`roles` with `TenantCapability`. Options: (a) keep roles till-local on cloud, as
today, or (b) author them on the platform and send them. (b) means one role per
person across tills, but it's a large contract. Write up both; don't build either.

### CB-07: Back-office sign-in on cloud · S · docs + small web · **`BUILT` 2026-09-27**

Commit `b0ab577`: the till's back office opens with a username plus the database
back-office password. On cloud, a manager should be sent to the dashboard
instead. Decide what the till shows on cloud (a link to `/admin`?). This is mostly
a ruling; the web side is the dashboard's existing login.

> **2026-09-27 (owner go).** Ruled: **the whole back office**, not part of it.
> A cloud till shows a signpost — `CloudBackOfficeScreen` — naming the
> dashboard and nothing else. No panes, no read-only mode, no edits.
>
> The reasoning is §2's, applied honestly: the platform authors every row a
> Management pane would edit, so an edit made on a cloud till survived only
> until the next bundle landed on top of it. That is worse than no edit,
> because it looked like it had worked.
>
> Enforced at the ROUTE (`lib/app/router.dart`), not on the doors that open
> it — Management is reached from the start screen, Ctrl+Shift+S, the status
> bar and deep links that name a pane, and a guard on any one of those is a
> guard somebody adds a fifth way around.
>
> **The address is derived, not sent.** `dashboardAddress()` builds it from the
> platform URL and tenant slug the till already has, and answers null rather
> than guessing — a wrong address sends a manager to a certificate warning or
> to somebody else's restaurant. If the platform ever wants to name it
> explicitly, a `dashboard_url` on the bundle would be the place.
>
> Selling, shifts, the drawer and cash-up are untouched and still work with no
> internet. Those are facts about this terminal, not rows the platform owns.

### CB-08: Receipt profile · S · owner decision · **platform half `BUILT`**

> **2026-09-22 (owner go: "hand A3 and A7 to xorder-cloud", item A3).** The
> platform now authors the legal identity on a cloud till's receipt, and the
> bundle carries it as a **new key, `receipt_profiles[]`** — one row per active
> branch, field names copied one for one from the till's
> `pos_receipt_profiles` columns so its seeder is a straight mapping. A branch
> nobody has authored is *projected* from the restaurant rather than omitted,
> because a missing row is exactly what made every cloud till print with
> compiled-in defaults.
>
> **Where it is authored:** a dedicated page, Settings → Point of sale →
> **Receipt details** (`apps/web/src/pages/dashboard/PosReceiptView.vue`), not
> the branch form — a receipt profile is a POS and e-receipt concern, the
> Branches page is shared with tenants that never bought the till, and the
> money config next door is the established home for "platform authors, till
> reads". Endpoints `GET /api/dashboard/receipt-profiles` and
> `PUT /api/dashboard/receipt-profiles/{branch}`, gated `feature:pos` +
> `can:settings.view` (+ `can:settings.update` + `subscription.writable` to
> write); cross-tenant branch → 404; every write bumps `pos_config_version`;
> a `revision` guard refuses a stale save with 409. EN + AR, RTL.
>
> **One author per row, kept:** `registration_number` is the restaurant's
> single copy (`restaurants.tax_registration_number`) projected into every
> profile — one taxpayer has one number, and a per-branch copy would be a
> second author. `branch_code` is ETA's branch code and is deliberately **not**
> `branches.code` (the invoice prefix); the form says so in both languages.
>
> **CLOUD_WAVE1 deviation 6 is closed in the same change:**
> `UpdateRestaurantProfileRequest` finally accepts `tax_registration_number`,
> so the number has an authoring path for the first time, and changing it bumps
> `config_version`.
>
> **Two owner decisions I did not take.** (1) The page reuses
> `settings.view`/`settings.update` rather than minting a
> `pos.receipt_profile` TenantCapability — the legal identity on a slip is the
> same class of fact as the tax registration number `settings.update` already
> authors, and a new checkbox would leave every role that can edit tax unable
> to edit the header it prints on. Reversible for one enum case, one label pair
> and a grant on every role. (2) **Print LAYOUT preferences stay till-local**,
> per the §4a map's split; only the identity half moved. Nothing decides
> whether a cloud till should stop offering its own Receipt pane — that is
> `pos-dev`'s, and it needs the CB-01 ruling.
>
> Wire shape: `BACKEND_TO_POS.md` §023, "Amendment 2026-09-22 (A3)". On branch
> `pos/cloud-refunds-receipt-profile` in xorder-new; **not pushed, not
> deployed**. The till half (seeding `pos_receipt_profiles` from the bundle and
> making the pane read-only on cloud) is `pos-dev`'s.

`pos_receipt_profiles` (commit `f7208b0`: who the slip says sold the food) is
till-local on both. Decide whether a cloud restaurant sets it once on the
platform (the restaurant profile already carries `tax_registration_number`).

### CB-09: Purchasing, suppliers, units, stock on cloud · L · **`BUILT — slices a–e; on feature branches, not merged to main, not deployed`**

> **Owner decisions 2026-09-12.** (1) On cloud the platform is the only author
> of purchasing and receiving (D1). (2) `purchasing` is a **standalone** plan
> feature and **does not depend on `pos`** (D6, amended by the owner). Any
> client type (restaurant, café, cloud kitchen, and so on) can have it, with
> or without a till, so there is no `pos` in its gate stack, entitlement or
> navigation, and new copy uses neutral wording ("business"/"client",
> "النشاط"/"العميل"). (3) One capability, `purchase.manage`, gates reads and
> writes (D7). (4) Slices a, b and c are approved, built in that order with an
> owner review between slices. Slice a (suppliers, units, the feature, the
> capability, and the D8 bundle filter) is committed as `dd9a530` on the
> xorder-new branch `feat/cb-09-purchasing`. Slice b (stock items, purchase
> orders, receiving at the till's moving-average cost, the per-branch stock
> ledger and "received to date", and their pages) is committed as `bcb092c`
> (design §14). Neither is deployed. **2026-09-13, the owner: "finish all
> phases".** Slice c, committed as `3c4181e`, is supplier invoices, supplier
> payments allocated to invoices (never above an invoice's total, enforced
> under a row lock and proved concurrently on PostgreSQL), derived supplier
> balances and the supplier account page (design §15). **D11 is decided and
> built on the platform:** a part-received order can be closed short to
> `received`, marked closed short with a reason, and stock is never touched.
> **D12 is decided and built on the platform (slice d, design §16), the last
> platform slice:** opening stock, waste, adjustments up and down, and stock
> counts, per branch. Each is one immutable movement in the same ledger,
> carrying a reason code, a note and the actor, and it is audited. Openings
> and rises enter at moving-average cost; waste and falls leave at the
> average and may go below zero, as on the till. A count posts counted minus
> recorded under the level lock, and a movement never converts units or
> touches an order. The Stock page is now headed "Recorded stock". Slice d is
> uncommitted and not deployed. Returns to a supplier are an open owner
> question. The offline till's own short-close and stock entries are separate
> `pos-dev` items. Slice e (the till side) is `pos-dev`'s. POS-BE-030 is not
> filed from here.
>
> **Designed 2026-09-12 (`xorder-cloud`), after the owner's "go CB-09".** The
> go was taken as design only: the design comes back for review before
> anything is built. No code, migration or test was written. Design, with a
> recommended answer for each question and item-by-item approval points:
> [`xorder-new/docs/backend/CB-09-cloud-purchasing-design.md`](../backend/CB-09-cloud-purchasing-design.md).
> In brief: on cloud the platform is the only author of purchasing and stock.
> There is a new `purchasing` plan feature (standalone since the owner's
> 2026-09-12 ruling; the original design had it require `pos`) and one
> `purchase.manage` capability, the till's own name. Stock items get their own
> table, not a `MenuItem` flag. Valuation is the till's moving average, and
> neither side deducts sales. The till's buying and inventory panes are hidden
> on cloud. One draft contract, text in the design, is to be filed as
> POS-BE-030 on approval. It also records four places where the till's code
> and doc 16 disagree (design §10). Nothing here authorises implementation:
> each slice needs its own go.

Till-local only: `pos_suppliers`, `pos_purchase_orders`/`lines`,
`pos_supplier_invoices`, `pos_supplier_payments`, `pos_units`, `pos_stock_levels`,
`pos_stock_movements`, stock-only items. On cloud the Items pane is hidden
because the seeder would delete stock-only products. This is doc 16's
purchases → cost → inventory → COGS chain. Doc 16 §5 Q1–Q2 are the owner's:
is it a cloud v1 feature, and is inventory v1 at all? Write the proposal
(platform tables mirroring the till's, integer thousandths for quantity, no
stored supplier balance) and stop there.

### CB-10: The money facts that don't reach the platform · M · backend half only · **refunds `BUILT`**

> **2026-09-22 (owner go: "hand A3 and A7 to xorder-cloud", item A7).**
> **POS-BE-010 is built, tested and `READY`** — `POST /api/pos/refunds` +
> `GET /api/pos/refunds/by-client-id/{uuid}`, reversing records that never
> touch the original order, credit notes in their own `CN-` sequence bucket,
> cumulative quantity AND money checks taken under the order's row lock,
> idempotent per POS-BE-007. The reason no cloud till had ever uploaded a
> refund is also fixed: `POST /api/pos/orders` now accepts
> `lines[].client_line_id`, so a refund addresses lines by a key the till owns
> and never needs a platform order-item id. `OrderStatus` was deliberately
> **not** extended — refund state rides the derived `settlement_status`
> (`PARTIALLY_REFUNDED` / `REFUNDED`, the till's own `PaymentStatus` words).
> Shift cash-up now subtracts cash refunds. Wire shape and every recorded
> deviation: `BACKEND_TO_POS.md` §010. On branch
> `pos/cloud-refunds-receipt-profile` in xorder-new; **not pushed, not
> deployed**. The till half (queueing and draining refunds) is `pos-dev`'s.
>
> **Still open in CB-10:** the business-day field on orders, and POS-BE-021.

Plan 17 §6 C1 findings (2026-09-10). Backend-side gaps, yours:
- ~~**POS-BE-010 refunds**: APPROVED, unbuilt. Build `POST` refunds as reversing records.~~ **Done 2026-09-22, see above.**
- **Business day on orders**: §006 doesn't carry it, and POS-BE-029 needs it.
  Propose an additive field.
- **POS-BE-021 bulk sync**: APPROVED, unbuilt; the till's post-delivery
  payments and refund links need it.
Till-side gaps (discount not sent, on-account sent as paid, shifts and cash
movements not queued) are `pos-dev`'s. Note them, don't fix them.

### CB-11: POS-BE-029, the branch sales read · M · contract exists

`GET /api/pos/branch/sales/summary` and `GET /api/pos/branch/sales`. The full wire
shape is in `POS_TO_BACKEND.md`, and the till client is already built against it.
Device token plus `pos.reports`, requesting terminal's branch only, 404 otherwise.
Reply in `BACKEND_TO_POS.md`.
*Note (2026-09-11):* the platform has **no** `pos.reports` TenantCapability
(`apps/api/app/Enums/TenantCapability.php:93-106`). The platform's
`reports.view` is what reaches the till: the bundle sends it as-is, and it is
already the till's canonical name (`permissions.dart:93`). The reply must name
the real gate, which is probably `reports.view`, or add `pos.reports` with a
label in both languages.

### CB-12: The cloud sales dashboard (C3) and sync health (C5) · L

The cross-branch view the till must never become: KPIs by branch, terminal and
tender; refunds; AR and aging (after S4 and customers). C5 is a per-business-day
till-vs-platform count and sum, keyed by client ids. Depends on CB-10. Specify
it in `docs/backend/` first.

### CB-13: POS audit trail on the platform · S–M · owner decision

`pos_audit_events` never leaves the till. Decide whether cloud managers see void,
refund and override events in the dashboard (`AuditLog` exists). If so, it
rides the sync contract.

---

## 4a. CB-01 draft — awaiting owner ruling

**Status: `DRAFTED — awaiting owner`.** Written 2026-09-11 by `xorder-cloud`.
This is a **proposal**. Each claim below was checked by reading the code on
2026-09-11. Nothing was run. Paths: *POS* = `xorder-pos/lib/…`,
*API* = `apps/api/app/…`.

### Q1. Money: does a cloud till use the bundle's `charges` and `tender_types`?

**Tender types: no. The platform's list is ignored.**
- The seeder stores the whole `money` block in `pos_money_config.payload`
  (POS `data/cloud/bootstrap_seeder.dart:179-191`). Its only reader is
  `moneyConfigProvider` (POS `app/providers.dart:1149-1178`), which calls
  `MoneyConfigCodec.toTaxConfig`. That reads `charges`, `tax_rules` and
  `tax_mode`, and **never** `tender_types`
  (POS `data/postgres/money_config_codec.dart:21-43`).
- The payment screen reads `pos_tender_types` (POS `app/providers.dart:2098-2113`).
  If that table is empty, it uses the hardcoded `TenderMethod.seeded` with
  ids 1–4 (POS `data/postgres/postgres_tender_types_repository.dart`;
  `domain/models/tender_method.dart:115-146`).
- The Payment methods pane is shown on cloud, but `_edit` returns straight away
  when `catalogAdminRepositoryProvider` is null
  (POS `features/admin/presentation/management_tenders_pane.dart:36-37`). That
  provider is null outside offline (POS `app/providers.dart:1874`). **On cloud,
  tapping a row does nothing, and no notice is shown.** The pane's doc comment
  says a cloud restaurant can say what it accepts (`:18-20`). The code does
  not allow it.
- **This is a defect beyond ownership: the tender ids come from two different
  sets.** The drain sends the till's local `tender_type_id`
  (POS `data/cloud/outbox_drain.dart:301-312`). The platform checks it against
  its own tenant-scoped `TenderType` ids (API `Services/PosOrderService.php:401-416`).
  So a cloud payment with local id 1–4 is either refused with 422 "Unknown tender
  type", or it matches a *different* platform tender whose id happens to be
  1–4. The two sides also use different `kind` vocabularies. The platform
  allows `cash|card|external|other` (API `Http/Requests/Dashboard/StoreTenderTypeRequest.php:19`),
  and the till allows `cash|card|wallet|account|voucher|other`
  (POS `data/postgres/migrations.dart:2208`). Found by reading only, not
  reproduced.
  **Owner go 2026-09-11: fixed as a defect.** The fix is an amendment to
  POS-BE-013 (see `BACKEND_TO_POS.md` §013), not a POS-BE-030. Platform side:
  a POS restaurant's first terminal (provision or register, with claim as the
  backstop) creates default Cash + Card when the restaurant has no tender types
  (API `Services/PosProvisioningService.php`, `ensureDefaultTenders`). So
  `money.tender_types` is never empty. Till side (`pos-dev`): on cloud, seed
  `pos_tender_types` from the bundle and pay with platform ids, never null
  (the shift report counts a null tender as cash). The `kind` vocabulary gap
  is **not** closed by this; it stays with CB-02's optional richer fields.

**Service charges: the platform's first percent charge applies, until the till
has one local row. After that the till wins completely.**
- The codec keeps only the **first percent** charge, as `serviceBp` plus
  dine-in-only (`money_config_codec.dart:25-37`). It drops fixed charges,
  `taxable`, and every charge after the first.
- `taxConfigProvider` replaces that result with the local `pos_service_charges`
  rows whenever there are any (POS `app/providers.dart:1071-1074`). After that,
  `serviceFor` uses only the local rows (POS `domain/models/ticket.dart:491-513`).
- Local writes are not blocked on cloud. `save()` checks only the admin
  credential and `settings.manage`
  (POS `data/postgres/postgres_service_charges_repository.dart:72-96`), and the
  pane is not in `_authoringPanes` (POS `features/admin/presentation/management_screen.dart:102-106`).
  This is a real two-author case.

**Taxes: the platform's rate applies. One caveat was not verified.** The pane
is fully blanked on cloud (`management_taxes_pane.dart:161,184-193`), not half
of it. The rate is the first `tax_rules` entry (`money_config_codec.dart:28`).
Its `applies_to` scope is ignored. *Caveat:* when a local default row exists in
`pos_tax_groups`, `defaultTaxGroup` uses that row's rate instead of the
platform's `vatBp` (POS `domain/models/ticket.dart:396-409`;
`app/providers.dart:1082-1083`). The setup wizard's `bootstrapDatabase` seeds a
1400 bp default group (POS `features/setup/application/setup_controller.dart:436`),
and cloud setup runs that path too (`:461-464`). **Not verified:** whether that
row sits under the same restaurant id the seeder later writes. `seedRestaurant`
keys on the slug, while the seeder upserts on the platform id. If it does, a
cloud till charges 14% whatever the platform says. This is for `pos-dev` to
check, and it belongs to CB-04.

### Q2. Order types: `pos_order_types` vs `branch.supported_order_types`

- **Which types a branch offers comes from the platform.** The seeder writes
  `pos_branches.supported_order_types` (POS `bootstrap_seeder.dart:121-139`),
  and `branchOrderTypesProvider` filters on it (POS `app/providers.dart:1044-1056`).
- **What each type requires, what it is called, and whether it is on comes from
  local data nobody can edit.** `orderTypeRulesProvider` reads `pos_order_types`,
  or `OrderTypeRules.fallback` (POS `app/providers.dart:1004-1019`). The seeder
  never touches that table. On cloud the pane shows `orderTypesComeFromPlatform`
  and disables every edit (POS `features/admin/presentation/management_order_types_pane.dart:68-69,98-122`),
  but **the platform sends no rules.** The rules are frozen at the seeded four.
- The platform's two branch requests disagree on the vocabulary.
  `StoreRestaurantRequest` allows `dine_in|pickup|delivery`
  (API `Http/Requests/Admin/StoreRestaurantRequest.php:108`), and
  `UpdateBranchRequest` allows `dine_in|takeaway|delivery|drive_thru|pickup`
  (API `Http/Requests/Dashboard/UpdateBranchRequest.php:60`). The till maps
  `pickup` to `takeaway` (POS `domain/models/ticket.dart:35`).

### Q3. Roles: `pos_staff.role_id` / `pos_roles` vs platform `roles`

- The bundle sends each person's `role_id` and resolved `capabilities`
  (API `Services/PosBootstrapService.php:249-264`). The owner gets every
  TenantCapability (API `Models/User.php:131-142`).
- The seeder upserts `pos_staff.capabilities` as the canonicalised platform set.
  It **never writes** `role_id`, `pos_roles`, `pos_staff_roles`, overrides or
  limits (POS `bootstrap_seeder.dart:194-242`). The platform's `role_id` is
  dropped.
- On cloud the till still lets a manager change `role_id`. `update()` refuses
  name, username, direct grants and branch, but allows `roleId`
  (POS `data/postgres/postgres_admin_repositories.dart:507-529`). The seeder's
  upsert leaves `role_id` alone, so the local role survives every reseed.
- The effective set is the local roles and overrides, resolved, **unioned with**
  the platform grants (POS `domain/models/shift.dart:65-73`). So a local role can
  *add* a capability the platform withheld, such as refunds. A local DENY
  override *cannot* remove a platform grant. Ceilings (`pos_permission_limits`)
  exist only on the till. Platform `roles` have no multi-role, overrides,
  ceilings or risk levels (API `Models/Role.php`).

### Q4. `PosBootstrapService::catalog()` vs the till's catalogue (feeds CB-05)

Sent (API `Services/PosBootstrapService.php:161-241`):
- categories: `id`, names, `sort_order`, `is_active`. `slug` is always null.
- items: `id`, `category_id`, names, `price_minor`, `discounted_price_minor`,
  `is_available`, `sort_order`, `option_group_ids`. `sku` and `barcode` are
  always null (`:212-213`, POS-BE-004).
- option groups: `id`, names, `is_required`, `max_select`, `is_variant`,
  `sort_order`, and options with `price_delta_minor`, `is_available` and
  `sort_order`.
- tables: `area_name` is carried as a string only (`:79-92`).

Gaps against the till's schema (POS `data/postgres/migrations.dart`):

| Till has | Bundle | Platform has it? |
|---|---|---|
| per-branch / per-channel prices, `pos_product_prices` (`:1766`) | no | **no model** |
| combos, `pos_combos` + groups + options (`:1858`) | no | **yes** (`Combo`, `ComboGroup`, `ComboGroupItem`) |
| tax group per product (`:1677`) / per category (`:2410`) | no | partly: `TaxRule.applies_to.category_ids/item_ids`, but the codec ignores scope |
| modifier `min_select`, `free_options`, `is_default` (`:1819`, `:1823`, mig 17) | no | not checked |
| `sku`, `barcode` | null | no (POS-BE-004 unbuilt) |
| dining areas as rows | name only | yes (`DiningArea`) |
| stock-only items (mig 40) | n/a | no |

**Hazard for CB-05.** `pos_combos.category_id` (`:1862`) and
`pos_combo_options.product_id` (`:1909`) are `ON DELETE RESTRICT`. The seeder's
`DELETE FROM pos_products` / `pos_categories` would therefore fail and roll
back the **whole** seed on any cloud till holding a combo row. Sending combos
means the seeder must delete combos first.

### Proposed map

| Row | Today on cloud | Proposed owner | Reason | What changes on each side | Carried by |
|---|---|---|---|---|---|
| Staff | platform; the till refuses identity edits | **platform** (keep) | Already one author. | none | CB-07 (sign-in) |
| Roles | two authors, additive | **platform** (recommend option b, phased) | One person should hold one set of rights on every till. Today a till can grant what the dashboard withheld, and the dashboard cannot see it. Phase 1 is cheap: on cloud the till resolves the platform grants alone and the Roles pane goes read-only. Multi-role, overrides and ceilings move to the platform only if the owner wants them. | Till: ignore local `role_id`, extra roles and overrides on cloud; the pane gets a notice. Platform: none in phase 1; CB-06 for the rich features. | CB-06 |
| Menu | platform | **platform** (keep) | One author already; only parity gaps remain. | see Q4 | CB-05 |
| Floor | platform | **platform** (keep) | Same. Areas travel only as names. | optional `area_id` | CB-05 |
| Taxes | platform rate, with a local-group caveat | **platform** | POS-BE-013 already rules this. The caveat must be closed, not re-decided. | Till: verify, then neutralise the local default group on cloud. Platform: express "product on rate X". | CB-04 |
| Service charges | two authors; local wins once a row exists | **platform** (recommend) | The platform already has `Charge`, its controller, `PosMoneyView` and the config-version bump. This is the "platform authors, till reads" template. | Platform: additive `name_ar`, `is_automatic`, `is_optional`. Bundle: full list. Till: seed `pos_service_charges` from the bundle on cloud; the pane goes read-only like Taxes. | CB-02 |
| Payment methods | **nobody**; the seeded four; ids don't match the platform's | **platform**: **settled 2026-09-11** (owner go: fixed as a defect; POS-BE-013 amended) | The platform already validates tender ids on every synced payment, so the ids must be its own. The alternative, the platform learning the till's ids, would be a merge path. | Done 2026-09-11: the platform creates default Cash + Card at the first terminal; the till seeds `pos_tender_types` by platform id on cloud. Still optional: additive `code`, `name_ar`, `counts_as_cash`, `opens_drawer`, `requires_reference`, `refund_allowed`; one `kind` vocabulary; the pane going read-only. | POS-BE-013 amendment (done); CB-02 for the optional fields |
| Order types | platform picks the offered set; rules frozen, no author | **platform** | The till already tells the manager these come from the platform. Make that true. | Platform: rules per restaurant (or per branch), one vocabulary, bundle block, config-version bump. Till: seeder writes `pos_order_types`. | CB-03 |
| Purchasing | till-local | **platform** (owner, 2026-09-12, CB-09 D1) | The platform is the only author on cloud; the till's panes are to be hidden on cloud (slice e, not yet approved). | Platform: slices a → b → c. Till: nothing until slice e. | CB-09 |
| Receipt | till-local `pos_receipt_profiles` | **platform** for the legal identity (name, TRN, address); **till** for print-layout preferences | Who the slip says sold the food is a fact about the business, and the platform already sends name and TRN. How a given printer lays it out is a fact about the device. | **Platform: done 2026-09-22** — `receipt_profiles` table, the Receipt details page, and the bundle's `receipt_profiles[]` key. Till: seed from the bundle, make the pane read-only on cloud, keep the layout half local. | CB-08 |
| ETA | till job | **till** (keep) | Submission happens on the device and is queued there. | none | — |
| Activity | till-local, not synced | **till** writes events; platform gets a read-only copy if wanted | Only the till writes these events, so this is a sync question, not an ownership one. | only if CB-13 says yes | CB-13 |
| Backup | till | **till** (keep) | It covers local-only state. Synced facts are durable on the platform. | none | — |
| Items (stock) | hidden; nobody | **platform** (CB-09 D1, D3: a separate `stock_items` table) | The seeder would delete stock-only products. | Platform: slice b. | CB-09 |
| Units | till-local | **platform** (CB-09 D1) | Only purchasing and stock use units. | Platform: slice a (same seven default codes as the till). | CB-09 |

### Questions the owner must answer

1. **Service charges: does the platform author them on cloud?** (Recommended.)
   *Narrowed 2026-09-11:* tender ownership on cloud now follows POS-BE-013
   (the platform), settled by the defect fix in question 2, so this question
   concerns **service charges only**. If yes, local `pos_service_charges` rows
   already typed on cloud tills are **replaced** on the next seed, with no
   import, per the no-merge rule. Accept that?
2. ~~Tender-id mismatch: fix it now as a defect, ahead of CB-02?~~ **Owner go
   2026-09-11: fixed as a defect.** It turned out to need no `POS-BE-030`. It
   is an amendment to POS-BE-013 (ids MUST come from `money.tender_types`; the
   list is never empty; null is not a fallback), plus seeder work from
   `pos-dev`. See Q1.
3. **Order-type rules: set per restaurant (as the till has them) or per branch
   (as `supported_order_types` is)?** And should `pickup` be retired in favour
   of `takeaway` on the platform?
4. **Roles: (b) platform-only on cloud, with the till's Roles pane read-only
   and multi-role, overrides and ceilings lost on cloud until CB-06 ports
   them?** Or (a) keep today's additive local roles? Or (a′) keep local roles
   but cap them at the platform's grants?
5. ~~**Receipt: does the platform author the legal identity on the slip?**~~
   **Answered 2026-09-22: yes** (owner go, item A3). Built; see CB-08. What is
   still open there is only the capability choice and whether the till's
   Receipt pane goes read-only on cloud.
6. **May `pos-dev` verify the `pos_tax_groups` caveat** (Q1)? If it holds, a
   cloud till may be charging 14% regardless of the platform's rate.
7. Unchanged from §5: is Cloud Wave 1 deployed? (*Purchasing answered
   2026-09-12:* yes, platform-authored and standalone. See CB-09.)

---

## 5. Decisions only the owner can take

1. **CB-01 ownership map**, above all CB-02 (service charges; payment methods
   were settled 2026-09-11 as a defect fix) and
   CB-06 (roles). The draft and the exact questions are in §4a.
2. ~~**Is purchasing and inventory a cloud v1 feature?**~~ **Answered
   2026-09-12:** yes. The platform authors it, as a standalone `purchasing`
   feature that doesn't need `pos`. Slices a → b → c are approved (CB-09).
3. **Deploy Cloud Wave 1 to production?** It's still local-only per the Wave 1
   journal, and every CB item that ships assumes it's live.

---

## 6. Sources

- `xorder-pos/docs/pos/16-back-office-scope.md`: ownership table, the 15 areas, the chain
- `xorder-pos/docs/pos/17-sales-and-payments-plan.md` §2, §3a, §6: cloud plan and C1 findings
- `xorder-pos/lib/features/admin/presentation/management_screen.dart`: panes, areas, cloud gating
- `xorder-pos/lib/data/cloud/bootstrap_seeder.dart`: what a bundle overwrites
- `apps/api/app/Services/PosBootstrapService.php`: what a bundle carries
- `docs/backend/CLOUD_WAVE1_PROGRESS.md`: what the platform built

## 7. Questions from pos-dev

_(none yet)_
