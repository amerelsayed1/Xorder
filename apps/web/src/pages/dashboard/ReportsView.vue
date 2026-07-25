<script setup>
import { ref, computed, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import api from '@xorder/api-client/api.js'
import { withMinDuration } from '../../lib/minLoading.js'
import Skeleton from '@xorder/ui/Skeleton.vue'
import ApexChart from '../../components/ApexChart.vue'
import { columnChart, barChart } from '../../lib/charts.js'

const { t, locale } = useI18n()

const report = ref(null)
const areaReport = ref(null)
const branches = ref([])
const areas = ref([])
const loading = ref(true)
const exporting = ref('')

const dateFrom = ref('')
const dateTo = ref('')
const branchId = ref('')
const areaId = ref('')
const areaType = ref('')
const orderType = ref('')
const includeCancelled = ref(false)
const groupBy = ref('period')

const AREA_TYPES = ['indoor', 'outdoor', 'custom']
const ORDER_TYPES = ['dine_in', 'pickup', 'delivery']

function params() {
    return {
        date_from: dateFrom.value || undefined,
        date_to: dateTo.value || undefined,
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

async function load() {
    loading.value = true
    try {
        const [products, areasRes] = await withMinDuration(Promise.all([
            api.get('api/dashboard/reports/products-by-time', { params: params() }),
            api.get('api/dashboard/reports/dining-areas', { params: params() }),
        ]))
        report.value = products.data.data
        areaReport.value = areasRes.data.data
    } catch (err) {
        alert(t('rep.load_failed'))
    } finally {
        loading.value = false
    }
}

function reset() {
    dateFrom.value = ''; dateTo.value = ''; branchId.value = ''; areaId.value = ''
    areaType.value = ''; orderType.value = ''; includeCancelled.value = false; groupBy.value = 'period'
    load()
}

async function doExport(format) {
    if (exporting.value) return
    exporting.value = format
    try {
        const res = await api.get('api/dashboard/reports/products-by-time/export', {
            params: { ...params(), format },
            responseType: 'blob',
        })
        const blobUrl = URL.createObjectURL(res.data)
        const a = document.createElement('a')
        a.href = blobUrl
        a.download = `products-by-time.${format === 'xlsx' ? 'xlsx' : 'csv'}`
        a.click()
        URL.revokeObjectURL(blobUrl)
    } catch (err) {
        alert(t('rep.load_failed'))
    } finally {
        exporting.value = ''
    }
}

onMounted(() => { loadFilters(); load() })

const localName = (row, base) => {
    const en = row[`${base}_en`], ar = row[`${base}_ar`]
    return (locale.value === 'ar' ? (ar || en) : (en || ar)) || '—'
}

// Day-part keys get a friendly label; hourly keys ("08:00") pass through.
const periodLabel = (key) => {
    if (!key) return t('rep.na')
    if (/^\d{2}:\d{2}$/.test(key)) return key
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

// Max quantity for the inline bar in the product table.
const maxQty = computed(() => Math.max(1, ...((report.value?.products || []).map((p) => p.quantity))))

const hasProducts = computed(() => (report.value?.products || []).length > 0)
const hasAreas = computed(() => (areaReport.value?.areas || []).some((a) => a.total_orders > 0 || a.bill_requests > 0))

// Sales-by-period — Flowbite column chart over the report's period buckets.
function periodSalesOptions(c) {
    const periods = report.value?.periods || []
    return columnChart({
        colors: c,
        categories: periods.map((p) => periodLabel(p.key)),
        series: [{ name: t('rep.sales'), data: periods.map((p) => Number(p.total_sales) || 0) }],
        palette: [c.accent],
        money: true,
        height: 300,
    })
}

// Dining-area comparison — Flowbite horizontal bar chart of orders per area.
const chartAreas = computed(() => (areaReport.value?.areas || []).filter((a) => a.total_orders > 0))
function areaOrdersOptions(c) {
    return barChart({
        colors: c,
        categories: chartAreas.value.map((a) => localName(a, 'name')),
        series: [{ name: t('rep.orders'), data: chartAreas.value.map((a) => a.total_orders) }],
        color: c.accent,
        height: Math.max(200, chartAreas.value.length * 42),
    })
}
</script>

<template>
    <div class="space-y-5">
        <div>
            <h1 class="page-title">{{ t('rep.title') }}</h1>
            <p class="page-sub">{{ t('rep.subtitle') }}</p>
        </div>

        <!-- Filters -->
        <div class="card p-4 space-y-3">
            <div class="rep-filters">
                <label class="rep-field">
                    <span class="label">{{ t('rep.date_from') }}</span>
                    <input v-model="dateFrom" type="date" class="input" />
                </label>
                <label class="rep-field">
                    <span class="label">{{ t('rep.date_to') }}</span>
                    <input v-model="dateTo" type="date" class="input" />
                </label>
                <label class="rep-field">
                    <span class="label">{{ t('rep.branch') }}</span>
                    <select v-model="branchId" class="input">
                        <option value="">{{ t('rep.all_branches') }}</option>
                        <option v-for="b in branches" :key="b.id" :value="b.id">{{ localName(b, 'name') }}</option>
                    </select>
                </label>
                <label class="rep-field">
                    <span class="label">{{ t('rep.area') }}</span>
                    <select v-model="areaId" class="input">
                        <option value="">{{ t('rep.all_areas') }}</option>
                        <option v-for="a in areas" :key="a.id" :value="a.id">{{ localName(a, 'name') }}</option>
                    </select>
                </label>
                <label class="rep-field">
                    <span class="label">{{ t('rep.type') }}</span>
                    <select v-model="areaType" class="input">
                        <option value="">{{ t('rep.all_types') }}</option>
                        <option v-for="ty in AREA_TYPES" :key="ty" :value="ty">{{ typeLabel(ty) }}</option>
                    </select>
                </label>
                <label class="rep-field">
                    <span class="label">{{ t('nav.orders') }}</span>
                    <select v-model="orderType" class="input">
                        <option value="">{{ t('rep.all_order_types') }}</option>
                        <option v-for="ot in ORDER_TYPES" :key="ot" :value="ot">{{ t('order_type.' + ot) }}</option>
                    </select>
                </label>
                <label class="rep-field">
                    <span class="label">{{ t('rep.group_by') }}</span>
                    <select v-model="groupBy" class="input">
                        <option value="period">{{ t('rep.by_period') }}</option>
                        <option value="hour">{{ t('rep.by_hour') }}</option>
                    </select>
                </label>
            </div>
            <div class="flex items-center gap-3 flex-wrap">
                <label class="rep-check">
                    <input v-model="includeCancelled" type="checkbox" />
                    <span>{{ t('rep.include_cancelled') }}</span>
                </label>
                <div class="flex-1"></div>
                <button class="btn btn-ghost btn-sm" @click="reset">{{ t('rep.reset') }}</button>
                <button class="btn btn-accent btn-sm" @click="load">{{ t('rep.apply') }}</button>
                <button class="btn btn-ghost btn-sm" :disabled="!!exporting" @click="doExport('csv')">
                    {{ exporting === 'csv' ? t('rep.exporting') : t('rep.export_csv') }}
                </button>
                <button class="btn btn-ghost btn-sm" :disabled="!!exporting" @click="doExport('xlsx')">
                    {{ exporting === 'xlsx' ? t('rep.exporting') : t('rep.export_xlsx') }}
                </button>
            </div>
        </div>

        <template v-if="loading">
            <div class="card p-4 space-y-3">
                <Skeleton h="16px" w="30%" />
                <Skeleton v-for="n in 5" :key="'s' + n" h="14px" w="90%" />
            </div>
        </template>

        <template v-else>
            <!-- Product performance -->
            <div class="card p-4 space-y-3">
                <div>
                    <h2 class="rep-h2">{{ t('rep.products_title') }}</h2>
                    <p class="page-sub">{{ t('rep.products_sub') }}</p>
                </div>

                <div v-if="!hasProducts" class="py-8 text-center" style="color:var(--muted)">
                    {{ t('rep.no_products') }}
                </div>

                <template v-else>
                    <!-- Top / low performers -->
                    <div class="rep-perf">
                        <div class="rep-perf-col">
                            <div class="label mb-1.5">{{ t('rep.top_performers') }}</div>
                            <div v-for="p in report.top_performers" :key="'top' + p.name" class="rep-perf-row">
                                <span class="rep-perf-name">{{ p.name }}</span>
                                <span class="badge badge-green">{{ p.quantity }}</span>
                            </div>
                        </div>
                        <div v-if="report.low_performers?.length" class="rep-perf-col">
                            <div class="label mb-1.5">{{ t('rep.low_performers') }}</div>
                            <div v-for="p in report.low_performers" :key="'low' + p.name" class="rep-perf-row">
                                <span class="rep-perf-name">{{ p.name }}</span>
                                <span class="badge badge-gray">{{ p.quantity }}</span>
                            </div>
                        </div>
                    </div>

                    <!-- Full product table -->
                    <div class="rep-table-wrap">
                        <table class="rep-table">
                            <thead>
                                <tr>
                                    <th>{{ t('rep.product') }}</th>
                                    <th class="num">{{ t('rep.quantity') }}</th>
                                    <th class="num">{{ t('rep.orders') }}</th>
                                    <th class="num">{{ t('rep.sales') }}</th>
                                    <th class="num">{{ t('rep.avg_qty') }}</th>
                                    <th class="num">{{ t('rep.pct_orders') }}</th>
                                    <th>{{ t('rep.most_active') }}</th>
                                </tr>
                            </thead>
                            <tbody>
                                <tr v-for="p in report.products" :key="p.name">
                                    <td>
                                        <div class="rep-prod">
                                            <span>{{ p.name }}</span>
                                            <span class="rep-bar"><span class="rep-bar-fill" :style="{ width: (p.quantity / maxQty * 100) + '%' }"></span></span>
                                        </div>
                                    </td>
                                    <td class="num">{{ p.quantity }}</td>
                                    <td class="num">{{ p.orders_containing }}</td>
                                    <td class="num">{{ money(p.total_sales) }}</td>
                                    <td class="num">{{ p.avg_qty_per_order }}</td>
                                    <td class="num">{{ p.pct_of_orders }}%</td>
                                    <td>{{ periodLabel(p.most_active_period) }}</td>
                                </tr>
                            </tbody>
                        </table>
                    </div>

                    <!-- Sales by period (chart) -->
                    <div v-if="(report.periods || []).length">
                        <div class="label mb-2">{{ t('rep.sales') }} · {{ t('rep.by_period_title') }}</div>
                        <ApexChart :build="periodSalesOptions" :redraw="[report, locale]" />
                    </div>

                    <!-- Per-period breakdown -->
                    <div>
                        <div class="label mb-2">{{ t('rep.by_period_title') }}</div>
                        <div class="rep-periods">
                            <div v-for="per in report.periods" :key="per.key" class="rep-period">
                                <div class="rep-period-top">
                                    <strong>{{ periodLabel(per.key) }}</strong>
                                    <span class="rep-period-orders">{{ t('rep.period_orders', { n: per.total_orders }) }}</span>
                                </div>
                                <div class="rep-period-sales">{{ money(per.total_sales) }}</div>
                                <ul class="rep-period-items">
                                    <li v-for="pi in per.products.slice(0, 3)" :key="pi.name">
                                        <span>{{ pi.name }}</span><span>{{ pi.quantity }}</span>
                                    </li>
                                </ul>
                            </div>
                        </div>
                    </div>
                </template>
            </div>

            <!-- Dining-area comparison -->
            <div class="card p-4 space-y-3">
                <div>
                    <h2 class="rep-h2">{{ t('rep.areas_title') }}</h2>
                    <p class="page-sub">{{ t('rep.areas_sub') }}</p>
                </div>

                <div v-if="!hasAreas" class="py-8 text-center" style="color:var(--muted)">
                    {{ t('rep.no_areas') }}
                </div>

                <template v-else>
                    <!-- Indoor vs outdoor roll-up -->
                    <div class="rep-rollups">
                        <div v-for="ty in (areaReport.by_type || [])" :key="'ty' + ty.type" class="rep-rollup">
                            <div class="rep-rollup-label">{{ typeLabel(ty.type) }}</div>
                            <div class="rep-rollup-val">{{ ty.total_orders }}</div>
                            <div class="rep-rollup-sub">{{ t('rep.orders') }} · {{ money(ty.total_sales) }}</div>
                        </div>
                    </div>

                    <!-- Orders per area (chart) -->
                    <div v-if="chartAreas.length">
                        <div class="label mb-2">{{ t('rep.orders') }} · {{ t('rep.area') }}</div>
                        <ApexChart :build="areaOrdersOptions" :redraw="[areaReport, locale]" />
                    </div>

                    <div class="rep-table-wrap">
                        <table class="rep-table">
                            <thead>
                                <tr>
                                    <th>{{ t('rep.area') }}</th>
                                    <th>{{ t('rep.branch') }}</th>
                                    <th>{{ t('rep.type') }}</th>
                                    <th class="num">{{ t('rep.orders') }}</th>
                                    <th class="num">{{ t('rep.sales') }}</th>
                                    <th class="num">{{ t('rep.aov') }}</th>
                                    <th class="num">{{ t('rep.bill_requests') }}</th>
                                    <th class="num">{{ t('rep.response_time') }}</th>
                                    <th class="num">{{ t('rep.completion_time') }}</th>
                                    <th class="num">{{ t('rep.rating') }}</th>
                                    <th class="num">{{ t('rep.negatives') }}</th>
                                </tr>
                            </thead>
                            <tbody>
                                <tr v-for="a in areaReport.areas" :key="a.id">
                                    <td>{{ localName(a, 'name') }}</td>
                                    <td>{{ localName(a, 'branch_name') }}</td>
                                    <td>{{ typeLabel(a.type) }}</td>
                                    <td class="num">{{ a.total_orders }}</td>
                                    <td class="num">{{ money(a.total_sales) }}</td>
                                    <td class="num">{{ money(a.avg_order_value) }}</td>
                                    <td class="num">{{ a.bill_requests }}</td>
                                    <td class="num">{{ fmtSecs(a.avg_response_seconds) }}</td>
                                    <td class="num">{{ fmtSecs(a.avg_completion_seconds) }}</td>
                                    <td class="num">{{ a.avg_review_rating != null ? a.avg_review_rating + '★' : t('rep.na') }}</td>
                                    <td class="num">{{ a.negative_review_count }}</td>
                                </tr>
                            </tbody>
                        </table>
                    </div>
                </template>
            </div>
        </template>
    </div>
</template>

<style scoped>
.rep-h2 { font-size: 17px; font-weight: 700; color: var(--ink); }
.rep-filters { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 12px; }
.rep-field { display: flex; flex-direction: column; gap: 4px; }
.rep-field .label { font-size: 12px; color: var(--muted); }
.rep-check { display: inline-flex; align-items: center; gap: 7px; font-size: 13.5px; color: var(--body); cursor: pointer; }
.rep-check input { width: 15px; height: 15px; }
.btn-sm { padding: 6px 13px; font-size: 12.5px; }

.rep-perf { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; }
.rep-perf-row { display: flex; align-items: center; justify-content: space-between; gap: 8px; padding: 5px 0; border-bottom: 1px solid var(--line); font-size: 13.5px; color: var(--body); }
.rep-perf-name { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }

.rep-table-wrap { overflow-x: auto; }
.rep-table { width: 100%; border-collapse: collapse; font-size: 13.5px; }
.rep-table th, .rep-table td { text-align: start; padding: 8px 10px; border-bottom: 1px solid var(--line); white-space: nowrap; }
.rep-table th { color: var(--muted); font-weight: 600; font-size: 12px; }
.rep-table td { color: var(--body); }
.rep-table .num { text-align: end; font-variant-numeric: tabular-nums; }
.rep-prod { display: flex; flex-direction: column; gap: 3px; min-width: 140px; }
.rep-bar { display: block; height: 4px; border-radius: 3px; background: var(--accent-soft); overflow: hidden; }
.rep-bar-fill { display: block; height: 100%; background: var(--accent); }

.rep-periods { display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: 12px; }
.rep-period { border: 1px solid var(--line); border-radius: 12px; padding: 12px; }
.rep-period-top { display: flex; align-items: center; justify-content: space-between; gap: 8px; }
.rep-period-top strong { font-size: 14px; color: var(--ink); }
.rep-period-orders { font-size: 12px; color: var(--muted); }
.rep-period-sales { font-size: 18px; font-weight: 700; color: var(--accent); margin: 4px 0 8px; }
.rep-period-items { list-style: none; margin: 0; padding: 0; font-size: 12.5px; color: var(--body); }
.rep-period-items li { display: flex; justify-content: space-between; gap: 8px; padding: 2px 0; }

.rep-rollups { display: grid; grid-template-columns: repeat(auto-fit, minmax(130px, 1fr)); gap: 12px; }
.rep-rollup { border: 1px solid var(--line); border-radius: 12px; padding: 12px 14px; }
.rep-rollup-label { font-size: 12.5px; color: var(--muted); }
.rep-rollup-val { font-size: 24px; font-weight: 800; color: var(--ink); line-height: 1.2; }
.rep-rollup-sub { font-size: 12px; color: var(--muted); }

@media (max-width: 640px) {
    .rep-perf { grid-template-columns: 1fr; }
}
</style>
