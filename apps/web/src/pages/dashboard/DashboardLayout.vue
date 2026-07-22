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
import { buildDashboardNav } from './nav.config.js'

const auth = useAuth()
const router = useRouter()
const { t, locale } = useI18n()
const r = computed(() => auth.restaurant)

// The restaurant dashboard follows the language the Super Admin configured for
// the restaurant — staff can't switch it (the toggle is hidden below). Apply it
// as soon as the restaurant context is known.
watch(() => r.value?.default_language, (lang) => { if (lang) setLocale(lang) }, { immediate: true })

const title = computed(() => pickLocalized(r.value, 'name', locale.value) || t('admin.restaurant'))
const mark = computed(() => localizedInitial(r.value, 'name', locale.value, 'R'))
const logo = computed(() => r.value?.logo_url || '')
const role = computed(() => t('roles.restaurant_admin'))

// New-order alerts: poll the unfulfilled-order count; when it rises, play the
// order sound, show a toast, badge the tab title, and (if the tab is
// backgrounded) fire a system notification — so a busy kitchen notices.
const newOrders = ref(0)
const newRequests = ref(0)
const prevCount = ref(null) // null until the first poll — never alert on load
const prevRequests = ref(null)
const toast = ref(null)
let pollTimer, toastTimer, alarm
let notifyReady = false
const baseTitle = document.title

// New-order badge. Only polled when system ordering is enabled — WhatsApp-only
// plans have no durable order queue (the endpoint would 403).
async function loadNewCount() {
    if (!hasSystemOrdering.value) return
    try {
        const { data } = await api.get('api/dashboard/orders/new-count')
        const count = data.data?.new_orders ?? 0
        if (prevCount.value !== null && count > prevCount.value) announce(count - prevCount.value)
        prevCount.value = count
        newOrders.value = count
    } catch (err) { /* keep the last known count */ }
}

// Live bill-request badge. Only polled when the feature is enabled.
async function loadRequestCount() {
    if (!hasBillRequests.value) return
    try {
        const { data } = await api.get('api/dashboard/bill-requests/new-count')
        const count = data.count ?? 0
        if (prevRequests.value !== null && count > prevRequests.value) announce(count - prevRequests.value, 'request')
        prevRequests.value = count
        newRequests.value = count
    } catch (err) { /* keep the last known count */ }
}

// The order sound — a real audio file. Autoplay needs one prior user gesture,
// which the first interaction on the dashboard provides (see armAlerts).
function ensureAlarm() {
    if (!alarm) { alarm = new Audio('/new-order.mp3'); alarm.preload = 'auto' }
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

// A foreground FCM push (tab focused) → same in-app treatment: sound + toast.
function onForegroundPush() {
    playSound().catch(() => {})
    toast.value = { arrived: newOrders.value || 1 }
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
    router.push({ name: 'dashboard.requests' })
}

// Tab-title badge, e.g. "(3) Mahsoub" — cleared when the count is zero.
watch(newOrders, (n) => {
    document.title = n > 0 ? `(${n}) ${baseTitle}` : baseTitle
})

onMounted(() => {
    if ('Notification' in window) notifyReady = Notification.permission === 'granted'
    loadSupportWhatsapp()
    loadNewCount()
    loadRequestCount()
    pollTimer = setInterval(() => { loadNewCount(); loadRequestCount() }, 10_000)
    window.addEventListener('pointerdown', armAlerts, { once: true })
    window.addEventListener('keydown', armAlerts, { once: true })
    window.addEventListener('xorder:read-only-blocked', onReadOnlyBlocked)
})
onUnmounted(() => {
    clearInterval(pollTimer)
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
async function loadSupportWhatsapp() {
    if (!isExpired.value) return
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

const hasBillRequests = computed(() => (r.value?.features || []).includes('bill_requests'))
// System order queue exists unless the restaurant is WhatsApp-only.
const hasSystemOrdering = computed(() => (r.value?.ordering_mode || 'both') !== 'whatsapp')

// Build the grouped sidebar from the declarative schema. Feature flags gate
// which children (and therefore which groups) appear; the live badge counts are
// stamped in from here so polling stays owned by this layout.
const nav = computed(() => buildDashboardNav({
    features: r.value?.features || [],
    badges: { orders: newOrders.value, requests: newRequests.value, live: newOrders.value + newRequests.value },
}))
</script>

<template>
    <SakaiLayout :title="title" :role="role" :mark="mark" :logo="logo" :nav="nav" :hide-lang-toggle="true">
        <template #banner>
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
