<script setup>
import { ref, computed } from 'vue'
import { RouterLink, RouterView, useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { useAuth } from '@xorder/api-client/auth.js'
import { setLocale } from './i18n'
import Icon from './Icon.vue'

const props = defineProps({
    title: { type: String, required: true },
    role: { type: String, required: true },     // shown under brand
    mark: { type: String, default: 'Z' },
    theme: { type: String, default: 'theme-warm' },
    nav: { type: Array, required: true },        // [{ to, labelKey, icon }]
})

const auth = useAuth()
const router = useRouter()
const { t, locale } = useI18n()
const open = ref(false)

const userInitial = computed(() => (auth.user?.name || 'U').trim().charAt(0).toUpperCase())
const targetLocaleName = computed(() => t(locale.value === 'ar' ? 'languages.en' : 'languages.ar'))

async function logout() {
    await auth.logout()
    router.push({ name: 'login' })
}
function toggleLang() { setLocale(locale.value === 'ar' ? 'en' : 'ar') }
</script>

<template>
    <div class="portal flex" :class="theme">
        <!-- Mobile top bar -->
        <div class="sidebar sm:hidden fixed top-0 inset-x-0 h-14 z-30 flex items-center justify-between px-4">
            <button class="text-white" @click="open = !open"><Icon name="menu" :size="22" /></button>
            <span class="side-name">{{ title }}</span>
            <button class="text-white/70" @click="logout"><Icon name="logout" :size="20" /></button>
        </div>

        <!-- Scrim -->
        <div v-if="open" class="fixed inset-0 bg-black/40 z-30 sm:hidden" @click="open = false"></div>

        <!-- Sidebar -->
        <aside class="sidebar w-60 flex-shrink-0 flex flex-col p-4 fixed sm:sticky top-0 h-screen z-40 transition-transform"
            :class="open ? 'translate-x-0' : '-translate-x-full sm:translate-x-0'">
            <div class="side-brand">
                <div class="side-mark">{{ mark }}</div>
                <div class="min-w-0">
                    <div class="side-name truncate">{{ title }}</div>
                    <div class="side-role">{{ role }}</div>
                </div>
            </div>

            <nav class="space-y-1 flex-1">
                <RouterLink v-for="link in nav" :key="link.to.name ?? link.to" :to="link.to"
                    class="nav-item" active-class="active" :end="link.end" @click="open = false">
                    <span class="nav-ico"><Icon :name="link.icon" :size="18" /></span>{{ t(link.labelKey) }}
                </RouterLink>
            </nav>

            <div class="side-sub">
                <div class="flex items-center gap-3">
                    <div class="avatar">{{ userInitial }}</div>
                    <div class="min-w-0 flex-1">
                        <div class="text-sm text-white/90 truncate">{{ auth.user?.name }}</div>
                        <button class="text-xs flex items-center gap-1 mt-0.5" style="color:var(--sidebar-muted)" @click="logout">
                            <Icon name="logout" :size="13" />{{ t('nav.logout') }}
                        </button>
                    </div>
                </div>
            </div>

            <div v-if="theme === 'theme-warm'" class="side-powered">
                <span>{{ t('app.powered_by') }}</span><strong>Xorder</strong>
            </div>
        </aside>

        <!-- Main -->
        <div class="flex-1 min-w-0">
            <div class="max-w-6xl mx-auto w-full">
                <header class="hidden sm:flex items-center justify-end gap-3 px-6 lg:px-8 h-16">
                    <button class="pill-btn" @click="toggleLang">
                        <Icon name="globe" :size="16" />{{ targetLocaleName }}
                    </button>
                </header>
                <main class="px-4 sm:px-6 lg:px-8 pb-12 pt-16 sm:pt-2">
                    <RouterView />
                </main>
            </div>
        </div>
    </div>
</template>
