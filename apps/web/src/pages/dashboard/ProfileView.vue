<script setup>
import { computed, reactive, ref, onMounted, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import ImageUploader from '@xorder/ui/ImageUploader.vue'
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
function languagePayload() {
    return languageChoice.value === 'both'
        ? { bilingual: true, default_language: defaultLang.value }
        : { bilingual: false, default_language: languageChoice.value }
}
const form = reactive({
    name_en: '', name_ar: '', description_en: '', description_ar: '',
    phone: '', whatsapp_number: '', address: '', opening_hours: '',
    business_hours: {}, delivery_time_min: null, delivery_time_max: null,
    minimum_order: '', latitude: '', longitude: '', timezone: '',
    logo_url: '', cover_image_url: '',
    social_links: { instagram: '', facebook: '', tiktok: '' },
    accepts_orders: true,
})
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
        const payload = { ...form, ...languagePayload() }
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
        saved.value = true
    } catch (err) {
        errors.value = err.response?.data?.errors || {}
    } finally {
        saving.value = false
    }
}

// --- Change password ---
// A self-service change (separate from the profile save): verifies the current
// password server-side and, on success, swaps in the fresh token the API
// returns so the session keeps working. Stays enabled even for a read-only /
// expired restaurant — locking a user out of their own password would be wrong.
const pw = reactive({ current_password: '', password: '', password_confirmation: '' })
const pwErrors = ref({})
const pwSaved = ref(false)
const pwSaving = ref(false)

async function changePassword() {
    pwErrors.value = {}
    pwSaved.value = false
    if (pw.password !== pw.password_confirmation) {
        pwErrors.value = { password_confirmation: [t('profile.password_mismatch')] }
        return
    }
    pwSaving.value = true
    try {
        await ensureCsrf()
        await auth.changePassword({ ...pw })
        pwSaved.value = true
        pw.current_password = ''
        pw.password = ''
        pw.password_confirmation = ''
    } catch (err) {
        pwErrors.value = err.response?.data?.errors || {}
    } finally {
        pwSaving.value = false
    }
}
</script>

<template>
    <SettingsHeader class="prof-head" :title="t('nav.profile')" :desc="t('profile.subtitle')">
        <template #actions>
            <span v-if="saved" class="chip chip-green" role="status"><span class="dot"></span>{{ t('common.saved') }}</span>
            <!-- Outside the <form> on purpose: the header belongs to the shell,
                 the form to the card. Calling submit() directly keeps one save
                 path rather than a second one via form="" association. -->
            <button v-if="!loading && !loadError" type="button" class="set-btn-primary act"
                :disabled="saving || !canUpdate" @click="submit">
                {{ saving ? t('common.saving') : t('common.save') }}
            </button>
        </template>
    </SettingsHeader>

    <!-- Skeleton mirrors the stack of section cards -->
    <div v-if="loading" class="stack">
        <div class="set-skel" style="height: 300px"></div>
        <div class="set-skel" style="height: 220px"></div>
        <div class="set-skel" style="height: 160px"></div>
        <div class="set-skel" style="height: 220px"></div>
    </div>

    <ErrorState v-else-if="loadError" @retry="load" />

    <template v-else>
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
                <div class="lang-options" role="radiogroup" :aria-labelledby="'pf-languages'">
                    <label v-for="opt in languageOptions" :key="opt.value" class="lang-opt" :class="{ on: languageChoice === opt.value }">
                        <input type="radio" name="content-language" :value="opt.value" v-model="languageChoice"
                            :disabled="!canUpdate" :data-test="'lang-' + opt.value" />
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

            <!-- Same save path as the header button, kept in reach on a long page -->
            <div class="action-bar">
                <button type="submit" class="btn btn-accent act-btn" :disabled="saving || !canUpdate">
                    {{ saving ? t('common.saving') : t('common.save') }}
                </button>
            </div>
        </form>

        <!-- Change password — deliberately its own card and its own endpoint,
             and not disabled when the restaurant is read-only: a lapsed
             subscription must not lock someone out of their own password. -->
        <form class="card sec pw-card" aria-labelledby="pf-pw" @submit.prevent="changePassword">
            <div class="pw-head">
                <div class="min-w-0">
                    <h2 id="pf-pw" class="h-card">{{ t('profile.change_password') }}</h2>
                    <p class="hint">{{ t('profile.change_password_sub') }}</p>
                </div>
                <span v-if="pwSaved" class="chip chip-green" role="status"><span class="dot"></span>{{ t('profile.password_changed') }}</span>
            </div>

            <label class="field" style="max-width: 340px">
                <span class="label">{{ t('profile.current_password') }}</span>
                <input v-model="pw.current_password" type="password" dir="ltr" autocomplete="current-password" class="input" />
                <FormError :errors="pwErrors" field="current_password" />
            </label>

            <div class="grid-auto">
                <label class="field">
                    <span class="label">{{ t('profile.new_password') }}</span>
                    <input v-model="pw.password" type="password" dir="ltr" autocomplete="new-password" class="input" />
                    <span class="hint" style="margin-top: 6px">{{ t('profile.password_rule') }}</span>
                    <FormError :errors="pwErrors" field="password" />
                </label>
                <label class="field">
                    <span class="label">{{ t('profile.confirm_password') }}</span>
                    <input v-model="pw.password_confirmation" type="password" dir="ltr" autocomplete="new-password" class="input" />
                    <FormError :errors="pwErrors" field="password_confirmation" />
                </label>
            </div>

            <div class="pw-foot">
                <button type="submit" class="btn btn-accent act-btn" :disabled="pwSaving">{{ pwSaving ? t('common.saving') : t('profile.change_password') }}</button>
            </div>
        </form>
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

.pw-head { display: flex; flex-wrap: wrap; align-items: flex-start; justify-content: space-between; gap: 12px; }
.pw-foot { display: flex; }

.act { min-height: 40px; font-size: 14px; justify-content: center; }
.act-btn { min-height: 44px; justify-content: center; }

/* Sticky save row */
.action-bar { position: sticky; bottom: 0; z-index: 5; display: flex; justify-content: flex-end; gap: 10px;
    padding: 12px 16px; background: var(--card); border: 1px solid var(--line); border-radius: 15px;
    box-shadow: 0 -4px 14px rgba(0, 0, 0, .05); }

@media (max-width: 640px) {
    .sec { padding: 16px; }
    .act { min-height: 44px; }
    .action-bar .act-btn, .pw-foot .act-btn { flex: 1 1 auto; }
}
</style>
