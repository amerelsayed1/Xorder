import { createRouter, createWebHistory } from 'vue-router'
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
        meta: { role: 'SUPER_ADMIN' },
        children: [
            { path: '', name: 'admin.dashboard', component: () => import('../pages/admin/DashboardView.vue') },
            { path: 'insights', name: 'admin.insights', component: () => import('../pages/admin/InsightsView.vue') },
            { path: 'restaurants', name: 'admin.restaurants', component: () => import('../pages/admin/RestaurantsList.vue') },
            { path: 'restaurants/create', name: 'admin.restaurants.create', component: () => import('../pages/admin/RestaurantForm.vue') },
            { path: 'restaurants/:id', name: 'admin.restaurants.show', component: () => import('../pages/admin/RestaurantDetails.vue') },
            { path: 'restaurants/:id/edit', name: 'admin.restaurants.edit', component: () => import('../pages/admin/RestaurantForm.vue') },
            { path: 'plans', name: 'admin.plans', component: () => import('../pages/admin/PlansList.vue') },
            { path: 'plans/create', name: 'admin.plans.create', component: () => import('../pages/admin/PlanForm.vue') },
            { path: 'plans/:id/edit', name: 'admin.plans.edit', component: () => import('../pages/admin/PlanForm.vue') },
            { path: 'landing', name: 'admin.landing', component: () => import('../pages/admin/LandingContentView.vue') },
            { path: 'leads', name: 'admin.leads', component: () => import('../pages/admin/LeadsView.vue') },
            { path: 'menu-parser', name: 'admin.menu-parser', component: () => import('../pages/admin/MenuParserView.vue') },
        ],
    },
    { path: '/:pathMatch(.*)*', redirect: '/' },
]

const restaurantRoutes = [
    loginRoute,
    {
        path: '/',
        component: () => import('../pages/dashboard/DashboardLayout.vue'),
        meta: { role: 'RESTAURANT_ADMIN' },
        children: [
            { path: '', name: 'dashboard.home', component: () => import('../pages/dashboard/HomeView.vue') },
            { path: 'insights', name: 'dashboard.insights', component: () => import('../pages/dashboard/InsightsView.vue') },
            { path: 'orders', name: 'dashboard.orders', component: () => import('../pages/dashboard/OrdersView.vue') },
            { path: 'branches', name: 'dashboard.branches', component: () => import('../pages/dashboard/BranchesView.vue') },
            { path: 'profile', name: 'dashboard.profile', component: () => import('../pages/dashboard/ProfileView.vue') },
            { path: 'categories', name: 'dashboard.categories', component: () => import('../pages/dashboard/CategoriesView.vue') },
            { path: 'items', name: 'dashboard.items', component: () => import('../pages/dashboard/ItemsView.vue') },
            { path: 'combos', name: 'dashboard.combos', component: () => import('../pages/dashboard/CombosView.vue') },
            { path: 'qr', name: 'dashboard.qr', component: () => import('../pages/dashboard/QrView.vue') },
        ],
    },
    { path: '/:pathMatch(.*)*', redirect: '/' },
]

const router = createRouter({
    history: createWebHistory(import.meta.env.BASE_URL),
    routes: isSuperAdminHost ? superAdminRoutes : restaurantRoutes,
})

// Bounce the browser to the subdomain that matches the signed-in user.
function redirectToCorrectHost(auth) {
    if (auth.isSuperAdmin) {
        window.location.href = superAdminUrl('/')
    } else if (auth.restaurant?.slug) {
        window.location.href = restaurantUrl(auth.restaurant.slug, '/')
    } else {
        window.location.href = superAdminUrl('/')
    }
}

// Is the signed-in user the right kind for THIS host? Returns the in-portal home
// route, or null if they belong on a different subdomain.
function inPortalHome(auth) {
    if (isSuperAdminHost) {
        return auth.isSuperAdmin ? { name: 'admin.dashboard' } : null
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

    if (to.meta.role) {
        if (!auth.isAuthenticated) return { name: 'login', query: { redirect: to.fullPath } }

        // Wrong portal kind for this host, or right kind but wrong restaurant
        // subdomain → send the browser to the correct subdomain.
        if (auth.user.role !== to.meta.role || inPortalHome(auth) === null) {
            redirectToCorrectHost(auth)
            return false
        }
    }

    return true
})

export default router
