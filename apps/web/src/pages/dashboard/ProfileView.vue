<script setup>
import { computed, reactive, ref, onMounted } from 'vue'
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
const { langs, bilingual } = useMenuLang()
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
        const payload = { ...form }
        for (const k of ['latitude', 'longitude', 'minimum_order', 'delivery_time_min', 'delivery_time_max']) {
            if (payload[k] === '' || payload[k] === undefined || (typeof payload[k] === 'number' && Number.isNaN(payload[k]))) {
                payload[k] = null
            }
        }
        await api.put('api/dashboard/restaurant', payload)
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
    <SettingsHeader :title="t('nav.profile')" :desc="t('profile.subtitle')">
        <template #actions>
            <span v-if="saved" class="set-chip set-chip-green"><span class="dot"></span>{{ t('common.saved') }}</span>
            <!-- Outside the <form> on purpose: the header belongs to the shell,
                 the form to the card. Calling submit() directly keeps one save
                 path rather than a second one via form="" association. -->
            <button v-if="!loading && !loadError" type="button" class="set-btn-primary"
                :disabled="saving || !canUpdate" @click="submit">
                {{ saving ? t('common.saving') : t('common.save') }}
            </button>
        </template>
    </SettingsHeader>

    <div v-if="loading" class="set-stack-lg">
        <div class="set-skel" style="height: 420px"></div>
        <div class="set-skel" style="height: 220px"></div>
    </div>

    <ErrorState v-else-if="loadError" @retry="load" />

    <template v-else>
        <form class="set-card set-form" @submit.prevent="submit">
            <div class="set-grid">
                <label v-for="lng in langs" :key="'n' + lng" class="set-field" :dir="lng === 'ar' ? 'rtl' : 'ltr'">
                    <span class="label">{{ bilingual ? t('common.name_' + lng) : t('common.name') }} <span class="set-req">*</span></span>
                    <input v-model="form['name_' + lng]" class="input" />
                    <FormError :errors="errors" :field="'name_' + lng" />
                </label>
                <label class="set-field">
                    <span class="label">{{ t('restaurant.whatsapp') }}</span>
                    <input v-model="form.whatsapp_number" class="input" dir="ltr" data-en-digits />
                    <FormError :errors="errors" field="whatsapp_number" />
                </label>
            </div>

            <div class="set-grid">
                <label v-for="lng in langs" :key="'d' + lng" class="set-field" :dir="lng === 'ar' ? 'rtl' : 'ltr'">
                    <span class="label">{{ bilingual ? t('common.description_' + lng) : t('common.description') }}</span>
                    <textarea v-model="form['description_' + lng]" rows="3" class="input" style="resize: vertical"
                        :placeholder="t('restaurant.description_placeholder')"></textarea>
                </label>
            </div>

            <!-- Phone, address, and working hours are configured per-branch
                 (every client has at least one branch). Only the WhatsApp
                 ordering number — one per menu — stays at restaurant level. -->
            <!-- Owner's "are we taking orders right now" switch. Hidden when
                 the plan entitles no ordering channel. -->
            <div v-if="orderingEntitled" class="set-inset">
                <div>
                    <span class="set-inset-title">{{ t('restaurant.accepts_orders') }}</span>
                    <p class="set-inset-hint">{{ form.accepts_orders ? t('restaurant.accepts_orders_on') : t('restaurant.accepts_orders_off') }}</p>
                </div>
                <button
                    type="button"
                    class="switch"
                    :class="{ on: form.accepts_orders }"
                    :disabled="!canUpdate"
                    :aria-pressed="form.accepts_orders"
                    :aria-label="t('restaurant.accepts_orders')"
                    @click="form.accepts_orders = !form.accepts_orders"
                ></button>
            </div>

            <div class="set-grid-sm">
                <div class="set-field">
                    <span class="label">{{ t('restaurant.delivery_time') }}</span>
                    <div class="flex items-center gap-2">
                        <input v-model.number="form.delivery_time_min" type="number" min="0" max="1440" class="input" :placeholder="t('restaurant.delivery_from')" dir="ltr" />
                        <span style="color:var(--muted)">–</span>
                        <input v-model.number="form.delivery_time_max" type="number" min="0" max="1440" class="input" :placeholder="t('restaurant.delivery_to')" dir="ltr" />
                    </div>
                    <FormError :errors="errors" field="delivery_time_min" />
                    <FormError :errors="errors" field="delivery_time_max" />
                </div>
                <label class="set-field">
                    <span class="label">{{ t('restaurant.minimum_order') }}</span>
                    <input v-model="form.minimum_order" type="number" min="0" step="0.01" class="input" dir="ltr"
                        :placeholder="t('restaurant.minimum_order_placeholder')" />
                    <FormError :errors="errors" field="minimum_order" />
                </label>
            </div>

            <label class="set-field">
                <span class="label">{{ t('restaurant.timezone') }}</span>
                <select v-model="form.timezone" class="input" dir="ltr">
                    <option v-for="tz in timezoneOptions" :key="tz" :value="tz">{{ tz }}</option>
                </select>
                <p class="set-inset-hint" style="margin-top: 6px">
                    {{ t('restaurant.timezone_hint') }}
                    <template v-if="timezoneNow"> — {{ t('restaurant.timezone_now', { time: timezoneNow }) }}</template>
                </p>
                <FormError :errors="errors" field="timezone" />
            </label>

            <div class="set-grid-sm">
                <ImageUploader v-model="form.logo_url" folder="logos" :label="t('restaurant.logo')" :disabled="!canUpdate" />
                <ImageUploader v-model="form.cover_image_url" folder="covers" :label="t('restaurant.cover_image')" :disabled="!canUpdate" />
            </div>

            <div class="set-field" style="gap: 10px">
                <div>
                    <span class="label">{{ t('restaurant.social_links') }}</span>
                    <p class="set-inset-hint">{{ t('restaurant.social_hint') }}</p>
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
            </div>
        </form>

        <!-- Change password — deliberately its own card and its own endpoint,
             and not disabled when the restaurant is read-only: a lapsed
             subscription must not lock someone out of their own password. -->
        <form class="set-card" @submit.prevent="changePassword">
            <div class="set-card-head">
                <div class="set-card-head-text">
                    <span class="set-card-title">{{ t('profile.change_password') }}</span>
                    <span class="set-card-desc">{{ t('profile.change_password_sub') }}</span>
                </div>
                <span v-if="pwSaved" class="set-chip set-chip-green" style="margin-inline-start:auto"><span class="dot"></span>{{ t('profile.password_changed') }}</span>
            </div>

            <div class="set-form">
                <label class="set-field" style="max-width: 340px">
                    <span class="label">{{ t('profile.current_password') }}</span>
                    <input v-model="pw.current_password" type="password" dir="ltr" autocomplete="current-password" class="input" />
                    <FormError :errors="pwErrors" field="current_password" />
                </label>

                <div class="set-grid-sm">
                    <label class="set-field">
                        <span class="label">{{ t('profile.new_password') }}</span>
                        <input v-model="pw.password" type="password" dir="ltr" autocomplete="new-password" class="input" />
                        <span class="set-inset-hint" style="margin-top: 6px">{{ t('profile.password_rule') }}</span>
                        <FormError :errors="pwErrors" field="password" />
                    </label>
                    <label class="set-field">
                        <span class="label">{{ t('profile.confirm_password') }}</span>
                        <input v-model="pw.password_confirmation" type="password" dir="ltr" autocomplete="new-password" class="input" />
                        <FormError :errors="pwErrors" field="password_confirmation" />
                    </label>
                </div>
            </div>

            <div class="set-card-foot">
                <button type="submit" class="set-btn-primary" :disabled="pwSaving">{{ pwSaving ? t('common.saving') : t('profile.change_password') }}</button>
            </div>
        </form>
    </template>
</template>

<style scoped>
.social-ico {
    font-size: 20px;
    width: 24px;
    text-align: center;
    flex: none;
}
</style>
