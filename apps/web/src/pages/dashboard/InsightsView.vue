<script setup>
import { ref, onMounted } from 'vue'
import { RouterLink } from 'vue-router'
import { useI18n } from 'vue-i18n'
import api from '@xorder/api-client/api.js'

const { t } = useI18n()
const data = ref(null)
const loading = ref(true)

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

            <!-- Needs attention -->
            <div class="card p-5">
                <h2 class="h-card mb-3">{{ t('insights.needs_attention') }}</h2>
                <p v-if="!data.needs_attention.length" style="color:var(--green)" class="text-sm">{{ t('insights.menu_healthy') }}</p>
                <ul v-else class="space-y-3">
                    <li v-for="issue in data.needs_attention" :key="issue.key" class="flex items-start justify-between gap-3">
                        <div>
                            <div class="text-sm">{{ t('insights.attn.' + issue.key) }}</div>
                            <div v-if="issue.sample && issue.sample.length" class="text-xs mt-1" style="color:var(--muted)">
                                {{ issue.sample.join(' · ') }}
                            </div>
                        </div>
                        <span class="badge"
                            :class="issue.severity === 'high' ? 'badge-red' : issue.severity === 'medium' ? 'badge-amber' : 'badge-gray'">
                            {{ issue.count }}
                        </span>
                    </li>
                </ul>
            </div>

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
