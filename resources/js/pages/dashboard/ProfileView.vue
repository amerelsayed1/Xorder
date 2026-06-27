<script setup>
import { reactive, ref, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import api, { ensureCsrf } from '../../lib/api'
import ImageUploader from '../../components/ImageUploader.vue'
import FormError from '../../components/FormError.vue'

const { t } = useI18n()
const form = reactive({
    name_en: '', name_ar: '', description_en: '', description_ar: '',
    phone: '', whatsapp_number: '', address: '', opening_hours: '',
    logo_url: '', cover_image_url: '', brand_color: '#b8431f', secondary_color: '', default_language: 'ar',
})
const errors = ref({})
const saved = ref(false)
const saving = ref(false)

onMounted(async () => {
    const { data } = await api.get('api/dashboard/restaurant')
    Object.assign(form, { ...data.data, secondary_color: data.data.secondary_color || '' })
})

async function submit() {
    errors.value = {}; saved.value = false; saving.value = true
    try {
        await ensureCsrf()
        await api.put('api/dashboard/restaurant', form)
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
                <p class="page-sub">How your restaurant appears on the public menu.</p>
            </div>
            <span v-if="saved" class="badge badge-green"><span class="dot"></span>Saved</span>
        </div>

        <div class="card p-6 space-y-5">
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <label class="block"><span class="label">{{ t('common.name_en') }}</span>
                    <input v-model="form.name_en" class="input" />
                    <FormError :errors="errors" field="name_en" /></label>
                <label class="block" dir="rtl"><span class="label">{{ t('common.name_ar') }}</span>
                    <input v-model="form.name_ar" class="input" /></label>
            </div>
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <label class="block"><span class="label">{{ t('common.description_en') }}</span>
                    <textarea v-model="form.description_en" rows="2" class="input"></textarea></label>
                <label class="block" dir="rtl"><span class="label">{{ t('common.description_ar') }}</span>
                    <textarea v-model="form.description_ar" rows="2" class="input"></textarea></label>
            </div>
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <label class="block"><span class="label">{{ t('restaurant.phone') }}</span>
                    <input v-model="form.phone" class="input" /></label>
                <label class="block"><span class="label">{{ t('restaurant.whatsapp') }}</span>
                    <input v-model="form.whatsapp_number" class="input" /></label>
            </div>
            <label class="block"><span class="label">{{ t('restaurant.address') }}</span>
                <input v-model="form.address" class="input" /></label>
            <label class="block"><span class="label">Opening hours</span>
                <input v-model="form.opening_hours" class="input" /></label>

            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <ImageUploader v-model="form.logo_url" folder="logos" label="Logo" />
                <ImageUploader v-model="form.cover_image_url" folder="covers" label="Cover image" />
            </div>

            <div class="grid grid-cols-3 gap-4 items-end">
                <label class="block"><span class="label">{{ t('restaurant.brand_color') }}</span>
                    <input v-model="form.brand_color" type="color" class="mt-1.5 w-full h-11 rounded-lg border cursor-pointer" style="border-color:var(--line)" /></label>
                <label class="block"><span class="label">{{ t('restaurant.secondary_color') }}</span>
                    <input v-model="form.secondary_color" type="color" class="mt-1.5 w-full h-11 rounded-lg border cursor-pointer" style="border-color:var(--line)" /></label>
                <label class="block"><span class="label">{{ t('restaurant.language') }}</span>
                    <select v-model="form.default_language" class="input">
                        <option value="ar">العربية</option><option value="en">English</option>
                    </select></label>
            </div>
        </div>

        <button type="submit" :disabled="saving" class="btn btn-accent">{{ saving ? '…' : t('common.save') }}</button>
    </form>
</template>
