<script setup>
import { reactive, ref, computed, onMounted } from 'vue'
import { useRoute, useRouter, RouterLink } from 'vue-router'
import { useI18n } from 'vue-i18n'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import FormError from '@xorder/ui/FormError.vue'
import { pickLocalized } from '@xorder/ui/localize.js'

const route = useRoute()
const router = useRouter()
const { t, locale } = useI18n()

const isEdit = computed(() => !!route.params.id)
const backArrow = computed(() => locale.value === 'ar' ? '→' : '←')
const forwardArrow = computed(() => locale.value === 'ar' ? '←' : '→')

const form = reactive({ name: '', username: '', email: '', role_id: '', status: 'ACTIVE', password: '' })
const roles = ref([])
const errors = ref({})
const saving = ref(false)
const generatedPassword = ref('')

const roleLabel = (r) => pickLocalized({ name_en: r.name, name_ar: r.name_ar }, 'name', locale.value) || r.name

function generatePassword() {
    const chars = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'
    form.password = Array.from(crypto.getRandomValues(new Uint8Array(14))).map(b => chars[b % chars.length]).join('')
}

onMounted(async () => {
    const { data } = await api.get('api/dashboard/roles')
    roles.value = data.data
    if (isEdit.value) {
        const { data: staff } = await api.get(`api/dashboard/staff/${route.params.id}`)
        Object.assign(form, {
            name: staff.data.name, username: staff.data.username, email: staff.data.email || '',
            role_id: staff.data.role_id, status: staff.data.status, password: '',
        })
    } else if (roles.value.length) {
        form.role_id = roles.value[0].id
    }
})

async function submit() {
    errors.value = {}
    saving.value = true
    try {
        await ensureCsrf()
        const payload = {
            name: form.name, username: form.username, email: form.email || null,
            role_id: form.role_id, status: form.status,
        }
        if (isEdit.value) {
            await api.put(`api/dashboard/staff/${route.params.id}`, payload)
            router.push({ name: 'dashboard.staff' })
        } else {
            if (form.password) payload.password = form.password
            const { data } = await api.post('api/dashboard/staff', payload)
            // A generated password is shown once and never again — hold the page
            // until it has been read rather than bouncing straight to the list.
            if (data.generated_password) generatedPassword.value = data.generated_password
            else router.push({ name: 'dashboard.staff' })
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
        <RouterLink :to="{ name: 'dashboard.staff' }" class="text-sm" style="color:var(--muted)">{{ backArrow }} {{ t('team.back_to_staff') }}</RouterLink>
        <h1 class="page-title my-3">{{ isEdit ? t('team.edit_staff') : t('team.add_staff') }}</h1>

        <div v-if="generatedPassword" class="card p-5 mb-4" style="border-color:var(--green);background:var(--green-soft)">
            <p class="font-medium" style="color:var(--green)">{{ t('team.generated_password') }}</p>
            <p class="mono text-2xl mt-1" style="color:var(--ink)" dir="ltr">{{ generatedPassword }}</p>
            <p class="text-sm mt-1" style="color:var(--green)">{{ t('team.generated_password_note') }}</p>
            <RouterLink :to="{ name: 'dashboard.staff' }" class="btn btn-dark mt-3">{{ t('common.done') }} {{ forwardArrow }}</RouterLink>
        </div>

        <form v-if="!generatedPassword" @submit.prevent="submit" class="space-y-5">
            <div class="card p-6 space-y-4">
                <label class="block"><span class="label">{{ t('team.name') }}</span>
                    <input v-model="form.name" class="input" />
                    <FormError :errors="errors" field="name" /></label>

                <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                    <label class="block"><span class="label">{{ t('team.username') }}</span>
                        <input v-model="form.username" type="text" dir="ltr" autocapitalize="none" spellcheck="false" class="input" />
                        <span class="block text-xs mt-1" style="color:var(--muted)">{{ t('team.username_hint') }}</span>
                        <FormError :errors="errors" field="username" /></label>
                    <label class="block"><span class="label">{{ t('team.email') }}</span>
                        <input v-model="form.email" type="email" class="input" dir="ltr" />
                        <span class="block text-xs mt-1" style="color:var(--muted)">{{ t('team.email_hint') }}</span>
                        <FormError :errors="errors" field="email" /></label>
                </div>

                <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                    <label class="block"><span class="label">{{ t('team.role') }}</span>
                        <select v-model="form.role_id" class="input">
                            <option v-for="r in roles" :key="r.id" :value="r.id">{{ roleLabel(r) }}</option>
                        </select>
                        <FormError :errors="errors" field="role_id" /></label>
                    <label class="block"><span class="label">{{ t('common.status') }}</span>
                        <select v-model="form.status" class="input">
                            <option value="ACTIVE">{{ t('status.ACTIVE') }}</option>
                            <option value="SUSPENDED">{{ t('status.SUSPENDED') }}</option>
                        </select></label>
                </div>

                <label v-if="!isEdit" class="block"><span class="label">{{ t('team.password') }}</span>
                    <div class="flex gap-2 mt-1.5">
                        <input v-model="form.password" type="text" dir="ltr" class="input" style="margin-top:0" :placeholder="t('team.password_hint')" />
                        <button type="button" @click="generatePassword" class="btn btn-ghost whitespace-nowrap">{{ t('admin.generate_password') }}</button>
                    </div>
                    <FormError :errors="errors" field="password" /></label>
            </div>

            <div class="flex justify-end gap-2">
                <RouterLink :to="{ name: 'dashboard.staff' }" class="btn btn-ghost">{{ t('common.cancel') }}</RouterLink>
                <button type="submit" :disabled="saving" class="btn btn-accent">{{ saving ? t('common.saving') : (isEdit ? t('admin.save_changes') : t('team.add_staff')) }}</button>
            </div>
        </form>
    </div>
</template>
