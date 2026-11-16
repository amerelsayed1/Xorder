import { beforeEach, describe, expect, it } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'
import { useAuth } from './auth.js'

const as = (user) => {
    const auth = useAuth()
    auth.user = user
    return auth
}

beforeEach(() => setActivePinia(createPinia()))

describe('roles', () => {
    it('classifies platform vs tenant accounts', () => {
        expect(as({ role: 'SALES' }).isPlatformUser).toBe(true)
        expect(as({ role: 'SALES' }).isTenantUser).toBe(false)
        expect(as({ role: 'RESTAURANT_STAFF' }).isTenantUser).toBe(true)
        expect(as({ role: 'RESTAURANT_ADMIN' }).isRestaurantAdmin).toBe(true)
        expect(as({ role: 'RESTAURANT_STAFF' }).isRestaurantAdmin).toBe(false)
    })
    it('is unauthenticated with no user', () => {
        const auth = as(null)
        expect(auth.isAuthenticated).toBe(false)
        expect(auth.isPlatformUser).toBe(false)
        expect(auth.isTenantUser).toBe(false)
    })
})

describe('can()', () => {
    it('gives SUPER_ADMIN everything', () => {
        expect(as({ role: 'SUPER_ADMIN' }).can('anything.at.all')).toBe(true)
    })
    it('resolves platform roles from the static matrix, and no further', () => {
        expect(as({ role: 'SUPPORT' }).can('audit.view')).toBe(true)
        expect(as({ role: 'SUPPORT' }).can('restaurants.manage')).toBe(false)
        expect(as({ role: 'MODERATOR' }).can('plans.manage')).toBe(false)
    })
    it('resolves tenant staff only from the capabilities the server sent', () => {
        const auth = as({ role: 'RESTAURANT_STAFF', capabilities: ['orders.view'] })
        expect(auth.can('orders.view')).toBe(true)
        expect(auth.can('menu.delete')).toBe(false)
    })
    it('does not let a tenant account use platform capabilities, or the reverse', () => {
        expect(as({ role: 'RESTAURANT_ADMIN', capabilities: [] }).can('restaurants.manage')).toBe(false)
        expect(as({ role: 'SALES', capabilities: ['orders.view'] }).can('orders.view')).toBe(false)
    })
    it('denies an unknown role and a missing capabilities list', () => {
        expect(as({ role: 'MYSTERY' }).can('restaurants.view')).toBe(false)
        expect(as({ role: 'RESTAURANT_STAFF' }).can('orders.view')).toBe(false)
    })
})

describe('isReadOnly', () => {
    it.each([
        [{ status: 'SUSPENDED' }, true],
        [{ status: 'ARCHIVED' }, true],
        [{ subscription_status: 'EXPIRED' }, true],
        [{ subscription_status: 'SUSPENDED' }, true],
        [{ status: 'ACTIVE', subscription_status: 'ACTIVE' }, false],
    ])('%j -> %s', (restaurant, expected) => {
        expect(as({ role: 'RESTAURANT_ADMIN', restaurant }).isReadOnly).toBe(expected)
    })
    it('is false with no restaurant (platform user)', () => {
        expect(as({ role: 'ADMIN' }).isReadOnly).toBe(false)
    })
})

describe('hasFeature / homeRoute', () => {
    it('checks the plan feature list', () => {
        const auth = as({ role: 'RESTAURANT_ADMIN', restaurant: { features: ['pos'] } })
        expect(auth.hasFeature('pos')).toBe(true)
        expect(auth.hasFeature('whatsapp_ordering')).toBe(false)
    })
    it('routes each kind of account to its own home', () => {
        expect(as({ role: 'ADMIN' }).homeRoute()).toEqual({ name: 'admin.dashboard' })
        expect(as({ role: 'RESTAURANT_STAFF' }).homeRoute()).toEqual({ name: 'dashboard.home' })
        expect(as(null).homeRoute()).toEqual({ name: 'login' })
    })
})
