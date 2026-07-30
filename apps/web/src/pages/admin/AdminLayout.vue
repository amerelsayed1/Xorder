<script setup>
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { useAuth } from '@xorder/api-client/auth.js'
import SakaiLayout from '@xorder/ui/SakaiLayout.vue'

const { t } = useI18n()
const auth = useAuth()

// Show the signed-in user's actual platform role (Super Admin / Admin /
// Moderator / Sales / Support).
const role = computed(() => t(`roles.${(auth.platformRole || 'super_admin').toLowerCase()}`))

// Each entry carries the capability its destination needs; the nav is filtered
// so a role only sees the sections it can open (mirrors the router + API gates).
// A `null` cap means "always visible" (e.g. the dashboard home).
const allNav = [
    { to: { name: 'admin.dashboard' }, labelKey: 'nav.dashboard', icon: 'pi pi-th-large', end: true, cap: null },
    { to: { name: 'admin.insights' }, labelKey: 'nav.insights', icon: 'pi pi-chart-bar', cap: 'insights.view' },
    { to: { name: 'admin.restaurants' }, labelKey: 'nav.restaurants', icon: 'pi pi-building', cap: 'restaurants.view' },
    { to: { name: 'admin.users' }, labelKey: 'nav.users', icon: 'pi pi-users', cap: 'platform_users.manage' },
    { to: { name: 'admin.plans' }, labelKey: 'nav.plans', icon: 'pi pi-tags', cap: 'plans.manage' },
    { to: { name: 'admin.leads' }, labelKey: 'nav.leads', icon: 'pi pi-inbox', cap: 'leads.manage' },
    { to: { name: 'admin.audit' }, labelKey: 'nav.audit', icon: 'pi pi-history', cap: 'audit.view' },
    {
        key: 'settings',
        labelKey: 'nav.settings',
        icon: 'pi pi-cog',
        cap: 'landing.manage',
        children: [
            { to: { name: 'admin.settings.seo' }, labelKey: 'nav.settings_seo', icon: 'pi pi-search' },
            { to: { name: 'admin.settings.hero' }, labelKey: 'nav.settings_hero', icon: 'pi pi-star' },
            { to: { name: 'admin.settings.whatsapp' }, labelKey: 'nav.settings_whatsapp', icon: 'pi pi-whatsapp' },
            { to: { name: 'admin.settings.highlights' }, labelKey: 'nav.settings_highlights', icon: 'pi pi-verified' },
            { to: { name: 'admin.settings.features' }, labelKey: 'nav.settings_features', icon: 'pi pi-th-large' },
            { to: { name: 'admin.settings.industries' }, labelKey: 'nav.settings_industries', icon: 'pi pi-briefcase' },
            { to: { name: 'admin.settings.demo' }, labelKey: 'nav.settings_demo', icon: 'pi pi-play' },
            { to: { name: 'admin.settings.faq' }, labelKey: 'nav.settings_faq', icon: 'pi pi-question-circle' },
            { to: { name: 'admin.settings.lead_cta' }, labelKey: 'nav.settings_lead_cta', icon: 'pi pi-send' },
        ],
    },
]

const nav = computed(() => allNav.filter((item) => item.cap == null || auth.can(item.cap)))
</script>

<template>
    <SakaiLayout title="Xorder" :role="role" mark="X" :nav="nav" />
</template>
