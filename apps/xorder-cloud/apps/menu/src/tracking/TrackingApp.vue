<script setup>
import { ref, computed, watch, onMounted } from 'vue'
import { useLocale } from '../composables/useLocale'
import { useOrderTracking } from '../composables/useOrderTracking'
import { readableOn } from '../lib/contrast'

// Guest paging S3: what a diner sees after scanning the QR on their receipt.
// Their order number, and the order's state. Deliberately not the menu: no
// categories, no cart, no prices, and nothing personal about the order.
const props = defineProps({ token: { type: String, required: true } })

// Language: the restaurant's own setting decides, as it does for the menu: its
// default language, and for a single-language restaurant that language only. A
// bilingual restaurant's diner can switch, and their choice is remembered. The
// restaurant is only known after the first response, so until then (and for
// the not-found screens, which have no restaurant) the phone's language is used.
const LANG_KEY = 'xorder.track_lang'
function storedLang() {
    try {
        const v = localStorage.getItem(LANG_KEY)
        return v === 'ar' || v === 'en' ? v : null
    } catch {
        return null // storage can be blocked; the page works without it
    }
}
const phoneLang = (navigator.language || '').toLowerCase().startsWith('en') ? 'en' : 'ar'
const { locale, isAr, t } = useLocale(storedLang() || phoneLang)

// ---- Alert while the page is open ------------------------------------------
// Vibration works where the browser allows it (not iOS Safari). Browsers block
// sound until the user has touched the page, so sound is opt-in with one tap.
// A page that is closed cannot alert: that is web push (stage S8).
const soundOn = ref(false)
let audio = null

// A loud, phone-style ring. A square wave sounds far louder to the ear than a
// sine at the same level, so it is used here at full gain, trilling between two
// high notes, two bursts per ring, repeated so it is hard to miss. A web page
// cannot go above the phone's own volume, and iPhone's silent switch mutes it.
function ring(rings = 3) {
    if (!audio) return
    const start = audio.currentTime + 0.05
    for (let r = 0; r < rings; r++) {
        for (let b = 0; b < 2; b++) {
            const t0 = start + r * 1.3 + b * 0.45
            const osc = audio.createOscillator()
            const gain = audio.createGain()
            osc.type = 'square'
            // Trill between two notes every 40 ms for the length of the burst.
            for (let k = 0; k * 0.04 < 0.35; k++) {
                osc.frequency.setValueAtTime(k % 2 ? 1319 : 988, t0 + k * 0.04)
            }
            gain.gain.setValueAtTime(0.0001, t0)
            gain.gain.linearRampToValueAtTime(1, t0 + 0.01)
            gain.gain.setValueAtTime(1, t0 + 0.33)
            gain.gain.linearRampToValueAtTime(0.0001, t0 + 0.36)
            osc.connect(gain).connect(audio.destination)
            osc.start(t0)
            osc.stop(t0 + 0.37)
        }
    }
}

function enableSound() {
    try {
        audio = audio || new (window.AudioContext || window.webkitAudioContext)()
        audio.resume?.()
        soundOn.value = true
        ring(1) // one ring so the diner hears what the alert sounds like
    } catch {
        soundOn.value = false
    }
}

function alertReady() {
    navigator.vibrate?.([400, 150, 400, 150, 400, 150, 800])
    if (soundOn.value) ring(3)
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
const bilingual = computed(() => restaurant.value?.bilingual !== false)
const restaurantName = computed(() => {
    const r = restaurant.value
    if (!r) return ''
    return (isAr.value ? (r.name_ar || r.name_en) : (r.name_en || r.name_ar)) || r.name || ''
})

// Apply the restaurant's language once, when it first arrives.
let languageApplied = false
watch(restaurant, (r) => {
    if (!r || languageApplied) return
    languageApplied = true
    const fallback = r.default_language === 'en' ? 'en' : 'ar'
    locale.value = r.bilingual === false ? fallback : (storedLang() || fallback)
})
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
    document.title = `${order.value.ref} · ${restaurantName.value || 'Xorder'}`
})
onMounted(() => {
    // Crawlers do not run this script; the server also sends an X-Robots-Tag.
    const meta = document.createElement('meta')
    meta.name = 'robots'
    meta.content = 'noindex'
    document.head.appendChild(meta)
})

const toggleLang = () => {
    locale.value = isAr.value ? 'en' : 'ar'
    try { localStorage.setItem(LANG_KEY, locale.value) } catch { /* storage unavailable */ }
}
</script>

<template>
    <main class="trk" :style="theme" :dir="isAr ? 'rtl' : 'ltr'">
        <header class="trk-head">
            <div class="trk-brand">
                <img v-if="restaurant?.logo_url" :src="restaurant.logo_url" alt="" class="trk-logo">
                <span v-if="restaurantName" class="trk-name">{{ restaurantName }}</span>
            </div>
            <button v-if="bilingual" type="button" class="trk-lang" @click="toggleLang">{{ isAr ? 'English' : 'عربي' }}</button>
        </header>

        <section class="trk-body" aria-live="polite">
            <!-- Not found / expired / feature off: nothing else to show. -->
            <p v-if="phase === 'notfound'" class="trk-msg">{{ t('track_not_found') }}</p>
            <p v-else-if="phase === 'unavailable'" class="trk-msg">{{ t('track_unavailable') }}</p>

            <!-- First load -->
            <template v-else-if="!order">
                <!-- No words until the restaurant's language is known, so an Arabic
                     restaurant never flashes English. -->
                <p v-if="stale" class="trk-msg">{{ t('track_reconnecting_first') }}</p>
                <span v-else class="trk-spin" role="status" aria-label="Loading… / جارٍ التحميل…"><i></i><i></i><i></i></span>
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
.trk-spin { display: inline-flex; gap: 8px; }
.trk-spin i { width: 12px; height: 12px; border-radius: 50%; background: #e4d8c4; }
@media (prefers-reduced-motion: no-preference) {
    .trk-spin i { animation: trk-dot 1s ease-in-out infinite; }
    .trk-spin i:nth-child(2) { animation-delay: 0.15s; }
    .trk-spin i:nth-child(3) { animation-delay: 0.3s; }
    @keyframes trk-dot { 0%, 100% { background: #e4d8c4; } 50% { background: #8a8174; } }
}

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
