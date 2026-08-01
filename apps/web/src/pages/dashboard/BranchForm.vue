<script setup>
import { reactive, ref, computed, onMounted, watch, nextTick } from 'vue'
import { useRoute, useRouter, RouterLink } from 'vue-router'
import { useI18n } from 'vue-i18n'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import { collectPhoneErrors } from '../../lib/phone.js'
import FormError from '@xorder/ui/FormError.vue'
import Icon from '@xorder/ui/Icon.vue'
import Skeleton from '@xorder/ui/Skeleton.vue'
import { useAuth } from '@xorder/api-client/auth.js'
import { useMenuLang } from '../../lib/menuLang.js'
import BusinessHoursEditor from '../../components/BusinessHoursEditor.vue'
import GeofenceMap from '../../components/GeofenceMap.vue'

const route = useRoute()
const router = useRouter()
const { t, locale } = useI18n()
const auth = useAuth()
// Render only the language name fields the client is configured for (single
// default-language field when not bilingual), matching the item/category forms.
const { langs, bilingual } = useMenuLang()

const isEdit = computed(() => !!route.params.id)
const backArrow = computed(() => locale.value === 'ar' ? '→' : '←')

const loading = ref(true)
const saving = ref(false)
const errors = ref({})
const blank = () => ({ name_en: '', name_ar: '', address: '', phone: '', whatsapp_number: '', opening_hours: '', business_hours: {}, map_url: '', latitude: null, longitude: null, geofence: null, geofence_enabled: false, is_open: true, is_active: true })
const form = reactive(blank())

// A fence the backend would enforce: a radius with a real centre + positive
// radius, or a polygon of >= 3 vertices (mirrors App\Support\GeoFence::isEnforceable).
function fenceEnforceable(f) {
    if (!f || typeof f !== 'object') return false
    if (f.type === 'radius') return !!f.center && f.center.lat != null && f.center.lng != null && Number(f.radius) > 0
    const pts = Array.isArray(f.points) ? f.points : (Array.isArray(f) ? f : [])
    return pts.length >= 3
}

// While a branch is loaded into the form we assign the fence programmatically;
// suppress the auto-enable during that so we never override the saved state.
let hydrating = false
// True when the branch already had an enforceable fence on open — its saved
// enabled/disabled choice is authoritative, so we don't auto-flip it.
let fenceExistedOnOpen = false
// True once the admin clicks the toggle this session — an explicit choice we honour.
let geofenceToggledManually = false

// Table-ordering venues are on-premise, so the first time an admin draws a fence
// we default presence-enforcement ON (opt-out). Gated to clients that actually
// run table ordering, and never applied to an existing fence or after the admin
// has made an explicit toggle choice.
watch(() => form.geofence, () => {
    if (hydrating || fenceExistedOnOpen || geofenceToggledManually) return
    if (!auth.hasFeature('table_management')) return
    if (fenceEnforceable(form.geofence)) form.geofence_enabled = true
}, { deep: true })

function toggleGeofence() {
    geofenceToggledManually = true
    form.geofence_enabled = !form.geofence_enabled
}

onMounted(async () => {
    hydrating = true
    if (isEdit.value) {
        try {
            // No single-resource endpoint exists (branches only exposes index),
            // so load the list and pick our branch out of it.
            const { data } = await api.get('api/dashboard/branches')
            const b = (data.data || []).find((x) => String(x.id) === String(route.params.id))
            if (b) Object.assign(form, blank(), {
                name_en: b.name_en || '', name_ar: b.name_ar || '', address: b.address || '',
                phone: b.phone || '', whatsapp_number: b.whatsapp_number || '',
                opening_hours: b.opening_hours || '', business_hours: b.business_hours || {}, map_url: b.map_url || '',
                latitude: b.latitude ?? null, longitude: b.longitude ?? null,
                geofence: b.geofence || null, geofence_enabled: !!b.geofence_enabled,
                is_open: b.is_open, is_active: b.is_active,
            })
            fenceExistedOnOpen = fenceEnforceable(form.geofence)
        } catch (err) { /* fall through to blank form */ }
    }
    loading.value = false
    nextTick(() => { hydrating = false })
})

function backToList() { router.push({ name: 'dashboard.branches' }) }

async function save() {
    if (saving.value) return // guard against double-submit (double-click)
    errors.value = {}
    const phoneErrors = collectPhoneErrors(
        { phone: form.phone, whatsapp_number: form.whatsapp_number },
        t('restaurant.phone_invalid'),
    )
    if (Object.keys(phoneErrors).length) { errors.value = phoneErrors; return }
    saving.value = true
    try {
        await ensureCsrf()
        if (isEdit.value) await api.put(`api/dashboard/branches/${route.params.id}`, form)
        else await api.post('api/dashboard/branches', form)
        backToList()
    } catch (err) { errors.value = err.response?.data?.errors || {} }
    finally { saving.value = false }
}
</script>

<template>
    <div class="max-w-2xl">
        <RouterLink :to="{ name: 'dashboard.branches' }" class="text-sm" style="color:var(--muted)">{{ backArrow }} {{ t('common.back') }}</RouterLink>
        <h1 class="page-title my-3">{{ isEdit ? t('branch.edit') : t('branch.new') }}</h1>

        <div v-if="loading" class="card p-6 space-y-4">
            <Skeleton class="h-10 w-full" />
            <Skeleton class="h-10 w-full" />
            <Skeleton class="h-40 w-full" />
        </div>

        <form v-else @submit.prevent="save" class="space-y-5">
            <div class="card p-6 space-y-4">
                <div class="grid grid-cols-1 gap-3" :class="{ 'sm:grid-cols-2': bilingual }">
                    <label v-for="lng in langs" :key="'n' + lng" class="block" :dir="lng === 'ar' ? 'rtl' : 'ltr'">
                        <span class="label">{{ bilingual ? t('common.name_' + lng) : t('common.name') }}</span>
                        <input v-model="form['name_' + lng]" class="input" />
                        <FormError :errors="errors" :field="'name_' + lng" /></label>
                </div>
                <label class="block"><span class="label">{{ t('restaurant.address') }}</span>
                    <textarea v-model="form.address" rows="2" class="input"></textarea>
                    <FormError :errors="errors" field="address" /></label>
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                    <label class="block"><span class="label">{{ t('restaurant.phone') }}</span>
                        <input v-model="form.phone" class="input" dir="ltr" data-en-digits />
                        <FormError :errors="errors" field="phone" /></label>
                    <label class="block"><span class="label">{{ t('restaurant.whatsapp') }}</span>
                        <input v-model="form.whatsapp_number" class="input" dir="ltr" data-en-digits />
                        <FormError :errors="errors" field="whatsapp_number" /></label>
                </div>
                <div class="block">
                    <span class="label">{{ t('restaurant.business_hours') }}</span>
                    <p class="page-sub" style="margin:2px 0 8px">{{ t('restaurant.business_hours_hint') }}</p>
                    <BusinessHoursEditor v-model="form.business_hours" :disabled="auth.isReadOnly" />
                </div>
                <label class="block"><span class="label">{{ t('branch.map_url') }}</span>
                    <input v-model="form.map_url" class="input" dir="ltr" placeholder="https://maps.google.com/…" />
                    <FormError :errors="errors" field="map_url" /></label>

                <!-- Presence geofence: draw the branch area; the toggle turns on
                     the on-site check for table-QR ordering. -->
                <div class="block">
                    <label class="flex items-center gap-2 text-sm" style="color:var(--body)">
                        <button type="button" class="switch" :class="{ on: form.geofence_enabled }" :disabled="auth.isReadOnly" @click="toggleGeofence"></button>
                        {{ t('branch.geofence_enable') }}
                    </label>
                    <p class="page-sub" style="margin:4px 0 8px">{{ t('branch.geofence_enable_hint') }}</p>
                    <GeofenceMap v-model="form.geofence" :center="{ lat: form.latitude, lng: form.longitude }" :disabled="auth.isReadOnly" />
                    <FormError :errors="errors" field="geofence" />
                </div>

                <div class="flex items-center gap-6">
                    <label class="flex items-center gap-2 text-sm" style="color:var(--body)">
                        <button type="button" class="switch" :class="{ on: form.is_open }" @click="form.is_open = !form.is_open"></button>
                        {{ t('branch.open') }}
                    </label>
                    <label class="flex items-center gap-2 text-sm" style="color:var(--body)">
                        <button type="button" class="switch" :class="{ on: form.is_active }" @click="form.is_active = !form.is_active"></button>
                        {{ t('common.active') }}
                    </label>
                </div>
            </div>

            <div class="flex justify-end gap-2">
                <RouterLink :to="{ name: 'dashboard.branches' }" class="btn btn-ghost">{{ t('common.cancel') }}</RouterLink>
                <button type="submit" :disabled="saving || auth.isReadOnly" class="btn btn-accent">
                    <Icon v-if="saving" name="loading" :size="16" class="animate-spin" />
                    {{ saving ? t('common.saving') : t('common.save') }}
                </button>
            </div>
        </form>
    </div>
</template>
