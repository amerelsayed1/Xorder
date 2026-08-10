<script setup>
import { ref, computed, onMounted } from 'vue'
import { RouterLink } from 'vue-router'
import { useI18n } from 'vue-i18n'
import api from '@xorder/api-client/api.js'
import { useAuth } from '@xorder/api-client/auth.js'
import Skeleton from '@xorder/ui/Skeleton.vue'
import ErrorState from '@xorder/ui/ErrorState.vue'
import ApexChart from '../../components/ApexChart.vue'
import { lineChart, columnChart, donutChart } from '../../lib/charts.js'
import { asPreview } from '../../lib/host.js'

const { t, locale } = useI18n()
const auth = useAuth()
const data = ref(null)
const loading = ref(true)
const error = ref(false)

// Order analytics (totals, "most ordered", the orders series) only mean
// anything when the restaurant takes system orders — WhatsApp orders aren't
// recorded and QR-only plans have no Order rows at all. Menu views stay shown.
const showOrders = computed(() => auth.hasFeature('system_ordering'))

// 14-day engagement — line chart (views, plus orders when tracked).
const daily = computed(() => data.value?.engagement?.daily || [])
const dayLabel = (iso) => new Date(iso + 'T00:00:00').toLocaleDateString(locale.value, { day: 'numeric' })

function engagementOptions(c) {
    const categories = daily.value.map(d => dayLabel(d.date))
    const series = [{ name: t('insights.views'), data: daily.value.map(d => d.views) }]
    const palette = [c.accent]
    if (showOrders.value) {
        series.push({ name: t('insights.orders'), data: daily.value.map(d => d.orders) })
        palette.push(c.green)
    }
    return lineChart({ colors: c, categories, series, palette, height: 280 })
}

// Most-ordered items — vertical column chart (a ranking, one column per item).
const topItems = computed(() => data.value?.top_items || [])

function topItemsOptions(c) {
    return columnChart({
        colors: c,
        categories: topItems.value.map(i => i.name),
        series: [{ name: t('insights.orders'), data: topItems.value.map(i => i.qty) }],
        height: 280,
    })
}

// Items-per-category distribution — donut. Only categories that actually hold
// items are charted; the total gates the chart vs. an empty-state message.
const categoryBreakdown = computed(() => (data.value?.category_breakdown || []).filter(c => c.menu_items_count > 0))
const categoryItemsTotal = computed(() => categoryBreakdown.value.reduce((sum, c) => sum + c.menu_items_count, 0))

function categoryDonutOptions(c) {
    const pool = [c.accent, c.green, c.amber, c.red, c.gray, c.accentDark, c.ink]
    return donutChart({
        colors: c,
        labels: categoryBreakdown.value.map(x => x.name),
        series: categoryBreakdown.value.map(x => x.menu_items_count),
        palette: categoryBreakdown.value.map((_, i) => pool[i % pool.length]),
    })
}

async function load() {
    loading.value = true
    error.value = false
    try {
        const res = await api.get('api/dashboard/insights')
        data.value = res.data.data
    } catch (err) {
        error.value = true
    } finally {
        loading.value = false
    }
}
onMounted(load)

function money(v) {
    if (v === null || v === undefined) return '—'
    return Number(v).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })
}
</script>

<template>
    <div class="space-y-6">
        <div>
            <h1 class="page-title">{{ t('insights.title') }}</h1>
            <p class="page-sub">{{ t('insights.dashboard_sub') }}</p>
        </div>

        <div v-if="loading" class="space-y-6">
            <div class="grid grid-cols-2 lg:grid-cols-4 gap-4">
                <Skeleton v-for="n in 4" :key="n" w="100%" h="82px" rounded="14px" />
            </div>
            <Skeleton w="100%" h="220px" rounded="14px" />
            <div class="grid gap-6 lg:grid-cols-2">
                <Skeleton w="100%" h="200px" rounded="14px" />
                <Skeleton w="100%" h="200px" rounded="14px" />
            </div>
        </div>

        <ErrorState v-else-if="error" @retry="load" />

        <template v-else-if="data">
            <!-- Menu overview -->
            <div class="grid grid-cols-2 lg:grid-cols-4 gap-4">
                <div class="stat">
                    <div class="stat-label">{{ t('insights.total_items') }}</div>
                    <div class="stat-num">{{ data.menu.total_items }}</div>
                </div>
                <div class="stat">
                    <div class="stat-label">{{ t('common.available') }}</div>
                    <div class="stat-num" style="color:var(--green)">{{ data.menu.available_items }}</div>
                </div>
                <div class="stat">
                    <div class="stat-label">{{ t('common.featured') }}</div>
                    <div class="stat-num">{{ data.menu.featured_items }}</div>
                </div>
                <div class="stat">
                    <div class="stat-label">{{ t('insights.discounted') }}</div>
                    <div class="stat-num" style="color:var(--accent)">{{ data.menu.discounted_items }}</div>
                </div>
            </div>

            <!-- Engagement -->
            <template v-if="data.engagement">
                <div class="grid grid-cols-2 gap-4" :class="showOrders ? 'lg:grid-cols-5' : 'sm:grid-cols-2'">
                    <div class="stat">
                        <div class="stat-label">{{ t('stats.views_today') }}</div>
                        <div class="stat-num">{{ data.engagement.views_today }}</div>
                    </div>
                    <div class="stat">
                        <div class="stat-label">{{ t('insights.views_14d') }}</div>
                        <div class="stat-num">{{ data.engagement.views_14d }}</div>
                    </div>
                    <template v-if="showOrders">
                        <div class="stat">
                            <div class="stat-label">{{ t('insights.orders_total') }}</div>
                            <div class="stat-num">{{ data.engagement.orders_total }}</div>
                        </div>
                        <div class="stat">
                            <div class="stat-label">{{ t('stats.new_orders') }}</div>
                            <div class="stat-num" style="color:var(--accent)">{{ data.engagement.orders_new }}</div>
                        </div>
                        <div class="stat">
                            <div class="stat-label">{{ t('insights.orders_14d') }}</div>
                            <div class="stat-num">{{ data.engagement.orders_14d }}</div>
                        </div>
                    </template>
                </div>

                <div v-if="daily.length" class="card p-5">
                    <h2 class="h-card mb-1">{{ t('insights.engagement') }} — {{ t('insights.last_14_days') }}</h2>
                    <ApexChart :build="engagementOptions" :redraw="[daily, showOrders, locale]" />
                </div>
            </template>

            <!-- Most ordered items -->
            <div v-if="showOrders" class="card p-5">
                <h2 class="h-card mb-1">{{ t('insights.top_items') }}</h2>
                <p v-if="!topItems.length" class="text-sm" style="color:var(--muted)">{{ t('insights.top_items_none') }}</p>
                <ApexChart v-else :build="topItemsOptions" :redraw="[topItems, locale]" />
            </div>

            <div class="grid gap-6 lg:grid-cols-2">
                <!-- Categories -->
                <div class="card p-5">
                    <h2 class="h-card mb-3">{{ t('insights.largest_categories') }}</h2>
                    <p class="text-sm mb-3" style="color:var(--muted)">
                        {{ t('insights.categories_summary', { active: data.menu.active_categories, total: data.menu.total_categories }) }}
                    </p>
                    <p v-if="!data.category_breakdown.length" style="color:var(--muted)" class="text-sm">{{ t('common.none') }}</p>
                    <ApexChart v-if="categoryItemsTotal" :build="categoryDonutOptions" :redraw="[categoryBreakdown, locale]" class="mb-2" />
                    <ul v-if="data.category_breakdown.length" class="space-y-2">
                        <li v-for="c in data.category_breakdown" :key="c.id" class="flex items-center justify-between gap-3">
                            <span class="text-sm truncate">
                                {{ c.name }}
                                <span v-if="!c.is_active" class="badge badge-gray ms-1">{{ t('common.inactive') }}</span>
                            </span>
                            <span class="text-sm" style="color:var(--muted)">{{ c.menu_items_count }} {{ t('insights.items_short') }}</span>
                        </li>
                    </ul>
                    <RouterLink :to="{ name: 'dashboard.categories' }" class="inline-block text-sm underline mt-3" style="color:var(--accent)">
                        {{ t('nav.categories') }} →
                    </RouterLink>
                </div>

                <!-- Pricing -->
                <div class="card p-5">
                    <h2 class="h-card mb-3">{{ t('insights.pricing') }}</h2>
                    <div class="grid grid-cols-3 gap-3">
                        <div class="stat">
                            <div class="stat-label">{{ t('insights.avg_price') }}</div>
                            <div class="stat-num">{{ money(data.pricing.average_price) }}</div>
                        </div>
                        <div class="stat">
                            <div class="stat-label">{{ t('insights.min_price') }}</div>
                            <div class="stat-num">{{ money(data.pricing.min_price) }}</div>
                        </div>
                        <div class="stat">
                            <div class="stat-label">{{ t('insights.max_price') }}</div>
                            <div class="stat-num">{{ money(data.pricing.max_price) }}</div>
                        </div>
                    </div>
                    <a :href="asPreview(data.public_url)" target="_blank" class="inline-block text-sm underline mt-4" style="color:var(--accent)">
                        ↗ {{ t('restaurant.public_url') }}
                    </a>
                </div>
            </div>
        </template>
    </div>
</template>

