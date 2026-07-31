<script setup>
import { ref, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute, useRouter } from 'vue-router'
import api from '@xorder/api-client/api.js'
import { useAuth } from '@xorder/api-client/auth.js'
import { currencyLabel } from '../../lib/currency.js'
import Skeleton from '@xorder/ui/Skeleton.vue'
import ErrorState from '@xorder/ui/ErrorState.vue'
import Icon from '@xorder/ui/Icon.vue'
import { withMinDuration } from '../../lib/minLoading.js'

const { t, locale } = useI18n()
const route = useRoute()
const router = useRouter()
const auth = useAuth()
const cur = () => currencyLabel(auth.restaurant?.currency, locale.value, auth.restaurant?.currency_symbol)

const loading = ref(true)
const error = ref(false)
const customer = ref(null)
const orders = ref([])

async function load() {
    loading.value = true
    error.value = false
    try {
        const { data } = await withMinDuration(api.get(`api/dashboard/customers/${route.params.id}`))
        customer.value = data.data
        orders.value = data.recent_orders || []
    } catch (err) {
        error.value = true
    } finally {
        loading.value = false
    }
}
onMounted(load)

const totalSpent = () => orders.value.reduce((s, o) => s + Number(o.total || 0), 0).toFixed(2)
const fmtTime = (iso) => iso ? new Date(iso).toLocaleString(locale.value === 'ar' ? 'ar-EG' : 'en-GB', { dateStyle: 'medium', timeStyle: 'short' }) : ''
const orderTypeLabel = (v) => v ? t('order_type.' + v) : ''
const statusLabel = (s) => t('orders.status.' + s)
</script>

<template>
    <div class="space-y-5">
        <button class="flex items-center gap-1.5 text-sm" style="color:var(--muted)" @click="router.push({ name: 'dashboard.customers' })">
            <Icon name="chevronDown" :size="16" class="rotate-90 rtl:-rotate-90" />{{ t('nav.customers') }}
        </button>

        <!-- Loading -->
        <div v-if="loading" class="space-y-4">
            <div class="card" style="padding:1.25rem">
                <div class="flex items-center gap-3">
                    <Skeleton w="56px" h="56px" rounded="50%" />
                    <div class="flex-1 space-y-2"><Skeleton w="180px" h="18px" /><Skeleton w="120px" h="13px" /></div>
                </div>
            </div>
            <div class="card" style="padding:1.25rem"><Skeleton w="140px" h="16px" /><div class="mt-3 space-y-2"><Skeleton w="100%" h="44px" rounded="12px" /><Skeleton w="100%" h="44px" rounded="12px" /></div></div>
            <div class="card" style="padding:1.25rem"><Skeleton w="140px" h="16px" /><div class="mt-3 space-y-2"><Skeleton w="100%" h="40px" /><Skeleton w="100%" h="40px" /></div></div>
        </div>

        <ErrorState v-else-if="error" @retry="load" />

        <template v-else-if="customer">
            <!-- Header + stats -->
            <div class="card" style="padding:1.25rem">
                <div class="flex items-start justify-between gap-4 flex-wrap">
                    <div class="flex items-center gap-3">
                        <div class="h-14 w-14 rounded-full grid place-items-center flex-shrink-0 font-bold text-lg" style="background:var(--accent-soft);color:var(--accent)">
                            {{ (customer.name || '؟').charAt(0).toUpperCase() }}
                        </div>
                        <div>
                            <h1 class="page-title" style="margin:0">{{ customer.name || t('customer.no_name') }}</h1>
                            <div class="text-sm mt-0.5" style="color:var(--muted)" dir="ltr">{{ customer.phone }}</div>
                            <div v-if="customer.email" class="text-xs" style="color:var(--muted)" dir="ltr">{{ customer.email }}</div>
                        </div>
                    </div>
                    <div class="flex gap-5">
                        <div><div class="text-2xl font-bold" style="color:var(--ink)">{{ customer.orders_count ?? orders.length }}</div><div class="text-xs" style="color:var(--muted)">{{ t('customer.orders_label') }}</div></div>
                        <div><div class="text-2xl font-bold" style="color:var(--ink)">{{ totalSpent() }} <span class="text-sm">{{ cur() }}</span></div><div class="text-xs" style="color:var(--muted)">{{ t('customer.total_spent') }}</div></div>
                    </div>
                </div>
                <p v-if="customer.note" class="text-sm mt-3" style="color:var(--muted)">{{ customer.note }}</p>
            </div>

            <!-- Addresses -->
            <div class="card" style="padding:1.25rem">
                <div class="label mb-3">{{ t('customer.addresses') }}</div>
                <p v-if="!customer.addresses?.length" class="text-sm" style="color:var(--muted)">{{ t('customer.no_addresses') }}</p>
                <ul v-else class="grid gap-2" style="grid-template-columns:repeat(auto-fill,minmax(240px,1fr))">
                    <li v-for="a in customer.addresses" :key="a.id" class="rounded-xl p-3 text-sm" style="background:var(--page);border:1px solid var(--line)">
                        <div class="flex items-center gap-2 mb-1">
                            <span v-if="a.label" class="chip-sm">{{ a.label }}</span>
                            <span v-if="a.is_default" class="chip-sm" style="background:var(--accent-soft);color:var(--accent)">{{ t('customer.default') }}</span>
                        </div>
                        <div style="color:var(--ink)">{{ a.address }}</div>
                        <div v-if="a.note" class="text-xs mt-1" style="color:var(--muted)">{{ a.note }}</div>
                    </li>
                </ul>
            </div>

            <!-- Order history -->
            <div class="card overflow-hidden">
                <div class="label px-5 pt-4 pb-2">{{ t('customer.recent_orders') }}</div>
                <p v-if="!orders.length" class="px-5 pb-5 text-sm" style="color:var(--muted)">{{ t('orders.none') }}</p>
                <ul v-else>
                    <li v-for="o in orders" :key="o.id" class="flex items-center justify-between gap-3 px-5 py-3 border-t" style="border-color:var(--line)">
                        <div>
                            <span class="font-medium" style="color:var(--ink)">{{ o.code }}</span>
                            <span v-if="o.order_type" class="text-xs" style="color:var(--muted)"> · {{ orderTypeLabel(o.order_type) }}</span>
                            <div class="text-xs" style="color:var(--muted)">{{ fmtTime(o.created_at) }}</div>
                            <div v-if="o.address" class="text-xs" style="color:var(--muted)">{{ o.address }}</div>
                        </div>
                        <div class="text-end">
                            <div class="font-medium" style="color:var(--ink)">{{ o.total }} {{ cur() }}</div>
                            <div class="text-xs" style="color:var(--muted)">{{ statusLabel(o.status) }}</div>
                        </div>
                    </li>
                </ul>
            </div>
        </template>

        <div v-else class="card p-8 text-center" style="color:var(--muted)">{{ t('common.none') }}</div>
    </div>
</template>

<style scoped>
.chip-sm { display: inline-flex; align-items: center; padding: 2px 10px; border-radius: 20px;
    border: 1px solid var(--line); background: var(--card); color: var(--body); font-size: 12px; font-weight: 600; }
</style>
