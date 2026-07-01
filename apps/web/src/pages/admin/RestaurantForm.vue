<script setup>
import { reactive, ref, computed, onMounted } from 'vue'
import { useRoute, useRouter, RouterLink } from 'vue-router'
import { useI18n } from 'vue-i18n'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import ImageUploader from '@xorder/ui/ImageUploader.vue'
import FormError from '@xorder/ui/FormError.vue'
import { publicOrigin } from '../../lib/host.js'

const route = useRoute()
const router = useRouter()
const { t, locale } = useI18n()

const isEdit = computed(() => !!route.params.id)
const backArrow = computed(() => locale.value === 'ar' ? '→' : '←')
const forwardArrow = computed(() => locale.value === 'ar' ? '←' : '→')
const slugPrefix = `${publicOrigin()}/r/`
const form = reactive({
    name_en: '', name_ar: '', slug: '',
    description_en: '', description_ar: '',
    phone: '', whatsapp_number: '', address: '', opening_hours: '',
    logo_url: '', cover_image_url: '',
    brand_color: '#f89a06', secondary_color: '',
    default_language: 'en',
    bilingual: true,
    currency: 'EGP',
    ordering_enabled: true,
    status: 'ACTIVE', subscription_status: 'TRIAL',
    admin: { name: '', email: '', password: '' },
})
const currencies = [
    { code: 'EGP', label: 'EGP — Egyptian Pound' },
    { code: 'SAR', label: 'SAR — Saudi Riyal' },
    { code: 'AED', label: 'AED — UAE Dirham' },
    { code: 'USD', label: 'USD — US Dollar' },
    { code: 'KWD', label: 'KWD — Kuwaiti Dinar' },
    { code: 'QAR', label: 'QAR — Qatari Riyal' },
    { code: 'BHD', label: 'BHD — Bahraini Dinar' },
    { code: 'OMR', label: 'OMR — Omani Rial' },
    { code: 'JOD', label: 'JOD — Jordanian Dinar' },
    { code: 'EUR', label: 'EUR — Euro' },
    { code: 'GBP', label: 'GBP — British Pound' },
]
const errors = ref({})
const saving = ref(false)
const generatedPassword = ref('')
const slugTouched = ref(false)

onMounted(async () => {
    if (isEdit.value) {
        const { data } = await api.get(`api/admin/restaurants/${route.params.id}`)
        Object.assign(form, { ...data.data, secondary_color: data.data.secondary_color || '' })
    }
})

function autoSlug() {
    if (!isEdit.value && !slugTouched.value) {
        form.slug = (form.name_en || '').toLowerCase().trim()
            .replace(/[^a-z0-9\s-]/g, '').replace(/\s+/g, '-').replace(/-+/g, '-')
    }
}
function generatePassword() {
    const chars = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'
    form.admin.password = Array.from(crypto.getRandomValues(new Uint8Array(14))).map(b => chars[b % chars.length]).join('')
}

async function submit() {
    errors.value = {}; saving.value = true
    try {
        await ensureCsrf()
        if (isEdit.value) {
            const payload = { ...form }; delete payload.admin
            await api.put(`api/admin/restaurants/${route.params.id}`, payload)
            router.push({ name: 'admin.restaurants.show', params: { id: route.params.id } })
        } else {
            const { data } = await api.post('api/admin/restaurants', form)
            if (data.generated_password) generatedPassword.value = data.generated_password
            else router.push({ name: 'admin.restaurants.show', params: { id: data.data.id } })
        }
    } catch (err) {
        errors.value = err.response?.data?.errors || {}
    } finally {
        saving.value = false
    }
}
</script>

<template>
    <div class="max-w-2xl">
        <RouterLink :to="{ name: 'admin.restaurants' }" class="text-sm" style="color:var(--muted)">{{ backArrow }} {{ t('common.back') }}</RouterLink>
        <h1 class="page-title my-3">{{ isEdit ? t('admin.edit_restaurant') : t('admin.create_restaurant') }}</h1>

        <!-- Generated password banner -->
        <div v-if="generatedPassword" class="card p-5 mb-4" style="border-color:var(--green);background:var(--green-soft)">
            <p class="font-medium" style="color:var(--green)">{{ t('restaurant.generated_password') }}</p>
            <p class="mono text-2xl mt-1" style="color:var(--ink)">{{ generatedPassword }}</p>
            <p class="text-sm mt-1" style="color:var(--green)">{{ t('restaurant.generated_password_note') }}</p>
            <RouterLink :to="{ name: 'admin.restaurants' }" class="btn btn-dark mt-3">{{ t('common.done') }} {{ forwardArrow }}</RouterLink>
        </div>

        <form v-if="!generatedPassword" @submit.prevent="submit" class="space-y-5">
            <!-- Restaurant -->
            <div class="card p-6 space-y-4">
                <h2 class="h-card">{{ t('admin.restaurant') }}</h2>
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                    <label class="block"><span class="label">{{ t('common.name_en') }}</span>
                        <input v-model="form.name_en" @input="autoSlug" class="input" />
                        <FormError :errors="errors" field="name_en" /></label>
                    <label class="block" dir="rtl"><span class="label">{{ t('common.name_ar') }}</span>
                        <input v-model="form.name_ar" class="input" /></label>
                </div>
                <label class="block"><span class="label">{{ t('restaurant.slug') }}</span>
                    <div class="flex items-center mt-1.5 rounded-lg border overflow-hidden" style="border-color:var(--line)">
                        <span class="mono text-sm px-3 py-2.5" style="background:var(--page);color:var(--muted)">{{ slugPrefix }}</span>
                        <input v-model="form.slug" @input="slugTouched = true" class="flex-1 px-3 py-2.5 text-sm mono" style="border:0;outline:0;background:var(--card);color:var(--ink)" />
                    </div>
                    <p v-if="isEdit" class="text-xs mt-1" style="color:var(--amber)">{{ t('restaurant.slug_warning') }}</p>
                    <FormError :errors="errors" field="slug" /></label>
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                    <label class="block"><span class="label">{{ t('restaurant.phone') }}</span><input v-model="form.phone" class="input" /></label>
                    <label class="block"><span class="label">{{ t('restaurant.whatsapp') }}</span><input v-model="form.whatsapp_number" class="input" /></label>
                </div>
                <label class="block"><span class="label">{{ t('restaurant.address') }}</span><input v-model="form.address" class="input" /></label>
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                    <ImageUploader v-model="form.logo_url" folder="logos" :label="t('restaurant.logo')" />
                    <ImageUploader v-model="form.cover_image_url" folder="covers" :label="t('restaurant.cover_image')" />
                </div>
                <div class="grid grid-cols-3 gap-4 items-end">
                    <label class="block"><span class="label">{{ t('restaurant.brand_color') }}</span>
                        <input v-model="form.brand_color" type="color" class="mt-1.5 w-full h-11 rounded-lg border cursor-pointer" style="border-color:var(--line)" /></label>
                    <label class="block"><span class="label">{{ t('restaurant.secondary_color') }}</span>
                        <input v-model="form.secondary_color" type="color" class="mt-1.5 w-full h-11 rounded-lg border cursor-pointer" style="border-color:var(--line)" /></label>
                    <label class="block"><span class="label">{{ t('restaurant.language') }}</span>
                        <select v-model="form.default_language" class="input"><option value="en">{{ t('languages.en') }}</option><option value="ar">{{ t('languages.ar') }}</option></select></label>
                    <label class="block"><span class="label">{{ t('restaurant.currency') }}</span>
                        <select v-model="form.currency" class="input">
                            <option v-for="c in currencies" :key="c.code" :value="c.code">{{ c.label }}</option>
                        </select>
                        <FormError :errors="errors" field="currency" /></label>
                </div>
                <label class="flex items-start gap-3 rounded-lg border p-3 cursor-pointer" style="border-color:var(--line)">
                    <input v-model="form.bilingual" type="checkbox" class="mt-0.5 h-4 w-4" />
                    <span>
                        <span class="label" style="margin:0">{{ t('restaurant.bilingual') }}</span>
                        <span class="block text-xs mt-0.5" style="color:var(--muted)">{{ t('restaurant.bilingual_hint') }}</span>
                    </span>
                </label>
                <label class="flex items-start gap-3 rounded-lg border p-3 cursor-pointer" style="border-color:var(--line)">
                    <input v-model="form.ordering_enabled" type="checkbox" class="mt-0.5 h-4 w-4" />
                    <span>
                        <span class="label" style="margin:0">{{ t('restaurant.ordering_enabled') }}</span>
                        <span class="block text-xs mt-0.5" style="color:var(--muted)">{{ t('restaurant.ordering_enabled_hint') }}</span>
                    </span>
                </label>
            </div>

            <!-- First admin (create only) -->
            <div v-if="!isEdit" class="card p-6 space-y-4">
                <h2 class="h-card">{{ t('admin.first_restaurant_admin') }}</h2>
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                    <label class="block"><span class="label">{{ t('restaurant.admin_name') }}</span>
                        <input v-model="form.admin.name" class="input" />
                        <FormError :errors="errors" field="admin.name" /></label>
                    <label class="block"><span class="label">{{ t('restaurant.admin_email') }}</span>
                        <input v-model="form.admin.email" type="email" class="input" />
                        <FormError :errors="errors" field="admin.email" /></label>
                </div>
                <label class="block"><span class="label">{{ t('restaurant.admin_password') }}</span>
                    <div class="flex gap-2 mt-1.5">
                        <input v-model="form.admin.password" type="text" class="input" style="margin-top:0" :placeholder="t('restaurant.password_hint')" />
                        <button type="button" @click="generatePassword" class="btn btn-ghost whitespace-nowrap">{{ t('admin.generate_password') }}</button>
                    </div>
                    <FormError :errors="errors" field="admin.password" /></label>
            </div>

            <div class="flex justify-end gap-2">
                <RouterLink :to="{ name: 'admin.restaurants' }" class="btn btn-ghost">{{ t('common.cancel') }}</RouterLink>
                <button type="submit" :disabled="saving" class="btn btn-accent">
                    {{ saving ? t('common.saving') : (isEdit ? t('admin.save_changes') : t('admin.create_restaurant_admin')) }}
                </button>
            </div>
        </form>
    </div>
</template>
