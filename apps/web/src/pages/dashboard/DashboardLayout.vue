<script setup>
import { computed, onMounted, onUnmounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import SakaiLayout from '@xorder/ui/SakaiLayout.vue'
import api from '@xorder/api-client/api.js'
import { useAuth } from '@xorder/api-client/auth.js'
import { localizedInitial, pickLocalized } from '@xorder/ui/localize.js'

const auth = useAuth()
const { t, locale } = useI18n()
const r = computed(() => auth.restaurant)
const title = computed(() => pickLocalized(r.value, 'name', locale.value) || t('admin.restaurant'))
const mark = computed(() => localizedInitial(r.value, 'name', locale.value, 'R'))
const logo = computed(() => r.value?.logo_url || '')
const role = computed(() => t('roles.restaurant_admin'))

// New-orders counter shown as a badge on the Orders nav entry, refreshed
// every 60s while the dashboard is open.
const newOrders = ref(0)
let pollTimer
async function loadNewCount() {
    try {
        const { data } = await api.get('api/dashboard/orders/new-count')
        newOrders.value = data.data?.new_orders ?? 0
    } catch (err) { /* keep the last known count */ }
}
onMounted(() => {
    loadNewCount()
    pollTimer = setInterval(loadNewCount, 60_000)
})
onUnmounted(() => clearInterval(pollTimer))

const nav = computed(() => [
    { to: { name: 'dashboard.home' }, labelKey: 'nav.dashboard', icon: 'pi pi-th-large', end: true },
    { to: { name: 'dashboard.orders' }, labelKey: 'nav.orders', icon: 'pi pi-shopping-bag', badge: newOrders.value },
    { to: { name: 'dashboard.insights' }, labelKey: 'nav.insights', icon: 'pi pi-chart-bar' },
    { to: { name: 'dashboard.items' }, labelKey: 'nav.items', icon: 'pi pi-list' },
    { to: { name: 'dashboard.categories' }, labelKey: 'nav.categories', icon: 'pi pi-tags' },
    { to: { name: 'dashboard.combos' }, labelKey: 'nav.combos', icon: 'pi pi-gift' },
    { to: { name: 'dashboard.qr' }, labelKey: 'nav.qr', icon: 'pi pi-qrcode' },
    { to: { name: 'dashboard.branches' }, labelKey: 'nav.branches', icon: 'pi pi-map-marker' },
    { to: { name: 'dashboard.profile' }, labelKey: 'nav.profile', icon: 'pi pi-cog' },
])
</script>

<template>
    <SakaiLayout :title="title" :role="role" :mark="mark" :logo="logo" :nav="nav" />
</template>
