<script setup>
import { ref } from 'vue'
import { RouterLink, RouterView, useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { useAuth } from '../stores/auth'
import { setLocale } from '../i18n'

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
            <button class="text-white text-xl" @click="open = !open">☰</button>
            <span class="side-name">{{ title }}</span>
            <button class="text-white/70 text-sm" @click="logout">{{ t('nav.logout') }}</button>
        </div>

        <!-- Scrim -->
        <div v-if="open" class="fixed inset-0 bg-black/40 z-30 sm:hidden" @click="open = false"></div>

        <!-- Sidebar -->
        <aside class="sidebar w-60 flex-shrink-0 flex flex-col p-4 fixed sm:sticky top-0 h-screen z-40 transition-transform"
            :class="open ? 'translate-x-0' : '-translate-x-full sm:translate-x-0'">
            <div class="side-brand">
                <div class="side-mark">{{ mark }}</div>
                <div>
                    <div class="side-name">{{ title }}</div>
                    <div class="side-role">{{ role }}</div>
                </div>
            </div>

            <nav class="space-y-1 flex-1">
                <RouterLink v-for="link in nav" :key="link.to.name ?? link.to" :to="link.to"
                    class="nav-item" active-class="active" :end="link.end" @click="open = false">
                    <span class="opacity-70">{{ link.icon }}</span>{{ t(link.labelKey) }}
                </RouterLink>
            </nav>

            <div class="side-sub">
                <div class="text-[11px] uppercase tracking-wide" style="color:var(--sidebar-muted)">{{ t('nav.profile') }}</div>
                <div class="text-sm text-white/90 mt-1 truncate">{{ auth.user?.name }}</div>
                <button class="text-xs mt-2" style="color:var(--sidebar-muted)" @click="logout">↩ {{ t('nav.logout') }}</button>
            </div>
        </aside>

        <!-- Main -->
        <div class="flex-1 min-w-0">
            <header class="hidden sm:flex items-center justify-end gap-3 px-6 lg:px-8 h-14">
                <button class="text-sm" style="color:var(--muted)" @click="toggleLang">{{ locale === 'ar' ? 'EN' : 'ع' }}</button>
            </header>
            <main class="px-4 sm:px-6 lg:px-8 pb-12 pt-16 sm:pt-0 max-w-6xl">
                <RouterView />
            </main>
        </div>
    </div>
</template>
