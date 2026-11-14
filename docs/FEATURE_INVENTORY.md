# Feature inventory

Index of the Xorder knowledge layer. Looked up by `/project-documentation context` and by every lifecycle skill (`/develop-feature` and the skills it calls). Keep it greppable: one summary row and, once documented, one block per feature, with the slug always in backticks.
Maintained by `/project-documentation scan`, `feature`, `update` and `validate`. Template: `.claude/skills/project-documentation/templates/FEATURE_INVENTORY.md`. Status definitions: `.claude/skills/project-documentation/references/progress-management.md`. Live progress: `docs/DOCUMENTATION_PROGRESS.md`.

Scan depth: **route level** (cloud routes parsed statically, POS→cloud client calls matched, bootstrap contents read) — 2026-10-20 · Baseline: cloud `main 06bc8e3` · POS `main d592db8`
What "route level" means: cloud routes were parsed statically (`scripts/harness/route-index.py` → `docs/architecture/cloud-route-index.md`, 252 routes, 77 controllers, count cross-checked against the source), the dashboard router was indexed (`docs/architecture/web-route-index.md`, 96 entries), the POS→cloud client calls were extracted from the POS code and matched to routes, and the bootstrap bundle contents were read. Footprint values follow the rules in `docs/architecture/feature-route-map.md`. Still **not** done: tracing business rules, request/response shapes, tables or tests for any feature except `pos-shifts`; Vue pages are matched to features by file name only; POS entry points are file-name hints.

Footprint: `cloud-only` · `pos-only` · `shared` (talk through the API) · `shared-model` · `UNVERIFIED` (not yet traced).
Verification: `UNVERIFIED` (not documented) · `drafted` · `validated` · `stale`.

## Modules
| Module | Description | Features | Module doc |
| --- | --- | --- | --- |
| `auth-and-tenancy` | Login, password reset, signup, JWT guard, tenant scope | 4 | `docs/modules/auth-and-tenancy.md` |
| `roles-and-staff` | Staff, tenant roles, platform users, POS PINs and grants | 4 | `docs/modules/roles-and-staff.md` |
| `restaurant-and-branches` | Restaurant profile and branding, branches, platform-side restaurant management, uploads | 4 | pending |
| `menu-management` | Categories, items, option groups, combos, import/export | 5 | pending |
| `pricing-tax-tenders` | Tax rules, service charges, tender types, financial accounts, units, receipt profile | 6 | pending |
| `tables-and-qr` | Tables, dining areas, QR codes | 3 | pending |
| `diner-ordering` | Public menu, diner orders, bill requests, reviews, diner customer capture | 5 | pending |
| `order-management` | Dashboard orders, live board, notifications and push | 3 | pending |
| `customers` | Customer directory (dashboard and POS) | 1 | pending |
| `pos-sales` | POS orders, sale, payment, receipt, floor, home screen | 6 | pending |
| `shifts-and-cash` | Shifts, cash movements, cash-up, refunds | 2 | `docs/modules/shifts-and-cash.md` |
| `pos-provisioning-licensing` | Terminals, pairing, bootstrap, licences, fleet | 5 | pending |
| `stock-and-purchasing` | Stock items/levels/adjustments, purchase orders, suppliers, supplier invoices and payments | 5 | pending |
| `reporting-and-insights` | Reports, stats, pulse, insights | 3 | pending |
| `platform-admin` | Plans, subscriptions, audit log, leads, landing content | 5 | pending |
| `pos-back-office-and-ops` | POS management screen, backup, ETA e-invoicing, printing, installer, setup wizard, status bar, receipt layout | 8 | pending |

## Features (summary)
Entry points are hints from directory/file names (cloud: controller; POS: folder or file). `—` means none found by name. Cloud revision and POS revision are the baseline above for seed rows.
| Slug | Module | Title | Footprint | Cloud entry (hint) | POS entry (hint) | Doc status | Verification |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `auth-login` | auth-and-tenancy | Login, session token and password change | shared (POS client call verified) | `Auth\AuthController`, `app/Support/Jwt.php` · 4 routes | — | drafted | core drafted |
| `auth-password-reset` | auth-and-tenancy | Password reset by email | cloud-only | `Auth\PasswordResetController` · 2 routes | — | drafted | core drafted |
| `auth-signup` | auth-and-tenancy | Self-service restaurant signup | cloud-only | `Public\SignupController` · 1 routes | — | drafted | core drafted |
| `tenant-isolation` | auth-and-tenancy | Tenant isolation (restaurant scope) | cloud-only | `Models\Scopes\RestaurantScope`, `Models\Concerns\BelongsToRestaurant`, `Support\TenantContext` · no routes | — | drafted | core drafted |
| `staff-management` | roles-and-staff | Restaurant staff accounts | shared (bootstrap download) | `Dashboard\StaffController` · 6 routes | `management_staff_pane.dart` | drafted | core drafted |
| `tenant-roles` | roles-and-staff | Roles, capabilities and gates | shared (bootstrap download) | `Dashboard\RoleController`, `Enums\TenantCapability` · 6 routes | `management_roles_pane.dart`, `permission_resolver.dart` | drafted | core drafted |
| `platform-users` | roles-and-staff | Platform (Super Admin portal) users | cloud-only | `Admin\PlatformUserController`, `Enums\Capability` · 6 routes | — | drafted | core drafted |
| `pos-pin` | roles-and-staff | Cashier PIN for the POS | shared (bootstrap download) | `Dashboard\PosPinController`, `Support\PosPin` · 2 routes | `core/security/pin_hash.dart` | drafted | core drafted |
| `content-languages` | menu-management | Content languages: names asked only in the enabled languages (XORD-005) | shared (bootstrap flag `bilingual`) | `Support\ContentLanguages`, `Requests\Concerns\PreservesDisabledLanguages` · 0 routes | `domain/models/content_languages.dart`, `menu_editor_widgets.dart`, 8 admin dialogs | drafted | cloud half UNVERIFIED this session |
| `restaurant-profile` | restaurant-and-branches | Restaurant profile and branding | shared (bootstrap download) | `Dashboard\RestaurantProfileController`, `Public\RestaurantBrandingController` · 3 routes | — | pending | UNVERIFIED |
| `branches` | restaurant-and-branches | Branches | shared (POS client call verified) | `Dashboard\BranchController`, `Dashboard\MapLinkController` · 8 routes | — | pending | UNVERIFIED |
| `platform-restaurants` | restaurant-and-branches | Restaurant provisioning and status (Super Admin) | cloud-only | `Admin\RestaurantController`, `Admin\RestaurantAdminController`, `Admin\RestaurantStatusController` · 9 routes | — | pending | UNVERIFIED |
| `image-uploads` | restaurant-and-branches | Image upload | cloud-only | `UploadController`, `Services\ImageUploadService` · 1 routes | — | pending | UNVERIFIED |
| `menu-categories` | menu-management | Categories | shared (bootstrap download) | `Dashboard\CategoryController` · 8 routes | `management_menu_pane.dart` | pending | UNVERIFIED |
| `menu-items` | menu-management | Menu items and variants | shared (bootstrap download) | `Dashboard\MenuItemController` · 8 routes | `management_items_pane.dart`, `domain/models/catalog.dart` | pending | UNVERIFIED |
| `menu-option-groups` | menu-management | Option groups and extras | shared (bootstrap download) | `Dashboard\OptionGroupController` · 5 routes | `management_extras_pane.dart`, `domain/models/option_group.dart` | pending | UNVERIFIED |
| `menu-combos` | menu-management | Combos | shared-model (no client or bootstrap link found) | `Dashboard\ComboController` · 5 routes | `management_combos_pane.dart`, `domain/models/combo.dart` | pending | UNVERIFIED |
| `menu-import-export` | menu-management | Menu import and export | shared-model (no client or bootstrap link found) | `Dashboard\MenuImportController`, `Dashboard\MenuExportController` · 2 routes | `menu_import_dialog.dart`, `domain/services/menu_import.dart` | pending | UNVERIFIED |
| `tax-rules` | pricing-tax-tenders | Tax rules | shared (bootstrap download) | `Dashboard\TaxRuleController` · 4 routes | `management_taxes_pane.dart`, `domain/models/tax.dart` | drafted (partial: offline VAT rate and default group; cloud dashboard screen untraced) | core drafted 2026-10-26 · xorder-pos `a6f5fe5` · xorder-cloud `06bc8e3` · `docs/features/tax-rules/` |
| `service-charges` | pricing-tax-tenders | Service charges | shared (bootstrap download) | `Dashboard\ChargeController` · 4 routes | `management_charges_pane.dart` | pending | UNVERIFIED |
| `tender-types` | pricing-tax-tenders | Payment methods | shared (bootstrap download) | `Dashboard\TenderTypeController` · 4 routes | `management_tenders_pane.dart`, `domain/models/tender_method.dart` | pending | UNVERIFIED |
| `financial-accounts` | pricing-tax-tenders | Financial accounts and the account each payment method pays into (XORD-015, stage 1) | shared (bootstrap download) | `Dashboard\FinancialAccountController`, `Dashboard\TenderAccountDefaultController` · 6 routes | `management_accounts_pane.dart`, `domain/models/financial_account.dart`, migration 60 | drafted (written 2026-10-26 from the build; stage 1 built and tested, stage 2 not built; not `validate`d) | core drafted; dashboard tab and till pane not seen running |
| `units` | pricing-tax-tenders | Units of measure | shared-model (no client or bootstrap link found) | `Dashboard\UnitController` · 4 routes | `management_units_pane.dart` | pending | UNVERIFIED |
| `receipt-profile` | pricing-tax-tenders | Receipt profile | shared (bootstrap download) | `Dashboard\ReceiptProfileController`, `Services\ReceiptProfileService` · 2 routes | `management_receipt_pane.dart`, `features/receipt/*` | pending | UNVERIFIED |
| `tables` | tables-and-qr | Tables | shared (bootstrap download) | `Dashboard\TableController` · 13 routes | `features/floor`, `management_floor_pane.dart` | pending | UNVERIFIED |
| `dining-areas` | tables-and-qr | Dining areas | shared-model (no client or bootstrap link found) | `Dashboard\DiningAreaController` · 5 routes | `domain/services/floor_overlay.dart` | pending | UNVERIFIED |
| `qr-codes` | tables-and-qr | QR codes | shared-model (no client or bootstrap link found) | `Dashboard\DashboardQrController`, `Admin\RestaurantQrController`, `Public\RestaurantQrController`, `Services\QrCodeService` · 6 routes | `features/receipt/receipt_qr.dart` | pending | UNVERIFIED |
| `public-menu` | diner-ordering | Public menu and SEO shell | cloud-only | `Public\PublicMenuApiController`, `Public\MenuShellController`, `Public\SitemapController` · 4 routes | — | pending | UNVERIFIED |
| `diner-orders` | diner-ordering | Diner orders (cart, WhatsApp checkout) | cloud-only | `Public\PublicOrderController`, `Public\PublicTableController` · 4 routes | — | pending | UNVERIFIED |
| `bill-requests` | diner-ordering | Bill requests | cloud-only | `Public\PublicBillRequestController`, `Dashboard\BillRequestController` · 6 routes | — | pending | UNVERIFIED |
| `reviews` | diner-ordering | Diner reviews and internal notes | cloud-only | `Public\PublicReviewController`, `Dashboard\ReviewController` · 6 routes | — | pending | UNVERIFIED |
| `diner-customer-capture` | diner-ordering | Diner customer capture | cloud-only | `Public\PublicCustomerController`, `Services\CustomerDirectory` · 1 routes | — | pending | UNVERIFIED |
| `dashboard-orders` | order-management | Orders and live board | cloud-only | `Dashboard\OrderController` · 3 routes | — | pending | UNVERIFIED |
| `notifications-push` | order-management | Notifications and push | cloud-only | `Dashboard\NotificationController`, `Dashboard\PushTokenController`, `Services\PushService` · 6 routes | — | pending | UNVERIFIED |
| `order-status-workflow` | order-management | Order status transitions | pos-only (no cloud route) | `Enums\OrderStatus` · no routes | `domain/models/order_record.dart` | pending | UNVERIFIED |
| `customers` | customers | Customer directory | shared (POS client call verified) | `Dashboard\CustomerController`, `Pos\CustomerController`, `Services\PosCustomerService` · 3 routes | `management_customers_pane.dart`, `features/payment/customer_dialog.dart` | pending | UNVERIFIED |
| `pos-orders` | pos-sales | POS orders and payments to cloud | shared (POS client call verified) | `Pos\OrderController`, `Services\PosOrderService`, `Services\PosPricingEngine` · 3 routes | `domain/services/ticket_engine.dart`, `postgres_orders_repository.dart` | pending | UNVERIFIED |
| `pos-sale-screen` | pos-sales | Sale screen | pos-only (no cloud route) | — · no routes | `features/sale` | pending | UNVERIFIED |
| `pos-payment` | pos-sales | Payment | pos-only (no cloud route) | `Services\PosOrderService` · no routes | `features/payment` | pending | UNVERIFIED |
| `pos-receipts-printing` | pos-sales | Receipts and printing | pos-only (no cloud route) | — · no routes | `features/receipt`, `data/hardware` | pending | UNVERIFIED |
| `receipt-logo-and-layout` | pos-sales | Receipt: restaurant logo, aligned amounts, currency on every amount (XORD-024 to 026) | pos-only (no cloud route) | — · no routes | `features/receipt/{receipt_document,receipt_raster,receipt_paper,logo_bitmap}.dart`, `core/config/printer_config.dart`, `printer_settings_dialog.dart` | drafted | core drafted |
| `pos-order-history` | pos-sales | Order history and reprint | pos-only (no cloud route) | — · no routes | `features/history`, `postgres_order_history_repository.dart` | pending | UNVERIFIED |
| `pos-shifts` | shifts-and-cash | POS shifts, cash movements and cash-up | **shared** | `Pos\ShiftController`, `Services\PosShiftService` | `postgres_shift_repository.dart`, `features/shift`, `features/cash` | **drafted** | **drafted** |
| `waiter-app` | pos-sales | Waiter handheld: table orders on a phone/tablet over a LAN link to the till (WA1) | pos-only (LAN link, no cloud route) | — · no cloud routes | `packages/xorder_waiter_link/`, `apps/xorder_pos_waiter/`, `features/waiter_link/`, `postgres_waiter_devices.dart`, migration 65 | WA1 built 2026-11-09, uncommitted (xorder-pos `development`) | drafted |
| `dashboard-shift-details` | shifts-and-cash | Dashboard shift details page and force close of a revoked till's shift | cloud-only (dashboard) | `Dashboard\PosShiftController`, `Services\PosShiftService::summary/forceClose` · 2 routes | — | built 2026-11-09, uncommitted (`feat/dashboard-shift-details`) | drafted |
| `pos-business-day` | shifts-and-cash | POS business day (opening it, day notice) | pos-only (no cloud route) | — · no routes | `domain/services/business_day_service.dart`, `features/shift`, `features/lock`, `features/start` | **drafted** | **drafted** |
| `pos-refunds` | shifts-and-cash | POS refunds | shared (POS client call verified) | `Pos\RefundController`, `Services\PosRefundService` · 2 routes | `features/refund`, `domain/services/refund_engine.dart` | pending | UNVERIFIED |
| `pos-terminals-pairing` | pos-provisioning-licensing | Terminal registration and pairing | shared (POS client call verified) | `Pos\TerminalController`, `Dashboard\PosTerminalController`, `Admin\RestaurantTerminalController`, `Services\PosProvisioningService` · 14 routes | `data/cloud/cloud_provisioning_repository.dart`, `features/setup` | pending | UNVERIFIED |
| `pos-bootstrap` | pos-provisioning-licensing | POS bootstrap bundle and config version | shared (POS client call verified) | `Pos\BootstrapController`, `Services\PosBootstrapService`, `Services\PosConfigVersion` · 1 routes | `data/cloud/bootstrap_bundle.dart`, `bootstrap_seeder.dart` | pending | UNVERIFIED |
| `pos-licensing` | pos-provisioning-licensing | POS licences (online and offline) | shared (POS client call verified) | `Pos\LicenceController`, `Admin\LicenceController`, `Services\LicenceIssuer`, `Services\LicenceActivator` · 17 routes | `features/licensing`, `bin/pos_licence.dart` | pending | UNVERIFIED |
| `pos-fleet` | pos-provisioning-licensing | Terminal fleet monitoring | cloud-only | `Admin\PosFleetController` · 2 routes | — | pending | UNVERIFIED |
| `pos-cloud-sync` | pos-provisioning-licensing | Sync and outbox | shared (POS client call verified) | `Pos\*` controllers · no routes | `data/cloud/cloud_sync.dart`, `outbox_drain.dart` | pending | UNVERIFIED |
| `stock-items` | stock-and-purchasing | Stock items | shared-model (no client or bootstrap link found) | `Dashboard\StockItemController`, `Services\StockItemService` · 5 routes | `management_stock_pane.dart`, `stock_item_dialog.dart` | pending | UNVERIFIED |
| `stock-levels-adjustments` | stock-and-purchasing | Stock levels and adjustments | shared-model (no client or bootstrap link found) | `Dashboard\StockLevelController`, `Dashboard\StockAdjustmentController`, `Services\StockAdjustmentService` · 2 routes | `domain/services/stock_costing.dart` | pending | UNVERIFIED |
| `purchase-orders` | stock-and-purchasing | Purchase orders and receiving | shared-model (no client or bootstrap link found) | `Dashboard\PurchaseOrderController`, `Services\PurchaseOrderService`, `Services\ReceivingService` · 8 routes · `Dashboard\PurchasingLookupController` | `management_purchasing_pane.dart`, `receive_dialog.dart` | pending | UNVERIFIED |
| `suppliers` | stock-and-purchasing | Suppliers | shared-model (no client or bootstrap link found) | `Dashboard\SupplierController` · 5 routes | `supplier_dialog.dart` | pending | UNVERIFIED |
| `supplier-invoices-payments` | stock-and-purchasing | Supplier invoices, payments and account | shared-model (no client or bootstrap link found) | `Dashboard\SupplierInvoiceController`, `SupplierPaymentController`, `SupplierAccountController` · 5 routes | `supplier_invoice_dialog.dart`, `postgres_supplier_invoices_repository.dart` | pending | UNVERIFIED |
| `reports` | reporting-and-insights | Reports | shared-model (no client or bootstrap link found) | `Dashboard\ReportController`, `Services\ReportService` · 3 routes | `management_reports_pane.dart`, `postgres_reports_repository.dart` | pending | UNVERIFIED |
| `dashboard-stats` | reporting-and-insights | Dashboard stats and pulse | shared-model (no client or bootstrap link found) | `Dashboard\StatsController`, `Dashboard\PulseController` · 2 routes | `management_home_pane.dart` | pending | UNVERIFIED |
| `insights` | reporting-and-insights | Insights | cloud-only | `Dashboard\InsightsController`, `Admin\InsightsController` · 2 routes | — | pending | UNVERIFIED |
| `plans-subscriptions` | platform-admin | Plans, entitlements, subscriptions | cloud-only | `Admin\PlanController`, `Admin\SubscriptionController`, `Services\PlanEntitlementService`, `Services\PlanLimitService`, command `subscriptions:process` · 6 routes | — | pending | UNVERIFIED |
| `audit-log` | platform-admin | Audit and activity logs | shared-model (no client or bootstrap link found) | `Admin\AuditLogController`, `Services\AuditLogger`, `Services\ActivityLogReader` · 4 routes | `management_activity_pane.dart` | pending | UNVERIFIED |
| `leads` | platform-admin | Leads | cloud-only | `Admin\LeadController`, `Public\LeadController` · 4 routes | — | pending | UNVERIFIED |
| `landing-content` | platform-admin | Landing content and marketing site | shared-model (no client or bootstrap link found) | `Admin\LandingContentController`, `Public\LandingContentController` · 3 routes | — (Vue `apps/landing`) | pending | UNVERIFIED |
| `restaurant-features` | platform-admin | Per-restaurant feature flags | cloud-only (service and middleware; no route) | `Services\RestaurantFeatureService`, `Enums\Feature`, middleware `EnsureFeatureEnabled` · no routes | — | pending | UNVERIFIED |
| `pos-management-screen` | pos-back-office-and-ops | POS back-office (management) screen | pos-only (no cloud route) | — · no routes | `features/admin/presentation/management_screen.dart` | pending | UNVERIFIED |
| `pos-cloud-back-office` | pos-back-office-and-ops | Cloud back office from the till | UNVERIFIED | — · no routes | `features/admin/presentation/cloud_back_office_screen.dart` | pending | UNVERIFIED |
| `pos-backup` | pos-back-office-and-ops | Backup and restore | pos-only (no cloud route) | — · no routes | `data/backup`, `management_backup_pane.dart` | pending | UNVERIFIED |
| `pos-eta-einvoicing` | pos-back-office-and-ops | ETA e-invoice filing | pos-only (no cloud route) | — · no routes | `data/eta`, `domain/services/eta_*.dart`, `management_eta_pane.dart` | pending | UNVERIFIED |
| `pos-setup-installer` | pos-back-office-and-ops | Setup wizard, installer, migration tool | pos-only (no cloud route) | — · no routes | `features/setup`, `bin/pos_migrate.dart`, `installer/` | pending | UNVERIFIED |
| `pos-setup-owner-step` | pos-back-office-and-ops | Setup step 4 (offline first install): two plain screens, one button each | pos-only (no cloud route) | — · no routes | `features/setup` (`setup_panes.dart`, `setup_state.dart`, `setup_controller.dart`, `setup_wizard.dart`) | drafted | built, uncommitted (2026-10-27); not validated; PostgreSQL build not run |
| `pos-terminal-delete-visibility` | pos-provisioning-licensing | Terminal lists say whether Delete can succeed (`has_money_history`), XORD-042 | cloud-only (dashboard and Super Admin) | `Dashboard\PosTerminalController@index`, `Admin\RestaurantTerminalController@index`, `Services\PosProvisioningService::withMoneyHistory` | — | drafted | built, uncommitted (2026-11-03); API tests run; pages not seen; not validated |
| `pos-cloud-single-till-sqlite` | pos-back-office-and-ops | Cloud POS on SQLite (proposal; owner widened it to every cloud till on 2026-11-08, Q8 open) | pos-only | — · no routes | `app/providers.dart`, `data/postgres/` (to be mirrored) | drafted | built 2026-11-09 on xorder-pos `development` (`28f6b67`…`53255d2`, not pushed): Cloud app on encrypted SQLite, every cloud till alone (Q8), sqlite3mc; PostgreSQL + SQLite suites run; Windows workflow not run; not validated |
| `pos-cloud-sign-in-setup` | pos-back-office-and-ops | Cloud app setup by owner sign-in instead of licence key + licence server (licence arrives in bootstrap) | shared (uses existing `auth/login`, `dashboard/pos/terminals*`, `pos/terminals/{register,claim}`, `pos/bootstrap`) | none new | `features/setup` (`setup_state.dart` `cloudSteps`, `setup_panes.dart`), `data/cloud/cloud_api.dart`, cloud app `cloud_provisioning_repository.dart` | drafted | built, uncommitted (2026-11-08, on xorder-pos `9f1b7d2`); D2–D6 (sign-in only, owner only, cloud-only licence, `____.xorder.io`, cloud only); unit + widget tests run; e2e rewritten, not run; not validated |
| `pos-split-apps` | pos-back-office-and-ops | One codebase, two apps: `packages/shared_module` shared + `apps/xorder_pos_cloud` + `apps/xorder_pos_offline` (D10; shared package renamed from `xorder_pos` 2026-11-08) | pos-only (cloud: one mode per licence, stage 6) | `Admin\StoreLicenceRequest`, `RenewLicenceRequest`, `StoreRestaurantRequest` (stage 6, branch `feat/licence-one-mode` `30b1529`, unmerged) | `packages/shared_module/` (shared till, `lib/pos_main.dart` `runPos`, `test/package_boundaries_test.dart`); `packages/xorder_pos_test_support/`; `apps/xorder_pos_offline/` (`lib/main.dart`, `lib/wiring.dart`, `lib/features/admin/`); `apps/xorder_pos_cloud/` (`lib/main.dart`, `lib/wiring.dart`, `lib/data/cloud/`, `lib/features/cloud_back_office_screen.dart`, `integration_test/`) | drafted (all seven files present; API, DATABASE, TEST_PLAN, TEST_REPORT, CHANGELOG written 2026-11-08 against POS `7fa0d06`; not `validate`d) | TECHNICAL approved 2026-11-08; stages 0-3 and the `shared_module` rename on POS `development` `7fa0d06` (workspace, two apps with a fixed mode, mode-only code moved into its app, `xorder_pos_test_support`); stages 4 (`a30cfae`, mode checks + AC-5) and 5 (`18a9f9d`, one Windows installer per app; not compiled, no Windows run) merged on `development`; stage 6 built on cloud branch `feat/licence-one-mode`, unmerged; `integration_test/` stale and not run |
| `pos-lock-signin` | pos-back-office-and-ops | Lock screen and cashier sign-in | pos-only (no cloud route) | — · no routes | `features/lock`, `features/start` | pending | UNVERIFIED |
| `global-status-bar` | pos-back-office-and-ops | Status bar under every POS screen | pos-only (no cloud route) | — · no routes | `app/till_status_bar.dart`, `app/app.dart` | drafted | drafted |
| `receipt-design-system` | pos-back-office-and-ops | Receipt layout and design tokens | pos-only (no cloud route) | — · no routes | `features/receipt/slip_style.dart`, `receipt_document.dart`, `receipt_raster.dart`, `receipt_paper.dart` | drafted | drafted |
| `pos-home-screen` | pos-sales | Home screen: one button per enabled order type | pos-only (no cloud route) | — · no routes | `features/home`, `app/router.dart`, `features/start` | drafted | drafted |
| `pos-signin-first-home` | pos-sales | Sign in first; shift, order types and Close the day on Home | pos-only (no cloud route) | — · no routes | `features/start`, `features/home`, `features/shift`, `app/router.dart`, `features/lock/idle_lock.dart` | drafted | built, uncommitted (2026-10-27); not validated |
| `finance-account-kind-per-method` | pricing-tax-tenders | A payment method offers only accounts of its own kind | shared (POS and cloud) | `FinancialAccountController`, `SetTenderAccountDefaultRequest` | `domain/models/financial_account.dart`, `management_accounts_pane.dart` | drafted | drafted |

## Feature blocks
Documented features only. Paths are workspace-relative; `C:` = `apps/xorder-cloud/apps/api/`, `P:` = `apps/xorder-pos/`, `W:` = `apps/xorder-cloud/apps/web/`.

### `pos-shifts`
- **Module / title / footprint:** `shifts-and-cash` · POS shifts, cash movements and cash-up · shared
- **Cloud implementation:** routes `GET pos/shifts/current`, `POST pos/shifts`, `POST pos/shifts/{shift}/close`, `GET pos/shifts/{shift}/report`, `POST pos/cash-movements` (`C:routes/api.php:814-818`, group `pos.device` at `:787`); `C:app/Http/Controllers/Pos/ShiftController.php`; requests `C:app/Http/Requests/Pos/{OpenShiftRequest,CloseShiftRequest,StoreCashMovementRequest}.php`; service `C:app/Services/PosShiftService.php`; models `C:app/Models/{PosShift,PosCashMovement}.php`; resource `C:app/Http/Resources/PosShiftResource.php`; capabilities `C:app/Enums/TenantCapability.php:98-100`; dashboard tiles `C:app/Http/Controllers/Dashboard/StatsController.php:75`, `W:src/pages/dashboard/HomeView.vue:179-190`
- **Desktop implementation:** `P:lib/data/postgres/postgres_shift_repository.dart`; interface `P:lib/domain/repositories/repositories.dart:851-900`; model `P:lib/domain/models/shift.dart`; screens `P:lib/features/shift/presentation/shift_dialogs.dart`, `P:lib/features/cash/presentation/*`, `P:lib/features/admin/presentation/management_shifts_pane.dart`; cloud client `P:lib/data/cloud/{cloud_api.dart:191-210,outbox_drain.dart,cloud_sync.dart:277-314}`
- **Relevant source files (evidence list):** every path in `docs/features/pos-shifts/FEATURE.md` "Confirmed source references", plus `C:app/Http/Middleware/PosDeviceAuth.php`, `C:bootstrap/app.php` (63, 71-86), `C:app/Services/PosOrderService.php` (503-513), `C:app/Http/Controllers/Dashboard/StatsController.php` (132-157), `C:database/migrations/2026_09_02_000900_create_pos_shifts_and_cash_movements_tables.php`, `C:database/migrations/2026_09_02_000600_add_pos_columns_to_orders_tables.php`, `C:database/migrations/2026_09_02_000700_create_order_payments_table.php`, `P:lib/data/postgres/postgres_cash_movements_repository.dart`, `P:lib/domain/services/authorization.dart`, `P:lib/domain/models/{permissions,pos_settings}.dart`, `P:lib/data/postgres/migrations.dart` (shifts at 278-330, movements at 1495-1540, columns/indexes/outbox at 4335-4380)
- **Business rules and workflows:** BR-1..BR-12, AC-1..AC-10 in `docs/features/pos-shifts/FEATURE.md`; WF-1..WF-5 in `docs/features/pos-shifts/WORKFLOWS.md`
- **API contracts:** POS-BE-009 (READY; built behavior diverges from the text in places, see API.md), POS-BE-010 (refund terms in cash maths), POS-BE-019 (error envelope), POS-BE-021 (APPROVED, not built; drain is the serial form); `docs/features/pos-shifts/API.md`
- **Database dependencies:** cloud `pos_shifts`, `pos_cash_movements`, `orders.pos_shift_id`, `order_payments.pos_shift_id`, `pos_refunds.pos_shift_id`; POS `pos_shifts`, `pos_cash_movements`, `pos_sync_outbox`, `pos_orders.shift_id`; `docs/features/pos-shifts/DATABASE.md`
- **Related features:** `pos-orders` (an order names the open shift; payments feed expected cash; cloud attributes only to an open shift), `pos-refunds` (cash refunds reduce expected cash), `pos-cloud-sync` (outbox ordering, quarantine/defer policy), `pos-terminals-pairing` (terminal row is the lock, heartbeat carries `shift_open`, `pos.device` gate), `tender-types` (cash kind decides cash sales), `tenant-roles` (capabilities and POS key mapping), `dashboard-stats` (current shift tile, `analytics.view`), `supplier-invoices-payments` (drawer pay-outs create cash movements, `drawer-payouts` endpoint), `pos-management-screen` (shift history pane)
- **Existing tests:** cloud `C:tests/Feature/Pos/PosShiftsTest.php`; POS `P:test/data/postgres_shift_test.dart` (integration-tagged), `P:test/data/shift_close_drain_test.dart`, `P:test/data/shift_history_test.dart`, `P:test/domain/{shift_ownership,cash_movement}_test.dart`, `P:test/features/{close_shift_*,cash_dialogs,shift_history_panes}_test.dart`; gaps listed in `TEST_PLAN.md`
- **Documentation status:** `docs/features/pos-shifts/` (FEATURE, TECHNICAL, API, DATABASE, TEST_PLAN, TEST_REPORT, CHANGELOG, WORKFLOWS; plus BEHAVIORAL_ANALYSIS, unvalidated); module doc `docs/modules/shifts-and-cash.md`
- **Source revision:** cloud `06bc8e3` · POS `d592db8` · uncommitted evidence files at that time: only the cited contract documents `docs/coordination/{BACKEND_TO_POS,POS_TO_BACKEND}.md` in both repos (hunks outside POS-BE-009) · documented 2026-10-20
- **Verification status:** core `drafted` (split from the analysis; core passes 6-9: 4, 2, 3 errors, then the first qualifying pass under the owner-approved criterion found 2 behavioral (B) and 16 other items, all fixed; criterion not met, new pass needed) · analysis `unvalidated` (`docs/features/pos-shifts/BEHAVIORAL_ANALYSIS.md`) · last validated 2026-10-20 in five independent passes (6, 7, 4, 3, 5 wrong claims; all fixed; not converged) — `docs/validation/2026-10-20-pos-shifts-validation-report.md`, `...-revalidation-report.md`, `...-round3-validation-report.md`, `...-round4-validation-report.md`, `...-round5-validation-report.md` · open unknowns: see FEATURE.md "Unknowns and assumptions"


### `pos-business-day`
- **Module / title / footprint:** `shifts-and-cash` · POS business day (opening it, and saying when it is wrong) · pos-only
- **Cloud implementation:** none; no route, payload or migration. Open contract item CB-10 (business day on synced orders, PROPOSED).
- **Desktop implementation:** `P:lib/domain/services/business_day_service.dart`; providers `P:lib/app/providers.dart:524,550,559,595`; callers `P:lib/features/shift/presentation/shift_dialogs.dart:123`, `P:lib/features/lock/lock_screen.dart:125`; notice `P:lib/features/start/start_screen.dart:224,382`; existing `P:lib/data/postgres/postgres_business_day_repository.dart`, `P:lib/domain/models/pos_settings.dart:179` (`DayPolicy`), `P:lib/features/cash/presentation/day_close_dialog.dart`.
- **Relevant source files (evidence list):** every path in `docs/features/pos-business-day/FEATURE.md` "Confirmed source references", plus `P:lib/data/backup/backup_service.dart` (restore guard) and `P:lib/data/postgres/migrations.dart` (1448-1486, 3246-3392).
- **Business rules and workflows:** BR-1..BR-10, AC-1..AC-7 in `docs/features/pos-business-day/FEATURE.md`
- **API contracts:** none (CB-10 PROPOSED, not built)
- **Database dependencies:** POS `pos_business_days`, `business_day_id` on `pos_orders`, `pos_refunds`, `pos_shifts`, `pos_cash_movements`; trigger `pos_stamp_business_day` (migration 36)
- **Related features:** `pos-shifts` (the shift is filed under the day; shift open calls this first), `pos-cloud-sync` (does not carry the day today), backup and restore (restore refused while a day is open)
- **Existing tests:** `P:test/domain/business_day_service_test.dart`, `P:test/features/business_day_opening_ui_test.dart`, `P:test/features/business_day_providers_test.dart`; PostgreSQL (written, not run) `P:test/data/business_day_opening_test.dart`; existing `P:test/data/business_day_stamping_test.dart`, `P:test/data/wave_b_repositories_test.dart`
- **Documentation status:** `docs/features/pos-business-day/` (FEATURE, TECHNICAL, API, DATABASE, TEST_PLAN, TEST_REPORT, CHANGELOG), drafted, not validated
- **Source revision:** POS `f78bfa7` plus uncommitted work (the change itself) · documented 2026-10-24
### `auth-login`
- **Module / title / footprint:** `auth-and-tenancy` · Login, session token and password change · shared (POS client call verified)
- **Cloud implementation:** login/me/logout/change-password (4 routes), `Support\Jwt`, guard in `AppServiceProvider` (route table: `docs/architecture/cloud-route-index.md`)
- **Desktop implementation:** see `docs/features/auth-login/FEATURE.md` (Cross-application dependencies)
- **Relevant source files (evidence list):** Cloud: `C:routes/api.php:87-96`; `C:app/Http/Controllers/Auth/AuthController.php`; `C:app/Http/Requests/Auth/{LoginRequest,ChangePasswordRequest}.php`; `C:app/Support/Jwt.php`; `C:config/jwt.php`; `C:config/auth.php`; `C:app/Providers/AppServiceProvider.php:175-182,219-254`; `C:app/Http/Middleware/{EnsureRole,SetLocale}.php`; `C:bootstrap/app.php:45-69`; `C:app/Http/Resources/UserResource.php`; `C:app/Models/User.php`; `C:app/Services/AuditLogger.php`. Clients: `K:api-client/src/{auth,api}.js`; `W:src/pages/LoginView.vue`; `W:src/router/index.js:260-291`; `W:src/pages/dashboard/ProfileView.vue:115-135`; `P:lib/data/cloud/{cloud_api,cloud_provisioning_repository}.dart`.
- **Business rules and workflows:** BR-/AC- ids in `docs/features/auth-login/FEATURE.md`; analysis (unvalidated) in `docs/features/auth-login/BEHAVIORAL_ANALYSIS.md`
- **API contracts:** `docs/features/auth-login/API.md`; no ledger item names `/api/auth/login`; related items POS-BE-022/023/030 are listed in `docs/features/auth-login/FEATURE.md`
- **Database dependencies:** `users`, `password_reset_tokens` (shared), `sessions` (exists; not used by the JWT guard); `docs/features/auth-login/DATABASE.md`
- **Related features:** `tenant-isolation`, `tenant-roles`, `auth-password-reset`, `pos-terminals-pairing` (pairing uses login)
- **Existing tests:** `docs/features/auth-login/FEATURE.md` ("Existing automated tests") and `TEST_PLAN.md`
- **Documentation status:** `docs/features/auth-login/` (7 files + BEHAVIORAL_ANALYSIS); module doc `docs/modules/auth-and-tenancy.md`
- **Source revision:** cloud `06bc8e3` · POS `d592db8` · documented 2026-10-20
- **Verification status:** core `drafted` (author self-check, mechanical citation check; no independent pass yet) · analysis `unvalidated`

### `auth-password-reset`
- **Module / title / footprint:** `auth-and-tenancy` · Password reset by email · cloud-only
- **Cloud implementation:** forgot-password, reset-password (2 routes) (route table: `docs/architecture/cloud-route-index.md`)
- **Desktop implementation:** see `docs/features/auth-password-reset/FEATURE.md` (Cross-application dependencies)
- **Relevant source files (evidence list):** `C:routes/api.php:88-89`; `C:app/Http/Controllers/Auth/PasswordResetController.php`; `C:app/Providers/AppServiceProvider.php:88-109`; `C:app/Models/Restaurant.php:314-328`; `C:config/auth.php:104-110`; `C:config/mail.php:17`; `C:app/Models/User.php`; `C:tests/Feature/SecurityHardeningTest.php`.
- **Business rules and workflows:** BR-/AC- ids in `docs/features/auth-password-reset/FEATURE.md`; analysis (unvalidated) in `docs/features/auth-password-reset/BEHAVIORAL_ANALYSIS.md`
- **API contracts:** `docs/features/auth-password-reset/API.md`; no contract-ledger item names these endpoints unless stated there
- **Database dependencies:** `password_reset_tokens`, `users`; `docs/features/auth-password-reset/DATABASE.md`
- **Related features:** `auth-login`, `staff-management`, `platform-users`
- **Existing tests:** `docs/features/auth-password-reset/FEATURE.md` ("Existing automated tests") and `TEST_PLAN.md`
- **Documentation status:** `docs/features/auth-password-reset/` (7 files + BEHAVIORAL_ANALYSIS); module doc `docs/modules/auth-and-tenancy.md`
- **Source revision:** cloud `06bc8e3` · POS `d592db8` · documented 2026-10-20
- **Verification status:** core `drafted` (author self-check, mechanical citation check; no independent pass yet) · analysis `unvalidated`

### `auth-signup`
- **Module / title / footprint:** `auth-and-tenancy` · Self-service restaurant signup · cloud-only
- **Cloud implementation:** public signup (1 route, flag `SELF_SERVE_SIGNUP`) (route table: `docs/architecture/cloud-route-index.md`)
- **Desktop implementation:** see `docs/features/auth-signup/FEATURE.md` (Cross-application dependencies)
- **Relevant source files (evidence list):** `C:routes/api.php:841-842`; `C:app/Http/Controllers/Public/SignupController.php`; `C:app/Http/Requests/Public/SignupRequest.php`; `C:app/Services/RestaurantProvisioningService.php`; `C:app/Services/SlugService.php`; `C:app/Notifications/RestaurantAdminCredentials.php`; `C:config/platform.php:42-57`; `C:app/Enums/Feature.php:86-95`.
- **Business rules and workflows:** BR-/AC- ids in `docs/features/auth-signup/FEATURE.md`; analysis (unvalidated) in `docs/features/auth-signup/BEHAVIORAL_ANALYSIS.md`
- **API contracts:** `docs/features/auth-signup/API.md`; no contract-ledger item names these endpoints unless stated there
- **Database dependencies:** `restaurants`, `users`, `roles`, `restaurant_features`, `pos_licences`; `docs/features/auth-signup/DATABASE.md`
- **Related features:** `pos-licensing`, `tenant-roles`, `plans-subscriptions`
- **Existing tests:** `docs/features/auth-signup/FEATURE.md` ("Existing automated tests") and `TEST_PLAN.md`
- **Documentation status:** `docs/features/auth-signup/` (7 files + BEHAVIORAL_ANALYSIS); module doc `docs/modules/auth-and-tenancy.md`
- **Source revision:** cloud `06bc8e3` · POS `d592db8` · documented 2026-10-20
- **Verification status:** core `drafted` (author self-check, mechanical citation check; no independent pass yet) · analysis `unvalidated`

### `tenant-isolation`
- **Module / title / footprint:** `auth-and-tenancy` · Tenant isolation (restaurant scope) · cloud-only
- **Cloud implementation:** no routes; `RestaurantScope`, `BelongsToRestaurant`, `TenantContext`, `PosDeviceAuth` override (route table: `docs/architecture/cloud-route-index.md`)
- **Desktop implementation:** see `docs/features/tenant-isolation/FEATURE.md` (Cross-application dependencies)
- **Relevant source files (evidence list):** `C:app/Models/Scopes/RestaurantScope.php`; `C:app/Models/Concerns/BelongsToRestaurant.php`; `C:app/Support/TenantContext.php`; `C:app/Http/Middleware/PosDeviceAuth.php`; `C:app/Http/Controllers/Dashboard/StaffController.php:154-170`; `C:app/Http/Controllers/Dashboard/PosPinController.php:76-100`; `C:tests/Feature/TenantIsolationTest.php`.
- **Business rules and workflows:** BR-/AC- ids in `docs/features/tenant-isolation/FEATURE.md`; analysis (unvalidated) in `docs/features/tenant-isolation/BEHAVIORAL_ANALYSIS.md`
- **API contracts:** `docs/features/tenant-isolation/API.md`; no contract-ledger item names these endpoints unless stated there
- **Database dependencies:** all tenant tables (`restaurant_id`); `docs/features/tenant-isolation/DATABASE.md`
- **Related features:** every tenant-owned feature; `pos-terminals-pairing`
- **Existing tests:** `docs/features/tenant-isolation/FEATURE.md` ("Existing automated tests") and `TEST_PLAN.md`
- **Documentation status:** `docs/features/tenant-isolation/` (7 files + BEHAVIORAL_ANALYSIS); module doc `docs/modules/auth-and-tenancy.md`
- **Source revision:** cloud `06bc8e3` · POS `d592db8` · documented 2026-10-20
- **Verification status:** core `drafted` (author self-check, mechanical citation check; no independent pass yet) · analysis `unvalidated`

### `staff-management`
- **Module / title / footprint:** `roles-and-staff` · Restaurant staff accounts · shared (bootstrap download)
- **Cloud implementation:** 6 staff routes, `PlanLimitService`, `TenantUserService` (route table: `docs/architecture/cloud-route-index.md`)
- **Desktop implementation:** see `docs/features/staff-management/FEATURE.md` (Cross-application dependencies)
- **Relevant source files (evidence list):** `C:routes/api.php:300-321`; `C:app/Http/Controllers/Dashboard/StaffController.php`; `C:app/Http/Requests/Dashboard/{StoreStaffRequest,UpdateStaffRequest}.php`; `C:app/Http/Requests/Dashboard/Concerns/GrantsTenantCapabilities.php`; `C:app/Services/{TenantUserService,PlanLimitService,PosBootstrapService}.php`; `C:app/Notifications/StaffCredentials.php`; `W:src/pages/dashboard/{StaffView,StaffForm}.vue`; `P:lib/data/cloud/bootstrap_seeder.dart:459-507`; `P:lib/features/admin/presentation/management_staff_pane.dart`.
- **Business rules and workflows:** BR-/AC- ids in `docs/features/staff-management/FEATURE.md`; analysis (unvalidated) in `docs/features/staff-management/BEHAVIORAL_ANALYSIS.md`
- **API contracts:** `docs/features/staff-management/API.md`; no contract-ledger item names these endpoints unless stated there
- **Database dependencies:** `users`, `roles`, `plans.max_staff`; POS `pos_staff`; `docs/features/staff-management/DATABASE.md`
- **Related features:** `tenant-roles`, `pos-pin`, `auth-login`, `plans-subscriptions`
- **Existing tests:** `docs/features/staff-management/FEATURE.md` ("Existing automated tests") and `TEST_PLAN.md`
- **Documentation status:** `docs/features/staff-management/` (7 files + BEHAVIORAL_ANALYSIS); module doc `docs/modules/roles-and-staff.md`
- **Source revision:** cloud `06bc8e3` · POS `d592db8` · documented 2026-10-20
- **Verification status:** core `drafted` (author self-check, mechanical citation check; no independent pass yet) · analysis `unvalidated`

### `tenant-roles`
- **Module / title / footprint:** `roles-and-staff` · Roles, capabilities and gates · shared (bootstrap download)
- **Cloud implementation:** 6 role routes, gates, `EnsureRole`, `EnsureFeatureEnabled`, `EnsureSubscriptionAllowsWrites` (route table: `docs/architecture/cloud-route-index.md`)
- **Desktop implementation:** see `docs/features/tenant-roles/FEATURE.md` (Cross-application dependencies)
- **Relevant source files (evidence list):** `C:app/Enums/{Capability,TenantCapability,RoleEnum,Feature}.php`; `C:app/Models/{Role,User}.php`; `C:app/Providers/AppServiceProvider.php:118-164`; `C:app/Http/Middleware/{EnsureRole,EnsureFeatureEnabled,EnsureSubscriptionAllowsWrites}.php`; `C:app/Http/Controllers/Dashboard/RoleController.php`; `C:app/Http/Requests/Dashboard/{StoreRoleRequest,UpdateRoleRequest}.php`; `C:app/Http/Requests/Dashboard/Concerns/GrantsTenantCapabilities.php`; `C:app/Services/TenantRoleService.php`; `W:src/lib/{capabilities,useCaps}.js`; `K:api-client/src/auth.js`; `P:lib/domain/models/permissions.dart`; `P:lib/domain/services/permission_resolver.dart`.
- **Business rules and workflows:** BR-/AC- ids in `docs/features/tenant-roles/FEATURE.md`; analysis (unvalidated) in `docs/features/tenant-roles/BEHAVIORAL_ANALYSIS.md`
- **API contracts:** `docs/features/tenant-roles/API.md`; POS-BE-002 (READY) names `GET /api/dashboard/roles/capabilities` in its request text, POS-BE-030 withholds `purchase.manage`; see `docs/features/tenant-roles/FEATURE.md`
- **Database dependencies:** `roles`, `users.role_id`; POS `pos_staff.capabilities`, `pos_roles`; `docs/features/tenant-roles/DATABASE.md`
- **Related features:** `staff-management`, `platform-users`, `restaurant-features`, `plans-subscriptions`
- **Existing tests:** `docs/features/tenant-roles/FEATURE.md` ("Existing automated tests") and `TEST_PLAN.md`
- **Documentation status:** `docs/features/tenant-roles/` (7 files + BEHAVIORAL_ANALYSIS); module doc `docs/modules/roles-and-staff.md`
- **Source revision:** cloud `06bc8e3` · POS `d592db8` · documented 2026-10-20
- **Verification status:** core `drafted` (author self-check, mechanical citation check; no independent pass yet) · analysis `unvalidated`

### `platform-users`
- **Module / title / footprint:** `roles-and-staff` · Platform (Super Admin portal) users · cloud-only
- **Cloud implementation:** 6 admin user routes, `PlatformUserService` (route table: `docs/architecture/cloud-route-index.md`)
- **Desktop implementation:** see `docs/features/platform-users/FEATURE.md` (Cross-application dependencies)
- **Relevant source files (evidence list):** `C:routes/api.php:139-146`; `C:app/Http/Controllers/Admin/PlatformUserController.php`; `C:app/Services/PlatformUserService.php`; `C:app/Http/Requests/Admin/{StorePlatformUserRequest,UpdatePlatformUserRequest}.php`; `C:app/Notifications/PlatformUserCredentials.php`; `W:src/pages/admin/{UsersList,UserForm}.vue`.
- **Business rules and workflows:** BR-/AC- ids in `docs/features/platform-users/FEATURE.md`; analysis (unvalidated) in `docs/features/platform-users/BEHAVIORAL_ANALYSIS.md`
- **API contracts:** `docs/features/platform-users/API.md`; no contract-ledger item names these endpoints unless stated there
- **Database dependencies:** `users` (restaurant_id null); `docs/features/platform-users/DATABASE.md`
- **Related features:** `tenant-roles` (platform matrix), `auth-login`
- **Existing tests:** `docs/features/platform-users/FEATURE.md` ("Existing automated tests") and `TEST_PLAN.md`
- **Documentation status:** `docs/features/platform-users/` (7 files + BEHAVIORAL_ANALYSIS); module doc `docs/modules/roles-and-staff.md`
- **Source revision:** cloud `06bc8e3` · POS `d592db8` · documented 2026-10-20
- **Verification status:** core `drafted` (author self-check, mechanical citation check; no independent pass yet) · analysis `unvalidated`

### `pos-pin`
- **Module / title / footprint:** `roles-and-staff` · Cashier PIN for the POS · shared (bootstrap download)
- **Cloud implementation:** 2 PIN routes, `Support\PosPin`, bootstrap `staff[].pin` (route table: `docs/architecture/cloud-route-index.md`)
- **Desktop implementation:** see `docs/features/pos-pin/FEATURE.md` (Cross-application dependencies)
- **Relevant source files (evidence list):** `C:routes/api.php:705-711`; `C:app/Http/Controllers/Dashboard/PosPinController.php`; `C:app/Http/Requests/Dashboard/SetPosPinRequest.php`; `C:app/Support/PosPin.php`; `C:app/Services/PosBootstrapService.php:333`; `C:app/Services/PosConfigVersion.php`; `P:lib/core/security/pin_hash.dart`; `P:lib/data/cloud/bootstrap_seeder.dart:465-483`; `P:lib/features/lock/lock_screen.dart`.
- **Business rules and workflows:** BR-/AC- ids in `docs/features/pos-pin/FEATURE.md`; analysis (unvalidated) in `docs/features/pos-pin/BEHAVIORAL_ANALYSIS.md`
- **API contracts:** `docs/features/pos-pin/API.md`; no contract-ledger item names these endpoints unless stated there
- **Database dependencies:** `users.pos_pin_salt|hash`, `restaurants.pos_config_version`; POS `pos_staff.pin_salt|pin_hash`; `docs/features/pos-pin/DATABASE.md`
- **Related features:** `staff-management`, `pos-bootstrap`, `pos-sale-screen` (lock screen)
- **Existing tests:** `docs/features/pos-pin/FEATURE.md` ("Existing automated tests") and `TEST_PLAN.md`
- **Documentation status:** `docs/features/pos-pin/` (7 files + BEHAVIORAL_ANALYSIS); module doc `docs/modules/roles-and-staff.md`
- **Source revision:** cloud `06bc8e3` · POS `d592db8` · documented 2026-10-20
- **Verification status:** core `drafted` (author self-check, mechanical citation check; no independent pass yet) · analysis `unvalidated`

## Uncovered source
Computed in the route-level scan (2026-10-20): cloud routes: every one of the 252 routed controllers belongs to a feature row (`Dashboard\PurchasingLookupController` was added to `purchase-orders`). Dashboard SPA pages: `admin/NotFoundView.vue` only (not a feature). Not computed: `apps/xorder-pos/lib` files outside the entry points named in the rows (for example `lib/data/import`, `lib/core/export`, `lib/core/l10n`, `lib/data/hardware`), the diner SPA (`apps/xorder-cloud/apps/menu/src`) and the marketing site, which are matched to features by name only; the next `module` run for each feature must list its files.

## Absent (searched, not found)
| Looked for | Search used | Result |
| --- | --- | --- |
| Cloud route for the POS branch-sales calls | `grep -rn "branch/sales" apps/xorder-cloud/apps/api/routes apps/xorder-cloud/apps/api/app` | no match; the endpoints are contract POS-BE-029, filed but not built (`apps/xorder-cloud/docs/coordination/POS_TO_BACKEND.md:1539-1541,2254`; `apps/xorder-pos/lib/data/cloud/branch_sales_api.dart`, class comment) |
| POS client call for 8 of the 20 `/api/pos/*` routes | the extraction in `docs/architecture/feature-route-map.md` method note (all `'/api/...'` string literals in `apps/xorder-pos/lib`) | no client call for `licence/issuer`, `licence/current`, `terminals/rotate-token`, `orders/by-client-id/{uuid}`, `orders/{order}/payments`, `refunds/by-client-id/{uuid}`, `shifts/current`, `shifts/{shift}/report` |
| Client of `GET /api/pos/shifts/current` or `/report` | `grep -rn "pos/shifts\|shifts/current\|cash-movements" apps/xorder-pos/lib apps/xorder-pos/test apps/xorder-pos/bin apps/xorder-cloud/apps/web/src apps/xorder-cloud/apps/menu/src apps/xorder-cloud/apps/landing/src apps/xorder-cloud/packages` | only `cloud_api.dart:192,201,207` (open, close, cash movement) |
| Vue shift page | `grep -rli shift apps/xorder-cloud/apps/web/src` | only `HomeView.vue` tiles and unrelated words |
| Laravel `Policies` classes | `ls apps/xorder-cloud/apps/api/app/Policies`; `grep -rn "Policy\|->authorize(" app` | no directory; no authorize calls; authorization is `Gate::define` in `app/Providers/AppServiceProvider.php:120-163` plus middleware and service-level capability checks |
| Queued jobs | `grep -rl ShouldQueue app` | none found; background work is scheduled commands (`routes/console.php`) |
| Vue unit/E2E tests | repo `CLAUDE.md`/`repo-map.md`; `docs/testing/reports/2026-10-20-project-test-report-build.md` | none configured; only `pnpm build` |
| Dashboard endpoint listing or editing shifts | `grep -in shift routes/api.php`; `grep -rln 'PosShift\b\|pos_shift' app routes` | the first finds the controller import (`:65`), comments (`:227,667,749`) and the five `pos/*` routes (`:814-818`); the second lists models, resources, `PosShiftService`, `PosOrderService`, `PosRefundService`, `PosProvisioningService` and `Dashboard\StatsController` as the only non-POS reader |
| `auth-login`: restaurant status check at login | `grep -rn "RestaurantStatus" app/Http/Controllers/Auth` (cloud api) | 0 matches |
| `auth-login`: use of the `remember` field | `grep -rn "'remember'" app` | only the rule at `app/Http/Requests/Auth/LoginRequest.php:19` |
| `auth-login`: coordination item naming `/api/auth/login` | `grep -n "auth/login" apps/xorder-cloud/docs/coordination/*.md apps/xorder-pos/docs/coordination/*.md` | no match (items POS-BE-022/023/030 mention login-adjacent flows; see `docs/features/auth-login/FEATURE.md`) |
| `staff-management`: soft deletes on `User` | `grep -c SoftDeletes app/Models/User.php` | 0 |
| `staff-management`: enforcement sites of `max_staff` | `grep -rn "max_staff" app database` | plan model/resource/requests, `app/Services/PlanLimitService.php:55`, two migrations; the only consumer in staff creation is `StaffController::store` through `PlanLimitService` |
| `staff-management`: cloud use of licence `max_users` | `grep -rn "max_users" app` | `PosLicence` model, resource and request, `Pos/LicenceController.php:159`, `Services/LicenceIssuer.php`; nothing in the staff code |
| `staff-management`: cloud test of a successful staff update | `grep -rn "putJson(\"/api/dashboard/staff" tests \| grep -v /pin` | one hit, `tests/Feature/TenantRbacTest.php:537`, the 404 case for another restaurant's owner |
| `staff-management` / `tenant-roles`: POS client calls to staff or role endpoints | `grep -rn "dashboard/staff\|/api/dashboard/roles" apps/xorder-pos/lib` ; `grep -rn "roles/capabilities" apps/xorder-pos/lib apps/xorder-pos/test` | no match for either |
| `tenant-roles`: test comparing `RoleEnum::capabilities()` with `ROLE_CAPS` | `grep -rn "->capabilities()" tests` | 0 matches |
| `tenant-roles`: test of `GET roles/capabilities` or `PUT roles/{role}` | `grep -rln "roles/capabilities" tests`; `grep -rn "putJson.*roles/" tests` | 0 matches for both |
| `tenant-roles`: migration backfilling later capabilities | `grep -rln "pos.operate\|purchase.manage\|pos.provision\|customers.create" database` | no file |
| `auth-login`: refresh token, token blocklist, `jti` | `grep -rniE "refresh_token|jti|blocklist" app config routes` (cloud api; the pipes are escaped in this table) | one match, a comment at `app/Http/Controllers/Auth/AuthController.php:126` suggesting a blocklist |
| `auth-login`: last-login timestamp | `grep -rn "last_login_at" app database` | no match |
| `auth-login`: Sanctum tokens | `grep -rn "createToken\|auth:sanctum" app routes` | no match |
| `auth-login`: Vue call to change-password outside the shared client | `grep -rln "change-password" apps/xorder-cloud/apps/web/src apps/xorder-cloud/packages/api-client/src` | only `packages/api-client/src/auth.js` (the profile page calls it through the client) |
| `auth-login`: POS calls to me, logout, change-password, forgot or reset | `grep -rn "auth/me\|auth/logout\|change-password\|forgot-password\|reset-password" apps/xorder-pos/lib` | no match |
| `staff-management`: pagination of the staff list | `grep -n "paginate\|simplePaginate\|->get()" app/Http/Controllers/Dashboard/StaffController.php` | only `->get()` (`:56`); no pagination |
