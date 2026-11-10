<script setup>
import { ref, computed, watch, onMounted, onUnmounted } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRouter } from 'vue-router'
import { useCaps } from '../../lib/useCaps.js'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import { currencyLabel } from '../../lib/currency.js'
import { formatMinor, currencyExponent } from '../../lib/money.js'
import { withMinDuration } from '../../lib/minLoading.js'
import Icon from '@xorder/ui/Icon.vue'
import Skeleton from '@xorder/ui/Skeleton.vue'
import ErrorState from '@xorder/ui/ErrorState.vue'
import Dialog from '@xorder/ui/Dialog.vue'
import { confirmWithInput } from '@xorder/ui/confirm.js'
import { alert } from '@xorder/ui/alert.js'
import { toast } from '@xorder/ui/toast.js'
import { useRealtime } from '../../stores/realtime.js'

const { t, locale } = useI18n()
// Advancing an order's status is an update.
const { canUpdate } = useCaps('orders')
const router = useRouter()
const rt = useRealtime()

// The customer name links to the directory record when the order was matched
// to a directory row. The directory is available on every plan.
const canOpenCustomer = (order) => !!order.customer_id
function openCustomer(order) {
    if (canOpenCustomer(order)) router.push({ name: 'dashboard.customer', params: { id: order.customer_id } })
}

const STATUSES = ['NEW', 'COMPLETED', 'CANCELLED']
const ORDER_TYPES = ['dine_in', 'pickup', 'delivery']
const badgeClass = { NEW: 'badge-amber', COMPLETED: 'badge-green', CANCELLED: 'badge-red' }
// Order type is nullable (older orders / QR-menu-only branches have none).
const orderTypeLabel = (order) => order.order_type ? t('order_type.' + order.order_type) : '—'
// Which statuses each status can move to, rendered as per-row action buttons.
const nextActions = { NEW: ['COMPLETED', 'CANCELLED'] }
const actionLabel = { COMPLETED: 'orders.complete', CANCELLED: 'orders.cancel_order' }

const rows = ref([])
const meta = ref(null)
const summary = ref(null)
const loading = ref(true)
// Why the list is not showing, when it is not: a refused request leaves a
// sentence rather than the "no orders yet" empty state. 'plan' is the feature
// gate — neither online ordering nor the POS is in this restaurant's plan, which
// the sidebar already hides but a typed URL still reaches. Until 16 Oct 2026 the
// 403 was swallowed and an owner read "no orders yet" over a day with a sale.
const failed = ref(null)
const statusFilter = ref('')
const typeFilter = ref('')
const query = ref('')
// Restaurant-local calendar days (YYYY-MM-DD), inclusive. Empty = unbounded.
const dateFrom = ref('')
const dateTo = ref('')
const exporting = ref(false)
const page = ref(1)
const updating = ref(null)
const newIds = ref(new Set())
const readAt = ref(null) // when the list was last read from the server
const receiptOrder = ref(null) // order shown in the bill/receipt sheet, or null

// XORD-048: the sheet opens at once with the list row, then swaps in the
// details request — invoice number, till, cashier, table, the money breakdown
// and payments, as the cashier's receipt carried them. If that request fails
// the row's own fields stay on screen.
async function openReceipt(order) {
    receiptOrder.value = order
    try {
        const { data } = await api.get(`api/dashboard/orders/${order.id}`)
        if (receiptOrder.value?.id === order.id) receiptOrder.value = data.data
    } catch {
        // Keep the list row; the sheet still shows what it has.
    }
}
let pollTimer, offTick, searchTimer

const filtersActive = computed(() => !!statusFilter.value || !!typeFilter.value || !!query.value.trim()
    || !!dateFrom.value || !!dateTo.value)
const statusCount = (key) => summary.value?.counts?.[key] ?? null
const metrics = computed(() => summary.value?.metrics || null)
// Prices in the day figures carry the restaurant's currency, not an order's.
const salesCurrency = computed(() => currencyLabel(metrics.value?.currency, locale.value))
// Formatted lazily so switching language relabels the stamp instead of
// leaving the previous locale's AM/PM marker sitting in the footer.
const updatedAt = computed(() => (readAt.value
    ? readAt.value.toLocaleTimeString(locale.value, { hour: '2-digit', minute: '2-digit' })
    : ''))

function params() {
    return {
        status: statusFilter.value || undefined,
        order_type: typeFilter.value || undefined,
        q: query.value.trim() || undefined,
        from: dateFrom.value || undefined,
        to: dateTo.value || undefined,
        page: page.value,
    }
}

// A range typed backwards is almost always the two fields swapped; fix it
// rather than ask the server for an error.
watch([dateFrom, dateTo], () => {
    if (dateFrom.value && dateTo.value && dateFrom.value > dateTo.value) {
        [dateFrom.value, dateTo.value] = [dateTo.value, dateFrom.value]
        return
    }
    page.value = 1
    load()
})

// Everything the current filters match, as CSV — not just this page. Fetched
// as a blob because the API needs the auth header a plain link can't carry.
async function exportCsv() {
    if (exporting.value) return
    exporting.value = true
    try {
        const { page: _ignored, ...filters } = params()
        const res = await api.get('api/dashboard/orders/export', { params: filters, responseType: 'blob' })
        const name = /filename="?([^";]+)"?/.exec(res.headers?.['content-disposition'] || '')?.[1] || 'orders.csv'
        const url = URL.createObjectURL(res.data)
        const a = document.createElement('a')
        a.href = url
        a.download = name
        document.body.appendChild(a)
        a.click()
        a.remove()
        setTimeout(() => URL.revokeObjectURL(url), 1000)
    } catch {
        alert(t('orders.export_failed'))
    } finally {
        exporting.value = false
    }
}

/**
 * `silent` keeps the current rows on screen while the request is in flight.
 * Used after a status change, where a skeleton would blank a table the user is
 * reading — but a full reload is still what we want, so the tab counts, the day
 * figures and (under a status filter) the row's own presence stay truthful.
 */
async function load({ silent = false } = {}) {
    if (!silent) loading.value = true
    failed.value = null
    try {
        const req = api.get('api/dashboard/orders', { params: params() })
        const { data } = await (silent ? req : withMinDuration(req))
        rows.value = data.data
        meta.value = data.meta || null
        summary.value = data.summary || null
        readAt.value = new Date()
    } catch (err) {
        failed.value = err?.response?.status === 403 ? 'plan' : 'error'
    } finally {
        if (!silent) loading.value = false
    }
}

// Live updates: pull orders that arrived since the last check and prepend them,
// so an order that just triggered a notification appears without a refresh.
// Only on page 1 with the current filter — pagination is left untouched.
async function pollNew() {
    // A refused list stays refused; polling it again would only repeat the 403.
    if (loading.value || failed.value || page.value !== 1 || document.hidden) return
    try {
        const { data } = await api.get('api/dashboard/orders', { params: { ...params(), page: 1 } })
        // The counts and the day figures move with every new order, so they are
        // taken from the poll even when no unseen row came back with it.
        summary.value = data.summary || summary.value
        const known = new Set(rows.value.map((r) => r.id))
        const fresh = (data.data || []).filter((o) => !known.has(o.id))
        if (fresh.length) {
            rows.value = [...fresh, ...rows.value]
            meta.value = data.meta || meta.value
            readAt.value = new Date()
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
onUnmounted(() => { clearInterval(pollTimer); clearTimeout(searchTimer); offTick?.() })

// Search runs on the server (it has to reach past the current page), so it waits
// for a pause in typing rather than firing a request per keystroke.
watch(query, () => {
    clearTimeout(searchTimer)
    searchTimer = setTimeout(() => { page.value = 1; load() }, 350)
})

function setFilter(s) {
    statusFilter.value = s
    page.value = 1
    load()
}

function setTypeFilter(type) {
    typeFilter.value = type
    page.value = 1
    load()
}

function resetFilters() {
    clearTimeout(searchTimer)
    statusFilter.value = ''
    typeFilter.value = ''
    query.value = ''
    // Clearing the dates triggers their watcher, which reloads; only reload
    // here when they were already empty.
    const hadDates = !!dateFrom.value || !!dateTo.value
    dateFrom.value = ''
    dateTo.value = ''
    page.value = 1
    if (!hadDates) load()
}

function goToPage(nextPage) {
    if (!meta.value || nextPage < 1 || nextPage > meta.value.last_page) return
    page.value = nextPage
    load()
}

async function setStatus(order, status) {
    const payload = { status }
    if (status === 'CANCELLED') {
        // The reason is optional; null means the user backed out.
        const reason = await confirmWithInput({
            title: t('orders.cancel_title'),
            message: t('orders.cancel_message'),
            confirmText: t('orders.cancel_order'),
            cancelText: t('common.back'),
            danger: true,
            inputLabel: t('orders.cancel_reason_label'),
            inputPlaceholder: t('orders.cancel_reason_ph'),
        })
        if (reason === null) return
        payload.reason = reason
    }
    updating.value = order.id
    try {
        await ensureCsrf()
        const { data } = await api.patch(`api/dashboard/orders/${order.id}/status`, payload)
        const i = rows.value.findIndex((r) => r.id === order.id)
        if (i !== -1) rows.value[i] = data.data
        toast(data.message || t('common.saved'))
        await load({ silent: true })
    } catch (err) {
        alert(t('orders.update_failed'))
    } finally {
        updating.value = null
    }
}

// The dine-in bill is owned by the table visit, so its rows carry no advance
// buttons here — staff close the visit instead.
const advanceActions = (order) => (order.table_visit_id ? [] : (nextActions[order.status] || []))

// One line of what was ordered, so the board is readable without opening every
// receipt. The full list stays in the receipt sheet.
function itemSummary(order) {
    const names = (order.items || []).map((i) => itemTitle(i)).filter(Boolean)
    return names.length ? names.join(' · ') : '—'
}
// The line name in the current UI locale (R1). POS lines carry both languages
// frozen from the item; older and QR/public lines carry only `name`, which is
// the fallback — so no historical order ever renders blank. Mirrors the
// app-wide idiom (RestaurantDetails.vue).
function itemName(it) {
    const byLocale = locale.value === 'ar' ? (it.name_ar || it.name_en) : (it.name_en || it.name_ar)
    return byLocale || it.name || ''
}
// "Pizza (Medium)": the name plus the chosen size/portion. Orders recorded
// before `variant` existed carry the size inside `options`, so nothing is lost
// for them either — it shows up in the extras line instead.
function itemTitle(it) {
    return it.variant ? `${itemName(it)} (${it.variant})` : itemName(it)
}
function itemCount(order) {
    return (order.items || []).reduce((n, i) => n + (Number(i.qty) || 0), 0)
}

// Clock time is what staff read back to a customer; the relative line under it
// answers "how long has this been sitting?" at a glance.
// Branch names follow the dashboard language, falling back to the other one.
const branchName = (order) => {
    const b = order.branch
    if (!b) return ''
    return locale.value === 'ar' ? (b.name_ar || b.name_en) : (b.name_en || b.name_ar)
}
const PAYMENT_BADGE = { PAID: 'badge-green', UNPAID: 'badge-amber', PARTIALLY_REFUNDED: 'badge-amber', REFUNDED: 'badge-red' }
// "Handled by" and "time to complete" as one quiet line under the status.
function handledLine(order) {
    const parts = []
    if (order.handled_by_name) parts.push(order.handled_by_name)
    if (order.minutes_to_complete != null) parts.push(t('orders.minutes', { n: order.minutes_to_complete }))
    return parts.join(' · ')
}

// The sheet's figures: stored minor units with the order's own currency.
function sheetMoney(order, minor, { negative = false } = {}) {
    return formatMinor(negative ? -minor : minor, currencyExponent(order.currency), currencyLabel(order.currency, locale.value))
}
const hasMinor = (v) => v != null && Number(v) !== 0
// "T3 · Terrace": the table with its dining area, in the dashboard language.
function tableLine(order) {
    const a = order.dining_area
    const area = a ? (locale.value === 'ar' ? (a.name_ar || a.name_en) : (a.name_en || a.name_ar)) : ''
    return [order.table_label, area].filter(Boolean).join(' · ')
}
function fmtDateTime(iso) {
    if (!iso) return ''
    return new Date(iso).toLocaleString(locale.value, { year: 'numeric', month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' })
}

function fmtClock(iso) {
    if (!iso) return ''
    return new Date(iso).toLocaleTimeString(locale.value, { hour: '2-digit', minute: '2-digit' })
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
        <div class="flex flex-wrap items-end justify-between gap-4">
            <div class="min-w-0">
                <div class="flex items-center gap-3 flex-wrap">
                    <h1 class="page-title">{{ t('orders.title') }}</h1>
                    <span class="live-pill"><span class="live-dot" aria-hidden="true"></span>{{ t('orders.live') }}</span>
                </div>
                <p class="page-sub" style="color:var(--body)">{{ t('orders.subtitle') }}</p>
            </div>
            <div class="flex items-center gap-2 flex-wrap head-tools">
                <div class="relative search-box">
                    <span class="search-ico"><Icon name="search" :size="17" /></span>
                    <input v-model="query" :placeholder="t('orders.search_placeholder')" :aria-label="t('orders.search_placeholder')" class="input" style="margin-top:0;padding-inline-start:38px;min-height:44px" />
                </div>
                <button class="btn btn-ghost touch" :disabled="loading" @click="load()">
                    <Icon name="refresh" :size="16" />{{ t('orders.refresh') }}
                </button>
            </div>
        </div>

        <!-- Date range + export. The range narrows the list, its tab counts and
             the export alike; the day figures below stay "today" on purpose. -->
        <div class="flex flex-wrap items-center justify-between gap-3">
            <div class="date-range">
                <label class="date-field">
                    <span>{{ t('orders.date_from') }}</span>
                    <input v-model="dateFrom" type="date" class="input" :max="dateTo || undefined" :aria-label="t('orders.date_from')" />
                </label>
                <span class="date-sep" aria-hidden="true">→</span>
                <label class="date-field">
                    <span>{{ t('orders.date_to') }}</span>
                    <input v-model="dateTo" type="date" class="input" :min="dateFrom || undefined" :aria-label="t('orders.date_to')" />
                </label>
                <button v-if="dateFrom || dateTo" type="button" class="btn btn-ghost btn-sm" @click="dateFrom = ''; dateTo = ''">
                    {{ t('orders.clear_dates') }}
                </button>
            </div>
            <button type="button" class="btn btn-ghost" :disabled="exporting || failed === 'plan'" @click="exportCsv">
                <Icon name="download" :size="16" />{{ exporting ? t('orders.exporting') : t('orders.export_csv') }}
            </button>
        </div>

        <!-- The day at a glance. Unfiltered on purpose — these describe the
             restaurant's day, not whatever the toolbar is currently showing.
             New orders lead and lights up when one is waiting. -->
        <section class="metric-grid" :aria-label="t('orders.subtitle')">
            <div class="stat metric" :class="{ 'metric-hot': metrics && metrics.new_orders > 0 }">
                <div class="stat-label"><i class="pi pi-bell me-1.5" aria-hidden="true"></i>{{ t('orders.m_new') }}</div>
                <div class="stat-num"><Skeleton v-if="!metrics" h="30px" w="52px" /><template v-else>{{ metrics.new_orders }}</template></div>
                <div class="stat-hint">{{ t('orders.m_new_hint') }}</div>
            </div>
            <div class="stat metric">
                <div class="stat-label">{{ t('orders.m_today') }}</div>
                <div class="stat-num"><Skeleton v-if="!metrics" h="30px" w="52px" /><template v-else>{{ metrics.orders_today }}</template></div>
                <div class="stat-hint">{{ t('orders.m_since_midnight') }}</div>
            </div>
            <div class="stat metric">
                <div class="stat-label">{{ t('orders.m_completed') }}</div>
                <div class="stat-num"><Skeleton v-if="!metrics" h="30px" w="52px" /><template v-else>{{ metrics.completed_today }}</template></div>
                <div class="stat-hint">{{ t('orders.status.COMPLETED') }}</div>
            </div>
            <div class="stat metric">
                <div class="stat-label">{{ t('orders.m_sales') }}</div>
                <div class="stat-num"><Skeleton v-if="!metrics" h="30px" w="90px" /><template v-else>{{ metrics.sales_today }}</template></div>
                <div class="stat-hint">{{ salesCurrency }}</div>
            </div>
        </section>

        <div class="card overflow-hidden">
            <!-- Toolbar: status tabs carry live counts, type tabs narrow further -->
            <div class="orders-toolbar">
                <div class="segmented tabs" role="group" :aria-label="t('common.status')">
                    <button type="button" :class="{ active: statusFilter === '' }" :aria-pressed="statusFilter === ''" @click="setFilter('')">
                        {{ t('common.all') }}
                        <span v-if="statusCount('all') !== null" class="tab-count">{{ statusCount('all') }}</span>
                    </button>
                    <button v-for="s in STATUSES" :key="s" type="button" :class="{ active: statusFilter === s }" :aria-pressed="statusFilter === s" @click="setFilter(s)">
                        {{ t('orders.status.' + s) }}
                        <span v-if="statusCount(s) !== null" class="tab-count" :class="{ 'tab-count-hot': s === 'NEW' && statusCount(s) > 0 }">{{ statusCount(s) }}</span>
                    </button>
                </div>
                <div class="flex items-center gap-2 flex-wrap">
                    <span class="text-sm" style="color:var(--body)">{{ t('orders.type') }}</span>
                    <div class="segmented tabs" role="group" :aria-label="t('orders.type')">
                        <button type="button" :class="{ active: typeFilter === '' }" :aria-pressed="typeFilter === ''" @click="setTypeFilter('')">{{ t('common.all') }}</button>
                        <button v-for="ty in ORDER_TYPES" :key="ty" type="button" :class="{ active: typeFilter === ty }" :aria-pressed="typeFilter === ty" @click="setTypeFilter(ty)">
                            {{ t('order_type.' + ty) }}
                        </button>
                    </div>
                </div>
            </div>

            <!-- Table on wide screens; each row folds into a card on a phone -->
            <div class="overflow-x-auto">
                <table class="w-full text-sm orders-table">
                    <thead>
                        <tr class="orders-head">
                            <th class="text-start">{{ t('orders.order') }}</th>
                            <th class="text-start">{{ t('orders.items') }}</th>
                            <th class="text-start">{{ t('orders.type') }}</th>
                            <th class="text-start">{{ t('orders.customer') }}</th>
                            <th class="text-start">{{ t('orders.time') }}</th>
                            <th class="text-start">{{ t('orders.total') }}</th>
                            <th class="text-start">{{ t('common.status') }}</th>
                            <th class="text-end">{{ t('common.actions') }}</th>
                        </tr>
                    </thead>
                    <tbody>
                        <template v-if="loading">
                            <tr v-for="n in 6" :key="'sk' + n" class="sk-row">
                                <td v-for="c in 8" :key="c"><Skeleton h="16px" :w="c === 8 ? '60%' : '80%'" /></td>
                            </tr>
                        </template>
                        <!-- v-else so a pending filter switch shows only the shimmer,
                             never the previous filter's rows underneath it. -->
                        <template v-else-if="rows.length">
                            <tr v-for="order in rows" :key="order.id" class="orders-row"
                                :class="{ 'order-row-new': newIds.has(order.id), 'row-pending': order.status === 'NEW' }">
                                <td class="c-code whitespace-nowrap cell-code">
                                    {{ order.code }}
                                    <div v-if="branchName(order)" class="cell-sub">{{ branchName(order) }}</div>
                                </td>
                                <td class="c-items cell-items">
                                    <div class="cell-strong truncate">{{ itemSummary(order) }}</div>
                                    <div class="cell-sub">{{ t('orders.items_n', { n: itemCount(order) }) }}</div>
                                </td>
                                <td class="c-type whitespace-nowrap">
                                    <span v-if="order.order_type" class="type-tag">
                                        <span class="type-dot" :class="'type-' + order.order_type" aria-hidden="true"></span>{{ orderTypeLabel(order) }}
                                    </span>
                                    <span v-else style="color:var(--body)">—</span>
                                    <!-- Where it was rung up, when that is not the QR
                                         menu. A till sale and a diner's phone order look
                                         identical in every other column, and they are not
                                         the same thing to a manager reading this list. -->
                                    <span v-if="order.source === 'pos'" class="src-tag">{{ t('order_source.pos') }}</span>
                                    <span v-if="order.table_label" class="src-tag">{{ order.table_label }}</span>
                                </td>
                                <td class="c-cust">
                                    <button v-if="canOpenCustomer(order)" type="button" class="cust-link cell-strong" @click="openCustomer(order)">{{ order.customer_name || '—' }}</button>
                                    <div v-else class="cell-strong">{{ order.customer_name || '—' }}</div>
                                    <div v-if="order.customer_phone" class="cell-sub cell-phone"><bdi dir="ltr">{{ order.customer_phone }}</bdi></div>
                                </td>
                                <td class="c-time whitespace-nowrap">
                                    <div class="cell-strong tabular">{{ fmtClock(order.created_at) }}</div>
                                    <div class="cell-sub">{{ fmtTime(order.created_at) }}</div>
                                </td>
                                <td class="c-total whitespace-nowrap cell-total">
                                    {{ order.total }} <span class="cell-cur">{{ currencyLabel(order.currency, locale) }}</span>
                                    <div v-if="order.payment_status" class="cell-sub">
                                        <span class="pay-tag" :class="PAYMENT_BADGE[order.payment_status]">{{ t('orders.payment.' + order.payment_status) }}</span>
                                    </div>
                                </td>
                                <td class="c-status">
                                    <span class="badge" :class="badgeClass[order.status]"><span class="dot"></span>{{ t('orders.status.' + order.status) }}</span>
                                    <div v-if="handledLine(order)" class="cell-sub">{{ handledLine(order) }}</div>
                                </td>
                                <td class="c-actions text-end whitespace-nowrap">
                                    <div class="inline-flex items-center gap-2">
                                        <template v-if="canUpdate">
                                            <!-- The move-forward action is the one staff reach for all day, so it
                                                 keeps its label. Cancel is rare and destructive: it stays available
                                                 but shrinks to an icon rather than crowding the row. -->
                                            <button v-if="advanceActions(order).includes('COMPLETED')"
                                                class="btn btn-accent btn-sm act"
                                                :disabled="updating === order.id" @click="setStatus(order, 'COMPLETED')">
                                                <Icon name="check" :size="14" />{{ t(actionLabel.COMPLETED) }}
                                            </button>
                                            <button v-if="advanceActions(order).includes('CANCELLED')"
                                                type="button" class="icon-btn icon-btn-danger act-icon"
                                                :title="t('orders.cancel_order')" :aria-label="t('orders.cancel_order')"
                                                :disabled="updating === order.id" @click="setStatus(order, 'CANCELLED')">
                                                <Icon name="close" :size="16" />
                                            </button>
                                        </template>
                                        <button type="button" class="btn btn-ghost btn-sm act" @click="openReceipt(order)">
                                            <Icon name="receipt" :size="14" />{{ t('orders.details') }}
                                        </button>
                                    </div>
                                </td>
                            </tr>
                        </template>
                        <tr v-else-if="failed === 'plan'" class="state-row">
                            <td colspan="8" class="px-6 py-14 text-center text-sm" style="color:var(--body)">
                                <i class="pi pi-lock block mb-2" style="font-size:22px" aria-hidden="true"></i>{{ t('orders.not_in_plan') }}
                            </td>
                        </tr>
                        <tr v-else-if="failed" class="state-row">
                            <td colspan="8" class="px-6 py-6"><ErrorState @retry="load()" /></td>
                        </tr>
                        <tr v-else class="state-row">
                            <td colspan="8" class="px-6 py-14">
                                <div class="empty">
                                    <div class="empty-mark"><Icon name="receipt" :size="22" /></div>
                                    <div class="empty-title">{{ filtersActive ? t('orders.no_match_title') : t('orders.none') }}</div>
                                    <p v-if="filtersActive" class="empty-body">{{ t('orders.no_match_body') }}</p>
                                    <button v-if="filtersActive" class="btn btn-accent touch" @click="resetFilters">{{ t('orders.reset') }}</button>
                                </div>
                            </td>
                        </tr>
                    </tbody>
                </table>
            </div>

            <!-- Footer strip: what is on screen, when it was last read, and the
                 pager when there is more than one page of it. -->
            <div class="orders-foot">
                <span v-if="meta">{{ t('orders.showing_count', { n: rows.length, total: meta.total }) }}</span>
                <span v-else></span>
                <div class="flex items-center gap-3 flex-wrap">
                    <template v-if="meta && meta.last_page > 1">
                        <button class="btn btn-ghost btn-sm touch" :disabled="meta.current_page <= 1" @click="goToPage(meta.current_page - 1)">
                            {{ t('common.previous') }}
                        </button>
                        <span class="tabular">{{ meta.current_page }} / {{ meta.last_page }}</span>
                        <button class="btn btn-ghost btn-sm touch" :disabled="meta.current_page >= meta.last_page" @click="goToPage(meta.current_page + 1)">
                            {{ t('common.next') }}
                        </button>
                    </template>
                    <span v-if="updatedAt">{{ t('orders.updated_at', { time: updatedAt }) }}</span>
                </div>
            </div>
        </div>

        <!-- Bill / receipt sheet -->
        <Dialog v-if="receiptOrder" :title="receiptOrder.invoice_number || receiptOrder.code"
            :subtitle="receiptOrder.invoice_number ? `${receiptOrder.code} · ${t('orders.receipt')}` : t('orders.receipt')"
            @close="receiptOrder = null">
            <div class="receipt">
                <div class="receipt-meta">
                    <div class="receipt-meta-row">
                        <span style="color:var(--body)">{{ t('orders.time') }}</span>
                        <span style="color:var(--ink)">{{ fmtDateTime(receiptOrder.created_at) }} · {{ fmtTime(receiptOrder.created_at) }}</span>
                    </div>
                    <div v-if="receiptOrder.order_type" class="receipt-meta-row">
                        <span style="color:var(--body)">{{ t('orders.type') }}</span>
                        <span class="badge badge-type">{{ orderTypeLabel(receiptOrder) }}</span>
                    </div>
                    <div v-if="tableLine(receiptOrder)" class="receipt-meta-row">
                        <span style="color:var(--body)">{{ t('orders.sheet_table') }}</span>
                        <span style="color:var(--ink)">{{ tableLine(receiptOrder) }}</span>
                    </div>
                    <div class="receipt-meta-row">
                        <span style="color:var(--body)">{{ t('orders.customer') }}</span>
                        <span style="color:var(--ink)">{{ receiptOrder.customer_name || '—' }}</span>
                    </div>
                    <div class="receipt-meta-row">
                        <span style="color:var(--body)">{{ t('common.status') }}</span>
                        <span class="badge" :class="badgeClass[receiptOrder.status]">{{ t('orders.status.' + receiptOrder.status) }}</span>
                    </div>
                    <div v-if="branchName(receiptOrder)" class="receipt-meta-row">
                        <span style="color:var(--muted)">{{ t('orders.branch') }}</span>
                        <span style="color:var(--ink)">{{ branchName(receiptOrder) }}</span>
                    </div>
                    <div v-if="receiptOrder.cashier_name" class="receipt-meta-row">
                        <span style="color:var(--muted)">{{ t('orders.sheet_cashier') }}</span>
                        <span style="color:var(--ink)">{{ receiptOrder.cashier_name }}</span>
                    </div>
                    <div v-if="receiptOrder.terminal_name" class="receipt-meta-row">
                        <span style="color:var(--muted)">{{ t('orders.sheet_till') }}</span>
                        <span style="color:var(--ink)">{{ receiptOrder.terminal_name }}</span>
                    </div>
                    <div v-if="receiptOrder.payment_status" class="receipt-meta-row">
                        <span style="color:var(--muted)">{{ t('orders.payment_label') }}</span>
                        <span class="pay-tag" :class="PAYMENT_BADGE[receiptOrder.payment_status]">{{ t('orders.payment.' + receiptOrder.payment_status) }}</span>
                    </div>
                    <div v-if="receiptOrder.handled_by_name" class="receipt-meta-row">
                        <span style="color:var(--muted)">{{ t('orders.handled_by') }}</span>
                        <span style="color:var(--ink)">{{ receiptOrder.handled_by_name }}</span>
                    </div>
                    <div v-if="receiptOrder.minutes_to_complete != null" class="receipt-meta-row">
                        <span style="color:var(--muted)">{{ t('orders.time_to_complete') }}</span>
                        <span style="color:var(--ink)">{{ t('orders.minutes', { n: receiptOrder.minutes_to_complete }) }}</span>
                    </div>
                </div>

                <div class="receipt-divider"></div>

                <div class="receipt-items">
                    <div v-for="(it, i) in receiptOrder.items" :key="i" class="receipt-line">
                        <span class="order-item-qty">{{ it.qty }}×</span>
                        <span class="receipt-line-name">
                            <span class="receipt-line-title">{{ itemName(it) }}<span v-if="it.variant" class="receipt-variant">{{ it.variant }}</span></span>
                            <span v-if="it.options?.length" class="receipt-line-sub">+ {{ it.options.join(' · ') }}</span>
                            <span v-if="it.note" class="receipt-line-sub receipt-line-note">✎ {{ it.note }}</span>
                        </span>
                        <span v-if="it.line_total != null" class="receipt-line-total">{{ it.line_total }} {{ currencyLabel(receiptOrder.currency, locale) }}</span>
                    </div>
                </div>

                <div v-if="receiptOrder.status === 'CANCELLED' && (receiptOrder.cancellation_reason || receiptOrder.cancelled_at)" class="receipt-note receipt-cancel">
                    <div v-if="receiptOrder.cancellation_reason"><span style="color:var(--muted)">{{ t('orders.cancel_reason') }}:</span> {{ receiptOrder.cancellation_reason }}</div>
                    <div v-if="receiptOrder.cancelled_at" class="receipt-cancel-by">
                        {{ receiptOrder.cancelled_by_name ? t('orders.cancelled_by_at', { name: receiptOrder.cancelled_by_name, time: fmtTime(receiptOrder.cancelled_at) }) : t('orders.cancelled_at', { time: fmtTime(receiptOrder.cancelled_at) }) }}
                    </div>
                </div>

                <div v-if="receiptOrder.note" class="receipt-note">
                    <span style="color:var(--body)">{{ t('orders.note') }}:</span> {{ receiptOrder.note }}
                </div>

                <div class="receipt-divider"></div>

                <div v-if="receiptOrder.subtotal_minor != null" class="receipt-meta receipt-sums">
                    <div class="receipt-meta-row">
                        <span style="color:var(--body)">{{ t('orders.sheet_subtotal') }}</span>
                        <span style="color:var(--ink)">{{ sheetMoney(receiptOrder, receiptOrder.subtotal_minor) }}</span>
                    </div>
                    <div v-if="hasMinor(receiptOrder.discount_minor)" class="receipt-meta-row">
                        <span style="color:var(--body)">{{ t('orders.sheet_discount') }}</span>
                        <span style="color:var(--ink)">{{ sheetMoney(receiptOrder, receiptOrder.discount_minor, { negative: true }) }}</span>
                    </div>
                    <div v-if="hasMinor(receiptOrder.charges_minor)" class="receipt-meta-row">
                        <span style="color:var(--body)">{{ t('orders.sheet_service') }}</span>
                        <span style="color:var(--ink)">{{ sheetMoney(receiptOrder, receiptOrder.charges_minor) }}</span>
                    </div>
                    <div v-if="receiptOrder.tax_minor != null" class="receipt-meta-row">
                        <span style="color:var(--body)">{{ t('orders.sheet_tax') }}</span>
                        <span style="color:var(--ink)">{{ sheetMoney(receiptOrder, receiptOrder.tax_minor) }}</span>
                    </div>
                </div>

                <div class="receipt-total">
                    <span>{{ t('orders.total') }}</span>
                    <span>{{ receiptOrder.total }} {{ currencyLabel(receiptOrder.currency, locale) }}</span>
                </div>

                <div v-if="receiptOrder.payments?.length || hasMinor(receiptOrder.refunded_minor)" class="receipt-meta receipt-payments">
                    <div v-for="(p, i) in receiptOrder.payments" :key="i" class="receipt-meta-row">
                        <span style="color:var(--body)">{{ p.tender_name || t('orders.sheet_payment') }}</span>
                        <span style="color:var(--ink)">{{ sheetMoney(receiptOrder, p.amount_minor) }}</span>
                    </div>
                    <div v-if="hasMinor(receiptOrder.refunded_minor)" class="receipt-meta-row">
                        <span style="color:var(--body)">{{ t('orders.sheet_refunded') }}</span>
                        <span style="color:var(--ink)">{{ sheetMoney(receiptOrder, receiptOrder.refunded_minor, { negative: true }) }}</span>
                    </div>
                </div>
            </div>
        </Dialog>
    </div>

</template>

<style scoped>
/* Colours come only from the shared theme variables and the PrimeVue primary
   scale; nothing here introduces a new hex value. */
.touch { min-height: 44px; }

/* Header */
.live-pill { display: inline-flex; align-items: center; gap: 6px; padding: 4px 11px; border-radius: 20px;
    background: var(--green-soft); color: var(--green); font-size: 13px; font-weight: 600; }
.live-dot { width: 7px; height: 7px; border-radius: 50%; background: var(--green); }
.head-tools { flex: 1 1 320px; justify-content: flex-end; }
.search-box { flex: 1 1 200px; max-width: 320px; }
.search-ico { position: absolute; top: 50%; transform: translateY(-50%); inset-inline-start: 12px;
    color: var(--body); pointer-events: none; display: flex; }

/* Day figures */
.metric-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 12px; }
.metric { min-width: 0; padding: 16px 18px; }
.metric .stat-label { color: var(--body); font-size: 14.5px; }
.metric .stat-num { font-size: clamp(26px, 7vw, 34px); overflow-wrap: anywhere; min-height: 34px; }
.stat-hint { font-size: 13.5px; color: var(--body); margin-top: 6px; }
/* A pending order turns the lead tile into an accent block. */
.metric-hot { background: var(--accent-soft); border-color: var(--accent); }
.metric-hot .stat-label { color: var(--ink); font-weight: 700; }

/* Toolbar */
.orders-toolbar { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: 12px 16px;
    padding: 12px 16px; border-bottom: 1px solid var(--line); }
.tabs { max-width: 100%; overflow-x: auto; }
.tabs button { display: inline-flex; align-items: center; gap: 7px; min-height: 40px; white-space: nowrap; font-size: 14.5px; }
.tab-count { font-size: 12.5px; font-weight: 700; line-height: 1.6; padding: 0 7px; border-radius: 20px;
    background: var(--line); color: var(--ink); }
.tabs button.active .tab-count { background: var(--accent); color: var(--ink); }
.tab-count-hot { background: var(--accent); color: var(--ink); }

/* Table */
.orders-table { min-width: 900px; border-collapse: collapse; }
.orders-table th, .orders-table td { padding: 12px; }
.orders-table th:first-child, .orders-table td:first-child { padding-inline-start: 20px; }
.orders-table th:last-child, .orders-table td:last-child { padding-inline-end: 20px; }
.orders-head th { font-size: 12.5px; font-weight: 600; letter-spacing: .2px;
    color: var(--body); background: var(--page); border-bottom: 1px solid var(--line); }
.orders-row { border-top: 1px solid var(--line); vertical-align: top; transition: background .15s; }
.orders-row:first-child { border-top: 0; }
.orders-row:hover { background: var(--page); }
.sk-row { border-top: 1px solid var(--line); }
.sk-row td { padding-block: 16px; }
/* Waiting orders carry a bar on the start edge, so they are findable by shape
   as well as by the status label. */
.orders-row td:first-child { border-inline-start: 4px solid transparent; }
.row-pending td:first-child { border-inline-start-color: var(--accent); }

.cell-strong { font-weight: 600; color: var(--ink); font-size: 15px; }
.cell-sub { font-size: 13px; color: var(--body); margin-top: 2px; }
/* A phone number broken across two lines stops looking like a phone number. */
.cell-phone { white-space: nowrap; text-align: start; }
.cell-code { font-weight: 700; color: var(--ink); font-size: 15px; font-variant-numeric: tabular-nums; }
.cell-items { max-width: 240px; }
.cell-items .truncate { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.cell-total { font-weight: 700; color: var(--ink); font-size: 15px; font-variant-numeric: tabular-nums; unicode-bidi: isolate; }
.cell-cur { font-weight: 500; color: var(--body); font-size: 13px; }
.tabular { font-variant-numeric: tabular-nums; }
.act { min-height: 44px; }
/* Ink on orange keeps the one-tap action legible at counter distance. */
.act.btn-accent { color: var(--ink); }
.act-icon { width: 44px; height: 44px; }

/* Order type: a coloured dot beside the label (the label carries the meaning) */
.type-tag { display: inline-flex; align-items: center; gap: 7px; color: var(--body); font-size: 14.5px; }
.type-dot { width: 8px; height: 8px; border-radius: 50%; background: var(--muted); flex-shrink: 0; }
.type-delivery { background: var(--accent); }
.type-pickup { background: var(--gray); }
.type-dine_in { background: var(--green); }
/* Deliberately quieter than the status pill: this is provenance, not something
   anybody has to act on. Logical properties so it sits after the type in both
   directions. */
.src-tag {
    display: inline-block;
    margin-inline-start: 8px;
    padding: 1px 7px;
    border-radius: 4px;
    font-size: 12px;
    font-weight: 600;
    line-height: 1.6;
    color: var(--body);
    background: var(--gray-soft);
    vertical-align: middle;
}

/* Empty state */
.empty { display: flex; flex-direction: column; align-items: center; gap: 12px; text-align: center; }
.empty-mark { width: 52px; height: 52px; border-radius: 15px; border: 1px dashed var(--line); background: var(--page);
    display: grid; place-items: center; color: var(--body); }
.empty-title { font-family: var(--font-display); font-weight: 600; font-size: 16.5px; color: var(--ink); }
.empty-body { font-size: 14.5px; color: var(--body); max-width: 340px; }

/* Footer strip */
.orders-foot { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: 12px;
    padding: 12px 16px; background: var(--page); border-top: 1px solid var(--line);
    font-size: 13.5px; color: var(--body); }

/* Customer name → directory record. Looks like text until hovered. */
.cust-link { padding: 0; border: 0; background: none; font: inherit; font-weight: 600; font-size: 15px; cursor: pointer; text-align: start; }
.cust-link:hover { color: var(--p-primary-700); text-decoration: underline; }
/* Order line: quantity leads (inline-start), name follows — isolated so the
   Latin "3×" never gets reordered next to an Arabic name. */
.order-item-qty { flex: none; font-weight: 700; color: var(--p-primary-800); unicode-bidi: isolate; }
/* Neutral badge for the order type inside the receipt sheet. */
.badge-type { background: var(--card); border: 1px solid var(--line); color: var(--body); }

/* Bill / receipt sheet */
.receipt-meta { display: flex; flex-direction: column; gap: 8px; }
.receipt-meta-row { display: flex; align-items: center; justify-content: space-between; gap: 12px; font-size: 14.5px; }
.receipt-divider { height: 1px; background: var(--line); margin: 16px 0; }
.receipt-sums { margin-bottom: 12px; }
.receipt-payments { margin-top: 12px; }
.receipt-items { display: flex; flex-direction: column; gap: 10px; }
.receipt-line { display: flex; align-items: baseline; gap: 8px; font-size: 15px; }
.receipt-line-name { flex: 1 1 auto; color: var(--body); display: flex; flex-direction: column; gap: 2px; min-width: 0; }
.receipt-line-title { color: var(--ink); display: inline-flex; flex-wrap: wrap; align-items: baseline; gap: 6px; }
/* The chosen size/portion — a chip so it reads as one thing with the name,
   never as an add-on. */
.receipt-variant { font-size: 12.5px; font-weight: 600; color: var(--p-primary-800); background: var(--accent-soft);
    padding: 1px 7px; border-radius: 10px; }
.receipt-line-sub { font-size: 13.5px; color: var(--body); }
.receipt-line-note { color: var(--ink); }
.receipt-line-total { flex: none; font-weight: 600; color: var(--ink); unicode-bidi: isolate; }
.receipt-note { margin-top: 14px; font-size: 14px; color: var(--body); }
.receipt-total { display: flex; align-items: center; justify-content: space-between;
    font-size: 17px; font-weight: 700; color: var(--ink); }

/* Briefly highlight a just-arrived order. */
.order-row-new { animation: order-flash 5s ease-out; }
@keyframes order-flash {
    0% { background: var(--accent-soft); }
    100% { background: transparent; }
}
@media (prefers-reduced-motion: reduce) { .order-row-new { animation: none; } }
.receipt-cancel { border-inline-start: 3px solid #d83a2a; }
.date-range { display: flex; flex-wrap: wrap; align-items: flex-end; gap: 8px; }
.date-field { display: flex; flex-direction: column; gap: 4px; font-size: 12px; color: var(--muted); }
.date-field .input { margin-top: 0; width: 160px; height: 38px; }
.date-sep { color: var(--muted); padding-bottom: 9px; }
[dir=rtl] .date-sep { transform: scaleX(-1); }
.pay-tag { display: inline-block; font-size: 11px; font-weight: 600; padding: 1px 7px; border-radius: 6px; margin-top: 3px; }
.receipt-cancel-by { font-size: 12px; color: var(--muted); margin-top: 4px; }

/* Phone: every order becomes a card. Code and status on the first line, the
   items under them, then type/time, customer, and the total beside the actions, so
   the one-tap "Received" button is never off-screen. */
@media (max-width: 760px) {
    .orders-table { min-width: 0; display: block; }
    .orders-table thead { position: absolute; width: 1px; height: 1px; overflow: hidden; clip-path: inset(50%); }
    .orders-table tbody { display: block; }
    .orders-table tbody tr, .orders-table tbody td { display: block; }
    .orders-table td { padding: 0; }
    .orders-table td:first-child, .orders-table td:last-child { padding-inline: 0; }
    .orders-table .state-row td { padding: 40px 16px; }
    .orders-table .sk-row { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; padding: 16px; }
    .orders-table .orders-row {
        display: grid; grid-template-columns: minmax(0, 1fr) auto;
        grid-template-areas: "code status" "items items" "type time" "cust cust" "total actions";
        gap: 8px 12px; align-items: center; padding: 14px 16px;
        border-inline-start: 4px solid transparent;
    }
    .orders-table .orders-row.row-pending { border-inline-start-color: var(--accent); }
    .orders-table .orders-row td:first-child { border-inline-start: 0; }
    .c-code { grid-area: code; }
    .c-status { grid-area: status; justify-self: end; }
    .c-items { grid-area: items; max-width: none; }
    .c-items .truncate { white-space: normal; }
    .c-type { grid-area: type; }
    .c-cust { grid-area: cust; min-width: 0; }
    .c-time { grid-area: time; text-align: end; }
    .c-total { grid-area: total; }
    .c-actions { grid-area: actions; }
    .orders-toolbar { padding: 12px; }
}
</style>
