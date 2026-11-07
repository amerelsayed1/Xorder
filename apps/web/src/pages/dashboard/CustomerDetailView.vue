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
const badgeClass = { NEW: 'badge-amber', COMPLETED: 'badge-green', CANCELLED: 'badge-red' }
</script>

<template>
    <div class="space-y-5">
        <button type="button" class="back-link" @click="router.push({ name: 'dashboard.customers' })">
            <Icon name="chevronDown" :size="16" class="rotate-90 rtl:-rotate-90" />{{ t('nav.customers') }}
        </button>

        <!-- Loading skeleton: same blocks as the loaded page -->
        <div v-if="loading" class="space-y-5" aria-busy="true">
            <div class="card p-5">
                <div class="flex items-center gap-4">
                    <Skeleton w="64px" h="64px" rounded="50%" />
                    <div class="flex-1 space-y-2"><Skeleton w="180px" h="20px" /><Skeleton w="120px" h="14px" /></div>
                </div>
            </div>
            <div class="card p-5"><Skeleton w="140px" h="18px" /><div class="mt-3 space-y-2"><Skeleton w="100%" h="56px" rounded="12px" /><Skeleton w="100%" h="56px" rounded="12px" /><Skeleton w="100%" h="56px" rounded="12px" /></div></div>
            <div class="card p-5"><Skeleton w="140px" h="18px" /><div class="mt-3 grid gap-2 sm:grid-cols-2"><Skeleton w="100%" h="64px" rounded="12px" /><Skeleton w="100%" h="64px" rounded="12px" /></div></div>
        </div>

        <ErrorState v-else-if="error" @retry="load" />

        <template v-else-if="customer">
            <!-- Who they are, and the two numbers that matter -->
            <section class="card p-5" aria-labelledby="cd-name">
                <div class="flex items-start justify-between gap-5 flex-wrap">
                    <div class="flex items-center gap-4 min-w-0">
                        <div class="cd-avatar" aria-hidden="true">{{ (customer.name || '؟').charAt(0).toUpperCase() }}</div>
                        <div class="min-w-0">
                            <h1 id="cd-name" class="page-title" style="margin:0">{{ customer.name || t('customer.no_name') }}</h1>
                            <a v-if="customer.phone" :href="'tel:' + customer.phone" class="cd-contact" dir="ltr">{{ customer.phone }}</a>
                            <div v-if="customer.email" class="text-sm truncate" style="color:var(--body)" dir="ltr">{{ customer.email }}</div>
                        </div>
                    </div>
                    <div class="cd-stats">
                        <div class="cd-stat">
                            <div class="cd-stat-num">{{ customer.orders_count ?? orders.length }}</div>
                            <div class="cd-stat-label">{{ t('customer.orders_label') }}</div>
                        </div>
                        <div class="cd-stat">
                            <div class="cd-stat-num">{{ totalSpent() }} <span class="cd-stat-cur">{{ cur() }}</span></div>
                            <div class="cd-stat-label">{{ t('customer.total_spent') }}</div>
                        </div>
                    </div>
                </div>
                <p v-if="customer.note" class="cd-note">{{ customer.note }}</p>
            </section>

            <!-- Order history: the main content -->
            <section class="card overflow-hidden" aria-labelledby="cd-orders">
                <h2 id="cd-orders" class="h-card px-5 pt-4 pb-3">{{ t('customer.recent_orders') }}</h2>
                <p v-if="!orders.length" class="px-5 pb-6 text-sm" style="color:var(--body)">{{ t('orders.none') }}</p>
                <ul v-else>
                    <li v-for="o in orders" :key="o.id" class="cd-order">
                        <div class="min-w-0">
                            <div>
                                <span class="cd-code">{{ o.code }}</span>
                                <span v-if="o.order_type" class="cd-sub"> · {{ orderTypeLabel(o.order_type) }}</span>
                            </div>
                            <div class="cd-sub">{{ fmtTime(o.created_at) }}</div>
                            <div v-if="o.address" class="cd-sub">{{ o.address }}</div>
                        </div>
                        <div class="text-end flex-none">
                            <div class="cd-total">{{ o.total }} <span class="cd-cur">{{ cur() }}</span></div>
                            <span class="badge mt-1" :class="badgeClass[o.status]"><span class="dot"></span>{{ statusLabel(o.status) }}</span>
                        </div>
                    </li>
                </ul>
            </section>

            <!-- Addresses -->
            <section class="card p-5" aria-labelledby="cd-addr">
                <h2 id="cd-addr" class="h-card mb-3">{{ t('customer.addresses') }}</h2>
                <p v-if="!customer.addresses?.length" class="text-sm" style="color:var(--body)">{{ t('customer.no_addresses') }}</p>
                <ul v-else class="grid gap-3" style="grid-template-columns:repeat(auto-fill,minmax(min(100%,260px),1fr))">
                    <li v-for="a in customer.addresses" :key="a.id" class="cd-addr">
                        <div v-if="a.label || a.is_default" class="flex items-center gap-2 mb-1.5 flex-wrap">
                            <span v-if="a.label" class="chip-sm">{{ a.label }}</span>
                            <span v-if="a.is_default" class="chip-sm chip-default"><i class="pi pi-check" style="font-size:10px" aria-hidden="true"></i>{{ t('customer.default') }}</span>
                        </div>
                        <div style="color:var(--ink);font-size:15px">{{ a.address }}</div>
                        <div v-if="a.note" class="text-sm mt-1" style="color:var(--body)">{{ a.note }}</div>
                    </li>
                </ul>
            </section>
        </template>

        <div v-else class="card p-8 text-center" style="color:var(--body)">{{ t('common.none') }}</div>
    </div>
</template>

<style scoped>
/* Colours come only from the shared theme variables and the PrimeVue primary
   scale; nothing here introduces a new hex value. */
.back-link { display: inline-flex; align-items: center; gap: 6px; min-height: 44px; padding-inline-end: 12px;
    font-size: 15px; font-weight: 500; color: var(--p-primary-700); background: none; border: 0; cursor: pointer; font-family: inherit; }
.back-link:hover { text-decoration: underline; }

.cd-avatar { width: 64px; height: 64px; border-radius: 50%; flex: none; display: grid; place-items: center;
    background: var(--accent-soft); color: var(--p-primary-700); font-weight: 700; font-size: 24px; }
.cd-contact { display: inline-block; margin-top: 2px; min-height: 28px; font-size: 16px; font-weight: 500; color: var(--p-primary-700); }
.cd-contact:hover { text-decoration: underline; }
.cd-stats { display: flex; gap: 12px; flex-wrap: wrap; }
.cd-stat { background: var(--page); border-radius: 12px; padding: 12px 18px; min-width: 120px; }
.cd-stat-num { font-family: var(--font-display); font-weight: 700; font-size: 26px; line-height: 1.1; color: var(--ink); font-variant-numeric: tabular-nums; }
.cd-stat-cur { font-size: 14px; font-weight: 500; color: var(--body); }
.cd-stat-label { font-size: 13.5px; color: var(--body); margin-top: 2px; }
.cd-note { margin-top: 14px; padding: 10px 12px; border-radius: 10px; background: var(--accent-soft); font-size: 14.5px; color: var(--ink); }

.cd-order { display: flex; align-items: center; justify-content: space-between; gap: 14px; padding: 12px 20px; min-height: 64px;
    border-top: 1px solid var(--line); transition: background .15s; }
.cd-order:hover { background: var(--page); }
.cd-code { font-size: 16px; font-weight: 700; color: var(--ink); }
.cd-sub { font-size: 13.5px; color: var(--body); }
.cd-total { font-size: 16px; font-weight: 700; color: var(--ink); font-variant-numeric: tabular-nums; unicode-bidi: isolate; }
.cd-cur { font-size: 13px; font-weight: 500; color: var(--body); }

.cd-addr { border-radius: 12px; padding: 12px 14px; background: var(--page); border: 1px solid var(--line); }
.chip-sm { display: inline-flex; align-items: center; gap: 5px; padding: 2px 10px; border-radius: 20px;
    border: 1px solid var(--line); background: var(--card); color: var(--body); font-size: 12.5px; font-weight: 600; }
.chip-default { background: var(--accent-soft); border-color: var(--accent-soft); color: var(--p-primary-800); }
</style>
