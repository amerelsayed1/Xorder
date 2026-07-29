<script setup>
import { reactive, ref, computed, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import ImageUploader from '@xorder/ui/ImageUploader.vue'
import FormError from '@xorder/ui/FormError.vue'
import { useMenuLang } from '../../lib/menuLang.js'
import { collectPhoneErrors } from '../../lib/phone.js'
import { resolveMapLink, mapsUrl } from '../../lib/mapLink.js'
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
    ordering_mode: 'both',
    social_links: { instagram: '', facebook: '', tiktok: '' },
})
const errors = ref({})
const saved = ref(false)
const saving = ref(false)

// --- Map location, entered as a Google Maps link ---
// The owner pastes a link; we resolve it to latitude/longitude (still what the
// menu's map + directions button consume). The link itself isn't stored.
const mapUrl = ref('')
const mapStatus = ref('idle') // 'idle' | 'resolving' | 'error'
const coordsSet = computed(() => {
    const lat = Number(form.latitude), lng = Number(form.longitude)
    return form.latitude !== '' && form.latitude != null
        && form.longitude !== '' && form.longitude != null
        && Number.isFinite(lat) && Number.isFinite(lng)
})
const coordsPreviewUrl = computed(() => coordsSet.value ? mapsUrl(form.latitude, form.longitude) : '')

async function resolveMap() {
    const text = mapUrl.value.trim()
    if (!text) { mapStatus.value = coordsSet.value ? 'idle' : 'idle'; return }
    mapStatus.value = 'resolving'
    const coords = await resolveMapLink(text)
    if (coords) {
        form.latitude = coords.latitude
        form.longitude = coords.longitude
        mapUrl.value = ''          // tidy the field; the resolved pin shows below
        mapStatus.value = 'idle'
        delete errors.value.latitude; delete errors.value.longitude
    } else {
        mapStatus.value = 'error'
    }
}

function clearCoords() {
    form.latitude = ''
    form.longitude = ''
    mapUrl.value = ''
    mapStatus.value = 'idle'
}
// Ordering channels the restaurant's plan grants; the selector is capped to these.
const orderingModeOptions = ref([])

onMounted(async () => {
    const { data } = await api.get('api/dashboard/restaurant')
    Object.assign(form, {
        ...data.data,
        // The API sends {} when nothing is set — keep every known field present
        // so the inputs stay controlled.
        social_links: { instagram: '', facebook: '', tiktok: '', ...(data.data.social_links || {}) },
    })
    orderingModeOptions.value = data.data.available_ordering_modes || []
    if (orderingModeOptions.value.length && !orderingModeOptions.value.includes(form.ordering_mode)) {
        form.ordering_mode = orderingModeOptions.value[0]
    }
})

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
</script>

<template>
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
                <input v-model="form.whatsapp_number" class="input" dir="ltr" />
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

            <div class="block">
                <span class="label">{{ t('restaurant.map_location') }}</span>
                <p class="page-sub" style="margin:2px 0 8px">{{ t('restaurant.map_link_hint') }}</p>
                <label class="block">
                    <span class="label">{{ t('restaurant.map_link') }}</span>
                    <input v-model="mapUrl" @change="resolveMap" @blur="resolveMap"
                        @keydown.enter.prevent="resolveMap" type="url" class="input" dir="ltr"
                        :placeholder="t('restaurant.map_link_placeholder')" :disabled="mapStatus === 'resolving'" />
                </label>

                <!-- Resolving spinner -->
                <p v-if="mapStatus === 'resolving'" class="text-sm" style="margin-top:6px;color:var(--muted)">
                    {{ t('restaurant.map_resolving') }}
                </p>
                <!-- Resolved / current location -->
                <p v-else-if="coordsSet" class="text-sm" style="margin-top:6px;color:var(--accent, #1f7a3d);display:flex;align-items:center;gap:8px;flex-wrap:wrap">
                    <span>📍 {{ t('restaurant.map_location_set') }}</span>
                    <span dir="ltr" style="color:var(--muted)">{{ Number(form.latitude).toFixed(6) }}, {{ Number(form.longitude).toFixed(6) }}</span>
                    <a :href="coordsPreviewUrl" target="_blank" rel="noopener" style="color:var(--accent, #1f7a3d);text-decoration:underline">{{ t('restaurant.map_preview') }}</a>
                    <button type="button" @click="clearCoords" style="color:var(--muted);text-decoration:underline;background:none;border:none;cursor:pointer;padding:0">{{ t('restaurant.map_clear') }}</button>
                </p>
                <!-- Could not resolve -->
                <p v-else-if="mapStatus === 'error'" class="text-sm" style="margin-top:6px;color:var(--red, #dc2626)">
                    {{ t('restaurant.map_link_invalid') }}
                </p>

                <FormError :errors="errors" field="latitude" />
                <FormError :errors="errors" field="longitude" />
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

            <div v-if="orderingModeOptions.length > 1" class="block">
                <span class="label">{{ t('restaurant.ordering_mode') }}</span>
                <div class="flex gap-2 mt-1.5 flex-wrap">
                    <button v-for="m in orderingModeOptions" :key="m" type="button" @click="form.ordering_mode = m"
                        class="btn" :class="form.ordering_mode === m ? 'btn-dark' : 'btn-ghost'">{{ t('restaurant.ordering_mode_' + m) }}</button>
                </div>
                <span class="block text-xs mt-1.5" style="color:var(--muted)">{{ t('restaurant.ordering_mode_hint') }}</span>
            </div>

        </div>

        <button type="submit" :disabled="saving || auth.isReadOnly" class="btn btn-accent">{{ saving ? t('common.saving') : t('common.save') }}</button>
    </form>
</template>

<style scoped>
.social-ico {
    font-size: 20px;
    width: 24px;
    text-align: center;
    flex: none;
}
</style>
