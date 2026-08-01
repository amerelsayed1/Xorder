<script setup>
import { reactive, ref, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import ImageUploader from '@xorder/ui/ImageUploader.vue'
import FormError from '@xorder/ui/FormError.vue'
import ErrorState from '@xorder/ui/ErrorState.vue'
import { useMenuLang } from '../../lib/menuLang.js'
import { collectPhoneErrors } from '../../lib/phone.js'
import { useAuth } from '@xorder/api-client/auth.js'

const { t } = useI18n()
const auth = useAuth()
const { langs, bilingual } = useMenuLang()
const form = reactive({
    name_en: '', name_ar: '', description_en: '', description_ar: '',
    phone: '', whatsapp_number: '', address: '', opening_hours: '',
    business_hours: {}, delivery_time_min: null, delivery_time_max: null,
    minimum_order: '', latitude: '', longitude: '',
    logo_url: '', cover_image_url: '',
    social_links: { instagram: '', facebook: '', tiktok: '' },
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
    <div v-if="loading" class="space-y-5 max-w-3xl">
        <div class="h-8 w-48 rounded-lg" style="background:var(--line)"></div>
        <div class="card" style="height:280px"></div>
        <div class="card" style="height:200px"></div>
    </div>

    <ErrorState v-else-if="loadError" @retry="load" />

    <template v-else>
    <form @submit.prevent="submit" class="space-y-5 max-w-3xl">
        <div class="flex items-center justify-between">
            <div>
                <h1 class="page-title">{{ t('nav.profile') }}</h1>
                <p class="page-sub">{{ t('profile.subtitle') }}</p>
            </div>
            <span v-if="saved" class="badge badge-green"><span class="dot"></span>{{ t('common.saved') }}</span>
        </div>

        <div class="card p-6 space-y-5">
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <label v-for="lng in langs" :key="'n' + lng" class="block" :dir="lng === 'ar' ? 'rtl' : 'ltr'">
                    <span class="label">{{ bilingual ? t('common.name_' + lng) : t('common.name') }}</span>
                    <input v-model="form['name_' + lng]" class="input" />
                    <FormError :errors="errors" :field="'name_' + lng" /></label>
            </div>
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <label v-for="lng in langs" :key="'d' + lng" class="block" :dir="lng === 'ar' ? 'rtl' : 'ltr'">
                    <span class="label">{{ bilingual ? t('common.description_' + lng) : t('common.description') }}</span>
                    <textarea v-model="form['description_' + lng]" rows="2" class="input"></textarea></label>
            </div>
            <!-- Phone, address, and working hours are configured per-branch
                 (every client has at least one branch). Only the WhatsApp
                 ordering number — one per menu — stays at restaurant level. -->
            <label class="block"><span class="label">{{ t('restaurant.whatsapp') }}</span>
                <input v-model="form.whatsapp_number" class="input" dir="ltr" data-en-digits />
                <FormError :errors="errors" field="whatsapp_number" /></label>

            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div class="block">
                    <span class="label">{{ t('restaurant.delivery_time') }}</span>
                    <div class="flex items-center gap-2 mt-1.5">
                        <input v-model.number="form.delivery_time_min" type="number" min="0" max="1440" class="input" :placeholder="t('restaurant.delivery_from')" dir="ltr" />
                        <span style="color:var(--muted)">–</span>
                        <input v-model.number="form.delivery_time_max" type="number" min="0" max="1440" class="input" :placeholder="t('restaurant.delivery_to')" dir="ltr" />
                    </div>
                    <FormError :errors="errors" field="delivery_time_min" />
                    <FormError :errors="errors" field="delivery_time_max" />
                </div>
                <label class="block"><span class="label">{{ t('restaurant.minimum_order') }}</span>
                    <input v-model="form.minimum_order" type="number" min="0" step="0.01" class="input" dir="ltr" />
                    <FormError :errors="errors" field="minimum_order" /></label>
            </div>

            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <ImageUploader v-model="form.logo_url" folder="logos" :label="t('restaurant.logo')" :disabled="auth.isReadOnly" />
                <ImageUploader v-model="form.cover_image_url" folder="covers" :label="t('restaurant.cover_image')" :disabled="auth.isReadOnly" />
            </div>

            <div class="block">
                <span class="label">{{ t('restaurant.social_links') }}</span>
                <p class="page-sub" style="margin:2px 0 8px">{{ t('restaurant.social_hint') }}</p>
                <div class="flex flex-col gap-3">
                    <label class="flex items-center gap-3">
                        <i class="pi pi-instagram social-ico" style="color:#e4405f" aria-hidden="true"></i>
                        <span class="flex-1 min-w-0">
                            <input v-model="form.social_links.instagram" type="url" dir="ltr" aria-label="Instagram" placeholder="https://instagram.com/…" class="input" />
                            <FormError :errors="errors" field="social_links.instagram" />
                        </span>
                    </label>
                    <label class="flex items-center gap-3">
                        <i class="pi pi-facebook social-ico" style="color:#1877f2" aria-hidden="true"></i>
                        <span class="flex-1 min-w-0">
                            <input v-model="form.social_links.facebook" type="url" dir="ltr" aria-label="Facebook" placeholder="https://facebook.com/…" class="input" />
                            <FormError :errors="errors" field="social_links.facebook" />
                        </span>
                    </label>
                    <label class="flex items-center gap-3">
                        <i class="pi pi-tiktok social-ico" style="color:var(--ink)" aria-hidden="true"></i>
                        <span class="flex-1 min-w-0">
                            <input v-model="form.social_links.tiktok" type="url" dir="ltr" aria-label="TikTok" placeholder="https://tiktok.com/@…" class="input" />
                            <FormError :errors="errors" field="social_links.tiktok" />
                        </span>
                    </label>
                </div>
            </div>

        </div>

        <button type="submit" :disabled="saving || auth.isReadOnly" class="btn btn-accent">{{ saving ? t('common.saving') : t('common.save') }}</button>
    </form>

    <!-- Change password — deliberately its own form (own endpoint), and not
         disabled when the restaurant is read-only. -->
    <form @submit.prevent="changePassword" class="space-y-5 max-w-3xl mt-8">
        <div class="flex items-center justify-between">
            <div>
                <h2 class="page-title" style="font-size:1.25rem">{{ t('profile.change_password') }}</h2>
                <p class="page-sub">{{ t('profile.change_password_sub') }}</p>
            </div>
            <span v-if="pwSaved" class="badge badge-green"><span class="dot"></span>{{ t('profile.password_changed') }}</span>
        </div>

        <div class="card p-6 space-y-4">
            <label class="block">
                <span class="label">{{ t('profile.current_password') }}</span>
                <input v-model="pw.current_password" type="password" dir="ltr" autocomplete="current-password" class="input" />
                <FormError :errors="pwErrors" field="current_password" />
            </label>

            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <label class="block">
                    <span class="label">{{ t('profile.new_password') }}</span>
                    <input v-model="pw.password" type="password" dir="ltr" autocomplete="new-password" class="input" />
                    <span class="block text-xs mt-1" style="color:var(--muted)">{{ t('profile.password_rule') }}</span>
                    <FormError :errors="pwErrors" field="password" />
                </label>
                <label class="block">
                    <span class="label">{{ t('profile.confirm_password') }}</span>
                    <input v-model="pw.password_confirmation" type="password" dir="ltr" autocomplete="new-password" class="input" />
                    <FormError :errors="pwErrors" field="password_confirmation" />
                </label>
            </div>
        </div>

        <button type="submit" :disabled="pwSaving" class="btn btn-accent">{{ pwSaving ? t('common.saving') : t('profile.change_password') }}</button>
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
