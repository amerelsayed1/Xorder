<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { useI18n } from 'vue-i18n'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import { withMinDuration } from '../../lib/minLoading.js'
import Skeleton from '@xorder/ui/Skeleton.vue'
import { confirm } from '@xorder/ui/confirm.js'

const { t, locale } = useI18n()

const STATUSES = ['REQUESTED', 'SEEN', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED']
const badgeClass = {
    REQUESTED: 'badge-amber', SEEN: 'badge-indigo', IN_PROGRESS: 'badge-indigo',
    COMPLETED: 'badge-green', CANCELLED: 'badge-red',
}
// Which statuses each open request can advance to, rendered as per-card buttons.
const nextActions = {
    REQUESTED: ['SEEN', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED'],
    SEEN: ['IN_PROGRESS', 'COMPLETED', 'CANCELLED'],
    IN_PROGRESS: ['COMPLETED', 'CANCELLED'],
}
const actionLabel = { SEEN: 'req.act_seen', IN_PROGRESS: 'req.act_progress', COMPLETED: 'req.act_complete', CANCELLED: 'req.act_cancel' }
// An open request untouched for this long is visually flagged as overdue.
const OVERDUE_SECONDS = 300

const rows = ref([])
const areas = ref([])
const loading = ref(true)
const statusFilter = ref('')
const areaFilter = ref('')
const updating = ref(null)
let pollTimer

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
    } catch (err) { /* keep current view */ }
}

onMounted(() => {
    loadAreas()
    load()
    pollTimer = setInterval(poll, 12_000)
})
onUnmounted(() => clearInterval(pollTimer))

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
            <div v-for="bill in rows" :key="bill.id" class="card req-card" :class="{ 'req-card--overdue': isOverdue(bill) }">
                <div class="flex items-start justify-between gap-2">
                    <div>
                        <div class="req-table">{{ t('req.table') }} {{ bill.table_label || '—' }}</div>
                        <div v-if="areaName(bill)" class="text-xs" style="color:var(--muted)">{{ areaName(bill) }}</div>
                    </div>
                    <span class="badge" :class="badgeClass[bill.status]">{{ t('req.status.' + bill.status) }}</span>
                </div>

                <div class="req-time" :class="{ 'req-time--overdue': isOverdue(bill) }">
                    <span class="req-time-dot" />
                    {{ t('req.waiting', { time: fmtElapsed(bill.requested_at) }) }}
                </div>

                <div v-if="bill.customer_note" class="req-note">
                    {{ t('req.note') }}: {{ bill.customer_note }}
                </div>

                <div v-if="nextActions[bill.status]" class="req-actions">
                    <button v-for="next in nextActions[bill.status]" :key="next"
                        class="btn btn-sm" :class="next === 'CANCELLED' ? 'btn-ghost btn-cancel' : 'btn-accent'"
                        :disabled="updating === bill.id" @click="setStatus(bill, next)">
                        {{ t(actionLabel[next]) }}
                    </button>
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
.btn-cancel { color: #c0392b; }
.req-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(260px, 1fr)); gap: 14px; }
.req-card { padding: 16px; display: flex; flex-direction: column; gap: 10px; }
.req-card--overdue { border-color: #e0a106; box-shadow: 0 0 0 1px #e0a10633; }
.req-table { font-weight: 700; color: var(--ink); font-size: 15px; }
.req-time { display: inline-flex; align-items: center; gap: 6px; font-size: 13px; color: var(--muted); }
.req-time-dot { width: 7px; height: 7px; border-radius: 50%; background: currentColor; flex: none; }
.req-time--overdue { color: #b26b00; font-weight: 700; }
.req-note { font-size: 13px; color: var(--body); background: var(--accent-soft); border-radius: 10px; padding: 8px 10px; }
.req-actions { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 2px; }
</style>
