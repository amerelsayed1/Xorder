<script setup>
import { ref, computed } from 'vue'
import { RouterLink, RouterView, useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { useAuth } from '@xorder/api-client/auth.js'
import { setLocale } from './i18n'
import XorderLogo from './XorderLogo.vue'
import Button from 'primevue/button'
import Avatar from 'primevue/avatar'
import Menu from 'primevue/menu'

const props = defineProps({
    title: { type: String, required: true },
    role: { type: String, required: true },
    mark: { type: String, default: 'X' },
    logo: { type: String, default: '' }, // optional brand logo (e.g. restaurant) shown in the topbar
    nav: { type: Array, required: true }, // [{ to, labelKey, icon (pi pi-*) }]
})

const auth = useAuth()
const router = useRouter()
const { t, locale } = useI18n()
const mobileOpen = ref(false)
const profileMenu = ref()

const userInitial = computed(() => (auth.user?.name || 'U').trim().charAt(0).toUpperCase())
const homeTo = computed(() => auth.homeRoute())

async function logout() {
    await auth.logout()
    router.push({ name: 'login' })
}
function toggleLang() { setLocale(locale.value === 'ar' ? 'en' : 'ar') }
const targetLocaleName = computed(() => t(locale.value === 'ar' ? 'languages.en' : 'languages.ar'))

const profileItems = computed(() => [
    { label: auth.user?.name || '', items: [{ label: t('nav.logout'), icon: 'pi pi-sign-out', command: logout }] },
])
</script>

<template>
    <div class="sakai">
        <!-- Topbar -->
        <header class="sakai-topbar">
            <div class="flex items-center gap-2">
                <button class="sakai-icon-btn lg:hidden" @click="mobileOpen = !mobileOpen"><i class="pi pi-bars" /></button>
                <RouterLink :to="homeTo" class="flex items-center gap-2.5">
                    <template v-if="props.logo">
                        <img :src="props.logo" class="sakai-brand-logo" :alt="props.title" />
                        <span class="sakai-brand-name">{{ props.title }}</span>
                    </template>
                    <XorderLogo v-else class="sakai-logo" />
                </RouterLink>
            </div>
            <div class="flex items-center gap-2">
                <Button :label="targetLocaleName" icon="pi pi-globe" text severity="secondary" size="small" @click="toggleLang" />
                <button class="sakai-profile" @click="profileMenu.toggle($event)">
                    <Avatar :label="userInitial" shape="circle" style="background:var(--p-primary-color);color:#fff;font-weight:700" />
                    <span class="hidden sm:block sakai-profile-name">{{ auth.user?.name }}</span>
                    <i class="pi pi-angle-down text-xs hidden sm:block" />
                </button>
                <Menu ref="profileMenu" :model="profileItems" popup />
            </div>
        </header>

        <!-- Sidebar -->
        <div v-if="mobileOpen" class="sakai-scrim lg:hidden" @click="mobileOpen = false"></div>
        <aside class="sakai-sidebar" :class="{ open: mobileOpen }">
            <ul class="sakai-menu">
                <li class="sakai-menu-label">{{ t('common.menu') }}</li>
                <li v-for="link in nav" :key="link.to.name ?? link.to">
                    <RouterLink :to="link.to" custom v-slot="{ href, navigate, isActive, isExactActive }">
                        <a :href="href" class="sakai-menu-item" :class="{ active: link.end ? isExactActive : isActive }"
                            @click="navigate($event); mobileOpen = false">
                            <i :class="link.icon" /><span>{{ t(link.labelKey) }}</span>
                        </a>
                    </RouterLink>
                </li>
            </ul>
            <div class="sakai-powered">
                <span>{{ t('app.powered_by') }}</span><XorderLogo />
            </div>
        </aside>

        <!-- Content -->
        <main class="sakai-content theme-warm">
            <div class="sakai-content-inner">
                <RouterView />
            </div>
        </main>
    </div>
</template>

<style scoped>
.sakai { min-height: 100vh; background: var(--p-surface-50); }

/* Topbar */
.sakai-topbar { position: fixed; inset-inline: 0; top: 0; height: 64px; z-index: 30;
    display: flex; align-items: center; justify-content: space-between; gap: 12px; padding: 0 22px;
    background: var(--p-content-background); border-bottom: 1px solid var(--p-content-border-color); }
.sakai-logo { height: 28px; width: auto; color: var(--p-text-color); display: block; }
.sakai-brand-logo { height: 34px; width: 34px; border-radius: 9px; object-fit: cover; display: block; }
.sakai-brand-name { font-family: var(--font-display); font-weight: 600; font-size: 16px; color: var(--p-text-color); }
.sakai-icon-btn { width: 40px; height: 40px; border-radius: 8px; display: grid; place-items: center;
    color: var(--p-text-muted-color); background: transparent; border: none; cursor: pointer; }
.sakai-icon-btn:hover { background: var(--p-surface-100); }
.sakai-profile { display: flex; align-items: center; gap: 9px; padding: 5px 10px 5px 5px; border-radius: 30px;
    background: transparent; border: 1px solid transparent; cursor: pointer; }
.sakai-profile:hover { background: var(--p-surface-100); }
.sakai-profile-name { font-size: 14px; font-weight: 500; color: var(--p-text-color); }

/* Sidebar */
.sakai-sidebar { position: fixed; inset-inline-start: 0; top: 64px; bottom: 0; width: 268px; z-index: 25;
    background: var(--p-content-background); border-inline-end: 1px solid var(--p-content-border-color);
    padding: 16px; display: flex; flex-direction: column; overflow-y: auto; transition: transform .2s ease; }
.sakai-menu { list-style: none; padding: 6px 0 0; margin: 0; flex: 1; }
.sakai-menu-label { font-size: 11px; font-weight: 700; text-transform: uppercase; letter-spacing: .06em;
    color: var(--p-text-muted-color); padding: 12px 12px 8px; }
.sakai-menu-item { display: flex; align-items: center; gap: 11px; padding: 11px 12px; border-radius: 9px;
    color: var(--p-text-color); font-size: 14.5px; font-weight: 500; text-decoration: none; transition: background .15s, color .15s; }
.sakai-menu-item i { font-size: 17px; width: 20px; text-align: center; color: var(--p-text-muted-color); transition: color .15s; }
.sakai-menu-item:hover { background: var(--p-surface-100); }
.sakai-menu-item.active { background: var(--p-primary-50); color: var(--p-primary-color); }
.sakai-menu-item.active i { color: var(--p-primary-color); }
.sakai-powered { display: flex; align-items: center; gap: 7px; padding: 14px 8px 4px; font-size: 12px; color: var(--p-text-muted-color); }
.sakai-powered svg { height: 14px; width: auto; color: var(--p-text-color); opacity: .8; }

.sakai-scrim { position: fixed; inset: 0; z-index: 24; background: rgba(0,0,0,.4); }

/* Content */
.sakai-content { padding: 88px 0 40px; margin-inline-start: 268px; }
.sakai-content-inner { max-width: 1400px; margin: 0 auto; padding-inline: 28px; }

@media (max-width: 1023px) {
    .sakai-sidebar { transform: translateX(-100%); }
    [dir=rtl] .sakai-sidebar { transform: translateX(100%); }
    .sakai-sidebar.open { transform: translateX(0); }
    .sakai-content { margin-inline-start: 0; }
}
</style>
