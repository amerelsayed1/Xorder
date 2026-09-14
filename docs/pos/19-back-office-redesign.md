# 19 — Back office redesign: from six mockups to shippable slices

**Written 14 September 2026.** Plan only; no code. Placed in `docs/pos/` (not
`docs/plans/`) because every plan in this repo lives here, numbered.

**Fixed by the owner, not re-opened here:** keep the design system (radius 0,
`lib/core/ui/tokens.dart`, accent `#F89A06`, widgets in `lib/core/ui/widgets/`);
take layout, information architecture and content from the mockups only; back
office only — till, start and lock screens untouched.

**How this was verified.** Every "exists" below was read in source: panes and
gates in `lib/features/admin/presentation/management_screen.dart`, the bar in
`lib/app/app.dart`, table definitions in `lib/data/postgres/migrations.dart`,
interfaces in `lib/domain/repositories/`. The cloud dashboard **is** on this
machine (`/Users/amerelsayed/Projects/Web Application/xorder-new`, contrary to
the brief) and was read, not run: `apps/web/src/pages/dashboard/nav.config.js`,
`settings/settings.config.js`, `HomeView.vue`, `OrdersView.vue`, `StaffView.vue`,
`InsightsView.vue`.

**Two stale facts found on the way.** Plan 17 §6 C4 says `business_day_id` is
never stamped; migrations 35–36 stamp it by trigger (`migrations.dart:3247`,
`test/data/business_day_stamping_test.dart`). Doc 16 §2 lists Purchases,
Suppliers, Inventory and Backup as absent; all four are built. Both docs are
corrected in place (14 Sep).

**Owner answers, 14 September 2026** (were §5 questions 1–4): Admin Mode
before the shell; People under Settings, as on the cloud; export is Excel only,
behind a new `report.export`; Finance ships now, read-only, over data that
already exists.

---

## 1. Shell decision

### 1.1 The tab set — nine tabs: the mockup's, with People under Settings

| Tab (EN / AR) | Panes it hosts today | New content | Gate to show the tab |
|---|---|---|---|
| Home / الرئيسية | — | BO-4 | anyone past the door; KPI tiles need `reports.view` |
| Sales / المبيعات | — (order history re-hosted, BO-2) | BO-3 | anyone past the door; rows scoped by `order.view_all` (`history_scope.dart`) |
| Reports / التقارير | — | BO-5, BO-6 | `reports.view` |
| Menu / المنيو | menu, extras, floor | — | authoring till only (`_authoringPanes`, `management_screen.dart:135`) |
| Inventory / المخزون | items, stock, units | — | `purchase.manage` + authoring; cloud shows the platform pointer |
| Purchasing / المشتريات | purchasing (its four `PurchasingTab`s) | — | `purchase.manage` + authoring; cloud shows the platform pointer |
| Finance / المال | — | BO-9, BO-10 (read-only) | `reports.view`; bills-due card also `purchase.manage` |
| System / النظام | terminal, backup, activity, eta (when `etaFilingEnabled`) | — | per pane, unchanged (`_paneRequires`, `:459`) |
| Settings / الإعدادات | receipt, staff, roles, taxes, charges, tenders, order types | BO-7, BO-8 | per pane, unchanged; if BO-0 moves the door off `staff.manage`, Staff and Roles gain it in `_paneRequires` |

Where the orphans go, and why:
* **Money → Settings.** Taxes, service charges, payment methods and order types
  are configuration, and the cloud already puts them there (`settings.config.js`
  group `pos`: "POS money"). The mockup's Settings side nav lists payment
  methods and taxes too. The mockup's *Finance* is money that moved, not money
  rules, so the two are not merged.
* **Compliance dissolves.** Receipt goes to Settings › General (it *is* the
  company-info form — trade name, registration number, phone, address). ETA
  goes to System, still hidden while `etaFilingEnabled` is false.
* **Floor and Extras stay under Menu** (today's grouping; the cloud's Menu has
  Extras, and it has tables under a separate "Place" group the mockup does not
  have).
* **Units stay under Inventory** (today's grouping; the cloud agrees,
  `nav.config.js` group `inventory`).
* **Terminal → System**, not Settings. It wipes the machine; it is the
  mockup's "branches & devices", but lives beside backup and the log.
* **People → Settings › Users and Settings › Roles** (owner, 14 Sep), as on
  the cloud (`settings.config.js` group `account`: profile, users, roles). The
  mockup's People tab and its Settings entry "users & permissions" are one
  place.

**One list, not two.** `ManagementArea` and `areaOf` (`:190`, `:217`) become
`BackOfficeTab` and `tabOf`, still a total `switch`, so a pane with no tab fails
to compile. `managementPanesFor`, the authoring rule and `_paneRequires` are
unchanged — the tab strip, the bar and the Home quick actions all ask the same
function, which is the rule the current code already states (`:88-92`).
**A tab with no visible pane is absent**, as an empty area is today (`:246-249`);
the exception is Inventory and Purchasing on a cloud till, which keep their
word and show `purchasingComesFromPlatform`, as the bar does now (`:365-371`).

**A documented reversal.** `management_screen.dart:649` says "No tabs … the
window's bar names every area and every pane". This plan puts tabs back and
shrinks the bar (below). Record the change in that comment when BO-1 lands.

### 1.2 Inside a tab

* **Two to five panes:** a secondary row of text tabs under the strip (Menu,
  Inventory, System). Purchasing keeps its own internal tabs.
* **Settings:** a left (RTL: right) side nav at `PosSize.settingsNav` (232),
  a token that exists and nothing uses yet, grouped as the cloud groups it:
  *Account* — General, Users, Roles; *Point of sale* — Taxes, Service charges,
  Payment methods, Order types; *This terminal* — Language & appearance.
* Active tab: accent underline, radius 0, no tinted tiles
  (`07-design-system.md:30`). Icons are Material `Icons.*`; no new assets.
* **All visible tabs fit without scrolling at `PosSize.wideShellMin` (1100 px)
  in both languages.** A tab strip you have to scroll hides half the product.

### 1.3 Status bar (every tab)

| Mockup | Source |
|---|---|
| green dot + "connected" | `BranchServerPill` offline / `SyncPill` cloud (`pos_widgets.dart:209`, `:246`), same providers the till uses |
| branch name | `pos_branches.name` for this terminal |
| version | `posAppVersion` (`cloud_provisioning_repository.dart`, as `about_dialog.dart:35`) |
| "Amer · Administrator" | `admin.name` · role display name (what `_Header`, `:761`, prints today) |

The title bar ("XORDER | Back Office v1.0.0", window controls) is OS chrome.
It's out of scope.

### 1.4 The menu bar and F8

* **The bar collapses to one "Back office / الإدارة" menu**: one line per
  visible tab, Purchasing's "new order / new invoice / new supplier" lines kept
  (they are real shortcuts, `managementMenuEntries`, `:310`), the cloud pointer
  line kept. Seven area buttons plus a nine-tab strip would be the same
  navigation twice — the exact reason the tabs were removed. `managementBarFor`
  stays the single source; `app.dart:447` `_managementMenus` just draws it.
* **Visibility rules unchanged:** after sign-in only, never on start or lock
  (`app.dart:240-255`); absent for someone who cannot enter the back office
  (`staff.manage` today, `:477`; BO-0's `admin.enter` after it).
* **The door is Admin Mode's** (owner, 14 Sep: Admin Mode lands before the
  shell — BO-0). Ctrl+Shift+S → username + PIN, `admin.enter`; BO-0 retires
  F8. The shell lives *inside* that door and lands on Home once BO-4 exists (the
  first visible tab until then).

---

## 2. Mapping — every mockup element to a source

Legend: **✓** exists (pane/widget + query) · **Q** data exists, needs a new
query · **∅** no source (what it would take) · **✗** cut (why).

### 2.1 Home

| Element | Verdict | Where |
|---|---|---|
| Logo, welcome, tagline | ✓ | static strings, EN+AR |
| Card: current branch | ✓ | `pos_branches.name`; chevron → System › Terminal |
| Card: current device | ✓ | `pos_terminals.name` (`migrations.dart:152`); chevron → System › Terminal |
| Card: connection | ✓ | status-bar providers (§1.3) |
| Card: last sync | ✓ cloud / ✗ offline | cloud: `pos_cloud_state.bootstrap_synced_at` (`:631`) + `OrdersRepository.pendingSyncCount`. Offline has no platform, so "last sync" is always "never"; **show last backup instead** (`pos_backups`, `backupsProvider`) — the offline "is my data safe" answer |
| KPI today's sales, orders, average order | Q | current business day from `BusinessDayRepository.current()`; totals from `PostgresBranchSalesRepository` (`BranchSales`, `branch_sales.dart:165`) — gross, discounts, refunds, orders; average = net ÷ orders in integer minor units |
| "vs yesterday" delta | Q | previous business day **to the same elapsed time since the day opened** — a whole-day comparison reads as a collapse every morning. Delta in integer basis points |
| KPI net profit | ✗ | no cost price on `pos_products` (`:225-250`: `price_minor` only) and sales write no stock movements (kind `sale` allowed at `:2643`, nothing writes it). Any profit figure would be invented |
| Quick action: sales reports | ✓ | → Reports tab (hidden without `reports.view`) |
| Quick action: product management | ✓ | → Menu tab; hidden on a cloud till |
| Quick action: low stock | ✗ | stock items have no reorder level (`stock_item.dart`), and on-hand is received-to-date because sales don't deduct — the cloud labels the same page "Recorded stock" (`nav.config.js`, inventory comment) |
| Quick action: employees | ✓ | → Settings › Users |

**Cloud divergence:** the cloud Home (`HomeView.vue`) shows menu counts, QR
views, a setup guide and featured items — no sales KPIs. The mockup's sales Home
is a desktop-only deviation, justified because an offline install has no other
dashboard (plan 17 §2). Flag it; don't copy the QR/views cards (no source here).

### 2.2 Sales

Today: `OrderHistoryScreen` (`lib/features/history/presentation/order_history_screen.dart`)
at route `/orders`, opened from Settings › Orders, with detail pane
(`order_detail_pane.dart`), status and payment chips, `OrderHistoryQuery`
(`order_record.dart:399`).

| Element | Verdict | Where |
|---|---|---|
| Search: invoice no. | ✓ | `OrderHistoryQuery.search`, `byInvoiceNumber` |
| Search: customer name | ∅ | no `pos_customers`; Wave H (`11-gap-closure-plan.md` §10) |
| Date range | ✓ | `from`/`to`, business dates |
| Branch filter | ✗ | a till sees its own branch only (plan 17 §2, owner 2026-09-10). **Terminal filter instead** — ✓ `terminalId`, `terminals()` |
| Order status | ✓ | `statuses` |
| Payment method | ✓ | `tenderTypeId` |
| "+ New order" | ✗ | orders are taken at the till; the back office is not a till (decision 3). "Back to till" already exists |
| KPI total sales / invoice count / paid / outstanding | Q | new `OrderHistoryRepository.summarise(query)` — **same WHERE as `search`, same scope rule**. Outstanding = total − paid over `unpaid`/`partiallyPaid` (`payment_status.dart:28`) |
| Row checkbox | ✗ | no bulk action is defined, and bulk void/refund is not one anybody should have |
| Invoice no., date-time, total | ✓ | `OrderRecord` |
| Customer | ∅ | Wave H |
| Payment method column | Q | not on `OrderRecord`; add aggregated tender labels to the `search` query |
| Status pill | ✓ | `OrderStatusChip` + `PaymentStatusChip` — two chips, per plan 17 §4 |
| Branch column | ✗ | → terminal column, ✓ `OrderRecord.terminalName` |
| Pagination + page size | Q | today: cap 200 with a "truncated" notice (`order_history_screen.dart:482-513`). Build keyset prev/next with "showing n of total", **as the cloud does** (`OrdersView.vue:385-397`); no page-size picker (the cloud has none) |
| Detail: status, invoice, date, lines, subtotal, discount, tax, total | ✓ | `OrderRecordDetail`. **Service charge must be shown too** — the mockup omits it and its totals would not add up |
| Detail: customer, phone, email | ∅ | Wave H |
| Detail: branch | ✗ | → terminal |
| Print | ✓ | preview / reprint (`order_detail_pane.dart:579-603`), `receipt.reprint` |
| Edit | ✗ | a settled sale is immutable; voids and refunds are the corrections (plan 17 §0 rule 4) |
| Refund | ✓ | `refundAction` → `RefundSheet`, `order.refund` + `refund.max` |

**Cloud divergence:** the cloud list has order type and item count columns and
status tabs; the mockup has payment method and branch. Take the cloud's **order
type** column (the till has order types), the mockup's payment method, and drop
branch.

### 2.3 Reports

| Element | Verdict | Where |
|---|---|---|
| Period today / week / month / custom | Q | business-day ranges; week start from `intl` for the locale, not hard-coded |
| Export Excel | Q — BO-11 | `excel` is in `pubspec.yaml`; export the rows the screen shows. **New capability `report.export`** (owner, 14 Sep; plan 17 §5, `11` §9) — not yet in `PosCapability.all` (`permissions.dart:100`) |
| Export PDF | ✗ deferred | no PDF package in `pubspec.yaml`, and none is to be added (owner, 14 Sep) |
| KPI total sales, average order | Q | Wave G `ReportsRepository` over `pos_orders`/`pos_refunds` |
| KPI net profit | ✗ | as Home |
| KPI customer count | ✗ | no customers. **Replace with refunds** (count + amount) — in plan 17 S3's own KPI list |
| Deltas vs previous period | Q | same-length previous range, basis points |
| Sales trend line + metric dropdown | Q | per business day: net, orders, average |
| Top products (qty, top 5) | Q | `pos_order_lines` by `menu_item_id`, net of `refunded_quantity` and voided lines |
| Payment methods donut | Q, reshaped | `MethodTotal` (`branch_sales.dart:57`); **a 100% stacked bar + table, not a donut** — square language, and legible in Arabic. On-account shown separately, never as takings (plan 17 §3a rule 3) |
| Branch / device performance table | Q | per terminal: `BranchSales.terminals` exists for one business day (`branch_sales.dart:99`, `test/data/branch_sales_test.dart`); extend to a range. Branch rows ✗ (one branch) |
| Insight: best day | Q | derived from the trend |
| Insight: top branch | ✗ | → top terminal |
| Insight: growth rate | Q | the headline delta |
| Insight: new customers | ✗ | no customers |

**Charts:** no chart package is in `pubspec.yaml`. Draw line and bars with a
`CustomPainter` on tokens. Values stay integers (minor units, basis points)
until the painter maps them to pixels; no `double` touches a figure.

**Cloud divergence:** cloud Insights (`InsightsView.vue`) is menu engagement —
QR views, items, pricing — plus product and area reports; it has no POS sales
analytics (the platform's C3 is unbuilt). Desktop Reports follows plan 17 S3 /
Wave G instead. Flag it.

### 2.4 Finance

The whole tab diverges from the cloud: the cloud has no finance area
(`nav.config.js`), and plan 17 §7 declines GL and COGS. What survives is a
**read-only view over ledgers that already exist**, and it ships now (owner,
14 Sep). Every row below marked ✗ or ∅ is cut from BO-9 and BO-10, not stubbed.

| Element | Verdict | Where |
|---|---|---|
| Sub-tab overview | Q | the cards below |
| Sub-tab revenues | Q | = Reports' sales totals, same query, not a second one |
| Sub-tab expenses | Q, partial | drawer pay-outs (`pos_cash_movements` kind `pay_out`, reason `petty_expense`, `migrations.dart:1517`, `:1584`) + supplier payments (`pos_supplier_payments`). `CashMovementsRepository` reads per shift only (`repositories.dart:537`); needs a range read |
| Sub-tab treasury | Q, partial | cash expected in **open drawers**: `ShiftRepository.summarise` exists but `current()` is per terminal (`postgres_shift_repository.dart:47`); needs "all open shifts at this branch" |
| Sub-tab payments | Q | plan 17 S2's payments view: one row per `pos_order_payments` row. Read-only needs no migration |
| Sub-tab settlements | ✗ | no concept of card or aggregator settlement in the schema |
| Sub-tab bills due | ✓ | `pos_supplier_invoices.due_at` (`:2742`), `SupplierInvoicesRepository.unpaid/balances`. Supplier tables are **not granted to the till** (doc 16 §6), so it reads through the back-office credential, and it's hidden on cloud (platform-authored, CB-09) |
| Sub-tab taxes | Q | `pos_order_taxes` (`:1689`) per rate, net of refunds — the figure a VAT return needs |
| KPI revenue | Q | as Reports |
| KPI expenses | Q, partial | pay-outs + supplier payments; label says exactly that |
| KPI net profit | ✗ | as Home |
| KPI cash balance | ✗ as one figure | no bank or wallet accounts exist; `wallet` is a tender kind (money collected by method), not a balance. Show "cash expected in open drawers" instead |
| Card: recent expenses (materials, rent, salaries) | partial | materials ✓ (supplier invoices); rent and salaries ∅ — no expense entity or categories. That is Wave Q, accounting lite (doc 16 §4) |
| Card: bills due (overdue / due / 7 days / total) | ✓ | as above |
| Card: payment methods donut | Q | as Reports, as a bar |
| Card: treasury (drawer, bank, e-wallet, total) | partial | drawer Q; bank and e-wallet ✗ |
| Table: recent transactions | Q | union of sales (invoice no.), supplier invoices, supplier payments and pay-outs, each drilling to its own screen |
| Column: account | ✗ | no chart of accounts |
| Status "pending" | ✗ | nothing produces it (plan 17 §7); use the source's own state (unpaid, void) |

### 2.5 People → Settings › Users & roles

Today: `ManagementStaffPane`, `ManagementRolesPane`, `StaffDirectoryRepository`,
`RolesRepository`. `pos_staff` columns (`migrations.dart:171-185`): name,
username, branch, capabilities, active — **no phone, no last login.**

| Element | Verdict | Where |
|---|---|---|
| Manage roles / + Add employee | ✓ | Roles pane / Staff create. On cloud, identity is platform-authored (existing refusals) |
| KPI total / active (% of total) | ✓ | `all(includeInactive: true)`, `isActive` |
| KPI current shifts | Q | `pos_shifts WHERE closed_at IS NULL` across the branch's terminals (shared with Finance's treasury) |
| KPI roles count | ✓ | `RolesRepository.all` |
| Filter status, role, name search | ✓ | in memory over `all()` |
| Filter branch / column branch | ✗ | a till serves one branch |
| Search / column phone | ∅ | Wave I adds `phone` (`11` §11); not built |
| Avatar initials, name, role pill, status | ✓ | the cloud does the same (`StaffView.vue:217-231`); also show `@username` as the cloud does |
| Last login | ∅ → substitute | no `last_login_at`, and no sign-in audit event (the `AuditAction` list has none). **Show "last shift opened"** from `pos_shifts.opened_by` and label it that way |
| Actions menu | ✓ | existing edit, PIN reset, deactivate, grants |
| Role-permission matrix | Q | **generated**: columns from `pos_roles`, rows from `PosCapability.all` grouped by the tab each unlocks, cells from role capabilities. Read-only, links to Roles. Says it shows role grants, not per-person overrides. Never a hard-coded table |

**Placement (owner, 14 Sep):** as on the cloud — Settings › Users and
Settings › Roles (`settings.config.js` group `account`). The mockup's People
screen becomes the Users section: tiles, filters, table and matrix under the
Settings side nav. "Manage roles" opens Settings › Roles.

### 2.6 Settings

| Element | Verdict | Where |
|---|---|---|
| Nav: general | ✓ | Receipt pane (`ReceiptProfile`, `receipt_profile.dart:123-156`) + appearance |
| Nav: payment methods, taxes | ✓ | Tenders and Taxes panes (+ Charges, Order types) |
| Nav: language & appearance | ✓ | `localeProvider`, `brightnessProvider` — **this terminal's** preference (terminal config file), labelled so |
| Nav: branches & devices, backup, log | → System | not duplicated; one pane, one place |
| Nav: users & permissions | ✓ | Settings › Users and › Roles — the Staff and Roles panes, as on the cloud |
| Nav: notifications | ✗ | no notification system; toggles that change nothing |
| Company name* | ✓ | `ReceiptProfile.tradeName` |
| Short name | ✗ | no field, no consumer |
| Commercial registration no. | ✗ as drawn | the existing field is `registrationNumber`, the **tax** registration number. Label it that way. The CR number has no field or consumer |
| Default branch | ✗ | a till belongs to one branch, fixed at setup |
| Default currency | ✗ | `Money` defaults to EGP; the order and purchase tables hold `currency`. Changing it is a data migration, not a setting |
| Phone | ✓ | `ReceiptProfile.phone` |
| Email | ✗ | no field, not printed |
| (Address — not in mockup) | ✓ keep | `BranchAddress`; the slip needs it |
| Appearance: language, theme, dark toggle | ✓ reshaped | **three-way theme: system / light / dark** (`brightnessProvider` null = follow the machine); a single toggle loses "system" |
| Notifications card | ✗ | as above |
| Backup: last backup + timestamp | ✓ | `backupsProvider` |
| Backup: create now | ✓ | via the Backup pane's action, `backup.manage` only |
| Backup: auto daily at 02:00 | ✗ → existing | no scheduler exists. The real policy is **back up at day close** (`backup.on_day_close`, `pos_settings.dart`; `backup.dart:189`) — show that toggle |
| Save / Reset | reshaped | per section, with a dirty bar (`PosSize.settingsDirtyBar`, 64). The sections have different gates and the receipt profile is revisioned, so one form-wide save would half-succeed |

**Localise, not require:** SAR / ر.س → EGP, +966 → +20, السجل التجاري → رقم
التسجيل الضريبي, mada → the tenders configured in `pos_tender_types`.

---

## 3. Slices

Each is one `pos-dev` run. **Every slice ships its strings in EN and AR**
(`app_strings.dart`) and runs `arabic_screens_test.dart`. Money stays in integer
minor units; shares and deltas in integer basis points. DB suites run as
`POS_PG_USER`. No slice runs `dart format`. Any new query a repository issues
must be covered by `test/data/grants_cover_usage_test.dart`.

### BO-0 — Admin Mode on main · **gate** (owner, 14 Sep: before the shell)
Not a slice of this plan; it is what BO-1 waits for.

**Where it stands (updated 14 Sep): recovered, not rebuilt.** The 13 Sep work
was replayed from its session transcripts and committed as `43eeae7` on
`pos/admin-mode`: migrations 46 (`admin.enter` for the owner role) and 47
(`payment.remove` kept by the roles that had it), with both review findings
fixed. Every item under *Done means* below is satisfied on that branch; it
reaches `main` when the branch merges. The "lost / rebuild" finding this
paragraph used to hold is withdrawn.

**Done means, on `main`:**
* `admin.enter` is in `PosCapability.all`: critical, not in `overridable`, Owner
  by default, grantable by the owner, labelled in EN and AR;
* Ctrl+Shift+S opens a username + PIN login; the forced terminal reset that owns
  that chord today (`app.dart:72-83`) moves inside Admin Mode with its own
  rescue chord;
* F8 no longer opens the back office (`app.dart:95`);
* the admin DB password lives in `secrets.json`, asked once on an existing
  install;
* `ManagementScreen` is Admin Mode's body, not a parallel screen, with an
  inactivity timeout, Exit Admin Mode, and audit rows for enter and exit;
* the two review findings are closed: `resetPin` cannot target the owner, and
  PIN entry has an attempt limit;
* its migrations are numbered after main's latest;
* `admin_entry_test.dart` passes: a locked till reaches no pane without the
  login, and F8 opens nothing.

Phase 2 (single-use approvals) is not part of the gate. It changes
repositories, not the shell.

### BO-1 — Shell: tabs, sub-nav, status bar, one bar menu · **M**
Re-host every existing pane; no pane changes behaviour. M because it rewrites
the navigation model (`ManagementArea` → `BackOfficeTab`), the bar, and the
tests that pin both.

*Accepted when:*
* for every admin fixture × {authoring, cloud}, the set of reachable panes
  equals today's `managementPanesFor` result (a table-driven test);
* on a cloud till, Menu is absent and Inventory and Purchasing show the platform
  pointer; a deep link to Purchasing still says where it went
  (`cloud_purchasing_hidden_test.dart`);
* a tab with no visible pane is absent; `tabOf` is a total `switch`;
* `ManagementDestination` deep links, the Purchasing "new" entries, Esc
  (field first, then close), the schema notice and the backup notice all behave
  as before (`management_gate_test.dart`, `backup_pane_test.dart`);
* the bar holds one Back office menu, still hidden on start and lock and signed
  out (`settings_bar_test.dart`); the way in is BO-0's door, and F8 opens nothing;
* Staff and Roles are reached under Settings; there is no People tab;
* at 1100 px, all visible tabs show without scrolling, in EN and AR;
* the status bar shows connection, branch, version and user from the providers
  in §1.3.

*Depends on* **BO-0, Admin Mode on main.**

### BO-2 — Sales tab: the order history, re-hosted · **S**
The history widget embedded as the Sales tab. It adds an order-type column, a
payment-method column (tender labels aggregated in `search`) and a terminal
column. `/orders` from the Settings menu keeps working for cashiers. S because
it's one widget and one query column.
*Accepted when* the same query returns the same rows on both routes; the
payment-method column lists every tender of a split bill; `history_scope_test`
still holds inside the back office. *Depends on* BO-1.

### BO-3 — Sales: summary strip and pagination · **M**
`OrderHistoryRepository.summarise(query)` and keyset pagination with a total
count. M because the summary must be proven equal to the list, under scope.
*Accepted when* a DB test, for each filter and their combinations, shows total,
count, paid and outstanding equal to the sum of every page of `search`; a
cashier without `order.view_all` gets totals for their own sales only; paging
never repeats or skips a row when two sales share a timestamp. *Depends on* BO-2.

### BO-4 — Home · **M**
Status cards, three KPI tiles with same-elapsed-time deltas, quick actions. The
back office lands here. M because of the delta rule and the no-business-day
case.
*Accepted when* each tile equals `BranchSales` for the current business day
(DB test); the delta compares against the previous business day cut at the same
elapsed time; with no day open, tiles show the last closed day and say so; tiles
are absent without `reports.view`; quick actions obey the same pane list (none
for Menu on cloud); offline shows last backup where cloud shows last sync.
*Depends on* BO-1. Parallel with BO-2 and BO-3.

### BO-5 — Reports read model (Wave G core) · **M**
`ReportsRepository` + `ReportFilter` (`11` §9): period totals, per-day series,
top products, tender shares, per-terminal over a range. No screen. M because
it's the part that must be right; the screen is drawing.
*Accepted when* every figure equals the sum of the rows its drill-down would
list (plan 17 S3); the per-terminal total equals the branch total to the
piastre and lists terminals with zero sales; refunds sit on the issuing
terminal's day. *Depends on* nothing. Parallel with BO-1.

### BO-6 — Reports tab · **M**
Period selector, four KPI tiles (sales, average, orders, refunds), trend line,
top-5 bars, tender stacked bar, terminal table, insights. `CustomPainter`
charts. *Accepted when* every value on screen comes from BO-5 (widget test with
a fake repository — a test double, never a default binding); the tab is absent
without `reports.view`; the charts render in RTL. *Depends on* BO-1, BO-5.

### BO-7 — Settings › Users: KPIs, filters, matrix · **S**
The mockup's People screen as the Users section: four tiles, filters,
`@username`, last-shift column, generated role matrix. S:
the data is already loaded, plus one open-shifts query.
*Accepted when* the matrix changes when a role's capabilities change (no
hard-coded cells); the "current shifts" count equals open `pos_shifts` rows for
the branch (DB test); the column is headed "last shift", not "last login".
*Depends on* BO-1.

### BO-8 — Settings: side nav and General · **S**
Side nav; General = receipt profile form + this-terminal appearance + backup
summary card with the day-close toggle. *Accepted when* the receipt profile
saves exactly as today (`receipt_profile_ui_test.dart`); "create backup now" is
absent without `backup.manage`; the theme offers system / light / dark.
*Depends on* BO-1.

### BO-9 — Finance: revenue, taxes, payments · **M**
Overview (revenue, tender bar), taxes collected by rate, payments list. All read
from BO-5 plus `pos_order_taxes`. *Accepted when* tax collected per rate, net of
refunds, equals the sum of `pos_order_taxes` for the range (DB test); revenue
here equals Reports' figure for the same range. *Depends on* BO-5, BO-1.

### BO-10 — Finance: expenses, bills due, drawers, transactions · **M**
A range read for `pos_cash_movements`, bills-due buckets, cash expected in open
drawers, and the union transactions table with drill-down. *Accepted when* the
bills-due buckets partition unpaid invoices by `due_at` against the business
date; expenses = pay-outs + non-void supplier payments, with a label saying so;
the bills card is absent on cloud and without `purchase.manage`; it reads
supplier tables through the back-office credential only. *Depends on* BO-9, BO-7
(shares the open-shifts query).

### BO-11 — Excel export and `report.export` · **S**
The new capability (owner, 14 Sep) goes into `PosCapability.all` with a risk
level and EN and AR labels, in the Owner template only. The Excel button on
Reports and on the Sales list writes exactly the rows on screen, using the
`excel` package already in `pubspec.yaml`. No PDF. S: one capability and one
writer.
*Accepted when* the button is absent without `report.export` (checked with
`Authorization.check`, and the test fixture holds it through a role, not a
direct grant); the file's rows and totals equal the screen's for the same
filter; headers are in the operator's language; `capability_labels_test.dart`
covers the new key. *Depends on* BO-6 (and BO-3 for the Sales export).

### Order and parallelism

```
BO-0 Admin Mode ─> BO-1 ─┬─> BO-2 ─> BO-3
                         ├─> BO-4
                         ├─> BO-7 ───────────┐
                         ├─> BO-8            │
                         ├─> BO-6 ─> BO-11   │
                         └─> BO-9 ─> BO-10 <─┘
BO-5 (no screen; may start now) ─> BO-6, BO-9
```
Corrected order: **BO-0 → BO-1**, then BO-2 → BO-3, BO-4, BO-7, BO-8,
BO-6 → BO-11, and BO-9 → BO-10 (BO-10 also after BO-7). BO-5 is the only item
that may start before Admin Mode lands: it touches no screen. It then feeds
BO-6 and BO-9. After BO-1, the screen slices can run in parallel, but all of
them touch `app_strings.dart`, so merge one at a time.

---

## 4. Cut, and why (not scheduled)

Net profit (all three screens) — no cost price, no sale deduction · low stock —
no reorder level, on-hand not real · customers, customer count, new customers,
customer search — Wave H · phone, last login — Wave I · settlements, bank and
e-wallet balances, account column — no accounting model · rent and salary
expenses — Wave Q · notifications — no system behind them · branch filters and
columns, default branch — one branch per till · default currency, short name,
CR number, email — no field or consumer · "+ New order", Edit order, bulk
checkboxes — the till's job, or unsafe · 02:00 scheduled backup — replaced by
the existing day-close backup · donuts — replaced by bars · page-size picker —
the cloud has none · PDF export — deferred, no PDF package (owner, 14 Sep) ·
People as a top-level tab — under Settings, as on the cloud (owner, 14 Sep).

---

## 5. Decisions and open questions

**Answered by the owner, 14 September 2026:**
1. Admin Mode before the shell → BO-0 gates BO-1.
2. People under Settings, as on the cloud → §1.1, §2.5.
3. Excel export only, behind a new `report.export` → BO-11; PDF deferred.
4. Finance ships now as read-only views over existing data → BO-9 and BO-10;
   anything without a source is cut (§2.4, §4).

**Still open:**
1. **Admin Mode must be rebuilt, not merged.** Its Phase 1 and 2 work is not in
   git (BO-0). Do you accept rebuilding it from the 12 Sep decisions, ahead of
   every back-office slice except BO-5?
