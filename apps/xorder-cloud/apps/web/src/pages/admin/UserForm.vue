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
        <RouterLink :to="{ name: 'admin.users' }" class="back-link">{{ backArrow }} {{ t('common.back') }}</RouterLink>
        <h1 class="page-title my-3">{{ isEdit ? t('users.edit_user') : t('users.add_user') }}</h1>

        <!-- Generated password banner (create with no password supplied) -->
        <div v-if="generatedPassword" class="card p-5 mb-4" role="status" style="border-color:var(--green);background:var(--green-soft)">
            <p class="font-medium" style="color:var(--green)">{{ t('users.generated_password') }}</p>
            <p class="mono text-2xl mt-1" style="color:var(--ink)">{{ generatedPassword }}</p>
            <p class="text-sm mt-1" style="color:var(--body)">{{ t('users.generated_password_note') }}</p>
            <RouterLink :to="{ name: 'admin.users' }" class="btn btn-dark mt-3 cta">{{ t('common.done') }} {{ forwardArrow }}</RouterLink>
        </div>

        <form v-if="!generatedPassword" @submit.prevent="submit" class="space-y-5">
            <!-- Who -->
            <section class="card p-6 space-y-4" aria-labelledby="uf-account">
                <h2 id="uf-account" class="h-card">{{ t('users.section_account') }}</h2>
                <label class="block"><span class="label">{{ t('users.name') }}</span>
                    <input v-model="form.name" class="input" />
                    <FormError :errors="errors" field="name" /></label>

                <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                    <label class="block"><span class="label">{{ t('users.username') }}</span>
                        <input v-model="form.username" type="text" dir="ltr" autocapitalize="none" spellcheck="false" class="input" />
                        <span class="help">{{ t('users.username_hint') }}</span>
                        <FormError :errors="errors" field="username" /></label>
                    <label class="block"><span class="label">{{ t('users.email') }}</span>
                        <input v-model="form.email" type="email" class="input" dir="ltr" />
                        <FormError :errors="errors" field="email" /></label>
                </div>
            </section>

            <!-- What they can do -->
            <section class="card p-6 space-y-4" aria-labelledby="uf-access">
                <h2 id="uf-access" class="h-card">{{ t('users.section_access') }}</h2>
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                    <label class="block"><span class="label">{{ t('users.role') }}</span>
                        <select v-model="form.role" class="input">
                            <option v-for="r in ASSIGNABLE_ROLES" :key="r" :value="r">{{ t(`roles.${r.toLowerCase()}`) }}</option>
                        </select>
                        <span class="help">{{ t(`users.role_help.${form.role.toLowerCase()}`) }}</span>
                        <FormError :errors="errors" field="role" /></label>
                    <label class="block"><span class="label">{{ t('common.status') }}</span>
                        <select v-model="form.status" class="input">
                            <option value="ACTIVE">{{ t('status.ACTIVE') }}</option>
                            <option value="SUSPENDED">{{ t('status.SUSPENDED') }}</option>
                        </select></label>
                </div>
            </section>

            <!-- First password (create only) -->
            <section v-if="!isEdit" class="card p-6 space-y-4" aria-labelledby="uf-pw">
                <h2 id="uf-pw" class="h-card">{{ t('users.password') }}</h2>
                <label class="block"><span class="label">{{ t('users.password') }}</span>
                    <div class="flex flex-wrap gap-2 mt-1.5">
                        <input v-model="form.password" type="text" class="input pw-input" style="margin-top:0" :placeholder="t('users.password_hint')" />
                        <button type="button" @click="generatePassword" class="btn btn-ghost whitespace-nowrap cta">{{ t('admin.generate_password') }}</button>
                    </div>
                    <FormError :errors="errors" field="password" /></label>
            </section>

            <div class="action-row">
                <RouterLink :to="{ name: 'admin.users' }" class="btn btn-ghost cta">{{ t('common.cancel') }}</RouterLink>
                <button type="submit" :disabled="saving" class="btn btn-accent cta">{{ saving ? t('common.saving') : (isEdit ? t('admin.save_changes') : t('users.add_user')) }}</button>
            </div>
        </form>
    </div>
</template>

<style scoped>
.back-link { display: inline-flex; align-items: center; min-height: 32px; font-size: 14px; font-weight: 500; color: var(--p-primary-700); }
.back-link:hover { text-decoration: underline; }
.help { display: block; font-size: 13px; margin-top: 5px; color: var(--body); }
.cta { min-height: 44px; justify-content: center; }
.pw-input { flex: 1 1 200px; width: auto; }
/* Save stays reachable while the form scrolls */
.action-row { position: sticky; bottom: 0; z-index: 5; display: flex; justify-content: flex-end; gap: 8px; padding: 12px 0;
    background: linear-gradient(to top, var(--page) 70%, transparent); }
</style>
