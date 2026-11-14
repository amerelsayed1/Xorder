# Back Office navigation — inventory, duplicates, mapping (XORD-022)

**Status:** discovery only. No application code changed. The proposed hierarchy needs the owner's decisions in section 7 before any structural change.
**Verified against:** `xorder-pos` HEAD `2e7e612` **plus the uncommitted working tree** (about 40 modified files from other findings; none of them touch the navigation files read here). Read on 2026-10-25.
**Cloud dashboard:** out of scope (the epic is the Flutter POS). Not read.
**Baseline:** `flutter test test/features/back_office_shell_test.dart test/features/settings_bar_test.dart` → `+61: All tests passed!` (macOS, no database).

## 1. Where the navigation lives (verified)

| Piece | File | What it is |
|---|---|---|
| The bar the user sees | `lib/app/app.dart` `_settingsBar` (l. 185–496) | Material `MenuBar` through the `menu_bar` package (`^0.5.3`): `BarButton` → `SubMenu` → `MenuButton`, `MenuDivider`. One bar for the whole app, above the router. A separate `PlatformMenuBar` (l. 140) holds only the macOS app/window menu. |
| The tabs, panes, order, labels, gates | `lib/features/admin/presentation/management_screen.dart` | `BackOfficeTab` (10), `ManagementPane` (46), `tabOf`, `_placeInTab`, `managementPaneLabel`, `_paneRequires`, `managementPanesFor`, `backOfficeTabsFor`, `managementBarFor`. `app.dart` only draws what `managementBarFor` returns. |
| Labels | `lib/core/l10n/app_strings.dart` (`EnStrings`, `ArStrings`) | Already localised; no hard-coded nav labels found. |
| Routes | `lib/app/router.dart` | **Nine** go_router paths: `/welcome /setup /licence / /lock /floor /sale /orders /management`. Back Office pages are **not** URL routes: one `/management` route, the page travels in `extra` as a `ManagementDestination` (`pane`, `returnTo`, `purchasingTab`, `create`). |
| The sale-screen top bar | `lib/features/sale/widgets/pos_top_bar.dart` | **Not** the epic's subject: no dropdowns. Order-type switch, sync/branch pill, Open drawer, shift label, **Lock**, Close shift, operator name. |

**Consequence for "preserve routes / deep links":** moving a pane between menus changes `tabOf` and `_placeInTab`, not a URL. The things to preserve are the `ManagementPane` names (tests and `ManagementDestination` callers use them), `/management`, and `/orders`.

## 2. The epic's claims against the source

| Claim (as reported) | Verdict | Evidence |
|---|---|---|
| Payment Methods under Reports **and** Finance | **Confirmed, and it is three, not two** | `reportsPayments` (Reports), `financePayments` (Finance), `tenders` (Settings › Orders & invoices settings). The first two are read-only views of the same `salesReportProvider`; only `tenders` creates/edits methods (`ManagementTendersPane`, `TenderTypeDialog`). |
| Employees under Reports **and** People | **Label collision only** | `reportsEmployees` ("Employees" / الموظفين, a sales breakdown) and `staff` ("Staff" / الموظفون, management). Different pages. The English words differ (Employees vs Staff); the Arabic is the same word in two grammatical cases. |
| Orders and Invoices settings more than once in Settings | **Confirmed** | Till line `settingsOrders` "Orders & invoices" (→ `/orders`, the order history) **and** `settingsOrdersInvoices` "Orders & invoices settings" (→ the config pane). Near-identical words for a history list and a configuration page. The same history list is also the **Sales** tab (`ManagementPane.sales`), so one screen has three entries. |
| Language and theme overlap | **Confirmed, deliberate** | Two quick toggles in the till's Settings menu **and** the Language and Appearance panes. `management_screen.dart` l. 373–377 says the toggles stay because the menu is reachable without Admin Mode. Both write the same providers (`localeProvider`, `brightnessProvider`) per that comment; not independently re-checked. |
| Dining areas under Menu | **Confirmed** | `floor` → `BackOfficeTab.menu` (label "Floor" / الصالة). |
| Customers and employees in People | **Confirmed** | People = Staff, Roles & permissions, Shifts, Customers. The code comment says the owner's map "has no word for Customers", so it was placed last. |
| System vs Settings overlap | **Naming only** | No pane appears in both. System = Activity, Backup, Devices, Sync (+ E-receipts, hidden while `etaFilingEnabled` is false). Settings = the config panes. |
| Settings dropdown mixes account actions | **Confirmed** | See section 4. Also: three different "who" ideas share the bar — the till operator (`signedInStaffProvider`), the Admin Mode user (`adminSessionProvider`), and "Log out", which ends **Admin Mode only**. |
| Inconsistent dropdown widths / no clear active state | **UNVERIFIED** | The menus are `menu_bar` package defaults; no code of ours sets width or marks an active item. Not looked at in a running app. |
| Permission-based visibility | **Mostly already built** | See section 5. |

## 3. The 46 panes, as built

Tab order is the code's (`BackOfficeTab.values`). "Gate" is `_paneRequires`; "—" means no gate beyond the Admin Mode door (`admin.enter`). "Authoring" = hidden on a cloud till (`_authoringPanes`).

| Tab (EN / AR) | Pane → label EN / AR | Gate | Notes |
|---|---|---|---|
| **Home** / الرئيسية — a button | `home` Home / الرئيسية | — | |
| **Sales** / المبيعات — a button | `sales` Sales / المبيعات | — | The order history, rows scoped by `HistoryScope`; Returns is a switch inside the page. |
| **Reports** / التقارير | `reports` Business summary / ملخص الأعمال · `reportsSales` Sales · `reportsItems` Items / الأصناف · `reportsPayments` Payment methods / طرق الدفع · `reportsBranches` Branches & devices / الفروع والأجهزة · `reportsEmployees` Employees / الموظفين | `reports.view` | |
| **Menu** / المنيو | `menu` Menu / المنيو · `categories` Categories / الأقسام (**opens the same pane as `menu`**) · `extras` Extras library / مكتبة الإضافات · `floor` Floor / الصالة · `combos` Combos / الكومبو | — | Authoring. |
| **Inventory** / المخزون | `items` Stock items / أصناف المخزون · `stock` Stock on hand / المخزون المتاح · `units` Units / الوحدات | `purchase.manage` | Authoring; cloud till shows a pointer line. |
| **Purchasing** / المشتريات | `purchasing`, drawn as 7 lines: Purchase orders, New order, Suppliers, New supplier, Invoices, Enter an invoice, Payments | `purchase.manage` | Authoring; cloud till shows a pointer line. |
| **Finance** / المالية | `financeOverview` Overview · `financeRevenue` Revenue · `financeDrawers` Treasury / الخزينة · `financeExpenses` Expenses · `settlements` Settlements / التسويات · `financePayments` Payment methods · `financeTaxes` Taxes · `financeBills` Bills due · `financeTransactions` Transactions · `financeProfitLoss` Profit & loss | `reports.view` (Bills due also `purchase.manage`, authoring) | Read-only by design ("money that moved"). |
| **People** / الأفراد | `staff` Staff / الموظفون · `roles` Roles & permissions / الأدوار والصلاحيات · `shifts` Shifts / الورديات · `customers` Customers / العملاء | `staff`, `roles`: —; `shifts`, `customers`: `reports.view` | |
| **System** / النظام | `activity` Activity / السجل · `backup` Backup / النسخ الاحتياطي · `terminal` Devices / الأجهزة · `sync` Sync / المزامنة · `eta` E-receipts (hidden) | `backup`: `backup.manage`; `terminal`: `terminal.manage`; others — | |
| **Settings** / الإعدادات | *Orders & invoices settings* (one bar line, five panes behind a side nav): `receipt` General / عام, `orderTypes` Order types, `taxes` Tax, `charges` Service charges, `tenders` Payment methods · `printer` Printer & cash drawer · `language` Language · `appearance` Appearance · `user` User · `about` About XOrder | `printer`: `terminal.manage`; others — | The bar merges these with the till's own Settings lines (section 4). |
| **Log out** / تسجيل الخروج — a button, Admin Mode only | — | — | Ends Admin Mode and returns to where it was entered. |

A tab with no visible pane is absent (`backOfficeTabsFor`); on a cloud till Inventory and Purchasing stay as one pointer line each.

## 4. The "Settings" dropdown, line by line

The bar's Settings menu is the till's own lines with the Back Office Settings items appended beneath a divider (`app.dart` l. 341–477).

| Line | Does | Shown to | Kind |
|---|---|---|---|
| Sync now | `cloud.kick` | cloud tills only | action |
| Orders & invoices | `go('/orders', extra: here)` | everybody signed in | **destination (Sales)** — not a setting |
| Printer & cash drawer… | dialog | `terminal.manage`; hidden when Admin Mode lists the pane | setting |
| Language (the one you would get) | toggles `localeProvider` | all | quick toggle |
| Switch to light / dark | toggles `brightnessProvider` | all | quick toggle |
| Switch user | `go('/lock')` | all | **account** |
| About XOrder POS | dialog | all; hidden when Admin Mode lists the pane | info |
| Delete and set up again (⇧⌘R) | force reset | `terminal.manage` | **dangerous action** |
| *(Admin Mode only)* Orders & invoices settings, Printer…, Language, Appearance, User, About XOrder | open panes | per section 3 | settings + account |

"Sign out" exists only as the top-level **Log out** button, and only in Admin Mode. **Lock** is on the sale screen's top bar, not in any menu. No menu shows the current user's name; the sale top bar shows the operator, the Back Office status bar shows who is in Admin Mode (`back_office_shell_test`: "the status bar … who is in").

## 5. Permission mapping today (022-F)

- **Door:** `admin.enter` (`admin_session.dart`), checked in the session, not in a widget; Admin Mode asks non-cashiers for a password. The bar's Back Office menus do not exist outside Admin Mode.
- **Per pane:** `_paneRequires` (section 3). Hidden panes are absent from the bar **and** refused as a deep link (`managementPanesFor` is the single answer, held equal to the bar by `back_office_shell_test`). A parent with no visible child is absent. Owner retention: the owner role holds every capability, plus `_ownerBeforeTheGrant` for a till upgraded before `admin.enter` existed.
- **Gap:** **21 panes have no gate beyond the door** (`home`, `sales`, `staff`, `roles`, `menu`, `categories`, `extras`, `combos`, `floor`, `taxes`, `charges`, `tenders`, `orderTypes`, `receipt`, `eta`, `activity`, `appearance`, `language`, `sync`, `user`, `about`). Anyone who can enter Admin Mode sees them even where the repository will refuse the write. The source says why: a pane is gated only if its repository enforces the same capability.
- **Capabilities the repositories already enforce, and which could therefore gate their panes without a new claim** (read in `lib/data/postgres/`, not yet wired to the bar): `catalog.manage` (catalogue authoring: menu, categories, extras, combos, floor); `staff.manage` (staff, roles); `settings.manage` (receipt profile, tax/charge/tender writes in the catalog repository); `pos.settings.order_types.manage` (order types, XORD-002); `business.branding.manage` (logo card, XORD-021). Which write path each pane uses was **not** traced pane by pane: UNVERIFIED until it is.
- **Branch scope:** a POS database is one branch's; the cloud-side tenant/branch isolation is not part of this UI. UNVERIFIED for anything beyond the single branch server.
- **Refresh policy:** not examined (what the till does when a role changes mid-session). UNVERIFIED.
- **Tests that exist:** owner and a cashier-grade administrator on both deployments, a no-`reports.view` administrator (no Reports menu), cloud-till pointer behaviour. Not found: a manager, or a custom role with a partial grant.

## 6. Current → proposed mapping

The proposal is the epic's. "Needs decision" refers to section 7.

| Proposed menu | Proposed item | Maps to (current) | Verdict |
|---|---|---|---|
| Dashboard | Business Overview | tab **Home** → `home` | rename Home → Dashboard; `reports` ("Business summary") is a different page |
| Sales | Orders, Invoices, Refunds | `sales` (Invoices and Cancelled orders are filters, Returns a switch, inside one page) | **one page today**; three menu items would be three links to one page, or a split of the page. Needs decision |
| Menu | Products, Categories, Modifiers, Combos | `menu` (products), `categories` (same pane), `extras` (= Modifiers), `combos` | label change only; `categories` and `menu` open the same pane |
| Inventory | Inventory Items, Stock Availability, Units, **Stocktaking** | `items`, `stock`, `units` | **Stocktaking: no pane found** — do not create |
| Purchasing | Purchase Orders, Suppliers, Purchase Invoices, Supplier Payments | `purchasing` (7 lines) | exists; unchanged |
| Finance | **Financial Accounts**, Cash Registers, Revenue, Expenses, Payment Methods, Settlements | Cash Registers ≈ `financeDrawers` ("Treasury"); `financeRevenue`, `financeExpenses`, `settlements`; `financePayments` | **Financial Accounts: no pane** (XORD-015, not built). "Payment Methods = manage" is **not** what `financePayments` is: management is `tenders` under Settings. Also in Finance today, not in the proposal: Overview, Taxes, Bills due, Transactions, Profit & loss — they would lose a home. Needs decision |
| People | Employees, Roles & Permissions, Shifts, Customers | `staff`, `roles`, `shifts`, `customers` | same four; rename Staff → Employees |
| Reports | Sales, Products, Employees, Payment Methods, **Inventory** | `reportsSales`, `reportsItems`, `reportsEmployees`, `reportsPayments` | **Inventory report: no pane.** Also today: Business summary, Branches & devices (not in the proposal). |
| Management | Dining Areas & Tables, Devices, Synchronization, Backups, System Logs | `floor` (from Menu), `terminal`, `sync`, `backup`, `activity` | this is today's **System** renamed, plus `floor`. Cheapest change in the plan |
| Settings | General, Orders, Printing, Language, Appearance, **Business Settings** | `receipt`, the other four Orders & invoices panes, `printer`, `language`, `appearance` | "Orders" = today's five-pane group. **Business Settings: no pane** — likely `receipt`/taxes/charges/tenders; needs decision |
| *(account menu, new)* | Current user, Switch user, Lock POS, Sign out, About | `user` (pane), `/lock`, the sale-bar Lock, **Log out** (Admin Mode only), `about` | see 022-D below |

Net: the proposal is the existing ten-tab map with three renames (Home, System, People items), `floor` moved, and a new account menu. Three proposed items have no destination today (Stocktaking, Financial Accounts, Reports › Inventory) and one is ambiguous (Business Settings).

## 7. Decisions needed before any code (and a conflict to resolve)

1. **The current structure is the owner's own map** (`management_screen.dart` cites "owner's map, 14 Sep 2026" and the removals of 15 Sep 2026). The epic reverses parts of it. Confirm the epic **replaces** that map, including the tests that pin it (below).
2. **Payment methods, one place each:** keep Settings › Payment methods as the only management page; Reports › Payment methods as the analysis; and **remove or merge** `financePayments`, which duplicates the report on the same provider? Or keep it as Finance's ledger view and rename it (for example "Payments")?
3. **Sales:** the epic lists Orders, Invoices, Refunds. Keep one Sales page with filters (today), or add menu items that open it on a filter?
4. **Orders history line in Settings** ("Orders & invoices" → `/orders`): remove from Settings (Sales is its home), or keep for cashiers outside Admin Mode? Outside Admin Mode there is no Sales tab, so removing it removes cashiers' only path to order history from the bar.
5. **Account menu:** the Admin Mode "Log out" and the till's "Switch user" mean different things (end Admin Mode vs hand the till over). Should the account menu show both, named apart? Where does Lock live (the sale bar has it already)?
6. **Staff vs Employees:** one English word and one Arabic spelling across People and Reports.
7. **Finance extras** (Overview, Taxes, Bills due, Transactions, Profit & loss), **Reports extras** (Business summary, Branches & devices), and Combos: keep, or fold? The epic says preserve every page.
8. **Permissions:** wire the pane gates in section 5 (changes who sees Menu, Staff, Roles and the Settings panes; a manager or cashier-grade administrator may lose entries they see today). Approve per pane.
9. **Quick toggles** for language and theme: keep (reachable without Admin Mode) or move to the account menu? They stay clearly tied to the same providers either way.

## 8. Impact and risks

- **Tests that encode the current map and will need deliberate edits** (not silent ones): `back_office_shell_test.dart` — `ten tabs, in its order, in its words` (l. 772, English and Arabic names), `every tab's items…` (l. 805, the full Arabic label list per tab), the Settings-section test (l. 893), `People is a tab again…` (l. 918), the fit test at 1100 px, `every tab is named in both languages, never the same word twice` (l. 1132); `settings_bar_test.dart` — the map and Arabic-words tests (l. 417, 847), the fit test (l. 904), Home/Log out tests (l. 775).
- **Width:** the bar is tested to fit at the supported width in both languages; adding a menu (an account menu) or longer labels can break that, and the page header uses the same words.
- **Cloud vs offline:** `_authoringPanes` and `_pointsToPlatform` are keyed to `BackOfficeTab`; renaming or splitting a tab must keep them total (they are exhaustive `switch`es, so the compiler will say).
- **Food-service models:** Floor/Dining areas is meaningless to a cloud kitchen or a food truck; Shifts/Treasury depend on cash handling. "Hide because not applicable" is a different rule from "hide because not permitted" and has no mechanism today (the platform has no venue type). Not solved here.
- **Not examined:** dropdown behaviour in a running app (Arabic RTL placement, keyboard, Escape, off-screen placement) — it is the `menu_bar` package over Flutter's `MenuAnchor`; whether the package honours RTL and the keyboard is UNVERIFIED.
- **Documentation gaps:** `docs/FEATURE_INVENTORY.md` has no row for Back Office navigation, and there is no existing navigation document before this one. The seven-file feature folder was not created.

## 9. Proposed acceptance criteria and test plan (for approval, not yet applied)

- A table-driven test over `ManagementPane.values`: every pane has exactly one primary menu location and an EN and AR label; the only repeated labels are the ones listed as intentional here.
- `managementPanesFor` and the bar still agree for owner, manager, cashier-grade administrator, a custom role with one capability, offline and cloud (extend `back_office_shell_test`).
- A deep link naming a pane the person may not open is refused (already tested for Purchasing; extend per newly gated pane).
- Widget tests: account menu contents per person; keyboard open and Escape; Arabic placement; the bar fits at the supported widths in both languages.
- Manual: a before/after screenshot per changed menu in English and Arabic.
