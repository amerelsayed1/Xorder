<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { useI18n } from 'vue-i18n'
import { useAuth } from '@xorder/api-client/auth.js'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import { currencyLabel } from '../../lib/currency.js'
import Skeleton from '@xorder/ui/Skeleton.vue'
import { confirm } from '@xorder/ui/confirm.js'
import { useRealtime } from '../../stores/realtime.js'

const { t, locale } = useI18n()
const auth = useAuth()
const rt = useRealtime()
const feats = computed(() => auth.restaurant?.features || [])
const showOrders = computed(() => feats.value.includes('system_ordering'))
const showRequests = computed(() => feats.value.includes('bill_requests'))

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
const REQ_PRIMARY = { REQUESTED: 'SEEN', SEEN: 'IN_PROGRESS', IN_PROGRESS: 'COMPLETED' }
const reqActionLabel = { SEEN: 'req.act_seen', IN_PROGRESS: 'req.act_progress', COMPLETED: 'req.act_complete', CANCELLED: 'req.act_cancel' }
const reqBadge = { REQUESTED: 'badge-amber', SEEN: 'badge-indigo', IN_PROGRESS: 'badge-indigo' }
const reqPrimary = (b) => REQ_PRIMARY[b.status] || null
const reqCanComplete = (b) => ['REQUESTED', 'SEEN'].includes(b.status)

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
        requests.value = requests.value.filter((r) => r.id !== bill.id || ['REQUESTED', 'SEEN', 'IN_PROGRESS'].includes(status))
        const i = requests.value.findIndex((r) => r.id === bill.id)
        if (i !== -1) requests.value[i] = { ...requests.value[i], status }
    } catch { alert(t('req.update_failed')) }
    finally { updating.value = null }
}

// ---------- Orders (active = NEW + CONFIRMED, oldest first) ----------
const orders = ref([])
const orderNewIds = ref(new Set())
const ORDER_NEXT = { NEW: ['CONFIRMED', 'CANCELLED'], CONFIRMED: ['COMPLETED', 'CANCELLED'] }
const orderActionLabel = { CONFIRMED: 'orders.confirm', COMPLETED: 'orders.complete', CANCELLED: 'orders.cancel_order' }
const orderBadge = { NEW: 'badge-amber', CONFIRMED: 'badge-indigo' }

async function loadOrders(highlight) {
    if (!showOrders.value) return
    const [n, c] = await Promise.all([
        api.get('api/dashboard/orders', { params: { status: 'NEW' } }),
        api.get('api/dashboard/orders', { params: { status: 'CONFIRMED' } }),
    ])
    const merged = [...(n.data.data || []), ...(c.data.data || [])]
        .sort((a, b) => new Date(a.created_at) - new Date(b.created_at))
    applyList(orders, merged, orderNewIds, highlight)
}

async function setOrderStatus(order, status) {
    if (status === 'CANCELLED' && ! await confirmCancel('orders')) return
    updating.value = 'o' + order.id
    try {
        await ensureCsrf()
        await api.patch(`api/dashboard/orders/${order.id}/status`, { status })
        // Drops off the board once it leaves the active set.
        orders.value = orders.value.filter((o) => o.id !== order.id)
    } catch { alert(t('orders.update_failed')) }
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
    try { await Promise.all([loadRequests(highlight), loadOrders(highlight)]) } catch { /* keep view */ }
}

onMounted(async () => {
    await refresh(false)
    loading.value = false
    // Refresh the instant the shared pulse detects new orders/requests. A slower
    // fallback still catches status changes made by other staff (which don't move
    // the new-item counts, so the pulse tick wouldn't fire for them).
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
</script>

<template>
    <div class="space-y-5">
        <div>
            <h1 class="page-title">{{ t('live.title') }}</h1>
            <p class="page-sub">{{ t('live.subtitle') }}</p>
        </div>

        <div v-if="loading" class="live-grid">
            <div v-for="n in 2" :key="'sk' + n" class="card p-4 space-y-3">
                <Skeleton h="16px" w="40%" /><Skeleton h="60px" w="100%" /><Skeleton h="60px" w="100%" />
            </div>
        </div>

        <div v-else-if="!showRequests && !showOrders" class="card px-5 py-12 text-center" style="color:var(--muted)">
            {{ t('live.none') }}
        </div>

        <div v-else class="live-grid">
            <!-- Requests column -->
            <section v-if="showRequests" class="live-col card">
                <header class="live-col-head">
                    <h2 class="live-col-title">{{ t('live.requests_col') }}</h2>
                    <span class="live-count" :class="{ 'live-count-hot': requests.length }">{{ requests.length }}</span>
                </header>
                <div v-if="!requests.length" class="live-empty">{{ t('live.no_requests') }}</div>
                <div v-else class="live-list">
                    <article v-for="b in requests" :key="b.id" class="live-item" :class="{ 'live-item-new': requestNewIds.has(b.id) }">
                        <div class="live-item-head">
                            <div>
                                <strong>{{ t('req.table') }} {{ b.table_label || '—' }}</strong>
                                <span v-if="areaName(b)" class="live-sub">{{ areaName(b) }}</span>
                            </div>
                            <span class="badge" :class="reqBadge[b.status]">{{ t('req.status.' + b.status) }}</span>
                        </div>
                        <div class="live-time">{{ t('req.waiting', { time: fmtTime(b.requested_at) }) }}</div>
                        <div v-if="b.customer_note" class="live-note">{{ b.customer_note }}</div>
                        <div v-if="!auth.isReadOnly" class="live-actions">
                            <button class="live-primary" :disabled="updating === 'r' + b.id" @click="setRequestStatus(b, reqPrimary(b))">
                                {{ t(reqActionLabel[reqPrimary(b)]) }}
                            </button>
                            <button v-if="reqCanComplete(b)" class="live-sec" :disabled="updating === 'r' + b.id" @click="setRequestStatus(b, 'COMPLETED')">{{ t('req.act_complete') }}</button>
                            <button class="live-cancel" :disabled="updating === 'r' + b.id" @click="setRequestStatus(b, 'CANCELLED')">{{ t('req.act_cancel') }}</button>
                        </div>
                    </article>
                </div>
            </section>

            <!-- Orders column -->
            <section v-if="showOrders" class="live-col card">
                <header class="live-col-head">
                    <h2 class="live-col-title">{{ t('live.orders_col') }}</h2>
                    <span class="live-count" :class="{ 'live-count-hot': orders.length }">{{ orders.length }}</span>
                </header>
                <div v-if="!orders.length" class="live-empty">{{ t('live.no_orders') }}</div>
                <div v-else class="live-list">
                    <article v-for="o in orders" :key="o.id" class="live-item" :class="{ 'live-item-new': orderNewIds.has(o.id) }">
                        <div class="live-item-head">
                            <div>
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
                        <div v-if="!auth.isReadOnly" class="live-actions">
                            <button v-for="next in ORDER_NEXT[o.status] || []" :key="next"
                                :class="next === 'CANCELLED' ? 'live-cancel' : (next === 'CONFIRMED' ? 'live-primary' : 'live-primary')"
                                :disabled="updating === 'o' + o.id" @click="setOrderStatus(o, next)">{{ t(orderActionLabel[next]) }}</button>
                        </div>
                    </article>
                </div>
            </section>
        </div>
    </div>
</template>

<style scoped>
.live-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(320px, 1fr)); gap: 16px; align-items: start; }
.live-col { padding: 0; overflow: hidden; }
.live-col-head { display: flex; align-items: center; justify-content: space-between; padding: 14px 16px; border-bottom: 1px solid var(--line); }
.live-col-title { display: flex; align-items: center; gap: 8px; font-size: 16px; font-weight: 700; color: var(--ink); font-family: var(--font-display); }
.live-count { min-width: 26px; text-align: center; padding: 2px 9px; border-radius: 999px; font-size: 13px; font-weight: 700; background: var(--page); color: var(--muted); }
.live-count-hot { background: var(--accent); color: #fff; }
.live-empty { padding: 32px 16px; text-align: center; color: var(--muted); font-size: 13.5px; }
.live-list { display: flex; flex-direction: column; gap: 10px; padding: 14px; max-height: 72vh; overflow-y: auto; }

.live-item { border: 1px solid var(--line); border-radius: 12px; padding: 12px; display: flex; flex-direction: column; gap: 7px; }
.live-item-new { border-color: var(--accent); box-shadow: 0 0 0 2px color-mix(in srgb, var(--accent) 20%, transparent); animation: live-pop .35s ease; }
@keyframes live-pop { from { transform: scale(.98); } to { transform: scale(1); } }
.live-item-head { display: flex; align-items: flex-start; justify-content: space-between; gap: 8px; }
.live-item-head strong { display: block; color: var(--ink); font-size: 14.5px; }
.live-sub { display: block; font-size: 12px; color: var(--muted); margin-top: 1px; }
.live-time { font-size: 12.5px; color: var(--muted); }
.live-note { font-size: 12.5px; color: var(--body); background: var(--accent-soft); border-radius: 8px; padding: 6px 9px; }
.live-order-items { list-style: none; margin: 0; padding: 0; font-size: 13px; color: var(--body); }
.live-order-items li { padding: 1px 0; }
.live-qty { font-weight: 700; color: var(--accent-dark, var(--accent)); unicode-bidi: isolate; }

.live-actions { display: flex; align-items: center; gap: 6px; flex-wrap: wrap; margin-top: 2px; }
.live-primary { flex: 1 1 auto; min-width: 96px; padding: 8px 12px; border: 0; border-radius: 9px; cursor: pointer; background: var(--accent); color: #fff; font-size: 13px; font-weight: 700; }
.live-primary:hover { filter: brightness(1.05); }
.live-sec { padding: 7px 11px; border-radius: 9px; cursor: pointer; font-size: 12.5px; font-weight: 600; border: 1px solid var(--line); background: var(--card); color: var(--body); }
.live-sec:hover { border-color: var(--accent); color: var(--accent); }
.live-cancel { padding: 7px 11px; border: 0; background: none; cursor: pointer; font-size: 12.5px; font-weight: 600; color: var(--muted); border-radius: 9px; }
.live-cancel:hover { color: #c0392b; }
.live-primary:disabled, .live-sec:disabled, .live-cancel:disabled { opacity: .6; cursor: default; }
</style>
