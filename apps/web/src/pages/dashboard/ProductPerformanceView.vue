<script setup>
import { ref, computed, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import api from '@xorder/api-client/api.js'
import { withMinDuration } from '../../lib/minLoading.js'
import Skeleton from '@xorder/ui/Skeleton.vue'
import ApexChart from '../../components/ApexChart.vue'
import { columnChart } from '../../lib/charts.js'
import { useReportFilters } from '../../composables/useReportFilters.js'

const { t, locale } = useI18n()

const {
    branches, areas,
    dateFrom, dateTo, timeFrom, timeTo, branchId, areaId, areaType, orderType, includeCancelled, groupBy,
    AREA_TYPES, ORDER_TYPES,
    params, loadFilters, resetFilters,
    localName, periodLabel, money,
} = useReportFilters()

const report = ref(null)
const loading = ref(true)
const exporting = ref('')

async function load() {
    loading.value = true
    try {
        const products = await withMinDuration(
            api.get('api/dashboard/reports/products-by-time', { params: params() }),
        )
        report.value = products.data.data
    } catch (err) {
        alert(t('rep.load_failed'))
    } finally {
        loading.value = false
    }
}

function reset() {
    resetFilters()
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

// Max quantity for the inline bar in the product table.
const maxQty = computed(() => Math.max(1, ...((report.value?.products || []).map((p) => p.quantity))))
const hasProducts = computed(() => (report.value?.products || []).length > 0)

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
</script>

<template>
    <div class="space-y-5">
        <div>
            <h1 class="page-title">{{ t('rep.products_title') }}</h1>
            <p class="page-sub">{{ t('rep.products_sub') }}</p>
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
                    <span class="label">{{ t('rep.time_from') }}</span>
                    <input v-model="timeFrom" type="time" class="input" />
                </label>
                <label class="rep-field">
                    <span class="label">{{ t('rep.time_to') }}</span>
                    <input v-model="timeTo" type="time" class="input" />
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
                        <option v-for="ty in AREA_TYPES" :key="ty" :value="ty">{{ t('rep.type_' + ty) }}</option>
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
            <div class="card p-4 space-y-3">
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
                                    <th class="num">#</th>
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
                                <tr v-for="(p, idx) in report.products" :key="p.name">
                                    <td class="num">{{ idx + 1 }}</td>
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
        </template>
    </div>
</template>

<style scoped>
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

@media (max-width: 640px) {
    .rep-perf { grid-template-columns: 1fr; }
}
</style>
