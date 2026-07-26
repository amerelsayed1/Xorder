<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { useAuth } from '@xorder/api-client/auth.js'
import api from '@xorder/api-client/api.js'
import { setLocale } from '@xorder/ui/i18n'
import { pickLocalized } from '@xorder/ui/localize.js'
import XorderLogo from '@xorder/ui/XorderLogo.vue'
import { restaurantSlug } from '../lib/host.js'
import { inPortalHome, redirectToCorrectHost } from '../router/index.js'

const auth = useAuth()
const router = useRouter()
const route = useRoute()
const { t, locale } = useI18n()

const form = ref({ username: '', password: '', remember: false })
const error = ref('')
const loading = ref(false)
const showPassword = ref(false)

// On a restaurant subdomain, brand the login with the restaurant's logo + name.
const branding = ref(null)
const brandName = computed(() => branding.value ? pickLocalized(branding.value, 'name', locale.value) : '')
onMounted(async () => {
    if (!restaurantSlug) return
    try {
        const { data } = await api.get(`api/public/restaurants/${restaurantSlug}/branding`)
        branding.value = data.data
    } catch { /* fall back to the default Xorder branding */ }
})

async function submit() {
    error.value = ''
    loading.value = true
    try {
        // Tell the API which tenant this login targets. The SPA knows its own
        // subdomain, so we don't depend on the Host header surviving a dev
        // proxy or a decoupled API origin. Null on the super-admin portal.
        await auth.login({ ...form.value, restaurant: restaurantSlug })
        // Where the signed-in user belongs depends on the host. On the correct
        // portal, go to its home (honouring any post-login redirect). If the
        // account belongs elsewhere — e.g. a restaurant admin who opened the
        // super-admin URL — send the browser to their own subdomain instead of
        // pushing a route that doesn't exist here and surfacing it as a false
        // "login failed".
        const home = inPortalHome(auth)
        if (home) {
            router.push(route.query.redirect || home)
        } else {
            redirectToCorrectHost(auth)
        }
    } catch (err) {
        error.value = err.response?.data?.errors?.email?.[0]
            || err.response?.data?.message
            || t('auth.login_failed')
    } finally {
        loading.value = false
    }
}
function toggleLang() { setLocale(locale.value === 'ar' ? 'en' : 'ar') }
const targetLocaleName = () => t(locale.value === 'ar' ? 'languages.en' : 'languages.ar')
</script>

<template>
    <div class="theme-warm portal min-h-screen flex items-center justify-center p-4">
        <div class="w-full max-w-sm">
            <div class="flex justify-end mb-4">
                <button class="text-sm" style="color:var(--muted)" @click="toggleLang">
                    {{ targetLocaleName() }}
                </button>
            </div>

            <div class="card p-7">
                <div class="mb-5">
                    <div v-if="branding && branding.logo_url" class="flex items-center gap-3">
                        <img :src="branding.logo_url" :alt="brandName" style="height:46px;width:46px;border-radius:11px;object-fit:cover;display:block" />
                        <span class="page-title" style="font-size:20px">{{ brandName }}</span>
                    </div>
                    <XorderLogo v-else style="height:34px;width:auto;color:var(--ink);display:block" />
                    <div class="page-sub" style="margin-top:10px">{{ t('auth.welcome') }}</div>
                </div>

                <form @submit.prevent="submit" class="space-y-4">
                    <label class="block">
                        <span class="label">{{ t('auth.username') }}</span>
                        <input v-model="form.username" type="text" required autocomplete="username" autocapitalize="none" spellcheck="false" class="input" />
                    </label>
                    <label class="block">
                        <span class="label">{{ t('auth.password') }}</span>
                        <div style="position:relative">
                            <input v-model="form.password" :type="showPassword ? 'text' : 'password'" required autocomplete="current-password" class="input" style="padding-inline-end:2.75rem" />
                            <button type="button" @click="showPassword = !showPassword"
                                :aria-label="showPassword ? t('auth.hide_password') : t('auth.show_password')"
                                :title="showPassword ? t('auth.hide_password') : t('auth.show_password')"
                                style="position:absolute;inset-inline-end:0;top:0;bottom:0;display:flex;align-items:center;padding-inline:0.75rem;color:var(--muted);background:none;border:0;cursor:pointer">
                                <svg v-if="showPassword" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19m-6.72-1.07a3 3 0 1 1-4.24-4.24"/><line x1="1" y1="1" x2="23" y2="23"/></svg>
                                <svg v-else width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg>
                            </button>
                        </div>
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
