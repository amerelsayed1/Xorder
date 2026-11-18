<script setup>
import { ref, computed, watch, onMounted } from 'vue'
import { useLocale } from '../composables/useLocale'
import { usePagerLookup } from '../composables/usePagerLookup'
import { readableOn } from '../lib/contrast'

// Guest paging, shared QR: what a client sees after scanning the restaurant's one
// standing QR. They type the number printed on their slip; the page finds their
// order and moves to its order-number page by itself. Deliberately not the menu:
// nothing here but one box.

// Language: the restaurant's own setting decides, as it does for the menu and for
// the order-number page (they share the remembered choice). Until the restaurant
// is known the phone's language is used, and no words are shown until then.
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

const { phase, restaurant, problem, busy, stale, submit } = usePagerLookup()

const number = ref('')

const bilingual = computed(() => restaurant.value?.bilingual !== false)
const restaurantName = computed(() => {
    const r = restaurant.value
    if (!r) return ''
    return (isAr.value ? (r.name_ar || r.name_en) : (r.name_en || r.name_ar)) || r.name || ''
})

let languageApplied = false
watch(restaurant, (r) => {
    if (!r || languageApplied) return
    languageApplied = true
    const fallback = r.default_language === 'en' ? 'en' : 'ar'
    locale.value = r.bilingual === false ? fallback : (storedLang() || fallback)
})

const accent = computed(() => restaurant.value?.brand_color || '#f59e0b')
const theme = computed(() => ({ '--accent': accent.value, '--on-accent': readableOn(accent.value) }))

watch([restaurantName, locale], () => {
    if (restaurantName.value) document.title = restaurantName.value
})
onMounted(() => {
    // A page every client sees the same way; nothing for a crawler to index.
    const meta = document.createElement('meta')
    meta.name = 'robots'
    meta.content = 'noindex'
    document.head.appendChild(meta)
})

const toggleLang = () => {
    locale.value = isAr.value ? 'en' : 'ar'
    try { localStorage.setItem(LANG_KEY, locale.value) } catch { /* storage unavailable */ }
}

// Digits open the numeric keypad; when more than one order shares the number the
// client must type the full number, which has letters, so the full keyboard.
const keyboard = computed(() => (problem.value === 'ambiguous' ? 'text' : 'numeric'))
const message = computed(() => ({
    not_found: t('join_not_found'),
    ambiguous: t('join_ambiguous'),
    invalid: t('join_invalid'),
    busy: t('join_busy'),
    error: t('error_generic'),
})[problem.value] || '')

const onSubmit = () => submit(number.value)
</script>

<template>
    <main class="pj" :style="theme" :dir="isAr ? 'rtl' : 'ltr'">
        <header class="pj-head">
            <div class="pj-brand">
                <img v-if="restaurant?.logo_url" :src="restaurant.logo_url" alt="" class="pj-logo">
                <span v-if="restaurantName" class="pj-name">{{ restaurantName }}</span>
            </div>
            <button v-if="restaurant && bilingual" type="button" class="pj-lang" @click="toggleLang">{{ isAr ? 'English' : 'عربي' }}</button>
        </header>

        <section class="pj-body" aria-live="polite">
            <!-- No words until the restaurant's language is known. -->
            <template v-if="phase === 'loading'">
                <p v-if="stale" class="pj-msg">{{ t('track_reconnecting_first') }}</p>
                <span v-else class="pj-spin" role="status" aria-label="Loading… / جارٍ التحميل…"><i></i><i></i><i></i></span>
            </template>

            <p v-else-if="phase === 'found'" class="pj-msg">{{ t('join_found') }}</p>

            <p v-else-if="phase === 'unavailable'" class="pj-msg">{{ t('track_unavailable') }}</p>

            <form v-else class="pj-form" @submit.prevent="onSubmit">
                <label for="pj-number" class="pj-title">{{ t('join_title') }}</label>
                <input id="pj-number" v-model="number" class="pj-input" dir="ltr" type="text" :inputmode="keyboard"
                    enterkeyhint="go" autocomplete="off" autocapitalize="characters" spellcheck="false" maxlength="40"
                    placeholder="42" :aria-invalid="problem === 'invalid' || problem === 'not_found'" required>
                <p class="pj-hint">{{ t('join_hint') }} <bdi class="pj-example" dir="ltr">MAIN-2026-000042</bdi></p>

                <p v-if="message" class="pj-problem" role="alert">{{ message }}<template v-if="problem === 'ambiguous'"> <bdi class="pj-example" dir="ltr">MAIN-2026-000042</bdi></template></p>

                <button type="submit" class="pj-btn" :disabled="busy">{{ busy ? t('join_looking') : t('join_button') }}</button>
            </form>
        </section>

        <footer class="pj-foot">{{ t('powered_by') }} <strong>Xorder</strong></footer>
    </main>
</template>

<style scoped>
.pj {
    min-height: 100dvh;
    display: flex;
    flex-direction: column;
    background: #fffaf3;
    color: #1f1a14;
    font-family: 'Tajawal', ui-sans-serif, system-ui, sans-serif;
}
.pj-head { display: flex; align-items: center; justify-content: space-between; gap: 12px; padding: 14px 16px; }
.pj-brand { display: flex; align-items: center; gap: 10px; min-width: 0; }
.pj-logo { width: 36px; height: 36px; border-radius: 10px; object-fit: cover; flex: none; }
.pj-name { font-weight: 700; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.pj-lang { border: 1px solid #e4d8c4; background: #fff; border-radius: 999px; padding: 6px 14px; font-size: 14px; cursor: pointer; color: inherit; }

.pj-body { flex: 1; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 16px; padding: 16px 20px 32px; text-align: center; }
.pj-msg { margin: 0; font-size: 18px; color: #625b52; max-width: 28ch; }

.pj-form { width: min(100%, 420px); display: flex; flex-direction: column; gap: 14px; align-items: stretch; }
.pj-title { font-size: 22px; font-weight: 800; }
.pj-input {
    width: 100%; box-sizing: border-box; text-align: center; font-size: clamp(32px, 11vw, 48px); font-weight: 800;
    letter-spacing: 0.06em; font-variant-numeric: tabular-nums; padding: 14px 12px; border-radius: 16px;
    border: 2px solid #e4d8c4; background: #fff; color: #1f1a14; text-transform: uppercase;
}
.pj-input:focus { outline: none; border-color: var(--accent); box-shadow: 0 0 0 3px color-mix(in srgb, var(--accent) 25%, transparent); }
.pj-input::placeholder { color: #cdbfa8; }
.pj-hint { margin: 0; font-size: 15px; color: #625b52; }
.pj-example { white-space: nowrap; font-weight: 700; }
.pj-problem { margin: 0; font-size: 16px; color: #8a4b00; background: #fff3e0; border-radius: 12px; padding: 10px 14px; }

.pj-btn { min-height: 54px; border: 0; border-radius: 14px; background: var(--accent); color: var(--on-accent); font-size: 18px; font-weight: 800; cursor: pointer; }
.pj-btn:disabled { opacity: 0.6; cursor: default; }
.pj-foot { text-align: center; font-size: 13px; color: #8a8174; padding: 12px 16px 20px; }

.pj-spin { display: inline-flex; gap: 8px; }
.pj-spin i { width: 12px; height: 12px; border-radius: 50%; background: #e4d8c4; }
@media (prefers-reduced-motion: no-preference) {
    .pj-spin i { animation: pj-dot 1s ease-in-out infinite; }
    .pj-spin i:nth-child(2) { animation-delay: 0.15s; }
    .pj-spin i:nth-child(3) { animation-delay: 0.3s; }
    @keyframes pj-dot { 0%, 100% { background: #e4d8c4; } 50% { background: #8a8174; } }
}
</style>
