<script setup>
// Waiter shifts (POS-BE-033 shift clock): when each waiter started and
// finished a shift on the XOrder Waiter handheld. Read-only — the handheld is
// the only author. The server gates it with feature:table_management +
// can:staff.view; the route guard mirrors the capability and the sidebar
// entry carries the feature.
import { ref, reactive, computed, onMounted, onBeforeUnmount } from 'vue'
import { useI18n } from 'vue-i18n'
import api from '@xorder/api-client/api.js'
import { withMinDuration } from '../../lib/minLoading.js'
import ErrorState from '@xorder/ui/ErrorState.vue'
import SettingsHeader from './settings/SettingsHeader.vue'

const { t, locale } = useI18n()

const rows = ref([])
const totals = ref([])
const waiters = ref([])
const meta = ref({ current_page: 1, last_page: 1, total: 0 })
const range = ref({ from: '', to: '', timezone: '' })
const loading = ref(true)
const failed = ref(false)

// Empty dates let the server pick its default (the restaurant's last 7 days)
// and echo the range back, which then fills the inputs.
const filters = reactive({ from: '', to: '', user_id: '' })
const page = ref(1)

async function load() {
    loading.value = true
    failed.value = false
    try {
        const params = { page: page.value }
        if (filters.from) params.from = filters.from
        if (filters.to) params.to = filters.to
        if (filters.user_id) params.user_id = filters.user_id
        const { data } = await withMinDuration(api.get('api/dashboard/waiter-shifts', { params }))
        rows.value = data.data
        totals.value = data.totals
        waiters.value = data.waiters
        meta.value = data.meta
        range.value = data.range
        filters.from = data.range.from
        filters.to = data.range.to
    } catch (err) {
        failed.value = true
    } finally {
        loading.value = false
    }
}

function applyFilters() {
    // The server refuses an inverted range; keep the pair consistent instead.
    if (filters.from && filters.to && filters.from > filters.to) filters.to = filters.from
    page.value = 1
    load()
}

function goTo(p) {
    page.value = p
    load()
}

// Open shifts count up while the page is open: re-render against a ticking
// "now" (every 30 s, so a minute never lags by more than half) rather than
// refetching.
const now = ref(Date.now())
let timer = null
onMounted(() => {
    load()
    timer = setInterval(() => { now.value = Date.now() }, 30000)
})
onBeforeUnmount(() => clearInterval(timer))

// The server's duration is as of the response; an open shift adds the time
// since the shift started, measured on this clock.
function minutesOf(r) {
    if (!r.open) return r.duration_minutes
    return Math.max(0, Math.floor((now.value - new Date(r.started_at).getTime()) / 60000))
}

function fmtDuration(min) {
    const h = Math.floor(min / 60)
    const m = min % 60
    return h > 0 ? t('waiter_shifts.hours_minutes', { h, m }) : t('waiter_shifts.minutes', { m })
}

// Times in the restaurant's own zone, the same zone the range is cut in.
const fmt = computed(() => {
    const opts = { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' }
    try {
        return new Intl.DateTimeFormat(locale.value, range.value.timezone ? { ...opts, timeZone: range.value.timezone } : opts)
    } catch {
        return new Intl.DateTimeFormat(locale.value, opts)
    }
})
const fmtTime = (iso) => (iso ? fmt.value.format(new Date(iso)) : '—')

// Totals: the server sums the range as of the response; add the live part of
// each open shift so the totals tick with the rows on this page.
const openRows = computed(() => rows.value.filter((r) => r.open))
function totalMinutes(tot) {
    if (!tot.on_shift) return tot.minutes
    const open = openRows.value.find((r) => r.user_id === tot.user_id)
    return open ? tot.minutes - open.duration_minutes + minutesOf(open) : tot.minutes
}
</script>

<template>
    <SettingsHeader :title="t('nav.waiter_shifts')" :desc="t('waiter_shifts.subtitle')" />

    <div class="set-card">
        <div class="set-card-body">
            <div class="ws-filters">
                <label class="ws-field">
                    <span class="label">{{ t('waiter_shifts.from') }}</span>
                    <input v-model="filters.from" type="date" class="input" dir="ltr" @change="applyFilters" />
                </label>
                <label class="ws-field">
                    <span class="label">{{ t('waiter_shifts.to') }}</span>
                    <input v-model="filters.to" type="date" class="input" dir="ltr" @change="applyFilters" />
                </label>
                <label class="ws-field ws-field-wide">
                    <span class="label">{{ t('waiter_shifts.waiter') }}</span>
                    <select v-model="filters.user_id" class="input" @change="applyFilters">
                        <option value="">{{ t('waiter_shifts.all_waiters') }}</option>
                        <option v-for="w in waiters" :key="w.id" :value="w.id">{{ w.name }}</option>
                    </select>
                </label>
            </div>
            <p v-if="range.timezone" class="set-note">{{ t('waiter_shifts.range_note', { tz: range.timezone }) }}</p>
        </div>
    </div>

    <ErrorState v-if="failed" :message="t('common.error')" @retry="load" />

    <div v-else-if="loading" class="set-stack">
        <div v-for="n in 3" :key="n" class="set-skel" style="height: 72px"></div>
    </div>

    <div v-else-if="!rows.length" class="set-card">
        <div class="set-empty">
            <span class="set-empty-title">{{ t('waiter_shifts.none') }}</span>
            <span class="set-empty-hint">{{ t('waiter_shifts.none_hint') }}</span>
        </div>
    </div>

    <template v-else>
        <div v-if="totals.length" class="set-card">
            <div class="set-card-head">
                <div class="set-card-head-text">
                    <span class="set-card-title">{{ t('waiter_shifts.totals') }}</span>
                </div>
            </div>
            <div class="set-list">
                <div v-for="tot in totals" :key="tot.user_id" class="set-list-row ws-total">
                    <div class="set-row-name">
                        <strong>{{ tot.waiter_name || t('waiter_shifts.unknown_waiter') }}</strong>
                        <span v-if="tot.on_shift" class="set-chip set-chip-green"><span class="dot"></span>{{ t('waiter_shifts.on_shift') }}</span>
                    </div>
                    <span class="set-note">{{ t('waiter_shifts.shifts_count', { n: tot.shifts }, tot.shifts) }}</span>
                    <span class="set-fact-value mono ws-total-value">{{ fmtDuration(totalMinutes(tot)) }}</span>
                </div>
            </div>
        </div>

        <div class="set-stack">
            <div v-for="r in rows" :key="r.id" class="set-row">
                <div class="set-row-id" style="min-width: 170px">
                    <div class="set-row-name">
                        <strong>{{ r.waiter_name || t('waiter_shifts.unknown_waiter') }}</strong>
                        <span class="set-chip" :class="r.open ? 'set-chip-green' : ''">
                            <span class="dot"></span>{{ r.open ? t('waiter_shifts.on_shift') : t('waiter_shifts.finished') }}
                        </span>
                    </div>
                </div>

                <div class="set-facts">
                    <div class="set-fact">
                        <span class="set-fact-label">{{ t('waiter_shifts.started') }}</span>
                        <span class="set-fact-value">{{ fmtTime(r.started_at) }}</span>
                    </div>
                    <div class="set-fact">
                        <span class="set-fact-label">{{ t('waiter_shifts.ended') }}</span>
                        <span class="set-fact-value">{{ r.open ? '—' : fmtTime(r.ended_at) }}</span>
                    </div>
                    <div class="set-fact">
                        <span class="set-fact-label">{{ t('waiter_shifts.duration') }}</span>
                        <span class="set-fact-value mono">{{ fmtDuration(minutesOf(r)) }}</span>
                    </div>
                    <div class="set-fact">
                        <span class="set-fact-label">{{ t('waiter_shifts.started_on') }}</span>
                        <span class="set-fact-value">{{ r.started_device || t('waiter_shifts.unknown_device') }}</span>
                    </div>
                    <div v-if="!r.open" class="set-fact">
                        <span class="set-fact-label">{{ t('waiter_shifts.ended_on') }}</span>
                        <span class="set-fact-value">{{ r.ended_device || t('waiter_shifts.unknown_device') }}</span>
                    </div>
                </div>
            </div>
        </div>

        <div v-if="meta.last_page > 1" class="ws-pager">
            <button type="button" class="set-btn set-btn-sm" :disabled="meta.current_page <= 1" @click="goTo(meta.current_page - 1)">
                {{ t('waiter_shifts.prev') }}
            </button>
            <span class="set-note">{{ t('waiter_shifts.page', { page: meta.current_page, last: meta.last_page }) }}</span>
            <button type="button" class="set-btn set-btn-sm" :disabled="meta.current_page >= meta.last_page" @click="goTo(meta.current_page + 1)">
                {{ t('waiter_shifts.next') }}
            </button>
        </div>
    </template>
</template>

<style scoped>
.ws-filters { display: flex; flex-wrap: wrap; gap: 12px 16px; align-items: flex-end; }
.ws-field { display: flex; flex-direction: column; flex: 0 1 180px; min-width: 150px; }
.ws-field-wide { flex: 1 1 220px; }
.ws-total { display: flex; align-items: center; gap: 12px; flex-wrap: wrap; padding: 12px 18px; }
.ws-total-value { margin-inline-start: auto; }
.ws-pager { display: flex; align-items: center; justify-content: center; gap: 12px; }
</style>
