import { defineStore } from 'pinia'
import api, { setToken, clearToken, getToken } from './api'

export const useAuth = defineStore('auth', {
    state: () => ({
        user: null,
        loaded: false,
    }),
    getters: {
        isAuthenticated: (s) => !!s.user,
        isSuperAdmin: (s) => s.user?.role === 'SUPER_ADMIN',
        isRestaurantAdmin: (s) => s.user?.role === 'RESTAURANT_ADMIN',
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
        homeRoute() {
            if (this.isSuperAdmin) return { name: 'admin.dashboard' }
            if (this.isRestaurantAdmin) return { name: 'dashboard.home' }
            return { name: 'login' }
        },
    },
})
