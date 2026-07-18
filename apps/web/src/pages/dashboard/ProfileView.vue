<script setup>
import { reactive, ref, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import ImageUploader from '@xorder/ui/ImageUploader.vue'
import FormError from '@xorder/ui/FormError.vue'
import { useMenuLang } from '../../lib/menuLang.js'

const { t } = useI18n()
const { langs, bilingual } = useMenuLang()
const form = reactive({
    name_en: '', name_ar: '', description_en: '', description_ar: '',
    phone: '', whatsapp_number: '', address: '', opening_hours: '',
    logo_url: '', cover_image_url: '', brand_color: '#f89a06', secondary_color: '', default_language: 'ar',
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
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <label class="block"><span class="label">{{ t('restaurant.phone') }}</span>
                    <input v-model="form.phone" class="input" /></label>
                <label class="block"><span class="label">{{ t('restaurant.whatsapp') }}</span>
                    <input v-model="form.whatsapp_number" class="input" /></label>
            </div>
            <label class="block"><span class="label">{{ t('restaurant.address') }}</span>
                <input v-model="form.address" class="input" /></label>
            <label class="block"><span class="label">{{ t('restaurant.opening_hours') }}</span>
                <input v-model="form.opening_hours" class="input" /></label>

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
                    <select v-model="form.default_language" class="input">
                        <option value="ar">{{ t('languages.ar') }}</option><option value="en">{{ t('languages.en') }}</option>
                    </select></label>
            </div>
        </div>

        <button type="submit" :disabled="saving" class="btn btn-accent">{{ saving ? t('common.saving') : t('common.save') }}</button>
    </form>
</template>
