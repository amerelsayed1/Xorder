<script setup>
import { computed, onMounted, onUnmounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRouter } from 'vue-router'
import SakaiLayout from '@xorder/ui/SakaiLayout.vue'
import { setLocale } from '@xorder/ui/i18n'
import api from '@xorder/api-client/api.js'
import { useAuth } from '@xorder/api-client/auth.js'
import { localizedInitial, pickLocalized } from '@xorder/ui/localize.js'
import { registerPush } from '../../lib/push.js'
import { useRealtime } from '../../stores/realtime.js'
import NotificationBell from '../../components/NotificationBell.vue'
import FullscreenToggle from '../../components/FullscreenToggle.vue'
import { buildDashboardNav } from './nav.config.js'
import { daysUntil, todayIn, ENDING_SOON_DAYS } from '../../lib/subscription.js'

const auth = useAuth()
const router = useRouter()
const { t, locale } = useI18n()
const r = computed(() => auth.restaurant)
const rt = useRealtime()

// Bilingual restaurants get a language toggle so staff can switch AR/EN
// themselves. Single-language restaurants are locked to the language the Super
// Admin configured. For bilingual ones we only seed the default on first visit
// (nothing saved yet) and otherwise respect the staff's saved choice.
const bilingual = computed(() => r.value?.bilingual !== false)
watch(() => r.value, (rest) => {
    if (!rest) return
    if (rest.bilingual === false) {
        setLocale(rest.default_language)
    } else if (!localStorage.getItem('locale')) {
        setLocale(rest.default_language || 'ar')
    }
}, { immediate: true })

const title = computed(() => pickLocalized(r.value, 'name', locale.value) || t('admin.restaurant'))
const mark = computed(() => localizedInitial(r.value, 'name', locale.value, 'R'))
const logo = computed(() => r.value?.logo_url || '')
const role = computed(() => auth.isRestaurantAdmin ? t('roles.restaurant_admin') : t('roles.restaurant_staff'))

// New-order / bill-request alerts. Counts now come from the shared realtime
// store's single consolidated /pulse poll (one request, ETag-gated); this layout
// only reacts to a rise: play the order sound, show a toast, badge the tab
// title, and (if the tab is backgrounded) fire a system notification — so a busy
// kitchen notices.
const newOrders = computed(() => rt.newOrders)
const newRequests = computed(() => rt.newRequests)
const pendingOrders = computed(() => rt.pendingOrders)
// What staff must look at: new orders plus WhatsApp orders awaiting a decision.
const attention = computed(() => newOrders.value + pendingOrders.value)
const prevCount = ref(null) // null until the first poll — never alert on load
const prevRequests = ref(null)
const prevPending = ref(null)
const toast = ref(null)
let toastTimer, alarm, offTick
let notifyReady = false
const baseTitle = document.title

// Fired on every pulse that observed a change. A null count means the plan
// doesn't have that feature, so it's skipped and never alerts.
function onPulse(d) {
    if (d.new_orders != null) {
        if (prevCount.value !== null && d.new_orders > prevCount.value) announce(d.new_orders - prevCount.value, 'order')
        prevCount.value = d.new_orders
    }
    if (d.pending_orders != null) {
        if (prevPending.value !== null && d.pending_orders > prevPending.value) announce(d.pending_orders - prevPending.value, 'order')
        prevPending.value = d.pending_orders
    }
    if (d.new_requests != null) {
        if (prevRequests.value !== null && d.new_requests > prevRequests.value) announce(d.new_requests - prevRequests.value, 'request')
        prevRequests.value = d.new_requests
    }
}

// The order sound — a real audio file. Autoplay needs one prior user gesture,
// which the first interaction on the dashboard provides (see armAlerts).
function ensureAlarm() {
    if (!alarm) { alarm = new Audio('/new-order-v2.mp3'); alarm.preload = 'auto' }
    return alarm
}
function playSound() {
    try { const a = ensureAlarm(); a.currentTime = 0; return Promise.resolve(a.play()) }
    catch (err) { return Promise.reject(err) }
}
function requestNotify() {
    if (!('Notification' in window)) return
    if (Notification.permission === 'granted') notifyReady = true
    else if (Notification.permission === 'default') Notification.requestPermission().then((p) => { notifyReady = p === 'granted' })
}

// kind: 'order' | 'request' — drives the toast/notification copy and where a
// click lands, so a new bill request alerts as loudly as a new order.
function announce(arrived, kind = 'order') {
    playSound().catch(() => {})
    toast.value = { arrived, kind }
    clearTimeout(toastTimer)
    toastTimer = setTimeout(() => (toast.value = null), 7000)
    if (notifyReady && document.visibilityState !== 'visible') {
        try {
            const title = kind === 'request' ? t('req.new_toast', { n: arrived }) : t('orders.new_toast', { n: arrived })
            const body = kind === 'request' ? t('req.new_toast_sub') : t('orders.new_toast_sub')
            const n = new Notification(title, { body, tag: 'xorder-' + kind, renotify: true })
            n.onclick = () => { window.focus(); kind === 'request' ? goRequests() : goOrders(); n.close() }
        } catch (err) { /* ignore */ }
    }
}

// A foreground FCM push (tab focused). Only new orders / bill requests warrant
// the loud alarm + toast; reviews and subscription notices also arrive as
// pushes, but they must NOT ring the new-order sound — they surface silently
// through the notification bell instead (the pulse keeps its unread count).
function onForegroundPush(payload) {
    const type = payload?.data?.type || ''
    if (type !== 'order.created' && type !== 'bill_request.created') return
    const kind = type === 'bill_request.created' ? 'request' : 'order'
    playSound().catch(() => {})
    toast.value = { arrived: 1, kind }
    clearTimeout(toastTimer)
    toastTimer = setTimeout(() => (toast.value = null), 7000)
}

// Unlock audio (browsers gate autoplay), request notification permission, and
// register this device for push — all on the first interaction on the page.
function armAlerts() {
    const a = ensureAlarm()
    a.muted = true
    Promise.resolve(a.play()).then(() => { a.pause(); a.currentTime = 0; a.muted = false }).catch(() => { a.muted = false })
    requestNotify()
    registerPush(onForegroundPush).catch(() => {})
}

function goOrders() {
    toast.value = null
    router.push({ name: 'dashboard.orders' })
}

function goRequests() {
    toast.value = null
    router.push({ name: 'dashboard.home' })
}

// Tab-title badge, e.g. "(3) Mahsoub" — cleared when the count is zero.
watch(attention, (n) => {
    document.title = n > 0 ? `(${n}) ${baseTitle}` : baseTitle
})

onMounted(() => {
    if ('Notification' in window) notifyReady = Notification.permission === 'granted'
    loadSupportWhatsapp()
    offTick = rt.onTick(onPulse)
    rt.start(10_000)
    window.addEventListener('pointerdown', armAlerts, { once: true })
    window.addEventListener('keydown', armAlerts, { once: true })
    window.addEventListener('xorder:read-only-blocked', onReadOnlyBlocked)
})
onUnmounted(() => {
    offTick?.()
    rt.stop()
    clearTimeout(toastTimer)
    clearTimeout(readOnlyTimer)
    window.removeEventListener('pointerdown', armAlerts)
    window.removeEventListener('keydown', armAlerts)
    window.removeEventListener('xorder:read-only-blocked', onReadOnlyBlocked)
    document.title = baseTitle
})

// Expired-subscription banner. The public menu stays live (by design), but the
// owner should know editing is blocked until they renew.
const isExpired = computed(() => r.value?.subscription_status === 'EXPIRED')
const expiredDate = computed(() => r.value?.subscription_end_date || null)

// Xorder's own WhatsApp (from the landing CMS) so an expired owner can reach us
// to renew in one tap. Fetched only when expired; the button hides if unset.
const supportWa = ref('')
const waLink = computed(() => {
    if (!supportWa.value) return null
    const name = pickLocalized(r.value, 'name', locale.value) || ''
    const msg = t('subscription.whatsapp_message', { name })
    return `https://wa.me/${supportWa.value}?text=${encodeURIComponent(msg)}`
})
// ---- Plan badge + trial / ending-soon banner -----------------------------
// Both are for whoever holds settings.view (the owner): a cook gains nothing
// from a countdown they cannot act on. There is no "My plan" page any more;
// the banner's WhatsApp button is how an owner reaches Xorder to upgrade.
const canSeePlan = computed(() => auth.can('settings.view'))
const subStatus = computed(() => r.value?.subscription_status || null)
const daysLeft = computed(() => daysUntil(r.value?.subscription_end_date, r.value?.timezone))
const planBadge = computed(() => {
    if (!canSeePlan.value || !r.value) return null
    const isTrial = subStatus.value === 'TRIAL'
    return {
        name: r.value.subscription_plan || t('my_plan.no_plan'),
        isTrial,
        // The countdown rides the badge only where it matters: a trial, or a
        // paid plan inside its last week.
        days: (isTrial || (daysLeft.value !== null && daysLeft.value <= ENDING_SOON_DAYS)) && daysLeft.value !== null && daysLeft.value >= 0
            ? daysLeft.value : null,
        tone: isExpired.value || subStatus.value === 'SUSPENDED' ? 'bad'
            : (daysLeft.value !== null && daysLeft.value <= 3 ? 'urgent' : (isTrial ? 'trial' : 'ok')),
    }
})

// Dismissing the banner hides it for the rest of the restaurant's day; it is
// back tomorrow, because tomorrow is a day closer. A per-browser convenience,
// so storage that throws (private window, blocked site data) only means it
// cannot be dismissed.
const BANNER_KEY = 'xorder.plan_banner_dismissed'
const bannerDismissedOn = ref((() => { try { return localStorage.getItem(BANNER_KEY) || '' } catch { return '' } })())
function dismissPlanBanner() {
    bannerDismissedOn.value = todayIn(r.value?.timezone)
    try { localStorage.setItem(BANNER_KEY, bannerDismissedOn.value) } catch { /* storage unavailable */ }
}
const showPlanBanner = computed(() => {
    if (!canSeePlan.value || isExpired.value) return false
    if (bannerDismissedOn.value === todayIn(r.value?.timezone)) return false
    if (subStatus.value === 'TRIAL') return daysLeft.value === null || daysLeft.value >= 0
    return subStatus.value === 'ACTIVE' && daysLeft.value !== null && daysLeft.value >= 0 && daysLeft.value <= ENDING_SOON_DAYS
})
const planBannerText = computed(() => {
    const plan = r.value?.subscription_plan || ''
    const d = daysLeft.value
    if (subStatus.value === 'TRIAL') {
        if (d === null) return t('plan_banner.trial_open', { plan })
        return d === 0 ? t('plan_banner.trial_today', { plan }) : t('plan_banner.trial_days', { plan, n: d }, d)
    }
    return d === 0 ? t('plan_banner.ends_today', { plan }) : t('plan_banner.ends_days', { plan, n: d }, d)
})
const planWaLink = computed(() => {
    if (!supportWa.value) return null
    const name = pickLocalized(r.value, 'name', locale.value) || ''
    const msg = t('my_plan.wa_upgrade', { name, plan: r.value?.subscription_plan || '' })
    return `https://wa.me/${supportWa.value}?text=${encodeURIComponent(msg)}`
})

async function loadSupportWhatsapp() {
    // Wanted by the expired banner and by the trial / ending-soon banner.
    if (!isExpired.value && !showPlanBanner.value) return
    try {
        const { data } = await api.get('api/public/landing-content')
        supportWa.value = String(data.data?.whatsapp?.number || '').replace(/\D/g, '')
    } catch { /* no button if the CMS number can't be read */ }
}

// A brief toast whenever the API rejects a write because the dashboard is
// read-only — a safety net for any control that slips past the disabled state.
const readOnlyFlash = ref(false)
let readOnlyTimer
function onReadOnlyBlocked() {
    readOnlyFlash.value = true
    clearTimeout(readOnlyTimer)
    readOnlyTimer = setTimeout(() => (readOnlyFlash.value = false), 6000)
}

// Build the grouped sidebar from the declarative schema. Two gates decide which
// children (and therefore which groups) appear: the restaurant's plan feature
// flags, and the signed-in user's own capabilities — so a cashier's sidebar
// carries only what their role can actually open. The live badge counts are
// stamped in from the shared realtime store, which owns the single pulse poll.
const nav = computed(() => buildDashboardNav({
    features: r.value?.features || [],
    can: auth.can,
    badges: { orders: attention.value, requests: newRequests.value },
}))
</script>

<template>
    <SakaiLayout :title="title" :role="role" :mark="mark" :logo="logo" :nav="nav" :hide-lang-toggle="!bilingual" searchable>
        <template #topbar-actions>
            <div v-if="planBadge" class="plan-badge" :class="'plan-badge--' + planBadge.tone" role="img"
                :title="t('nav.my_plan')" :aria-label="t('nav.my_plan') + ': ' + planBadge.name">
                <i class="pi pi-star-fill" aria-hidden="true"></i>
                <span class="plan-badge-name">{{ planBadge.name }}</span>
                <span v-if="planBadge.days !== null" class="plan-badge-days">
                    <span class="topbar-wide-only">{{ t('plan_banner.badge_days', { n: planBadge.days }) }}</span>
                    <!-- Phones: just the number; the banner spells it out. -->
                    <span class="topbar-narrow-only">{{ planBadge.days }}</span>
                </span>
            </div>
            <!-- Phones get no fullscreen (iOS Safari has none at all), which also
                 leaves the narrow top bar room for the plan badge. -->
            <span class="topbar-wide-only"><FullscreenToggle /></span>
            <NotificationBell />
        </template>
        <template #banner>
            <div v-if="showPlanBanner" class="plan-banner" :class="{ urgent: daysLeft !== null && daysLeft <= 3 }" role="status">
                <i class="pi pi-star-fill plan-banner-icon" aria-hidden="true"></i>
                <span class="plan-banner-text">{{ planBannerText }}</span>
                <a v-if="planWaLink" :href="planWaLink" target="_blank" rel="noopener noreferrer" class="plan-banner-btn plan-banner-btn--wa">
                    <i class="pi pi-whatsapp" aria-hidden="true"></i>{{ t('my_plan.upgrade') }}
                </a>
                <button type="button" class="plan-banner-close" :aria-label="t('plan_banner.dismiss')" :title="t('plan_banner.dismiss')" @click="dismissPlanBanner">
                    <i class="pi pi-times" aria-hidden="true"></i>
                </button>
            </div>
            <div v-if="isExpired" class="sub-banner" role="alert">
                <i class="pi pi-exclamation-triangle sub-banner-icon" aria-hidden="true"></i>
                <div class="sub-banner-text">
                    <strong>{{ t('subscription.expired_title') }}</strong>
                    <span>{{ expiredDate ? t('subscription.expired_body_dated', { date: expiredDate }) : t('subscription.expired_body') }}</span>
                </div>
                <a v-if="waLink" class="sub-banner-wa" :href="waLink" target="_blank" rel="noopener noreferrer">
                    <i class="pi pi-whatsapp" aria-hidden="true"></i>
                    <span>{{ t('subscription.contact_whatsapp') }}</span>
                </a>
            </div>
        </template>
    </SakaiLayout>

    <!-- Read-only (subscription blocked a write) toast -->
    <Transition name="order-toast">
        <div v-if="readOnlyFlash" class="order-toast order-toast--warn">
            <i class="pi pi-lock" aria-hidden="true"></i>
            <span class="order-toast-text"><strong>{{ t('subscription.read_only_toast') }}</strong></span>
        </div>
    </Transition>

    <!-- New-order toast -->
    <Transition name="order-toast">
        <button v-if="toast" class="order-toast" @click="toast.kind === 'request' ? goRequests() : goOrders()">
            <span class="order-toast-dot"></span>
            <span class="order-toast-text">
                <strong>{{ toast.kind === 'request' ? t('req.new_toast', { n: toast.arrived }) : t('orders.new_toast', { n: toast.arrived }) }}</strong>
                <span>{{ toast.kind === 'request' ? t('req.new_toast_sub') : t('orders.new_toast_sub') }}</span>
            </span>
        </button>
    </Transition>
</template>

<style scoped>
.plan-badge { display: inline-flex; align-items: center; gap: 6px; height: 32px; padding: 0 11px; border-radius: 20px;
    font-size: 12.5px; font-weight: 600; text-decoration: none; white-space: nowrap; max-width: 220px;
    border: 1px solid var(--line); background: var(--card); color: var(--ink); }
.plan-badge i { font-size: 12px; color: var(--accent); }
.plan-badge-name { overflow: hidden; text-overflow: ellipsis; }
.plan-badge-days { font-weight: 700; padding-inline-start: 6px; border-inline-start: 1px solid currentColor; opacity: .9; }
.plan-badge--trial { background: #fef3c7; border-color: #fcd34d; color: #92400e; }
.plan-badge--urgent, .plan-badge--bad { background: #fdecea; border-color: #f5b5ae; color: #b42318; }
.plan-badge--urgent i, .plan-badge--bad i, .plan-badge--trial i { color: currentColor; }
.topbar-narrow-only { display: none; }
@media (max-width: 640px) { .topbar-wide-only { display: none; } .topbar-narrow-only { display: inline; } .plan-badge-name { display: none; } .plan-badge { padding: 0 9px; } .plan-badge-days { border: 0; padding: 0; } }

.plan-banner { display: flex; flex-wrap: wrap; align-items: center; gap: 10px 12px; margin-block-end: 20px;
    padding: 12px 14px 12px 18px; border-radius: 12px; background: #fff7e6; border: 1px solid #fcd34d; color: #92400e; }
.plan-banner.urgent { background: #fdecea; border-color: #f5b5ae; color: #b42318; }
.plan-banner-icon { font-size: 16px; flex: none; }
.plan-banner-text { flex: 1 1 260px; font-size: 14px; font-weight: 600; line-height: 1.45; }
.plan-banner-btn { display: inline-flex; align-items: center; gap: 6px; padding: 7px 13px; border-radius: 9px;
    font-size: 13px; font-weight: 600; text-decoration: none; background: #fff; color: inherit; border: 1px solid currentColor; }
.plan-banner-btn--wa { background: #25d366; border-color: #25d366; color: #fff; }
.plan-banner-close { display: grid; place-items: center; width: 30px; height: 30px; border-radius: 8px; border: 0;
    background: transparent; color: inherit; cursor: pointer; opacity: .7; }
.plan-banner-close:hover { opacity: 1; background: rgba(0, 0, 0, .05); }

.sub-banner {
    display: flex; align-items: center; flex-wrap: wrap; gap: 12px;
    margin-block-end: 20px; padding: 14px 18px; border-radius: 12px;
    background: #fef3c7; border: 1px solid #fcd34d; color: #92400e;
}
.sub-banner-icon { font-size: 20px; line-height: 1.4; flex: none; align-self: flex-start; }
.sub-banner-text { display: flex; flex-direction: column; gap: 2px; line-height: 1.4; flex: 1 1 240px; }
.sub-banner-text strong { font-size: 14px; font-weight: 700; }
.sub-banner-wa {
    margin-inline-start: auto; flex: none;
    display: inline-flex; align-items: center; gap: 8px;
    padding: 9px 16px; border-radius: 10px;
    background: #25d366; color: #fff; font-size: 13px; font-weight: 700;
    text-decoration: none; white-space: nowrap;
}
.sub-banner-wa:hover { background: #1ebe5b; }
.sub-banner-wa .pi { font-size: 16px; }
.sub-banner-text span { font-size: 13px; opacity: .95; }

.order-toast {
    position: fixed; inset-block-end: 22px; inset-inline: 0; margin-inline: auto;
    z-index: 60; width: max-content; max-width: 92vw;
    display: flex; align-items: center; gap: 12px; cursor: pointer;
    padding: 12px 18px; border-radius: 14px; border: none;
    background: var(--p-primary-color, #f89a06); color: #fff;
    box-shadow: 0 12px 34px rgba(80, 55, 15, .35);
    font: inherit; text-align: start;
}
.order-toast--warn { background: #92400e; cursor: default; }
.order-toast--warn .pi { font-size: 18px; }
.order-toast-dot { width: 10px; height: 10px; border-radius: 50%; background: #fff; flex: none; animation: order-pulse 1s infinite; }
.order-toast-text { display: flex; flex-direction: column; line-height: 1.3; }
.order-toast-text strong { font-size: 14px; font-weight: 700; }
.order-toast-text span { font-size: 12px; opacity: .9; }
@keyframes order-pulse { 0%, 100% { opacity: 1; } 50% { opacity: .35; } }
.order-toast-enter-active, .order-toast-leave-active { transition: transform .25s ease, opacity .25s ease; }
.order-toast-enter-from, .order-toast-leave-to { transform: translateY(16px); opacity: 0; }
</style>
