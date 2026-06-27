<script setup>
import { ref } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { useAuth } from '../stores/auth'
import { setLocale } from '../i18n'

const auth = useAuth()
const router = useRouter()
const route = useRoute()
const { t, locale } = useI18n()

const form = ref({ email: '', password: '', remember: false })
const error = ref('')
const loading = ref(false)

async function submit() {
    error.value = ''
    loading.value = true
    try {
        await auth.login(form.value)
        router.push(route.query.redirect || auth.homeRoute())
    } catch (err) {
        error.value = err.response?.data?.message
            || err.response?.data?.errors?.email?.[0]
            || 'Login failed'
    } finally {
        loading.value = false
    }
}
function toggleLang() { setLocale(locale.value === 'ar' ? 'en' : 'ar') }
</script>

<template>
    <div class="theme-warm portal min-h-screen flex items-center justify-center p-4">
        <div class="w-full max-w-sm">
            <div class="flex justify-end mb-4">
                <button class="text-sm" style="color:var(--muted)" @click="toggleLang">
                    {{ locale === 'ar' ? 'English' : 'العربية' }}
                </button>
            </div>

            <div class="card p-7">
                <div class="flex items-center gap-3 mb-5">
                    <div class="side-mark">Q</div>
                    <div>
                        <div class="page-title" style="font-size:18px">{{ t('app.title') }}</div>
                        <div class="page-sub">{{ t('auth.welcome') }}</div>
                    </div>
                </div>

                <form @submit.prevent="submit" class="space-y-4">
                    <label class="block">
                        <span class="label">{{ t('auth.email') }}</span>
                        <input v-model="form.email" type="email" required autocomplete="username" class="input" />
                    </label>
                    <label class="block">
                        <span class="label">{{ t('auth.password') }}</span>
                        <input v-model="form.password" type="password" required autocomplete="current-password" class="input" />
                    </label>
                    <label class="flex items-center gap-2 text-sm" style="color:var(--body)">
                        <input v-model="form.remember" type="checkbox" /> {{ t('auth.remember') }}
                    </label>

                    <p v-if="error" class="text-sm" style="color:#c0392b">{{ error }}</p>

                    <button type="submit" :disabled="loading" class="btn btn-accent w-full justify-center">
                        {{ loading ? t('auth.signing_in') : t('auth.login') }}
                    </button>
                </form>
            </div>
        </div>
    </div>
</template>
