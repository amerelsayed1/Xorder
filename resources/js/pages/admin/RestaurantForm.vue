<script setup>
import { reactive, ref, computed, onMounted } from 'vue'
import { useRoute, useRouter, RouterLink } from 'vue-router'
import api, { ensureCsrf } from '../../lib/api'
import ImageUploader from '../../components/ImageUploader.vue'
import FormError from '../../components/FormError.vue'

const route = useRoute()
const router = useRouter()

const isEdit = computed(() => !!route.params.id)
const form = reactive({
    name_en: '', name_ar: '', slug: '',
    description_en: '', description_ar: '',
    phone: '', whatsapp_number: '', address: '', opening_hours: '',
    logo_url: '', cover_image_url: '',
    brand_color: '#b8431f', secondary_color: '',
    default_language: 'en',
    status: 'ACTIVE', subscription_status: 'TRIAL',
    admin: { name: '', email: '', password: '' },
})
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
        <RouterLink :to="{ name: 'admin.restaurants' }" class="text-sm" style="color:var(--muted)">← Back</RouterLink>
        <h1 class="page-title my-3">{{ isEdit ? 'Edit restaurant' : 'Create restaurant' }}</h1>

        <!-- Generated password banner -->
        <div v-if="generatedPassword" class="card p-5 mb-4" style="border-color:var(--green);background:var(--green-soft)">
            <p class="font-medium" style="color:var(--green)">Generated password</p>
            <p class="mono text-2xl mt-1" style="color:var(--ink)">{{ generatedPassword }}</p>
            <p class="text-sm mt-1" style="color:var(--green)">Copy this now — it will not be shown again.</p>
            <RouterLink :to="{ name: 'admin.restaurants' }" class="btn btn-dark mt-3">Done →</RouterLink>
        </div>

        <form v-if="!generatedPassword" @submit.prevent="submit" class="space-y-5">
            <!-- Restaurant -->
            <div class="card p-6 space-y-4">
                <h2 class="h-card">Restaurant</h2>
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                    <label class="block"><span class="label">Name (English)</span>
                        <input v-model="form.name_en" @input="autoSlug" class="input" />
                        <FormError :errors="errors" field="name_en" /></label>
                    <label class="block" dir="rtl"><span class="label">Name (Arabic)</span>
                        <input v-model="form.name_ar" class="input" /></label>
                </div>
                <label class="block"><span class="label">Slug</span>
                    <div class="flex items-center mt-1.5 rounded-lg border overflow-hidden" style="border-color:var(--line)">
                        <span class="mono text-sm px-3 py-2.5" style="background:var(--page);color:var(--muted)">qrmenu.io/r/</span>
                        <input v-model="form.slug" @input="slugTouched = true" class="flex-1 px-3 py-2.5 text-sm mono" style="border:0;outline:0;background:var(--card);color:var(--ink)" />
                    </div>
                    <p v-if="isEdit" class="text-xs mt-1" style="color:var(--amber)">⚠ Changing the slug breaks any QR codes already printed.</p>
                    <FormError :errors="errors" field="slug" /></label>
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                    <label class="block"><span class="label">Phone</span><input v-model="form.phone" class="input" /></label>
                    <label class="block"><span class="label">WhatsApp</span><input v-model="form.whatsapp_number" class="input" /></label>
                </div>
                <label class="block"><span class="label">Address</span><input v-model="form.address" class="input" /></label>
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                    <ImageUploader v-model="form.logo_url" folder="logos" label="Logo" />
                    <ImageUploader v-model="form.cover_image_url" folder="covers" label="Cover image" />
                </div>
                <div class="grid grid-cols-3 gap-4 items-end">
                    <label class="block"><span class="label">Brand color</span>
                        <input v-model="form.brand_color" type="color" class="mt-1.5 w-full h-11 rounded-lg border cursor-pointer" style="border-color:var(--line)" /></label>
                    <label class="block"><span class="label">Secondary</span>
                        <input v-model="form.secondary_color" type="color" class="mt-1.5 w-full h-11 rounded-lg border cursor-pointer" style="border-color:var(--line)" /></label>
                    <label class="block"><span class="label">Default language</span>
                        <select v-model="form.default_language" class="input"><option value="en">English</option><option value="ar">العربية</option></select></label>
                </div>
            </div>

            <!-- First admin (create only) -->
            <div v-if="!isEdit" class="card p-6 space-y-4">
                <h2 class="h-card">First Restaurant Admin</h2>
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                    <label class="block"><span class="label">Admin name</span>
                        <input v-model="form.admin.name" class="input" />
                        <FormError :errors="errors" field="admin.name" /></label>
                    <label class="block"><span class="label">Admin email</span>
                        <input v-model="form.admin.email" type="email" class="input" />
                        <FormError :errors="errors" field="admin.email" /></label>
                </div>
                <label class="block"><span class="label">Password</span>
                    <div class="flex gap-2 mt-1.5">
                        <input v-model="form.admin.password" type="text" class="input" style="margin-top:0" placeholder="Leave blank to auto-generate" />
                        <button type="button" @click="generatePassword" class="btn btn-ghost whitespace-nowrap">Generate</button>
                    </div>
                    <FormError :errors="errors" field="admin.password" /></label>
            </div>

            <div class="flex justify-end gap-2">
                <RouterLink :to="{ name: 'admin.restaurants' }" class="btn btn-ghost">Cancel</RouterLink>
                <button type="submit" :disabled="saving" class="btn btn-accent">
                    {{ saving ? '…' : (isEdit ? 'Save changes' : 'Create restaurant & admin') }}
                </button>
            </div>
        </form>
    </div>
</template>
