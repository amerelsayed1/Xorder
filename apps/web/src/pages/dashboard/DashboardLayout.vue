<script setup>
import { computed, onMounted, onUnmounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRouter } from 'vue-router'
import SakaiLayout from '@xorder/ui/SakaiLayout.vue'
import api from '@xorder/api-client/api.js'
import { useAuth } from '@xorder/api-client/auth.js'
import { localizedInitial, pickLocalized } from '@xorder/ui/localize.js'

const auth = useAuth()
const router = useRouter()
const { t, locale } = useI18n()
const r = computed(() => auth.restaurant)
const title = computed(() => pickLocalized(r.value, 'name', locale.value) || t('admin.restaurant'))
const mark = computed(() => localizedInitial(r.value, 'name', locale.value, 'R'))
const logo = computed(() => r.value?.logo_url || '')
const role = computed(() => t('roles.restaurant_admin'))

// New-order alerts: poll the unfulfilled-order count; when it rises, chime,
// show a toast, and badge the browser-tab title — so a busy kitchen notices a
// new order without watching the screen. In-app only (while the tab is open).
const newOrders = ref(0)
const prevCount = ref(null) // null until the first poll — never alert on load
const toast = ref(null)
let pollTimer, toastTimer, audioCtx
const baseTitle = document.title

async function loadNewCount() {
    try {
        const { data } = await api.get('api/dashboard/orders/new-count')
        const count = data.data?.new_orders ?? 0
        if (prevCount.value !== null && count > prevCount.value) {
            announce(count - prevCount.value)
        }
        prevCount.value = count
        newOrders.value = count
    } catch (err) { /* keep the last known count */ }
}

let notifyReady = false

function announce(arrived) {
    chime()
    toast.value = { arrived }
    clearTimeout(toastTimer)
    toastTimer = setTimeout(() => (toast.value = null), 7000)
    // When the dashboard tab is in the background, a system notification (with
    // its own OS sound) is what actually reaches the user.
    if (notifyReady && document.visibilityState !== 'visible') {
        try {
            const n = new Notification(t('orders.new_toast', { n: arrived }), {
                body: t('orders.new_toast_sub'), tag: 'xorder-order', renotify: true,
            })
            n.onclick = () => { window.focus(); goOrders(); n.close() }
        } catch (err) { /* ignore */ }
    }
}

// One soft sine note via Web Audio — no asset to ship.
function blip(freq, when = 0) {
    if (!audioCtx) return
    const t0 = audioCtx.currentTime + when
    const o = audioCtx.createOscillator()
    const g = audioCtx.createGain()
    o.type = 'sine'
    o.frequency.value = freq
    g.gain.setValueAtTime(0.0001, t0)
    g.gain.exponentialRampToValueAtTime(0.22, t0 + 0.02)
    g.gain.exponentialRampToValueAtTime(0.0001, t0 + 0.26)
    o.connect(g); g.connect(audioCtx.destination)
    o.start(t0); o.stop(t0 + 0.28)
}
function chime() {
    try {
        audioCtx = audioCtx || new (window.AudioContext || window.webkitAudioContext)()
        if (audioCtx.state === 'suspended') audioCtx.resume()
        blip(880, 0)
        blip(1174, 0.18)
    } catch (err) { /* audio unavailable — toast + title still fire */ }
}

// Browsers gate audio and notifications behind a user gesture, so arm both on
// the first interaction. A short confirmation blip proves sound is working.
function armAlerts() {
    try {
        audioCtx = audioCtx || new (window.AudioContext || window.webkitAudioContext)()
        audioCtx.resume().then(() => blip(1320)).catch(() => {})
    } catch (err) { /* ignore */ }
    if ('Notification' in window) {
        if (Notification.permission === 'granted') {
            notifyReady = true
        } else if (Notification.permission === 'default') {
            Notification.requestPermission().then((p) => { notifyReady = p === 'granted' })
        }
    }
}

function goOrders() {
    toast.value = null
    router.push({ name: 'dashboard.orders' })
}

// Tab-title badge, e.g. "(3) Mahsoub" — cleared when the count is zero.
watch(newOrders, (n) => {
    document.title = n > 0 ? `(${n}) ${baseTitle}` : baseTitle
})

onMounted(() => {
    if ('Notification' in window) notifyReady = Notification.permission === 'granted'
    loadNewCount()
    pollTimer = setInterval(loadNewCount, 20_000)
    window.addEventListener('pointerdown', armAlerts, { once: true })
    window.addEventListener('keydown', armAlerts, { once: true })
})
onUnmounted(() => {
    clearInterval(pollTimer)
    clearTimeout(toastTimer)
    window.removeEventListener('pointerdown', armAlerts)
    window.removeEventListener('keydown', armAlerts)
    document.title = baseTitle
})

const nav = computed(() => [
    { to: { name: 'dashboard.home' }, labelKey: 'nav.dashboard', icon: 'pi pi-th-large', end: true },
    { to: { name: 'dashboard.orders' }, labelKey: 'nav.orders', icon: 'pi pi-shopping-bag', badge: newOrders.value },
    { to: { name: 'dashboard.customers' }, labelKey: 'nav.customers', icon: 'pi pi-users' },
    { to: { name: 'dashboard.insights' }, labelKey: 'nav.insights', icon: 'pi pi-chart-bar' },
    { to: { name: 'dashboard.items' }, labelKey: 'nav.items', icon: 'pi pi-list' },
    { to: { name: 'dashboard.categories' }, labelKey: 'nav.categories', icon: 'pi pi-tags' },
    { to: { name: 'dashboard.combos' }, labelKey: 'nav.combos', icon: 'pi pi-gift' },
    { to: { name: 'dashboard.qr' }, labelKey: 'nav.qr', icon: 'pi pi-qrcode' },
    { to: { name: 'dashboard.branches' }, labelKey: 'nav.branches', icon: 'pi pi-map-marker' },
    { to: { name: 'dashboard.profile' }, labelKey: 'nav.profile', icon: 'pi pi-cog' },
])
</script>

<template>
    <SakaiLayout :title="title" :role="role" :mark="mark" :logo="logo" :nav="nav" />

    <!-- New-order toast -->
    <Transition name="order-toast">
        <button v-if="toast" class="order-toast" @click="goOrders">
            <span class="order-toast-dot"></span>
            <span class="order-toast-text">
                <strong>{{ t('orders.new_toast', { n: toast.arrived }) }}</strong>
                <span>{{ t('orders.new_toast_sub') }}</span>
            </span>
        </button>
    </Transition>
</template>

<style scoped>
.order-toast {
    position: fixed; inset-block-end: 22px; inset-inline: 0; margin-inline: auto;
    z-index: 60; width: max-content; max-width: 92vw;
    display: flex; align-items: center; gap: 12px; cursor: pointer;
    padding: 12px 18px; border-radius: 14px; border: none;
    background: var(--p-primary-color, #f89a06); color: #fff;
    box-shadow: 0 12px 34px rgba(80, 55, 15, .35);
    font: inherit; text-align: start;
}
.order-toast-dot { width: 10px; height: 10px; border-radius: 50%; background: #fff; flex: none; animation: order-pulse 1s infinite; }
.order-toast-text { display: flex; flex-direction: column; line-height: 1.3; }
.order-toast-text strong { font-size: 14px; font-weight: 700; }
.order-toast-text span { font-size: 12px; opacity: .9; }
@keyframes order-pulse { 0%, 100% { opacity: 1; } 50% { opacity: .35; } }
.order-toast-enter-active, .order-toast-leave-active { transition: transform .25s ease, opacity .25s ease; }
.order-toast-enter-from, .order-toast-leave-to { transform: translateY(16px); opacity: 0; }
</style>
