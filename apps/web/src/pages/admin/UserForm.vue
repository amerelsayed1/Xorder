<script setup>
import { reactive, ref, computed, onMounted } from 'vue'
import { useRoute, useRouter, RouterLink } from 'vue-router'
import { useI18n } from 'vue-i18n'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import FormError from '@xorder/ui/FormError.vue'
import { collectEmailErrors } from '../../lib/email.js'

const route = useRoute()
const router = useRouter()
const { t, locale } = useI18n()

const isEdit = computed(() => !!route.params.id)
const backArrow = computed(() => locale.value === 'ar' ? '→' : '←')
const forwardArrow = computed(() => locale.value === 'ar' ? '←' : '→')

// Roles the Super Admin may assign — mirrors RoleEnum::assignable() on the API.
const ASSIGNABLE_ROLES = ['ADMIN', 'MODERATOR', 'SALES', 'SUPPORT']

const form = reactive({ name: '', username: '', email: '', role: 'SUPPORT', status: 'ACTIVE', password: '' })
const errors = ref({})
const saving = ref(false)
const generatedPassword = ref('')

function generatePassword() {
    const chars = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'
    form.password = Array.from(crypto.getRandomValues(new Uint8Array(14))).map(b => chars[b % chars.length]).join('')
}

onMounted(async () => {
    if (isEdit.value) {
        const { data } = await api.get(`api/admin/users/${route.params.id}`)
        Object.assign(form, {
            name: data.data.name, username: data.data.username, email: data.data.email,
            role: data.data.role, status: data.data.status, password: '',
        })
    }
})

async function submit() {
    errors.value = {}
    const clientErrors = collectEmailErrors({ email: form.email }, t('restaurant.email_invalid'))
    if (Object.keys(clientErrors).length) { errors.value = clientErrors; return }

    saving.value = true
    try {
        await ensureCsrf()
        if (isEdit.value) {
            const payload = { name: form.name, username: form.username, email: form.email, role: form.role, status: form.status }
            await api.put(`api/admin/users/${route.params.id}`, payload)
            router.push({ name: 'admin.users' })
        } else {
            const payload = { name: form.name, username: form.username, email: form.email, role: form.role, status: form.status }
            if (form.password) payload.password = form.password
            const { data } = await api.post('api/admin/users', payload)
            if (data.generated_password) generatedPassword.value = data.generated_password
            else router.push({ name: 'admin.users' })
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
        <RouterLink :to="{ name: 'admin.users' }" class="text-sm" style="color:var(--muted)">{{ backArrow }} {{ t('common.back') }}</RouterLink>
        <h1 class="page-title my-3">{{ isEdit ? t('users.edit_user') : t('users.add_user') }}</h1>

        <!-- Generated password banner (create with no password supplied) -->
        <div v-if="generatedPassword" class="card p-5 mb-4" style="border-color:var(--green);background:var(--green-soft)">
            <p class="font-medium" style="color:var(--green)">{{ t('users.generated_password') }}</p>
            <p class="mono text-2xl mt-1" style="color:var(--ink)">{{ generatedPassword }}</p>
            <p class="text-sm mt-1" style="color:var(--green)">{{ t('users.generated_password_note') }}</p>
            <RouterLink :to="{ name: 'admin.users' }" class="btn btn-dark mt-3">{{ t('common.done') }} {{ forwardArrow }}</RouterLink>
        </div>

        <form v-if="!generatedPassword" @submit.prevent="submit" class="space-y-5">
            <div class="card p-6 space-y-4">
                <label class="block"><span class="label">{{ t('users.name') }}</span>
                    <input v-model="form.name" class="input" />
                    <FormError :errors="errors" field="name" /></label>

                <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                    <label class="block"><span class="label">{{ t('users.username') }}</span>
                        <input v-model="form.username" type="text" dir="ltr" autocapitalize="none" spellcheck="false" class="input" />
                        <span class="block text-xs mt-1" style="color:var(--muted)">{{ t('users.username_hint') }}</span>
                        <FormError :errors="errors" field="username" /></label>
                    <label class="block"><span class="label">{{ t('users.email') }}</span>
                        <input v-model="form.email" type="email" class="input" dir="ltr" />
                        <FormError :errors="errors" field="email" /></label>
                </div>

                <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                    <label class="block"><span class="label">{{ t('users.role') }}</span>
                        <select v-model="form.role" class="input">
                            <option v-for="r in ASSIGNABLE_ROLES" :key="r" :value="r">{{ t(`roles.${r.toLowerCase()}`) }}</option>
                        </select>
                        <span class="block text-xs mt-1" style="color:var(--muted)">{{ t(`users.role_help.${form.role.toLowerCase()}`) }}</span>
                        <FormError :errors="errors" field="role" /></label>
                    <label class="block"><span class="label">{{ t('common.status') }}</span>
                        <select v-model="form.status" class="input">
                            <option value="ACTIVE">{{ t('status.ACTIVE') }}</option>
                            <option value="SUSPENDED">{{ t('status.SUSPENDED') }}</option>
                        </select></label>
                </div>

                <label v-if="!isEdit" class="block"><span class="label">{{ t('users.password') }}</span>
                    <div class="flex gap-2 mt-1.5">
                        <input v-model="form.password" type="text" class="input" style="margin-top:0" :placeholder="t('users.password_hint')" />
                        <button type="button" @click="generatePassword" class="btn btn-ghost whitespace-nowrap">{{ t('admin.generate_password') }}</button>
                    </div>
                    <FormError :errors="errors" field="password" /></label>
            </div>

            <div class="flex justify-end gap-2">
                <RouterLink :to="{ name: 'admin.users' }" class="btn btn-ghost">{{ t('common.cancel') }}</RouterLink>
                <button type="submit" :disabled="saving" class="btn btn-accent">{{ saving ? t('common.saving') : (isEdit ? t('admin.save_changes') : t('users.add_user')) }}</button>
            </div>
        </form>
    </div>
</template>
