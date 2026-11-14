# Dashboard SPA route index (generated)

Generated 2026-10-20 from `apps/xorder-cloud/apps/web/src/router/index.js` at cloud `main 06bc8e3` by `python3 -I scripts/harness/web-route-index.py` (line-based static parse; paths are as written, relative to their parent layout route; a route written over several lines may show `-` for missing fields). The menu (`apps/menu`) and landing (`apps/landing`) apps have no router file of this kind.

| Section | Path | Name | Page | Meta | router/index.js |
| --- | --- | --- | --- | --- | --- |
|  | `/login` | - | - | - | 12 |
| superAdminRoutes | `/` | - | - | - | 21 |
| superAdminRoutes | `` | admin.dashboard | `pages/admin/DashboardView.vue` | - | 25 |
| superAdminRoutes | `insights` | admin.insights | `pages/admin/InsightsView.vue` | capability: 'insights.view' | 26 |
| superAdminRoutes | `restaurants` | admin.restaurants | `pages/admin/RestaurantsList.vue` | capability: 'restaurants.view' | 27 |
| superAdminRoutes | `restaurants/create` | admin.restaurants.create | `pages/admin/RestaurantForm.vue` | capability: 'restaurants.manage' | 28 |
| superAdminRoutes | `restaurants/:id` | admin.restaurants.show | `pages/admin/RestaurantDetails.vue` | capability: 'restaurants.view' | 29 |
| superAdminRoutes | `restaurants/:id/edit` | admin.restaurants.edit | `pages/admin/RestaurantForm.vue` | capability: 'restaurants.manage' | 30 |
| superAdminRoutes | `users` | admin.users | `pages/admin/UsersList.vue` | capability: 'platform_users.manage' | 31 |
| superAdminRoutes | `users/create` | admin.users.create | `pages/admin/UserForm.vue` | capability: 'platform_users.manage' | 32 |
| superAdminRoutes | `users/:id/edit` | admin.users.edit | `pages/admin/UserForm.vue` | capability: 'platform_users.manage' | 33 |
| superAdminRoutes | `plans` | admin.plans | `pages/admin/PlansList.vue` | capability: 'plans.manage' | 34 |
| superAdminRoutes | `plans/create` | admin.plans.create | `pages/admin/PlanForm.vue` | capability: 'plans.manage' | 35 |
| superAdminRoutes | `plans/:id/edit` | admin.plans.edit | `pages/admin/PlanForm.vue` | capability: 'plans.manage' | 36 |
| superAdminRoutes | `pos/licences` | admin.licences | `pages/admin/pos/LicencesList.vue` | capability: 'licences.manage' | 40 |
| superAdminRoutes | `pos/licences/new` | admin.licences.new | `pages/admin/pos/ClientKindChoice.vue` | capability: 'licences.manage' | 45 |
| superAdminRoutes | `pos/licences/offline` | admin.licences.offline | `pages/admin/pos/OfflineLicenceForm.vue` | capability: 'licences.manage' | 46 |
| superAdminRoutes | `pos/licences/create` | admin.licences.create | `pages/admin/pos/LicenceForm.vue` | capability: 'licences.manage' | 49 |
| superAdminRoutes | `pos/licences/:id` | admin.licences.show | `pages/admin/pos/LicenceDetails.vue` | capability: 'licences.manage' | 50 |
| superAdminRoutes | `leads` | admin.leads | `pages/admin/LeadsView.vue` | capability: 'leads.manage' | 51 |
| superAdminRoutes | `audit-logs` | admin.audit | `pages/admin/AuditLogsView.vue` | capability: 'audit.view' | 52 |
| superAdminRoutes | `settings` | - | - | - | 54 |
| superAdminRoutes | `` | admin.settings.seo | - | - | 58 |
| superAdminRoutes | `seo` | admin.settings.seo | `pages/admin/settings/SeoSettings.vue` | - | 59 |
| superAdminRoutes | `hero` | admin.settings.hero | `pages/admin/settings/HeroSettings.vue` | - | 60 |
| superAdminRoutes | `whatsapp` | admin.settings.whatsapp | `pages/admin/settings/WhatsappSettings.vue` | - | 61 |
| superAdminRoutes | `highlights` | admin.settings.highlights | `pages/admin/settings/HighlightsSettings.vue` | - | 62 |
| superAdminRoutes | `features` | admin.settings.features | `pages/admin/settings/FeaturesSettings.vue` | - | 63 |
| superAdminRoutes | `industries` | admin.settings.industries | `pages/admin/settings/IndustriesSettings.vue` | - | 64 |
| superAdminRoutes | `demo` | admin.settings.demo | `pages/admin/settings/DemoSettings.vue` | - | 65 |
| superAdminRoutes | `packages` | admin.plans | - | - | 68 |
| superAdminRoutes | `faq` | admin.settings.faq | `pages/admin/settings/FaqSettings.vue` | - | 69 |
| superAdminRoutes | `lead-cta` | admin.settings.lead_cta | `pages/admin/settings/LeadCtaSettings.vue` | - | 70 |
| superAdminRoutes | `:pathMatch(.*)*` | admin.notfound | `pages/admin/NotFoundView.vue` | - | 75 |
| restaurantRoutes | `/admin` | - | - | - | 113 |
| restaurantRoutes | `` | dashboard.home | `pages/dashboard/HomeView.vue` | - | 122 |
| restaurantRoutes | `live` | dashboard.live | `pages/dashboard/LiveBoardView.vue` | capability: 'live.view' | 123 |
| restaurantRoutes | `insights` | dashboard.insights | `pages/dashboard/InsightsView.vue` | capability: 'analytics.view' | 124 |
| restaurantRoutes | `orders` | dashboard.orders | `pages/dashboard/OrdersView.vue` | capability: 'orders.view' | 125 |
| restaurantRoutes | `reviews` | dashboard.reviews | `pages/dashboard/ReviewsView.vue` | capability: 'reviews.view' | 126 |
| restaurantRoutes | `reports` | dashboard.reports.products | - | - | 127 |
| restaurantRoutes | `reports/products` | dashboard.reports.products | `pages/dashboard/ProductPerformanceView.vue` | capability: 'reports.view' | 128 |
| restaurantRoutes | `reports/areas` | dashboard.reports.areas | `pages/dashboard/AreasComparisonView.vue` | capability: 'reports.view' | 129 |
| restaurantRoutes | `customers` | dashboard.customers | `pages/dashboard/CustomersView.vue` | capability: 'customers.view' | 130 |
| restaurantRoutes | `customers/:id` | dashboard.customer | `pages/dashboard/CustomerDetailView.vue` | capability: 'customers.view' | 131 |
| restaurantRoutes | `branches` | dashboard.branches | `pages/dashboard/BranchesView.vue` | capability: 'branches.view' | 132 |
| restaurantRoutes | `branches/create` | dashboard.branches.create | `pages/dashboard/BranchForm.vue` | capability: 'branches.create' | 133 |
| restaurantRoutes | `branches/:id/edit` | dashboard.branches.edit | `pages/dashboard/BranchForm.vue` | capability: 'branches.update' | 134 |
| restaurantRoutes | `dining-areas` | dashboard.areas | `pages/dashboard/DiningAreasView.vue` | capability: 'tables.view' | 135 |
| restaurantRoutes | `tables` | dashboard.tables | `pages/dashboard/TablesView.vue` | capability: 'tables.view' | 136 |
| restaurantRoutes | `purchasing/suppliers` | dashboard.purchasing.suppliers | `pages/dashboard/purchasing/SuppliersView.vue` | capability: 'purchase.manage' | 141 |
| restaurantRoutes | `purchasing/orders` | dashboard.purchasing.orders | `pages/dashboard/purchasing/PurchaseOrdersView.vue` | capability: 'purchase.manage' | 142 |
| restaurantRoutes | `purchasing/orders/new` | dashboard.purchasing.orders.create | `pages/dashboard/purchasing/PurchaseOrderForm.vue` | capability: 'purchase.manage' | 143 |
| restaurantRoutes | `purchasing/orders/:id` | dashboard.purchasing.order | `pages/dashboard/purchasing/PurchaseOrderView.vue` | capability: 'purchase.manage' | 144 |
| restaurantRoutes | `purchasing/orders/:id/edit` | dashboard.purchasing.orders.edit | `pages/dashboard/purchasing/PurchaseOrderForm.vue` | capability: 'purchase.manage' | 145 |
| restaurantRoutes | `inventory/stock` | dashboard.inventory.stock | `pages/dashboard/inventory/StockView.vue` | capability: 'purchase.manage' | 146 |
| restaurantRoutes | `inventory/stock/:itemId` | dashboard.inventory.movements | `pages/dashboard/inventory/StockMovementsView.vue` | capability: 'purchase.manage' | 147 |
| restaurantRoutes | `inventory/items` | dashboard.inventory.items | `pages/dashboard/inventory/StockItemsView.vue` | capability: 'purchase.manage' | 148 |
| restaurantRoutes | `purchasing/invoices` | dashboard.purchasing.invoices | `pages/dashboard/purchasing/SupplierInvoicesView.vue` | capability: 'purchase.manage' | 150 |
| restaurantRoutes | `purchasing/invoices/new` | dashboard.purchasing.invoices.create | `pages/dashboard/purchasing/SupplierInvoiceForm.vue` | capability: 'purchase.manage' | 151 |
| restaurantRoutes | `purchasing/invoices/:id` | dashboard.purchasing.invoice | `pages/dashboard/purchasing/SupplierInvoiceView.vue` | capability: 'purchase.manage' | 152 |
| restaurantRoutes | `purchasing/invoices/:id/edit` | dashboard.purchasing.invoices.edit | `pages/dashboard/purchasing/SupplierInvoiceForm.vue` | capability: 'purchase.manage' | 153 |
| restaurantRoutes | `purchasing/payments` | dashboard.purchasing.payments | `pages/dashboard/purchasing/SupplierPaymentsView.vue` | capability: 'purchase.manage' | 154 |
| restaurantRoutes | `purchasing/payments/new` | dashboard.purchasing.payments.create | `pages/dashboard/purchasing/SupplierPaymentForm.vue` | capability: 'purchase.manage' | 155 |
| restaurantRoutes | `purchasing/payments/:id` | dashboard.purchasing.payment | `pages/dashboard/purchasing/SupplierPaymentView.vue` | capability: 'purchase.manage' | 156 |
| restaurantRoutes | `purchasing/suppliers/:id` | dashboard.purchasing.supplier | `pages/dashboard/purchasing/SupplierAccountView.vue` | capability: 'purchase.manage' | 157 |
| restaurantRoutes | `settings` | - | - | - | 165 |
| restaurantRoutes | `` | dashboard.profile | `pages/dashboard/ProfileView.vue` | - | 169 |
| restaurantRoutes | `users` | dashboard.staff | `pages/dashboard/StaffView.vue` | capability: 'staff.view' | 170 |
| restaurantRoutes | `users/create` | dashboard.staff.create | `pages/dashboard/StaffForm.vue` | capability: 'staff.create' | 171 |
| restaurantRoutes | `users/:id/edit` | dashboard.staff.edit | `pages/dashboard/StaffForm.vue` | capability: 'staff.update' | 172 |
| restaurantRoutes | `roles` | dashboard.roles | `pages/dashboard/RolesView.vue` | capability: 'staff.view' | 173 |
| restaurantRoutes | `roles/create` | dashboard.roles.create | `pages/dashboard/RoleForm.vue` | capability: 'staff.create' | 174 |
| restaurantRoutes | `roles/:id/edit` | dashboard.roles.edit | `pages/dashboard/RoleForm.vue` | capability: 'staff.update' | 175 |
| restaurantRoutes | `devices` | dashboard.pos.terminals | `pages/dashboard/PosTerminalsView.vue` | capability: 'pos.provision' | 181 |
| restaurantRoutes | `taxes` | dashboard.pos.money | `pages/dashboard/PosMoneyView.vue` | capability: 'settings.view' | 185 |
| restaurantRoutes | `payment-methods` | dashboard.pos.payment_methods | `pages/dashboard/settings/PaymentMethodsView.vue` | capability: 'settings.view' | 189 |
| restaurantRoutes | `receipt` | dashboard.pos.receipt | `pages/dashboard/PosReceiptView.vue` | capability: 'settings.view' | 195 |
| restaurantRoutes | `units` | dashboard.inventory.units | `pages/dashboard/inventory/UnitsView.vue` | capability: 'purchase.manage' | 202 |
| restaurantRoutes | `settings/profile` | dashboard.profile | - | - | 205 |
| restaurantRoutes | `inventory/units` | dashboard.inventory.units | - | - | 207 |
| restaurantRoutes | `profile` | dashboard.profile | - | - | 211 |
| restaurantRoutes | `staff` | dashboard.staff | - | - | 212 |
| restaurantRoutes | `staff/create` | dashboard.staff.create | - | - | 213 |
| restaurantRoutes | `staff/:id/edit` | dashboard.staff.edit | - | - | 214 |
| restaurantRoutes | `roles` | dashboard.roles | - | - | 215 |
| restaurantRoutes | `roles/create` | dashboard.roles.create | - | - | 216 |
| restaurantRoutes | `roles/:id/edit` | dashboard.roles.edit | - | - | 217 |
| restaurantRoutes | `pos/terminals` | dashboard.pos.terminals | - | - | 218 |
| restaurantRoutes | `pos/money` | dashboard.pos.money | - | - | 219 |
| restaurantRoutes | `categories` | dashboard.categories | `pages/dashboard/CategoriesView.vue` | capability: 'menu.view' | 220 |
| restaurantRoutes | `items` | dashboard.items | `pages/dashboard/ItemsView.vue` | capability: 'menu.view' | 221 |
| restaurantRoutes | `extras` | dashboard.extras | `pages/dashboard/ExtrasView.vue` | capability: 'menu.view' | 222 |
| restaurantRoutes | `items/create` | dashboard.items.create | `pages/dashboard/ItemForm.vue` | capability: 'menu.create' | 223 |
| restaurantRoutes | `items/:id/edit` | dashboard.items.edit | `pages/dashboard/ItemForm.vue` | capability: 'menu.update' | 224 |
| restaurantRoutes | `/:pathMatch(.*)*` | - | - | - | 227 |
