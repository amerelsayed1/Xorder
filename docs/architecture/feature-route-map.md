# Feature → route map (generated at route level)

Generated 2026-10-20 from `docs/architecture/cloud-route-index.md`, `docs/architecture/web-route-index.md` and the seed rows of `docs/FEATURE_INVENTORY.md` (cloud `main 06bc8e3`, POS `main d592db8`). Cloud controllers per feature come from the inventory seed rows; route counts and gates come from the route index (static parse). Vue pages are matched **by file name** and are not traced. Footprint rules: **shared (POS client call verified)** = the POS code calls an endpoint of this feature (`apps/xorder-pos/lib/data/cloud/*`, `lib/features/licensing/data/*`); **shared (bootstrap download)** = the data is delivered to the POS in `GET /api/pos/bootstrap` (`PosBootstrapService.php`) and no other client call was found; **shared-model** = both apps have the concept, no client call or bootstrap field links them; **cloud-only** = no POS counterpart found by name; **pos-only** = no cloud route.

| Slug | Module | Footprint | Routes | Controllers | Gates (can / feature) | Vue pages (by name) |
| --- | --- | --- | --- | --- | --- | --- |
| `auth-login` | auth-and-tenancy | shared (POS client call verified) | 4 | `Auth\AuthController` | - | - |
| `auth-password-reset` | auth-and-tenancy | cloud-only | 2 | `Auth\PasswordResetController` | - | - |
| `auth-signup` | auth-and-tenancy | cloud-only | 1 | `Public\SignupController` | - | - |
| `staff-management` | roles-and-staff | shared (bootstrap download) | 6 | `Dashboard\StaffController` | `can:staff.create`, `can:staff.delete`, `can:staff.update`, `can:staff.view` | `dashboard/StaffForm.vue`, `dashboard/StaffView.vue` |
| `tenant-roles` | roles-and-staff | shared (bootstrap download) | 6 | `Dashboard\RoleController` | `can:staff.create`, `can:staff.delete`, `can:staff.update`, `can:staff.view` | `dashboard/RoleForm.vue`, `dashboard/RolesView.vue` |
| `platform-users` | roles-and-staff | cloud-only | 6 | `Admin\PlatformUserController` | `can:platform_users.manage` | `admin/UserForm.vue`, `admin/UsersList.vue` |
| `pos-pin` | roles-and-staff | shared-model (no client or bootstrap link found) | 2 | `Dashboard\PosPinController` | `feature:pos` | - |
| `restaurant-profile` | restaurant-and-branches | shared (bootstrap download) | 3 | `Dashboard\RestaurantProfileController`, `Public\RestaurantBrandingController` | `can:settings.update`, `can:settings.view` | `dashboard/ProfileView.vue` |
| `branches` | restaurant-and-branches | shared (POS client call verified) | 8 | `Dashboard\BranchController`, `Dashboard\MapLinkController` | `can:branches.create`, `can:branches.delete`, `can:branches.list`, `can:branches.update`, `can:branches.view`, `feature:multi_branch` | `dashboard/BranchForm.vue`, `dashboard/BranchesView.vue` |
| `platform-restaurants` | restaurant-and-branches | cloud-only | 9 | `Admin\RestaurantController`, `Admin\RestaurantAdminController`, `Admin\RestaurantStatusController` | `can:restaurants.manage`, `can:restaurants.view` | `admin/DashboardView.vue`, `admin/RestaurantDetails.vue`, `admin/RestaurantForm.vue`, `admin/RestaurantsList.vue` |
| `image-uploads` | restaurant-and-branches | cloud-only | 1 | `UploadController` | - | - |
| `menu-categories` | menu-management | shared (bootstrap download) | 8 | `Dashboard\CategoryController` | `can:menu.create`, `can:menu.delete`, `can:menu.update`, `can:menu.view` | `dashboard/CategoriesView.vue` |
| `menu-items` | menu-management | shared (bootstrap download) | 8 | `Dashboard\MenuItemController` | `can:menu.create`, `can:menu.delete`, `can:menu.update`, `can:menu.view` | `dashboard/ItemForm.vue`, `dashboard/ItemsView.vue` |
| `menu-option-groups` | menu-management | shared (bootstrap download) | 5 | `Dashboard\OptionGroupController` | `can:menu.create`, `can:menu.delete`, `can:menu.update`, `can:menu.view` | `dashboard/ExtrasView.vue` |
| `menu-combos` | menu-management | shared-model (no client or bootstrap link found) | 5 | `Dashboard\ComboController` | `can:menu.create`, `can:menu.delete`, `can:menu.update`, `can:menu.view` | - |
| `menu-import-export` | menu-management | shared-model (no client or bootstrap link found) | 2 | `Dashboard\MenuImportController`, `Dashboard\MenuExportController` | `can:menu.create`, `can:menu.update`, `can:menu.view` | - |
| `tax-rules` | pricing-tax-tenders | shared (bootstrap download) | 4 | `Dashboard\TaxRuleController` | `can:settings.update`, `can:settings.view`, `feature:pos` | `dashboard/PosMoneyView.vue` |
| `service-charges` | pricing-tax-tenders | shared (bootstrap download) | 4 | `Dashboard\ChargeController` | `can:settings.update`, `can:settings.view`, `feature:pos` | `dashboard/PosMoneyView.vue` |
| `tender-types` | pricing-tax-tenders | shared (bootstrap download) | 4 | `Dashboard\TenderTypeController` | `can:settings.update`, `can:settings.view`, `feature:pos` | `dashboard/PosMoneyView.vue`, `dashboard/settings/PaymentMethodsView.vue` |
| `units` | pricing-tax-tenders | shared-model (no client or bootstrap link found) | 4 | `Dashboard\UnitController` | `can:purchase.manage`, `feature:purchasing` | `dashboard/inventory/UnitsView.vue` |
| `receipt-profile` | pricing-tax-tenders | shared (bootstrap download) | 2 | `Dashboard\ReceiptProfileController` | `can:settings.update`, `can:settings.view`, `feature:pos` | `dashboard/PosReceiptView.vue` |
| `tables` | tables-and-qr | shared (bootstrap download) | 13 | `Dashboard\TableController` | `can:tables.create`, `can:tables.delete`, `can:tables.live`, `can:tables.update`, `can:tables.view`, `feature:table_management` | `dashboard/TablesView.vue` |
| `dining-areas` | tables-and-qr | shared-model (no client or bootstrap link found) | 5 | `Dashboard\DiningAreaController` | `can:tables.create`, `can:tables.delete`, `can:tables.update`, `can:tables.view`, `feature:table_management` | `dashboard/DiningAreasView.vue` |
| `qr-codes` | tables-and-qr | shared-model (no client or bootstrap link found) | 6 | `Dashboard\DashboardQrController`, `Admin\RestaurantQrController`, `Public\RestaurantQrController` | `can:restaurants.view`, `can:settings.view` | - |
| `public-menu` | diner-ordering | cloud-only | 4 | `Public\PublicMenuApiController`, `Public\MenuShellController`, `Public\SitemapController` | - | - |
| `diner-orders` | diner-ordering | cloud-only | 4 | `Public\PublicOrderController`, `Public\PublicTableController` | - | - |
| `bill-requests` | diner-ordering | cloud-only | 6 | `Public\PublicBillRequestController`, `Dashboard\BillRequestController` | `can:bills.read`, `can:bills.update`, `feature:bill_requests` | - |
| `reviews` | diner-ordering | cloud-only | 6 | `Public\PublicReviewController`, `Dashboard\ReviewController` | `can:reviews.update`, `can:reviews.view`, `feature:internal_reviews` | `dashboard/ReviewsView.vue` |
| `diner-customer-capture` | diner-ordering | cloud-only | 1 | `Public\PublicCustomerController` | - | - |
| `dashboard-orders` | order-management | cloud-only | 3 | `Dashboard\OrderController` | `can:orders.read`, `can:orders.update`, `feature:system_ordering\\|pos` | `dashboard/LiveBoardView.vue`, `dashboard/OrdersView.vue` |
| `notifications-push` | order-management | cloud-only | 6 | `Dashboard\NotificationController`, `Dashboard\PushTokenController` | - | - |
| `order-status-workflow` | order-management | pos-only (no cloud route) | 0 | - | - | - |
| `customers` | customers | shared (POS client call verified) | 3 | `Dashboard\CustomerController`, `Pos\CustomerController` | `can:customers.view` | `dashboard/CustomerDetailView.vue`, `dashboard/CustomersView.vue` |
| `pos-orders` | pos-sales | shared (POS client call verified) | 3 | `Pos\OrderController` | - | - |
| `pos-sale-screen` | pos-sales | pos-only (no cloud route) | 0 | - | - | - |
| `pos-payment` | pos-sales | pos-only (no cloud route) | 0 | - | - | - |
| `pos-receipts-printing` | pos-sales | pos-only (no cloud route) | 0 | - | - | - |
| `pos-order-history` | pos-sales | pos-only (no cloud route) | 0 | - | - | - |
| `pos-shifts` | shifts-and-cash | shared (POS client call verified) | 5 | `Pos\ShiftController` | - | - |
| `pos-refunds` | shifts-and-cash | shared (POS client call verified) | 2 | `Pos\RefundController` | - | - |
| `pos-terminals-pairing` | pos-provisioning-licensing | shared (POS client call verified) | 14 | `Pos\TerminalController`, `Dashboard\PosTerminalController`, `Admin\RestaurantTerminalController` | `can:pos.provision`, `can:pos_fleet.manage`, `can:pos_fleet.view`, `feature:pos` | `dashboard/PosTerminalsView.vue` |
| `pos-bootstrap` | pos-provisioning-licensing | shared (POS client call verified) | 1 | `Pos\BootstrapController` | - | - |
| `pos-licensing` | pos-provisioning-licensing | shared (POS client call verified) | 17 | `Pos\LicenceController`, `Admin\LicenceController` | `can:licences.manage` | `admin/pos/ClientKindChoice.vue`, `admin/pos/LicenceDetails.vue`, `admin/pos/LicenceForm.vue`, `admin/pos/LicencesList.vue`, `admin/pos/OfflineLicenceForm.vue` |
| `pos-fleet` | pos-provisioning-licensing | cloud-only | 2 | `Admin\PosFleetController` | `can:pos_fleet.view` | - |
| `pos-cloud-sync` | pos-provisioning-licensing | shared (POS client call verified) | 0 | - | - | - |
| `stock-items` | stock-and-purchasing | shared-model (no client or bootstrap link found) | 5 | `Dashboard\StockItemController` | `can:purchase.manage`, `feature:purchasing` | `dashboard/inventory/StockItemsView.vue`, `dashboard/inventory/StockMovementsView.vue`, `dashboard/inventory/StockView.vue` |
| `stock-levels-adjustments` | stock-and-purchasing | shared-model (no client or bootstrap link found) | 2 | `Dashboard\StockLevelController`, `Dashboard\StockAdjustmentController` | `can:purchase.manage`, `feature:purchasing` | - |
| `purchase-orders` | stock-and-purchasing | shared-model (no client or bootstrap link found) | 8 | `Dashboard\PurchaseOrderController` | `can:purchase.manage`, `feature:purchasing` | `dashboard/purchasing/PurchaseOrderForm.vue`, `dashboard/purchasing/PurchaseOrderView.vue`, `dashboard/purchasing/PurchaseOrdersView.vue` |
| `suppliers` | stock-and-purchasing | shared-model (no client or bootstrap link found) | 5 | `Dashboard\SupplierController` | `can:purchase.manage`, `feature:purchasing` | `dashboard/purchasing/SupplierAccountView.vue`, `dashboard/purchasing/SuppliersView.vue` |
| `supplier-invoices-payments` | stock-and-purchasing | shared-model (no client or bootstrap link found) | 5 | `Dashboard\SupplierInvoiceController` | `can:purchase.manage`, `feature:purchasing` | `dashboard/purchasing/SupplierInvoiceForm.vue`, `dashboard/purchasing/SupplierInvoiceView.vue`, `dashboard/purchasing/SupplierInvoicesView.vue`, `dashboard/purchasing/SupplierPaymentForm.vue`, `dashboard/purchasing/SupplierPaymentView.vue`, `dashboard/purchasing/SupplierPaymentsView.vue` |
| `reports` | reporting-and-insights | shared-model (no client or bootstrap link found) | 3 | `Dashboard\ReportController` | `can:reports.view`, `feature:product_analytics` | `dashboard/AreasComparisonView.vue`, `dashboard/ProductPerformanceView.vue` |
| `dashboard-stats` | reporting-and-insights | shared-model (no client or bootstrap link found) | 2 | `Dashboard\StatsController`, `Dashboard\PulseController` | `can:analytics.view` | `dashboard/HomeView.vue` |
| `insights` | reporting-and-insights | cloud-only | 2 | `Dashboard\InsightsController`, `Admin\InsightsController` | `can:analytics.view`, `can:insights.view` | `admin/InsightsView.vue`, `dashboard/InsightsView.vue` |
| `plans-subscriptions` | platform-admin | cloud-only | 6 | `Admin\PlanController`, `Admin\SubscriptionController` | `can:plans.manage`, `can:subscriptions.manage` | `admin/PlanForm.vue`, `admin/PlansList.vue` |
| `audit-log` | platform-admin | shared-model (no client or bootstrap link found) | 4 | `Admin\AuditLogController` | `can:audit.view` | `admin/AuditLogsView.vue` |
| `leads` | platform-admin | cloud-only | 4 | `Admin\LeadController`, `Public\LeadController` | `can:leads.manage` | `admin/LeadsView.vue` |
| `landing-content` | platform-admin | shared-model (no client or bootstrap link found) | 3 | `Admin\LandingContentController`, `Public\LandingContentController` | `can:landing.manage` | `admin/settings/DemoSettings.vue`, `admin/settings/FaqSettings.vue`, `admin/settings/FeaturesSettings.vue`, `admin/settings/HeroSettings.vue`, `admin/settings/HighlightsSettings.vue`, `admin/settings/IndustriesSettings.vue` … |
| `restaurant-features` | platform-admin | cloud-only (service and middleware; no route) | 0 | - | - | - |
| `pos-management-screen` | pos-back-office-and-ops | pos-only (no cloud route) | 0 | - | - | - |
| `pos-cloud-back-office` | pos-back-office-and-ops | UNVERIFIED | 0 | - | - | - |
| `pos-backup` | pos-back-office-and-ops | pos-only (no cloud route) | 0 | - | - | - |
| `pos-eta-einvoicing` | pos-back-office-and-ops | pos-only (no cloud route) | 0 | - | - | - |
| `pos-setup-installer` | pos-back-office-and-ops | pos-only (no cloud route) | 0 | - | - | - |
| `pos-lock-signin` | pos-back-office-and-ops | pos-only (no cloud route) | 0 | - | - | - |

## Uncovered by the seed rows

Routed controllers not named in any feature row: `Dashboard\PurchasingLookupController`, `Dashboard\SupplierAccountController`, `Dashboard\SupplierPaymentController`.

Dashboard SPA pages (from `docs/architecture/web-route-index.md`) not matched to a feature by name (1): `admin/NotFoundView.vue`.

## Method notes
- POS client calls: every string literal of the form `'/api/...'`, `"/api/..."` or `'$_base/api/...'` in `apps/xorder-pos/lib/**/*.dart` was extracted (path variables normalised to `{}`) and compared with the paths in `cloud-route-index.md`. Result: 18 distinct paths, 17 matching a route, 2 without a route (`/api/pos/branch/sales`, `/api/pos/branch/sales/summary`, contract POS-BE-029, filed and not built); 8 of the 20 cloud `/api/pos/*` routes have no POS call. A path built dynamically (not as a literal) would be missed.
- Bootstrap contents: keys read from `apps/xorder-cloud/apps/api/app/Services/PosBootstrapService.php:57-163`.
- Vue pages are matched by file name only.
