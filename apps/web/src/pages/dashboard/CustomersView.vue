<script setup>
import { ref, onMounted, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import api from '@xorder/api-client/api.js'
import { useAuth } from '@xorder/api-client/auth.js'
import Modal from '@xorder/ui/Modal.vue'
import ListSkeleton from '@xorder/ui/ListSkeleton.vue'
import Icon from '@xorder/ui/Icon.vue'

const { t, locale } = useI18n()
const auth = useAuth()
const cur = () => auth.restaurant?.currency_symbol || ''

const rows = ref([])
const loading = ref(true)
const search = ref('')
const detail = ref(null)
const detailLoading = ref(false)
let searchTimer

async function load() {
    loading.value = true
    try {
        const { data } = await api.get('api/dashboard/customers', { params: { search: search.value || undefined } })
        rows.value = data.data
    } finally { loading.value = false }
}
onMounted(load)
watch(search, () => { clearTimeout(searchTimer); searchTimer = setTimeout(load, 300) })

async function open(c) {
    detail.value = { ...c, addresses: [], recent_orders: [] }
    detailLoading.value = true
    try {
        const { data } = await api.get(`api/dashboard/customers/${c.id}`)
        detail.value = { ...data.data, recent_orders: data.recent_orders || [] }
    } finally { detailLoading.value = false }
}

const fmtTime = (iso) => iso ? new Date(iso).toLocaleString(locale.value === 'ar' ? 'ar-EG' : 'en-GB', { dateStyle: 'medium', timeStyle: 'short' }) : ''
const orderTypeLabel = (v) => v ? t('order_type.' + v) : ''
const statusLabel = (s) => t('orders.status.' + s)
</script>

<template>
    <div class="space-y-5">
        <div class="flex items-start justify-between gap-3">
            <div>
                <h1 class="page-title">{{ t('nav.customers') }}</h1>
                <p class="page-sub">{{ t('customer.subtitle', { count: rows.length }) }}</p>
            </div>
        </div>

        <div class="relative" style="max-width:320px">
            <span class="absolute top-1/2 -translate-y-1/2" style="inset-inline-start:12px;color:var(--muted)"><Icon name="search" :size="17" /></span>
            <input v-model="search" :placeholder="t('customer.search_ph')" class="input" style="padding-inline-start:38px" />
        </div>

        <div class="card overflow-hidden">
            <ListSkeleton v-if="loading" />
            <div v-else-if="!rows.length" class="p-8 text-center" style="color:var(--muted)">{{ t('customer.none') }}</div>
            <ul v-else>
                <li v-for="c in rows" :key="c.id" class="flex items-center gap-3 px-5 py-3 border-t first:border-t-0 cursor-pointer hover:bg-black/[.02]" style="border-color:var(--line)" @click="open(c)">
                    <div class="h-11 w-11 rounded-full grid place-items-center flex-shrink-0 font-bold" style="background:var(--accent-soft);color:var(--accent)">{{ (c.name || '؟').charAt(0).toUpperCase() }}</div>
                    <div class="flex-1 min-w-0">
                        <div class="font-medium" style="color:var(--ink)">{{ c.name || t('customer.no_name') }}</div>
                        <div class="text-xs" style="color:var(--muted)" dir="ltr">{{ c.phone }}</div>
                    </div>
                    <div class="text-xs text-end" style="color:var(--muted)">
                        <div>{{ t('customer.orders_n', { n: c.orders_count }) }}</div>
                        <div v-if="c.addresses_count">{{ t('customer.addresses_n', { n: c.addresses_count }) }}</div>
                    </div>
                    <Icon name="chevronDown" :size="16" class="-rotate-90 rtl:rotate-90" style="color:var(--muted)" />
                </li>
            </ul>
        </div>

        <!-- Customer detail -->
        <Modal v-if="detail" :title="detail.name || t('customer.no_name')" @close="detail = null">
            <div class="space-y-4">
                <div class="flex flex-wrap gap-x-6 gap-y-1 text-sm">
                    <span dir="ltr" style="color:var(--ink)"><Icon name="link" :size="14" class="inline" /> {{ detail.phone }}</span>
                    <span v-if="detail.email" dir="ltr" style="color:var(--muted)">{{ detail.email }}</span>
                </div>
                <p v-if="detail.note" class="text-sm" style="color:var(--muted)">{{ detail.note }}</p>

                <div>
                    <div class="label mb-2">{{ t('customer.addresses') }}</div>
                    <div v-if="detailLoading" class="space-y-2"><div class="h-10 rounded-lg" style="background:var(--line)"></div></div>
                    <p v-else-if="!detail.addresses?.length" class="text-sm" style="color:var(--muted)">{{ t('customer.no_addresses') }}</p>
                    <ul v-else class="space-y-2">
                        <li v-for="a in detail.addresses" :key="a.id" class="rounded-xl p-3 text-sm" style="background:var(--page);border:1px solid var(--line)">
                            <div class="flex items-center gap-2">
                                <span v-if="a.label" class="chip">{{ a.label }}</span>
                                <span v-if="a.is_default" class="chip" style="background:var(--accent-soft);color:var(--accent)">{{ t('customer.default') }}</span>
                            </div>
                            <div style="color:var(--ink)">{{ a.address }}</div>
                            <div v-if="a.note" class="text-xs" style="color:var(--muted)">{{ a.note }}</div>
                        </li>
                    </ul>
                </div>

                <div>
                    <div class="label mb-2">{{ t('customer.recent_orders') }}</div>
                    <p v-if="!detail.recent_orders?.length" class="text-sm" style="color:var(--muted)">{{ t('orders.none') }}</p>
                    <ul v-else class="space-y-1">
                        <li v-for="o in detail.recent_orders" :key="o.id" class="flex items-center justify-between gap-3 py-2 border-t first:border-t-0 text-sm" style="border-color:var(--line)">
                            <div>
                                <span class="font-medium" style="color:var(--ink)">{{ o.code }}</span>
                                <span v-if="o.order_type" class="text-xs" style="color:var(--muted)"> · {{ orderTypeLabel(o.order_type) }}</span>
                                <div class="text-xs" style="color:var(--muted)">{{ fmtTime(o.created_at) }}</div>
                            </div>
                            <div class="text-end">
                                <div class="font-medium" style="color:var(--ink)">{{ o.total }} {{ cur() }}</div>
                                <div class="text-xs" style="color:var(--muted)">{{ statusLabel(o.status) }}</div>
                            </div>
                        </li>
                    </ul>
                </div>
            </div>
        </Modal>
    </div>
</template>
