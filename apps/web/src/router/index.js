import { createRouter, createWebHistory } from 'vue-router'
import { trackPageView } from '@xorder/analytics'
import { useAuth } from '@xorder/api-client/auth.js'
import { isSuperAdminHost, restaurantSlug, superAdminUrl, restaurantUrl } from '../lib/host.js'

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
            { path: '', name: 'dashboard.home', component: () => import('../pages/dashboard/HomeView.vue') },
            { path: 'live', name: 'dashboard.live', component: () => import('../pages/dashboard/LiveBoardView.vue') },
            { path: 'insights', name: 'dashboard.insights', component: () => import('../pages/dashboard/InsightsView.vue') },
            { path: 'orders', name: 'dashboard.orders', component: () => import('../pages/dashboard/OrdersView.vue') },
            { path: 'reviews', name: 'dashboard.reviews', component: () => import('../pages/dashboard/ReviewsView.vue') },
            { path: 'reports', redirect: { name: 'dashboard.reports.products' } },
            { path: 'reports/products', name: 'dashboard.reports.products', component: () => import('../pages/dashboard/ProductPerformanceView.vue') },
            { path: 'reports/areas', name: 'dashboard.reports.areas', component: () => import('../pages/dashboard/AreasComparisonView.vue') },
            { path: 'customers', name: 'dashboard.customers', component: () => import('../pages/dashboard/CustomersView.vue') },
            { path: 'customers/:id', name: 'dashboard.customer', component: () => import('../pages/dashboard/CustomerDetailView.vue') },
            { path: 'branches', name: 'dashboard.branches', component: () => import('../pages/dashboard/BranchesView.vue') },
            { path: 'dining-areas', name: 'dashboard.areas', component: () => import('../pages/dashboard/DiningAreasView.vue') },
            { path: 'tables', name: 'dashboard.tables', component: () => import('../pages/dashboard/TablesView.vue') },
            { path: 'profile', name: 'dashboard.profile', component: () => import('../pages/dashboard/ProfileView.vue') },
            { path: 'categories', name: 'dashboard.categories', component: () => import('../pages/dashboard/CategoriesView.vue') },
            { path: 'items', name: 'dashboard.items', component: () => import('../pages/dashboard/ItemsView.vue') },
            { path: 'items/create', name: 'dashboard.items.create', component: () => import('../pages/dashboard/ItemForm.vue') },
            { path: 'items/:id/edit', name: 'dashboard.items.edit', component: () => import('../pages/dashboard/ItemForm.vue') },
            { path: 'qr', name: 'dashboard.qr', component: () => import('../pages/dashboard/QrView.vue') },
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
    if (auth.isRestaurantAdmin && auth.restaurant?.slug === restaurantSlug) {
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
