<script setup>
import { ref, onMounted, computed } from 'vue'
import { RouterLink } from 'vue-router'
import { useI18n } from 'vue-i18n'
import api from '@xorder/api-client/api.js'
import Skeleton from '@xorder/ui/Skeleton.vue'
import ApexChart from '../../components/ApexChart.vue'
import { donutChart } from '../../lib/charts.js'

const { t, locale } = useI18n()
const data = ref(null)
const loading = ref(true)

// Status → localized label + theme color, in display order. Zero-count slices
// are dropped so an empty status never shows as a hairline wedge.
const REST_STATUS = [
    { key: 'ACTIVE', label: () => t('common.active'), color: (c) => c.green },
    { key: 'SUSPENDED', label: () => t('common.suspended'), color: (c) => c.red },
    { key: 'ARCHIVED', label: () => t('common.archived'), color: (c) => c.gray },
]
const SUB_STATUS = [
    { key: 'TRIAL', label: () => t('insights.sub.TRIAL'), color: (c) => c.accent },
    { key: 'ACTIVE', label: () => t('insights.sub.ACTIVE'), color: (c) => c.green },
    { key: 'EXPIRED', label: () => t('insights.sub.EXPIRED'), color: (c) => c.red },
    { key: 'SUSPENDED', label: () => t('insights.sub.SUSPENDED'), color: (c) => c.gray },
]

function statusDonut(defs, counts) {
    const present = defs.filter((d) => (counts[d.key] || 0) > 0)
    return (c) => donutChart({
        colors: c,
        labels: present.map((d) => d.label()),
        series: present.map((d) => counts[d.key] || 0),
        palette: present.map((d) => d.color(c)),
    })
}

const restaurantsByStatus = computed(() => data.value?.restaurants?.by_status || {})
const subsByStatus = computed(() => data.value?.subscriptions?.by_status || {})
const sum = (obj) => Object.values(obj).reduce((a, b) => a + (b || 0), 0)
const restaurantsTotal = computed(() => sum(restaurantsByStatus.value))
const subsTotal = computed(() => sum(subsByStatus.value))

const restaurantsDonut = (c) => statusDonut(REST_STATUS, restaurantsByStatus.value)(c)
const subsDonut = (c) => statusDonut(SUB_STATUS, subsByStatus.value)(c)

onMounted(async () => {
    try {
        const res = await api.get('api/admin/insights')
        data.value = res.data.data
    } finally {
        loading.value = false
    }
})

const attention = computed(() => {
    if (!data.value) return []
    const n = data.value.needs_attention
    return [
        { key: 'subscriptions_past_end_date', count: n.subscriptions_past_end_date, severity: 'high' },
        { key: 'subscriptions_expiring_in_7_days', count: n.subscriptions_expiring_in_7_days, severity: 'high' },
        { key: 'restaurants_without_menu_items', count: n.restaurants_without_menu_items, severity: 'medium' },
        { key: 'restaurants_without_categories', count: n.restaurants_without_categories, severity: 'medium' },
    ].filter((i) => i.count > 0)
})

function fmtDate(iso) {
    if (!iso) return '—'
    return new Date(iso).toLocaleDateString()
}
</script>

<template>
    <div class="space-y-6">
        <div>
            <h1 class="page-title">{{ t('insights.title') }}</h1>
            <p class="page-sub">{{ t('insights.admin_sub') }}</p>
        </div>

        <div v-if="loading" class="space-y-6">
            <div class="grid grid-cols-2 lg:grid-cols-3 gap-4">
                <Skeleton v-for="n in 3" :key="n" w="100%" h="82px" rounded="14px" />
            </div>
            <Skeleton w="100%" h="140px" rounded="14px" />
            <div class="grid gap-6 lg:grid-cols-2">
                <Skeleton w="100%" h="200px" rounded="14px" />
                <Skeleton w="100%" h="200px" rounded="14px" />
            </div>
        </div>

        <template v-else-if="data">
            <!-- Headline counters -->
            <div class="grid grid-cols-2 lg:grid-cols-3 gap-4">
                <div class="stat">
                    <div class="stat-label">{{ t('insights.total_restaurants') }}</div>
                    <div class="stat-num">{{ data.restaurants.total }}</div>
                </div>
                <div class="stat">
                    <div class="stat-label">{{ t('insights.active') }}</div>
                    <div class="stat-num" style="color:var(--green)">{{ data.restaurants.by_status.ACTIVE }}</div>
                </div>
                <div class="stat">
                    <div class="stat-label">{{ t('insights.total_categories') }}</div>
                    <div class="stat-num">{{ data.content.total_categories }}</div>
                </div>
            </div>

            <!-- Status distributions -->
            <div class="grid gap-6 lg:grid-cols-2">
                <div class="card p-5">
                    <h2 class="h-card mb-1">{{ t('insights.restaurants_by_status') }}</h2>
                    <ApexChart v-if="restaurantsTotal" :build="restaurantsDonut" :redraw="[restaurantsByStatus, locale]" />
                    <p v-else class="text-sm py-8 text-center" style="color:var(--muted)">{{ t('insights.chart_no_data') }}</p>
                </div>
                <div class="card p-5">
                    <h2 class="h-card mb-1">{{ t('insights.subs_by_status') }}</h2>
                    <ApexChart v-if="subsTotal" :build="subsDonut" :redraw="[subsByStatus, locale]" />
                    <p v-else class="text-sm py-8 text-center" style="color:var(--muted)">{{ t('insights.chart_no_data') }}</p>
                </div>
            </div>

            <!-- Needs attention -->
            <div class="card p-5">
                <h2 class="h-card mb-3">{{ t('insights.needs_attention') }}</h2>
                <p v-if="!attention.length" style="color:var(--muted)" class="text-sm">{{ t('insights.all_clear') }}</p>
                <ul v-else class="space-y-2">
                    <li v-for="issue in attention" :key="issue.key" class="flex items-center justify-between gap-3">
                        <span class="text-sm">{{ t('insights.attn.' + issue.key) }}</span>
                        <span class="badge" :class="issue.severity === 'high' ? 'badge-red' : 'badge-amber'">{{ issue.count }}</span>
                    </li>
                </ul>
            </div>

            <div class="grid gap-6 lg:grid-cols-2">
                <!-- Subscriptions -->
                <div class="card p-5">
                    <h2 class="h-card mb-3">{{ t('insights.subscriptions') }}</h2>
                    <div class="grid grid-cols-2 gap-3">
                        <div class="stat">
                            <div class="stat-label">{{ t('insights.sub.TRIAL') }}</div>
                            <div class="stat-num">{{ data.subscriptions.by_status.TRIAL }}</div>
                        </div>
                        <div class="stat">
                            <div class="stat-label">{{ t('insights.sub.ACTIVE') }}</div>
                            <div class="stat-num" style="color:var(--green)">{{ data.subscriptions.by_status.ACTIVE }}</div>
                        </div>
                        <div class="stat">
                            <div class="stat-label">{{ t('insights.sub.EXPIRED') }}</div>
                            <div class="stat-num" style="color:#c0392b">{{ data.subscriptions.by_status.EXPIRED }}</div>
                        </div>
                        <div class="stat">
                            <div class="stat-label">{{ t('insights.sub.SUSPENDED') }}</div>
                            <div class="stat-num" style="color:var(--muted)">{{ data.subscriptions.by_status.SUSPENDED }}</div>
                        </div>
                    </div>
                    <div class="mt-4 text-sm space-y-1" style="color:var(--muted)">
                        <div class="flex justify-between"><span>{{ t('insights.expiring_7') }}</span><strong>{{ data.subscriptions.expiring_in_7_days }}</strong></div>
                        <div class="flex justify-between"><span>{{ t('insights.expiring_30') }}</span><strong>{{ data.subscriptions.expiring_in_30_days }}</strong></div>
                    </div>
                </div>

                <!-- Growth + footprint -->
                <div class="card p-5">
                    <h2 class="h-card mb-3">{{ t('insights.growth') }}</h2>
                    <div class="grid grid-cols-2 gap-3">
                        <div class="stat">
                            <div class="stat-label">{{ t('insights.new_7') }}</div>
                            <div class="stat-num">{{ data.restaurants.new_last_7_days }}</div>
                        </div>
                        <div class="stat">
                            <div class="stat-label">{{ t('insights.new_30') }}</div>
                            <div class="stat-num">{{ data.restaurants.new_last_30_days }}</div>
                        </div>
                        <div class="stat">
                            <div class="stat-label">{{ t('insights.suspended') }}</div>
                            <div class="stat-num" style="color:#c0392b">{{ data.restaurants.by_status.SUSPENDED }}</div>
                        </div>
                        <div class="stat">
                            <div class="stat-label">{{ t('insights.admins') }}</div>
                            <div class="stat-num">{{ data.content.restaurant_admins }}</div>
                        </div>
                    </div>
                </div>
            </div>

            <div class="grid gap-6 lg:grid-cols-2">
                <!-- Top restaurants -->
                <div class="card p-5">
                    <h2 class="h-card mb-3">{{ t('insights.top_restaurants') }}</h2>
                    <p v-if="!data.top_restaurants.length" style="color:var(--muted)" class="text-sm">{{ t('common.none') }}</p>
                    <ul v-else class="space-y-2">
                        <li v-for="r in data.top_restaurants" :key="r.id" class="flex items-center justify-between gap-3">
                            <RouterLink :to="{ name: 'admin.restaurants.show', params: { id: r.id } }" class="text-sm underline truncate" style="color:var(--accent)">{{ r.name }}</RouterLink>
                            <span class="text-sm" style="color:var(--muted)">{{ r.menu_items_count }} {{ t('insights.items_short') }}</span>
                        </li>
                    </ul>
                </div>

                <!-- Recent restaurants -->
                <div class="card p-5">
                    <h2 class="h-card mb-3">{{ t('insights.recent_restaurants') }}</h2>
                    <p v-if="!data.recent_restaurants.length" style="color:var(--muted)" class="text-sm">{{ t('common.none') }}</p>
                    <ul v-else class="space-y-2">
                        <li v-for="r in data.recent_restaurants" :key="r.id" class="flex items-center justify-between gap-3">
                            <RouterLink :to="{ name: 'admin.restaurants.show', params: { id: r.id } }" class="text-sm underline truncate" style="color:var(--accent)">{{ r.name }}</RouterLink>
                            <span class="text-sm" style="color:var(--muted)">{{ fmtDate(r.created_at) }}</span>
                        </li>
                    </ul>
                </div>
            </div>
        </template>
    </div>
</template>
