<script setup>
import { computed, reactive, ref, onMounted, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import ImageUploader from '@xorder/ui/ImageUploader.vue'
import { asPreview } from '../../lib/host.js'
import FormError from '@xorder/ui/FormError.vue'
import ErrorState from '@xorder/ui/ErrorState.vue'
import { useMenuLang } from '../../lib/menuLang.js'
import { collectPhoneErrors } from '../../lib/phone.js'
import { useAuth } from '@xorder/api-client/auth.js'
import { useCaps } from '../../lib/useCaps.js'
import SettingsHeader from './settings/SettingsHeader.vue'

const { t, locale } = useI18n()
const auth = useAuth()
// The page opens on settings.view; every field and the save button
// additionally require settings.update.
const { canUpdate } = useCaps('settings')
const { langs, bilingual, defaultLang } = useMenuLang()

// Content languages (XORD-005): which languages the menu is written in. Three
// choices, read off the two stored flags. "Both" keeps whichever language is
// already primary, so choosing it never silently swaps the menu's first language.
const languageChoice = ref('both')
const languageOptions = [
    { value: 'ar', label: 'wizard.lang_arabic_only' },
    { value: 'en', label: 'wizard.lang_english_only' },
    { value: 'both', label: 'wizard.lang_bilingual' },
]
function readLanguageChoice() {
    languageChoice.value = bilingual.value ? 'both' : defaultLang.value
}
// Read at load and again whenever the stored setting changes underneath us (a
// colleague saved it, or our own save refreshed the session).
watch([bilingual, defaultLang], readLanguageChoice, { immediate: true })
const form = reactive({
    name_en: '', name_ar: '', description_en: '', description_ar: '',
    phone: '', whatsapp_number: '', address: '', opening_hours: '',
    business_hours: {}, delivery_time_min: null, delivery_time_max: null,
    minimum_order: '', latitude: '', longitude: '', timezone: '',
    logo_url: '', cover_image_url: '',
    social_links: { instagram: '', facebook: '', tiktok: '' },
    accepts_orders: true,
    // The menu's look (owner-editable since 2026-11-03).
    brand_color: '#f89a06',
    menu_layout: 'photo',
    public_url: '',
})

// A short palette that reads well on the white menu; any other colour can be
// picked with the colour well or typed as hex.
const COLOR_PRESETS = ['#f89a06', '#d83a2a', '#c2185b', '#7b3fa0', '#1f5fbf', '#0f8a7e', '#2e7d32', '#3b2f2f', '#111827']
// Mirrors App\Enums\MenuLayout; labels resolve via t('restaurant.menu_layout_*').
const MENU_LAYOUTS = ['photo', 'text-grid', 'text-list']
const colorValid = computed(() => /^#[0-9a-fA-F]{6}$/.test(form.brand_color || ''))
// Typing "1e7a46" without the hash is the common slip; accept it.
function normalizeColor() {
    const v = (form.brand_color || '').trim()
    if (/^[0-9a-fA-F]{6}$/.test(v)) form.brand_color = '#' + v
    else form.brand_color = v
}
// The plan decides whether ordering exists; the switch below only turns an
// entitled channel on and off. With no entitled channel there is nothing to
// switch, so the control is hidden rather than shown doing nothing.
const orderingEntitled = ref(false)
// Zones the dashboard offers by name. Any IANA identifier the server knows is
// accepted, so a restaurant already on something outside this list keeps it —
// the current value is appended below rather than silently swapped.
const TIMEZONES = [
    'Africa/Cairo', 'Asia/Riyadh', 'Asia/Dubai', 'Asia/Kuwait', 'Asia/Qatar',
    'Asia/Bahrain', 'Asia/Muscat', 'Asia/Amman', 'Asia/Beirut', 'Asia/Baghdad',
    'Africa/Casablanca', 'Africa/Tunis', 'Africa/Algiers', 'Africa/Tripoli',
    'Africa/Khartoum', 'Europe/London', 'Europe/Paris', 'Europe/Istanbul', 'UTC',
]
const timezoneOptions = computed(() => (
    form.timezone && !TIMEZONES.includes(form.timezone) ? [form.timezone, ...TIMEZONES] : TIMEZONES
))
// What the chosen zone means in practice, so the owner can sanity-check it
// against the clock on their wall before saving.
const timezoneNow = computed(() => {
    try {
        return new Intl.DateTimeFormat(locale.value === 'ar' ? 'ar-EG' : 'en-GB', {
            timeZone: form.timezone || 'UTC', hour: '2-digit', minute: '2-digit', weekday: 'short',
        }).format(new Date())
    } catch {
        return ''
    }
})
const errors = ref({})
const saved = ref(false)
const saving = ref(false)
const loading = ref(true)
const loadError = ref(false)

// Save bar state. The bar sits at the bottom of the viewport while the profile
// cards scroll past it, and its button only lights up once something actually
// changed, so a stray tap never re-sends the same profile.
const snapshot = ref('')
const serialize = () => JSON.stringify(form)
const dirty = computed(() => snapshot.value !== '' && serialize() !== snapshot.value)
// Editing again after a save: the "saved" chip gives way to the unsaved hint.
watch(dirty, (d) => { if (d) saved.value = false })

async function load() {
    loading.value = true
    loadError.value = false
    try {
        const { data } = await api.get('api/dashboard/restaurant')
        Object.assign(form, {
            ...data.data,
            // The API sends {} when nothing is set — keep every known field present
            // so the inputs stay controlled.
            social_links: { instagram: '', facebook: '', tiktok: '', ...(data.data.social_links || {}) },
        })
        orderingEntitled.value = !!data.data.ordering_entitled
        snapshot.value = serialize()
    } catch (err) {
        loadError.value = true
    } finally {
        loading.value = false
    }
}
onMounted(load)

async function submit() {
    errors.value = {}; saved.value = false
    // Phone moved to the branch; only the WhatsApp ordering number lives here now.
    const phoneErrors = collectPhoneErrors(
        { whatsapp_number: form.whatsapp_number },
        t('restaurant.phone_invalid'),
    )
    if (Object.keys(phoneErrors).length) { errors.value = phoneErrors; return }
    saving.value = true
    try {
        await ensureCsrf()
        // Blank number inputs arrive as '' — send null so nullable/required_with
        // rules (e.g. latitude↔longitude) see a truly absent value.
        const payload = { ...form }
        // A half-typed colour would only come back as a 422 on the whole
        // profile; keep the saved one until the hex is complete.
        if (!colorValid.value) delete payload.brand_color
        delete payload.public_url
        for (const k of ['latitude', 'longitude', 'minimum_order', 'delivery_time_min', 'delivery_time_max']) {
            if (payload[k] === '' || payload[k] === undefined || (typeof payload[k] === 'number' && Number.isNaN(payload[k]))) {
                payload[k] = null
            }
        }
        await api.put('api/dashboard/restaurant', payload)
        // The forms across the dashboard read the restaurant from the session,
        // so refresh it: a form opened after this save shows the new languages,
        // and one left open re-renders its fields from the same reactive source.
        await auth.fetchUser()
        snapshot.value = serialize()
        saved.value = true
    } catch (err) {
        errors.value = err.response?.data?.errors || {}
    } finally {
        saving.value = false
    }
}
</script>

<template>
    <!-- No action in the header: the Save bar at the end of the cards is the
         one save control, and it stays on screen while the page scrolls. -->
    <SettingsHeader class="prof-head" :title="t('nav.profile')" :desc="t('profile.subtitle')" />

    <!-- Skeleton mirrors the stack of section cards -->
    <div v-if="loading" class="stack">
        <div class="set-skel" style="height: 300px"></div>
        <div class="set-skel" style="height: 220px"></div>
        <div class="set-skel" style="height: 160px"></div>
        <div class="set-skel" style="height: 220px"></div>
    </div>

    <ErrorState v-else-if="loadError" @retry="load" />

    <template v-else>
      <div class="prof-stack">
        <form class="stack" @submit.prevent="submit">
            <!-- 1. Restaurant identity -->
            <section class="card sec" aria-labelledby="pf-identity">
                <h2 id="pf-identity" class="h-card">{{ t('profile.sec_identity') }}</h2>
                <div class="grid-auto">
                    <label v-for="lng in langs" :key="'n' + lng" class="field" :dir="lng === 'ar' ? 'rtl' : 'ltr'">
                        <span class="label">{{ bilingual ? t('common.name_' + lng) : t('common.name') }} <span class="req" aria-hidden="true">*</span></span>
                        <input v-model="form['name_' + lng]" class="input" />
                        <FormError :errors="errors" :field="'name_' + lng" />
                    </label>
                    <label class="field">
                        <span class="label">{{ t('restaurant.whatsapp') }}</span>
                        <input v-model="form.whatsapp_number" class="input" dir="ltr" data-en-digits />
                        <FormError :errors="errors" field="whatsapp_number" />
                    </label>
                </div>

                <div class="grid-auto">
                    <label v-for="lng in langs" :key="'d' + lng" class="field" :dir="lng === 'ar' ? 'rtl' : 'ltr'">
                        <span class="label">{{ bilingual ? t('common.description_' + lng) : t('common.description') }}</span>
                        <textarea v-model="form['description_' + lng]" rows="3" class="input" style="resize: vertical"
                            :placeholder="t('restaurant.description_placeholder')"></textarea>
                    </label>
                </div>
                <!-- Phone, address, and working hours are configured per-branch
                     (every client has at least one branch). Only the WhatsApp
                     ordering number — one per menu — stays at restaurant level. -->
            </section>

            <!-- Content languages -->
            <section class="card sec" aria-labelledby="pf-languages">
                <h2 id="pf-languages" class="h-card">{{ t('profile.sec_languages') }}</h2>
                <p class="help">{{ t('profile.languages_hint') }}</p>
                <!-- Shown, not edited: one setting for the whole business, set by
                     the platform (owner decision 2026-11-07). -->
                <p class="help">{{ t('profile.languages_platform_set') }}</p>
                <div class="lang-options" role="radiogroup" :aria-labelledby="'pf-languages'">
                    <label v-for="opt in languageOptions" :key="opt.value" class="lang-opt" :class="{ on: languageChoice === opt.value }">
                        <input type="radio" name="content-language" :value="opt.value" v-model="languageChoice"
                            disabled :data-test="'lang-' + opt.value" />
                        {{ t(opt.label) }}
                    </label>
                </div>
                <FormError :errors="errors" field="default_language" />
                <FormError :errors="errors" field="bilingual" />
            </section>

            <!-- 2. Ordering and time zone -->
            <section class="card sec" aria-labelledby="pf-ordering">
                <h2 id="pf-ordering" class="h-card">{{ t('profile.sec_ordering') }}</h2>

                <!-- Owner's "are we taking orders right now" switch. Hidden when
                     the plan entitles no ordering channel. -->
                <div v-if="orderingEntitled" class="inset">
                    <div class="min-w-0">
                        <span class="inset-title">{{ t('restaurant.accepts_orders') }}</span>
                        <p class="hint">{{ form.accepts_orders ? t('restaurant.accepts_orders_on') : t('restaurant.accepts_orders_off') }}</p>
                    </div>
                    <button
                        type="button"
                        class="switch"
                        :class="{ on: form.accepts_orders }"
                        :disabled="!canUpdate"
                        role="switch"
                        :aria-checked="form.accepts_orders"
                        :aria-label="t('restaurant.accepts_orders')"
                        @click="form.accepts_orders = !form.accepts_orders"
                    ></button>
                </div>

                <div class="grid-auto">
                    <div class="field">
                        <span class="label">{{ t('restaurant.delivery_time') }}</span>
                        <div class="flex items-center gap-2">
                            <input v-model.number="form.delivery_time_min" type="number" min="0" max="1440" class="input" :placeholder="t('restaurant.delivery_from')" :aria-label="t('restaurant.delivery_from')" dir="ltr" />
                            <span style="color:var(--body)" aria-hidden="true">–</span>
                            <input v-model.number="form.delivery_time_max" type="number" min="0" max="1440" class="input" :placeholder="t('restaurant.delivery_to')" :aria-label="t('restaurant.delivery_to')" dir="ltr" />
                        </div>
                        <FormError :errors="errors" field="delivery_time_min" />
                        <FormError :errors="errors" field="delivery_time_max" />
                    </div>
                    <label class="field">
                        <span class="label">{{ t('restaurant.minimum_order') }}</span>
                        <input v-model="form.minimum_order" type="number" min="0" step="0.01" class="input" dir="ltr"
                            :placeholder="t('restaurant.minimum_order_placeholder')" />
                        <FormError :errors="errors" field="minimum_order" />
                    </label>
                </div>

                <label class="field">
                    <span class="label">{{ t('restaurant.timezone') }}</span>
                    <select v-model="form.timezone" class="input" dir="ltr">
                        <option v-for="tz in timezoneOptions" :key="tz" :value="tz">{{ tz }}</option>
                    </select>
                    <p class="hint" style="margin-top: 6px">
                        {{ t('restaurant.timezone_hint') }}
                        <template v-if="timezoneNow"> — {{ t('restaurant.timezone_now', { time: timezoneNow }) }}</template>
                    </p>
                    <FormError :errors="errors" field="timezone" />
                </label>
            </section>

            <!-- 3. Branding -->
            <section class="card sec" aria-labelledby="pf-branding">
                <h2 id="pf-branding" class="h-card">{{ t('profile.sec_branding') }}</h2>
                <div class="grid-auto">
                    <ImageUploader v-model="form.logo_url" folder="logos" :label="t('restaurant.logo')" :disabled="!canUpdate" />
                    <ImageUploader v-model="form.cover_image_url" folder="covers" :label="t('restaurant.cover_image')" :disabled="!canUpdate" />
                </div>
            </section>

            <!-- 4. Social links -->
            <section class="card sec" aria-labelledby="pf-social">
                <div>
                    <h2 id="pf-social" class="h-card">{{ t('restaurant.social_links') }}</h2>
                    <p class="hint">{{ t('restaurant.social_hint') }}</p>
                </div>
                <div class="flex flex-col gap-3">
                    <label class="flex items-center gap-3">
                        <i class="pi pi-instagram social-ico" style="color:#e4405f" aria-hidden="true"></i>
                        <span class="flex-1 min-w-0">
                            <input v-model="form.social_links.instagram" type="url" dir="ltr" aria-label="Instagram" placeholder="https://instagram.com/…" class="input" style="margin-top:0" />
                            <FormError :errors="errors" field="social_links.instagram" />
                        </span>
                    </label>
                    <label class="flex items-center gap-3">
                        <i class="pi pi-facebook social-ico" style="color:#1877f2" aria-hidden="true"></i>
                        <span class="flex-1 min-w-0">
                            <input v-model="form.social_links.facebook" type="url" dir="ltr" aria-label="Facebook" placeholder="https://facebook.com/…" class="input" style="margin-top:0" />
                            <FormError :errors="errors" field="social_links.facebook" />
                        </span>
                    </label>
                    <label class="flex items-center gap-3">
                        <i class="pi pi-tiktok social-ico" style="color:var(--ink)" aria-hidden="true"></i>
                        <span class="flex-1 min-w-0">
                            <input v-model="form.social_links.tiktok" type="url" dir="ltr" aria-label="TikTok" placeholder="https://tiktok.com/@…" class="input" style="margin-top:0" />
                            <FormError :errors="errors" field="social_links.tiktok" />
                        </span>
                    </label>
                </div>
            </section>
        </form>

        <!-- Menu look: saved by the same Save bar as the profile above. -->
        <section class="set-card" :aria-label="t('branding.title')">
            <div class="set-card-head">
                <div class="set-card-head-text">
                    <span class="set-card-title">{{ t('branding.title') }}</span>
                    <span class="set-card-desc">{{ t('branding.sub') }}</span>
                </div>
                <a v-if="form.public_url" :href="asPreview(form.public_url)" target="_blank" rel="noopener"
                    class="set-btn" style="margin-inline-start:auto">{{ t('branding.preview') }}</a>
            </div>

            <div class="set-form">
                <div class="set-field" style="gap: 10px">
                    <span class="label">{{ t('restaurant.brand_color') }}</span>
                    <div class="brand-row">
                        <input v-model="form.brand_color" type="color" class="brand-well" :disabled="!canUpdate"
                            :aria-label="t('restaurant.brand_color')" />
                        <input v-model="form.brand_color" class="input brand-hex" dir="ltr" maxlength="7" :disabled="!canUpdate"
                            :aria-invalid="!colorValid" @blur="normalizeColor" />
                        <div class="brand-swatches" role="group" :aria-label="t('branding.presets')">
                            <button v-for="c in COLOR_PRESETS" :key="c" type="button" class="brand-swatch"
                                :class="{ on: (form.brand_color || '').toLowerCase() === c }" :style="{ background: c }"
                                :disabled="!canUpdate" :aria-label="c" :title="c" @click="form.brand_color = c"></button>
                        </div>
                    </div>
                    <p v-if="!colorValid" class="set-inset-hint" style="color:#c0392b">{{ t('branding.color_invalid') }}</p>
                    <FormError :errors="errors" field="brand_color" />
                    <!-- What the colour does on the menu: buttons, prices, the active category. -->
                    <div class="brand-sample" :style="{ '--b': colorValid ? form.brand_color : '#f89a06' }" aria-hidden="true">
                        <span class="brand-sample-chip">{{ t('branding.sample_category') }}</span>
                        <span class="brand-sample-price">45.00</span>
                        <span class="brand-sample-btn">{{ t('branding.sample_add') }}</span>
                    </div>
                </div>

                <div class="set-field" style="gap: 10px">
                    <span class="label">{{ t('restaurant.menu_layout') }}</span>
                    <div class="layout-grid" role="radiogroup" :aria-label="t('restaurant.menu_layout')">
                        <button v-for="m in MENU_LAYOUTS" :key="m" type="button" role="radio"
                            class="layout-card" :class="{ on: form.menu_layout === m }" :aria-checked="form.menu_layout === m"
                            :disabled="!canUpdate" @click="form.menu_layout = m">
                            <span class="layout-art" :class="'art-' + m" aria-hidden="true">
                                <template v-if="m === 'photo'"><i class="art-img"></i><i class="art-img"></i><i class="art-line"></i><i class="art-line"></i></template>
                                <template v-else-if="m === 'text-grid'"><i class="art-box"></i><i class="art-box"></i><i class="art-box"></i><i class="art-box"></i></template>
                                <template v-else><i class="art-row"></i><i class="art-row"></i><i class="art-row"></i><i class="art-row"></i></template>
                            </span>
                            <span class="layout-name">{{ t('restaurant.menu_layout_' + m.replace('-', '_')) }}</span>
                        </button>
                    </div>
                    <p class="set-inset-hint">{{ t('restaurant.menu_layout_hint') }}</p>
                    <FormError :errors="errors" field="menu_layout" />
                </div>
            </div>
        </section>

        <!-- Save bar: sticky to the bottom of the viewport while the profile
             cards run past it, then parks under the last card. -->
        <div class="save-bar">
            <span v-if="saved" class="set-chip set-chip-green"><span class="dot"></span>{{ t('common.saved') }}</span>
            <span v-else-if="dirty" class="save-bar-hint">{{ t('common.unsaved_changes') }}</span>
            <button type="button" class="set-btn-primary" :disabled="saving || !canUpdate || !dirty" @click="submit">
                {{ saving ? t('common.saving') : t('common.save_changes') }}
            </button>
        </div>
      </div>
    </template>
</template>

<style scoped>
/* Colours come from the shared theme variables only. The settings shell's
   own text is nudged to --body so secondary copy stays readable. */
.prof-head :deep(.set-desc), .prof-head :deep(.set-crumb) { color: var(--body); font-size: 14px; }

.stack { display: flex; flex-direction: column; gap: 18px; }
.sec { padding: 22px; display: flex; flex-direction: column; gap: 18px; }
.lang-options { display: flex; flex-wrap: wrap; gap: 10px; }
.lang-opt { display: inline-flex; align-items: center; gap: 8px; padding: 10px 14px; border: 1px solid var(--line, #e5e7eb); border-radius: 12px; cursor: pointer; min-height: 44px; }
.lang-opt.on { border-color: var(--p-primary-600, #2563eb); background: var(--p-primary-50, #eff6ff); }
.grid-auto { display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); gap: 16px; }
.field { display: flex; flex-direction: column; min-width: 0; }
.req { color: var(--red); }
.hint { font-size: 13.5px; color: var(--body); line-height: 1.55; margin-top: 3px; }

.inset { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: 14px;
    padding: 14px 16px; border: 1px solid var(--line); border-radius: 12px; background: var(--page); }
.inset-title { font-size: 15px; font-weight: 600; color: var(--ink); }

.social-ico { font-size: 20px; width: 24px; text-align: center; flex: none; }

.chip { display: inline-flex; align-items: center; gap: 6px; padding: 4px 11px; border-radius: 999px; font-size: 12.5px; font-weight: 600; }
.chip .dot { width: 6px; height: 6px; border-radius: 999px; background: currentColor; }
.chip-green { background: var(--green-soft); color: var(--green); }

/* The profile form + menu look share one Save; the bar is sticky inside this box. */
.prof-stack { display: flex; flex-direction: column; gap: 18px; }
.save-bar {
    position: sticky; bottom: 0; z-index: 5;
    display: flex; align-items: center; justify-content: flex-end; gap: 14px;
    padding: 14px 18px; border: 1px solid var(--line); border-radius: 15px;
    background: var(--card); box-shadow: 0 -6px 24px rgba(31, 27, 22, .08);
}
.save-bar-hint { font-size: 13.5px; color: var(--body); }

@media (max-width: 640px) {
    .sec { padding: 16px; }
    .save-bar { padding: 12px 14px; }
    .save-bar .set-btn-primary { flex: 1; }
}
/* Menu look */
.brand-row { display: flex; flex-wrap: wrap; align-items: center; gap: 10px; }
.brand-well { width: 46px; height: 42px; padding: 2px; border: 1px solid var(--line); border-radius: 10px; background: var(--card); cursor: pointer; }
.brand-hex { width: 110px; margin-top: 0; font-family: var(--font-mono, ui-monospace, monospace); text-transform: uppercase; }
.brand-swatches { display: flex; flex-wrap: wrap; gap: 6px; }
.brand-swatch { width: 26px; height: 26px; border-radius: 50%; border: 2px solid var(--card); box-shadow: 0 0 0 1px var(--line); cursor: pointer; }
.brand-swatch.on { box-shadow: 0 0 0 2px var(--ink); }
.brand-swatch:disabled, .layout-card:disabled { cursor: not-allowed; opacity: .6; }
.brand-sample { display: flex; flex-wrap: wrap; align-items: center; gap: 12px; padding: 12px 14px; border-radius: 12px;
    background: var(--page); border: 1px dashed var(--line); }
.brand-sample-chip { font-size: 12.5px; font-weight: 600; padding: 4px 12px; border-radius: 20px; background: var(--b); color: #fff; }
.brand-sample-price { font-weight: 700; color: var(--b); }
.brand-sample-btn { margin-inline-start: auto; font-size: 13px; font-weight: 600; padding: 7px 14px; border-radius: 10px; background: var(--b); color: #fff; }
.layout-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 10px; }
.layout-card { display: flex; flex-direction: column; gap: 8px; padding: 10px; border: 1.5px solid var(--line); border-radius: 12px;
    background: var(--card); cursor: pointer; text-align: start; font: inherit; }
.layout-card.on { border-color: var(--accent); background: var(--accent-soft); }
.layout-name { font-size: 13px; font-weight: 600; color: var(--ink); }
.layout-art { display: grid; gap: 5px; height: 72px; padding: 7px; border-radius: 8px; background: var(--page); }
.layout-art i { display: block; border-radius: 4px; background: var(--line); }
.art-photo { grid-template-columns: 1fr 1fr; grid-template-rows: 1fr 6px 6px; }
.art-photo .art-img { background: #d9d4cc; }
.art-text-grid { grid-template-columns: 1fr 1fr; }
.art-text-list { grid-template-rows: repeat(4, 1fr); }
</style>
