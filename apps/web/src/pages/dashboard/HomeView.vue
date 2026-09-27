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
import { alert } from '@xorder/ui/alert.js'
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
const qr = ref(null)
const items = ref([])
const engagement = ref(null)
const copied = ref(false)
// Without this, a failed core fetch left `stats` null forever and the page
// showed a permanent loading skeleton — a blank first screen after login.
const error = ref(false)

// This page is where every tenant account lands, owners and staff alike, so it
// must not assume the full owner capability set. Each panel is fetched only if
// the signed-in user may read it; a role without analytics.view gets the plain
// shortcut landing below instead of a wall of stats it cannot see.
const canAnalytics = computed(() => auth.can('analytics.view'))
const canMenu = computed(() => auth.can('menu.view'))
const canSettings = computed(() => auth.can('settings.view'))
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
        const [s, q, it, cats] = await Promise.all([
            api.get('api/dashboard/stats'),
            canSettings.value ? api.get('api/dashboard/qr') : Promise.resolve(null),
            canMenu.value ? api.get('api/dashboard/items') : Promise.resolve(null),
            canMenu.value ? api.get('api/dashboard/categories') : Promise.resolve(null),
        ])
        stats.value = s.data.data
        qr.value = q.data?.data ?? null
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
const bars = computed(() => viewDays.value.map((d, i, all) => ({
    date: d.date,
    day: new Date(d.date + 'T00:00:00').getDate(),
    last: i === all.length - 1,
    h: viewsMax.value > 0 ? (d.views / viewsMax.value) * 100 + '%' : '0%',
    tip: `${d.date} — ${t('dashboard.views_total', { n: d.views })}`,
})))
const rangeLabel = computed(() => t(range.value === 7 ? 'dashboard.last_7' : 'dashboard.last_14'))

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
    const time = shift.value.opened_at
        ? new Date(shift.value.opened_at).toLocaleTimeString(locale.value, { hour: 'numeric', minute: '2-digit' })
        : ''
    return t('dashboard.shift_started', { who: shift.value.opened_by || shift.value.terminal || '—', time })
})

// --- QR / sharing ----------------------------------------------------------

// JWT-Bearer API: fetch the PNG through the authed client (a bare link carries
// no Authorization header and 401s), then save the blob.
async function downloadQr() {
    try {
        const res = await api.get('api/dashboard/qr/download', { responseType: 'blob' })
        const blobUrl = URL.createObjectURL(res.data)
        const a = document.createElement('a')
        a.href = blobUrl; a.download = 'qr-menu.png'; a.click()
        URL.revokeObjectURL(blobUrl)
    } catch (err) { alert(err.response?.data?.message || t('admin.download_failed')) }
}

// Print the code on its own rather than the whole dashboard: a table tent is
// the QR and the menu address, not a screenshot of the admin UI.
function printQr() {
    if (!qr.value?.svg) return
    const w = window.open('', '_blank', 'width=480,height=640')
    if (!w) return
    w.document.write(`<!doctype html><html><head><title>${clientName.value}</title>
        <style>body{margin:0;display:grid;place-items:center;min-height:100vh;font-family:system-ui,sans-serif;gap:16px}
        svg{width:280px;height:280px}.u{font:13px ui-monospace,monospace;color:#555}</style></head>
        <body><div>${qr.value.svg}</div><div class="u">${stats.value?.public_url || ''}</div></body></html>`)
    w.document.close()
    w.focus()
    w.print()
}

function copyUrl() {
    if (!stats.value) return
    navigator.clipboard?.writeText(stats.value.public_url)
    copied.value = true
    setTimeout(() => (copied.value = false), 1600)
}

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
// every detectable step is done. (The QR lives on the card to the right, so
// there's no separate "print your QR" step.)
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
        <div class="card p-5">
            <h2 class="h-card mb-3">{{ t('stats.quick_actions') }}</h2>
            <div v-if="staffShortcuts.length" class="flex flex-col gap-2">
                <RouterLink v-for="link in staffShortcuts" :key="link.key" :to="link.to" class="btn btn-ghost justify-start">
                    <i :class="link.icon" style="font-size:15px" aria-hidden="true"></i>{{ t(link.labelKey) }}
                </RouterLink>
            </div>
            <p v-else class="text-sm py-6 text-center" style="color:var(--muted)">{{ t('dashboard.staff_home_empty') }}</p>
        </div>
    </div>

    <div v-else-if="stats" class="home">
        <!-- Header -->
        <div class="flex flex-wrap items-end justify-between gap-4">
            <div>
                <h1 class="page-title">{{ clientName }}</h1>
                <p class="page-sub">{{ t('dashboard.subtitle') }}</p>
            </div>
            <div class="flex items-center gap-2 flex-wrap">
                <a :href="asPreview(stats.public_url)" target="_blank" class="btn btn-ghost"><Icon name="external" :size="16" />{{ t('dashboard.view_menu') }}</a>
                <RouterLink v-if="!auth.isReadOnly && auth.can('menu.create')" :to="{ name: 'dashboard.items' }" class="btn btn-accent"><Icon name="plus" :size="16" />{{ t('dashboard.add_item') }}</RouterLink>
            </div>
        </div>

        <!-- Setup guide (hidden once every detectable step is done, or dismissed) -->
        <div v-if="showSetup" class="card setup">
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
        </div>

        <!-- Headline counters -->
        <div class="tiles">
            <div class="tile">
                <div class="tile-head">{{ t('dashboard.sales_today') }}<span class="tile-note">{{ t('dashboard.orders_count', { n: stats.orders_today ?? 0 }) }}</span></div>
                <div class="flex items-baseline gap-1.5">
                    <span class="tile-num">{{ group(stats.sales_today ?? 0) }}</span>
                    <span class="tile-unit">{{ cur }}</span>
                </div>
                <div v-if="salesChange" class="tile-delta" :style="{ color: salesUp ? 'var(--green)' : 'var(--red)' }">{{ salesChange }}</div>
            </div>

            <component :is="canOrders ? RouterLink : 'div'" v-bind="canOrders ? { to: { name: 'dashboard.orders' } } : {}" class="tile">
                <div class="tile-head">{{ t('stats.new_orders') }}<span v-if="stats.new_orders" class="pulse"></span></div>
                <div class="flex items-baseline justify-between gap-2">
                    <span class="tile-num">{{ stats.new_orders ?? 0 }}</span>
                    <span v-if="canOrders" class="tile-link">{{ t('dashboard.view_orders') }}</span>
                </div>
            </component>

            <div class="tile">
                <div class="tile-head">{{ t('stats.views_today') }}</div>
                <div class="flex items-baseline justify-between gap-2">
                    <span class="tile-num">{{ stats.views_today ?? 0 }}</span>
                    <span v-if="viewsChange" class="tile-delta" :style="{ color: viewsDelta >= 0 ? 'var(--green)' : 'var(--red)' }">{{ viewsChange }}</span>
                </div>
            </div>

            <div class="tile">
                <div class="tile-head">{{ t('dashboard.available_items') }}<span class="tile-note">{{ availablePct }}%</span></div>
                <div class="flex items-baseline gap-1.5">
                    <span class="tile-num">{{ stats.available_items }}</span>
                    <span class="tile-unit mono">/ {{ stats.total_items }}</span>
                </div>
                <div class="avail-track"><div class="avail-fill" :style="{ width: availablePct + '%' }"></div></div>
                <RouterLink v-if="stats.unavailable_items && canMenu" :to="{ name: 'dashboard.items' }" class="tile-warn">
                    {{ t('dashboard.unavailable_link', { n: stats.unavailable_items }) }}
                </RouterLink>
            </div>

            <div class="tile">
                <div class="tile-head">{{ t('stats.total_categories') }}</div>
                <div class="flex items-baseline justify-between gap-2">
                    <span class="tile-num">{{ stats.total_categories }}</span>
                    <RouterLink v-if="canMenu" :to="{ name: 'dashboard.categories' }" class="tile-link">{{ t('dashboard.manage_categories') }}</RouterLink>
                </div>
            </div>
        </div>

        <!-- Two columns that fold to one when there isn't room for both -->
        <div class="panels">
            <div class="col">
                <!-- Menu views -->
                <div class="card p-5">
                    <div class="flex items-start justify-between gap-3 flex-wrap">
                        <div>
                            <h2 class="h-card">{{ t('dashboard.menu_views') }}</h2>
                            <p class="text-xs mt-0.5" style="color:var(--muted)">
                                <span class="mono" style="color:var(--ink);font-weight:600">{{ group(viewsTotal) }}</span>
                                {{ t('dashboard.views_word') }} {{ t('dashboard.over_range', { range: rangeLabel }) }}
                            </p>
                        </div>
                        <div class="seg">
                            <button class="seg-btn" :class="{ on: range === 7 }" @click="range = 7">{{ t('dashboard.range_7') }}</button>
                            <button class="seg-btn" :class="{ on: range === 14 }" @click="range = 14">{{ t('dashboard.range_14') }}</button>
                        </div>
                    </div>

                    <template v-if="hasViews">
                        <div class="chart">
                            <div class="chart-y"><span>{{ group(viewsMax) }}</span><span>0</span></div>
                            <div>
                                <div class="chart-plot">
                                    <div v-for="b in bars" :key="b.date" class="bar-slot" :title="b.tip">
                                        <div class="bar" :style="{ height: b.h }"></div>
                                    </div>
                                </div>
                                <div class="chart-x">
                                    <span v-for="b in bars" :key="b.date" :style="{ color: b.last ? 'var(--ink)' : 'var(--muted)' }">{{ b.day }}</span>
                                </div>
                            </div>
                        </div>
                    </template>
                    <p v-else class="text-sm py-8 text-center" style="color:var(--muted)">{{ t('dashboard.no_views') }}</p>
                </div>

                <!-- Featured items -->
                <div class="card overflow-hidden">
                    <div class="flex items-center justify-between px-5 py-4" style="border-bottom:1px solid var(--line)">
                        <h2 class="h-card">{{ t('dashboard.featured_items') }}</h2>
                        <RouterLink v-if="canMenu" :to="{ name: 'dashboard.items' }" class="tile-link">{{ t('common.view_all') }}</RouterLink>
                    </div>
                    <div v-if="featured.length">
                        <div v-for="it in featured" :key="it.id" class="feat-row">
                            <img v-if="it.image_url && !failedImg.has(it.id)" :src="it.image_url" @error="onImgError(it.id)" class="feat-thumb object-cover" alt="" />
                            <div v-else class="feat-thumb feat-thumb-blank"><Icon name="utensils" :size="18" /></div>
                            <div class="min-w-0 flex-1 feat-name">
                                <div class="font-medium truncate" style="color:var(--ink)">{{ itemName(it) }}</div>
                                <div v-if="itemAltName(it)" class="text-xs truncate" style="color:var(--muted)" :dir="locale === 'ar' ? 'ltr' : 'rtl'">{{ itemAltName(it) }}</div>
                            </div>
                            <span v-if="catOf(it)" class="text-xs whitespace-nowrap" style="color:var(--muted)">{{ catOf(it) }}</span>
                            <span v-if="!it.is_available" class="badge badge-amber">{{ t('common.unavailable') }}</span>
                            <span class="price whitespace-nowrap mono">{{ it.discounted_price || it.price }} {{ cur }}</span>
                        </div>
                    </div>
                    <p v-else class="text-sm py-8 text-center" style="color:var(--muted)">{{ t('common.none') }}</p>
                </div>
            </div>

            <div class="col">
                <!-- Current shift -->
                <div v-if="hasPos" class="card p-5 flex flex-col gap-4">
                    <div class="flex items-start justify-between gap-3">
                        <div>
                            <div class="flex items-center gap-2 flex-wrap">
                                <h2 class="h-card">{{ t('dashboard.current_shift') }}</h2>
                                <span class="shift-pill" :class="{ off: !shift }">
                                    <span class="shift-dot"></span>{{ shift ? t('dashboard.shift_open') : t('dashboard.shift_none') }}
                                </span>
                            </div>
                            <p class="text-xs mt-1" style="color:var(--muted)">{{ shift ? shiftMeta : t('dashboard.shift_none_sub') }}</p>
                        </div>
                    </div>
                    <div v-if="shift" class="shift-grid">
                        <div v-for="k in shiftStats" :key="k.label" class="shift-cell">
                            <div class="text-xs" style="color:var(--muted)">{{ k.label }}</div>
                            <div class="flex items-baseline gap-1 mt-1">
                                <span class="shift-num">{{ k.value }}</span>
                                <span class="text-xs" style="color:var(--muted)">{{ k.unit }}</span>
                            </div>
                        </div>
                    </div>
                    <div class="flex items-center gap-2 text-xs pt-3" style="color:var(--muted);border-top:1px solid var(--line)">
                        <i class="pi pi-desktop" style="font-size:13px"></i>{{ t('dashboard.shift_managed_by_pos') }}
                    </div>
                </div>

                <!-- Share the menu -->
                <div v-if="qr" class="share-card">
                    <div>
                        <div class="share-title">{{ t('dashboard.share_menu') }}</div>
                        <div class="share-sub">{{ t('dashboard.share_menu_sub') }}</div>
                    </div>
                    <div class="flex gap-4 items-center flex-wrap">
                        <div class="share-qr"><div v-html="qr.svg" class="qrbox"></div></div>
                        <div class="flex-1 flex flex-col gap-2" style="min-width:140px">
                            <button @click="downloadQr" class="share-btn share-btn-accent"><Icon name="download" :size="15" />PNG</button>
                            <button @click="printQr" class="share-btn share-btn-ghost"><i class="pi pi-print" style="font-size:14px"></i>{{ t('dashboard.print') }}</button>
                        </div>
                    </div>
                    <div class="share-url">
                        <span dir="ltr" class="share-url-text mono">{{ stats.public_url }}</span>
                        <button @click="copyUrl" class="share-copy">
                            <Icon :name="copied ? 'check' : 'copy'" :size="14" />{{ copied ? t('common.copied') : t('common.copy') }}
                        </button>
                    </div>
                </div>

                <!-- Quick actions -->
                <div class="card p-2">
                    <div class="quick-head">{{ t('stats.quick_actions') }}</div>
                    <RouterLink v-if="canMenu" :to="{ name: 'dashboard.categories' }" class="quick-row"><Icon name="categories" :size="18" /><span class="flex-1">{{ t('nav.categories') }}</span><Icon name="chevronDown" :size="14" class="quick-chev" /></RouterLink>
                    <RouterLink v-if="canMenu" :to="{ name: 'dashboard.items' }" class="quick-row"><Icon name="items" :size="18" /><span class="flex-1">{{ t('nav.items') }}</span><Icon name="chevronDown" :size="14" class="quick-chev" /></RouterLink>
                    <RouterLink v-if="canSettings" :to="{ name: 'dashboard.profile' }" class="quick-row"><Icon name="store" :size="18" /><span class="flex-1">{{ t('dashboard.restaurant_profile') }}</span><Icon name="chevronDown" :size="14" class="quick-chev" /></RouterLink>
                </div>
            </div>
        </div>
    </div>

    <ErrorState v-else-if="error" @retry="load" />

    <!-- Loading skeleton -->
    <div v-else class="space-y-6">
        <div class="h-8 w-48 rounded-lg" style="background:var(--line)"></div>
        <div class="tiles">
            <div v-for="n in 5" :key="n" class="card" style="height:104px"></div>
        </div>
        <div class="panels">
            <div class="card" style="height:340px"></div>
            <div class="card" style="height:340px"></div>
        </div>
    </div>
</template>

<style scoped>
.home { display: flex; flex-direction: column; gap: 20px; }
.mono { font-family: var(--font-mono); font-variant-numeric: tabular-nums; }

/* ── Setup guide ────────────────────────────────────────────────── */
.setup { padding: 16px 20px; display: flex; align-items: center; gap: 20px; flex-wrap: wrap; }
.setup-progress { flex: 1 1 240px; min-width: 0; }
.setup-title { font-family: var(--font-display); font-weight: 700; font-size: 15px; color: var(--ink); }
.setup-count { font-family: var(--font-mono); font-size: 12.5px; color: var(--muted); }
.setup-track { margin-top: 10px; height: 6px; border-radius: 999px; background: var(--gray-soft); overflow: hidden; }
.setup-fill { height: 100%; background: var(--accent); border-radius: 999px; transition: width .2s; }
.step-pill {
    height: 36px; flex: none; padding: 0 12px; white-space: nowrap;
    display: inline-flex; align-items: center; gap: 8px;
    border-radius: 999px; border: 1px solid var(--accent); background: var(--accent-soft);
    font-size: 13px; font-weight: 600; color: var(--ink);
}
.step-pill.done { border-color: var(--line); background: var(--page); color: var(--muted); font-weight: 400; }
.step-dot {
    width: 18px; height: 18px; border-radius: 50%; flex: none;
    border: 1.5px solid var(--accent); display: grid; place-items: center; color: #fff;
}
.step-pill.done .step-dot { border-color: var(--green); background: var(--green); }
.setup-x { flex: none; }

/* ── Headline counters ──────────────────────────────────────────── */
.tiles { display: grid; grid-template-columns: repeat(auto-fit, minmax(190px, 1fr)); gap: 12px; }
.tile {
    background: var(--card); border: 1px solid var(--line); border-radius: 14px;
    padding: 16px 18px; display: flex; flex-direction: column; gap: 10px;
    text-decoration: none; min-width: 0;
}
a.tile:hover { border-color: var(--accent); }
.tile-head {
    display: flex; align-items: center; justify-content: space-between; gap: 8px;
    font-size: 13px; color: var(--body);
}
.tile-note { font-size: 12px; color: var(--muted); font-family: var(--font-mono); }
.tile-num {
    font-family: var(--font-mono); font-size: 30px; font-weight: 700;
    letter-spacing: -.02em; color: var(--ink); line-height: 1;
}
.tile-unit { font-size: 13px; color: var(--muted); }
.tile-delta { font-size: 12.5px; font-weight: 500; }
.tile-link { font-size: 12.5px; font-weight: 500; color: var(--accent); }
.tile-warn { font-size: 12.5px; font-weight: 500; color: var(--red); }
.avail-track { height: 4px; border-radius: 999px; background: var(--red-soft); overflow: hidden; }
.avail-fill { height: 100%; background: var(--green); }
/* A live count that is about to be acted on — the one thing on this row that
   changes while the page is open. */
.pulse {
    width: 8px; height: 8px; border-radius: 50%; flex: none;
    background: var(--accent); box-shadow: 0 0 0 4px var(--accent-soft);
}

/* ── Panels ─────────────────────────────────────────────────────── */
.panels {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(min(100%, 420px), 1fr));
    gap: 20px; align-items: start;
}
.col { display: flex; flex-direction: column; gap: 20px; min-width: 0; }

/* ── Payments ───────────────────────────────────────────────────── */
.seg { display: flex; gap: 2px; padding: 3px; background: var(--gray-soft); border-radius: 9px; }
.seg-btn {
    height: 28px; padding: 0 12px; white-space: nowrap; border: 0; border-radius: 7px;
    background: transparent; color: var(--body);
    font-family: inherit; font-size: 12.5px; font-weight: 500; cursor: pointer;
    transition: background .15s, color .15s, box-shadow .15s;
}
.seg-btn.on { background: var(--card); color: var(--ink); font-weight: 600; box-shadow: 0 1px 2px rgba(0, 0, 0, .1); }
.chart { margin-top: 16px; display: grid; grid-template-columns: 44px minmax(0, 1fr); gap: 8px; }
.chart-y {
    display: flex; flex-direction: column; justify-content: space-between; height: 160px;
    font-family: var(--font-mono); font-size: 11px; color: var(--muted); text-align: end;
}
.chart-plot {
    height: 160px; display: flex; align-items: flex-end; gap: 6px;
    border-bottom: 1px solid var(--line);
}
.bar-slot { flex: 1; height: 100%; display: flex; align-items: flex-end; min-width: 0; }
.bar {
    width: 100%; min-height: 3px; border-radius: 4px 4px 0 0;
    background: var(--accent);
}
.chart-x { display: flex; gap: 6px; margin-top: 6px; }
.chart-x > span {
    flex: 1; text-align: center; min-width: 0;
    font-family: var(--font-mono); font-size: 11px;
}

/* ── Featured items ─────────────────────────────────────────────── */
.feat-row {
    display: flex; align-items: center; gap: 12px;
    padding: 12px 20px; border-bottom: 1px solid var(--line);
}
.feat-row:last-child { border-bottom: 0; }
.feat-row:hover { background: var(--page); }
.feat-thumb { flex: none; width: 44px; height: 44px; border-radius: 10px; }
.feat-thumb-blank { display: grid; place-items: center; background: var(--accent-soft); color: var(--accent); }
/* The alt-name carries dir="ltr" for correct English shaping, which would
   otherwise start-align it to the left — force every line in the block to the
   reading edge so the two names stack together next to the image. */
[dir="rtl"] .feat-name > * { text-align: right !important; }
[dir="ltr"] .feat-name > * { text-align: left !important; }

/* ── Current shift ──────────────────────────────────────────────── */
.shift-pill {
    display: inline-flex; align-items: center; gap: 6px; white-space: nowrap;
    font-size: 12px; font-weight: 600; padding: 2px 9px; border-radius: 999px;
    background: var(--green-soft); color: var(--green);
}
.shift-pill.off { background: var(--gray-soft); color: var(--muted); }
.shift-dot { width: 6px; height: 6px; border-radius: 50%; background: currentColor; }
.shift-grid {
    display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 1px;
    background: var(--line); border: 1px solid var(--line); border-radius: 10px; overflow: hidden;
}
.shift-cell { background: var(--card); padding: 12px 14px; min-width: 0; }
.shift-num { font-family: var(--font-mono); font-size: 18px; font-weight: 700; color: var(--ink); }

/* ── Share card ─────────────────────────────────────────────────── */
.share-card {
    background: var(--ink); border-radius: 14px; padding: 20px; color: #fff;
    display: flex; flex-direction: column; gap: 16px;
}
.share-title { font-family: var(--font-display); font-weight: 700; font-size: 15px; }
.share-sub { margin-top: 2px; font-size: 12.5px; color: rgba(255, 255, 255, .62); }
.share-qr { flex: none; width: 120px; height: 120px; border-radius: 12px; background: #fff; padding: 10px; }
.share-qr .qrbox { width: 100%; height: 100%; }
.share-qr :deep(svg) { width: 100%; height: 100%; display: block; }
.share-btn {
    height: 36px; padding: 0 12px; border-radius: 9px; cursor: pointer;
    display: flex; align-items: center; justify-content: center; gap: 8px;
    font-family: inherit; font-size: 13px; font-weight: 600; border: 0;
    transition: filter .15s, background .15s;
}
.share-btn-accent { background: var(--accent); color: #fff; }
.share-btn-accent:hover { background: var(--accent-dark); }
.share-btn-ghost { background: transparent; border: 1px solid rgba(255, 255, 255, .26); color: #fff; font-weight: 500; }
.share-btn-ghost:hover { background: rgba(255, 255, 255, .1); }
.share-url {
    display: flex; align-items: center; gap: 6px; padding: 4px;
    background: rgba(255, 255, 255, .08); border-radius: 10px; min-width: 0;
}
.share-url-text {
    flex: 1; min-width: 0; padding: 0 10px; font-size: 12.5px;
    color: rgba(255, 255, 255, .88);
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
}
.share-copy {
    height: 32px; padding: 0 12px; flex: none; border: 0; border-radius: 8px; cursor: pointer;
    display: flex; align-items: center; gap: 6px;
    background: #fff; color: var(--ink); font-family: inherit; font-size: 12.5px; font-weight: 600;
}

/* ── Quick actions ──────────────────────────────────────────────── */
.quick-head { padding: 10px 12px 6px; font-size: 13px; font-weight: 600; color: var(--body); }
.quick-row {
    display: flex; align-items: center; gap: 12px; padding: 10px 12px;
    border-radius: 9px; color: var(--ink); font-size: 14px; text-decoration: none;
    transition: background .15s;
}
.quick-row:hover { background: var(--page); }
.quick-row :deep(svg):first-child { color: var(--muted); flex: none; }
.quick-chev { color: var(--muted); transform: rotate(90deg); }
[dir="rtl"] .quick-chev { transform: rotate(-90deg); }
</style>
