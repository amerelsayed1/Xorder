<script setup>
import { ref, computed, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import { alert } from '@xorder/ui/alert.js'
import api from '@xorder/api-client/api.js'
import { withMinDuration } from '../../lib/minLoading.js'
import Skeleton from '@xorder/ui/Skeleton.vue'
import ErrorState from '@xorder/ui/ErrorState.vue'
import ApexChart from '../../components/ApexChart.vue'
import { barChart } from '../../lib/charts.js'
import { useReportFilters } from '../../composables/useReportFilters.js'
import ReportFilters from '../../components/ReportFilters.vue'

const { t, locale } = useI18n()

const rf = useReportFilters()
const { params, loadFilters, localName, typeLabel, fmtSecs, money } = rf

const areaReport = ref(null)
const loading = ref(true)

async function load() {
    loading.value = true
    try {
        const areasRes = await withMinDuration(
            api.get('api/dashboard/reports/dining-areas', { params: params() }),
        )
        areaReport.value = areasRes.data.data
    } catch (err) {
        alert(t('rep.load_failed'))
    } finally {
        loading.value = false
    }
}

onMounted(() => { loadFilters(); load() })

const hasAreas = computed(() => (areaReport.value?.areas || []).some((a) => a.total_orders > 0 || a.bill_requests > 0))

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
            <h1 class="page-title">{{ t('rep.areas_title') }}</h1>
            <p class="page-sub" style="color:var(--body)">{{ t('rep.areas_sub') }}</p>
        </div>

        <!-- Filters -->
        <ReportFilters :ctx="rf" @apply="load" />

        <!-- Loading skeleton: same blocks as the loaded page -->
        <template v-if="loading">
            <div class="space-y-5" aria-busy="true">
                <div class="grid grid-cols-2 lg:grid-cols-4 gap-4">
                    <Skeleton v-for="n in 2" :key="n" w="100%" h="96px" rounded="15px" />
                </div>
                <Skeleton w="100%" h="300px" rounded="15px" />
                <Skeleton w="100%" h="260px" rounded="15px" />
            </div>
        </template>

        <!-- No report was ever received: the load failed (an alert has also been shown) -->
        <ErrorState v-else-if="!areaReport" @retry="load" />

        <div v-else-if="!hasAreas" class="card px-5 py-12 text-center" style="color:var(--body)">
            <i class="pi pi-map block mb-2" style="font-size:26px" aria-hidden="true"></i>
            {{ t('rep.no_areas') }}
        </div>

        <template v-else>
            <!-- Indoor vs outdoor roll-up -->
            <section v-if="(areaReport.by_type || []).length" class="grid grid-cols-2 lg:grid-cols-4 gap-4">
                <div v-for="ty in areaReport.by_type" :key="'ty' + ty.type" class="stat">
                    <div class="stat-label" style="color:var(--body)">{{ typeLabel(ty.type) }}</div>
                    <div class="stat-num">{{ ty.total_orders }}</div>
                    <div class="text-sm mt-1.5" style="color:var(--body)">{{ t('rep.orders') }} · <strong style="color:var(--ink)">{{ money(ty.total_sales) }}</strong></div>
                </div>
            </section>

            <!-- Orders per area (chart) -->
            <section v-if="chartAreas.length" class="card p-5" aria-labelledby="ac-chart">
                <h2 id="ac-chart" class="h-card mb-2">{{ t('rep.orders') }} · {{ t('rep.area') }}</h2>
                <ApexChart :build="areaOrdersOptions" :redraw="[areaReport, locale]" />
            </section>

            <!-- Detail table: scrolls inside its card, area name stays pinned -->
            <section class="card" aria-labelledby="ac-table">
                <h2 id="ac-table" class="h-card px-5 pt-5 pb-3">{{ t('rep.area') }}</h2>
                <div class="rep-table-wrap">
                    <table class="rep-table">
                        <thead>
                            <tr>
                                <th class="sticky-col">{{ t('rep.area') }}</th>
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
                                <td class="sticky-col name-cell">{{ localName(a, 'name') }}</td>
                                <td>{{ localName(a, 'branch_name') }}</td>
                                <td>{{ typeLabel(a.type) }}</td>
                                <td class="num strong">{{ a.total_orders }}</td>
                                <td class="num strong">{{ money(a.total_sales) }}</td>
                                <td class="num">{{ money(a.avg_order_value) }}</td>
                                <td class="num">{{ a.bill_requests }}</td>
                                <td class="num">{{ fmtSecs(a.avg_response_seconds) }}</td>
                                <td class="num">{{ fmtSecs(a.avg_completion_seconds) }}</td>
                                <td class="num">{{ a.avg_review_rating != null ? a.avg_review_rating + '★' : t('rep.na') }}</td>
                                <td class="num">
                                    <span v-if="a.negative_review_count > 0" class="badge badge-red"><i class="pi pi-exclamation-triangle" style="font-size:11px" aria-hidden="true"></i>{{ a.negative_review_count }}</span>
                                    <template v-else>{{ a.negative_review_count }}</template>
                                </td>
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
</style>
