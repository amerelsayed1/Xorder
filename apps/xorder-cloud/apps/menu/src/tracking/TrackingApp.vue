<script setup>
import { ref, computed, watch, onMounted } from 'vue'
import { useLocale } from '../composables/useLocale'
import { useOrderTracking } from '../composables/useOrderTracking'
import { readableOn } from '../lib/contrast'

// Guest paging S3: what a diner sees after scanning the QR on their receipt.
// Their order number, and the order's state. Deliberately not the menu: no
// categories, no cart, no prices, and nothing personal about the order.
const props = defineProps({ token: { type: String, required: true } })

// Arabic is the product default; an English-language phone gets English.
const initial = (navigator.language || '').toLowerCase().startsWith('en') ? 'en' : 'ar'
const { locale, isAr, t } = useLocale(initial)

// ---- Alert while the page is open ------------------------------------------
// Vibration works where the browser allows it (not iOS Safari). Browsers block
// sound until the user has touched the page, so sound is opt-in with one tap.
// A page that is closed cannot alert: that is web push (stage S8).
const soundOn = ref(false)
let audio = null

function beep() {
    if (!audio) return
    const now = audio.currentTime
    ;[880, 880, 1175].forEach((freq, i) => {
        const start = now + i * 0.25
        const osc = audio.createOscillator()
        const gain = audio.createGain()
        osc.type = 'sine'
        osc.frequency.value = freq
        gain.gain.setValueAtTime(0.0001, start)
        gain.gain.exponentialRampToValueAtTime(0.4, start + 0.02)
        gain.gain.exponentialRampToValueAtTime(0.0001, start + 0.2)
        osc.connect(gain).connect(audio.destination)
        osc.start(start)
        osc.stop(start + 0.22)
    })
}

function enableSound() {
    try {
        audio = audio || new (window.AudioContext || window.webkitAudioContext)()
        audio.resume?.()
        soundOn.value = true
        beep()
    } catch {
        soundOn.value = false
    }
}

function alertReady() {
    navigator.vibrate?.([250, 120, 250, 120, 500])
    if (soundOn.value) beep()
}

const { order, phase, stale, acking, acknowledge } = useOrderTracking(props.token, { onBecameReady: alertReady })

// ---- Derived view state -----------------------------------------------------
const status = computed(() => {
    const o = order.value
    if (!o) return null
    if (o.order_status === 'CANCELLED') return 'CANCELLED'
    return o.status
})
const stepIndex = computed(() => ({ PREPARING: 0, READY: 1, PICKED_UP: 2 })[status.value] ?? 0)
const steps = ['preparing', 'ready', 'picked_up']

const restaurant = computed(() => order.value?.restaurant || null)
const accent = computed(() => restaurant.value?.brand_color || '#f59e0b')
const theme = computed(() => ({ '--accent': accent.value, '--on-accent': readableOn(accent.value) }))

const headline = computed(() => ({
    PREPARING: t('track_preparing'),
    READY: t('track_ready'),
    PICKED_UP: t('track_picked_up'),
    CANCELLED: t('track_cancelled'),
})[status.value] || '')

// The tab shows the number, so a diner switching apps still sees it.
watch([order, locale], () => {
    if (!order.value) return
    document.title = `${order.value.ref} · ${restaurant.value?.name || 'Xorder'}`
})
onMounted(() => {
    // Crawlers do not run this script; the server also sends an X-Robots-Tag.
    const meta = document.createElement('meta')
    meta.name = 'robots'
    meta.content = 'noindex'
    document.head.appendChild(meta)
})

const toggleLang = () => { locale.value = isAr.value ? 'en' : 'ar' }
</script>

<template>
    <main class="trk" :style="theme" :dir="isAr ? 'rtl' : 'ltr'">
        <header class="trk-head">
            <div class="trk-brand">
                <img v-if="restaurant?.logo_url" :src="restaurant.logo_url" alt="" class="trk-logo">
                <span v-if="restaurant?.name" class="trk-name">{{ restaurant.name }}</span>
            </div>
            <button type="button" class="trk-lang" @click="toggleLang">{{ isAr ? 'English' : 'عربي' }}</button>
        </header>

        <section class="trk-body" aria-live="polite">
            <!-- Not found / expired / feature off: nothing else to show. -->
            <p v-if="phase === 'notfound'" class="trk-msg">{{ t('track_not_found') }}</p>
            <p v-else-if="phase === 'unavailable'" class="trk-msg">{{ t('track_unavailable') }}</p>

            <!-- First load -->
            <template v-else-if="!order">
                <p class="trk-msg">{{ stale ? t('track_reconnecting_first') : t('track_loading') }}</p>
            </template>

            <template v-else>
                <p class="trk-label">{{ t('track_your_number') }}</p>
                <p class="trk-number" dir="ltr">{{ order.ref }}</p>

                <div class="trk-card" :class="{ ready: status === 'READY', cancelled: status === 'CANCELLED' }">
                    <p class="trk-headline">{{ headline }}</p>
                    <p v-if="order.call_out && status === 'READY'" class="trk-callout">{{ t('track_call_out') }}</p>
                    <p v-else-if="status === 'PREPARING'" class="trk-hint">{{ t('track_keep_open') }}</p>
                </div>

                <ol v-if="status !== 'CANCELLED'" class="trk-steps" :aria-label="t('track_your_number')">
                    <li v-for="(s, i) in steps" :key="s" :class="{ done: i < stepIndex, current: i === stepIndex }">
                        <span class="dot" aria-hidden="true"></span>
                        <span class="lbl">{{ t('track_step_' + s) }}</span>
                    </li>
                </ol>

                <template v-if="status === 'READY'">
                    <p v-if="order.acknowledged_at" class="trk-hint">{{ t('track_on_my_way_done') }}</p>
                    <button v-else type="button" class="trk-btn" :disabled="acking" @click="acknowledge">
                        {{ t('track_on_my_way') }}
                    </button>
                </template>

                <button v-if="status === 'PREPARING' || status === 'READY'" type="button" class="trk-sound"
                    :disabled="soundOn" @click="enableSound">
                    {{ soundOn ? t('track_sound_enabled') : t('track_sound_on') }}
                </button>

                <p v-if="stale" class="trk-stale" role="status">{{ t('track_reconnecting') }}</p>
            </template>
        </section>

        <footer class="trk-foot">{{ t('powered_by') }} <strong>Xorder</strong></footer>
    </main>
</template>

<style scoped>
.trk {
    min-height: 100dvh;
    display: flex;
    flex-direction: column;
    background: #fffaf3;
    color: #1f1a14;
    font-family: 'Tajawal', ui-sans-serif, system-ui, sans-serif;
}
.trk-head { display: flex; align-items: center; justify-content: space-between; gap: 12px; padding: 14px 16px; }
.trk-brand { display: flex; align-items: center; gap: 10px; min-width: 0; }
.trk-logo { width: 36px; height: 36px; border-radius: 10px; object-fit: cover; flex: none; }
.trk-name { font-weight: 700; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.trk-lang { border: 1px solid #e4d8c4; background: #fff; border-radius: 999px; padding: 6px 14px; font-size: 14px; cursor: pointer; color: inherit; }

.trk-body { flex: 1; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 16px; padding: 16px 20px 32px; text-align: center; }
.trk-label { margin: 0; font-size: 18px; color: #625b52; }
.trk-number { margin: 0; font-size: clamp(64px, 24vw, 150px); line-height: 1; font-weight: 800; letter-spacing: -0.02em; font-variant-numeric: tabular-nums; unicode-bidi: isolate; word-break: break-all; }
.trk-msg { margin: 0; font-size: 18px; color: #625b52; max-width: 28ch; }

.trk-card { width: min(100%, 420px); border-radius: 20px; padding: 18px 20px; background: #fff; border: 2px solid #efe3cf; }
.trk-card.ready { background: var(--accent); border-color: var(--accent); color: var(--on-accent); }
.trk-card.cancelled { background: #f6ecec; border-color: #e6c9c9; color: #7a2b2b; }
.trk-headline { margin: 0; font-size: 22px; font-weight: 800; }
.trk-callout { margin: 8px 0 0; font-weight: 700; }
.trk-hint { margin: 8px 0 0; font-size: 15px; color: #625b52; }
.trk-card.ready .trk-hint { color: inherit; opacity: 0.9; }

.trk-steps { list-style: none; margin: 0; padding: 0; display: flex; gap: 8px; width: min(100%, 420px); }
.trk-steps li { flex: 1; display: flex; flex-direction: column; align-items: center; gap: 6px; font-size: 13px; color: #8a8174; }
.trk-steps .dot { width: 14px; height: 14px; border-radius: 50%; background: #e4d8c4; }
.trk-steps li.done .dot, .trk-steps li.current .dot { background: var(--accent); }
.trk-steps li.current { color: #1f1a14; font-weight: 700; }

.trk-btn { width: min(100%, 420px); min-height: 52px; border: 0; border-radius: 14px; background: var(--accent); color: var(--on-accent); font-size: 18px; font-weight: 800; cursor: pointer; }
.trk-btn:disabled { opacity: 0.6; cursor: default; }
.trk-sound { border: 0; background: transparent; color: #625b52; text-decoration: underline; font-size: 15px; cursor: pointer; padding: 8px; }
.trk-sound:disabled { text-decoration: none; cursor: default; }
.trk-stale { margin: 0; font-size: 14px; color: #8a4b00; background: #fff3e0; border-radius: 10px; padding: 8px 12px; }
.trk-foot { text-align: center; font-size: 13px; color: #8a8174; padding: 12px 16px 20px; }

@media (prefers-reduced-motion: no-preference) {
    .trk-card.ready { animation: trk-pulse 1.6s ease-in-out infinite; }
    @keyframes trk-pulse { 0%, 100% { transform: scale(1); } 50% { transform: scale(1.025); } }
}
</style>
