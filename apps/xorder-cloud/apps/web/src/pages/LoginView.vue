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
    <div class="theme-warm portal login min-h-screen flex items-center justify-center p-4">
        <div class="w-full max-w-sm">
            <div class="flex justify-end mb-3">
                <button type="button" class="lang-btn" @click="toggleLang">
                    {{ targetLocaleName() }}
                </button>
            </div>

            <div class="card login-card">
                <div class="mb-6">
                    <div v-if="branding && branding.logo_url" class="flex items-center gap-3">
                        <img :src="branding.logo_url" :alt="brandName" style="height:46px;width:46px;border-radius:11px;object-fit:cover;display:block" />
                        <span class="page-title" style="font-size:20px">{{ brandName }}</span>
                    </div>
                    <XorderLogo v-else style="height:34px;width:auto;color:var(--ink);display:block" />
                    <div class="page-sub" style="margin-top:12px;color:var(--body);font-size:15.5px">{{ t('auth.welcome') }}</div>
                </div>

                <form @submit.prevent="submit" class="space-y-4">
                    <label class="block">
                        <span class="label">{{ t('auth.username') }}</span>
                        <input v-model="form.username" type="text" required autocomplete="username" autocapitalize="none" spellcheck="false" class="input fld" />
                    </label>
                    <label class="block">
                        <span class="label">{{ t('auth.password') }}</span>
                        <div style="position:relative">
                            <input v-model="form.password" :type="showPassword ? 'text' : 'password'" required autocomplete="current-password" class="input fld" style="padding-inline-end:3rem" />
                            <button type="button" @click="showPassword = !showPassword" class="pw-toggle"
                                :aria-label="showPassword ? t('auth.hide_password') : t('auth.show_password')"
                                :title="showPassword ? t('auth.hide_password') : t('auth.show_password')">
                                <svg v-if="showPassword" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19m-6.72-1.07a3 3 0 1 1-4.24-4.24"/><line x1="1" y1="1" x2="23" y2="23"/></svg>
                                <svg v-else width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg>
                            </button>
                        </div>
                    </label>
                    <label class="remember">
                        <input v-model="form.remember" type="checkbox" /> {{ t('auth.remember') }}
                    </label>

                    <p v-if="error" class="login-error" role="alert">{{ error }}</p>

                    <button type="submit" :disabled="loading" class="btn btn-accent w-full justify-center submit">
                        {{ loading ? t('auth.signing_in') : t('auth.login') }}
                    </button>
                </form>
            </div>
        </div>
    </div>
</template>

<style scoped>
.login-card { padding: 28px; }
.lang-btn { min-height: 44px; padding-inline: 12px; font-size: 14px; font-weight: 500; color: var(--body); background: none; border: 0;
    border-radius: 10px; cursor: pointer; transition: background .15s, color .15s; }
.lang-btn:hover { background: var(--card); color: var(--ink); }
.fld { min-height: 46px; }
.fld:focus { box-shadow: 0 0 0 3px var(--accent-soft); }
.pw-toggle { position: absolute; inset-inline-end: 0; top: 6px; bottom: 0; width: 46px; height: 46px; display: flex; align-items: center;
    justify-content: center; color: var(--body); background: none; border: 0; border-radius: 10px; cursor: pointer; }
.pw-toggle:hover { color: var(--ink); }
.remember { display: flex; align-items: center; gap: 10px; min-height: 44px; font-size: 14.5px; color: var(--body); cursor: pointer; }
.remember input { width: 18px; height: 18px; accent-color: var(--accent); }
.login-error { font-size: 14px; color: var(--red); background: var(--red-soft); border-radius: 10px; padding: 10px 12px; }
.submit { min-height: 48px; font-size: 15.5px; }
</style>
