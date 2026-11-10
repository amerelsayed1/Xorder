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
    // Three node shapes, freely mixed:
    //   flat item   { to, labelKey, icon, badge?, end?, match? }
    //   group       { key, labelKey, icon, badge?, children: [item] }   accordion, one open at a time
    //   section     { key, labelKey, section: true, children: [item] }  heading + always-visible items
    // `match` is an optional list of route-NAME prefixes that also light the
    // item up, for one entry that stands for several pages (tabbed screens,
    // a settings shell whose index route is not a parent of its sections).
    nav: { type: Array, required: true },
    // Show a "search pages" box above the menu. It filters every reachable
    // leaf by its translated label, so it can only offer what `nav` offers.
    searchable: { type: Boolean, default: false },
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
    return Array.isArray(group.children) && group.children.some((c) => isChildActive(c) || matchesName(c))
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

// --- Route-name matching -----------------------------------------------------
function matchesName(item) {
    const name = String(route.name || '')
    return Array.isArray(item.match) && item.match.some((p) => name.startsWith(p))
}
// RouterLink's own isActive, widened by `match`.
function itemActive(item, isActive, isExactActive) {
    if (matchesName(item)) return true
    return item.end ? isExactActive : isActive
}

// --- Sections (always-visible headings) ------------------------------------
// A section can be folded by hand; the choice is a per-browser convenience, so
// storage that throws (private window, blocked site data) must never break the
// menu. The section holding the current page is always shown regardless.
const COLLAPSE_KEY = 'xorder.nav.collapsed'
const collapsed = ref((() => {
    try { return JSON.parse(localStorage.getItem(COLLAPSE_KEY) || '{}') || {} } catch { return {} }
})())
function sectionActive(section) {
    return (section.children || []).some((c) => {
        if (matchesName(c)) return true
        let path
        try { path = router.resolve(c.to).path } catch { return false }
        return c.end ? route.path === path : (route.path === path || route.path.startsWith(path + '/'))
    })
}
function sectionOpen(section) {
    return !collapsed.value[section.key] || sectionActive(section)
}
function toggleSection(section) {
    collapsed.value = { ...collapsed.value, [section.key]: sectionOpen(section) }
    try { localStorage.setItem(COLLAPSE_KEY, JSON.stringify(collapsed.value)) } catch { /* storage unavailable */ }
}
// A folded section still says something is waiting inside it.
const sectionBadge = (section) => (section.children || []).reduce((n, c) => n + (Number(c.badge) || 0), 0)
const hasSections = computed(() => props.nav.some((n) => n.section))

// --- Page search -------------------------------------------------------------
const query = ref('')
const leaves = computed(() => props.nav.flatMap((n) => (n.children
    ? n.children.map((c) => ({ ...c, parentLabelKey: n.labelKey }))
    : [n])))
const results = computed(() => {
    const q = query.value.trim().toLowerCase()
    if (!q) return []
    // Match in both languages: an owner on the Arabic UI often types the
    // English name of a page (and vice versa).
    const labels = (key) => ['ar', 'en'].map((lng) => t(key, {}, { locale: lng }).toLowerCase())
    return leaves.value.filter((l) => labels(l.labelKey).some((x) => x.includes(q))
        || (l.parentLabelKey && labels(l.parentLabelKey).some((x) => x.includes(q))))
})
function goFirstResult() {
    const first = results.value[0]
    if (!first) return
    router.push(first.to)
    query.value = ''
    mobileOpen.value = false
}
function pickResult(navigate, e) {
    navigate(e)
    query.value = ''
    mobileOpen.value = false
}

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
            <div v-if="searchable" class="sakai-search">
                <i class="pi pi-search" aria-hidden="true" />
                <input v-model="query" type="search" class="sakai-search-input"
                    :placeholder="t('nav.search_pages')" :aria-label="t('nav.search_pages')"
                    @keydown.enter.prevent="goFirstResult" @keydown.esc="query = ''" />
            </div>

            <!-- Search results replace the menu while a query is typed. -->
            <ul v-if="query.trim()" class="sakai-menu">
                <li v-for="r in results" :key="'s-' + (r.key ?? r.to?.name)">
                    <RouterLink :to="r.to" custom v-slot="{ href, navigate }">
                        <a :href="href" class="sakai-menu-item" @click="pickResult(navigate, $event)">
                            <i :class="r.icon" />
                            <span class="sakai-result-text">
                                <span>{{ t(r.labelKey) }}</span>
                                <small v-if="r.parentLabelKey">{{ t(r.parentLabelKey) }}</small>
                            </span>
                        </a>
                    </RouterLink>
                </li>
                <li v-if="!results.length" class="sakai-search-empty">{{ t('nav.search_none') }}</li>
            </ul>

            <ul v-else class="sakai-menu">
                <li v-if="!hasSections" class="sakai-menu-label">{{ t('common.menu') }}</li>
                <li v-for="link in nav" :key="link.key ?? link.to?.name ?? link.labelKey">
                    <!-- Section: a heading with its items always listed beneath -->
                    <template v-if="link.section">
                        <button type="button" class="sakai-section-toggle"
                            :aria-expanded="sectionOpen(link)"
                            :aria-controls="`sakai-section-${link.key}`"
                            @click="toggleSection(link)">
                            <span>{{ t(link.labelKey) }}</span>
                            <span v-if="!sectionOpen(link) && sectionBadge(link)" class="sakai-menu-badge">{{ sectionBadge(link) }}</span>
                            <i class="pi pi-angle-down sakai-group-arrow" :class="{ open: sectionOpen(link) }" aria-hidden="true" />
                        </button>
                        <ul v-show="sectionOpen(link)" :id="`sakai-section-${link.key}`" class="sakai-section-list">
                            <li v-for="child in link.children" :key="child.key ?? child.to.name">
                                <RouterLink :to="child.to" custom v-slot="{ href, navigate, isActive, isExactActive }">
                                    <a :href="href" class="sakai-menu-item"
                                        :class="{ active: itemActive(child, isActive, isExactActive) }"
                                        @click="navigate($event); mobileOpen = false">
                                        <i :class="child.icon" /><span>{{ t(child.labelKey) }}</span>
                                        <span v-if="child.badge" class="sakai-menu-badge">{{ child.badge }}</span>
                                    </a>
                                </RouterLink>
                            </li>
                        </ul>
                    </template>
                    <!-- Collapsible group -->
                    <template v-else-if="link.children">
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
                                            :class="{ active: itemActive(child, isActive, isExactActive) }"
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
                        <a :href="href" class="sakai-menu-item" :class="{ active: itemActive(link, isActive, isExactActive) }"
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
.sakai-profile-side { width: auto; border-radius: 0; padding: 10px 16px 2px;
    margin: 0 -16px -16px; border-top: 1px solid var(--p-content-border-color);
    cursor: default; }
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

/* Section heading: quiet, uppercase-free label that folds its list. */
.sakai-section-toggle { display: flex; align-items: center; gap: 8px; width: 100%;
    margin-top: 14px; padding: 6px 12px; background: transparent; border: none; cursor: pointer;
    font: inherit; font-size: 12px; font-weight: 600; letter-spacing: .02em; text-align: start;
    color: var(--p-text-muted-color); border-radius: 7px; }
.sakai-menu > li:first-child > .sakai-section-toggle { margin-top: 0; }
.sakai-section-toggle:hover { color: var(--p-text-color); }
.sakai-section-toggle .sakai-group-arrow { font-size: 11px !important; }
.sakai-section-toggle .sakai-menu-badge { margin-inline-start: auto; }
.sakai-section-toggle .sakai-menu-badge + .sakai-group-arrow { margin-inline-start: 6px; }
.sakai-section-list { list-style: none; margin: 2px 0 0; padding: 0; display: flex; flex-direction: column; gap: 1px; }
.sakai-section-list .sakai-menu-item { padding: 9px 12px; }

/* Page search */
.sakai-search { position: relative; margin-bottom: 6px; }
.sakai-search > i { position: absolute; top: 50%; transform: translateY(-50%); inset-inline-start: 12px;
    font-size: 13px; color: var(--p-text-muted-color); pointer-events: none; }
.sakai-search-input { width: 100%; height: 38px; padding-inline: 34px 10px; border-radius: 9px;
    border: 1px solid var(--p-content-border-color); background: var(--p-surface-50);
    font: inherit; font-size: 13.5px; color: var(--p-text-color); outline: none; }
.sakai-search-input:focus { border-color: var(--p-primary-color); background: var(--p-content-background); }
.sakai-result-text { display: flex; flex-direction: column; line-height: 1.25; min-width: 0; }
.sakai-result-text small { font-size: 11.5px; color: var(--p-text-muted-color); font-weight: 400; }
.sakai-search-empty { padding: 12px; font-size: 13px; color: var(--p-text-muted-color); }

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

/* Very narrow phones (360px class): the 22px top-bar gutters alone pushed the
   last control off screen. */
@media (max-width: 400px) {
    .sakai-topbar { padding: 0 10px; gap: 6px; }
}
</style>
