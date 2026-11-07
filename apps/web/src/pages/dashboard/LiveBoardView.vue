<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { useI18n } from 'vue-i18n'
import { useAuth } from '@xorder/api-client/auth.js'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import { currencyLabel } from '../../lib/currency.js'
import Skeleton from '@xorder/ui/Skeleton.vue'
import Dialog from '@xorder/ui/Dialog.vue'
import { confirm, confirmWithInput } from '@xorder/ui/confirm.js'
import { alert } from '@xorder/ui/alert.js'
import { toast } from '@xorder/ui/toast.js'
import { useRealtime } from '../../stores/realtime.js'

const { t, locale } = useI18n()
const auth = useAuth()
const rt = useRealtime()
const feats = computed(() => auth.restaurant?.features || [])
// Two gates per column, and both must pass: the plan flag says the restaurant
// bought the capability, the tenant capability says this person may use it. A
// waiter with tables.view but no bills.view gets a floor grid and no bill feed,
// rather than a 403 that blanks the whole board.
// live.view grants the whole board; the per-section views also reach it, so a
// manager who already holds orders.view keeps the board without a second grant.
// Mirrors the server's orders.read / bills.read / tables.live gates.
const onLiveBoard = (own) => auth.can('live.view') || auth.can(own)
const showRequests = computed(() => feats.value.includes('bill_requests') && onLiveBoard('bills.view'))
const showTables = computed(() => feats.value.includes('table_management') && onLiveBoard('tables.view'))
const showOrders = computed(() => feats.value.includes('system_ordering') && onLiveBoard('orders.view'))

// Whether the action buttons on each column are offered at all. The API is the
// authority; hiding them just avoids a button that can only ever 403.
const canActRequests = computed(() => !auth.isReadOnly && auth.can('bills.update'))
const canActOrders = computed(() => !auth.isReadOnly && auth.can('orders.update'))
const canActTables = computed(() => !auth.isReadOnly && auth.can('tables.update'))

const loading = ref(true)
const updating = ref(null)
let pollTimer, offTick

// Replace a column's list, flagging genuinely-new ids so they briefly highlight.
function applyList(listRef, next, newIdsRef, highlight) {
    if (highlight) {
        const known = new Set(listRef.value.map((r) => r.id))
        const fresh = next.filter((r) => !known.has(r.id)).map((r) => r.id)
        if (fresh.length) {
            const ids = new Set(newIdsRef.value)
            fresh.forEach((id) => ids.add(id))
            newIdsRef.value = ids
            setTimeout(() => {
                const s = new Set(newIdsRef.value)
                fresh.forEach((id) => s.delete(id))
                newIdsRef.value = s
            }, 6000)
        }
    }
    listRef.value = next
}

// ---------- Bill requests (open only, oldest first) ----------
const requests = ref([])
const requestNewIds = ref(new Set())
const reqBadge = { REQUESTED: 'badge-amber', SEEN: 'badge-indigo', IN_PROGRESS: 'badge-indigo' }
// Table ids that currently have an open request → they pulse on the floor grid.
const requestByTable = computed(() => {
    const m = new Map()
    for (const r of requests.value) if (r.table_id != null && !m.has(r.table_id)) m.set(r.table_id, r)
    return m
})

async function loadRequests(highlight) {
    if (!showRequests.value) return
    const { data } = await api.get('api/dashboard/bill-requests')
    applyList(requests, data.data || [], requestNewIds, highlight)
}

async function setRequestStatus(bill, status) {
    if (status === 'CANCELLED' && ! await confirmCancel('req')) return
    updating.value = 'r' + bill.id
    try {
        await ensureCsrf()
        await api.patch(`api/dashboard/bill-requests/${bill.id}/status`, { status })
        // Drops off the board once it leaves the open set.
        if (['COMPLETED', 'CANCELLED'].includes(status)) {
            requests.value = requests.value.filter((r) => r.id !== bill.id)
        } else {
            const i = requests.value.findIndex((r) => r.id === bill.id)
            if (i !== -1) requests.value[i] = { ...requests.value[i], status }
        }
        loadTables(false) // a cleared request stops the table pulsing
        toast(t('common.saved'))
    } catch { alert(t('req.update_failed')) }
    finally { updating.value = null }
}

// ---------- Tables (live floor grid) ----------
const tables = ref([])

async function loadTables(highlight) {
    if (!showTables.value) return
    const { data } = await api.get('api/dashboard/tables/live')
    tables.value = data.data || []
    void highlight
}

// ---------- New table orders (shares the left feed with bill requests) ----------
const orders = ref([])
const orderNewIds = ref(new Set())

async function loadOrders(highlight) {
    if (!showOrders.value) return
    // New (unacknowledged) orders placed from a table. They sit in the left feed
    // next to bill requests and drive the floor-grid flash.
    const { data } = await api.get('api/dashboard/orders', { params: { status: 'NEW' } })
    const list = (data.data || []).filter((o) => o.table_id != null)
    applyList(orders, list, orderNewIds, highlight)
}

// Table id → its live-grid row, so a feed order can show its table label/area.
const tableById = computed(() => {
    const m = new Map()
    for (const tbl of tables.value) m.set(tbl.id, tbl)
    return m
})

// Unified left feed: open bill requests + new table orders, grouped by table so
// everything happening on one table sits together. Groups (and the items within
// them) are ordered oldest-first, keeping the longest-waiting table on top.
const hasFeed = computed(() => showRequests.value || showOrders.value)
const feedGroups = computed(() => {
    const groups = new Map()
    const ensure = (id, label, area) => {
        if (!groups.has(id)) groups.set(id, { id, label, area, items: [] })
        return groups.get(id)
    }
    if (showRequests.value) for (const b of requests.value) {
        const tbl = tableById.value.get(b.table_id)
        const g = ensure(b.table_id ?? 'r' + b.id, tbl?.label || b.table_label || '—', tbl ? areaName(tbl) : areaName(b))
        g.items.push({ type: 'request', key: 'r' + b.id, ts: b.requested_at, req: b })
    }
    if (showOrders.value) for (const o of orders.value) {
        const tbl = tableById.value.get(o.table_id)
        const g = ensure(o.table_id, tbl?.label || '#' + o.table_id, tbl ? areaName(tbl) : '')
        g.items.push({ type: 'order', key: 'o' + o.id, ts: o.created_at, order: o })
    }
    const arr = [...groups.values()]
    for (const g of arr) g.items.sort((a, b) => new Date(a.ts) - new Date(b.ts))
    return arr.sort((a, b) => new Date(a.items[0]?.ts || 0) - new Date(b.items[0]?.ts || 0))
})
const feedCount = computed(() => feedGroups.value.reduce((n, g) => n + g.items.length, 0))
const feedIsNew = (it) => (it.type === 'request' ? requestNewIds.value.has(it.req.id) : orderNewIds.value.has(it.order.id))

// ---------- Table modal: that table's active orders ----------
const openTable = ref(null)
const modalOrders = ref([])
const modalLoading = ref(false)
const ORDER_NEXT = { NEW: ['COMPLETED', 'CANCELLED'] }
const orderActionLabel = { COMPLETED: 'orders.complete', CANCELLED: 'orders.cancel_order' }
const orderBadge = { NEW: 'badge-amber' }
const ACTIVE = ['NEW']
// The open bill request (if any) for the table whose modal is showing.
const modalRequest = computed(() => (openTable.value ? requestByTable.value.get(openTable.value.id) || null : null))

async function openTableModal(tbl) {
    openTable.value = tbl
    modalOrders.value = []
    if (!showOrders.value) return
    modalLoading.value = true
    try {
        const { data } = await api.get('api/dashboard/orders', { params: { table_id: tbl.id } })
        modalOrders.value = (data.data || [])
            .filter((o) => ACTIVE.includes(o.status))
            .sort((a, b) => new Date(a.created_at) - new Date(b.created_at))
    } catch { /* leave empty; the panel shows the empty state */ }
    finally { modalLoading.value = false }
}
function closeModal() { openTable.value = null; modalOrders.value = [] }

async function setOrderStatus(order, status) {
    const payload = { status }
    if (status === 'CANCELLED') {
        // Optional reason; null means the user backed out.
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
    updating.value = 'o' + order.id
    try {
        await ensureCsrf()
        await api.patch(`api/dashboard/orders/${order.id}/status`, payload)
        // Drops off both the modal and the left feed once it leaves the NEW set.
        modalOrders.value = modalOrders.value.filter((o) => o.id !== order.id)
        orders.value = orders.value.filter((o) => o.id !== order.id)
        loadTables(false) // refresh the card's active-order count / flash
        toast(t('common.saved'))
    } catch { alert(t('orders.update_failed')) }
    finally { updating.value = null }
}

async function finishTableVisit(status) {
    if (!openTable.value) return
    const closing = status === 'CLOSED'
    const ok = await confirm({
        title: t(closing ? 'live.close_visit_title' : 'live.cancel_visit_title'),
        message: t(closing ? 'live.close_visit_message' : 'live.cancel_visit_message'),
        confirmText: t(closing ? 'live.close_visit' : 'live.cancel_visit'),
        cancelText: t('common.back'),
        danger: !closing,
    })
    if (!ok) return

    updating.value = 'visit-' + openTable.value.id
    try {
        await api.post(`api/dashboard/tables/${openTable.value.id}/visit/finish`, { status })
        closeModal()
        await refresh(false)
        toast(t('live.visit_finished'))
    } catch { alert(t('live.visit_finish_failed')) }
    finally { updating.value = null }
}

function confirmCancel(ns) {
    return confirm({
        title: t(ns === 'req' ? 'req.act_cancel' : 'orders.cancel_title'),
        message: t('orders.cancel_message'),
        confirmText: t(ns === 'req' ? 'req.act_cancel' : 'orders.cancel_order'),
        cancelText: t('common.back'),
        danger: true,
    })
}

async function refresh(highlight) {
    try { await Promise.all([loadRequests(highlight), loadTables(highlight), loadOrders(highlight)]) } catch { /* keep view */ }
}

onMounted(async () => {
    await refresh(false)
    loading.value = false
    // Refresh the instant the shared pulse detects new orders/requests. A slower
    // fallback still catches status changes made by other staff.
    offTick = rt.onTick(() => { if (!document.hidden) refresh(true) })
    pollTimer = setInterval(() => { if (!document.hidden) refresh(true) }, 20000)
})
onUnmounted(() => { clearInterval(pollTimer); offTick?.() })

const areaName = (b) => (locale.value === 'ar' ? (b.area_name_ar || b.area_name_en) : (b.area_name_en || b.area_name_ar)) || ''
// R1: line name in the current locale; POS lines carry both, older/QR lines
// fall back to the single `name` so nothing renders blank.
const itemName = (it) => (locale.value === 'ar' ? (it.name_ar || it.name_en) : (it.name_en || it.name_ar)) || it.name || ''
function fmtTime(iso) {
    if (!iso) return ''
    const d = new Date(iso)
    const diffMin = Math.round((d.getTime() - Date.now()) / 60000)
    const rtf = new Intl.RelativeTimeFormat(locale.value, { numeric: 'auto' })
    if (Math.abs(diffMin) < 60) return rtf.format(diffMin, 'minute')
    if (Math.abs(diffMin) < 60 * 24) return rtf.format(Math.round(diffMin / 60), 'hour')
    return d.toLocaleString(locale.value, { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' })
}
const panelDir = computed(() => (locale.value === 'ar' ? 'rtl' : 'ltr'))
</script>

<template>
    <div class="space-y-4 live-page">
        <div>
            <h1 class="page-title">{{ t('live.title') }}</h1>
            <p class="page-sub" style="color:var(--body)">{{ t('live.subtitle') }}</p>
        </div>

        <div v-if="loading" class="live-grid" aria-busy="true">
            <div v-for="n in 2" :key="'sk' + n" class="card p-4 space-y-3">
                <Skeleton h="20px" w="40%" /><Skeleton h="84px" w="100%" /><Skeleton h="84px" w="100%" />
            </div>
        </div>

        <div v-else-if="!hasFeed && !showTables" class="card px-5 py-12 text-center" style="color:var(--body)">
            <i class="pi pi-bolt block mb-2" style="font-size:24px" aria-hidden="true"></i>
            {{ t('live.none') }}
        </div>

        <!-- Two panels: the incoming feed (orders + bill requests) on the left,
             tables floor on the right. dir=ltr on the wrapper fixes that order;
             each panel restores locale dir. -->
        <div v-else class="live-grid" :class="{ 'live-grid-one': !hasFeed || !showTables }" dir="ltr">
            <!-- Incoming feed: new table orders + open bill requests -->
            <section v-if="hasFeed" class="live-col card" :dir="panelDir" aria-labelledby="live-feed-title">
                <header class="live-col-head">
                    <h2 id="live-feed-title" class="live-col-title">{{ t('live.requests_col') }}</h2>
                    <span class="live-count" :class="{ 'live-count-hot': feedCount }">{{ feedCount }}</span>
                </header>
                <div v-if="!feedCount" class="live-empty">
                    <i class="pi pi-check-circle block mb-2" style="font-size:24px" aria-hidden="true"></i>
                    {{ t('live.feed_empty') }}
                </div>
                <div v-else class="live-list">
                    <!-- One block per table: its new orders + open bill requests -->
                    <section v-for="g in feedGroups" :key="g.id" class="feed-group">
                        <header class="feed-group-head">
                            <strong>{{ t('req.table') }} {{ g.label }}</strong>
                            <span v-if="g.area" class="live-sub">{{ g.area }}</span>
                            <span class="feed-group-count">{{ g.items.length }}</span>
                        </header>
                        <template v-for="it in g.items" :key="it.key">
                            <!-- Bill request -->
                            <article v-if="it.type === 'request'" class="req-card req-card-bill" :class="{ 'req-card-new': feedIsNew(it) }">
                                <div class="req-top">
                                    <span class="req-kind req-kind-bill"><i class="pi pi-receipt" aria-hidden="true"></i>{{ t('req.bill') }}</span>
                                    <span class="badge" :class="reqBadge[it.req.status]">{{ t('req.status.' + it.req.status) }}</span>
                                </div>
                                <div v-if="it.req.customer_note" class="req-line">{{ it.req.customer_note }}</div>
                                <div class="live-time"><i class="pi pi-clock" aria-hidden="true"></i>{{ t('req.waiting', { time: fmtTime(it.req.requested_at) }) }}</div>
                                <div v-if="canActRequests" class="live-actions">
                                    <button class="live-primary" :disabled="updating === 'r' + it.req.id" @click="setRequestStatus(it.req, 'COMPLETED')">
                                        <i class="pi pi-check" aria-hidden="true"></i>{{ t('orders.complete') }}
                                    </button>
                                    <button class="live-cancel" :disabled="updating === 'r' + it.req.id" @click="setRequestStatus(it.req, 'CANCELLED')">{{ t('req.act_cancel') }}</button>
                                </div>
                            </article>
                            <!-- New table order -->
                            <article v-else class="req-card req-card-order" :class="{ 'req-card-new': feedIsNew(it) }">
                                <div class="req-top">
                                    <span class="req-kind req-kind-order"><i class="pi pi-shopping-bag" aria-hidden="true"></i>{{ t('orders.order') }} <strong>{{ it.order.code }}</strong></span>
                                    <span class="badge" :class="orderBadge[it.order.status]">{{ t('orders.status.' + it.order.status) }}</span>
                                </div>
                                <div class="live-time"><i class="pi pi-clock" aria-hidden="true"></i>{{ fmtTime(it.order.created_at) }}<template v-if="it.order.customer_name"> · {{ it.order.customer_name }}</template></div>
                                <ul class="live-order-items">
                                    <li v-for="(itm, i) in it.order.items" :key="i">
                                        <span class="live-qty">{{ itm.qty }}×</span> {{ itm.name }}<span v-if="itm.variant" class="live-variant">{{ itm.variant }}</span>
                                        <div v-if="itm.options?.length" class="live-item-sub">+ {{ itm.options.join(' · ') }}</div>
                                        <div v-if="itm.note" class="live-item-sub live-item-note"><i class="pi pi-pencil" aria-hidden="true"></i> {{ itm.note }}</div>
                                    </li>
                                </ul>
                                <div class="live-total">{{ it.order.total }} {{ currencyLabel(it.order.currency, locale) }}</div>
                                <div v-if="canActOrders && !it.order.table_visit_id" class="live-actions">
                                    <button v-for="next in ORDER_NEXT[it.order.status] || []" :key="next"
                                        :class="next === 'CANCELLED' ? 'live-cancel' : 'live-primary'"
                                        :disabled="updating === 'o' + it.order.id" @click="setOrderStatus(it.order, next)">
                                        <i v-if="next !== 'CANCELLED'" class="pi pi-check" aria-hidden="true"></i>{{ t(orderActionLabel[next]) }}
                                    </button>
                                </div>
                            </article>
                        </template>
                    </section>
                </div>
            </section>

            <!-- Tables floor grid -->
            <section v-if="showTables" class="live-col card" :dir="panelDir" aria-labelledby="live-tables-title">
                <header class="live-col-head">
                    <h2 id="live-tables-title" class="live-col-title">{{ t('live.tables_col') }}</h2>
                    <span class="live-count live-count-neutral">{{ tables.length }}</span>
                </header>
                <div v-if="!tables.length" class="live-empty">{{ t('live.no_tables') }}</div>
                <div v-else class="tables-grid">
                    <!-- Each table says what it needs in words and an icon, not only
                         by flashing: bill request, new order, in service, occupied, free. -->
                    <button v-for="tbl in tables" :key="tbl.id" type="button" class="tcard"
                        :class="{ 'tcard-flash': tbl.has_request, 'tcard-flash-order': !tbl.has_request && tbl.has_new_order, 'tcard-free': !tbl.occupied && !tbl.has_request && !tbl.has_new_order && !tbl.active_orders }"
                        @click="openTableModal(tbl)">
                        <span class="tcard-body">
                            <span class="tcard-toprow">
                                <span class="tcard-area">{{ areaName(tbl) }}</span>
                            </span>
                            <span class="tcard-bottom">
                                <span class="tcard-name">{{ t('req.table') }} {{ tbl.label }}</span>
                                <span class="tcard-sub">
                                    <span v-if="tbl.has_request" class="tcard-req"><i class="pi pi-receipt" aria-hidden="true"></i>{{ requestByTable.get(tbl.id)?.customer_note || t('req.bill') }}</span>
                                    <span v-else-if="tbl.has_new_order" class="tcard-neworder"><i class="pi pi-bell" aria-hidden="true"></i>{{ t('orders.status.NEW') }}<template v-if="tbl.active_orders"> · {{ t('live.active_orders_n', { n: tbl.active_orders }) }}</template></span>
                                    <span v-else-if="tbl.active_orders"><i class="pi pi-clock" aria-hidden="true"></i>{{ t('live.active_orders_n', { n: tbl.active_orders }) }}</span>
                                    <span v-else-if="tbl.occupied"><i class="pi pi-user" aria-hidden="true"></i>{{ t('live.occupied') }}</span>
                                    <span v-else class="tcard-idle"><i class="pi pi-circle" aria-hidden="true"></i>{{ t('live.available') }}</span>
                                </span>
                            </span>
                        </span>
                    </button>
                </div>
            </section>
        </div>

        <!-- Per-table orders modal -->
        <Dialog v-if="openTable" :title="t('req.table') + ' ' + openTable.label" :subtitle="t('live.table_orders_sub')" @close="closeModal">
            <div class="tm-body">
                <!-- Open bill request for this table, if any -->
                <div v-if="modalRequest" class="tm-req">
                    <div class="tm-req-line"><i class="pi pi-receipt" aria-hidden="true"></i>{{ modalRequest.customer_note || t('req.bill') }}</div>
                    <div class="live-time"><i class="pi pi-clock" aria-hidden="true"></i>{{ t('req.waiting', { time: fmtTime(modalRequest.requested_at) }) }}</div>
                    <div v-if="canActRequests" class="live-actions">
                        <button class="live-primary" :disabled="updating === 'r' + modalRequest.id" @click="setRequestStatus(modalRequest, 'COMPLETED')">
                            <i class="pi pi-check" aria-hidden="true"></i>{{ t('orders.complete') }}
                        </button>
                        <button class="live-cancel" :disabled="updating === 'r' + modalRequest.id" @click="setRequestStatus(modalRequest, 'CANCELLED')">{{ t('req.act_cancel') }}</button>
                    </div>
                </div>

                <div v-if="modalLoading" class="space-y-2">
                    <Skeleton h="64px" w="100%" /><Skeleton h="64px" w="100%" />
                </div>
                <div v-else-if="!modalOrders.length" class="live-empty" style="padding:20px 0">{{ t('live.no_orders_table') }}</div>
                <article v-for="o in modalOrders" v-else :key="o.id" class="tm-order">
                    <div class="req-top">
                        <div class="req-meta">
                            <strong>{{ o.code }}</strong>
                            <span class="live-sub">{{ o.customer_name || '—' }}<template v-if="o.customer_phone"> · <span dir="ltr">{{ o.customer_phone }}</span></template></span>
                        </div>
                        <span class="badge" :class="orderBadge[o.status]">{{ t('orders.status.' + o.status) }}</span>
                    </div>
                    <div class="live-time"><i class="pi pi-clock" aria-hidden="true"></i>{{ fmtTime(o.created_at) }} · <b style="color:var(--ink)">{{ o.total }} {{ currencyLabel(o.currency, locale) }}</b></div>
                    <ul class="live-order-items">
                        <li v-for="(it, i) in o.items" :key="i">
                            <span class="live-qty">{{ it.qty }}×</span> {{ itemName(it) }}<span v-if="it.variant" class="live-variant">{{ it.variant }}</span>
                            <div v-if="it.options?.length" class="live-item-sub">+ {{ it.options.join(' · ') }}</div>
                            <div v-if="it.note" class="live-item-sub live-item-note"><i class="pi pi-pencil" aria-hidden="true"></i> {{ it.note }}</div>
                        </li>
                    </ul>
                    <div v-if="o.note" class="live-note">{{ o.note }}</div>
                    <div v-if="canActOrders && !o.table_visit_id" class="live-actions">
                        <button v-for="next in ORDER_NEXT[o.status] || []" :key="next"
                            :class="next === 'CANCELLED' ? 'live-cancel' : 'live-primary'"
                            :disabled="updating === 'o' + o.id" @click="setOrderStatus(o, next)">
                            <i v-if="next !== 'CANCELLED'" class="pi pi-check" aria-hidden="true"></i>{{ t(orderActionLabel[next]) }}
                        </button>
                    </div>
                </article>
                <div v-if="openTable.occupied && canActTables" class="live-actions tm-finish-actions">
                    <button class="live-primary" :disabled="updating === 'visit-' + openTable.id" @click="finishTableVisit('CLOSED')">
                        {{ t('live.close_visit') }}
                    </button>
                    <button class="live-cancel" :disabled="updating === 'visit-' + openTable.id" @click="finishTableVisit('CANCELLED')">
                        {{ t('live.cancel_visit') }}
                    </button>
                </div>
            </div>
        </Dialog>
    </div>
</template>

<style scoped>
/* Colours come only from the shared theme variables and the PrimeVue primary
   scale; nothing here introduces a new hex value. Status is always carried by
   a label and an icon as well as colour. */

/* Fill the content area: the view is a flex column the height of the viewport
   minus the sakai-content chrome (88px top + 40px bottom padding); the grid
   grows to take whatever the header leaves. */
.live-page { display: flex; flex-direction: column; height: calc(100vh - 128px); }
.live-grid { flex: 1; min-height: 0; display: grid; grid-template-columns: minmax(320px, 400px) 1fr; gap: 16px; align-items: stretch; }
.live-grid-one { grid-template-columns: 1fr; }
.live-col { padding: 0; overflow: hidden; display: flex; flex-direction: column; min-height: 0; }

.live-col-head { display: flex; align-items: center; gap: 12px; padding: 14px 18px; border-bottom: 1px solid var(--line); }
.live-col-title { flex: 1; font-size: 17px; font-weight: 700; color: var(--ink); font-family: var(--font-display); }
.live-count { min-width: 30px; text-align: center; padding: 2px 10px; border-radius: 999px; font-size: 14px; font-weight: 700;
    background: var(--page); color: var(--ink); border: 1px solid var(--line); }
.live-count-hot { background: var(--accent); border-color: var(--accent); color: var(--ink); }
.live-count-neutral { background: var(--accent-soft); border-color: var(--accent-soft); color: var(--ink); }
.live-empty { padding: 40px 16px; text-align: center; color: var(--body); font-size: 15px; }

/* Incoming feed */
.live-list { flex: 1; min-height: 0; display: flex; flex-direction: column; gap: 20px; padding: 14px; overflow-y: auto; }
/* One block per table: a header, then that table's order / request cards. */
.feed-group { display: flex; flex-direction: column; gap: 10px; }
.feed-group-head { display: flex; align-items: center; gap: 8px; padding-bottom: 6px; border-bottom: 2px solid var(--line); }
.feed-group-head strong { color: var(--ink); font-size: 17px; font-weight: 800; }
.feed-group-count { margin-inline-start: auto; min-width: 24px; text-align: center; padding: 1px 9px; font-size: 13px; font-weight: 700;
    background: var(--accent-soft); color: var(--ink); border-radius: 999px; }
.req-card { display: flex; flex-direction: column; gap: 8px; padding: 12px 14px; border: 1px solid var(--line); border-radius: 12px;
    border-inline-start-width: 5px; background: var(--card); }
.req-card-bill { border-inline-start-color: var(--red); }
.req-card-order { border-inline-start-color: var(--accent); }
.req-card-new { animation: live-pop .35s ease; }
@keyframes live-pop { from { transform: scale(.98); } to { transform: scale(1); } }
.req-top { display: flex; align-items: flex-start; justify-content: space-between; gap: 10px; }
.req-meta { display: flex; flex-direction: column; gap: 3px; }
.req-meta strong { color: var(--ink); font-size: 16px; font-weight: 700; }
.req-kind { display: inline-flex; align-items: center; gap: 7px; font-size: 14.5px; font-weight: 600; color: var(--ink); min-width: 0; }
.req-kind strong { font-weight: 800; }
.req-kind-bill i { color: var(--red); }
.req-kind-order i { color: var(--p-primary-700); }
.req-line { font-size: 15px; font-weight: 600; color: var(--red); }
.live-sub { font-size: 13.5px; color: var(--body); }
.live-time { display: flex; align-items: center; gap: 6px; font-size: 14px; color: var(--body); }
.live-time i { font-size: 13px; }
.live-total { font-size: 16px; font-weight: 700; color: var(--ink); font-variant-numeric: tabular-nums; unicode-bidi: isolate; }

/* Tables floor grid */
.tables-grid { flex: 1; min-height: 0; overflow-y: auto; padding: 16px; display: grid;
    grid-template-columns: repeat(auto-fill, minmax(140px, 1fr)); grid-auto-rows: min-content; gap: 10px; align-content: start; }
.tcard { display: flex; align-items: stretch; text-align: start; padding: 0; border: 1px solid var(--line); border-radius: 12px;
    overflow: hidden; background: var(--card); cursor: pointer; font-family: inherit; transition: border-color .15s, box-shadow .15s; }
.tcard:hover { border-color: var(--accent); box-shadow: 0 2px 8px rgba(0,0,0,.06); }
.tcard:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
/* A free table is dashed and flat; every other state is solid. */
.tcard-free { background: var(--page); border-style: dashed; }
.tcard-body { flex: 1; min-width: 0; padding: 10px 12px; display: flex; flex-direction: column; gap: 6px; min-height: 104px; box-sizing: border-box; }
.tcard-toprow { display: flex; align-items: center; gap: 6px; min-width: 0; }
.tcard-area { flex: 1; min-width: 0; font-size: 13px; font-weight: 600; color: var(--body); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.tcard-bottom { margin-top: auto; display: flex; flex-direction: column; gap: 3px; min-width: 0; }
.tcard-name { font-size: 16px; font-weight: 800; color: var(--ink); line-height: 1.25; overflow-wrap: anywhere; }
.tcard-sub { font-size: 13.5px; color: var(--body); min-height: 18px; }
.tcard-sub > span { display: inline-flex; align-items: center; gap: 5px; }
.tcard-sub i { font-size: 12px; }
.tcard-req { color: var(--red); font-weight: 700; }
.tcard-neworder { color: var(--p-primary-800); font-weight: 700; }
.tcard-idle { color: var(--body); }
.tcard-flash { animation: reqflash 1.1s ease-in-out infinite; }
@keyframes reqflash {
    0%, 100% { background: var(--card); border-color: var(--red); }
    50% { background: var(--red-soft); border-color: var(--red); }
}
/* New (unacknowledged) order — flashes in the accent/amber tone to read as
   "incoming order", distinct from the red bill-request pulse above. */
.tcard-flash-order { animation: orderflash 1.1s ease-in-out infinite; }
@keyframes orderflash {
    0%, 100% { background: var(--card); border-color: var(--accent); }
    50% { background: var(--amber-soft); border-color: var(--accent); }
}
@media (prefers-reduced-motion: reduce) {
    .tcard-flash { animation: none; background: var(--red-soft); border-color: var(--red); }
    .tcard-flash-order { animation: none; background: var(--amber-soft); border-color: var(--accent); }
    .req-card-new { animation: none; }
}

/* Modal body */
.tm-body { display: flex; flex-direction: column; gap: 14px; }
.tm-req { background: var(--red-soft); border-radius: 12px; padding: 12px 14px; display: flex; flex-direction: column; gap: 8px; }
.tm-req-line { display: flex; align-items: center; gap: 8px; font-size: 15.5px; font-weight: 700; color: var(--red); }
.tm-order { border: 1px solid var(--line); border-radius: 12px; padding: 12px 14px; display: flex; flex-direction: column; gap: 8px; }
.live-note { font-size: 14px; color: var(--ink); background: var(--accent-soft); border-radius: 8px; padding: 7px 10px; }
.live-order-items { list-style: none; margin: 0; padding: 0; font-size: 15px; color: var(--ink); }
.live-order-items li { padding: 3px 0; }
/* The chosen size/portion, kept visually attached to the name; add-ons and the
   diner's note sit under it in a quieter line so the kitchen reads the item
   the way the diner built it. */
.live-variant { margin-inline-start: 6px; font-size: 12.5px; font-weight: 600; color: var(--p-primary-800);
    background: var(--accent-soft); padding: 1px 7px; border-radius: 10px; vertical-align: 1px; }
.live-item-sub { font-size: 13.5px; color: var(--body); padding-inline-start: 28px; }
.live-item-note { color: var(--ink); }
.live-qty { font-weight: 800; color: var(--p-primary-800); unicode-bidi: isolate; }

/* Shared action buttons: 44px tall so they are safe to hit on a tablet */
.live-actions { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; margin-top: 2px; }
.live-primary, .live-cancel { display: inline-flex; align-items: center; justify-content: center; gap: 7px; min-height: 44px;
    border-radius: 10px; cursor: pointer; font-family: inherit; font-size: 15px; font-weight: 700; }
.live-primary { flex: 1 1 auto; min-width: 110px; padding: 0 16px; border: 0; background: var(--accent); color: var(--ink); }
.live-primary:hover { background: var(--accent-dark); }
.live-cancel { padding: 0 14px; border: 1px solid var(--line); background: var(--card); color: var(--body); font-weight: 600; }
.live-cancel:hover { border-color: var(--red); color: var(--red); }
.live-primary:focus-visible, .live-cancel:focus-visible { outline: 2px solid var(--ink); outline-offset: 2px; }
.live-primary:disabled, .live-cancel:disabled { opacity: .6; cursor: default; }

@media (max-width: 900px) {
    /* Narrow tablets: feed on top, floor below, both scroll with the page. */
    .live-page { height: auto; }
    .live-grid, .live-grid:not(.live-grid-one) { grid-template-columns: 1fr; }
    .live-list, .tables-grid { overflow-y: visible; }
}
@media (max-width: 480px) {
    .tables-grid { grid-template-columns: repeat(2, minmax(0, 1fr)); padding: 12px; }
}
</style>
