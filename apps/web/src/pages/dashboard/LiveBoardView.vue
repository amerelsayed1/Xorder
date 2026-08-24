<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { useI18n } from 'vue-i18n'
import { useAuth } from '@xorder/api-client/auth.js'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import { currencyLabel } from '../../lib/currency.js'
import Skeleton from '@xorder/ui/Skeleton.vue'
import Dialog from '@xorder/ui/Dialog.vue'
import { confirm } from '@xorder/ui/confirm.js'
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
    if (status === 'CANCELLED' && ! await confirmCancel('orders')) return
    updating.value = 'o' + order.id
    try {
        await ensureCsrf()
        await api.patch(`api/dashboard/orders/${order.id}/status`, { status })
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
    <div class="space-y-5 live-page">
        <div>
            <h1 class="page-title">{{ t('live.title') }}</h1>
            <p class="page-sub">{{ t('live.subtitle') }}</p>
        </div>

        <div v-if="loading" class="live-grid">
            <div v-for="n in 2" :key="'sk' + n" class="card p-4 space-y-3">
                <Skeleton h="16px" w="40%" /><Skeleton h="60px" w="100%" /><Skeleton h="60px" w="100%" />
            </div>
        </div>

        <div v-else-if="!hasFeed && !showTables" class="card px-5 py-12 text-center" style="color:var(--muted)">
            {{ t('live.none') }}
        </div>

        <!-- Two joined panels: the incoming feed (orders + bill requests) on the
             left, tables floor on the right. dir=ltr on the wrapper fixes that
             order; each panel restores locale dir. -->
        <div v-else class="live-grid" :class="{ 'live-grid-one': !hasFeed || !showTables }" dir="ltr">
            <!-- Incoming feed: new table orders + open bill requests -->
            <section v-if="hasFeed" class="live-col card" :dir="panelDir">
                <header class="live-col-head">
                    <h2 class="live-col-title">{{ t('live.requests_col') }}</h2>
                    <span class="live-count" :class="{ 'live-count-hot': feedCount }">{{ feedCount }}</span>
                </header>
                <div v-if="!feedCount" class="live-empty">{{ t('live.feed_empty') }}</div>
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
                            <article v-if="it.type === 'request'" class="req-card" :class="{ 'req-card-new': feedIsNew(it) }">
                                <div class="req-top">
                                    <span class="live-sub">{{ t('req.waiting', { time: fmtTime(it.req.requested_at) }) }}</span>
                                    <span class="badge" :class="reqBadge[it.req.status]">{{ t('req.status.' + it.req.status) }}</span>
                                </div>
                                <div class="req-line">{{ it.req.customer_note || t('req.bill') }}</div>
                                <div v-if="canActRequests" class="live-actions">
                                    <button class="live-primary" :disabled="updating === 'r' + it.req.id" @click="setRequestStatus(it.req, 'COMPLETED')">
                                        {{ t('orders.complete') }}
                                    </button>
                                    <button class="live-cancel" :disabled="updating === 'r' + it.req.id" @click="setRequestStatus(it.req, 'CANCELLED')">{{ t('req.act_cancel') }}</button>
                                </div>
                            </article>
                            <!-- New table order -->
                            <article v-else class="req-card" :class="{ 'req-card-new': feedIsNew(it) }">
                                <div class="req-top">
                                    <div class="req-meta">
                                        <strong>{{ it.order.code }}</strong>
                                        <span class="live-sub">{{ fmtTime(it.order.created_at) }}<template v-if="it.order.customer_name"> · {{ it.order.customer_name }}</template></span>
                                    </div>
                                    <span class="badge" :class="orderBadge[it.order.status]">{{ t('orders.status.' + it.order.status) }}</span>
                                </div>
                                <ul class="live-order-items">
                                    <li v-for="(itm, i) in it.order.items" :key="i"><span class="live-qty">{{ itm.qty }}×</span> {{ itm.name }}</li>
                                </ul>
                                <div class="live-time"><b style="color:var(--ink)">{{ it.order.total }} {{ currencyLabel(it.order.currency, locale) }}</b></div>
                                <div v-if="canActOrders && !it.order.table_visit_id" class="live-actions">
                                    <button v-for="next in ORDER_NEXT[it.order.status] || []" :key="next"
                                        :class="next === 'CANCELLED' ? 'live-cancel' : 'live-primary'"
                                        :disabled="updating === 'o' + it.order.id" @click="setOrderStatus(it.order, next)">{{ t(orderActionLabel[next]) }}</button>
                                </div>
                            </article>
                        </template>
                    </section>
                </div>
            </section>

            <!-- Tables floor grid -->
            <section v-if="showTables" class="live-col card" :dir="panelDir">
                <header class="live-col-head">
                    <h2 class="live-col-title">{{ t('live.tables_col') }}</h2>
                    <span class="live-count live-count-neutral">{{ tables.length }}</span>
                </header>
                <div v-if="!tables.length" class="live-empty">{{ t('live.no_tables') }}</div>
                <div v-else class="tables-grid">
                    <button v-for="tbl in tables" :key="tbl.id" type="button" class="tcard"
                        :class="{ 'tcard-flash': tbl.has_request, 'tcard-flash-order': !tbl.has_request && tbl.has_new_order }"
                        @click="openTableModal(tbl)">
                        <span class="tcard-body">
                            <span class="tcard-toprow">
                                <span class="tcard-area">{{ areaName(tbl) }}</span>
                            </span>
                            <span class="tcard-bottom">
                                <span class="tcard-name">{{ t('req.table') }} {{ tbl.label }}</span>
                                <span class="tcard-sub">
                                    <span v-if="tbl.has_request" class="tcard-req">{{ requestByTable.get(tbl.id)?.customer_note || t('req.bill') }}</span>
                                    <span v-else-if="tbl.active_orders">{{ t('live.active_orders_n', { n: tbl.active_orders }) }}</span>
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
                    <div class="tm-req-line">{{ modalRequest.customer_note || t('req.bill') }}</div>
                    <div class="live-sub">{{ t('req.waiting', { time: fmtTime(modalRequest.requested_at) }) }}</div>
                    <div v-if="canActRequests" class="live-actions">
                        <button class="live-primary" :disabled="updating === 'r' + modalRequest.id" @click="setRequestStatus(modalRequest, 'COMPLETED')">
                            {{ t('orders.complete') }}
                        </button>
                        <button class="live-cancel" :disabled="updating === 'r' + modalRequest.id" @click="setRequestStatus(modalRequest, 'CANCELLED')">{{ t('req.act_cancel') }}</button>
                    </div>
                </div>

                <div v-if="modalLoading" class="space-y-2">
                    <Skeleton h="54px" w="100%" /><Skeleton h="54px" w="100%" />
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
                    <div class="live-time">{{ fmtTime(o.created_at) }} · <b style="color:var(--ink)">{{ o.total }} {{ currencyLabel(o.currency, locale) }}</b></div>
                    <ul class="live-order-items">
                        <li v-for="(it, i) in o.items" :key="i"><span class="live-qty">{{ it.qty }}×</span> {{ it.name }}</li>
                    </ul>
                    <div v-if="o.note" class="live-note">{{ o.note }}</div>
                    <div v-if="canActOrders && !o.table_visit_id" class="live-actions">
                        <button v-for="next in ORDER_NEXT[o.status] || []" :key="next"
                            :class="next === 'CANCELLED' ? 'live-cancel' : 'live-primary'"
                            :disabled="updating === 'o' + o.id" @click="setOrderStatus(o, next)">{{ t(orderActionLabel[next]) }}</button>
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
/* Fill the content area: the view is a flex column the height of the viewport
   minus the sakai-content chrome (88px top + 40px bottom padding); the grid
   grows to take whatever the header leaves. */
.live-page { display: flex; flex-direction: column; height: calc(100vh - 128px); }
.live-grid { flex: 1; min-height: 0; display: grid; grid-template-columns: 300px 1fr; gap: 0; align-items: stretch; }
.live-grid-one { grid-template-columns: 1fr; }
/* Square corners across the whole view (overrides the global .card radius). */
.card { border-radius: 0; }
.live-col { padding: 0; overflow: hidden; display: flex; flex-direction: column; border-radius: 0; }
/* Flush, joined block: the requests panel loses its inner (right) border so the
   two panels join. Physical `border-right` — not `border-inline-end` — because
   each panel restores dir=rtl for its content, which would otherwise flip the
   logical end to the outer-left edge and drop the board's outer border. The
   wrapper is dir=ltr, so requests is always the left panel in every locale. */
.live-grid:not(.live-grid-one) > .live-col:first-child { border-right: none; }

.live-col-head { display: flex; align-items: center; gap: 12px; padding: 16px 20px; border-bottom: 1px solid var(--line); }
.live-col-title { flex: 1; font-size: 16.5px; font-weight: 700; color: var(--ink); font-family: var(--font-display); }
.live-count { min-width: 26px; text-align: center; padding: 2px 9px; font-size: 13px; font-weight: 700; background: var(--page); color: var(--muted); }
.live-count-hot { background: var(--accent); color: #fff; }
.live-count-neutral { background: var(--accent-soft); color: var(--accent); }
.live-empty { padding: 40px 16px; text-align: center; color: var(--muted); font-size: 13.5px; }

/* Requests column */
.live-list { flex: 1; min-height: 0; display: flex; flex-direction: column; gap: 22px; padding: 16px; overflow-y: auto; }
/* One block per table: a header, then that table's order / request cards. */
.feed-group { display: flex; flex-direction: column; }
.feed-group-head { display: flex; align-items: center; gap: 8px; padding-bottom: 8px; margin-bottom: 12px; border-bottom: 1px solid var(--line); }
.feed-group-head strong { color: var(--ink); font-size: 14.5px; font-weight: 800; }
.feed-group-count { margin-inline-start: auto; min-width: 20px; text-align: center; padding: 1px 8px; font-size: 12px; font-weight: 700; background: var(--accent-soft); color: var(--accent); border-radius: 10px; }
.req-card { display: flex; flex-direction: column; gap: 8px; padding: 4px 0; }
.req-card + .req-card { border-top: 1px solid var(--line); padding-top: 14px; }
.req-card-new { animation: live-pop .35s ease; }
@keyframes live-pop { from { transform: scale(.98); } to { transform: scale(1); } }
.req-top { display: flex; align-items: flex-start; justify-content: space-between; gap: 10px; }
.req-meta { display: flex; flex-direction: column; gap: 3px; }
.req-meta strong { color: var(--ink); font-size: 14px; font-weight: 700; }
.req-line { font-size: 13px; font-weight: 600; color: #dc2626; }
.live-sub { font-size: 12px; color: var(--muted); }

/* Tables floor grid */
.tables-grid { flex: 1; min-height: 0; overflow-y: auto; padding: 18px; display: grid;
    grid-template-columns: repeat(auto-fill, minmax(120px, 1fr)); grid-auto-rows: min-content; gap: 10px; align-content: start; }
.tcard { display: flex; align-items: stretch; text-align: start; padding: 0; border: 1px solid var(--line);
    overflow: hidden; background: var(--page); cursor: pointer; font-family: inherit; }
.tcard:hover { border-color: var(--accent); box-shadow: 0 2px 8px rgba(0,0,0,.06); }
.tcard-body { flex: 1; min-width: 0; padding: 8px 10px; display: flex; flex-direction: column; gap: 6px; height: 92px; box-sizing: border-box; }
.tcard-toprow { display: flex; align-items: center; gap: 6px; min-width: 0; }
.tcard-area { flex: 1; min-width: 0; font-size: 11.5px; font-weight: 600; color: var(--muted); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.tcard-bottom { margin-top: auto; display: flex; flex-direction: column; gap: 1px; min-width: 0; }
.tcard-name { font-size: 12.5px; font-weight: 700; color: var(--ink); line-height: 1.3; overflow-wrap: anywhere; }
.tcard-sub { font-size: 11.5px; color: var(--muted); min-height: 15px; }
.tcard-req { color: #dc2626; font-weight: 700; }
.tcard-flash { animation: reqflash 1.1s ease-in-out infinite; }
@keyframes reqflash {
    0%, 100% { background: #fff1f1; border-color: #fecaca; }
    50% { background: #fecaca; border-color: #f87171; }
}
/* New (unacknowledged) order — flashes in the accent/amber tone to read as
   "incoming order", distinct from the red bill-request pulse above. */
.tcard-flash-order { animation: orderflash 1.1s ease-in-out infinite; }
@keyframes orderflash {
    0%, 100% { background: #fffbeb; border-color: #fde68a; }
    50% { background: #fef3c7; border-color: #fbbf24; }
}

/* Modal body */
.tm-body { display: flex; flex-direction: column; gap: 14px; }
.tm-req { background: #fef2f2; padding: 12px 14px; display: flex; flex-direction: column; gap: 8px; }
.tm-req-line { font-size: 14px; font-weight: 700; color: #dc2626; }
.tm-order { border: 1px solid var(--line); padding: 12px; display: flex; flex-direction: column; gap: 7px; }
.live-time { font-size: 12.5px; color: var(--muted); }
.live-note { font-size: 12.5px; color: var(--body); background: var(--accent-soft); padding: 6px 9px; }
.live-order-items { list-style: none; margin: 0; padding: 0; font-size: 13px; color: var(--body); }
.live-order-items li { padding: 1px 0; }
.live-qty { font-weight: 700; color: var(--accent-dark, var(--accent)); unicode-bidi: isolate; }

/* Shared action buttons */
.live-actions { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; margin-top: 2px; }
.live-primary { flex: 1 1 auto; min-width: 96px; padding: 9px 14px; border: 0; cursor: pointer; background: var(--accent); color: #fff; font-size: 13px; font-weight: 700; font-family: inherit; }
.live-primary:hover { background: var(--accent-dark); }
.live-sec { padding: 8px 12px; cursor: pointer; font-size: 12.5px; font-weight: 600; border: 1px solid var(--line); background: var(--card); color: var(--body); font-family: inherit; }
.live-sec:hover { border-color: var(--accent); color: var(--accent); }
.live-cancel { padding: 8px 10px; border: 0; background: none; cursor: pointer; font-size: 12.5px; font-weight: 600; color: var(--muted); font-family: inherit; }
.live-cancel:hover { color: #c0392b; }
.live-primary:disabled, .live-sec:disabled, .live-cancel:disabled { opacity: .6; cursor: default; }

@media (max-width: 720px) {
    /* Stacked panels flow naturally instead of sharing a fixed viewport height. */
    .live-page { height: auto; }
    .live-grid, .live-grid:not(.live-grid-one) { grid-template-columns: 1fr; }
    .live-grid > .live-col { border-right: 1px solid var(--line) !important; }
    .live-grid > .live-col:first-child { margin-bottom: 16px; }
}
</style>
