<script setup>
// "My plan": what the restaurant is on, how much of each enforced limit it
// uses, and what the other plans offer. Read-only — changing plan is a
// WhatsApp conversation with Xorder until there is a checkout.
import { computed, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import api from '@xorder/api-client/api.js'
import { useAuth } from '@xorder/api-client/auth.js'
import { pickLocalized } from '@xorder/ui/localize.js'
import ErrorState from '@xorder/ui/ErrorState.vue'
import Icon from '@xorder/ui/Icon.vue'
import { currencyLabel } from '../../lib/currency.js'
import { withMinDuration } from '../../lib/minLoading.js'

const { t, locale } = useI18n()
const auth = useAuth()

const data = ref(null)
const loading = ref(true)
const failed = ref(false)

async function load() {
    loading.value = true
    failed.value = false
    try {
        const res = await withMinDuration(api.get('api/dashboard/plan'))
        data.value = res.data.data
    } catch {
        failed.value = true
    } finally {
        loading.value = false
    }
}
onMounted(load)

const plan = computed(() => data.value?.plan || null)
const sub = computed(() => data.value?.subscription || {})
const planName = computed(() => plan.value?.name || data.value?.plan_name || t('my_plan.no_plan'))

const STATUS_BADGE = { TRIAL: 'badge-amber', ACTIVE: 'badge-green', EXPIRED: 'badge-red', SUSPENDED: 'badge-red' }

function priceLabel(p) {
    if (!p) return ''
    if (p.price === null || p.price === undefined) return t('my_plan.custom_price')
    if (Number(p.price) === 0) return t('my_plan.free')
    return t('my_plan.per_month', { price: Number(p.price).toLocaleString(locale.value), currency: currencyLabel(p.currency, locale.value) })
}

function fmtDate(iso) {
    if (!iso) return ''
    return new Date(iso + 'T00:00:00').toLocaleDateString(locale.value, { day: 'numeric', month: 'long', year: 'numeric' })
}

// "5 days left", "Ends today", "Ended 3 days ago" — or nothing without an end date.
const daysLine = computed(() => {
    const d = sub.value.days_left
    if (d === null || d === undefined) return ''
    if (d > 0) return t('my_plan.days_left', { n: d }, d)
    if (d === 0) return t('my_plan.ends_today')
    return t('my_plan.ended_ago', { n: -d }, -d)
})
const endingSoon = computed(() => sub.value.days_left !== null && sub.value.days_left !== undefined && sub.value.days_left <= 7)

// ---- Usage meters ------------------------------------------------------------
const meters = computed(() => (data.value?.usage || []).map((m) => {
    const unlimited = m.max === null || m.max === undefined
    const pct = unlimited || m.max === 0 ? 0 : Math.min(100, Math.round((m.used / m.max) * 100))
    const state = unlimited ? 'ok' : (m.used >= m.max ? 'full' : (pct >= 80 ? 'warn' : 'ok'))
    return { ...m, unlimited, pct, state }
}))
const anyFull = computed(() => meters.value.some((m) => m.state === 'full'))

// ---- Upgrade via WhatsApp ----------------------------------------------------
const restaurantName = computed(() => pickLocalized(auth.restaurant, 'name', locale.value) || '')
function waLink(target) {
    const number = data.value?.support_whatsapp
    if (!number) return null
    const msg = target
        ? t('my_plan.wa_switch', { name: restaurantName.value, plan: target })
        : t('my_plan.wa_upgrade', { name: restaurantName.value, plan: planName.value })
    return `https://wa.me/${number}?text=${encodeURIComponent(msg)}`
}

// Every feature any plan mentions, so the comparison cards line up row by row.
const comparedFeatures = computed(() => {
    const seen = new Set()
    for (const p of data.value?.plans || []) for (const k of p.feature_keys || []) seen.add(k)
    return [...seen]
})
const LIMIT_KEYS = ['items', 'categories', 'branches', 'staff']
const limitText = (v) => (v === null || v === undefined ? t('my_plan.unlimited') : Number(v).toLocaleString(locale.value))
</script>

<template>
    <div class="space-y-5">
        <div>
            <h1 class="page-title">{{ t('my_plan.title') }}</h1>
            <p class="page-sub">{{ t('my_plan.subtitle') }}</p>
        </div>

        <div v-if="loading" class="space-y-4" aria-busy="true">
            <div class="card plan-skel" style="height: 150px"></div>
            <div class="card plan-skel" style="height: 220px"></div>
        </div>

        <ErrorState v-else-if="failed" @retry="load" />

        <template v-else-if="data">
            <!-- Current plan -->
            <section class="card p-5 plan-current">
                <div class="plan-current-main">
                    <div class="plan-current-icon" aria-hidden="true"><i class="pi pi-star-fill"></i></div>
                    <div class="min-w-0">
                        <div class="plan-current-kicker">{{ t('my_plan.current') }}</div>
                        <div class="flex flex-wrap items-center gap-2">
                            <h2 class="plan-current-name">{{ planName }}</h2>
                            <span v-if="sub.status" class="badge" :class="STATUS_BADGE[sub.status]"><span class="dot"></span>{{ t('subscription_status.' + sub.status) }}</span>
                        </div>
                        <div v-if="plan" class="plan-current-price">{{ priceLabel(plan) }}</div>
                        <div class="plan-current-dates">
                            <span v-if="sub.start_date">{{ t('my_plan.started', { date: fmtDate(sub.start_date) }) }}</span>
                            <span v-if="sub.end_date">{{ t(sub.days_left < 0 ? 'my_plan.ended_on' : 'my_plan.ends_on', { date: fmtDate(sub.end_date) }) }}</span>
                            <span v-if="daysLine" class="plan-days" :class="{ soon: endingSoon }">{{ daysLine }}</span>
                        </div>
                    </div>
                </div>
                <a v-if="waLink()" :href="waLink()" target="_blank" rel="noopener noreferrer" class="btn btn-accent">
                    <i class="pi pi-whatsapp" aria-hidden="true"></i>{{ t(sub.status === 'EXPIRED' ? 'my_plan.renew' : 'my_plan.upgrade') }}
                </a>
            </section>

            <!-- Usage -->
            <section class="card p-5">
                <div class="flex flex-wrap items-baseline justify-between gap-2 mb-4">
                    <h2 class="h-card">{{ t('my_plan.usage_title') }}</h2>
                    <span v-if="anyFull" class="plan-full-note">{{ t('my_plan.limit_reached_note') }}</span>
                </div>
                <div class="meter-grid">
                    <div v-for="m in meters" :key="m.key" class="meter" :class="'meter-' + m.state">
                        <div class="meter-head">
                            <span class="meter-label">{{ t('my_plan.usage.' + m.key) }}</span>
                            <span class="meter-count">
                                <template v-if="m.unlimited">{{ t('my_plan.used_unlimited', { used: m.used.toLocaleString(locale) }) }}</template>
                                <template v-else>{{ t('my_plan.used_of', { used: m.used.toLocaleString(locale), max: m.max.toLocaleString(locale) }) }}</template>
                            </span>
                        </div>
                        <div class="meter-track" role="progressbar" :aria-valuenow="m.unlimited ? undefined : m.used"
                            :aria-valuemin="0" :aria-valuemax="m.unlimited ? undefined : m.max" :aria-label="t('my_plan.usage.' + m.key)">
                            <div class="meter-fill" :style="{ width: (m.unlimited ? 100 : m.pct) + '%' }"></div>
                        </div>
                        <div v-if="m.state === 'full'" class="meter-note">{{ t('my_plan.limit_reached') }}</div>
                    </div>
                </div>
            </section>

            <!-- What's switched on -->
            <section v-if="data.features?.length" class="card p-5">
                <h2 class="h-card mb-3">{{ t('my_plan.included_title') }}</h2>
                <ul class="feature-chips">
                    <li v-for="f in data.features" :key="f"><i class="pi pi-check" aria-hidden="true"></i>{{ t('feature.' + f) }}</li>
                </ul>
            </section>

            <!-- Compare plans -->
            <section v-if="data.plans?.length" class="space-y-3">
                <h2 class="h-card">{{ t('my_plan.compare_title') }}</h2>
                <div class="compare-grid">
                    <article v-for="p in data.plans" :key="p.id" class="card compare-card" :class="{ current: p.current, recommended: p.recommended }">
                        <div class="compare-head">
                            <div class="flex flex-wrap items-center gap-2">
                                <h3 class="compare-name">{{ p.name }}</h3>
                                <span v-if="p.current" class="badge badge-green">{{ t('my_plan.your_plan') }}</span>
                                <span v-else-if="p.recommended" class="badge badge-amber">{{ t('my_plan.recommended') }}</span>
                            </div>
                            <div class="compare-price">{{ priceLabel(p) }}</div>
                        </div>
                        <ul class="compare-limits">
                            <li v-for="k in LIMIT_KEYS" :key="k">
                                <span>{{ t('my_plan.usage.' + k) }}</span><strong>{{ limitText(p.limits[k]) }}</strong>
                            </li>
                        </ul>
                        <ul class="compare-features">
                            <li v-for="f in comparedFeatures" :key="f" :class="{ off: !p.feature_keys.includes(f) }">
                                <i :class="p.feature_keys.includes(f) ? 'pi pi-check' : 'pi pi-minus'" aria-hidden="true"></i>
                                <span>{{ t('feature.' + f) }}</span>
                            </li>
                        </ul>
                        <a v-if="!p.current && waLink(p.name)" :href="waLink(p.name)" target="_blank" rel="noopener noreferrer"
                            class="btn compare-cta" :class="p.recommended ? 'btn-accent' : 'btn-ghost'">
                            {{ t('my_plan.ask_for', { plan: p.name }) }}
                        </a>
                    </article>
                </div>
                <p v-if="!data.support_whatsapp" class="text-sm" style="color:var(--muted)">{{ t('my_plan.no_contact') }}</p>
            </section>
        </template>
    </div>
</template>

<style scoped>
.plan-skel { background: var(--page); animation: plan-pulse 1.2s ease-in-out infinite; }
@keyframes plan-pulse { 50% { opacity: .55; } }

.plan-current { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: 16px; }
.plan-current-main { display: flex; align-items: flex-start; gap: 14px; min-width: 0; }
.plan-current-icon { width: 48px; height: 48px; flex: none; border-radius: 14px; display: grid; place-items: center;
    background: var(--accent-soft); color: var(--accent); font-size: 20px; }
.plan-current-kicker { font-size: 12px; color: var(--muted); }
.plan-current-name { font-family: var(--font-display); font-size: 22px; font-weight: 700; color: var(--ink); }
.plan-current-price { font-size: 14px; font-weight: 600; color: var(--body); margin-top: 2px; }
.plan-current-dates { display: flex; flex-wrap: wrap; gap: 4px 14px; margin-top: 6px; font-size: 13px; color: var(--muted); }
.plan-days { font-weight: 600; color: var(--body); }
.plan-days.soon { color: #c0392b; }

.meter-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 18px 24px; }
.meter-head { display: flex; justify-content: space-between; gap: 8px; font-size: 13.5px; margin-bottom: 7px; }
.meter-label { font-weight: 600; color: var(--ink); }
.meter-count { color: var(--muted); white-space: nowrap; }
.meter-track { height: 8px; border-radius: 6px; background: var(--line); overflow: hidden; }
.meter-fill { height: 100%; border-radius: 6px; background: var(--green); transition: width .3s ease; }
.meter-ok .meter-fill { background: var(--green); }
.meter-warn .meter-fill { background: var(--amber, #e0a100); }
.meter-full .meter-fill { background: #d83a2a; }
.meter-full .meter-count { color: #c0392b; font-weight: 600; }
.meter-note { font-size: 12px; color: #c0392b; margin-top: 5px; }
.plan-full-note { font-size: 13px; color: #c0392b; }

.feature-chips { display: flex; flex-wrap: wrap; gap: 8px; }
.feature-chips li { display: inline-flex; align-items: center; gap: 6px; font-size: 13px; padding: 5px 11px;
    border-radius: 20px; background: var(--green-soft); color: var(--green); font-weight: 600; }

.compare-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); gap: 14px; }
.compare-card { display: flex; flex-direction: column; gap: 14px; padding: 18px; }
.compare-card.current { border-color: var(--green); box-shadow: 0 0 0 1px var(--green) inset; }
.compare-card.recommended:not(.current) { border-color: var(--accent); }
.compare-name { font-family: var(--font-display); font-size: 17px; font-weight: 700; color: var(--ink); }
.compare-price { font-size: 15px; font-weight: 600; color: var(--body); margin-top: 4px; }
.compare-limits { display: flex; flex-direction: column; gap: 6px; padding-bottom: 12px; border-bottom: 1px solid var(--line); }
.compare-limits li { display: flex; justify-content: space-between; gap: 8px; font-size: 13px; color: var(--muted); }
.compare-limits strong { color: var(--ink); font-weight: 600; }
.compare-features { display: flex; flex-direction: column; gap: 6px; flex: 1; }
.compare-features li { display: flex; align-items: center; gap: 8px; font-size: 13px; color: var(--body); }
.compare-features li .pi-check { color: var(--green); }
.compare-features li.off { color: var(--muted); }
.compare-features li.off span { text-decoration: line-through; text-decoration-color: var(--line); }
.compare-cta { justify-content: center; }
</style>
