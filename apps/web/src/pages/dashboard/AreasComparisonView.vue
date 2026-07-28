<script setup>
import { ref, computed, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import { alert } from '@xorder/ui/alert.js'
import api from '@xorder/api-client/api.js'
import { withMinDuration } from '../../lib/minLoading.js'
import Skeleton from '@xorder/ui/Skeleton.vue'
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
            <p class="page-sub">{{ t('rep.areas_sub') }}</p>
        </div>

        <!-- Filters -->
        <ReportFilters :ctx="rf" @apply="load" />

        <template v-if="loading">
            <div class="card p-4 space-y-3">
                <Skeleton h="16px" w="30%" />
                <Skeleton v-for="n in 5" :key="'s' + n" h="14px" w="90%" />
            </div>
        </template>

        <template v-else>
            <div class="card p-4 space-y-3">
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
.rep-table-wrap { overflow-x: auto; }
.rep-table { width: 100%; border-collapse: collapse; font-size: 13.5px; }
.rep-table th, .rep-table td { text-align: start; padding: 8px 10px; border-bottom: 1px solid var(--line); white-space: nowrap; }
.rep-table th { color: var(--muted); font-weight: 600; font-size: 12px; }
.rep-table td { color: var(--body); }
.rep-table .num { text-align: end; font-variant-numeric: tabular-nums; }

.rep-rollups { display: grid; grid-template-columns: repeat(auto-fit, minmax(130px, 1fr)); gap: 12px; }
.rep-rollup { border: 1px solid var(--line); border-radius: 12px; padding: 12px 14px; }
.rep-rollup-label { font-size: 12.5px; color: var(--muted); }
.rep-rollup-val { font-size: 24px; font-weight: 800; color: var(--ink); line-height: 1.2; }
.rep-rollup-sub { font-size: 12px; color: var(--muted); }
</style>
