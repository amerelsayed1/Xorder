<script setup>
// Change password — its own settings section, its own endpoint, and its own
// save button. Deliberately apart from the profile: verifying the current
// password and swapping in the fresh token the API returns has nothing to do
// with the restaurant's public details, and it stays enabled even for a
// read-only / expired restaurant — locking a user out of their own password
// would be wrong.
import { reactive, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { ensureCsrf } from '@xorder/api-client/api.js'
import { useAuth } from '@xorder/api-client/auth.js'
import FormError from '@xorder/ui/FormError.vue'
import SettingsHeader from './SettingsHeader.vue'

const { t } = useI18n()
const auth = useAuth()

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
    <SettingsHeader :title="t('profile.change_password')" :desc="t('profile.change_password_sub')">
        <template #actions>
            <span v-if="pwSaved" class="set-chip set-chip-green" role="status"><span class="dot"></span>{{ t('profile.password_changed') }}</span>
        </template>
    </SettingsHeader>

    <form class="set-card" @submit.prevent="changePassword">
        <div class="set-form">
            <label class="set-field" style="max-width: 340px">
                <span class="label">{{ t('profile.current_password') }}</span>
                <input v-model="pw.current_password" type="password" dir="ltr" autocomplete="current-password" class="input" />
                <FormError :errors="pwErrors" field="current_password" />
            </label>

            <div class="set-grid-sm">
                <label class="set-field">
                    <span class="label">{{ t('profile.new_password') }}</span>
                    <input v-model="pw.password" type="password" dir="ltr" autocomplete="new-password" class="input" />
                    <span class="set-inset-hint" style="margin-top: 6px">{{ t('profile.password_rule') }}</span>
                    <FormError :errors="pwErrors" field="password" />
                </label>
                <label class="set-field">
                    <span class="label">{{ t('profile.confirm_password') }}</span>
                    <input v-model="pw.password_confirmation" type="password" dir="ltr" autocomplete="new-password" class="input" />
                    <FormError :errors="pwErrors" field="password_confirmation" />
                </label>
            </div>
        </div>

        <div class="set-card-foot">
            <button type="submit" class="set-btn-primary" :disabled="pwSaving">{{ pwSaving ? t('common.saving') : t('profile.change_password') }}</button>
        </div>
    </form>
</template>
