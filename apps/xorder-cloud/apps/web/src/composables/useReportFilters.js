import { ref, reactive, computed } from 'vue'
import { useI18n } from 'vue-i18n'
import api from '@xorder/api-client/api.js'

// Shared filter state + formatters for the analytics report pages (Product
// performance, Dining-area comparison). The two pages render the same
// <ReportFilters> component and only differ in which extras they turn on
// (the products page adds group-by + export), so the underlying state, query
// params, presets and formatters live here and the pages can't drift apart.
export function useReportFilters() {
    const { t, locale } = useI18n()

    const branches = ref([])
    const areas = ref([])

    // One reactive object (instead of a dozen refs) so the whole filter bar can
    // be handed to <ReportFilters> as a single prop and stay two-way bound.
    const defaults = () => ({
        dateFrom: '',
        dateTo: '',
        timeFrom: '',
        timeTo: '',
        daysOfWeek: [],       // 0=Sunday … 6=Saturday (matches Date.getDay())
        branchId: '',
        areaId: '',
        areaType: '',
        orderType: '',
        includeCancelled: false,
        groupBy: 'period',
    })
    const state = reactive(defaults())

    const AREA_TYPES = ['indoor', 'outdoor', 'custom']
    const ORDER_TYPES = ['dine_in', 'pickup', 'delivery']

    // Query params shared by both report endpoints. `group` only matters to the
    // products-by-time report, but it's harmless on the dining-areas endpoint.
    function params() {
        return {
            date_from: state.dateFrom || undefined,
            date_to: state.dateTo || undefined,
            time_from: state.timeFrom || undefined,
            time_to: state.timeTo || undefined,
            days_of_week: state.daysOfWeek.length ? [...state.daysOfWeek] : undefined,
            branch_id: state.branchId || undefined,
            dining_area_id: state.areaId || undefined,
            area_type: state.areaType || undefined,
            order_type: state.orderType || undefined,
            include_cancelled: state.includeCancelled ? 1 : undefined,
            group: state.groupBy,
        }
    }

    async function loadFilters() {
        try {
            const [b, a] = await Promise.all([
                api.get('api/dashboard/branches'),
                api.get('api/dashboard/dining-areas'),
            ])
            branches.value = b.data.data || []
            areas.value = a.data.data || []
        } catch (err) { /* filters are optional */ }
    }

    function resetFilters() {
        Object.assign(state, defaults())
    }

    // --- Quick date presets -------------------------------------------------
    // Local calendar dates ("YYYY-MM-DD") so they line up with the <input
    // type="date"> values and the restaurant-local day boundaries the API uses.
    const pad = (n) => String(n).padStart(2, '0')
    const iso = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
    const shiftDays = (n) => {
        const d = new Date()
        d.setDate(d.getDate() + n)
        return iso(d)
    }
    const startOfMonth = () => {
        const d = new Date()
        return iso(new Date(d.getFullYear(), d.getMonth(), 1))
    }

    // Each preset resolves to a [from, to] pair; `active` compares against the
    // current range so the matching chip highlights even after a manual edit.
    const PRESETS = [
        { key: 'today', label: () => t('rep.preset_today'), range: () => [shiftDays(0), shiftDays(0)] },
        { key: 'yesterday', label: () => t('rep.preset_yesterday'), range: () => [shiftDays(-1), shiftDays(-1)] },
        { key: 'last7', label: () => t('rep.preset_7d'), range: () => [shiftDays(-6), shiftDays(0)] },
        { key: 'last30', label: () => t('rep.preset_30d'), range: () => [shiftDays(-29), shiftDays(0)] },
        { key: 'month', label: () => t('rep.preset_month'), range: () => [startOfMonth(), shiftDays(0)] },
    ]

    function applyPreset(key) {
        const preset = PRESETS.find((p) => p.key === key)
        if (!preset) return
        const [from, to] = preset.range()
        state.dateFrom = from
        state.dateTo = to
    }

    const activePreset = computed(() => {
        for (const p of PRESETS) {
            const [from, to] = p.range()
            if (state.dateFrom === from && state.dateTo === to) return p.key
        }
        return ''
    })

    // --- Day-of-week --------------------------------------------------------
    // 2023-01-01 was a Sunday, so offsetting it by d gives a reference date whose
    // localized short weekday name we can show (Sun … Sat, 0 … 6).
    const WEEKDAYS = [0, 1, 2, 3, 4, 5, 6]
    const weekdayLabel = (d) =>
        new Date(2023, 0, 1 + d).toLocaleDateString(locale.value, { weekday: 'short' })

    function toggleDay(d) {
        state.daysOfWeek = state.daysOfWeek.includes(d)
            ? state.daysOfWeek.filter((x) => x !== d)
            : [...state.daysOfWeek, d].sort((a, b) => a - b)
    }

    // --- Formatters ---------------------------------------------------------
    const localName = (row, base) => {
        const en = row[`${base}_en`], ar = row[`${base}_ar`]
        return (locale.value === 'ar' ? (ar || en) : (en || ar)) || '—'
    }

    // Hourly keys ("08:00") pass through; day keys ("2026-07-01") become a
    // localized date; everything else is a day-part key with a friendly label.
    const periodLabel = (key) => {
        if (!key) return t('rep.na')
        if (/^\d{2}:\d{2}$/.test(key)) return key
        if (/^\d{4}-\d{2}-\d{2}$/.test(key)) {
            return new Date(`${key}T00:00:00`).toLocaleDateString(locale.value, {
                weekday: 'short', day: 'numeric', month: 'short',
            })
        }
        return t(`rep.period.${key}`)
    }

    const typeLabel = (type) => {
        if (type === 'indoor') return t('rep.type_indoor')
        if (type === 'outdoor') return t('rep.type_outdoor')
        return t('rep.type_custom')
    }

    function fmtSecs(s) {
        if (s == null) return t('rep.na')
        return s >= 60 ? t('rep.mins', { n: Math.round(s / 60) }) : t('rep.secs', { n: s })
    }

    const money = (n) => Number(n || 0).toLocaleString(locale.value, { maximumFractionDigits: 2 })

    return {
        state, branches, areas,
        AREA_TYPES, ORDER_TYPES,
        PRESETS, activePreset, applyPreset,
        WEEKDAYS, weekdayLabel, toggleDay,
        params, loadFilters, resetFilters,
        localName, periodLabel, typeLabel, fmtSecs, money,
    }
}
