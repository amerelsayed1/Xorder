<script setup>
import { ref, computed, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import { alert } from '@xorder/ui/alert.js'
import api from '@xorder/api-client/api.js'
import { withMinDuration } from '../../lib/minLoading.js'
import Skeleton from '@xorder/ui/Skeleton.vue'
import ErrorState from '@xorder/ui/ErrorState.vue'
import ApexChart from '../../components/ApexChart.vue'
import { areaChart } from '../../lib/charts.js'
import { useReportFilters } from '../../composables/useReportFilters.js'
import ReportFilters from '../../components/ReportFilters.vue'

const { t, locale } = useI18n()

const rf = useReportFilters()
const { params, loadFilters, periodLabel, money } = rf

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

const hasProducts = computed(() => (report.value?.products || []).length > 0)

// Section heading for the breakdown reflects the grouping the report ran with.
const breakdownTitle = computed(() =>
    report.value?.group === 'day' ? t('rep.by_day_title') : t('rep.by_period_title'),
)

// Sales-by-period — smooth area chart tracing sales across the day's buckets.
function periodSalesOptions(c) {
    const periods = report.value?.periods || []
    return areaChart({
        colors: c,
        categories: periods.map((p) => periodLabel(p.key)),
        series: [{ name: t('rep.sales'), data: periods.map((p) => Number(p.total_sales) || 0) }],
        color: c.accent,
        money: true,
        height: 300,
    })
}

// Display-only: bar widths are relative to the largest quantity in each list.
const topMax = computed(() => Math.max(1, ...(report.value?.top_performers || []).map((p) => p.quantity || 0)))
const lowMax = computed(() => Math.max(1, ...(report.value?.low_performers || []).map((p) => p.quantity || 0)))
</script>

<template>
    <div class="space-y-5">
        <div>
            <h1 class="page-title">{{ t('rep.products_title') }}</h1>
            <p class="page-sub" style="color:var(--body)">{{ t('rep.products_sub') }}</p>
        </div>

        <!-- Filters -->
        <ReportFilters
            :ctx="rf" :show-group="true" :show-export="true" :exporting="exporting"
            @apply="load" @export="doExport"
        />

        <!-- Loading skeleton: same blocks as the loaded page -->
        <template v-if="loading">
            <div class="space-y-5" aria-busy="true">
                <div class="grid gap-5 md:grid-cols-2">
                    <Skeleton w="100%" h="200px" rounded="15px" />
                    <Skeleton w="100%" h="200px" rounded="15px" />
                </div>
                <Skeleton w="100%" h="340px" rounded="15px" />
                <Skeleton w="100%" h="300px" rounded="15px" />
            </div>
        </template>

        <!-- No report was ever received: the load failed (an alert has also been shown) -->
        <ErrorState v-else-if="!report" @retry="load" />

        <div v-else-if="!hasProducts" class="card px-5 py-12 text-center" style="color:var(--body)">
            <i class="pi pi-chart-bar block mb-2" style="font-size:26px" aria-hidden="true"></i>
            {{ t('rep.no_products') }}
        </div>

        <template v-else>
            <!-- Top / low performers: the answer to "what should I push, what should I drop" -->
            <section class="grid gap-5" :class="report.low_performers?.length ? 'md:grid-cols-2' : ''">
                <div class="card p-5" aria-labelledby="pp-top">
                    <h2 id="pp-top" class="h-card mb-2"><i class="pi pi-arrow-up-right me-2 ico-up" aria-hidden="true"></i>{{ t('rep.top_performers') }}</h2>
                    <ol class="perf-list">
                        <li v-for="(p, i) in report.top_performers" :key="'top' + p.name" class="perf-row">
                            <span class="perf-rank">{{ i + 1 }}</span>
                            <span class="flex-1 min-w-0 space-y-1.5">
                                <span class="perf-name block truncate">{{ p.name }}</span>
                                <span class="bar-track"><span class="bar-fill" :style="{ width: Math.round((p.quantity / topMax) * 100) + '%' }" /></span>
                            </span>
                            <span class="badge badge-green">{{ p.quantity }}</span>
                        </li>
                    </ol>
                </div>
                <div v-if="report.low_performers?.length" class="card p-5" aria-labelledby="pp-low">
                    <h2 id="pp-low" class="h-card mb-2"><i class="pi pi-arrow-down-right me-2 ico-down" aria-hidden="true"></i>{{ t('rep.low_performers') }}</h2>
                    <ol class="perf-list">
                        <li v-for="(p, i) in report.low_performers" :key="'low' + p.name" class="perf-row">
                            <span class="perf-rank">{{ i + 1 }}</span>
                            <span class="flex-1 min-w-0 space-y-1.5">
                                <span class="perf-name block truncate">{{ p.name }}</span>
                                <span class="bar-track"><span class="bar-fill bar-fill-low" :style="{ width: Math.round((p.quantity / lowMax) * 100) + '%' }" /></span>
                            </span>
                            <span class="badge badge-gray">{{ p.quantity }}</span>
                        </li>
                    </ol>
                </div>
            </section>

            <!-- Sales by period (chart) -->
            <section v-if="(report.periods || []).length" class="card p-5" aria-labelledby="pp-sales">
                <h2 id="pp-sales" class="h-card mb-2">{{ t('rep.sales') }} · {{ breakdownTitle }}</h2>
                <ApexChart :build="periodSalesOptions" :redraw="[report, locale]" />
            </section>

            <!-- Per-period breakdown -->
            <section class="card p-5" aria-labelledby="pp-periods">
                <h2 id="pp-periods" class="h-card mb-3">{{ breakdownTitle }}</h2>
                <div class="rep-periods">
                    <div v-for="per in report.periods" :key="per.key" class="rep-period">
                        <div class="rep-period-top">
                            <strong>{{ periodLabel(per.key) }}</strong>
                            <span class="rep-period-orders">{{ t('rep.period_orders', { n: per.total_orders }) }}</span>
                        </div>
                        <div class="rep-period-sales">{{ money(per.total_sales) }}</div>
                        <ul class="rep-period-items">
                            <li v-for="pi in per.products.slice(0, 3)" :key="pi.name">
                                <span class="truncate">{{ pi.name }}</span><strong>{{ pi.quantity }}</strong>
                            </li>
                        </ul>
                    </div>
                </div>
            </section>

            <!-- Full product table: the detail, last. Scrolls inside its card and
                 keeps the product name pinned on a narrow screen. -->
            <section class="card" aria-labelledby="pp-table">
                <h2 id="pp-table" class="h-card px-5 pt-5 pb-3">{{ t('rep.product') }}</h2>
                <div class="rep-table-wrap">
                    <table class="rep-table">
                        <thead>
                            <tr>
                                <th class="num">#</th>
                                <th class="sticky-col">{{ t('rep.product') }}</th>
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
                                <td class="sticky-col name-cell">{{ p.name }}</td>
                                <td class="num strong">{{ p.quantity }}</td>
                                <td class="num">{{ p.orders_containing }}</td>
                                <td class="num strong">{{ money(p.total_sales) }}</td>
                                <td class="num">{{ p.avg_qty_per_order }}</td>
                                <td class="num">{{ p.pct_of_orders }}%</td>
                                <td>{{ periodLabel(p.most_active_period) }}</td>
                            </tr>
                        </tbody>
                    </table>
                </div>
            </section>
        </template>
    </div>
</template>

<style scoped>
/* Colours come only from the shared theme variables and the PrimeVue primary
   scale; nothing here introduces a new hex value. */
.ico-up { color: var(--green); }
.ico-down { color: var(--body); }

/* Top / low performers */
.perf-list { list-style: none; margin: 0; padding: 0; }
.perf-row { display: flex; align-items: center; gap: 12px; padding: 10px 0; min-height: 52px; border-top: 1px solid var(--line); }
.perf-row:first-child { border-top: 0; }
.perf-rank { width: 22px; text-align: center; font-size: 14px; font-weight: 600; color: var(--body); flex: none; }
.perf-name { font-size: 15px; font-weight: 500; color: var(--ink); }
.bar-track { display: block; height: 6px; border-radius: 3px; background: var(--gray-soft); }
.bar-fill { display: block; height: 6px; border-radius: 3px; background: var(--accent); }
.bar-fill-low { background: var(--gray); }

/* Product table */
.rep-table-wrap { overflow-x: auto; }
.rep-table { width: 100%; border-collapse: collapse; font-size: 14.5px; }
.rep-table th, .rep-table td { text-align: start; padding: 11px 14px; border-top: 1px solid var(--line); white-space: nowrap; }
.rep-table th { color: var(--body); font-weight: 600; font-size: 13px; background: var(--page); }
.rep-table td { color: var(--body); }
.rep-table tbody tr { transition: background .15s; }
.rep-table tbody tr:hover { background: var(--page); }
.rep-table tbody tr:hover .sticky-col { background: var(--page); }
.rep-table .num { text-align: end; font-variant-numeric: tabular-nums; }
.rep-table .strong, .rep-table .name-cell { color: var(--ink); font-weight: 600; }
.rep-table td:first-child, .rep-table th:first-child { padding-inline-start: 20px; }
.rep-table td:last-child, .rep-table th:last-child { padding-inline-end: 20px; }
.sticky-col { position: sticky; inset-inline-start: 0; background: var(--card); max-width: 220px; overflow: hidden; text-overflow: ellipsis; }
.rep-table th.sticky-col { background: var(--page); }

/* Period cards */
.rep-periods { display: grid; grid-template-columns: repeat(auto-fit, minmax(170px, 1fr)); gap: 12px; }
.rep-period { border: 1px solid var(--line); border-radius: 12px; padding: 14px; min-width: 0; }
.rep-period-top { display: flex; align-items: center; justify-content: space-between; gap: 8px; }
.rep-period-top strong { font-size: 15px; color: var(--ink); }
.rep-period-orders { font-size: 13px; color: var(--body); }
.rep-period-sales { font-size: 20px; font-weight: 700; color: var(--ink); margin: 4px 0 8px; font-variant-numeric: tabular-nums; }
.rep-period-items { list-style: none; margin: 0; padding: 0; font-size: 14px; color: var(--body); }
.rep-period-items li { display: flex; justify-content: space-between; gap: 8px; padding: 3px 0; min-width: 0; }
.rep-period-items strong { color: var(--ink); font-variant-numeric: tabular-nums; }
</style>
