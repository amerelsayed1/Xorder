<script setup>
import { ref, computed, watch } from 'vue'
import { RouterLink, RouterView, useRouter, useRoute } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { useAuth } from '@xorder/api-client/auth.js'
import { setLocale } from './i18n'
import XorderLogo from './XorderLogo.vue'
import Button from 'primevue/button'
import Avatar from 'primevue/avatar'

const props = defineProps({
    title: { type: String, required: true },
    role: { type: String, required: true },
    mark: { type: String, default: 'X' },
    logo: { type: String, default: '' }, // optional brand logo (e.g. restaurant) shown in the topbar
    // Flat items [{ to, labelKey, icon }] or collapsible groups
    // [{ key, labelKey, icon, badge?, children: [{ to, labelKey, icon, badge? }] }].
    nav: { type: Array, required: true },
    // Hide the EN/AR toggle. The restaurant dashboard locks its language to the
    // Super-Admin-configured default, so it passes true; the admin keeps it.
    hideLangToggle: { type: Boolean, default: false },
})

const auth = useAuth()
const router = useRouter()
const route = useRoute()
const { t, locale } = useI18n()
const mobileOpen = ref(false)

// --- Collapsible nav groups (accordion) -------------------------------------
// Only one group is open at a time. The group holding the active route opens
// automatically; the user can also toggle any group open/closed by hand.
const openGroup = ref(null)

// Does a child route match the current location? Prefix-match on the resolved
// path so detail routes (e.g. /admin/customers/5) keep their parent group open.
function isChildActive(child) {
    if (!child?.to) return false
    let path
    try { path = router.resolve(child.to).path } catch { return false }
    return route.path === path || route.path.startsWith(path + '/')
}
function isGroupActive(group) {
    return Array.isArray(group.children) && group.children.some(isChildActive)
}
function toggleGroup(key) {
    openGroup.value = openGroup.value === key ? null : key
}

// Follow the active route: expand the group that owns it (collapsing others),
// or collapse everything on a group-less page like the dashboard home.
function syncActiveGroup() {
    const active = props.nav.find((n) => n.children && isGroupActive(n))
    openGroup.value = active ? active.key : null
}
// Re-sync on navigation, and when the SET of groups changes (e.g. features load
// late). Deliberately NOT on the whole `nav` array — its reference changes on
// every badge poll, which would otherwise snap a hand-opened group shut.
watch(() => route.path, syncActiveGroup, { immediate: true })
watch(() => props.nav.map((n) => n.key).join('|'), syncActiveGroup)

const userInitial = computed(() => (auth.user?.name || 'U').trim().charAt(0).toUpperCase())
const homeTo = computed(() => auth.homeRoute())

async function logout() {
    await auth.logout()
    router.push({ name: 'login' })
}
function toggleLang() { setLocale(locale.value === 'ar' ? 'en' : 'ar') }
const targetLocaleName = computed(() => t(locale.value === 'ar' ? 'languages.en' : 'languages.ar'))
</script>

<template>
    <div class="sakai">
        <!-- Topbar -->
        <header class="sakai-topbar">
            <div class="flex items-center gap-2">
                <button class="sakai-icon-btn sakai-mobile-only" :aria-label="t('common.menu')" @click="mobileOpen = !mobileOpen"><i class="pi pi-bars" /></button>
                <RouterLink :to="homeTo" class="flex items-center gap-2.5">
                    <template v-if="props.logo">
                        <img :src="props.logo" class="sakai-brand-logo" :alt="props.title" />
                        <span class="sakai-brand-name">{{ props.title }}</span>
                    </template>
                    <XorderLogo v-else class="sakai-logo" />
                </RouterLink>
            </div>
            <div class="flex items-center gap-2">
                <slot name="topbar-actions" />
                <Button v-if="!hideLangToggle" :label="targetLocaleName" icon="pi pi-globe" text severity="secondary" size="small" @click="toggleLang" />
            </div>
        </header>

        <!-- Sidebar -->
        <div v-if="mobileOpen" class="sakai-scrim sakai-mobile-only" @click="mobileOpen = false"></div>
        <aside class="sakai-sidebar" :class="{ open: mobileOpen }">
            <ul class="sakai-menu">
                <li class="sakai-menu-label">{{ t('common.menu') }}</li>
                <li v-for="link in nav" :key="link.key ?? link.to?.name ?? link.labelKey">
                    <!-- Collapsible group -->
                    <template v-if="link.children">
                        <button type="button" class="sakai-menu-item sakai-group-toggle"
                            :class="{ 'has-active': isGroupActive(link) }"
                            :aria-expanded="openGroup === link.key"
                            :aria-controls="`sakai-group-${link.key}`"
                            @click="toggleGroup(link.key)">
                            <i :class="link.icon" /><span>{{ t(link.labelKey) }}</span>
                            <span v-if="link.badge" class="sakai-menu-badge">{{ link.badge }}</span>
                            <i class="pi pi-angle-down sakai-group-arrow" :class="{ open: openGroup === link.key }" aria-hidden="true" />
                        </button>
                        <div class="sakai-submenu-wrap" :class="{ open: openGroup === link.key }"
                            :inert="openGroup !== link.key">
                            <ul :id="`sakai-group-${link.key}`" class="sakai-submenu" role="region">
                                <li v-for="child in link.children" :key="child.key ?? child.to.name">
                                    <RouterLink :to="child.to" custom v-slot="{ href, navigate, isActive, isExactActive }">
                                        <a :href="href" class="sakai-menu-item sakai-submenu-item"
                                            :class="{ active: child.end ? isExactActive : isActive }"
                                            @click="navigate($event); mobileOpen = false">
                                            <i :class="child.icon" /><span>{{ t(child.labelKey) }}</span>
                                            <span v-if="child.badge" class="sakai-menu-badge">{{ child.badge }}</span>
                                        </a>
                                    </RouterLink>
                                </li>
                            </ul>
                        </div>
                    </template>
                    <!-- Flat item -->
                    <RouterLink v-else :to="link.to" custom v-slot="{ href, navigate, isActive, isExactActive }">
                        <a :href="href" class="sakai-menu-item" :class="{ active: link.end ? isExactActive : isActive }"
                            @click="navigate($event); mobileOpen = false">
                            <i :class="link.icon" /><span>{{ t(link.labelKey) }}</span>
                            <span v-if="link.badge" class="sakai-menu-badge">{{ link.badge }}</span>
                        </a>
                    </RouterLink>
                </li>
            </ul>
            <div class="sakai-profile sakai-profile-side">
                <Avatar :label="userInitial" shape="circle" style="background:var(--p-primary-color);color:#fff;font-weight:700" />
                <span class="sakai-profile-name">{{ auth.user?.name }}</span>
                <button class="sakai-logout-btn" :aria-label="t('nav.logout')" :title="t('nav.logout')" @click="logout">
                    <i class="pi pi-sign-out" />
                </button>
            </div>
        </aside>

        <!-- Content -->
        <main class="sakai-content theme-warm">
            <div class="sakai-content-inner">
                <slot name="banner" />
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

/* Sidebar variant: full-width row pinned at the bottom, name always shown. */
.sakai-profile-side { width: 100%; border-radius: 9px; padding: 9px 12px;
    margin-top: 8px; cursor: default; }
.sakai-profile-side:hover { background: transparent; }
.sakai-profile-side .sakai-profile-name { flex: 1; text-align: start; }
.sakai-logout-btn { display: grid; place-items: center; width: 32px; height: 32px; flex: none;
    border-radius: 8px; background: transparent; border: none; cursor: pointer; color: var(--p-text-muted-color); }
.sakai-logout-btn:hover { background: var(--p-surface-100); color: var(--p-primary-color); }
.sakai-logout-btn i { font-size: 16px; }

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

/* Collapsible group header — same look as a menu item, but a button. */
.sakai-group-toggle { width: 100%; background: transparent; border: none; cursor: pointer;
    font: inherit; text-align: start; font-size: 14.5px; font-weight: 500; }
.sakai-group-toggle.has-active { color: var(--p-primary-color); }
.sakai-group-toggle.has-active > i:first-child { color: var(--p-primary-color); }
.sakai-group-arrow { margin-inline-start: auto; font-size: 13px !important; width: auto !important;
    transition: transform .25s ease; }
.sakai-group-arrow.open { transform: rotate(180deg); }
/* A badge before the arrow shouldn't also claim the auto margin. */
.sakai-group-toggle .sakai-menu-badge { margin-inline-start: auto; }
.sakai-group-toggle .sakai-menu-badge + .sakai-group-arrow { margin-inline-start: 8px; }

/* Smooth expand/collapse via animatable grid rows (0fr → 1fr). */
.sakai-submenu-wrap { display: grid; grid-template-rows: 0fr; transition: grid-template-rows .25s ease; }
.sakai-submenu-wrap.open { grid-template-rows: 1fr; }
.sakai-submenu { list-style: none; margin: 0; padding: 0; overflow: hidden;
    padding-inline-start: 14px; margin-inline-start: 9px; border-inline-start: 1px solid var(--p-content-border-color); }
.sakai-submenu-wrap.open .sakai-submenu { padding-block: 2px; }
/* Child items sit indented and a touch smaller than their parent group. */
.sakai-submenu-item { font-size: 13.5px; padding: 9px 11px; }
.sakai-submenu-item i { font-size: 15px; }

.sakai-menu-badge { margin-inline-start: auto; min-width: 20px; height: 20px; padding: 0 6px; border-radius: 10px;
    display: inline-flex; align-items: center; justify-content: center;
    font-size: 11px; font-weight: 700; background: var(--p-primary-color); color: #fff; }
.sakai-scrim { position: fixed; inset: 0; z-index: 24; background: rgba(0,0,0,.4); }

/* Content */
.sakai-content { padding: 88px 0 40px; margin-inline-start: 268px; }
.sakai-content-inner { max-width: 1400px; margin: 0 auto; padding-inline: 28px; }

@media (max-width: 1023px) {
    /* Off-canvas drawer. `visibility: hidden` while closed keeps the panel from
       being painted (and tappable) once it has slid off-screen. Without it, an
       RTL sub-pixel/overflow quirk on mobile Chrome leaves the group-arrow tips
       peeking past the inline edge even though the drawer is translated away.
       The delayed visibility transition lets the slide-out finish first. */
    .sakai-sidebar { transform: translateX(-100%); visibility: hidden;
        transition: transform .2s ease, visibility 0s linear .2s; }
    [dir=rtl] .sakai-sidebar { transform: translateX(100%); }
    .sakai-sidebar.open { transform: translateX(0); visibility: visible;
        transition: transform .2s ease, visibility 0s; }
    .sakai-content { margin-inline-start: 0; }
}

/* Hamburger + scrim exist only below 1024px, where the sidebar is a drawer.
   Scoped here (not a Tailwind `lg:hidden` utility) so it can't be dropped by
   content-scanning and leave a dead button on desktop. */
@media (min-width: 1024px) {
    .sakai-mobile-only { display: none; }
}
</style>
