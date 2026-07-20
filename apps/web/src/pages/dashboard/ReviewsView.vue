<script setup>
import { ref, computed, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import { withMinDuration } from '../../lib/minLoading.js'
import Skeleton from '@xorder/ui/Skeleton.vue'
import Dialog from '@xorder/ui/Dialog.vue'

const { t, locale } = useI18n()

const STATUSES = ['NEW', 'IN_REVIEW', 'CONTACTED', 'RESOLVED', 'ARCHIVED']
const badgeClass = {
    NEW: 'badge-amber', IN_REVIEW: 'badge-indigo', CONTACTED: 'badge-indigo',
    RESOLVED: 'badge-green', ARCHIVED: 'badge-gray',
}

const rows = ref([])
const summary = ref({ average: 0, count: 0, low_count: 0, by_rating: {} })
const areas = ref([])
const loading = ref(true)

const ratingFilter = ref('')
const statusFilter = ref('')
const areaFilter = ref('')
const contactOnly = ref(false)
const dateFrom = ref('')
const dateTo = ref('')

// Detail dialog state
const active = ref(null)
const savingStatus = ref(false)
const noteText = ref('')
const savingNote = ref(false)

async function loadAreas() {
    try {
        const { data } = await api.get('api/dashboard/dining-areas')
        areas.value = data.data || []
    } catch (err) { /* area filter is optional */ }
}

async function loadSummary() {
    try {
        const { data } = await api.get('api/dashboard/reviews/summary')
        summary.value = data
    } catch (err) { /* tiles fall back to zeros */ }
}

function params() {
    return {
        rating: ratingFilter.value || undefined,
        status: statusFilter.value || undefined,
        dining_area_id: areaFilter.value || undefined,
        contact_permission: contactOnly.value ? 1 : undefined,
        date_from: dateFrom.value || undefined,
        date_to: dateTo.value || undefined,
    }
}

async function load() {
    loading.value = true
    try {
        const { data } = await withMinDuration(api.get('api/dashboard/reviews', { params: params() }))
        rows.value = data.data
    } finally {
        loading.value = false
    }
}

onMounted(() => {
    loadAreas()
    loadSummary()
    load()
})

function setRating(r) { ratingFilter.value = r; load() }
function setStatus(s) { statusFilter.value = s; load() }

const areaName = (row) => {
    const en = row.area_name_en, ar = row.area_name_ar
    return (locale.value === 'ar' ? (ar || en) : (en || ar)) || ''
}

const stars = (n) => '★★★★★'.slice(0, n) + '☆☆☆☆☆'.slice(0, 5 - n)

function fmtDate(iso) {
    if (!iso) return ''
    return new Date(iso).toLocaleString(locale.value, {
        month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit',
    })
}

async function openReview(row) {
    active.value = { ...row, notes: row.notes || [] }
    noteText.value = ''
    try {
        const { data } = await api.get(`api/dashboard/reviews/${row.id}`)
        active.value = data.data
    } catch (err) { /* keep the list row data */ }
}
function closeReview() { active.value = null }

async function changeStatus(status) {
    if (!active.value || savingStatus.value) return
    savingStatus.value = true
    try {
        await ensureCsrf()
        const { data } = await api.patch(`api/dashboard/reviews/${active.value.id}/status`, { status })
        active.value = { ...active.value, status: data.data.status }
        const i = rows.value.findIndex((r) => r.id === active.value.id)
        if (i !== -1) rows.value[i] = { ...rows.value[i], status: data.data.status }
        loadSummary()
    } catch (err) {
        alert(t('rev.update_failed'))
    } finally {
        savingStatus.value = false
    }
}

async function addNote() {
    if (!active.value || !noteText.value.trim() || savingNote.value) return
    savingNote.value = true
    try {
        await ensureCsrf()
        const { data } = await api.post(`api/dashboard/reviews/${active.value.id}/notes`, { note: noteText.value })
        active.value = data.data
        noteText.value = ''
    } catch (err) {
        alert(t('rev.update_failed'))
    } finally {
        savingNote.value = false
    }
}
</script>

<template>
    <div class="space-y-5">
        <!-- Header -->
        <div>
            <h1 class="page-title">{{ t('rev.title') }}</h1>
            <p class="page-sub">{{ t('rev.subtitle') }}</p>
        </div>

        <!-- Summary tiles -->
        <div class="rev-tiles">
            <div class="card rev-tile">
                <div class="rev-tile-val">{{ summary.average }} <span class="rev-tile-star">★</span></div>
                <div class="rev-tile-label">{{ t('rev.avg') }}</div>
            </div>
            <div class="card rev-tile">
                <div class="rev-tile-val">{{ summary.count }}</div>
                <div class="rev-tile-label">{{ t('rev.total') }}</div>
            </div>
            <div class="card rev-tile rev-tile--low">
                <div class="rev-tile-val">{{ summary.low_count }}</div>
                <div class="rev-tile-label">{{ t('rev.low') }}</div>
            </div>
        </div>

        <!-- Filters -->
        <div class="space-y-2">
            <div class="flex items-center gap-2 flex-wrap">
                <button class="chip" :class="{ 'chip-on': ratingFilter === '' }" @click="setRating('')">{{ t('rev.all_ratings') }}</button>
                <button v-for="r in [5, 4, 3, 2, 1]" :key="r" class="chip" :class="{ 'chip-on': ratingFilter === r }" @click="setRating(r)">
                    {{ r }}★
                </button>
            </div>
            <div class="flex items-center gap-2 flex-wrap">
                <button class="chip" :class="{ 'chip-on': statusFilter === '' }" @click="setStatus('')">{{ t('common.all') }}</button>
                <button v-for="s in STATUSES" :key="s" class="chip" :class="{ 'chip-on': statusFilter === s }" @click="setStatus(s)">
                    {{ t('rev.status.' + s) }}
                </button>
            </div>
            <div class="flex items-center gap-2 flex-wrap">
                <select v-model="areaFilter" class="chip chip-select" @change="load">
                    <option value="">{{ t('rev.all_areas') }}</option>
                    <option v-for="a in areas" :key="a.id" :value="a.id">{{ locale === 'ar' ? (a.name_ar || a.name_en) : (a.name_en || a.name_ar) }}</option>
                </select>
                <input v-model="dateFrom" type="date" class="chip chip-select" @change="load" />
                <input v-model="dateTo" type="date" class="chip chip-select" @change="load" />
                <label class="chip rev-check">
                    <input v-model="contactOnly" type="checkbox" @change="load" />
                    <span>{{ t('rev.contact_only') }}</span>
                </label>
            </div>
        </div>

        <!-- List -->
        <template v-if="loading">
            <div class="space-y-2">
                <div v-for="n in 4" :key="'sk' + n" class="card p-4 space-y-2">
                    <Skeleton h="14px" w="30%" />
                    <Skeleton h="12px" w="80%" />
                </div>
            </div>
        </template>
        <div v-else-if="!rows.length" class="card px-5 py-10 text-center" style="color:var(--muted)">
            {{ t('rev.none') }}
        </div>
        <div v-else class="space-y-2">
            <button v-for="row in rows" :key="row.id" class="card rev-row" :class="{ 'rev-row--low': row.is_low }" @click="openReview(row)">
                <div class="rev-row-main">
                    <div class="rev-row-top">
                        <span class="rev-row-stars" :class="{ 'rev-row-stars--low': row.is_low }">{{ stars(row.rating) }}</span>
                        <span class="badge" :class="badgeClass[row.status]">{{ t('rev.status.' + row.status) }}</span>
                        <span v-if="row.is_low" class="badge badge-red">{{ t('rev.low_badge') }}</span>
                    </div>
                    <p v-if="row.comment" class="rev-row-comment">{{ row.comment }}</p>
                    <div class="rev-row-meta">
                        <span>{{ row.customer_name || t('rev.anonymous') }}</span>
                        <span v-if="row.table_label">· {{ t('rev.table') }} {{ row.table_label }}</span>
                        <span v-if="areaName(row)">· {{ areaName(row) }}</span>
                        <span>· {{ fmtDate(row.created_at) }}</span>
                    </div>
                </div>
            </button>
        </div>

        <!-- Detail dialog -->
        <Dialog v-if="active" :title="stars(active.rating)" :subtitle="t('rev.detail_sub')" @close="closeReview">
            <div class="space-y-4">
                <p v-if="active.comment" class="text-sm" style="color:var(--body)">{{ active.comment }}</p>
                <p v-else class="text-sm" style="color:var(--muted)">{{ t('rev.no_comment') }}</p>

                <div class="grid grid-cols-2 gap-3 text-sm">
                    <div><div class="label">{{ t('rev.customer') }}</div><div style="color:var(--ink)">{{ active.customer_name || t('rev.anonymous') }}</div></div>
                    <div v-if="active.customer_phone"><div class="label">{{ t('leads.whatsapp') }}</div><div style="color:var(--ink)" dir="ltr">{{ active.customer_phone }}</div></div>
                    <div v-if="active.table_label"><div class="label">{{ t('rev.table') }}</div><div style="color:var(--ink)">{{ active.table_label }}</div></div>
                    <div v-if="active.order_id"><div class="label">{{ t('rev.order_ref') }}</div><div style="color:var(--ink)">#{{ active.order_id }}</div></div>
                </div>
                <p v-if="active.contact_permission" class="text-sm" style="color:var(--green)">{{ t('rev.contact_ok') }}</p>

                <hr style="border-color:var(--line)" />

                <!-- Status actions -->
                <div>
                    <div class="label mb-1.5">{{ t('common.status') }}</div>
                    <div class="flex flex-wrap gap-2">
                        <button v-for="s in STATUSES" :key="s"
                            class="btn btn-sm" :class="active.status === s ? 'btn-accent' : 'btn-ghost'"
                            :disabled="savingStatus" @click="changeStatus(s)">
                            {{ t('rev.status.' + s) }}
                        </button>
                    </div>
                </div>

                <hr style="border-color:var(--line)" />

                <!-- Internal notes -->
                <div>
                    <div class="label">{{ t('rev.notes') }}</div>
                    <p class="text-xs mb-2" style="color:var(--muted)">{{ t('rev.notes_hint') }}</p>
                    <ul v-if="active.notes && active.notes.length" class="space-y-2 mb-3">
                        <li v-for="n in active.notes" :key="n.id" class="rev-note">
                            <div style="color:var(--body)">{{ n.note }}</div>
                            <div class="text-xs mt-1" style="color:var(--muted)">{{ n.user_name || '—' }} · {{ fmtDate(n.created_at) }}</div>
                        </li>
                    </ul>
                    <p v-else class="text-sm mb-3" style="color:var(--muted)">{{ t('rev.no_notes') }}</p>
                    <textarea v-model="noteText" rows="2" class="input" :placeholder="t('rev.note_ph')"></textarea>
                    <div class="flex justify-end mt-2">
                        <button class="btn btn-accent btn-sm" :disabled="savingNote || !noteText.trim()" @click="addNote">
                            {{ savingNote ? t('common.saving') : t('rev.add_note') }}
                        </button>
                    </div>
                </div>
            </div>
        </Dialog>
    </div>
</template>

<style scoped>
.chip { display: inline-flex; align-items: center; gap: 7px; padding: 7px 14px; border-radius: 20px;
    border: 1px solid var(--line); background: var(--card); color: var(--body); font-size: 13.5px; font-weight: 600; cursor: pointer; }
.chip-on { background: var(--accent); color: #fff; border-color: var(--accent); }
.chip-select { padding-inline-end: 10px; }
.rev-check { cursor: pointer; }
.rev-check input { width: 15px; height: 15px; }
.btn-sm { padding: 5px 11px; font-size: 12px; }
.rev-tiles { display: grid; grid-template-columns: repeat(3, 1fr); gap: 14px; }
.rev-tile { padding: 16px 18px; }
.rev-tile-val { font-size: 26px; font-weight: 800; color: var(--ink); line-height: 1.1; }
.rev-tile-star { color: #f5b301; font-size: 20px; }
.rev-tile-label { font-size: 13px; color: var(--muted); margin-top: 4px; }
.rev-tile--low .rev-tile-val { color: #c0392b; }
.rev-row { display: block; width: 100%; text-align: start; padding: 14px 16px; cursor: pointer; border: 1px solid var(--line); }
.rev-row:hover { border-color: var(--accent); }
.rev-row--low { border-inline-start: 3px solid #e0a106; }
.rev-row-top { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; }
.rev-row-stars { color: #f5b301; font-size: 15px; letter-spacing: 1px; }
.rev-row-stars--low { color: #e0a106; }
.rev-row-comment { font-size: 14px; color: var(--body); margin: 6px 0 4px; }
.rev-row-meta { font-size: 12.5px; color: var(--muted); display: flex; gap: 5px; flex-wrap: wrap; }
.rev-note { background: var(--accent-soft); border-radius: 10px; padding: 8px 10px; font-size: 13px; }
@media (max-width: 640px) { .rev-tiles { grid-template-columns: 1fr; } }
</style>
