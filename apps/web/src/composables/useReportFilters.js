import { ref } from 'vue'
import { useI18n } from 'vue-i18n'
import api from '@xorder/api-client/api.js'

// Shared filter state + formatters for the analytics report pages (Product
// performance, Dining-area comparison). Each page renders its own filter bar
// markup — the products page adds group-by + export, the areas page doesn't —
// but the underlying state, query params and formatters live here so the two
// pages can't drift apart.
export function useReportFilters() {
    const { t, locale } = useI18n()

    const branches = ref([])
    const areas = ref([])

    const dateFrom = ref('')
    const dateTo = ref('')
    const timeFrom = ref('')
    const timeTo = ref('')
    const branchId = ref('')
    const areaId = ref('')
    const areaType = ref('')
    const orderType = ref('')
    const includeCancelled = ref(false)
    const groupBy = ref('period')

    const AREA_TYPES = ['indoor', 'outdoor', 'custom']
    const ORDER_TYPES = ['dine_in', 'pickup', 'delivery']

    // Query params shared by both report endpoints. `group` only matters to the
    // products-by-time report, but it's harmless on the dining-areas endpoint.
    function params() {
        return {
            date_from: dateFrom.value || undefined,
            date_to: dateTo.value || undefined,
            time_from: timeFrom.value || undefined,
            time_to: timeTo.value || undefined,
            branch_id: branchId.value || undefined,
            dining_area_id: areaId.value || undefined,
            area_type: areaType.value || undefined,
            order_type: orderType.value || undefined,
            include_cancelled: includeCancelled.value ? 1 : undefined,
            group: groupBy.value,
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
        dateFrom.value = ''
        dateTo.value = ''
        timeFrom.value = ''
        timeTo.value = ''
        branchId.value = ''
        areaId.value = ''
        areaType.value = ''
        orderType.value = ''
        includeCancelled.value = false
        groupBy.value = 'period'
    }

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
        branches, areas,
        dateFrom, dateTo, timeFrom, timeTo, branchId, areaId, areaType, orderType, includeCancelled, groupBy,
        AREA_TYPES, ORDER_TYPES,
        params, loadFilters, resetFilters,
        localName, periodLabel, typeLabel, fmtSecs, money,
    }
}
