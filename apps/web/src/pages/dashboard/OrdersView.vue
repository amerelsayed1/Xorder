<script setup>
import { ref, computed, watch, onMounted, onUnmounted } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRouter } from 'vue-router'
import { useCaps } from '../../lib/useCaps.js'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import { currencyLabel } from '../../lib/currency.js'
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
const page = ref(1)
const updating = ref(null)
const newIds = ref(new Set())
const readAt = ref(null) // when the list was last read from the server
const receiptOrder = ref(null) // order shown in the bill/receipt sheet, or null
let pollTimer, offTick, searchTimer

const filtersActive = computed(() => !!statusFilter.value || !!typeFilter.value || !!query.value.trim())
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
        page: page.value,
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
    page.value = 1
    load()
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
            <div>
                <div class="flex items-center gap-3">
                    <h1 class="page-title">{{ t('orders.title') }}</h1>
                    <span class="live-pill"><span class="live-dot"></span>{{ t('orders.live') }}</span>
                </div>
                <p class="page-sub">{{ t('orders.subtitle') }}</p>
            </div>
            <div class="flex items-center gap-2">
                <div class="relative" style="width:270px;max-width:100%">
                    <span class="search-ico"><Icon name="search" :size="17" /></span>
                    <input v-model="query" :placeholder="t('orders.search_placeholder')" class="input" style="margin-top:0;padding-inline-start:38px" />
                </div>
                <button class="btn btn-ghost" :disabled="loading" @click="load()">
                    <Icon name="refresh" :size="16" />{{ t('orders.refresh') }}
                </button>
            </div>
        </div>

        <!-- The day at a glance. Unfiltered on purpose — these describe the
             restaurant's day, not whatever the toolbar is currently showing. -->
        <div class="metric-grid">
            <div class="stat">
                <div class="stat-label">{{ t('orders.m_new') }}</div>
                <div class="stat-num"><Skeleton v-if="!metrics" h="30px" w="52px" /><template v-else>{{ metrics.new_orders }}</template></div>
                <div class="stat-hint">{{ t('orders.m_new_hint') }}</div>
            </div>
            <div class="stat">
                <div class="stat-label">{{ t('orders.m_today') }}</div>
                <div class="stat-num"><Skeleton v-if="!metrics" h="30px" w="52px" /><template v-else>{{ metrics.orders_today }}</template></div>
                <div class="stat-hint">{{ t('orders.m_since_midnight') }}</div>
            </div>
            <div class="stat">
                <div class="stat-label">{{ t('orders.m_completed') }}</div>
                <div class="stat-num"><Skeleton v-if="!metrics" h="30px" w="52px" /><template v-else>{{ metrics.completed_today }}</template></div>
                <div class="stat-hint">{{ t('orders.status.COMPLETED') }}</div>
            </div>
            <div class="stat">
                <div class="stat-label">{{ t('orders.m_sales') }}</div>
                <div class="stat-num"><Skeleton v-if="!metrics" h="30px" w="90px" /><template v-else>{{ metrics.sales_today }}</template></div>
                <div class="stat-hint">{{ salesCurrency }}</div>
            </div>
        </div>

        <div class="card overflow-hidden">
            <!-- Toolbar: status tabs carry live counts, type tabs narrow further -->
            <div class="orders-toolbar">
                <div class="segmented tabs">
                    <button :class="{ active: statusFilter === '' }" @click="setFilter('')">
                        {{ t('common.all') }}
                        <span v-if="statusCount('all') !== null" class="tab-count">{{ statusCount('all') }}</span>
                    </button>
                    <button v-for="s in STATUSES" :key="s" :class="{ active: statusFilter === s }" @click="setFilter(s)">
                        {{ t('orders.status.' + s) }}
                        <span v-if="statusCount(s) !== null" class="tab-count">{{ statusCount(s) }}</span>
                    </button>
                </div>
                <div class="flex items-center gap-2">
                    <span class="text-sm" style="color:var(--muted)">{{ t('orders.type') }}</span>
                    <div class="segmented tabs">
                        <button :class="{ active: typeFilter === '' }" @click="setTypeFilter('')">{{ t('common.all') }}</button>
                        <button v-for="ty in ORDER_TYPES" :key="ty" :class="{ active: typeFilter === ty }" @click="setTypeFilter(ty)">
                            {{ t('order_type.' + ty) }}
                        </button>
                    </div>
                </div>
            </div>

            <!-- Table -->
            <div class="overflow-x-auto">
                <table class="w-full text-sm" style="min-width:900px">
                    <thead>
                        <tr class="orders-head">
                            <th class="px-5 py-3 text-start">{{ t('orders.order') }}</th>
                            <th class="px-3 py-3 text-start">{{ t('orders.items') }}</th>
                            <th class="px-3 py-3 text-start">{{ t('orders.type') }}</th>
                            <th class="px-3 py-3 text-start">{{ t('orders.customer') }}</th>
                            <th class="px-3 py-3 text-start">{{ t('orders.time') }}</th>
                            <th class="px-3 py-3 text-start">{{ t('orders.total') }}</th>
                            <th class="px-3 py-3 text-start">{{ t('common.status') }}</th>
                            <th class="px-5 py-3 text-end">{{ t('common.actions') }}</th>
                        </tr>
                    </thead>
                    <tbody>
                        <template v-if="loading">
                            <tr v-for="n in 6" :key="'sk' + n" class="border-t" :style="{ borderColor: 'var(--line)' }">
                                <td v-for="c in 8" :key="c" class="px-5 py-4"><Skeleton h="14px" :w="c === 8 ? '60%' : '80%'" /></td>
                            </tr>
                        </template>
                        <!-- v-else so a pending filter switch shows only the shimmer,
                             never the previous filter's rows underneath it. -->
                        <template v-else-if="rows.length">
                            <tr v-for="order in rows" :key="order.id" class="orders-row" :class="{ 'order-row-new': newIds.has(order.id) }">
                                <td class="px-5 py-3 whitespace-nowrap cell-code">{{ order.code }}</td>
                                <td class="px-3 py-3 cell-items">
                                    <div class="cell-strong truncate">{{ itemSummary(order) }}</div>
                                    <div class="cell-sub">{{ t('orders.items_n', { n: itemCount(order) }) }}</div>
                                </td>
                                <td class="px-3 py-3 whitespace-nowrap">
                                    <span v-if="order.order_type" class="type-tag">
                                        <span class="type-dot" :class="'type-' + order.order_type"></span>{{ orderTypeLabel(order) }}
                                    </span>
                                    <span v-else style="color:var(--muted)">—</span>
                                    <!-- Where it was rung up, when that is not the QR
                                         menu. A till sale and a diner's phone order look
                                         identical in every other column, and they are not
                                         the same thing to a manager reading this list. -->
                                    <span v-if="order.source === 'pos'" class="src-tag">{{ t('order_source.pos') }}</span>
                                </td>
                                <td class="px-3 py-3">
                                    <button v-if="canOpenCustomer(order)" type="button" class="cust-link cell-strong" @click="openCustomer(order)">{{ order.customer_name || '—' }}</button>
                                    <div v-else class="cell-strong">{{ order.customer_name || '—' }}</div>
                                    <div v-if="order.customer_phone" class="cell-sub cell-phone"><bdi dir="ltr">{{ order.customer_phone }}</bdi></div>
                                </td>
                                <td class="px-3 py-3 whitespace-nowrap">
                                    <div class="cell-strong tabular">{{ fmtClock(order.created_at) }}</div>
                                    <div class="cell-sub">{{ fmtTime(order.created_at) }}</div>
                                </td>
                                <td class="px-3 py-3 whitespace-nowrap cell-total">
                                    {{ order.total }} <span class="cell-cur">{{ currencyLabel(order.currency, locale) }}</span>
                                </td>
                                <td class="px-3 py-3">
                                    <span class="badge" :class="badgeClass[order.status]"><span class="dot"></span>{{ t('orders.status.' + order.status) }}</span>
                                </td>
                                <td class="px-5 py-3 text-end whitespace-nowrap">
                                    <div class="inline-flex items-center gap-2">
                                        <template v-if="canUpdate">
                                            <!-- The move-forward action is the one staff reach for all day, so it
                                                 keeps its label. Cancel is rare and destructive: it stays available
                                                 but shrinks to an icon rather than crowding the row. -->
                                            <button v-if="advanceActions(order).includes('COMPLETED')"
                                                class="btn btn-accent btn-sm"
                                                :disabled="updating === order.id" @click="setStatus(order, 'COMPLETED')">
                                                <Icon name="check" :size="14" />{{ t(actionLabel.COMPLETED) }}
                                            </button>
                                            <button v-if="advanceActions(order).includes('CANCELLED')"
                                                type="button" class="icon-btn icon-btn-danger"
                                                :title="t('orders.cancel_order')" :aria-label="t('orders.cancel_order')"
                                                :disabled="updating === order.id" @click="setStatus(order, 'CANCELLED')">
                                                <Icon name="close" :size="15" />
                                            </button>
                                        </template>
                                        <button type="button" class="btn btn-ghost btn-sm" @click="receiptOrder = order">
                                            <Icon name="receipt" :size="14" />{{ t('orders.details') }}
                                        </button>
                                    </div>
                                </td>
                            </tr>
                        </template>
                        <tr v-else-if="failed === 'plan'">
                            <td colspan="8" class="px-6 py-14 text-center text-sm" style="color:var(--muted)">{{ t('orders.not_in_plan') }}</td>
                        </tr>
                        <tr v-else-if="failed">
                            <td colspan="8" class="px-6 py-6"><ErrorState @retry="load()" /></td>
                        </tr>
                        <tr v-else>
                            <td colspan="8" class="px-6 py-14">
                                <div class="empty">
                                    <div class="empty-mark"></div>
                                    <div class="empty-title">{{ filtersActive ? t('orders.no_match_title') : t('orders.none') }}</div>
                                    <p v-if="filtersActive" class="empty-body">{{ t('orders.no_match_body') }}</p>
                                    <button v-if="filtersActive" class="btn btn-accent" @click="resetFilters">{{ t('orders.reset') }}</button>
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
                <div class="flex items-center gap-3">
                    <template v-if="meta && meta.last_page > 1">
                        <button class="btn btn-ghost btn-sm" :disabled="meta.current_page <= 1" @click="goToPage(meta.current_page - 1)">
                            {{ t('common.previous') }}
                        </button>
                        <span class="tabular">{{ meta.current_page }} / {{ meta.last_page }}</span>
                        <button class="btn btn-ghost btn-sm" :disabled="meta.current_page >= meta.last_page" @click="goToPage(meta.current_page + 1)">
                            {{ t('common.next') }}
                        </button>
                    </template>
                    <span v-if="updatedAt">{{ t('orders.updated_at', { time: updatedAt }) }}</span>
                </div>
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
                    <div v-if="receiptOrder.order_type" class="receipt-meta-row">
                        <span style="color:var(--muted)">{{ t('orders.type') }}</span>
                        <span class="badge badge-type">{{ orderTypeLabel(receiptOrder) }}</span>
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
/* Header */
.live-pill { display: inline-flex; align-items: center; gap: 6px; padding: 4px 11px; border-radius: 20px;
    background: var(--green-soft); color: var(--green); font-size: 12.5px; font-weight: 600; }
.live-dot { width: 7px; height: 7px; border-radius: 50%; background: var(--green); }
.search-ico { position: absolute; top: 50%; transform: translateY(-50%); inset-inline-start: 12px;
    color: var(--muted); pointer-events: none; display: flex; }

/* Day figures */
.metric-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(190px, 1fr)); gap: 14px; }
.stat-hint { font-size: 12.5px; color: var(--muted); margin-top: 6px; }

/* Toolbar */
.orders-toolbar { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: 14px;
    padding: 13px 16px; border-bottom: 1px solid var(--line); }
.tabs button { display: inline-flex; align-items: center; gap: 7px; }
.tab-count { font-size: 11.5px; font-weight: 600; line-height: 1.5; padding: 0 6px; border-radius: 20px;
    background: var(--line); color: var(--muted); }
.tabs button.active .tab-count { background: var(--accent); color: #fff; }

/* Table */
.orders-head th { font-size: 11px; font-weight: 600; text-transform: uppercase; letter-spacing: .3px;
    color: var(--muted); background: var(--page); border-bottom: 1px solid var(--line); }
.orders-row { border-top: 1px solid var(--line); vertical-align: top; }
.orders-row:first-child { border-top: 0; }
.orders-row:hover { background: var(--page); }
.cell-strong { font-weight: 600; color: var(--ink); }
.cell-sub { font-size: 12px; color: var(--muted); margin-top: 2px; }
/* A phone number broken across two lines stops looking like a phone number. */
.cell-phone { white-space: nowrap; text-align: start; }
.cell-code { font-weight: 600; color: var(--body); font-variant-numeric: tabular-nums; }
.cell-items { max-width: 210px; }
.cell-items .truncate { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.cell-total { font-weight: 600; color: var(--ink); font-variant-numeric: tabular-nums; unicode-bidi: isolate; }
.cell-cur { font-weight: 500; color: var(--muted); font-size: 12.5px; }
.tabular { font-variant-numeric: tabular-nums; }

/* Order type: a coloured dot rather than a fourth badge competing with status */
.type-tag { display: inline-flex; align-items: center; gap: 7px; color: var(--body); }
.type-dot { width: 7px; height: 7px; border-radius: 50%; background: var(--muted); flex-shrink: 0; }
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
    font-size: 11px;
    font-weight: 600;
    line-height: 1.6;
    color: var(--muted);
    background: var(--surface-2, rgba(127, 127, 127, .12));
    vertical-align: middle;
}

/* Empty state */
.empty { display: flex; flex-direction: column; align-items: center; gap: 12px; text-align: center; }
.empty-mark { width: 52px; height: 52px; border-radius: 15px; border: 1px dashed var(--line); background: var(--page); }
.empty-title { font-family: var(--font-display); font-weight: 600; font-size: 16.5px; color: var(--ink); }
.empty-body { font-size: 14px; color: var(--muted); max-width: 340px; }

/* Footer strip */
.orders-foot { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: 12px;
    padding: 12px 16px; background: var(--page); border-top: 1px solid var(--line);
    font-size: 13px; color: var(--muted); }

.btn-cancel { color: var(--red); }
/* Neutral badge for the order type inside the receipt sheet. */
.badge-type { background: var(--card); border: 1px solid var(--line); color: var(--body); }
/* Customer name → directory record. Looks like text until hovered. */
.cust-link { padding: 0; border: 0; background: none; font: inherit; cursor: pointer; text-align: start; }
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
.receipt-line-name { flex: 1 1 auto; color: var(--body); display: flex; flex-direction: column; gap: 2px; min-width: 0; }
.receipt-line-title { color: var(--ink); display: inline-flex; flex-wrap: wrap; align-items: baseline; gap: 6px; }
/* The chosen size/portion — a chip so it reads as one thing with the name,
   never as an add-on. */
.receipt-variant { font-size: 12px; font-weight: 600; color: var(--accent-dark); background: var(--accent-soft);
    padding: 1px 7px; border-radius: 10px; }
.receipt-line-sub { font-size: 12.5px; color: var(--muted); }
.receipt-line-note { color: var(--body); }
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
.receipt-cancel { border-inline-start: 3px solid #d83a2a; }
.receipt-cancel-by { font-size: 12px; color: var(--muted); margin-top: 4px; }
</style>
