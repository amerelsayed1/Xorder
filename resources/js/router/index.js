import { createRouter, createWebHistory } from 'vue-router'
import { useAuth } from '../stores/auth'

const routes = [
    { path: '/', redirect: '/login' },
    { path: '/login', name: 'login', component: () => import('../pages/LoginView.vue'), meta: { guest: true } },

    // Super Admin portal
    {
        path: '/admin',
        component: () => import('../pages/admin/AdminLayout.vue'),
        meta: { role: 'SUPER_ADMIN' },
        children: [
            { path: '', name: 'admin.dashboard', component: () => import('../pages/admin/DashboardView.vue') },
            { path: 'insights', name: 'admin.insights', component: () => import('../pages/admin/InsightsView.vue') },
            { path: 'restaurants', name: 'admin.restaurants', component: () => import('../pages/admin/RestaurantsList.vue') },
            { path: 'restaurants/create', name: 'admin.restaurants.create', component: () => import('../pages/admin/RestaurantForm.vue') },
            { path: 'restaurants/:id', name: 'admin.restaurants.show', component: () => import('../pages/admin/RestaurantDetails.vue') },
            { path: 'restaurants/:id/edit', name: 'admin.restaurants.edit', component: () => import('../pages/admin/RestaurantForm.vue') },
        ],
    },

    // Restaurant dashboard
    {
        path: '/dashboard',
        component: () => import('../pages/dashboard/DashboardLayout.vue'),
        meta: { role: 'RESTAURANT_ADMIN' },
        children: [
            { path: '', name: 'dashboard.home', component: () => import('../pages/dashboard/HomeView.vue') },
            { path: 'insights', name: 'dashboard.insights', component: () => import('../pages/dashboard/InsightsView.vue') },
            { path: 'profile', name: 'dashboard.profile', component: () => import('../pages/dashboard/ProfileView.vue') },
            { path: 'categories', name: 'dashboard.categories', component: () => import('../pages/dashboard/CategoriesView.vue') },
            { path: 'items', name: 'dashboard.items', component: () => import('../pages/dashboard/ItemsView.vue') },
            { path: 'qr', name: 'dashboard.qr', component: () => import('../pages/dashboard/QrView.vue') },
        ],
    },

    { path: '/:pathMatch(.*)*', redirect: '/login' },
]

const router = createRouter({
    history: createWebHistory(),
    routes,
})

router.beforeEach(async (to) => {
    const auth = useAuth()
    if (!auth.loaded) await auth.fetchUser()

    if (to.meta.guest && auth.isAuthenticated) {
        return auth.homeRoute()
    }

    if (to.meta.role) {
        if (!auth.isAuthenticated) return { name: 'login', query: { redirect: to.fullPath } }
        if (auth.user.role !== to.meta.role) return auth.homeRoute()
    }

    return true
})

export default router
