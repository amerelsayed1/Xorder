import { defineStore } from 'pinia'
import api, { setToken, clearToken, getToken } from './api'

// Every platform-level role (lives on the admin subdomain, restaurant_id null).
export const PLATFORM_ROLES = ['SUPER_ADMIN', 'ADMIN', 'MODERATOR', 'SALES', 'SUPPORT']

// Role → capability map. MUST mirror RoleEnum::capabilities() on the backend
// (apps/api/app/Enums/RoleEnum.php). This copy is UX-only — it hides sections
// the server would 403 anyway; the API gates remain authoritative. SUPER_ADMIN
// is intentionally absent: it is granted everything via `can()` below.
const ROLE_CAPS = {
    ADMIN: [
        'restaurants.view', 'restaurants.manage', 'plans.manage', 'subscriptions.manage',
        'leads.manage', 'landing.manage', 'audit.view', 'insights.view',
    ],
    MODERATOR: ['restaurants.view', 'restaurants.manage', 'landing.manage', 'insights.view'],
    SALES: ['restaurants.view', 'plans.manage', 'subscriptions.manage', 'leads.manage', 'insights.view'],
    SUPPORT: ['restaurants.view', 'audit.view', 'insights.view'],
}

export const useAuth = defineStore('auth', {
    state: () => ({
        user: null,
        loaded: false,
    }),
    getters: {
        isAuthenticated: (s) => !!s.user,
        isSuperAdmin: (s) => s.user?.role === 'SUPER_ADMIN',
        isRestaurantAdmin: (s) => s.user?.role === 'RESTAURANT_ADMIN',
        // Any platform staff role — the set that belongs on the admin portal.
        isPlatformUser: (s) => PLATFORM_ROLES.includes(s.user?.role),
        platformRole: (s) => s.user?.role ?? null,
        // Whether the signed-in user holds an admin-panel capability. Mirrors the
        // server's `can:<capability>` route middleware so the UI hides exactly
        // what the API would reject with a 403.
        can: (s) => (capability) =>
            s.user?.role === 'SUPER_ADMIN' || (ROLE_CAPS[s.user?.role] || []).includes(capability),
        restaurant: (s) => s.user?.restaurant ?? null,
        // Whether the current restaurant holds a plan-granted capability flag.
        // Mirrors the server's `feature:<key>` route middleware so the UI hides
        // exactly what the API would reject with a 403.
        hasFeature: (s) => (key) => (s.user?.restaurant?.features || []).includes(key),
        // The dashboard is read-only when the restaurant can't be written to —
        // mirrors the server's EnsureSubscriptionAllowsWrites middleware so the
        // UI hides/disables exactly what the API would reject with a 403.
        isReadOnly: (s) => {
            const r = s.user?.restaurant
            if (!r) return false
            return ['SUSPENDED', 'ARCHIVED'].includes(r.status)
                || ['EXPIRED', 'SUSPENDED'].includes(r.subscription_status)
        },
    },
    actions: {
        async login(credentials) {
            const { data } = await api.post('api/auth/login', credentials)
            setToken(data.token)
            this.user = data.data
            return this.user
        },
        async fetchUser() {
            // No token → skip the round-trip; the user is unauthenticated.
            if (!getToken()) {
                this.user = null
                this.loaded = true
                return
            }
            try {
                const { data } = await api.get('api/auth/me')
                this.user = data.data
            } catch {
                this.user = null
                clearToken()
            } finally {
                this.loaded = true
            }
        },
        async logout() {
            try {
                await api.post('api/auth/logout')
            } finally {
                this.user = null
                clearToken()
            }
        },
        // Self-service password change. The server invalidates every prior token
        // and returns a fresh one for this device, so swap the stored token to
        // keep the current session alive.
        async changePassword(payload) {
            const { data } = await api.post('api/auth/change-password', payload)
            if (data.token) setToken(data.token)
            return data
        },
        homeRoute() {
            if (this.isPlatformUser) return { name: 'admin.dashboard' }
            if (this.isRestaurantAdmin) return { name: 'dashboard.home' }
            return { name: 'login' }
        },
    },
})
