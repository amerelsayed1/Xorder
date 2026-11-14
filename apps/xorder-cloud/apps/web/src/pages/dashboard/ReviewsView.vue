<script setup>
import { ref, computed, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import { alert } from '@xorder/ui/alert.js'
import { useAuth } from '@xorder/api-client/auth.js'
import { useCaps } from '../../lib/useCaps.js'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import { withMinDuration } from '../../lib/minLoading.js'
import Skeleton from '@xorder/ui/Skeleton.vue'
import ErrorState from '@xorder/ui/ErrorState.vue'
import Dialog from '@xorder/ui/Dialog.vue'

const { t, locale } = useI18n()
const auth = useAuth()
// Moderating a review (status, notes) is an update.
const { canUpdate } = useCaps('reviews')

const STATUSES = ['NEW', 'IN_REVIEW', 'CONTACTED', 'RESOLVED', 'ARCHIVED']
const badgeClass = {
    NEW: 'badge-amber', IN_REVIEW: 'badge-indigo', CONTACTED: 'badge-indigo',
    RESOLVED: 'badge-green', ARCHIVED: 'badge-gray',
}

const rows = ref([])
const summary = ref({ average: 0, count: 0, low_count: 0, by_rating: {} })
const areas = ref([])
const loading = ref(true)
const error = ref(false)
const meta = ref(null)
const page = ref(1)

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
        page: page.value,
    }
}

async function load() {
    loading.value = true
    error.value = false
    try {
        const { data } = await withMinDuration(api.get('api/dashboard/reviews', { params: params() }))
        rows.value = data.data
        meta.value = data.meta || null
    } catch (err) {
        error.value = true
    } finally {
        loading.value = false
    }
}

// Any filter change resets to the first page before reloading.
function applyFilters() {
    page.value = 1
    load()
}

function goToPage(nextPage) {
    if (!meta.value || nextPage < 1 || nextPage > meta.value.last_page) return
    page.value = nextPage
    load()
}

onMounted(() => {
    loadAreas()
    loadSummary()
    load()
})

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

// Display-only: the summary endpoint already returns the per-star counts.
const ratingDist = computed(() => [5, 4, 3, 2, 1].map((star) => ({ star, n: summary.value.by_rating?.[star] || 0 })))
const distMax = computed(() => Math.max(1, ...ratingDist.value.map((d) => d.n)))
</script>

<template>
    <div class="space-y-5">
        <!-- Header -->
        <div>
            <h1 class="page-title">{{ t('rev.title') }}</h1>
            <p class="page-sub" style="color:var(--body)">{{ t('rev.subtitle') }}</p>
        </div>

        <!-- Summary. Low-rated leads: it is the one figure that asks for a reply. -->
        <section class="rev-summary" :aria-label="t('rev.title')">
            <div class="stat rev-low" :class="{ 'rev-low-hot': summary.low_count > 0 }">
                <div class="stat-label"><i class="pi pi-exclamation-triangle me-1.5" aria-hidden="true"></i>{{ t('rev.low') }}</div>
                <div class="stat-num">{{ summary.low_count }}</div>
            </div>
            <div class="stat">
                <div class="stat-label">{{ t('rev.total') }}</div>
                <div class="stat-num">{{ summary.count }}</div>
            </div>
            <div class="stat rev-avg">
                <div class="stat-label">{{ t('rev.avg') }}</div>
                <div class="rev-avg-body">
                    <div class="stat-num rev-avg-num">{{ summary.average }}<span class="rev-avg-star" aria-hidden="true">★</span></div>
                    <ul class="rev-dist" :aria-label="t('rev.avg')">
                        <li v-for="d in ratingDist" :key="d.star">
                            <span class="rev-dist-star">{{ d.star }} ★</span>
                            <span class="bar-track"><span class="bar-fill" :style="{ width: Math.round((d.n / distMax) * 100) + '%' }" /></span>
                            <span class="rev-dist-n">{{ d.n }}</span>
                        </li>
                    </ul>
                </div>
            </div>
        </section>

        <!-- Filters: status is the one staff use all day, so it is a tab strip
             with New first; the rest sit in a labelled row beneath it. -->
        <section class="card rev-filters" :aria-label="t('common.status')">
            <div class="segmented rev-status" role="group" :aria-label="t('common.status')">
                <button type="button" :class="{ active: statusFilter === '' }" :aria-pressed="statusFilter === ''" @click="statusFilter = ''; applyFilters()">{{ t('common.all') }}</button>
                <button v-for="s in STATUSES" :key="s" type="button" :class="{ active: statusFilter === s }" :aria-pressed="statusFilter === s" @click="statusFilter = s; applyFilters()">{{ t('rev.status.' + s) }}</button>
            </div>
            <div class="rev-controls">
                <select v-model="ratingFilter" class="ctl" :aria-label="t('rev.all_ratings')" @change="applyFilters">
                    <option value="">{{ t('rev.all_ratings') }}</option>
                    <option v-for="r in [5, 4, 3, 2, 1]" :key="r" :value="r">{{ r }} ★</option>
                </select>
                <select v-model="areaFilter" class="ctl" :aria-label="t('rev.all_areas')" @change="applyFilters">
                    <option value="">{{ t('rev.all_areas') }}</option>
                    <option v-for="a in areas" :key="a.id" :value="a.id">{{ locale === 'ar' ? (a.name_ar || a.name_en) : (a.name_en || a.name_ar) }}</option>
                </select>
                <input v-model="dateFrom" type="date" class="ctl" :aria-label="t('rep.date_from')" @change="applyFilters" />
                <input v-model="dateTo" type="date" class="ctl" :aria-label="t('rep.date_to')" @change="applyFilters" />
                <label class="ctl rev-check">
                    <input v-model="contactOnly" type="checkbox" @change="applyFilters" />
                    <span>{{ t('rev.contact_only') }}</span>
                </label>
            </div>
        </section>

        <!-- List -->
        <template v-if="loading">
            <div class="space-y-2" aria-busy="true">
                <div v-for="n in 4" :key="'sk' + n" class="card p-4 space-y-3">
                    <Skeleton h="18px" w="30%" />
                    <Skeleton h="14px" w="80%" />
                    <Skeleton h="12px" w="50%" />
                </div>
            </div>
        </template>
        <ErrorState v-else-if="error" @retry="load" />
        <div v-else-if="!rows.length" class="card px-5 py-12 text-center" style="color:var(--body)">
            <i class="pi pi-comments block mb-2" style="font-size:26px" aria-hidden="true"></i>
            {{ t('rev.none') }}
        </div>
        <ul v-else class="space-y-2">
            <li v-for="row in rows" :key="row.id">
                <button type="button" class="card rev-row" :class="{ 'rev-row--low': row.is_low, 'rev-row--new': !row.is_low && row.status === 'NEW' }" @click="openReview(row)">
                    <span class="rev-row-main">
                        <span class="rev-row-top">
                            <span class="rev-row-score" :class="{ 'rev-row-score--low': row.is_low }">{{ row.rating }}</span>
                            <span class="rev-row-stars" :class="{ 'rev-row-stars--low': row.is_low }" aria-hidden="true">{{ stars(row.rating) }}</span>
                            <span class="badge" :class="badgeClass[row.status]">{{ t('rev.status.' + row.status) }}</span>
                            <span v-if="row.is_low" class="badge badge-red"><i class="pi pi-exclamation-triangle" style="font-size:11px" aria-hidden="true"></i>{{ t('rev.low_badge') }}</span>
                        </span>
                        <span v-if="row.comment" class="rev-row-comment">{{ row.comment }}</span>
                        <span class="rev-row-meta">
                            <span>{{ row.customer_name || t('rev.anonymous') }}</span>
                            <span v-if="row.table_label">· {{ t('rev.table') }} {{ row.table_label }}</span>
                            <span v-if="areaName(row)">· {{ areaName(row) }}</span>
                            <span>· {{ fmtDate(row.created_at) }}</span>
                        </span>
                    </span>
                    <i class="pi pi-angle-right rev-go dir-flip" aria-hidden="true"></i>
                </button>
            </li>
        </ul>

        <!-- Pagination -->
        <div v-if="!error && meta && meta.last_page > 1" class="flex flex-wrap items-center justify-between gap-3">
            <span class="text-sm" style="color:var(--body)">
                {{ t('common.showing_range', { from: meta.from, to: meta.to, total: meta.total }) }}
            </span>
            <div class="flex items-center gap-2">
                <button class="btn btn-ghost btn-sm touch" :disabled="meta.current_page <= 1" @click="goToPage(meta.current_page - 1)">
                    {{ t('common.previous') }}
                </button>
                <span class="text-sm" style="color:var(--body)">{{ meta.current_page }} / {{ meta.last_page }}</span>
                <button class="btn btn-ghost btn-sm touch" :disabled="meta.current_page >= meta.last_page" @click="goToPage(meta.current_page + 1)">
                    {{ t('common.next') }}
                </button>
            </div>
        </div>

        <!-- Detail dialog -->
        <Dialog v-if="active" :title="stars(active.rating)" :subtitle="t('rev.detail_sub')" @close="closeReview">
            <div class="space-y-4">
                <p v-if="active.comment" class="rev-quote">{{ active.comment }}</p>
                <p v-else class="text-sm" style="color:var(--body)">{{ t('rev.no_comment') }}</p>

                <div class="grid grid-cols-2 gap-3 text-sm">
                    <div><div class="label">{{ t('rev.customer') }}</div><div style="color:var(--ink)">{{ active.customer_name || t('rev.anonymous') }}</div></div>
                    <div v-if="active.customer_phone"><div class="label">{{ t('leads.whatsapp') }}</div><div style="color:var(--ink)" dir="ltr">{{ active.customer_phone }}</div></div>
                    <div v-if="active.table_label"><div class="label">{{ t('rev.table') }}</div><div style="color:var(--ink)">{{ active.table_label }}</div></div>
                    <div v-if="active.order_id"><div class="label">{{ t('rev.order_ref') }}</div><div style="color:var(--ink)">#{{ active.order_id }}</div></div>
                </div>
                <p v-if="active.contact_permission" class="flex items-center gap-2 text-sm" style="color:var(--green)"><i class="pi pi-check-circle" aria-hidden="true"></i>{{ t('rev.contact_ok') }}</p>

                <hr style="border-color:var(--line)" />

                <!-- Status actions -->
                <div v-if="canUpdate">
                    <div class="label mb-1.5">{{ t('common.status') }}</div>
                    <div class="flex flex-wrap gap-2">
                        <button v-for="s in STATUSES" :key="s" type="button"
                            class="btn btn-sm touch" :class="active.status === s ? 'btn-accent st-on' : 'btn-ghost'"
                            :aria-pressed="active.status === s"
                            :disabled="savingStatus" @click="changeStatus(s)">
                            <i v-if="active.status === s" class="pi pi-check" style="font-size:12px" aria-hidden="true"></i>{{ t('rev.status.' + s) }}
                        </button>
                    </div>
                </div>

                <hr style="border-color:var(--line)" />

                <!-- Internal notes -->
                <div>
                    <div class="label">{{ t('rev.notes') }}</div>
                    <p class="text-sm mb-2" style="color:var(--body)">{{ t('rev.notes_hint') }}</p>
                    <ul v-if="active.notes && active.notes.length" class="space-y-2 mb-3">
                        <li v-for="n in active.notes" :key="n.id" class="rev-note">
                            <div style="color:var(--ink)">{{ n.note }}</div>
                            <div class="text-xs mt-1" style="color:var(--body)">{{ n.user_name || '—' }} · {{ fmtDate(n.created_at) }}</div>
                        </li>
                    </ul>
                    <p v-else class="text-sm mb-3" style="color:var(--body)">{{ t('rev.no_notes') }}</p>
                    <textarea v-if="canUpdate" v-model="noteText" rows="2" class="input" :placeholder="t('rev.note_ph')" :aria-label="t('rev.notes')"></textarea>
                    <div v-if="canUpdate" class="flex justify-end mt-2">
                        <button class="btn btn-accent btn-sm touch" :disabled="savingNote || !noteText.trim()" @click="addNote">
                            {{ savingNote ? t('common.saving') : t('rev.add_note') }}
                        </button>
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
[dir=rtl] .dir-flip { transform: scaleX(-1); }
.st-on { color: var(--ink); }

/* Summary */
.rev-summary { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 12px; }
.rev-summary .stat-label { color: var(--body); font-size: 14.5px; }
.rev-summary .stat-num { font-size: clamp(28px, 7vw, 34px); }
.rev-low-hot { background: var(--red-soft); border-color: var(--red); }
.rev-low-hot .stat-label { color: var(--ink); font-weight: 700; }
.rev-low-hot .stat-num { color: var(--red); }
.rev-avg { grid-column: 1 / -1; }
@media (min-width: 1024px) {
    .rev-summary { grid-template-columns: 1fr 1fr 2fr; }
    .rev-avg { grid-column: auto; }
}
.rev-avg-body { display: flex; align-items: center; gap: 24px; flex-wrap: wrap; }
.rev-avg-num { display: inline-flex; align-items: baseline; gap: 6px; margin-top: 0; }
.rev-avg-star { color: var(--accent); font-size: 24px; }
.rev-dist { list-style: none; margin: 0; padding: 0; flex: 1 1 220px; min-width: 0; display: flex; flex-direction: column; gap: 5px; }
.rev-dist li { display: flex; align-items: center; gap: 10px; font-size: 14px; color: var(--body); }
.rev-dist-star { width: 34px; flex: none; font-variant-numeric: tabular-nums; }
.rev-dist-n { width: 32px; flex: none; text-align: end; font-weight: 600; color: var(--ink); font-variant-numeric: tabular-nums; }
.bar-track { display: block; flex: 1; height: 8px; border-radius: 4px; background: var(--gray-soft); }
.bar-fill { display: block; height: 8px; border-radius: 4px; background: var(--accent); }

/* Filters */
.rev-filters { padding: 12px 14px; display: flex; flex-direction: column; gap: 12px; }
.rev-status { max-width: 100%; overflow-x: auto; align-self: flex-start; }
.rev-status button { min-height: 40px; white-space: nowrap; font-size: 14.5px; }
.rev-controls { display: flex; flex-wrap: wrap; gap: 8px; }
.ctl { display: inline-flex; align-items: center; gap: 8px; min-height: 44px; padding: 0 14px; border-radius: 10px;
    border: 1px solid var(--line); background: var(--card); color: var(--ink); font-size: 14.5px; font-family: inherit; }
.ctl:focus-visible { outline: 2px solid var(--accent); outline-offset: 1px; }
.rev-check { cursor: pointer; color: var(--body); }
.rev-check input { width: 18px; height: 18px; accent-color: var(--accent); }

/* Review rows */
.rev-row { display: flex; align-items: center; gap: 12px; width: 100%; text-align: start; padding: 14px 16px; min-height: 64px; cursor: pointer;
    border: 1px solid var(--line); border-inline-start-width: 5px; border-inline-start-color: var(--line);
    transition: border-color .15s, background .15s; }
.rev-row:hover { background: var(--page); border-color: var(--accent); }
.rev-row--new { border-inline-start-color: var(--accent); }
.rev-row--low { border-inline-start-color: var(--red); }
.rev-row-main { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 6px; }
.rev-row-top { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; }
.rev-row-score { font-family: var(--font-display); font-weight: 800; font-size: 22px; line-height: 1; color: var(--ink); min-width: 18px; }
.rev-row-score--low { color: var(--red); }
.rev-row-stars { color: var(--accent); font-size: 15px; letter-spacing: 1px; }
.rev-row-stars--low { color: var(--red); }
.rev-row-comment { font-size: 15.5px; color: var(--ink); display: -webkit-box; -webkit-line-clamp: 3; -webkit-box-orient: vertical; overflow: hidden; }
.rev-row-meta { font-size: 13.5px; color: var(--body); display: flex; gap: 5px; flex-wrap: wrap; }
.rev-go { color: var(--body); font-size: 14px; flex: none; }
.rev-quote { font-size: 16px; color: var(--ink); background: var(--page); border-radius: 12px; padding: 12px 14px; }
.rev-note { background: var(--accent-soft); border-radius: 10px; padding: 8px 10px; font-size: 14px; }
</style>
