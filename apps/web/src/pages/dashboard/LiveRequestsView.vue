<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { useI18n } from 'vue-i18n'
import { useAuth } from '@xorder/api-client/auth.js'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import { withMinDuration } from '../../lib/minLoading.js'
import Skeleton from '@xorder/ui/Skeleton.vue'
import { confirm } from '@xorder/ui/confirm.js'
import { useRealtime } from '../../stores/realtime.js'

const { t, locale } = useI18n()
const auth = useAuth()
const rt = useRealtime()

const STATUSES = ['REQUESTED', 'SEEN', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED']
const badgeClass = {
    REQUESTED: 'badge-amber', SEEN: 'badge-indigo', IN_PROGRESS: 'badge-indigo',
    COMPLETED: 'badge-green', CANCELLED: 'badge-red',
}
// One clear next step per open status (the natural progression); a "Complete"
// shortcut and "Cancel" are offered as lower-emphasis secondary actions.
const PRIMARY_NEXT = { REQUESTED: 'SEEN', SEEN: 'IN_PROGRESS', IN_PROGRESS: 'COMPLETED' }
const actionLabel = { SEEN: 'req.act_seen', IN_PROGRESS: 'req.act_progress', COMPLETED: 'req.act_complete', CANCELLED: 'req.act_cancel' }
const primaryNext = (bill) => PRIMARY_NEXT[bill.status] || null
const canComplete = (bill) => ['REQUESTED', 'SEEN'].includes(bill.status)
const canCancel = (bill) => ['REQUESTED', 'SEEN', 'IN_PROGRESS'].includes(bill.status)

// Freshly-arrived requests get a brief highlight so staff spot them at a glance.
const knownIds = new Set()
const newIds = ref(new Set())
function seedKnown(list) { list.forEach((b) => knownIds.add(b.id)) }
function detectArrivals(list) {
    const fresh = list.filter((b) => !knownIds.has(b.id))
    if (!fresh.length) return
    const next = new Set(newIds.value)
    fresh.forEach((b) => { knownIds.add(b.id); next.add(b.id) })
    newIds.value = next
    fresh.forEach((b) => setTimeout(() => {
        const s = new Set(newIds.value); s.delete(b.id); newIds.value = s
    }, 8000))
}
// An open request untouched for this long is visually flagged as overdue.
const OVERDUE_SECONDS = 300

const rows = ref([])
const areas = ref([])
const loading = ref(true)
const statusFilter = ref('')
const areaFilter = ref('')
const updating = ref(null)
let pollTimer, offTick

async function loadAreas() {
    try {
        const { data } = await api.get('api/dashboard/dining-areas')
        areas.value = data.data || []
    } catch (err) { /* area filter is optional */ }
}

async function load() {
    loading.value = true
    try {
        const { data } = await withMinDuration(api.get('api/dashboard/bill-requests', {
            params: {
                status: statusFilter.value || undefined,
                dining_area_id: areaFilter.value || undefined,
            },
        }))
        rows.value = data.data
        seedKnown(rows.value)
    } finally {
        loading.value = false
    }
}

// Silent refresh so status changes made elsewhere land without a flicker.
async function poll() {
    if (loading.value || document.hidden) return
    try {
        const { data } = await api.get('api/dashboard/bill-requests', {
            params: {
                status: statusFilter.value || undefined,
                dining_area_id: areaFilter.value || undefined,
            },
        })
        rows.value = data.data
        detectArrivals(rows.value)
    } catch (err) { /* keep current view */ }
}

onMounted(() => {
    loadAreas()
    load()
    // Refresh the instant the shared pulse detects a new request; a slower
    // fallback still catches status changes made by other staff.
    offTick = rt.onTick(() => { if (!document.hidden) poll() })
    pollTimer = setInterval(poll, 20_000)
})
onUnmounted(() => { clearInterval(pollTimer); offTick?.() })

function setStatusFilter(s) {
    statusFilter.value = s
    load()
}

async function setStatus(bill, status) {
    if (status === 'CANCELLED') {
        const ok = await confirm({
            title: t('req.act_cancel'),
            message: t('orders.cancel_message'),
            confirmText: t('req.act_cancel'),
            cancelText: t('common.back'),
            danger: true,
        })
        if (!ok) return
    }
    updating.value = bill.id
    try {
        await ensureCsrf()
        const { data } = await api.patch(`api/dashboard/bill-requests/${bill.id}/status`, { status })
        const i = rows.value.findIndex((r) => r.id === bill.id)
        // Drop from the board when it leaves the open set on the default view.
        if (i !== -1) {
            if (!statusFilter.value && !['REQUESTED', 'SEEN', 'IN_PROGRESS'].includes(data.data.status)) {
                rows.value.splice(i, 1)
            } else {
                rows.value[i] = data.data
            }
        }
    } catch (err) {
        alert(t('req.update_failed'))
    } finally {
        updating.value = null
    }
}

const areaName = (bill) => {
    const en = bill.area_name_en, ar = bill.area_name_ar
    return (locale.value === 'ar' ? (ar || en) : (en || ar)) || ''
}

function isOverdue(bill) {
    return ['REQUESTED', 'SEEN', 'IN_PROGRESS'].includes(bill.status)
        && (bill.elapsed_seconds ?? 0) >= OVERDUE_SECONDS
}

function fmtElapsed(iso) {
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
                <h1 class="page-title">{{ t('req.title') }}</h1>
                <p class="page-sub">{{ t('req.subtitle') }}</p>
            </div>
        </div>

        <!-- Filters -->
        <div class="flex items-center gap-2 flex-wrap">
            <button class="chip" :class="{ 'chip-on': statusFilter === '' }" @click="setStatusFilter('')">{{ t('common.all') }}</button>
            <button v-for="s in STATUSES" :key="s" class="chip" :class="{ 'chip-on': statusFilter === s }" @click="setStatusFilter(s)">
                {{ t('req.status.' + s) }}
            </button>
            <select v-model="areaFilter" class="chip chip-select" @change="load">
                <option value="">{{ t('req.all_areas') }}</option>
                <option v-for="a in areas" :key="a.id" :value="a.id">{{ locale === 'ar' ? (a.name_ar || a.name_en) : (a.name_en || a.name_ar) }}</option>
            </select>
        </div>

        <!-- Board -->
        <template v-if="loading">
            <div class="req-grid">
                <div v-for="n in 4" :key="'sk' + n" class="card p-4 space-y-3">
                    <Skeleton h="16px" w="50%" />
                    <Skeleton h="12px" w="70%" />
                    <Skeleton h="30px" w="90%" />
                </div>
            </div>
        </template>
        <div v-else-if="!rows.length" class="card px-5 py-10 text-center" style="color:var(--muted)">
            {{ t('req.none') }}
        </div>
        <div v-else class="req-grid">
            <div v-for="bill in rows" :key="bill.id" class="card req-card"
                :class="{ 'req-card--overdue': isOverdue(bill), 'req-card--new': newIds.has(bill.id) }">
                <div class="flex items-start justify-between gap-2">
                    <div>
                        <div class="req-table">{{ t('req.table') }} {{ bill.table_label || '—' }}</div>
                        <div v-if="areaName(bill)" class="text-xs" style="color:var(--muted)">{{ areaName(bill) }}</div>
                    </div>
                    <span v-if="newIds.has(bill.id)" class="req-new-pill">{{ t('req.just_arrived') }}</span>
                    <span v-else class="badge" :class="badgeClass[bill.status]">{{ t('req.status.' + bill.status) }}</span>
                </div>

                <div class="req-time" :class="{ 'req-time--overdue': isOverdue(bill) }">
                    <span class="req-time-dot" />
                    {{ t('req.waiting', { time: fmtElapsed(bill.requested_at) }) }}
                </div>

                <div v-if="bill.customer_note" class="req-note">
                    {{ t('req.note') }}: {{ bill.customer_note }}
                </div>

                <!-- One prominent next step; Complete + Cancel are lower-emphasis. -->
                <div v-if="primaryNext(bill) && !auth.isReadOnly" class="req-actions">
                    <button class="req-primary" :disabled="updating === bill.id" @click="setStatus(bill, primaryNext(bill))">
                        {{ t(actionLabel[primaryNext(bill)]) }}
                    </button>
                    <div v-if="canComplete(bill) || canCancel(bill)" class="req-secondary">
                        <button v-if="canComplete(bill)" class="req-sec" :disabled="updating === bill.id" @click="setStatus(bill, 'COMPLETED')">
                            {{ t('req.act_complete') }}
                        </button>
                        <button v-if="canCancel(bill)" class="req-cancel" :disabled="updating === bill.id" @click="setStatus(bill, 'CANCELLED')">
                            {{ t('req.act_cancel') }}
                        </button>
                    </div>
                </div>
            </div>
        </div>
    </div>
</template>

<style scoped>
.chip { display: inline-flex; align-items: center; gap: 7px; padding: 7px 14px; border-radius: 20px;
    border: 1px solid var(--line); background: var(--card); color: var(--body); font-size: 13.5px; font-weight: 600; cursor: pointer; }
.chip-on { background: var(--accent); color: #fff; border-color: var(--accent); }
.chip-select { padding-inline-end: 10px; }
.req-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(260px, 1fr)); gap: 14px; }
.req-card { padding: 16px; display: flex; flex-direction: column; gap: 10px; }
.req-card--overdue { border-color: #e0a106; box-shadow: 0 0 0 1px #e0a10633; }
.req-card--new { border-color: var(--accent); box-shadow: 0 0 0 2px color-mix(in srgb, var(--accent) 22%, transparent); animation: req-pop .35s ease; }
@keyframes req-pop { from { transform: scale(.98); } to { transform: scale(1); } }
.req-table { font-weight: 700; color: var(--ink); font-size: 15px; }
.req-time { display: inline-flex; align-items: center; gap: 6px; font-size: 13px; color: var(--muted); }
.req-time-dot { width: 7px; height: 7px; border-radius: 50%; background: currentColor; flex: none; }
.req-time--overdue { color: #b26b00; font-weight: 700; }
.req-note { font-size: 13px; color: var(--body); background: var(--accent-soft); border-radius: 10px; padding: 8px 10px; }

.req-new-pill {
    flex: none; align-self: flex-start; font-size: 11px; font-weight: 700; padding: 3px 9px; border-radius: 999px;
    color: #fff; background: var(--accent); animation: req-blink 1.1s ease-in-out infinite;
}
@keyframes req-blink { 50% { opacity: .55; } }

/* Action hierarchy: one full-width primary, then a quiet secondary row. */
.req-actions { display: flex; flex-direction: column; gap: 8px; margin-top: 4px; }
.req-primary {
    width: 100%; padding: 10px 14px; border: 0; border-radius: 10px; cursor: pointer;
    background: var(--accent); color: #fff; font-size: 14px; font-weight: 700;
    transition: filter .15s;
}
.req-primary:hover { filter: brightness(1.05); }
.req-primary:disabled { opacity: .6; cursor: default; }
.req-secondary { display: flex; align-items: center; gap: 6px; }
.req-sec {
    flex: 1; padding: 7px 12px; border-radius: 9px; cursor: pointer; font-size: 13px; font-weight: 600;
    border: 1px solid var(--line); background: var(--card); color: var(--body); transition: border-color .15s, color .15s;
}
.req-sec:hover { border-color: var(--accent); color: var(--accent); }
.req-cancel {
    padding: 7px 12px; border: 0; background: none; cursor: pointer; font-size: 13px; font-weight: 600; color: var(--muted);
    border-radius: 9px; transition: color .15s;
}
.req-cancel:hover { color: #c0392b; }
.req-sec:disabled, .req-cancel:disabled { opacity: .6; cursor: default; }
</style>
