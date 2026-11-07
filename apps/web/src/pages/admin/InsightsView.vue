<script setup>
import { ref, onMounted, computed } from 'vue'
import { RouterLink } from 'vue-router'
import { useI18n } from 'vue-i18n'
import api from '@xorder/api-client/api.js'
import Skeleton from '@xorder/ui/Skeleton.vue'
import ErrorState from '@xorder/ui/ErrorState.vue'

const { t } = useI18n()
const data = ref(null)
const loading = ref(true)
const failed = ref(false)

// Status → localized label + theme color, in display order. Zero-count segments
// are dropped so an empty status never shows as a hairline sliver.
const REST_STATUS = [
    { key: 'ACTIVE', label: () => t('common.active'), color: 'var(--green)' },
    { key: 'SUSPENDED', label: () => t('common.suspended'), color: 'var(--red)' },
    { key: 'ARCHIVED', label: () => t('common.archived'), color: 'var(--gray)' },
]
const SUB_STATUS = [
    { key: 'TRIAL', label: () => t('insights.sub.TRIAL'), color: 'var(--accent)' },
    { key: 'ACTIVE', label: () => t('insights.sub.ACTIVE'), color: 'var(--green)' },
    { key: 'EXPIRED', label: () => t('insights.sub.EXPIRED'), color: 'var(--red)' },
    { key: 'SUSPENDED', label: () => t('insights.sub.SUSPENDED'), color: 'var(--gray)' },
]

const sum = (obj) => Object.values(obj).reduce((a, b) => a + (b || 0), 0)
const pct = (n, total) => (total ? Math.round((n / total) * 100) : 0)

function breakdown(defs, counts) {
    const total = sum(counts)
    const segs = defs
        .filter((d) => (counts[d.key] || 0) > 0)
        .map((d) => ({ key: d.key, label: d.label(), color: d.color, count: counts[d.key], pct: pct(counts[d.key], total) }))
    return { total, segs, aria: segs.map((s) => `${s.label} ${s.count}`).join(', ') }
}

const restaurantsByStatus = computed(() => data.value?.restaurants?.by_status || {})
const subsByStatus = computed(() => data.value?.subscriptions?.by_status || {})
const rest = computed(() => breakdown(REST_STATUS, restaurantsByStatus.value))
const subs = computed(() => breakdown(SUB_STATUS, subsByStatus.value))

async function load() {
    loading.value = true
    failed.value = false
    try {
        const res = await api.get('api/admin/insights')
        data.value = res.data.data
    } catch {
        failed.value = true
    } finally {
        loading.value = false
    }
}
onMounted(load)

// Headline numbers. The percentages are display-only ratios of counts the
// server already returned; nothing here is a money value.
const kpis = computed(() => {
    if (!data.value) return []
    const r = data.value.restaurants
    const s = subsByStatus.value
    const active = r.by_status.ACTIVE || 0
    return [
        { key: 'total', label: t('insights.total_restaurants'), value: r.total, tone: 'ink',
            note: t('insights.kpi_new_30_note'), strong: `+${r.new_last_30_days}`, strongTone: 'green' },
        { key: 'active', label: t('insights.active_restaurants'), value: active, tone: 'green',
            note: t('insights.kpi_of_all'), strong: `${pct(active, r.total)}%`, strongTone: 'ink' },
        { key: 'subs', label: t('insights.active_subs'), value: s.ACTIVE || 0, tone: 'ink',
            note: t('insights.kpi_of_subs', { n: subs.value.total }), strong: `${pct(s.ACTIVE || 0, subs.value.total)}%`, strongTone: 'ink' },
        { key: 'trial', label: t('insights.on_trial'), value: s.TRIAL || 0, tone: 'ink',
            note: t('insights.kpi_of_subs', { n: subs.value.total }), strong: `${pct(s.TRIAL || 0, subs.value.total)}%`, strongTone: 'ink' },
    ]
})

const attention = computed(() => {
    if (!data.value) return []
    const n = data.value.needs_attention
    return [
        { key: 'subscriptions_past_end_date', count: n.subscriptions_past_end_date, severity: 'high', icon: 'pi-exclamation-triangle' },
        { key: 'subscriptions_expiring_in_7_days', count: n.subscriptions_expiring_in_7_days, severity: 'high', icon: 'pi-clock' },
        { key: 'restaurants_without_menu_items', count: n.restaurants_without_menu_items, severity: 'medium', icon: 'pi-list' },
        { key: 'restaurants_without_categories', count: n.restaurants_without_categories, severity: 'medium', icon: 'pi-folder' },
    ].filter((i) => i.count > 0)
})
const attentionTotal = computed(() => attention.value.reduce((a, i) => a + i.count, 0))

// Bar width is relative to the largest menu in the list.
const topRestaurants = computed(() => {
    const list = data.value?.top_restaurants || []
    const max = Math.max(1, ...list.map((r) => r.menu_items_count || 0))
    return list.map((r, i) => ({ ...r, rank: i + 1, bar: Math.round(((r.menu_items_count || 0) / max) * 100) }))
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
            <Skeleton w="100%" h="150px" rounded="15px" />
            <div class="grid grid-cols-2 lg:grid-cols-4 gap-4">
                <Skeleton v-for="n in 4" :key="n" w="100%" h="106px" rounded="15px" />
            </div>
            <div class="grid gap-6 lg:grid-cols-2">
                <Skeleton w="100%" h="300px" rounded="15px" />
                <Skeleton w="100%" h="300px" rounded="15px" />
            </div>
            <div class="grid gap-6 lg:grid-cols-2">
                <Skeleton w="100%" h="260px" rounded="15px" />
                <Skeleton w="100%" h="260px" rounded="15px" />
            </div>
        </div>

        <ErrorState v-else-if="failed" @retry="load" />

        <template v-else-if="data">
            <!-- Needs attention: first, it is the only block that asks for action -->
            <section class="card p-5 space-y-4" aria-labelledby="insights-attn">
                <div class="flex items-center justify-between gap-3">
                    <h2 id="insights-attn" class="h-card">{{ t('insights.needs_attention') }}</h2>
                    <span v-if="attention.length" class="badge badge-red">{{ t('insights.to_review', { n: attentionTotal }) }}</span>
                </div>
                <div v-if="attention.length" class="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
                    <div v-for="issue in attention" :key="issue.key" class="attn-tile">
                        <div class="flex items-center justify-between">
                            <span class="attn-ico" :class="issue.severity === 'high' ? 'attn-high' : 'attn-medium'">
                                <i class="pi" :class="issue.icon" aria-hidden="true" />
                            </span>
                            <span class="attn-count">{{ issue.count }}</span>
                        </div>
                        <p class="text-sm" style="color:var(--body)">{{ t('insights.attn.' + issue.key) }}</p>
                    </div>
                </div>
                <p v-else class="flex items-center gap-3 text-sm" style="color:var(--body)">
                    <span class="attn-ico attn-clear"><i class="pi pi-check" aria-hidden="true" /></span>
                    {{ t('insights.all_clear') }}
                </p>
            </section>

            <!-- Headline numbers -->
            <section class="grid grid-cols-2 lg:grid-cols-4 gap-4" :aria-label="t('insights.title')">
                <div v-for="k in kpis" :key="k.key" class="stat">
                    <div class="stat-label" style="color:var(--body)">{{ k.label }}</div>
                    <div class="stat-num" :class="k.tone === 'green' ? 'tone-green' : ''">{{ k.value }}</div>
                    <div class="text-sm mt-1.5" style="color:var(--body)">
                        <strong :class="k.strongTone === 'green' ? 'tone-green' : ''" style="font-weight:700">{{ k.strong }}</strong>
                        {{ k.note }}
                    </div>
                </div>
            </section>

            <!-- Status breakdowns -->
            <div class="grid gap-6 lg:grid-cols-2">
                <section class="card p-5 space-y-4">
                    <div class="flex items-baseline justify-between gap-3">
                        <h2 class="h-card">{{ t('insights.restaurants_by_status') }}</h2>
                        <span class="text-sm" style="color:var(--body)">{{ t('insights.total_n', { n: rest.total }) }}</span>
                    </div>
                    <template v-if="rest.total">
                        <div class="seg-bar" role="img" :aria-label="rest.aria">
                            <span v-for="s in rest.segs" :key="s.key" :style="{ flex: `${s.count} 1 0`, background: s.color }" />
                        </div>
                        <ul class="seg-list">
                            <li v-for="s in rest.segs" :key="s.key">
                                <span class="seg-dot" :style="{ background: s.color }" />
                                <span class="flex-1" style="color:var(--ink)">{{ s.label }}</span>
                                <strong style="color:var(--ink)">{{ s.count }}</strong>
                                <span class="seg-pct">{{ s.pct }}%</span>
                            </li>
                        </ul>
                    </template>
                    <p v-else class="text-sm py-8 text-center" style="color:var(--body)">{{ t('insights.chart_no_data') }}</p>
                    <div class="grid grid-cols-2 gap-3">
                        <div class="mini">
                            <div class="mini-label">{{ t('insights.new_7') }}</div>
                            <div class="mini-num">{{ data.restaurants.new_last_7_days }}</div>
                        </div>
                        <div class="mini">
                            <div class="mini-label">{{ t('insights.new_30') }}</div>
                            <div class="mini-num">{{ data.restaurants.new_last_30_days }}</div>
                        </div>
                    </div>
                </section>

                <section class="card p-5 space-y-4">
                    <div class="flex items-baseline justify-between gap-3">
                        <h2 class="h-card">{{ t('insights.subs_by_status') }}</h2>
                        <span class="text-sm" style="color:var(--body)">{{ t('insights.total_n', { n: subs.total }) }}</span>
                    </div>
                    <template v-if="subs.total">
                        <div class="seg-bar" role="img" :aria-label="subs.aria">
                            <span v-for="s in subs.segs" :key="s.key" :style="{ flex: `${s.count} 1 0`, background: s.color }" />
                        </div>
                        <ul class="seg-list">
                            <li v-for="s in subs.segs" :key="s.key">
                                <span class="seg-dot" :style="{ background: s.color }" />
                                <span class="flex-1" style="color:var(--ink)">{{ s.label }}</span>
                                <strong style="color:var(--ink)">{{ s.count }}</strong>
                                <span class="seg-pct">{{ s.pct }}%</span>
                            </li>
                        </ul>
                    </template>
                    <p v-else class="text-sm py-8 text-center" style="color:var(--body)">{{ t('insights.chart_no_data') }}</p>
                    <div class="grid grid-cols-2 gap-3">
                        <div class="mini mini-warn">
                            <div class="mini-label">{{ t('insights.expiring_7') }}</div>
                            <div class="mini-num">{{ data.subscriptions.expiring_in_7_days }}</div>
                        </div>
                        <div class="mini">
                            <div class="mini-label">{{ t('insights.expiring_30') }}</div>
                            <div class="mini-num">{{ data.subscriptions.expiring_in_30_days }}</div>
                        </div>
                    </div>
                </section>
            </div>

            <!-- Lists -->
            <div class="grid gap-6 lg:grid-cols-2">
                <section class="card p-5 pb-3">
                    <div class="flex items-baseline justify-between gap-3 mb-1.5">
                        <h2 class="h-card">{{ t('insights.top_restaurants') }}</h2>
                        <RouterLink :to="{ name: 'admin.restaurants' }" class="list-link">{{ t('insights.all_restaurants') }}</RouterLink>
                    </div>
                    <p v-if="!topRestaurants.length" class="text-sm py-2" style="color:var(--body)">{{ t('common.none') }}</p>
                    <ul v-else>
                        <li v-for="r in topRestaurants" :key="r.id">
                            <RouterLink :to="{ name: 'admin.restaurants.show', params: { id: r.id } }" class="list-row">
                                <span class="rank">{{ r.rank }}</span>
                                <span class="flex-1 min-w-0 space-y-1.5">
                                    <span class="row-name block truncate">{{ r.name }}</span>
                                    <span class="bar-track"><span class="bar-fill" :style="{ width: r.bar + '%' }" /></span>
                                </span>
                                <span class="text-sm text-end" style="color:var(--body)"><strong style="color:var(--ink)">{{ r.menu_items_count }}</strong> {{ t('insights.items_short') }}</span>
                            </RouterLink>
                        </li>
                    </ul>
                </section>

                <section class="card p-5 pb-3">
                    <div class="flex items-baseline justify-between gap-3 mb-1.5">
                        <h2 class="h-card">{{ t('insights.recent_restaurants') }}</h2>
                        <RouterLink :to="{ name: 'admin.restaurants' }" class="list-link">{{ t('insights.all_restaurants') }}</RouterLink>
                    </div>
                    <p v-if="!data.recent_restaurants.length" class="text-sm py-2" style="color:var(--body)">{{ t('common.none') }}</p>
                    <ul v-else>
                        <li v-for="r in data.recent_restaurants" :key="r.id">
                            <RouterLink :to="{ name: 'admin.restaurants.show', params: { id: r.id } }" class="list-row">
                                <span class="initial">{{ (r.name || '?').trim().charAt(0).toUpperCase() }}</span>
                                <span class="row-name flex-1 min-w-0 truncate">{{ r.name }}</span>
                                <span class="text-sm" style="color:var(--body)">{{ fmtDate(r.created_at) }}</span>
                            </RouterLink>
                        </li>
                    </ul>
                </section>
            </div>

            <!-- Footprint -->
            <section class="card px-5 py-4 flex flex-wrap items-center gap-x-10 gap-y-3" :aria-label="t('insights.platform_content')">
                <span class="font-bold" style="color:var(--ink)">{{ t('insights.platform_content') }}</span>
                <span class="text-sm" style="color:var(--body)"><strong class="text-lg" style="color:var(--ink)">{{ data.content.total_categories }}</strong> {{ t('insights.total_categories') }}</span>
                <span class="text-sm" style="color:var(--body)"><strong class="text-lg" style="color:var(--ink)">{{ data.content.restaurant_admins }}</strong> {{ t('insights.admins') }}</span>
            </section>
        </template>
    </div>
</template>

<style scoped>
/* All colours come from the shared theme variables (packages/ui/src/theme.css)
   and the PrimeVue primary scale; nothing here introduces a new hex value. */
.tone-green { color: var(--green); }

.attn-tile { display: flex; flex-direction: column; gap: 10px; padding: 16px; border: 1px solid var(--line);
    border-radius: 12px; background: var(--card); }
.attn-ico { width: 36px; height: 36px; border-radius: 10px; display: grid; place-items: center; font-size: 16px; }
.attn-high { background: var(--red-soft); color: var(--red); }
.attn-medium { background: var(--amber-soft); color: var(--p-primary-800); }
.attn-clear { border-radius: 50%; background: var(--green-soft); color: var(--green); flex: none; }
.attn-count { font-family: var(--font-display); font-weight: 700; font-size: 30px; line-height: 1; color: var(--ink); }

.seg-bar { display: flex; gap: 3px; height: 14px; }
.seg-bar > span { border-radius: 4px; min-width: 6px; }
.seg-list { list-style: none; margin: 0; padding: 0; }
.seg-list li { display: flex; align-items: center; gap: 10px; padding: 10px 0; border-top: 1px solid var(--line); font-size: 15px; }
.seg-dot { width: 10px; height: 10px; border-radius: 3px; flex: none; }
.seg-pct { width: 44px; text-align: end; font-size: 14px; color: var(--body); }

.mini { background: var(--page); border-radius: 12px; padding: 12px 14px; }
.mini-label { font-size: 13.5px; color: var(--body); }
.mini-num { font-family: var(--font-display); font-weight: 700; font-size: 22px; color: var(--ink); margin-top: 2px; }
.mini-warn { background: var(--amber-soft); }
.mini-warn .mini-label, .mini-warn .mini-num { color: var(--p-primary-800); }

.list-link { font-size: 14px; font-weight: 500; color: var(--p-primary-700); }
.list-link:hover { text-decoration: underline; }
.list-row { display: flex; align-items: center; gap: 14px; padding: 11px 8px; margin-inline: -8px; border-radius: 10px;
    transition: background .15s; }
.list-row:hover { background: var(--page); }
.list-row:hover .row-name { color: var(--p-primary-700); }
.row-name { font-size: 15px; font-weight: 500; color: var(--ink); }
.rank { width: 22px; text-align: center; font-size: 14px; font-weight: 500; color: var(--body); }
.bar-track { display: block; height: 6px; border-radius: 3px; background: var(--gray-soft); }
.bar-fill { display: block; height: 6px; border-radius: 3px; background: var(--accent); }
.initial { width: 34px; height: 34px; border-radius: 50%; flex: none; display: grid; place-items: center;
    background: var(--accent-soft); color: var(--p-primary-700); font-weight: 700; font-size: 14px; }
</style>
