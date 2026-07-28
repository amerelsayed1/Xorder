<script setup>
import { ref, onMounted, onUnmounted } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRouter } from 'vue-router'
import { useAuth } from '@xorder/api-client/auth.js'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import { currencyLabel } from '../../lib/currency.js'
import { withMinDuration } from '../../lib/minLoading.js'
import Icon from '@xorder/ui/Icon.vue'
import Skeleton from '@xorder/ui/Skeleton.vue'
import Dialog from '@xorder/ui/Dialog.vue'
import { confirm } from '@xorder/ui/confirm.js'
import { alert } from '@xorder/ui/alert.js'
import { useRealtime } from '../../stores/realtime.js'

const { t, locale } = useI18n()
const auth = useAuth()
const router = useRouter()
const rt = useRealtime()

// The customer name links to the directory record — but only when the customer
// directory feature is on and the order was matched to a directory row.
const canOpenCustomer = (order) => auth.hasFeature('customer_tracking') && !!order.customer_id
function openCustomer(order) {
    if (canOpenCustomer(order)) router.push({ name: 'dashboard.customer', params: { id: order.customer_id } })
}

const STATUSES = ['NEW', 'COMPLETED', 'CANCELLED']
const badgeClass = { NEW: 'badge-amber', COMPLETED: 'badge-green', CANCELLED: 'badge-red' }
// Which statuses each status can move to, rendered as per-row action buttons.
const nextActions = { NEW: ['COMPLETED', 'CANCELLED'] }
const actionLabel = { COMPLETED: 'orders.complete', CANCELLED: 'orders.cancel_order' }

const rows = ref([])
const meta = ref(null)
const loading = ref(true)
const statusFilter = ref('')
const page = ref(1)
const updating = ref(null)
const newIds = ref(new Set())
const receiptOrder = ref(null) // order shown in the bill/receipt sheet, or null
let pollTimer, offTick

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
    // New orders only ever appear when the shared pulse's new-order count rises,
    // so pull them in the instant it ticks; keep a slow fallback as a safety net.
    offTick = rt.onTick(() => { if (!document.hidden) pollNew() })
    pollTimer = setInterval(pollNew, 30_000)
})
onUnmounted(() => { clearInterval(pollTimer); offTick?.() })

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
            <table class="w-full text-sm" style="min-width:720px">
                <thead>
                    <tr class="text-start" style="color:var(--muted)">
                        <th class="px-5 py-3 font-medium text-start" style="font-size:11px;text-transform:uppercase">#</th>
                        <th class="px-5 py-3 font-medium text-start" style="font-size:11px;text-transform:uppercase">{{ t('orders.order') }}</th>
                        <th class="px-3 py-3 font-medium text-start" style="font-size:11px;text-transform:uppercase">{{ t('orders.time') }}</th>
                        <th class="px-3 py-3 font-medium text-start" style="font-size:11px;text-transform:uppercase">{{ t('orders.customer') }}</th>
                        <th class="px-3 py-3 font-medium text-start" style="font-size:11px;text-transform:uppercase">{{ t('common.status') }}</th>
                        <th class="px-5 py-3 font-medium text-end" style="font-size:11px;text-transform:uppercase">{{ t('common.actions') }}</th>
                    </tr>
                </thead>
                <tbody>
                    <template v-if="loading">
                        <tr v-for="n in 6" :key="'sk' + n" class="border-t" :style="{ borderColor: 'var(--line)' }">
                            <td v-for="c in 6" :key="c" class="px-5 py-4"><Skeleton :h="'14px'" :w="c === 6 ? '60%' : '80%'" /></td>
                        </tr>
                    </template>
                    <tr v-else-if="!rows.length"><td colspan="6" class="px-5 py-8 text-center" style="color:var(--muted)">{{ t('orders.none') }}</td></tr>
                    <tr v-for="(order, idx) in rows" :key="order.id" class="border-t align-top" :class="{ 'order-row-new': newIds.has(order.id) }" :style="{ borderColor: 'var(--line)' }">
                        <td class="px-5 py-3 whitespace-nowrap" style="color:var(--muted)">{{ (meta?.from || 1) + idx }}</td>
                        <td class="px-5 py-3 font-medium whitespace-nowrap" style="color:var(--ink)">{{ order.code }}</td>
                        <td class="px-3 py-3 whitespace-nowrap" style="color:var(--muted)">{{ fmtTime(order.created_at) }}</td>
                        <td class="px-3 py-3">
                            <button v-if="canOpenCustomer(order)" type="button" class="cust-link" @click="openCustomer(order)">{{ order.customer_name || '—' }}</button>
                            <div v-else style="color:var(--ink)">{{ order.customer_name || '—' }}</div>
                        </td>
                        <td class="px-3 py-3"><span class="badge" :class="badgeClass[order.status]">{{ t('orders.status.' + order.status) }}</span></td>
                        <td class="px-5 py-3 text-end whitespace-nowrap">
                            <div class="inline-flex items-center gap-2">
                                <button type="button" class="btn btn-ghost btn-sm" @click="receiptOrder = order">
                                    <Icon name="receipt" :size="14" />
                                    {{ t('orders.view') }}
                                </button>
                                <template v-if="!auth.isReadOnly">
                                    <button v-for="next in nextActions[order.status] || []" :key="next"
                                        class="btn btn-sm" :class="next === 'CANCELLED' ? 'btn-ghost btn-cancel' : 'btn-accent'"
                                        :disabled="updating === order.id" @click="setStatus(order, next)">
                                        <Icon v-if="next !== 'CANCELLED'" name="check" :size="14" />
                                        <Icon v-else name="close" :size="14" />
                                        {{ t(actionLabel[next]) }}
                                    </button>
                                </template>
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

        <!-- Bill / receipt sheet -->
        <Dialog v-if="receiptOrder" :title="receiptOrder.code" :subtitle="t('orders.receipt')" @close="receiptOrder = null">
            <div class="receipt">
                <div class="receipt-meta">
                    <div class="receipt-meta-row">
                        <span style="color:var(--muted)">{{ t('orders.time') }}</span>
                        <span style="color:var(--ink)">{{ fmtTime(receiptOrder.created_at) }}</span>
                    </div>
                    <div class="receipt-meta-row">
                        <span style="color:var(--muted)">{{ t('orders.customer') }}</span>
                        <span style="color:var(--ink)">{{ receiptOrder.customer_name || '—' }}</span>
                    </div>
                    <div class="receipt-meta-row">
                        <span style="color:var(--muted)">{{ t('common.status') }}</span>
                        <span class="badge" :class="badgeClass[receiptOrder.status]">{{ t('orders.status.' + receiptOrder.status) }}</span>
                    </div>
                </div>

                <div class="receipt-divider"></div>

                <div class="receipt-items">
                    <div v-for="(it, i) in receiptOrder.items" :key="i" class="receipt-line">
                        <span class="order-item-qty">{{ it.qty }}×</span>
                        <span class="receipt-line-name">{{ it.name }}<template v-if="it.options?.length"> ({{ it.options.join(', ') }})</template></span>
                        <span v-if="it.line_total != null" class="receipt-line-total">{{ it.line_total }} {{ currencyLabel(receiptOrder.currency, locale) }}</span>
                    </div>
                </div>

                <div v-if="receiptOrder.note" class="receipt-note">
                    <span style="color:var(--muted)">{{ t('orders.note') }}:</span> {{ receiptOrder.note }}
                </div>

                <div class="receipt-divider"></div>

                <div class="receipt-total">
                    <span>{{ t('orders.total') }}</span>
                    <span>{{ receiptOrder.total }} {{ currencyLabel(receiptOrder.currency, locale) }}</span>
                </div>
            </div>
        </Dialog>
    </div>
</template>

<style scoped>
.chip { display: inline-flex; align-items: center; gap: 7px; padding: 7px 14px; border-radius: 20px;
    border: 1px solid var(--line); background: var(--card); color: var(--body); font-size: 13.5px; font-weight: 600; cursor: pointer; }
.chip-on { background: var(--accent); color: #fff; border-color: var(--accent); }
.btn-cancel { color: #c0392b; }
/* Customer name → directory record. Looks like text until hovered. */
.cust-link { padding: 0; border: 0; background: none; font: inherit; color: var(--ink); cursor: pointer; text-align: start; }
.cust-link:hover { color: var(--accent); text-decoration: underline; }
/* Order line: quantity leads (inline-start), name follows — isolated so the
   Latin "3×" never gets reordered next to an Arabic name. */
.order-item { display: flex; align-items: baseline; gap: 6px; }
.order-item-qty { flex: none; font-weight: 700; color: var(--accent-dark); unicode-bidi: isolate; }
/* Bill / receipt sheet */
.receipt-meta { display: flex; flex-direction: column; gap: 8px; }
.receipt-meta-row { display: flex; align-items: center; justify-content: space-between; gap: 12px; font-size: 14px; }
.receipt-divider { height: 1px; background: var(--line); margin: 16px 0; }
.receipt-items { display: flex; flex-direction: column; gap: 10px; }
.receipt-line { display: flex; align-items: baseline; gap: 8px; }
.receipt-line-name { flex: 1 1 auto; color: var(--body); }
.receipt-line-total { flex: none; font-weight: 600; color: var(--ink); unicode-bidi: isolate; }
.receipt-note { margin-top: 14px; font-size: 13px; color: var(--body); }
.receipt-total { display: flex; align-items: center; justify-content: space-between;
    font-size: 16px; font-weight: 700; color: var(--ink); }
/* Briefly highlight a just-arrived order. */
.order-row-new { animation: order-flash 5s ease-out; }
@keyframes order-flash {
    0% { background: var(--accent-soft, #fdebd0); }
    100% { background: transparent; }
}
@media (prefers-reduced-motion: reduce) { .order-row-new { animation: none; } }
</style>
