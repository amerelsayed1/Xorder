<script setup>
import { ref, computed, onMounted } from 'vue'
import { RouterLink } from 'vue-router'
import { useI18n } from 'vue-i18n'
import api from '@xorder/api-client/api.js'
import { useAuth } from '@xorder/api-client/auth.js'
import { currencyLabel } from '../../lib/currency.js'
import { currencyExponent, minorToAmount } from '../../lib/money.js'
import { pickLocalized } from '@xorder/ui/localize.js'
import Icon from '@xorder/ui/Icon.vue'
import ErrorState from '@xorder/ui/ErrorState.vue'
import Skeleton from '@xorder/ui/Skeleton.vue'
import { asPreview } from '../../lib/host.js'
import { buildDashboardNav } from './nav.config.js'

const { t, locale } = useI18n()
const auth = useAuth()
// Greet the owner by their restaurant (client) name; fall back to the generic
// "Dashboard" label until the restaurant context is loaded.
const clientName = computed(() => pickLocalized(auth.restaurant, 'name', locale.value) || t('nav.dashboard'))
const cur = computed(() => currencyLabel(auth.restaurant?.currency, locale.value, auth.restaurant?.currency_symbol))
const exponent = computed(() => currencyExponent(auth.restaurant?.currency))
const stats = ref(null)
const items = ref([])
const engagement = ref(null)
// Without this, a failed core fetch left `stats` null forever and the page
// showed a permanent loading skeleton — a blank first screen after login.
const error = ref(false)

// This page is where every tenant account lands, owners and staff alike, so it
// must not assume the full owner capability set. Each panel is fetched only if
// the signed-in user may read it; a role without analytics.view gets the plain
// shortcut landing below instead of a wall of stats it cannot see.
const canAnalytics = computed(() => auth.can('analytics.view'))
const canMenu = computed(() => auth.can('menu.view'))
const canOrders = computed(() => auth.can('orders.view'))
// Payments and shifts only exist where a till does. Showing a cashier panel to
// a QR-menu-only tenant would be describing hardware they do not have.
const hasPos = computed(() => (auth.restaurant?.features || []).includes('pos'))

// The same nav schema the sidebar is built from, flattened to leaf links — so a
// staff member's shortcuts can never drift from what they may actually open.
const staffShortcuts = computed(() => buildDashboardNav({
    features: auth.restaurant?.features || [],
    can: auth.can,
}).flatMap((n) => (n.children ? n.children : [n])).filter((n) => n.to && n.key !== 'home'))

async function load() {
    error.value = false

    if (!canAnalytics.value) return

    try {
        const [s, it, cats] = await Promise.all([
            api.get('api/dashboard/stats'),
            canMenu.value ? api.get('api/dashboard/items') : Promise.resolve(null),
            canMenu.value ? api.get('api/dashboard/categories') : Promise.resolve(null),
        ])
        stats.value = s.data.data
        items.value = it.data?.data ?? []
        categories.value = cats.data?.data ?? []
    } catch (err) {
        error.value = true
        return
    }
    // The views series is a nicety — never let it block or break the home page.
    try {
        const ins = await api.get('api/dashboard/insights')
        engagement.value = ins.data.data?.engagement || null
    } catch (err) { /* insights optional */ }
}

onMounted(load)

// --- Formatting ------------------------------------------------------------

// Grouped Western digits, matching the tabular figures the rest of the money
// surfaces use. Minor units go through minorToAmount rather than a bare /100,
// because a Kuwaiti tenant's minor unit is a thousandth.
const group = (n) => Number(n || 0).toLocaleString('en-US', { maximumFractionDigits: exponent.value })
const fmtMinor = (minor) => group(minorToAmount(minor || 0, exponent.value))

// "+18%" / "-4%". Null change means there was no baseline to measure against,
// and the caller renders nothing rather than a misleading zero.
const signed = (n, suffix = '') => (n > 0 ? '+' : '') + n + suffix

const salesChange = computed(() => {
    const pct = stats.value?.sales_change_pct
    return pct === null || pct === undefined ? null : t('dashboard.vs_yesterday', { v: signed(pct, '%') })
})
const salesUp = computed(() => (stats.value?.sales_change_pct ?? 0) >= 0)

const viewsDelta = computed(() => (stats.value?.views_today ?? 0) - (stats.value?.views_yesterday ?? 0))
const viewsChange = computed(() => (stats.value?.views_yesterday ?? 0) === 0 && viewsDelta.value === 0
    ? null
    : t('dashboard.vs_yesterday', { v: signed(viewsDelta.value) }))

const availablePct = computed(() => {
    const total = stats.value?.total_items || 0
    return total > 0 ? Math.round((stats.value.available_items / total) * 100) : 0
})

// --- Menu views ------------------------------------------------------------

const range = ref(14)
// The series arrives oldest-first and always 14 days long, so the shorter
// range is its tail rather than a second request.
const viewDays = computed(() => (engagement.value?.daily || []).slice(-range.value))
const viewsTotal = computed(() => viewDays.value.reduce((a, d) => a + d.views, 0))
const hasViews = computed(() => viewsTotal.value > 0)

// The busiest day sets the scale, so a quiet fortnight still reads as a shape
// rather than a flat line.
const viewsMax = computed(() => Math.max(0, ...viewDays.value.map((d) => d.views)))
// Which visible bar is the peak — flagged so the chart highlights it in accent
// while the rest of the fortnight sits in cream. A tie takes the first day; if
// every day was zero, nothing is highlighted.
const peakIdx = computed(() => {
    if (!viewDays.value.length) return -1
    let best = 0
    for (let i = 1; i < viewDays.value.length; i++) {
        if (viewDays.value[i].views > viewDays.value[best].views) best = i
    }
    return viewDays.value[best].views > 0 ? best : -1
})
const bars = computed(() => viewDays.value.map((d, i, all) => ({
    date: d.date,
    day: new Date(d.date + 'T00:00:00').getDate(),
    last: i === all.length - 1,
    peak: i === peakIdx.value,
    h: viewsMax.value > 0 ? (d.views / viewsMax.value) * 100 + '%' : '0%',
    tip: `${d.date} — ${t('dashboard.views_total', { n: d.views })}`,
})))
const rangeLabel = computed(() => t(range.value === 7 ? 'dashboard.last_7' : 'dashboard.last_14'))

// Mini-stats above the chart: comparison to the previous window, daily
// average, and the peak day. The prior-period delta needs a window of equal
// length before the visible one — with a 14-day API series that only exists
// when the user is looking at the 7-day view; otherwise we omit the pill
// rather than pretending 0 was the baseline.
const viewsPrevTotal = computed(() => {
    const all = engagement.value?.daily || []
    const start = all.length - range.value * 2
    if (start < 0) return null
    return all.slice(start, all.length - range.value).reduce((a, d) => a + d.views, 0)
})
const viewsDeltaPct = computed(() => {
    const prev = viewsPrevTotal.value
    if (prev === null || prev <= 0) return null
    return Math.round(((viewsTotal.value - prev) / prev) * 100)
})
const viewsPeak = computed(() => {
    if (peakIdx.value < 0) return null
    const d = viewDays.value[peakIdx.value]
    return { value: d.views, day: new Date(d.date + 'T00:00:00').getDate() }
})
const viewStats = computed(() => {
    const list = []
    if (viewsDeltaPct.value !== null) {
        list.push({ label: t('dashboard.vs_previous'), value: signed(viewsDeltaPct.value, '%') })
    }
    if (viewDays.value.length > 0) {
        list.push({
            label: t('dashboard.daily_avg'),
            value: group(Math.round(viewsTotal.value / viewDays.value.length)),
            note: t('dashboard.views_word'),
        })
    }
    if (viewsPeak.value) {
        list.push({
            label: t('dashboard.peak_day'),
            value: group(viewsPeak.value.value),
            note: t('dashboard.day_n', { n: viewsPeak.value.day }),
            highlight: true,
        })
    }
    return list
})

// --- Current shift ---------------------------------------------------------

const shift = computed(() => stats.value?.current_shift || null)
const shiftStats = computed(() => shift.value ? [
    { label: t('dashboard.shift_sales'), value: fmtMinor(shift.value.sales_minor), unit: cur.value },
    { label: t('dashboard.shift_orders'), value: group(shift.value.orders_count), unit: t('dashboard.shift_orders') },
    { label: t('dashboard.shift_cash'), value: fmtMinor(shift.value.expected_cash_minor), unit: cur.value },
    { label: t('dashboard.shift_avg'), value: fmtMinor(shift.value.average_order_minor), unit: cur.value },
] : [])
const shiftMeta = computed(() => {
    if (!shift.value) return ''
    // A shift opened on an earlier day says which day: "10:55" alone reads as
    // this morning even when the shift has been open for weeks.
    const opened = shift.value.opened_at ? new Date(shift.value.opened_at) : null
    const now = new Date()
    const today = opened && opened.toDateString() === now.toDateString()
    const time = !opened ? '' : opened.toLocaleString(locale.value, {
        ...(today ? {} : { day: 'numeric', month: 'short' }),
        ...(today || opened.getFullYear() === now.getFullYear() ? {} : { year: 'numeric' }),
        hour: 'numeric',
        minute: '2-digit',
    })
    return t('dashboard.shift_started', { who: shift.value.opened_by || shift.value.terminal || '—', time })
})

// --- Featured items & setup guide ------------------------------------------

// Featured items first; fall back to the newest items so the card is never empty.
const featured = computed(() => {
    const f = items.value.filter(i => i.is_featured)
    return (f.length ? f : items.value).slice(0, 5)
})
// Item ids whose image_url failed to load (dead/broken link) — they fall back
// to the meal-icon placeholder instead of the browser's broken-image glyph.
const failedImg = ref(new Set())
function onImgError(id) { failedImg.value.add(id) }
const itemName = (it) => pickLocalized(it, 'name', locale.value)
const itemAltName = (it) => locale.value === 'ar' ? (it.name_en || '') : (it.name_ar || '')
const categories = ref([])
const catOf = (it) => {
    const c = categories.value.find(c => c.id === it.category_id)
    return c ? pickLocalized(c, 'name', locale.value) : ''
}

// Setup guide: steps we can detect from stats/auth data. The card hides once
// every detectable step is done. The QR itself is printed from the restaurant
// profile page, so there's no separate "print your QR" step here.
const setupSteps = computed(() => stats.value ? [
    { key: 'category', labelKey: 'dashboard.step_category', to: { name: 'dashboard.categories' }, done: stats.value.total_categories > 0 },
    { key: 'item', labelKey: 'dashboard.step_item', to: { name: 'dashboard.items' }, done: stats.value.total_items > 0 },
    { key: 'logo', labelKey: 'dashboard.step_logo', to: { name: 'dashboard.profile' }, done: !!auth.restaurant?.logo_url },
] : [])
const setupDone = computed(() => setupSteps.value.filter(s => s.done).length)
const setupComplete = computed(() => setupSteps.value.length > 0 && setupDone.value === setupSteps.value.length)

// Dismissal is a per-browser convenience, so a storage that can throw (private
// window, blocked site data) must never take the page down with it.
const DISMISS_KEY = 'xorder.setup_dismissed'
const dismissed = ref((() => { try { return localStorage.getItem(DISMISS_KEY) === '1' } catch { return false } })())
function dismissSetup() {
    dismissed.value = true
    try { localStorage.setItem(DISMISS_KEY, '1') } catch { /* storage unavailable */ }
}
const showSetup = computed(() => !setupComplete.value && !dismissed.value && setupSteps.value.length > 0)
</script>

<template>
    <!-- Staff landing: no stats capability, so show who they are and where they
         may go rather than an error or an empty dashboard. -->
    <div v-if="!canAnalytics" class="space-y-6">
        <div>
            <h1 class="page-title">{{ clientName }}</h1>
            <p class="page-sub">{{ t('dashboard.staff_home_sub') }}</p>
        </div>
        <section class="card p-5" aria-labelledby="home-shortcuts">
            <h2 id="home-shortcuts" class="h-card mb-3">{{ t('stats.quick_actions') }}</h2>
            <div v-if="staffShortcuts.length" class="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
                <RouterLink v-for="link in staffShortcuts" :key="link.key" :to="link.to" class="shortcut">
                    <span class="shortcut-ico"><i :class="link.icon" aria-hidden="true"></i></span>
                    <span class="flex-1 min-w-0 truncate">{{ t(link.labelKey) }}</span>
                    <i class="pi pi-angle-right dir-flip shortcut-go" aria-hidden="true"></i>
                </RouterLink>
            </div>
            <p v-else class="text-sm py-6 text-center" style="color:var(--body)">{{ t('dashboard.staff_home_empty') }}</p>
        </section>
    </div>

    <div v-else-if="stats" class="home">
        <!-- Header -->
        <div class="flex flex-wrap items-end justify-between gap-4">
            <div class="min-w-0">
                <h1 class="page-title">{{ clientName }}</h1>
                <p class="page-sub" style="color:var(--body)">{{ t('dashboard.subtitle') }}</p>
            </div>
            <div class="flex items-center gap-2 flex-wrap">
                <a :href="asPreview(stats.public_url)" target="_blank" rel="noopener" class="btn btn-ghost touch"><Icon name="external" :size="16" />{{ t('dashboard.view_menu') }}</a>
                <RouterLink v-if="!auth.isReadOnly && auth.can('menu.create')" :to="{ name: 'dashboard.items' }" class="btn btn-accent touch"><Icon name="plus" :size="16" />{{ t('dashboard.add_item') }}</RouterLink>
            </div>
        </div>

        <!-- Setup guide (hidden once every detectable step is done, or dismissed) -->
        <section v-if="showSetup" class="card setup" :aria-label="t('dashboard.setup_guide')">
            <div class="setup-progress">
                <div class="flex items-baseline gap-2.5">
                    <span class="setup-title">{{ t('dashboard.setup_guide') }}</span>
                    <span class="setup-count">{{ setupDone }}/{{ setupSteps.length }}</span>
                </div>
                <div class="setup-track"><div class="setup-fill" :style="{ width: (setupDone / setupSteps.length * 100) + '%' }"></div></div>
            </div>
            <div class="flex gap-2 flex-wrap">
                <RouterLink v-for="s in setupSteps" :key="s.key" :to="s.to" class="step-pill" :class="{ done: s.done }">
                    <span class="step-dot"><Icon v-if="s.done" name="check" :size="10" /></span>{{ t(s.labelKey) }}
                </RouterLink>
            </div>
            <button class="icon-btn setup-x" :title="t('common.close')" :aria-label="t('common.close')" @click="dismissSetup"><Icon name="close" :size="16" /></button>
        </section>

        <!-- Headline counters. New orders lead: it is the only tile that asks for
             action, so it is first, lights up when something is waiting, and is
             the one big tap target. -->
        <section class="tiles" :aria-label="t('nav.dashboard')">
            <component :is="canOrders ? RouterLink : 'div'" v-bind="canOrders ? { to: { name: 'dashboard.orders' } } : {}"
                class="tile tile-orders" :class="{ 'tile-hot': stats.new_orders > 0 }">
                <div class="tile-head">
                    <span class="tile-title"><i class="pi pi-bell" aria-hidden="true"></i>{{ t('stats.new_orders') }}</span>
                    <span v-if="stats.new_orders" class="pulse" aria-hidden="true"></span>
                </div>
                <div class="flex items-end justify-between gap-2">
                    <span class="tile-num tile-num-lg">{{ stats.new_orders ?? 0 }}</span>
                    <span v-if="canOrders" class="tile-link">{{ t('dashboard.view_orders') }}<i class="pi pi-arrow-right dir-flip" aria-hidden="true"></i></span>
                </div>
            </component>

            <div class="tile">
                <div class="tile-head"><span class="tile-title">{{ t('dashboard.sales_today') }}</span><span class="tile-note">{{ t('dashboard.orders_count', { n: stats.orders_today ?? 0 }) }}</span></div>
                <div class="flex items-baseline gap-1.5">
                    <span class="tile-num">{{ group(stats.sales_today ?? 0) }}</span>
                    <span class="tile-unit">{{ cur }}</span>
                </div>
                <div v-if="salesChange" class="tile-delta" :style="{ color: salesUp ? 'var(--green)' : 'var(--red)' }">{{ salesChange }}</div>
            </div>

            <div class="tile">
                <div class="tile-head"><span class="tile-title">{{ t('dashboard.available_items') }}</span><span class="tile-note">{{ availablePct }}%</span></div>
                <div class="flex items-baseline gap-1.5">
                    <span class="tile-num">{{ stats.available_items }}</span>
                    <span class="tile-unit mono">/ {{ stats.total_items }}</span>
                </div>
                <div class="avail-track" aria-hidden="true"><div class="avail-fill" :style="{ width: availablePct + '%' }"></div></div>
                <RouterLink v-if="stats.unavailable_items && canMenu" :to="{ name: 'dashboard.items' }" class="tile-warn">
                    <i class="pi pi-exclamation-circle" aria-hidden="true"></i>{{ t('dashboard.unavailable_link', { n: stats.unavailable_items }) }}
                </RouterLink>
            </div>

            <div class="tile">
                <div class="tile-head"><span class="tile-title">{{ t('stats.views_today') }}</span></div>
                <div class="flex items-baseline justify-between gap-2">
                    <span class="tile-num">{{ stats.views_today ?? 0 }}</span>
                    <span v-if="viewsChange" class="tile-delta" :style="{ color: viewsDelta >= 0 ? 'var(--green)' : 'var(--red)' }">{{ viewsChange }}</span>
                </div>
            </div>

            <div class="tile">
                <div class="tile-head"><span class="tile-title">{{ t('stats.total_categories') }}</span></div>
                <div class="flex items-baseline justify-between gap-2">
                    <span class="tile-num">{{ stats.total_categories }}</span>
                    <RouterLink v-if="canMenu" :to="{ name: 'dashboard.categories' }" class="tile-link">{{ t('dashboard.manage_categories') }}</RouterLink>
                </div>
            </div>
        </section>

        <!-- Current shift: live trading figures, so it sits above the analytics -->
        <!-- With a shift open, the whole card opens its details page: the link
             is the heading, stretched over the card, so keyboard and screen
             readers get one link and not a clickable box. -->
        <section v-if="hasPos" class="card shift-card p-5 flex flex-col gap-4" :class="{ 'has-link': shift }" aria-labelledby="home-shift">
            <div class="flex items-start justify-between gap-3 flex-wrap">
                <div class="min-w-0">
                    <div class="flex items-center gap-2 flex-wrap">
                        <h2 id="home-shift" class="h-card">
                            <RouterLink v-if="shift" :to="{ name: 'dashboard.shift', params: { id: shift.id } }" class="shift-link"
                                :aria-label="t('shift.open_details')">{{ t('dashboard.current_shift') }}</RouterLink>
                            <template v-else>{{ t('dashboard.current_shift') }}</template>
                        </h2>
                        <span class="shift-pill" :class="{ off: !shift }">
                            <span class="shift-dot" aria-hidden="true"></span>{{ shift ? t('dashboard.shift_open') : t('dashboard.shift_none') }}
                        </span>
                    </div>
                    <p class="text-sm mt-1" style="color:var(--body)">{{ shift ? shiftMeta : t('dashboard.shift_none_sub') }}</p>
                </div>
                <div class="flex items-center gap-2 text-sm" style="color:var(--body)">
                    <i class="pi pi-desktop" style="font-size:14px" aria-hidden="true"></i>{{ t('dashboard.shift_managed_by_pos') }}
                    <span v-if="shift" class="shift-more" aria-hidden="true">{{ t('shift.open_details') }}<i class="pi pi-angle-right dir-flip" /></span>
                </div>
            </div>
            <div v-if="shift" class="shift-grid">
                <div v-for="k in shiftStats" :key="k.label" class="shift-cell">
                    <div class="text-sm" style="color:var(--body)">{{ k.label }}</div>
                    <div class="flex items-baseline gap-1.5 mt-1">
                        <span class="shift-num">{{ k.value }}</span>
                        <span class="text-sm" style="color:var(--body)">{{ k.unit }}</span>
                    </div>
                </div>
            </div>
        </section>

        <!-- Analytics and menu detail. Two columns that fold to one when there
             isn't room for both. -->
        <div class="panels">
            <!-- Menu views -->
            <section class="card p-5" aria-labelledby="home-views">
                <div class="flex items-start justify-between gap-3 flex-wrap">
                    <div>
                        <h2 id="home-views" class="h-card">{{ t('dashboard.menu_views') }}</h2>
                        <p class="text-sm mt-0.5" style="color:var(--body)">
                            <span class="mono" style="color:var(--ink);font-weight:700">{{ group(viewsTotal) }}</span>
                            {{ t('dashboard.views_word') }} {{ t('dashboard.over_range', { range: rangeLabel }) }}
                        </p>
                    </div>
                    <div class="seg" role="group" :aria-label="t('dashboard.menu_views')">
                        <button type="button" class="seg-btn" :class="{ on: range === 7 }" :aria-pressed="range === 7" @click="range = 7">{{ t('dashboard.range_7') }}</button>
                        <button type="button" class="seg-btn" :class="{ on: range === 14 }" :aria-pressed="range === 14" @click="range = 14">{{ t('dashboard.range_14') }}</button>
                    </div>
                </div>

                <template v-if="hasViews">
                    <div v-if="viewStats.length" class="view-stats">
                        <div v-for="m in viewStats" :key="m.label" class="view-stat">
                            <span class="view-stat-label">{{ m.label }}</span>
                            <span class="flex items-baseline gap-1.5">
                                <span class="view-stat-value mono">{{ m.value }}</span>
                                <span v-if="m.note" class="view-stat-note" :class="{ hl: m.highlight }">{{ m.note }}</span>
                            </span>
                        </div>
                    </div>
                    <div class="chart">
                        <div class="chart-y"><span>{{ group(viewsMax) }}</span><span>0</span></div>
                        <div>
                            <div class="chart-plot">
                                <div v-for="b in bars" :key="b.date" class="bar-slot" :title="b.tip">
                                    <div class="bar" :class="{ peak: b.peak, last: b.last && !b.peak }" :style="{ height: b.h }"></div>
                                </div>
                            </div>
                            <div class="chart-x">
                                <span v-for="b in bars" :key="b.date" :style="{ color: b.last ? 'var(--ink)' : 'var(--body)' }">{{ b.day }}</span>
                            </div>
                        </div>
                    </div>
                </template>
                <p v-else class="text-sm py-8 text-center" style="color:var(--body)">{{ t('dashboard.no_views') }}</p>
            </section>

            <!-- Featured items -->
            <section class="card pb-2" aria-labelledby="home-featured">
                <div class="flex items-center justify-between gap-3 px-5 py-4" style="border-bottom:1px solid var(--line)">
                    <h2 id="home-featured" class="h-card">{{ t('dashboard.featured_items') }}</h2>
                    <RouterLink v-if="canMenu" :to="{ name: 'dashboard.items' }" class="tile-link">{{ t('common.view_all') }}</RouterLink>
                </div>
                <ul v-if="featured.length">
                    <li v-for="it in featured" :key="it.id" class="feat-row">
                        <img v-if="it.image_url && !failedImg.has(it.id)" :src="it.image_url" @error="onImgError(it.id)" class="feat-thumb object-cover" alt="" />
                        <div v-else class="feat-thumb feat-thumb-blank"><Icon name="utensils" :size="18" /></div>
                        <div class="min-w-0 flex-1 feat-name">
                            <div class="font-medium truncate" style="color:var(--ink)">{{ itemName(it) }}</div>
                            <div v-if="itemAltName(it)" class="text-xs truncate" style="color:var(--body)" :dir="locale === 'ar' ? 'ltr' : 'rtl'">{{ itemAltName(it) }}</div>
                            <div v-if="catOf(it)" class="text-xs truncate" style="color:var(--body)">{{ catOf(it) }}</div>
                        </div>
                        <span v-if="!it.is_available" class="badge badge-amber"><i class="pi pi-ban" style="font-size:11px" aria-hidden="true"></i>{{ t('common.unavailable') }}</span>
                        <span class="feat-price whitespace-nowrap mono">{{ it.discounted_price || it.price }} <span class="feat-cur">{{ cur }}</span></span>
                    </li>
                </ul>
                <p v-else class="text-sm py-8 text-center" style="color:var(--body)">{{ t('common.none') }}</p>
            </section>
        </div>
    </div>

    <ErrorState v-else-if="error" @retry="load" />

    <!-- Loading skeleton: same blocks as the loaded page -->
    <div v-else class="home" aria-busy="true">
        <div class="space-y-2"><Skeleton w="220px" h="30px" /><Skeleton w="320px" h="16px" /></div>
        <div class="tiles">
            <Skeleton v-for="n in 5" :key="n" w="100%" h="112px" rounded="14px" />
        </div>
        <div class="panels">
            <Skeleton w="100%" h="340px" rounded="15px" />
            <Skeleton w="100%" h="340px" rounded="15px" />
        </div>
    </div>
</template>

<style scoped>
/* Colours come only from the shared theme variables and the PrimeVue primary
   scale; nothing here introduces a new hex value. */
.home { display: flex; flex-direction: column; gap: 20px; }
.mono { font-family: var(--font-mono); font-variant-numeric: tabular-nums; }
.touch { min-height: 44px; }
/* Directional icons mirror under RTL */
[dir=rtl] .dir-flip { transform: scaleX(-1); }

/* ── Staff shortcuts ────────────────────────────────────────────── */
.shortcut { display: flex; align-items: center; gap: 12px; min-height: 56px; padding: 8px 14px; border-radius: 12px;
    border: 1px solid var(--line); background: var(--card); color: var(--ink); font-weight: 600; font-size: 15.5px;
    transition: border-color .15s, background .15s; }
.shortcut:hover { border-color: var(--accent); background: var(--page); }
.shortcut-ico { width: 38px; height: 38px; border-radius: 10px; flex: none; display: grid; place-items: center;
    background: var(--accent-soft); color: var(--p-primary-700); font-size: 16px; }
.shortcut-go { color: var(--body); font-size: 13px; }

/* ── Setup guide ────────────────────────────────────────────────── */
.setup { padding: 16px 20px; display: flex; align-items: center; gap: 20px; flex-wrap: wrap; }
.setup-progress { flex: 1 1 240px; min-width: 0; }
.setup-title { font-family: var(--font-display); font-weight: 700; font-size: 15.5px; color: var(--ink); }
.setup-count { font-family: var(--font-mono); font-size: 13px; color: var(--body); }
.setup-track { margin-top: 10px; height: 6px; border-radius: 999px; background: var(--gray-soft); overflow: hidden; }
.setup-fill { height: 100%; background: var(--accent); border-radius: 999px; transition: width .2s; }
.step-pill {
    min-height: 40px; flex: none; padding: 0 14px; white-space: nowrap;
    display: inline-flex; align-items: center; gap: 8px;
    border-radius: 999px; border: 1px solid var(--accent); background: var(--accent-soft);
    font-size: 14px; font-weight: 600; color: var(--ink);
}
.step-pill.done { border-color: var(--line); background: var(--page); color: var(--body); font-weight: 400; }
.step-dot {
    width: 18px; height: 18px; border-radius: 50%; flex: none;
    border: 1.5px solid var(--accent); display: grid; place-items: center; color: var(--card);
}
.step-pill.done .step-dot { border-color: var(--green); background: var(--green); }
.setup-x { flex: none; width: 44px; height: 44px; }

/* ── Headline counters ──────────────────────────────────────────── */
.tiles { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 210px), 1fr)); gap: 12px; }
.tile {
    background: var(--card); border: 1px solid var(--line); border-radius: 14px;
    padding: 16px 18px; display: flex; flex-direction: column; gap: 10px;
    text-decoration: none; min-width: 0;
    transition: border-color .15s, background .15s;
}
a.tile:hover { border-color: var(--accent); }
a.tile:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
.tile-head {
    display: flex; align-items: center; justify-content: space-between; gap: 8px;
    font-size: 14.5px; color: var(--body);
}
.tile-title { display: inline-flex; align-items: center; gap: 8px; font-weight: 500; color: var(--body); }
.tile-note { font-size: 13px; color: var(--body); font-family: var(--font-mono); }
.tile-num {
    font-family: var(--font-mono); font-size: 32px; font-weight: 700;
    letter-spacing: -.02em; color: var(--ink); line-height: 1;
}
.tile-num-lg { font-size: 44px; }
.tile-unit { font-size: 14px; color: var(--body); }
.tile-delta { font-size: 14px; font-weight: 600; }
.tile-link { display: inline-flex; align-items: center; gap: 6px; font-size: 14px; font-weight: 600; color: var(--p-primary-700); }
a.tile:hover .tile-link, .tile-link:hover { text-decoration: underline; }
.tile-warn {
    display: inline-flex; align-items: center; gap: 7px; min-height: 32px; font-size: 14px; font-weight: 600; color: var(--red);
}
.tile-warn:hover { text-decoration: underline; }
.avail-track { height: 6px; border-radius: 999px; background: var(--red-soft); overflow: hidden; }
.avail-fill { height: 100%; background: var(--green); }
/* The lead tile: a pending order turns it into an accent block so it is the
   first thing seen from across the counter. */
.tile-orders { gap: 14px; }
.tile-hot { background: var(--accent-soft); border-color: var(--accent); border-width: 2px; padding: 15px 17px; }
.tile-hot .tile-title { color: var(--ink); font-weight: 700; }
.tile-hot .tile-link { color: var(--p-primary-800); }
/* A live count that is about to be acted on. */
.pulse {
    width: 10px; height: 10px; border-radius: 50%; flex: none;
    background: var(--accent); box-shadow: 0 0 0 4px var(--accent-soft);
    animation: tile-pulse 1.6s ease-in-out infinite;
}
@keyframes tile-pulse { 50% { box-shadow: 0 0 0 7px var(--accent-soft); } }
@media (prefers-reduced-motion: reduce) { .pulse { animation: none; } }

/* ── Current shift ──────────────────────────────────────────────── */
/* The heading link stretches over the card (see the template comment). */
.shift-card { position: relative; transition: border-color .15s; }
.shift-card.has-link:hover { border-color: var(--p-primary-300); }
.shift-link { color: inherit; }
.shift-link::after { content: ''; position: absolute; inset: 0; border-radius: inherit; }
.shift-link:focus-visible { outline: none; }
.shift-link:focus-visible::after { outline: 2px solid var(--accent); outline-offset: 2px; }
.shift-more { display: inline-flex; align-items: center; gap: 4px; margin-inline-start: 10px; font-weight: 600; color: var(--p-primary-700); }
.shift-pill {
    display: inline-flex; align-items: center; gap: 6px; white-space: nowrap;
    font-size: 13px; font-weight: 600; padding: 3px 10px; border-radius: 999px;
    background: var(--green-soft); color: var(--green);
}
.shift-pill.off { background: var(--gray-soft); color: var(--body); }
.shift-dot { width: 7px; height: 7px; border-radius: 50%; background: currentColor; }
.shift-grid {
    display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 1px;
    background: var(--line); border: 1px solid var(--line); border-radius: 12px; overflow: hidden;
}
.shift-cell { background: var(--card); padding: 14px 16px; min-width: 0; }
.shift-num { font-family: var(--font-mono); font-size: 22px; font-weight: 700; color: var(--ink); }
@media (max-width: 720px) { .shift-grid { grid-template-columns: repeat(2, minmax(0, 1fr)); } }

/* ── Panels ─────────────────────────────────────────────────────── */
.panels {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(min(100%, 420px), 1fr));
    gap: 20px; align-items: start;
}

/* ── Menu-views chart ───────────────────────────────────────────── */
.seg { display: flex; gap: 2px; padding: 3px; background: var(--gray-soft); border-radius: 10px; }
.seg-btn {
    min-height: 36px; padding: 0 14px; white-space: nowrap; border: 0; border-radius: 8px;
    background: transparent; color: var(--body);
    font-family: inherit; font-size: 14px; font-weight: 500; cursor: pointer;
    transition: background .15s, color .15s, box-shadow .15s;
}
.seg-btn.on { background: var(--card); color: var(--ink); font-weight: 600; box-shadow: 0 1px 2px rgba(0, 0, 0, .1); }
/* Mini-metrics above the chart answer "compared to what?" for the totals line.
   `.hl` on the peak day's note ties it back to the highlighted bar below. */
.view-stats { margin-top: 14px; display: flex; gap: 24px; flex-wrap: wrap; }
.view-stat { display: flex; flex-direction: column; gap: 2px; min-width: 0; }
.view-stat-label { font-size: 13px; color: var(--body); }
.view-stat-value { font-size: 17px; font-weight: 700; color: var(--ink); font-variant-numeric: tabular-nums; }
.view-stat-note { font-size: 13px; font-weight: 500; color: var(--body); }
.view-stat-note.hl { color: var(--p-primary-800); font-weight: 600; }

.chart { margin-top: 16px; display: grid; grid-template-columns: 44px minmax(0, 1fr); gap: 8px; }
.chart-y {
    display: flex; flex-direction: column; justify-content: space-between; height: 160px;
    font-family: var(--font-mono); font-size: 12px; color: var(--body); text-align: end;
}
.chart-plot {
    height: 160px; display: flex; align-items: flex-end; gap: 6px;
    border-bottom: 1px solid var(--line);
}
.bar-slot { flex: 1; height: 100%; display: flex; align-items: flex-end; min-width: 0; }
/* Three-tier fill: the busiest day in solid accent, today one step lighter,
   the rest in a soft tint. All derived from the accent variable. */
.bar {
    width: 100%; min-height: 3px; border-radius: 4px 4px 0 0;
    background: color-mix(in srgb, var(--accent) 42%, var(--card));
}
.bar.last { background: color-mix(in srgb, var(--accent) 62%, var(--card)); }
.bar.peak { background: var(--accent); }
.chart-x { display: flex; gap: 6px; margin-top: 6px; }
.chart-x > span {
    flex: 1; text-align: center; min-width: 0;
    font-family: var(--font-mono); font-size: 12px;
}

/* ── Featured items ─────────────────────────────────────────────── */
.feat-row {
    display: flex; align-items: center; gap: 12px;
    padding: 10px 20px; min-height: 64px; border-bottom: 1px solid var(--line);
    transition: background .15s;
}
.feat-row:last-child { border-bottom: 0; }
.feat-row:hover { background: var(--page); }
.feat-thumb { flex: none; width: 46px; height: 46px; border-radius: 10px; }
.feat-thumb-blank { display: grid; place-items: center; background: var(--accent-soft); color: var(--p-primary-700); }
.feat-price { font-weight: 700; color: var(--ink); text-align: end; }
.feat-cur { font-weight: 500; color: var(--body); font-size: 13px; }
/* The alt-name carries dir="ltr" for correct English shaping, which would
   otherwise start-align it to the left — force every line in the block to the
   reading edge so the names stack together next to the image. */
[dir="rtl"] .feat-name > * { text-align: right !important; }
[dir="ltr"] .feat-name > * { text-align: left !important; }
</style>
