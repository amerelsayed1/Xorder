import { defineStore } from 'pinia'
import api, { ensureCsrf } from '../lib/api'

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
    },
    actions: {
        async login(credentials) {
            await ensureCsrf()
            const { data } = await api.post('api/auth/login', credentials)
            this.user = data.data
            return this.user
        },
        async fetchUser() {
            try {
                const { data } = await api.get('api/auth/me')
                this.user = data.data
            } catch {
                this.user = null
            } finally {
                this.loaded = true
            }
        },
        async logout() {
            try {
                await api.post('api/auth/logout')
            } finally {
                this.user = null
            }
        },
        homeRoute() {
            if (this.isSuperAdmin) return { name: 'admin.dashboard' }
            if (this.isRestaurantAdmin) return { name: 'dashboard.home' }
            return { name: 'login' }
        },
    },
})
