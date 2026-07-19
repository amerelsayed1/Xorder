<script setup>
import { computed, onMounted, onUnmounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRouter } from 'vue-router'
import SakaiLayout from '@xorder/ui/SakaiLayout.vue'
import api from '@xorder/api-client/api.js'
import { useAuth } from '@xorder/api-client/auth.js'
import { localizedInitial, pickLocalized } from '@xorder/ui/localize.js'
import { registerPush } from '../../lib/push.js'

const auth = useAuth()
const router = useRouter()
const { t, locale } = useI18n()
const r = computed(() => auth.restaurant)
const title = computed(() => pickLocalized(r.value, 'name', locale.value) || t('admin.restaurant'))
const mark = computed(() => localizedInitial(r.value, 'name', locale.value, 'R'))
const logo = computed(() => r.value?.logo_url || '')
const role = computed(() => t('roles.restaurant_admin'))

// New-order alerts: poll the unfulfilled-order count; when it rises, play a
// sound, show a toast, badge the tab title, and (if the tab is backgrounded)
// fire a system notification — so a busy kitchen notices without watching.
const newOrders = ref(0)
const prevCount = ref(null) // null until the first poll — never alert on load
const toast = ref(null)
const soundOn = ref(localStorage.getItem('xorder_sound') !== 'off')
let pollTimer, toastTimer, alarm
let notifyReady = false
const baseTitle = document.title

async function loadNewCount() {
    try {
        const { data } = await api.get('api/dashboard/orders/new-count')
        const count = data.data?.new_orders ?? 0
        if (prevCount.value !== null && count > prevCount.value) announce(count - prevCount.value)
        prevCount.value = count
        newOrders.value = count
    } catch (err) { /* keep the last known count */ }
}

// A two-tone beep synthesized once into a WAV blob and played through a plain
// <audio> element — more reliable across browsers than Web Audio oscillators,
// and loud enough for a kitchen. Autoplay still needs one prior gesture, which
// the sound button (and the first interaction) provides.
function beepUrl() {
    const sr = 44100
    const tone = (freq, dur) => {
        const n = Math.floor(sr * dur), out = new Float32Array(n)
        for (let i = 0; i < n; i++) {
            const s = i / sr
            const env = Math.min(1, s / 0.008) * Math.min(1, (dur - s) / 0.06)
            out[i] = Math.sin(2 * Math.PI * freq * s) * env * 0.6
        }
        return out
    }
    const gap = new Float32Array(Math.floor(sr * 0.04))
    const parts = [tone(988, 0.16), gap, tone(1319, 0.24)]
    const len = parts.reduce((a, p) => a + p.length, 0)
    const pcm = new Float32Array(len)
    let off = 0
    for (const p of parts) { pcm.set(p, off); off += p.length }
    const buf = new ArrayBuffer(44 + len * 2), dv = new DataView(buf)
    const ws = (o, str) => { for (let i = 0; i < str.length; i++) dv.setUint8(o + i, str.charCodeAt(i)) }
    ws(0, 'RIFF'); dv.setUint32(4, 36 + len * 2, true); ws(8, 'WAVE'); ws(12, 'fmt ')
    dv.setUint32(16, 16, true); dv.setUint16(20, 1, true); dv.setUint16(22, 1, true)
    dv.setUint32(24, sr, true); dv.setUint32(28, sr * 2, true); dv.setUint16(32, 2, true); dv.setUint16(34, 16, true)
    ws(36, 'data'); dv.setUint32(40, len * 2, true)
    for (let i = 0; i < len; i++) dv.setInt16(44 + i * 2, Math.max(-1, Math.min(1, pcm[i])) * 32767, true)
    return URL.createObjectURL(new Blob([buf], { type: 'audio/wav' }))
}
function ensureAlarm() {
    if (!alarm) { alarm = new Audio(beepUrl()); alarm.preload = 'auto' }
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

function announce(arrived) {
    if (soundOn.value) playSound().catch(() => {})
    toast.value = { arrived }
    clearTimeout(toastTimer)
    toastTimer = setTimeout(() => (toast.value = null), 7000)
    if (notifyReady && document.visibilityState !== 'visible') {
        try {
            const n = new Notification(t('orders.new_toast', { n: arrived }), {
                body: t('orders.new_toast_sub'), tag: 'xorder-order', renotify: true,
            })
            n.onclick = () => { window.focus(); goOrders(); n.close() }
        } catch (err) { /* ignore */ }
    }
}

// A foreground FCM push (tab focused) gets the same in-app treatment as a
// polled new order: sound + toast.
function onForegroundPush() {
    if (soundOn.value) playSound().catch(() => {})
    toast.value = { arrived: newOrders.value || 1 }
    clearTimeout(toastTimer)
    toastTimer = setTimeout(() => (toast.value = null), 7000)
}

// Unlock audio (browsers need a gesture) + notification permission + register
// this device for push, all on the first interaction.
function armAlerts() {
    const a = ensureAlarm()
    a.muted = true
    Promise.resolve(a.play()).then(() => { a.pause(); a.currentTime = 0; a.muted = false }).catch(() => { a.muted = false })
    requestNotify()
    registerPush(onForegroundPush).catch(() => {})
}

// Explicit sound button: a guaranteed gesture → play a test beep + arm + toggle.
function toggleSound() {
    soundOn.value = !soundOn.value
    localStorage.setItem('xorder_sound', soundOn.value ? 'on' : 'off')
    if (soundOn.value) { requestNotify(); playSound().catch(() => {}); registerPush(onForegroundPush).catch(() => {}) }
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

    <!-- Order-sound toggle / tester (click is a gesture, so it always plays) -->
    <button class="sound-toggle" :class="{ off: !soundOn }" @click="toggleSound"
        :title="soundOn ? t('orders.sound_on') : t('orders.sound_off')"
        :aria-label="soundOn ? t('orders.sound_on') : t('orders.sound_off')">
        <i :class="soundOn ? 'pi pi-volume-up' : 'pi pi-volume-off'"></i>
    </button>

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

.sound-toggle {
    position: fixed; inset-block-end: 20px; inset-inline-start: 20px; z-index: 55;
    width: 44px; height: 44px; border-radius: 50%; cursor: pointer;
    display: grid; place-items: center; font-size: 18px;
    background: var(--p-primary-color, #f89a06); color: #fff; border: none;
    box-shadow: 0 8px 22px rgba(80, 55, 15, .3);
    transition: transform .15s, background .15s;
}
.sound-toggle:hover { transform: scale(1.06); }
.sound-toggle:active { transform: scale(.95); }
.sound-toggle.off { background: var(--p-surface-400, #9c968c); }
</style>
