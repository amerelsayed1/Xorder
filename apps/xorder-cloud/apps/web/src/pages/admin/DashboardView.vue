<script setup>
import { ref, computed, onMounted } from 'vue'
import { RouterLink } from 'vue-router'
import { useI18n } from 'vue-i18n'
import api from '@xorder/api-client/api.js'
import { useAuth } from '@xorder/api-client/auth.js'
import { localizedInitial, pickLocalized } from '@xorder/ui/localize.js'
import StatusBadge from '@xorder/ui/StatusBadge.vue'
import Skeleton from '@xorder/ui/Skeleton.vue'
import ErrorState from '@xorder/ui/ErrorState.vue'

const { t, locale } = useI18n()
const auth = useAuth()

const loading = ref(true)
const failed = ref(false)
const total = ref(0)
const byStatus = ref({ ACTIVE: 0, SUSPENDED: 0, ARCHIVED: 0 })
const recent = ref([])
// Platform insights (attention list, subscription pipeline). Only requested for
// roles that may open the Insights page; null when not allowed or when it fails,
// in which case those blocks are simply not rendered.
const insights = ref(null)

async function load() {
    loading.value = true
    failed.value = false
    const insightsReq = auth.can('insights.view')
        ? api.get('api/admin/insights').then((r) => r.data.data).catch(() => null)
        : Promise.resolve(null)
    try {
        // Parallel: one grouped-count query for the totals and the first page of
        // restaurants for the "recent" list.
        const [stats, list] = await Promise.all([
            api.get('api/admin/restaurants/stats'),
            api.get('api/admin/restaurants'),
        ])
        total.value = stats.data.data.total
        byStatus.value = stats.data.data.by_status
        recent.value = list.data.data.slice(0, 6)
        insights.value = await insightsReq
    } catch {
        failed.value = true
    } finally {
        loading.value = false
    }
}
onMounted(load)

const restaurantName = (r) => pickLocalized(r, 'name', locale.value)
const initial = (r) => localizedInitial(r, 'name', locale.value)
const fmtDate = (d) => d ? new Date(d).toLocaleDateString(locale.value, { month: 'short', day: 'numeric' }) : ''

const sum = (obj) => Object.values(obj).reduce((a, b) => a + (b || 0), 0)
const pct = (n, tot) => (tot ? Math.round((n / tot) * 100) : 0)

// Segmented bar + legend rows. Zero-count statuses are dropped so no hairline
// sliver is drawn; colours are theme variables.
function breakdown(defs, counts, tot) {
    const segs = defs
        .filter((d) => (counts[d.key] || 0) > 0)
        .map((d) => ({ key: d.key, label: d.label(), color: d.color, count: counts[d.key], pct: pct(counts[d.key], tot) }))
    return { segs, aria: segs.map((s) => `${s.label} ${s.count}`).join(', ') }
}
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
const rest = computed(() => breakdown(REST_STATUS, byStatus.value, total.value))
const subCounts = computed(() => insights.value?.subscriptions?.by_status || {})
const subsTotal = computed(() => sum(subCounts.value))
const subs = computed(() => breakdown(SUB_STATUS, subCounts.value, subsTotal.value))

const attention = computed(() => {
    const n = insights.value?.needs_attention
    if (!n) return []
    return [
        { key: 'subscriptions_past_end_date', label: t('admin.attn_past_end'), count: n.subscriptions_past_end_date, severity: 'high' },
        { key: 'subscriptions_expiring_in_7_days', label: t('insights.expiring_7'), count: n.subscriptions_expiring_in_7_days, severity: 'high' },
        { key: 'restaurants_without_menu_items', label: t('admin.attn_no_items'), count: n.restaurants_without_menu_items, severity: 'medium' },
        { key: 'restaurants_without_categories', label: t('admin.attn_no_categories'), count: n.restaurants_without_categories, severity: 'medium' },
    ].filter((i) => i.count > 0)
})
const attentionTotal = computed(() => attention.value.reduce((a, i) => a + i.count, 0))

// Subscription badge on the recent list: trials always show the days left, an
// active plan only when it is about to end.
const subBadge = (s) => ({ ACTIVE: 'badge-green', TRIAL: 'badge-amber', EXPIRED: 'badge-red', SUSPENDED: 'badge-gray' }[s] || 'badge-gray')
const daysLeft = (r) => r.subscription_end_date
    ? Math.ceil((new Date(r.subscription_end_date) - new Date()) / 86400000)
    : null
function subLabel(r) {
    const base = t('subscription_status.' + r.subscription_status)
    const d = daysLeft(r)
    if (d === null || d < 0) return base
    if (r.subscription_status === 'TRIAL' || d <= 30) return `${base} · ${t('admin.days_left', { n: d })}`
    return base
}

// Shortcuts, filtered by the same capabilities as the sidebar and the router.
const ACTIONS = [
    { key: 'create', to: { name: 'admin.restaurants.create' }, label: () => t('admin.create_restaurant'), icon: 'pi-plus', cap: 'restaurants.manage' },
    { key: 'licence', to: { name: 'admin.licences.new' }, label: () => t('admin.qa_licence'), icon: 'pi-key', cap: 'licences.manage' },
    { key: 'plans', to: { name: 'admin.plans' }, label: () => t('nav.plans'), icon: 'pi-tags', cap: 'plans.manage' },
    { key: 'leads', to: { name: 'admin.leads' }, label: () => t('nav.leads'), icon: 'pi-inbox', cap: 'leads.manage' },
    { key: 'users', to: { name: 'admin.users' }, label: () => t('nav.users'), icon: 'pi-users', cap: 'platform_users.manage' },
    { key: 'audit', to: { name: 'admin.audit' }, label: () => t('nav.audit'), icon: 'pi-history', cap: 'audit.view' },
]
const actions = computed(() => ACTIONS.filter((a) => auth.can(a.cap)).map((a) => ({ ...a, text: a.label() })))
const canCreate = computed(() => auth.can('restaurants.manage'))
const canInsights = computed(() => auth.can('insights.view'))
</script>

<template>
    <div v-if="loading" class="space-y-6" aria-hidden="true">
        <div class="flex flex-wrap items-start justify-between gap-3">
            <div class="space-y-2"><Skeleton w="176px" h="28px" rounded="8px" /><Skeleton w="260px" h="14px" /></div>
            <Skeleton w="170px" h="44px" rounded="10px" />
        </div>
        <Skeleton w="100%" h="84px" rounded="15px" />
        <div class="grid gap-6 lg:grid-cols-2">
            <Skeleton w="100%" h="330px" rounded="15px" />
            <Skeleton w="100%" h="330px" rounded="15px" />
        </div>
        <div class="grid gap-6 lg:grid-cols-3">
            <Skeleton class="lg:col-span-2" w="100%" h="420px" rounded="15px" />
            <Skeleton w="100%" h="300px" rounded="15px" />
        </div>
    </div>

    <div v-else-if="failed" class="space-y-6">
        <div>
            <h1 class="page-title">{{ t('admin.overview') }}</h1>
            <p class="page-sub" style="color:var(--body)">{{ t('admin.restaurants_subtitle') }}</p>
        </div>
        <ErrorState @retry="load" />
    </div>

    <div v-else class="space-y-6">
        <!-- Header -->
        <div class="flex flex-wrap items-start justify-between gap-3">
            <div>
                <h1 class="page-title">{{ t('admin.overview') }}</h1>
                <p class="page-sub" style="color:var(--body)">{{ t('admin.restaurants_subtitle') }}</p>
            </div>
            <RouterLink v-if="canCreate" :to="{ name: 'admin.restaurants.create' }" class="btn btn-accent cta hdr-cta">
                <i class="pi pi-plus" aria-hidden="true" />{{ t('admin.create_restaurant') }}
            </RouterLink>
        </div>

        <!-- Needs attention: a slim banner; the detail lives in Insights -->
        <template v-if="insights">
            <section v-if="attention.length" class="card attn" aria-labelledby="dash-attn">
                <span class="attn-ico"><i class="pi pi-exclamation-triangle" aria-hidden="true" /></span>
                <div class="attn-text">
                    <h2 id="dash-attn" class="h-card">{{ t('admin.attention_title', { n: attentionTotal }, attentionTotal) }}</h2>
                    <p>{{ t('admin.attention_sub') }}</p>
                </div>
                <ul class="attn-chips">
                    <li v-for="a in attention" :key="a.key" class="chip">
                        <span>{{ a.label }}</span>
                        <span class="chip-count" :class="a.severity === 'high' ? 'chip-high' : 'chip-medium'">{{ a.count }}</span>
                    </li>
                </ul>
                <RouterLink v-if="canInsights" :to="{ name: 'admin.insights' }" class="list-link attn-link">
                    {{ t('admin.open_insights') }}<i class="pi pi-angle-right flip" aria-hidden="true" />
                </RouterLink>
            </section>
            <section v-else class="card allclear" :aria-label="t('insights.needs_attention')">
                <span class="allclear-ico"><i class="pi pi-check" aria-hidden="true" /></span>
                <span>{{ t('insights.all_clear') }}</span>
            </section>
        </template>

        <!-- Pulse: restaurants and subscriptions -->
        <div class="grid gap-6" :class="insights ? 'lg:grid-cols-2' : ''">
            <section class="card p-5 space-y-4" aria-labelledby="dash-rest">
                <div class="flex flex-wrap items-end justify-between gap-x-4 gap-y-2">
                    <div>
                        <h2 id="dash-rest" class="stat-label" style="color:var(--body)">{{ t('admin.total_restaurants') }}</h2>
                        <div class="big-num">{{ total }}</div>
                    </div>
                    <p v-if="insights" class="note">
                        <strong class="tone-green">+{{ insights.restaurants.new_last_30_days }}</strong> {{ t('insights.kpi_new_30_note') }}
                    </p>
                </div>
                <template v-if="total">
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
            </section>

            <section v-if="insights" class="card p-5 space-y-4" aria-labelledby="dash-subs">
                <div class="flex flex-wrap items-end justify-between gap-x-4 gap-y-3">
                    <div>
                        <h2 id="dash-subs" class="stat-label" style="color:var(--body)">{{ t('insights.subscriptions') }}</h2>
                        <div class="big-num">{{ subsTotal }}</div>
                    </div>
                    <div class="flex gap-2">
                        <div class="mini mini-warn">
                            <div class="mini-label">{{ t('insights.expiring_7') }}</div>
                            <div class="mini-num">{{ insights.subscriptions.expiring_in_7_days }}</div>
                        </div>
                        <div class="mini">
                            <div class="mini-label">{{ t('insights.expiring_30') }}</div>
                            <div class="mini-num">{{ insights.subscriptions.expiring_in_30_days }}</div>
                        </div>
                    </div>
                </div>
                <template v-if="subsTotal">
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
                <p v-else class="text-sm py-6 text-center" style="color:var(--body)">{{ t('insights.chart_no_data') }}</p>
            </section>
        </div>

        <!-- Recent restaurants + quick actions -->
        <div class="grid gap-6 lg:grid-cols-3 items-start">
            <section class="lg:col-span-2 card p-5 pb-3 min-w-0">
                <div class="flex items-baseline justify-between gap-3 mb-1.5">
                    <h2 class="h-card">{{ t('admin.recent_restaurants') }}</h2>
                    <RouterLink :to="{ name: 'admin.restaurants' }" class="list-link">{{ t('common.view_all') }}</RouterLink>
                </div>
                <ul v-if="recent.length">
                    <li v-for="r in recent" :key="r.id">
                        <RouterLink :to="{ name: 'admin.restaurants.show', params: { id: r.id } }" class="list-row">
                            <span class="initial">{{ initial(r) }}</span>
                            <span class="min-w-0 flex-1">
                                <span class="row-name block truncate">{{ restaurantName(r) }}</span>
                                <span class="row-meta">
                                    {{ t('admin.item_count', { count: r.menu_items_count ?? 0 }) }}<template v-if="fmtDate(r.created_at)"> · {{ fmtDate(r.created_at) }}</template>
                                </span>
                            </span>
                            <span class="row-badges">
                                <StatusBadge :value="r.status" />
                                <span v-if="r.subscription_status" class="badge" :class="subBadge(r.subscription_status)">{{ subLabel(r) }}</span>
                            </span>
                        </RouterLink>
                    </li>
                </ul>
                <div v-else class="empty">
                    <p>{{ t('admin.no_restaurants') }}</p>
                    <RouterLink v-if="canCreate" :to="{ name: 'admin.restaurants.create' }" class="btn btn-accent btn-sm cta">
                        <i class="pi pi-plus" aria-hidden="true" />{{ t('admin.create_restaurant') }}
                    </RouterLink>
                </div>
            </section>

            <section v-if="actions.length" class="card p-5 pb-3" aria-labelledby="dash-qa">
                <h2 id="dash-qa" class="h-card mb-1.5">{{ t('stats.quick_actions') }}</h2>
                <ul class="qa-list">
                    <li v-for="a in actions" :key="a.key">
                        <RouterLink :to="a.to" class="list-row qa-row">
                            <span class="qa-ico"><i class="pi" :class="a.icon" aria-hidden="true" /></span>
                            <span class="row-name flex-1">{{ a.text }}</span>
                            <i class="pi pi-angle-right flip qa-chev" aria-hidden="true" />
                        </RouterLink>
                    </li>
                </ul>
            </section>
        </div>
    </div>
</template>

<style scoped>
/* Colours come only from the shared theme variables and the PrimeVue primary
   scale; nothing here introduces a new hex value. */
.badge.badge-amber { color: var(--p-primary-800); }
.badge.badge-gray { color: var(--body); }
.tone-green { color: var(--green); }
.flip { display: inline-block; }
[dir=rtl] .flip { transform: scaleX(-1); }

.cta { min-height: 44px; }
@media (max-width: 560px) {
    .hdr-cta { width: 100%; justify-content: center; min-height: 48px; }
}

/* Needs attention */
.attn { display: flex; flex-wrap: wrap; align-items: center; gap: 14px 20px; padding: 16px 20px; }
.attn-ico { width: 40px; height: 40px; border-radius: 11px; flex: none; display: grid; place-items: center;
    background: var(--red-soft); color: var(--red); font-size: 18px; }
.attn-text p { margin: 2px 0 0; font-size: 13.5px; color: var(--body); }
.attn-chips { flex: 1 1 360px; display: flex; flex-wrap: wrap; gap: 8px; list-style: none; margin: 0; padding: 0; }
.chip { display: inline-flex; align-items: center; gap: 8px; min-height: 36px; padding: 0 6px 0 12px;
    border: 1px solid var(--line); border-radius: 999px; font-size: 13.5px; color: var(--body); background: var(--card); }
.chip-count { min-width: 24px; height: 24px; padding: 0 7px; box-sizing: border-box; border-radius: 999px;
    display: inline-grid; place-items: center; font-weight: 700; font-size: 13px; }
.chip-high { background: var(--red-soft); color: var(--red); }
.chip-medium { background: var(--amber-soft); color: var(--p-primary-800); }
.attn-link { display: inline-flex; align-items: center; gap: 6px; min-height: 44px; }
.allclear { display: flex; align-items: center; gap: 12px; padding: 14px 20px; font-size: 15px; color: var(--body); }
.allclear-ico { width: 34px; height: 34px; border-radius: 50%; display: grid; place-items: center;
    background: var(--green-soft); color: var(--green); }
@media (max-width: 640px) {
    .attn-chips { flex-basis: 100%; }
}

/* Pulse cards */
.big-num { font-family: var(--font-display); font-weight: 700; font-size: 40px; line-height: 1.05; color: var(--ink); margin-top: 4px; }
.note { font-size: 14px; color: var(--body); padding-bottom: 6px; margin: 0; }
.seg-bar { display: flex; gap: 3px; height: 14px; }
.seg-bar > span { border-radius: 4px; min-width: 6px; }
.seg-list { list-style: none; margin: 0; padding: 0; }
.seg-list li { display: flex; align-items: center; gap: 10px; padding: 10px 0; border-top: 1px solid var(--line); font-size: 15px; }
.seg-dot { width: 10px; height: 10px; border-radius: 3px; flex: none; }
.seg-pct { width: 44px; text-align: end; font-size: 14px; color: var(--body); }
.mini { background: var(--page); border-radius: 12px; padding: 8px 14px; min-width: 96px; }
.mini-label { font-size: 12.5px; color: var(--body); }
.mini-num { font-family: var(--font-display); font-weight: 700; font-size: 20px; color: var(--ink); }
.mini-warn { background: var(--amber-soft); }
.mini-warn .mini-label, .mini-warn .mini-num { color: var(--p-primary-800); }

/* Lists */
.list-link { font-size: 14px; font-weight: 500; color: var(--p-primary-700); }
.list-link:hover { text-decoration: underline; }
.list-row { display: flex; align-items: center; gap: 14px; padding: 12px 8px; margin-inline: -8px; min-height: 56px;
    border-top: 1px solid var(--line); border-radius: 10px; transition: background .15s; }
.list-row:hover { background: var(--page); }
.list-row:hover .row-name { color: var(--p-primary-700); }
.row-name { font-size: 15px; font-weight: 600; color: var(--ink); }
.row-meta { display: block; font-size: 13px; color: var(--body); margin-top: 2px; }
.row-badges { display: flex; flex-wrap: wrap; justify-content: flex-end; gap: 6px; }
.initial { width: 38px; height: 38px; border-radius: 50%; flex: none; display: grid; place-items: center;
    background: var(--accent-soft); color: var(--p-primary-700); font-weight: 700; font-size: 15px; font-family: var(--font-display); }
.empty { display: flex; flex-direction: column; align-items: center; gap: 12px; padding: 32px 12px; text-align: center; color: var(--body); font-size: 14.5px; }

/* Quick actions */
.qa-list { list-style: none; margin: 0; padding: 0; }
.qa-row { min-height: 52px; padding-block: 9px; }
.qa-ico { width: 34px; height: 34px; border-radius: 10px; flex: none; display: grid; place-items: center;
    background: var(--accent-soft); color: var(--p-primary-700); font-size: 16px; }
.qa-chev { color: var(--body); font-size: 14px; }
@media (max-width: 1023px) {
    /* Phones and tablets: shortcuts become a two-column tile grid. */
    .qa-list { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 12px; padding-bottom: 8px; }
    .qa-row { flex-direction: column; align-items: flex-start; gap: 10px; min-height: 88px; padding: 14px; margin-inline: 0;
        border: 1px solid var(--line); border-radius: 15px; background: var(--card); }
    .qa-chev { display: none; }
}

@media (max-width: 560px) {
    .list-row { flex-wrap: wrap; }
    .row-badges { flex-basis: 100%; justify-content: flex-start; padding-inline-start: 52px; }
    .qa-row.list-row { flex-wrap: nowrap; }
}
</style>
