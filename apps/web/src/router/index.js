import { createRouter, createWebHistory } from 'vue-router'
import { trackPageView } from '@xorder/analytics'
import { useAuth } from '@xorder/api-client/auth.js'
import { isSuperAdminHost, restaurantSlug, superAdminUrl, restaurantUrl } from '../lib/host.js'
import { visibleSettingsSections } from '../pages/dashboard/settings/settings.config.js'

// One SPA bundle, served at the root of every admin subdomain. Which portal
// it is depends on the host: admin.<root> => super admin, <slug>.<root> =>
// that restaurant's dashboard.

const loginRoute = {
    path: '/login',
    name: 'login',
    component: () => import('../pages/LoginView.vue'),
    meta: { guest: true },
}

const superAdminRoutes = [
    loginRoute,
    {
        path: '/',
        component: () => import('../pages/admin/AdminLayout.vue'),
        meta: { portal: 'admin' },
        children: [
            { path: '', name: 'admin.dashboard', component: () => import('../pages/admin/DashboardView.vue') },
            { path: 'insights', name: 'admin.insights', component: () => import('../pages/admin/InsightsView.vue'), meta: { capability: 'insights.view' } },
            { path: 'restaurants', name: 'admin.restaurants', component: () => import('../pages/admin/RestaurantsList.vue'), meta: { capability: 'restaurants.view' } },
            { path: 'restaurants/create', name: 'admin.restaurants.create', component: () => import('../pages/admin/RestaurantForm.vue'), meta: { capability: 'restaurants.manage' } },
            { path: 'restaurants/:id', name: 'admin.restaurants.show', component: () => import('../pages/admin/RestaurantDetails.vue'), meta: { capability: 'restaurants.view' } },
            { path: 'restaurants/:id/edit', name: 'admin.restaurants.edit', component: () => import('../pages/admin/RestaurantForm.vue'), meta: { capability: 'restaurants.manage' } },
            { path: 'users', name: 'admin.users', component: () => import('../pages/admin/UsersList.vue'), meta: { capability: 'platform_users.manage' } },
            { path: 'users/create', name: 'admin.users.create', component: () => import('../pages/admin/UserForm.vue'), meta: { capability: 'platform_users.manage' } },
            { path: 'users/:id/edit', name: 'admin.users.edit', component: () => import('../pages/admin/UserForm.vue'), meta: { capability: 'platform_users.manage' } },
            { path: 'plans', name: 'admin.plans', component: () => import('../pages/admin/PlansList.vue'), meta: { capability: 'plans.manage' } },
            { path: 'plans/create', name: 'admin.plans.create', component: () => import('../pages/admin/PlanForm.vue'), meta: { capability: 'plans.manage' } },
            { path: 'plans/:id/edit', name: 'admin.plans.edit', component: () => import('../pages/admin/PlanForm.vue'), meta: { capability: 'plans.manage' } },
            // POS licences (POS-BE-015). licences.manage is SUPER_ADMIN-only, so
            // this whole section is invisible to every other platform role — the
            // route guard is the courtesy; the API gate is the boundary.
            { path: 'pos/licences', name: 'admin.licences', component: () => import('../pages/admin/pos/LicencesList.vue'), meta: { capability: 'licences.manage' } },
            // The fork every new client starts at: a cloud tenant we host, or an
            // offline customer who gets a licence and nothing else. Sits BEFORE
            // the two forms it leads to, because choosing wrong is expensive to
            // undo — see ClientKindChoice.vue.
            { path: 'pos/licences/new', name: 'admin.licences.new', component: () => import('../pages/admin/pos/ClientKindChoice.vue'), meta: { capability: 'licences.manage' } },
            { path: 'pos/licences/offline', name: 'admin.licences.offline', component: () => import('../pages/admin/pos/OfflineLicenceForm.vue'), meta: { capability: 'licences.manage' } },
            // Issuing to a tenant that already exists — reached from the fork,
            // not from the list, because it creates no client.
            { path: 'pos/licences/create', name: 'admin.licences.create', component: () => import('../pages/admin/pos/LicenceForm.vue'), meta: { capability: 'licences.manage' } },
            { path: 'pos/licences/:id', name: 'admin.licences.show', component: () => import('../pages/admin/pos/LicenceDetails.vue'), meta: { capability: 'licences.manage' } },
            { path: 'leads', name: 'admin.leads', component: () => import('../pages/admin/LeadsView.vue'), meta: { capability: 'leads.manage' } },
            { path: 'audit-logs', name: 'admin.audit', component: () => import('../pages/admin/AuditLogsView.vue'), meta: { capability: 'audit.view' } },
            {
                path: 'settings',
                component: () => import('../pages/admin/settings/SettingsView.vue'),
                meta: { capability: 'landing.manage' },
                children: [
                    { path: '', redirect: { name: 'admin.settings.seo' } },
                    { path: 'seo', name: 'admin.settings.seo', component: () => import('../pages/admin/settings/SeoSettings.vue') },
                    { path: 'hero', name: 'admin.settings.hero', component: () => import('../pages/admin/settings/HeroSettings.vue') },
                    { path: 'whatsapp', name: 'admin.settings.whatsapp', component: () => import('../pages/admin/settings/WhatsappSettings.vue') },
                    { path: 'highlights', name: 'admin.settings.highlights', component: () => import('../pages/admin/settings/HighlightsSettings.vue') },
                    { path: 'features', name: 'admin.settings.features', component: () => import('../pages/admin/settings/FeaturesSettings.vue') },
                    { path: 'industries', name: 'admin.settings.industries', component: () => import('../pages/admin/settings/IndustriesSettings.vue') },
                    { path: 'demo', name: 'admin.settings.demo', component: () => import('../pages/admin/settings/DemoSettings.vue') },
                    // Packages settings were replaced by Plans management (/plans).
                    // Redirect the old path so saved bookmarks keep working.
                    { path: 'packages', redirect: { name: 'admin.plans' } },
                    { path: 'faq', name: 'admin.settings.faq', component: () => import('../pages/admin/settings/FaqSettings.vue') },
                    { path: 'lead-cta', name: 'admin.settings.lead_cta', component: () => import('../pages/admin/settings/LeadCtaSettings.vue') },
                ],
            },
            // Themed, auth-guarded 404 for any unknown admin path (inherits the
            // SUPER_ADMIN guard, so unauthenticated users still go to login).
            { path: ':pathMatch(.*)*', name: 'admin.notfound', component: () => import('../pages/admin/NotFoundView.vue') },
        ],
    },
]

// /settings IS the settings screen: it renders Profile in place rather than
// bouncing to a /settings/profile sub-path, so the address bar says what the
// sidebar said. Only the other four sections carry a suffix.
//
// Not everyone can open Profile, though — a cashier holding only pos.provision
// starts at POS devices — so the index route is guarded rather than gated with
// `meta.capability`: the global check below would bounce that cashier to the
// dashboard home before this ever ran. Returning `true` lets Profile render.
//
// It is also a `beforeEnter` and NOT a `redirect` for a second reason: a
// redirect function runs while the URL is being MATCHED, before the global
// `beforeEach` has had a chance to `await auth.fetchUser()`. On a cold load
// that meant asking an empty auth store what the user may open, getting
// "nothing", and falling through to home. `beforeEnter` runs after it.
const settingsIndexGuard = () => {
    const auth = useAuth()
    if (auth.can('settings.view')) return true

    const first = visibleSettingsSections({
        features: auth.restaurant?.features || [],
        can: auth.can,
    })[0]
    // Nothing visible means the sidebar should never have offered Settings;
    // fall back to the dashboard home rather than rendering an empty shell.
    return first ? first.to : { name: 'dashboard.home' }
}

const restaurantRoutes = [
    loginRoute,
    // The restaurant admin lives under /admin: on a restaurant subdomain the
    // bare root ("/") is the public menu (nginx redirects it), so the dashboard
    // needs its own path to stay reachable and refresh-safe.
    {
        path: '/admin',
        component: () => import('../pages/dashboard/DashboardLayout.vue'),
        meta: { portal: 'restaurant' },
        children: [
            // `meta.capability` mirrors the server's `can:<tenant capability>`
            // route middleware: a staff member whose role lacks it is bounced to
            // the dashboard home instead of rendering a page the API will 403.
            // The home view itself is deliberately ungated — it is where everyone
            // lands, and it degrades to whatever the user may actually see.
            { path: '', name: 'dashboard.home', component: () => import('../pages/dashboard/HomeView.vue') },
            { path: 'live', name: 'dashboard.live', component: () => import('../pages/dashboard/LiveBoardView.vue'), meta: { capability: 'live.view' } },
            { path: 'insights', name: 'dashboard.insights', component: () => import('../pages/dashboard/InsightsView.vue'), meta: { capability: 'analytics.view' } },
            { path: 'orders', name: 'dashboard.orders', component: () => import('../pages/dashboard/OrdersView.vue'), meta: { capability: 'orders.view' } },
            { path: 'reviews', name: 'dashboard.reviews', component: () => import('../pages/dashboard/ReviewsView.vue'), meta: { capability: 'reviews.view' } },
            { path: 'reports', redirect: { name: 'dashboard.reports.products' } },
            { path: 'reports/products', name: 'dashboard.reports.products', component: () => import('../pages/dashboard/ProductPerformanceView.vue'), meta: { capability: 'reports.view' } },
            { path: 'reports/areas', name: 'dashboard.reports.areas', component: () => import('../pages/dashboard/AreasComparisonView.vue'), meta: { capability: 'reports.view' } },
            { path: 'customers', name: 'dashboard.customers', component: () => import('../pages/dashboard/CustomersView.vue'), meta: { capability: 'customers.view' } },
            { path: 'customers/:id', name: 'dashboard.customer', component: () => import('../pages/dashboard/CustomerDetailView.vue'), meta: { capability: 'customers.view' } },
            // Branches and dining areas moved into the settings shell (below);
            // their old paths redirect there.
            { path: 'branches', redirect: { name: 'dashboard.branches' } },
            { path: 'branches/create', redirect: { name: 'dashboard.branches.create' } },
            { path: 'branches/:id/edit', redirect: (to) => ({ name: 'dashboard.branches.edit', params: to.params }) },
            { path: 'dining-areas', redirect: { name: 'dashboard.areas' } },
            { path: 'tables', name: 'dashboard.tables', component: () => import('../pages/dashboard/TablesView.vue'), meta: { capability: 'tables.view' } },
            // Purchasing and inventory (CB-09). The server stacks
            // feature:purchasing + can:purchase.manage; as elsewhere, the
            // feature half lives on the sidebar entry and the guard mirrors
            // the capability. No `pos` involvement: purchasing is standalone.
            { path: 'purchasing/suppliers', name: 'dashboard.purchasing.suppliers', component: () => import('../pages/dashboard/purchasing/SuppliersView.vue'), meta: { capability: 'purchase.manage' } },
            { path: 'purchasing/orders', name: 'dashboard.purchasing.orders', component: () => import('../pages/dashboard/purchasing/PurchaseOrdersView.vue'), meta: { capability: 'purchase.manage' } },
            { path: 'purchasing/orders/new', name: 'dashboard.purchasing.orders.create', component: () => import('../pages/dashboard/purchasing/PurchaseOrderForm.vue'), meta: { capability: 'purchase.manage' } },
            { path: 'purchasing/orders/:id', name: 'dashboard.purchasing.order', component: () => import('../pages/dashboard/purchasing/PurchaseOrderView.vue'), meta: { capability: 'purchase.manage' } },
            { path: 'purchasing/orders/:id/edit', name: 'dashboard.purchasing.orders.edit', component: () => import('../pages/dashboard/purchasing/PurchaseOrderForm.vue'), meta: { capability: 'purchase.manage' } },
            { path: 'inventory/stock', name: 'dashboard.inventory.stock', component: () => import('../pages/dashboard/inventory/StockView.vue'), meta: { capability: 'purchase.manage' } },
            { path: 'inventory/stock/:itemId', name: 'dashboard.inventory.movements', component: () => import('../pages/dashboard/inventory/StockMovementsView.vue'), meta: { capability: 'purchase.manage' } },
            { path: 'inventory/items', name: 'dashboard.inventory.items', component: () => import('../pages/dashboard/inventory/StockItemsView.vue'), meta: { capability: 'purchase.manage' } },
            // CB-09 slice c: supplier invoices, payments and the supplier account.
            { path: 'purchasing/invoices', name: 'dashboard.purchasing.invoices', component: () => import('../pages/dashboard/purchasing/SupplierInvoicesView.vue'), meta: { capability: 'purchase.manage' } },
            { path: 'purchasing/invoices/new', name: 'dashboard.purchasing.invoices.create', component: () => import('../pages/dashboard/purchasing/SupplierInvoiceForm.vue'), meta: { capability: 'purchase.manage' } },
            { path: 'purchasing/invoices/:id', name: 'dashboard.purchasing.invoice', component: () => import('../pages/dashboard/purchasing/SupplierInvoiceView.vue'), meta: { capability: 'purchase.manage' } },
            { path: 'purchasing/invoices/:id/edit', name: 'dashboard.purchasing.invoices.edit', component: () => import('../pages/dashboard/purchasing/SupplierInvoiceForm.vue'), meta: { capability: 'purchase.manage' } },
            { path: 'purchasing/payments', name: 'dashboard.purchasing.payments', component: () => import('../pages/dashboard/purchasing/SupplierPaymentsView.vue'), meta: { capability: 'purchase.manage' } },
            { path: 'purchasing/payments/new', name: 'dashboard.purchasing.payments.create', component: () => import('../pages/dashboard/purchasing/SupplierPaymentForm.vue'), meta: { capability: 'purchase.manage' } },
            { path: 'purchasing/payments/:id', name: 'dashboard.purchasing.payment', component: () => import('../pages/dashboard/purchasing/SupplierPaymentView.vue'), meta: { capability: 'purchase.manage' } },
            { path: 'purchasing/suppliers/:id', name: 'dashboard.purchasing.supplier', component: () => import('../pages/dashboard/purchasing/SupplierAccountView.vue'), meta: { capability: 'purchase.manage' } },
            // ------------------------------------------------------ settings
            // One shell over every settings section (see settings.config.js). The route *names* are the ones these
            // pages have always had, so every existing RouterLink keeps
            // resolving; only the URLs moved under /settings, which is what
            // makes each section linkable and the back button meaningful.
            // `meta.capability` still mirrors the server on every child.
            {
                path: 'settings',
                component: () => import('../pages/dashboard/settings/SettingsLayout.vue'),
                children: [
                    // Profile lives at the bare /settings — see settingsIndexGuard.
                    { path: '', name: 'dashboard.profile', component: () => import('../pages/dashboard/ProfileView.vue'), beforeEnter: settingsIndexGuard },
                    // Branches and dining areas: set up once, so they live here.
                    // The server gates branches with can:branches.* (create also
                    // feature:multi_branch) and areas with feature:table_management
                    // + can:tables.*; the feature halves live on the sub-menu entry.
                    { path: 'branches', name: 'dashboard.branches', component: () => import('../pages/dashboard/BranchesView.vue'), meta: { capability: 'branches.view' } },
                    { path: 'branches/create', name: 'dashboard.branches.create', component: () => import('../pages/dashboard/BranchForm.vue'), meta: { capability: 'branches.create' } },
                    { path: 'branches/:id/edit', name: 'dashboard.branches.edit', component: () => import('../pages/dashboard/BranchForm.vue'), meta: { capability: 'branches.update' } },
                    { path: 'dining-areas', name: 'dashboard.areas', component: () => import('../pages/dashboard/DiningAreasView.vue'), meta: { capability: 'tables.view' } },
                    // POS terminal provisioning (POS-BE-023). The server stacks
                    // feature:pos on top of can:pos.provision; client-side the
                    // feature gate lives on the settings sub-menu entry
                    // (feature: 'pos'), same as Orders and Branches — the route
                    // guard mirrors only the capability.
                    { path: 'devices', name: 'dashboard.pos.terminals', component: () => import('../pages/dashboard/PosTerminalsView.vue'), meta: { capability: 'pos.provision' } },
                    // Money configuration (POS-BE-013). The server gates it with
                    // feature:pos + can:settings.view; the feature half lives on
                    // the sub-menu entry, so the guard mirrors the capability.
                    { path: 'taxes', name: 'dashboard.pos.money', component: () => import('../pages/dashboard/PosMoneyView.vue'), meta: { capability: 'settings.view' } },
                    // Payment methods (tender types) as their own settings
                    // section, matching the "طرق الدفع والحسابات" design.
                    // Same server gate as taxes: feature:pos + can:settings.view.
                    { path: 'payment-methods', name: 'dashboard.pos.payment_methods', component: () => import('../pages/dashboard/settings/PaymentMethodsView.vue'), meta: { capability: 'settings.view' } },
                    // The receipt profile (A3 / CB-08) — who the slip says sold
                    // the food, per branch. Same server gate as the money
                    // config (feature:pos + can:settings.view, settings.update
                    // to write), so the guard mirrors the capability and the
                    // feature half lives on the sub-menu entry.
                    { path: 'receipt', name: 'dashboard.pos.receipt', component: () => import('../pages/dashboard/PosReceiptView.vue'), meta: { capability: 'settings.view' } },
                    // Units are what a business counts and buys in — set once
                    // and then referenced by every stock item and order line,
                    // which is a setting, not a day's work. Same server gate as
                    // the rest of purchasing (feature:purchasing +
                    // can:purchase.manage); the feature half lives on the
                    // sub-menu entry, so the guard mirrors the capability.
                    { path: 'units', name: 'dashboard.inventory.units', component: () => import('../pages/dashboard/inventory/UnitsView.vue'), meta: { capability: 'purchase.manage' } },
                ],
            },
            // ---------------------------------------------------------- team
            // Staff and roles have their own sidebar section. They reuse the
            // settings card styles but not its sub-menu: the sidebar already
            // lists both pages. Route names are unchanged.
            {
                path: 'team',
                component: () => import('../pages/dashboard/settings/TeamLayout.vue'),
                meta: { crumbKey: 'nav.section_team' },
                children: [
                    { path: '', redirect: { name: 'dashboard.staff' } },
                    { path: 'users', name: 'dashboard.staff', component: () => import('../pages/dashboard/StaffView.vue'), meta: { capability: 'staff.view' } },
                    { path: 'users/create', name: 'dashboard.staff.create', component: () => import('../pages/dashboard/StaffForm.vue'), meta: { capability: 'staff.create' } },
                    { path: 'users/:id/edit', name: 'dashboard.staff.edit', component: () => import('../pages/dashboard/StaffForm.vue'), meta: { capability: 'staff.update' } },
                    { path: 'roles', name: 'dashboard.roles', component: () => import('../pages/dashboard/RolesView.vue'), meta: { capability: 'staff.view' } },
                    { path: 'roles/create', name: 'dashboard.roles.create', component: () => import('../pages/dashboard/RoleForm.vue'), meta: { capability: 'staff.create' } },
                    { path: 'roles/:id/edit', name: 'dashboard.roles.edit', component: () => import('../pages/dashboard/RoleForm.vue'), meta: { capability: 'staff.update' } },
                ],
            },
            // Where staff and roles lived inside the settings shell.
            { path: 'settings/users', redirect: { name: 'dashboard.staff' } },
            { path: 'settings/users/create', redirect: { name: 'dashboard.staff.create' } },
            { path: 'settings/users/:id/edit', redirect: (to) => ({ name: 'dashboard.staff.edit', params: to.params }) },
            { path: 'settings/roles', redirect: { name: 'dashboard.roles' } },
            { path: 'settings/roles/create', redirect: { name: 'dashboard.roles.create' } },
            { path: 'settings/roles/:id/edit', redirect: (to) => ({ name: 'dashboard.roles.edit', params: to.params }) },
            { path: 'settings/profile', redirect: { name: 'dashboard.profile' } },
            // Units lived under Inventory until they moved into Settings.
            { path: 'inventory/units', redirect: { name: 'dashboard.inventory.units' } },
            // The paths these pages used before the settings shell existed.
            // Kept as redirects so bookmarks and anything already printed or
            // pasted still land in the right place.
            { path: 'profile', redirect: { name: 'dashboard.profile' } },
            { path: 'staff', redirect: { name: 'dashboard.staff' } },
            { path: 'staff/create', redirect: { name: 'dashboard.staff.create' } },
            { path: 'staff/:id/edit', redirect: (to) => ({ name: 'dashboard.staff.edit', params: to.params }) },
            { path: 'roles', redirect: { name: 'dashboard.roles' } },
            { path: 'roles/create', redirect: { name: 'dashboard.roles.create' } },
            { path: 'roles/:id/edit', redirect: (to) => ({ name: 'dashboard.roles.edit', params: to.params }) },
            { path: 'pos/terminals', redirect: { name: 'dashboard.pos.terminals' } },
            { path: 'pos/money', redirect: { name: 'dashboard.pos.money' } },
            { path: 'categories', name: 'dashboard.categories', component: () => import('../pages/dashboard/CategoriesView.vue'), meta: { capability: 'menu.view' } },
            { path: 'items', name: 'dashboard.items', component: () => import('../pages/dashboard/ItemsView.vue'), meta: { capability: 'menu.view' } },
            { path: 'extras', name: 'dashboard.extras', component: () => import('../pages/dashboard/ExtrasView.vue'), meta: { capability: 'menu.view' } },
            { path: 'items/create', name: 'dashboard.items.create', component: () => import('../pages/dashboard/ItemForm.vue'), meta: { capability: 'menu.create' } },
            { path: 'items/:id/edit', name: 'dashboard.items.edit', component: () => import('../pages/dashboard/ItemForm.vue'), meta: { capability: 'menu.update' } },
        ],
    },
    { path: '/:pathMatch(.*)*', redirect: '/admin' },
]

const router = createRouter({
    history: createWebHistory(import.meta.env.BASE_URL),
    routes: isSuperAdminHost ? superAdminRoutes : restaurantRoutes,
})

// Bounce the browser to the subdomain that matches the signed-in user.
// Restaurant subdomains serve the public menu at their root ("/"), so the
// restaurant dashboard lives at /admin.
export function redirectToCorrectHost(auth) {
    if (auth.isPlatformUser) {
        window.location.href = superAdminUrl('/')
    } else if (auth.restaurant?.slug) {
        window.location.href = restaurantUrl(auth.restaurant.slug, '/admin')
    } else {
        window.location.href = superAdminUrl('/')
    }
}

// Is the signed-in user the right kind for THIS host? Returns the in-portal home
// route, or null if they belong on a different subdomain.
export function inPortalHome(auth) {
    if (isSuperAdminHost) {
        return auth.isPlatformUser ? { name: 'admin.dashboard' } : null
    }
    if (auth.isTenantUser && auth.restaurant?.slug === restaurantSlug) {
        return { name: 'dashboard.home' }
    }
    return null
}

router.beforeEach(async (to) => {
    const auth = useAuth()
    if (!auth.loaded) await auth.fetchUser()

    if (to.meta.guest && auth.isAuthenticated) {
        const home = inPortalHome(auth)
        if (home) return home
        redirectToCorrectHost(auth)
        return false
    }

    if (to.meta.portal) {
        if (!auth.isAuthenticated) return { name: 'login', query: { redirect: to.fullPath } }

        // Wrong portal kind for this host, or right kind but wrong restaurant
        // subdomain → send the browser to the correct subdomain.
        const home = inPortalHome(auth)
        if (home === null) {
            redirectToCorrectHost(auth)
            return false
        }

        // In the right portal but lacking the capability this section needs →
        // bounce to the portal home (mirrors the server's 403). The API is still
        // the authority; this just keeps the UI from rendering a dead page.
        if (to.meta.capability && !auth.can(to.meta.capability)) {
            return home
        }
    }

    return true
})

// GA4 counts the first load automatically; report each SPA navigation by hand.
// Route names are logged instead of raw paths to keep ids (tokens, slugs) out
// of analytics.
router.afterEach((to) => {
    trackPageView(to.name ? `/${String(to.name)}` : to.path)
})

export default router
