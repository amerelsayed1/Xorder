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

// Comparison against the preceding 14 days. Off by default: most visits are a
// glance at "how are we doing today", and a second line on every load makes
// that read slower.
const compare = ref(false)
const previousDaily = computed(() => data.value?.engagement?.previous_daily || [])
const changePct = computed(() => data.value?.engagement?.orders_change_pct ?? null)
const previousTotal = computed(() => data.value?.engagement?.orders_14d_previous ?? 0)

function engagementOptions(c) {
    const categories = daily.value.map(d => dayLabel(d.date))
    const series = [{ name: t('insights.views'), data: daily.value.map(d => d.views) }]
    const palette = [c.accent]
    if (showOrders.value) {
        series.push({ name: t('insights.orders'), data: daily.value.map(d => d.orders) })
        palette.push(c.green)
    }

    // The comparison line is aligned by position, not by date: entry 3 of the
    // previous fortnight sits under entry 3 of this one, which is what makes
    // "same day, two weeks apart" readable on a shared x-axis.
    if (showOrders.value && compare.value && previousDaily.value.length) {
        series.push({
            name: t('insights.orders_previous'),
            data: previousDaily.value.map(d => d.orders),
        })
        palette.push(c.muted || '#9aa0a6')
    }

    const options = lineChart({ colors: c, categories, series, palette, height: 280 })

    // Dashed + thinner, so the past never competes with the present.
    if (series.length === 3) {
        options.stroke = { ...options.stroke, width: [3, 3, 2], dashArray: [0, 0, 6] }
        options.markers = { ...options.markers, size: [4, 4, 0] }
    }

    return options
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

// --- Display-only helpers for the template ---------------------------------
// The API already returns needs_attention (key, count, severity, optional sample);
// this only adds an icon and the screen each issue is fixed on.
const canOrders = computed(() => auth.can('orders.view'))
const canMenu = computed(() => auth.can('menu.view'))
const ATTN_ICON = {
    no_items: 'pi-list', empty_active_categories: 'pi-folder-open', items_missing_image: 'pi-image',
    items_missing_translation: 'pi-globe', items_missing_description: 'pi-align-left', unavailable_items: 'pi-ban',
}
const attention = computed(() => (data.value?.needs_attention || []).map((i) => ({
    ...i,
    icon: ATTN_ICON[i.key] || 'pi-info-circle',
    to: i.key === 'empty_active_categories' ? 'dashboard.categories' : 'dashboard.items',
})))
// Bar width is relative to the largest category.
const categoryMax = computed(() => Math.max(1, ...(data.value?.category_breakdown || []).map((c) => c.menu_items_count || 0)))
</script>

<template>
    <div class="space-y-6">
        <div>
            <h1 class="page-title">{{ t('insights.title') }}</h1>
            <p class="page-sub" style="color:var(--body)">{{ t('insights.dashboard_sub') }}</p>
        </div>

        <!-- Loading skeleton: same blocks as the loaded page -->
        <div v-if="loading" class="space-y-6" aria-busy="true">
            <Skeleton w="100%" h="130px" rounded="15px" />
            <div class="grid grid-cols-2 lg:grid-cols-5 gap-4">
                <Skeleton v-for="n in 5" :key="n" w="100%" h="96px" rounded="15px" />
            </div>
            <div class="grid grid-cols-2 lg:grid-cols-4 gap-4">
                <Skeleton v-for="n in 4" :key="'m' + n" w="100%" h="96px" rounded="15px" />
            </div>
            <Skeleton w="100%" h="340px" rounded="15px" />
            <div class="grid gap-6 lg:grid-cols-2">
                <Skeleton w="100%" h="260px" rounded="15px" />
                <Skeleton w="100%" h="260px" rounded="15px" />
            </div>
        </div>

        <ErrorState v-else-if="error" @retry="load" />

        <template v-else-if="data">
            <!-- Needs attention: first, it is the only block that asks for action -->
            <section class="card p-5 space-y-4" aria-labelledby="ti-attn">
                <div class="flex items-center justify-between gap-3">
                    <h2 id="ti-attn" class="h-card">{{ t('insights.needs_attention') }}</h2>
                    <span v-if="attention.length" class="badge badge-amber">{{ t('insights.to_review', { n: attention.length }) }}</span>
                </div>
                <div v-if="attention.length" class="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
                    <component :is="canMenu ? RouterLink : 'div'" v-for="issue in attention" :key="issue.key"
                        v-bind="canMenu ? { to: { name: issue.to } } : {}" class="attn-tile" :class="{ 'attn-link': canMenu }">
                        <span class="attn-ico" :class="'attn-' + issue.severity"><i class="pi" :class="issue.icon" aria-hidden="true" /></span>
                        <span class="flex-1 min-w-0">
                            <span class="block text-sm" style="color:var(--ink);font-weight:500">{{ t('insights.attn.' + issue.key) }}</span>
                            <span v-if="issue.sample?.length" class="block text-sm truncate" style="color:var(--body)">{{ issue.sample.join(' · ') }}</span>
                        </span>
                        <span class="attn-count">{{ issue.count }}</span>
                    </component>
                </div>
                <p v-else class="flex items-center gap-3 text-sm" style="color:var(--body)">
                    <span class="attn-ico attn-clear"><i class="pi pi-check" aria-hidden="true" /></span>
                    {{ t('insights.menu_healthy') }}
                </p>
            </section>

            <!-- Engagement numbers. New orders lead and becomes a link when
                 something is waiting. -->
            <section v-if="data.engagement" class="grid grid-cols-2 gap-4" :class="showOrders ? 'lg:grid-cols-5' : 'sm:grid-cols-2'" :aria-label="t('insights.engagement')">
                <component :is="canOrders && showOrders ? RouterLink : 'div'" v-if="showOrders"
                    v-bind="canOrders ? { to: { name: 'dashboard.orders' } } : {}"
                    class="stat stat-orders" :class="{ 'stat-hot': data.engagement.orders_new > 0 }">
                    <div class="stat-label"><i class="pi pi-bell me-1.5" aria-hidden="true" />{{ t('stats.new_orders') }}</div>
                    <div class="stat-num">{{ data.engagement.orders_new }}</div>
                    <div v-if="canOrders" class="stat-go">{{ t('dashboard.view_orders') }}<i class="pi pi-arrow-right dir-flip" aria-hidden="true" /></div>
                </component>
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
                        <div class="stat-label">{{ t('insights.orders_14d') }}</div>
                        <div class="stat-num">{{ data.engagement.orders_14d }}</div>
                    </div>
                    <div class="stat">
                        <div class="stat-label">{{ t('insights.orders_total') }}</div>
                        <div class="stat-num">{{ data.engagement.orders_total }}</div>
                    </div>
                </template>
            </section>

            <!-- Menu overview -->
            <section class="grid grid-cols-2 lg:grid-cols-4 gap-4" :aria-label="t('insights.total_items')">
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
            </section>

            <!-- Engagement chart -->
            <section v-if="data.engagement && daily.length" class="card p-5" aria-labelledby="ti-eng">
                <div class="flex items-start justify-between gap-3 mb-2 flex-wrap">
                    <h2 id="ti-eng" class="h-card">{{ t('insights.engagement') }} — {{ t('insights.last_14_days') }}</h2>

                    <label v-if="showOrders" class="compare-toggle">
                        <input v-model="compare" type="checkbox" />
                        <span>{{ t('insights.compare_previous') }}</span>
                    </label>
                </div>

                <!-- The headline the comparison exists to give: up or down,
                     and by how much, against the same length of time. -->
                <p v-if="showOrders && compare" class="text-sm mb-2" style="color:var(--body)">
                    <span v-if="changePct !== null" class="delta" :class="changePct >= 0 ? 'up' : 'down'">
                        {{ changePct >= 0 ? '▲' : '▼' }} {{ Math.abs(changePct) }}%
                    </span>
                    <span v-else class="delta flat">{{ t('insights.no_previous_data') }}</span>
                    {{ t('insights.vs_previous_14', { n: previousTotal }) }}
                </p>

                <ApexChart :build="engagementOptions" :redraw="[daily, showOrders, compare, locale]" />
            </section>

            <!-- Most ordered items -->
            <section v-if="showOrders" class="card p-5" aria-labelledby="ti-top">
                <h2 id="ti-top" class="h-card mb-1">{{ t('insights.top_items') }}</h2>
                <p v-if="!topItems.length" class="text-sm py-4" style="color:var(--body)">{{ t('insights.top_items_none') }}</p>
                <ApexChart v-else :build="topItemsOptions" :redraw="[topItems, locale]" />
            </section>

            <div class="grid gap-6 lg:grid-cols-2">
                <!-- Categories: a ranked list with proportional bars. The share
                     is the count itself, so no colour is needed to tell rows apart. -->
                <section class="card p-5 pb-3" aria-labelledby="ti-cats">
                    <div class="flex items-baseline justify-between gap-3 mb-1">
                        <h2 id="ti-cats" class="h-card">{{ t('insights.largest_categories') }}</h2>
                        <RouterLink v-if="canMenu" :to="{ name: 'dashboard.categories' }" class="list-link">{{ t('nav.categories') }}</RouterLink>
                    </div>
                    <p class="text-sm mb-2" style="color:var(--body)">
                        {{ t('insights.categories_summary', { active: data.menu.active_categories, total: data.menu.total_categories }) }}
                    </p>
                    <p v-if="!data.category_breakdown.length" class="text-sm py-2" style="color:var(--body)">{{ t('common.none') }}</p>
                    <ul v-else>
                        <li v-for="c in data.category_breakdown" :key="c.id" class="cat-row">
                            <span class="flex-1 min-w-0 space-y-1.5">
                                <span class="flex items-center gap-2 min-w-0">
                                    <span class="row-name truncate">{{ c.name }}</span>
                                    <span v-if="!c.is_active" class="badge badge-gray flex-none">{{ t('common.inactive') }}</span>
                                </span>
                                <span class="bar-track"><span class="bar-fill" :style="{ width: Math.round(((c.menu_items_count || 0) / categoryMax) * 100) + '%' }" /></span>
                            </span>
                            <span class="text-sm text-end flex-none" style="color:var(--body)"><strong style="color:var(--ink)">{{ c.menu_items_count }}</strong> {{ t('insights.items_short') }}</span>
                        </li>
                    </ul>
                </section>

                <!-- Pricing -->
                <section class="card p-5 space-y-4" aria-labelledby="ti-price">
                    <h2 id="ti-price" class="h-card">{{ t('insights.pricing') }}</h2>
                    <div class="mini-grid">
                        <div class="mini">
                            <div class="mini-label">{{ t('insights.avg_price') }}</div>
                            <div class="mini-num">{{ money(data.pricing.average_price) }}</div>
                        </div>
                        <div class="mini">
                            <div class="mini-label">{{ t('insights.min_price') }}</div>
                            <div class="mini-num">{{ money(data.pricing.min_price) }}</div>
                        </div>
                        <div class="mini">
                            <div class="mini-label">{{ t('insights.max_price') }}</div>
                            <div class="mini-num">{{ money(data.pricing.max_price) }}</div>
                        </div>
                    </div>
                    <a :href="asPreview(data.public_url)" target="_blank" rel="noopener" class="list-link inline-flex items-center gap-2" style="min-height:44px">
                        <i class="pi pi-external-link" aria-hidden="true" />{{ t('restaurant.public_url') }}
                    </a>
                </section>
            </div>
        </template>
    </div>
</template>

<style scoped>
/* All colours come from the shared theme variables and the PrimeVue primary
   scale; nothing here introduces a new hex value. */
[dir=rtl] .dir-flip { transform: scaleX(-1); }
.stat-label { color: var(--body); }

/* Needs attention */
.attn-tile { display: flex; align-items: center; gap: 12px; padding: 14px 16px; min-height: 64px; border: 1px solid var(--line);
    border-radius: 12px; background: var(--card); transition: border-color .15s, background .15s; }
.attn-link:hover { border-color: var(--accent); background: var(--page); }
.attn-ico { width: 38px; height: 38px; border-radius: 10px; flex: none; display: grid; place-items: center; font-size: 16px; }
.attn-high { background: var(--red-soft); color: var(--red); }
.attn-medium { background: var(--amber-soft); color: var(--p-primary-800); }
.attn-low { background: var(--gray-soft); color: var(--body); }
.attn-clear { border-radius: 50%; background: var(--green-soft); color: var(--green); }
.attn-count { font-family: var(--font-display); font-weight: 700; font-size: 26px; line-height: 1; color: var(--ink); flex: none; }

/* New orders lead tile */
.stat-orders { display: block; }
.stat-hot { background: var(--accent-soft); border-color: var(--accent); }
a.stat-orders:hover { border-color: var(--accent); }
.stat-go { display: inline-flex; align-items: center; gap: 6px; margin-top: 6px; font-size: 14px; font-weight: 600; color: var(--p-primary-700); }

.compare-toggle {
    display: inline-flex; align-items: center; gap: 8px; min-height: 44px;
    font-size: 14px; color: var(--body); cursor: pointer; user-select: none;
}
.compare-toggle input { width: 18px; height: 18px; accent-color: var(--accent); cursor: pointer; }
.delta { font-weight: 700; }
.delta.up { color: var(--green); }
.delta.down { color: var(--red); }
.delta.flat { color: var(--body); font-weight: 600; }

/* Ranked categories */
.cat-row { display: flex; align-items: center; gap: 14px; padding: 11px 8px; margin-inline: -8px; border-radius: 10px;
    border-top: 1px solid var(--line); transition: background .15s; }
.cat-row:first-child { border-top: 0; }
.cat-row:hover { background: var(--page); }
.row-name { font-size: 15px; font-weight: 500; color: var(--ink); }
.bar-track { display: block; height: 6px; border-radius: 3px; background: var(--gray-soft); }
.bar-fill { display: block; height: 6px; border-radius: 3px; background: var(--accent); }

.list-link { font-size: 14px; font-weight: 500; color: var(--p-primary-700); }
.list-link:hover { text-decoration: underline; }

/* Pricing */
.mini-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(110px, 1fr)); gap: 12px; }
.mini { background: var(--page); border-radius: 12px; padding: 12px 14px; min-width: 0; }
.mini-label { font-size: 13.5px; color: var(--body); }
.mini-num { font-family: var(--font-display); font-weight: 700; font-size: 22px; color: var(--ink); margin-top: 2px; font-variant-numeric: tabular-nums; }
</style>
