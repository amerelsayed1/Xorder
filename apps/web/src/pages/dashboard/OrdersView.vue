<script setup>
import { ref, onMounted, onUnmounted } from 'vue'
import { useI18n } from 'vue-i18n'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import { currencyLabel } from '../../lib/currency.js'
import { withMinDuration } from '../../lib/minLoading.js'
import Icon from '@xorder/ui/Icon.vue'
import Skeleton from '@xorder/ui/Skeleton.vue'
import { confirm } from '@xorder/ui/confirm.js'

const { t, locale } = useI18n()

const STATUSES = ['NEW', 'CONFIRMED', 'COMPLETED', 'CANCELLED']
const badgeClass = { NEW: 'badge-amber', CONFIRMED: 'badge-indigo', COMPLETED: 'badge-green', CANCELLED: 'badge-red' }
// Which statuses each status can move to, rendered as per-row action buttons.
const nextActions = { NEW: ['CONFIRMED', 'CANCELLED'], CONFIRMED: ['COMPLETED', 'CANCELLED'] }
const actionLabel = { CONFIRMED: 'orders.confirm', COMPLETED: 'orders.complete', CANCELLED: 'orders.cancel_order' }

const rows = ref([])
const meta = ref(null)
const loading = ref(true)
const statusFilter = ref('')
const page = ref(1)
const updating = ref(null)
const newIds = ref(new Set())
let pollTimer

async function load() {
    loading.value = true
    try {
        const { data } = await withMinDuration(api.get('api/dashboard/orders', {
            params: { status: statusFilter.value || undefined, page: page.value },
        }))
        rows.value = data.data
        meta.value = data.meta || null
    } finally {
        loading.value = false
    }
}

// Live updates: pull orders that arrived since the last check and prepend them,
// so an order that just triggered a notification appears without a refresh.
// Only on page 1 with the current filter — pagination is left untouched.
async function pollNew() {
    if (loading.value || page.value !== 1 || document.hidden) return
    try {
        const { data } = await api.get('api/dashboard/orders', {
            params: { status: statusFilter.value || undefined, page: 1 },
        })
        const known = new Set(rows.value.map((r) => r.id))
        const fresh = (data.data || []).filter((o) => !known.has(o.id))
        if (fresh.length) {
            rows.value = [...fresh, ...rows.value]
            meta.value = data.meta || meta.value
            const ids = new Set(newIds.value)
            fresh.forEach((o) => ids.add(o.id))
            newIds.value = ids
            setTimeout(() => {
                const s = new Set(newIds.value)
                fresh.forEach((o) => s.delete(o.id))
                newIds.value = s
            }, 5000)
        }
    } catch (err) { /* keep current view */ }
}

onMounted(() => {
    load()
    pollTimer = setInterval(pollNew, 12_000)
})
onUnmounted(() => clearInterval(pollTimer))

function setFilter(s) {
    statusFilter.value = s
    page.value = 1
    load()
}

function goToPage(nextPage) {
    if (!meta.value || nextPage < 1 || nextPage > meta.value.last_page) return
    page.value = nextPage
    load()
}

async function setStatus(order, status) {
    if (status === 'CANCELLED') {
        const ok = await confirm({
            title: t('orders.cancel_title'),
            message: t('orders.cancel_message'),
            confirmText: t('orders.cancel_order'),
            cancelText: t('common.back'),
            danger: true,
        })
        if (!ok) return
    }
    updating.value = order.id
    try {
        await ensureCsrf()
        const { data } = await api.patch(`api/dashboard/orders/${order.id}/status`, { status })
        const i = rows.value.findIndex((r) => r.id === order.id)
        if (i !== -1) rows.value[i] = data.data
    } catch (err) {
        alert(t('orders.update_failed'))
    } finally {
        updating.value = null
    }
}

function fmtTime(iso) {
    if (!iso) return ''
    const d = new Date(iso)
    const diffMin = Math.round((d.getTime() - Date.now()) / 60000)
    const rtf = new Intl.RelativeTimeFormat(locale.value, { numeric: 'auto' })
    if (Math.abs(diffMin) < 60) return rtf.format(diffMin, 'minute')
    if (Math.abs(diffMin) < 60 * 24) return rtf.format(Math.round(diffMin / 60), 'hour')
    return d.toLocaleString(locale.value, { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' })
}
</script>

<template>
    <div class="space-y-5">
        <!-- Header -->
        <div class="flex items-start justify-between gap-3 flex-wrap">
            <div>
                <h1 class="page-title">{{ t('orders.title') }}</h1>
                <p class="page-sub">{{ t('orders.subtitle') }}</p>
            </div>
        </div>

        <!-- Status filter -->
        <div class="flex items-center gap-2 flex-wrap">
            <button class="chip" :class="{ 'chip-on': statusFilter === '' }" @click="setFilter('')">{{ t('common.all') }}</button>
            <button v-for="s in STATUSES" :key="s" class="chip" :class="{ 'chip-on': statusFilter === s }" @click="setFilter(s)">
                {{ t('orders.status.' + s) }}
            </button>
        </div>

        <!-- Table -->
        <div class="card overflow-x-auto">
            <table class="w-full text-sm" style="min-width:860px">
                <thead>
                    <tr class="text-start" style="color:var(--muted)">
                        <th class="px-5 py-3 font-medium text-start" style="font-size:11px;text-transform:uppercase">{{ t('orders.order') }}</th>
                        <th class="px-3 py-3 font-medium text-start" style="font-size:11px;text-transform:uppercase">{{ t('orders.time') }}</th>
                        <th class="px-3 py-3 font-medium text-start" style="font-size:11px;text-transform:uppercase">{{ t('orders.customer') }}</th>
                        <th class="px-3 py-3 font-medium text-start" style="font-size:11px;text-transform:uppercase">{{ t('orders.items') }}</th>
                        <th class="px-3 py-3 font-medium text-start" style="font-size:11px;text-transform:uppercase">{{ t('orders.total') }}</th>
                        <th class="px-3 py-3 font-medium text-start" style="font-size:11px;text-transform:uppercase">{{ t('common.status') }}</th>
                        <th class="px-5 py-3 font-medium text-end" style="font-size:11px;text-transform:uppercase">{{ t('common.actions') }}</th>
                    </tr>
                </thead>
                <tbody>
                    <template v-if="loading">
                        <tr v-for="n in 6" :key="'sk' + n" class="border-t" :style="{ borderColor: 'var(--line)' }">
                            <td v-for="c in 7" :key="c" class="px-5 py-4"><Skeleton :h="'14px'" :w="c === 7 ? '60%' : '80%'" /></td>
                        </tr>
                    </template>
                    <tr v-else-if="!rows.length"><td colspan="7" class="px-5 py-8 text-center" style="color:var(--muted)">{{ t('orders.none') }}</td></tr>
                    <tr v-for="order in rows" :key="order.id" class="border-t align-top" :class="{ 'order-row-new': newIds.has(order.id) }" :style="{ borderColor: 'var(--line)' }">
                        <td class="px-5 py-3 font-medium whitespace-nowrap" style="color:var(--ink)">{{ order.code }}</td>
                        <td class="px-3 py-3 whitespace-nowrap" style="color:var(--muted)">{{ fmtTime(order.created_at) }}</td>
                        <td class="px-3 py-3">
                            <div style="color:var(--ink)">{{ order.customer_name || '—' }}</div>
                            <div v-if="order.customer_phone" class="text-xs" style="color:var(--muted)" dir="ltr">{{ order.customer_phone }}</div>
                        </td>
                        <td class="px-3 py-3">
                            <div v-for="(it, i) in order.items" :key="i" class="order-item" style="color:var(--body)">
                                <span class="order-item-qty">{{ it.qty }}×</span>
                                <span>{{ it.name }}<template v-if="it.options?.length"> ({{ it.options.join(', ') }})</template></span>
                            </div>
                            <div v-if="order.note" class="text-xs mt-1" style="color:var(--muted)">{{ t('orders.note') }}: {{ order.note }}</div>
                        </td>
                        <td class="px-3 py-3 whitespace-nowrap font-medium" style="color:var(--ink)">{{ order.total }} {{ currencyLabel(order.currency, locale) }}</td>
                        <td class="px-3 py-3"><span class="badge" :class="badgeClass[order.status]">{{ t('orders.status.' + order.status) }}</span></td>
                        <td class="px-5 py-3 text-end whitespace-nowrap">
                            <div class="inline-flex items-center gap-2">
                                <button v-for="next in nextActions[order.status] || []" :key="next"
                                    class="btn btn-sm" :class="next === 'CANCELLED' ? 'btn-ghost btn-cancel' : 'btn-accent'"
                                    :disabled="updating === order.id" @click="setStatus(order, next)">
                                    <Icon v-if="next !== 'CANCELLED'" name="check" :size="14" />
                                    <Icon v-else name="close" :size="14" />
                                    {{ t(actionLabel[next]) }}
                                </button>
                            </div>
                        </td>
                    </tr>
                </tbody>
            </table>
        </div>

        <!-- Pagination -->
        <div v-if="meta && meta.last_page > 1" class="flex flex-wrap items-center justify-between gap-3">
            <span class="text-sm" style="color:var(--muted)">
                {{ t('common.showing_range', { from: meta.from, to: meta.to, total: meta.total }) }}
            </span>
            <div class="flex items-center gap-2">
                <button class="btn btn-ghost btn-sm" :disabled="meta.current_page <= 1" @click="goToPage(meta.current_page - 1)">
                    {{ t('common.previous') }}
                </button>
                <span class="text-sm" style="color:var(--muted)">{{ meta.current_page }} / {{ meta.last_page }}</span>
                <button class="btn btn-ghost btn-sm" :disabled="meta.current_page >= meta.last_page" @click="goToPage(meta.current_page + 1)">
                    {{ t('common.next') }}
                </button>
            </div>
        </div>
    </div>
</template>

<style scoped>
.chip { display: inline-flex; align-items: center; gap: 7px; padding: 7px 14px; border-radius: 20px;
    border: 1px solid var(--line); background: var(--card); color: var(--body); font-size: 13.5px; font-weight: 600; cursor: pointer; }
.chip-on { background: var(--accent); color: #fff; border-color: var(--accent); }
.btn-cancel { color: #c0392b; }
/* Order line: quantity leads (inline-start), name follows — isolated so the
   Latin "3×" never gets reordered next to an Arabic name. */
.order-item { display: flex; align-items: baseline; gap: 6px; }
.order-item-qty { flex: none; font-weight: 700; color: var(--accent-dark); unicode-bidi: isolate; }
/* Briefly highlight a just-arrived order. */
.order-row-new { animation: order-flash 5s ease-out; }
@keyframes order-flash {
    0% { background: var(--accent-soft, #fdebd0); }
    100% { background: transparent; }
}
@media (prefers-reduced-motion: reduce) { .order-row-new { animation: none; } }
</style>
