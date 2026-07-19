<script setup>
import { ref, computed, onMounted } from 'vue'
import { RouterLink } from 'vue-router'
import { useI18n } from 'vue-i18n'
import api from '@xorder/api-client/api.js'

const { t, locale } = useI18n()
const data = ref(null)
const loading = ref(true)

// 14-day engagement chart: bar heights as a % of the busiest day.
const daily = computed(() => data.value?.engagement?.daily || [])
const dailyMax = computed(() => Math.max(1, ...daily.value.flatMap(d => [d.views, d.orders])))
const barHeight = (v) => `${Math.max(v > 0 ? 4 : 2, Math.round((v / dailyMax.value) * 100))}%`
const dayLabel = (iso) => new Date(iso + 'T00:00:00').toLocaleDateString(locale.value, { day: 'numeric' })
const dayTitle = (d) => `${d.date} — ${t('insights.views')}: ${d.views} · ${t('insights.orders')}: ${d.orders}`

onMounted(async () => {
    try {
        const res = await api.get('api/dashboard/insights')
        data.value = res.data.data
    } finally {
        loading.value = false
    }
})

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

        <p v-if="loading" style="color:var(--muted)">{{ t('common.loading') }}</p>

        <template v-else-if="data">
            <!-- Subscription banner -->
            <div v-if="data.subscription.days_remaining !== null && data.subscription.days_remaining <= 14"
                class="card p-4" :style="data.subscription.days_remaining < 0 ? 'border-color:#c0392b' : ''">
                <div class="flex items-center justify-between gap-3">
                    <span class="text-sm">
                        <strong>{{ t('insights.subscription') }}:</strong>
                        <template v-if="data.subscription.days_remaining < 0">{{ t('insights.sub_expired') }}</template>
                        <template v-else>{{ t('insights.sub_days_left', { n: data.subscription.days_remaining }) }}</template>
                    </span>
                    <span class="badge" :class="data.subscription.writable ? 'badge-amber' : 'badge-red'">{{ t('insights.sub.' + data.subscription.status) }}</span>
                </div>
            </div>

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
                <div class="grid grid-cols-2 lg:grid-cols-5 gap-4">
                    <div class="stat">
                        <div class="stat-label">{{ t('stats.views_today') }}</div>
                        <div class="stat-num">{{ data.engagement.views_today }}</div>
                    </div>
                    <div class="stat">
                        <div class="stat-label">{{ t('insights.views_14d') }}</div>
                        <div class="stat-num">{{ data.engagement.views_14d }}</div>
                    </div>
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
                </div>

                <div v-if="daily.length" class="card p-5">
                    <div class="flex items-center justify-between gap-3 flex-wrap mb-4">
                        <h2 class="h-card">{{ t('insights.engagement') }} — {{ t('insights.last_14_days') }}</h2>
                        <div class="flex items-center gap-4 text-xs" style="color:var(--muted)">
                            <span class="flex items-center gap-1.5"><span class="dot-legend" style="background:var(--accent)"></span>{{ t('insights.views') }}</span>
                            <span class="flex items-center gap-1.5"><span class="dot-legend" style="background:var(--green)"></span>{{ t('insights.orders') }}</span>
                        </div>
                    </div>
                    <div class="flex items-end gap-1.5" style="height:140px">
                        <div v-for="d in daily" :key="d.date" class="flex-1 h-full flex items-end justify-center gap-0.5" :title="dayTitle(d)">
                            <div class="eng-bar" style="background:var(--accent)" :style="{ height: barHeight(d.views) }"></div>
                            <div class="eng-bar" style="background:var(--green)" :style="{ height: barHeight(d.orders) }"></div>
                        </div>
                    </div>
                    <div class="flex gap-1.5 mt-1.5">
                        <div v-for="d in daily" :key="d.date" class="flex-1 text-center" style="font-size:10px;color:var(--muted)">{{ dayLabel(d.date) }}</div>
                    </div>
                </div>
            </template>

            <div class="grid gap-6 lg:grid-cols-2">
                <!-- Categories -->
                <div class="card p-5">
                    <h2 class="h-card mb-3">{{ t('insights.largest_categories') }}</h2>
                    <p class="text-sm mb-3" style="color:var(--muted)">
                        {{ t('insights.categories_summary', { active: data.menu.active_categories, total: data.menu.total_categories }) }}
                    </p>
                    <p v-if="!data.category_breakdown.length" style="color:var(--muted)" class="text-sm">{{ t('common.none') }}</p>
                    <ul v-else class="space-y-2">
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
                    <a :href="data.public_url" target="_blank" class="inline-block text-sm underline mt-4" style="color:var(--accent)">
                        ↗ {{ t('restaurant.public_url') }}
                    </a>
                </div>
            </div>
        </template>
    </div>
</template>

<style scoped>
.eng-bar { width: 45%; max-width: 14px; border-radius: 3px 3px 0 0; min-height: 2px; }
.dot-legend { width: 8px; height: 8px; border-radius: 50%; display: inline-block; }
</style>
