<script setup>
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import SakaiLayout from '@xorder/ui/SakaiLayout.vue'

const { t } = useI18n()
const role = computed(() => t('roles.super_admin'))

const nav = [
    { to: { name: 'admin.dashboard' }, labelKey: 'nav.dashboard', icon: 'pi pi-th-large', end: true },
    { to: { name: 'admin.insights' }, labelKey: 'nav.insights', icon: 'pi pi-chart-bar' },
    { to: { name: 'admin.restaurants' }, labelKey: 'nav.restaurants', icon: 'pi pi-building' },
    { to: { name: 'admin.plans' }, labelKey: 'nav.plans', icon: 'pi pi-tags' },
    { to: { name: 'admin.leads' }, labelKey: 'nav.leads', icon: 'pi pi-inbox' },
    { to: { name: 'admin.audit' }, labelKey: 'nav.audit', icon: 'pi pi-history' },
    {
        key: 'settings',
        labelKey: 'nav.settings',
        icon: 'pi pi-cog',
        children: [
            { to: { name: 'admin.settings.seo' }, labelKey: 'nav.settings_seo', icon: 'pi pi-search' },
            { to: { name: 'admin.settings.hero' }, labelKey: 'nav.settings_hero', icon: 'pi pi-star' },
            { to: { name: 'admin.settings.whatsapp' }, labelKey: 'nav.settings_whatsapp', icon: 'pi pi-whatsapp' },
            { to: { name: 'admin.settings.highlights' }, labelKey: 'nav.settings_highlights', icon: 'pi pi-verified' },
            { to: { name: 'admin.settings.features' }, labelKey: 'nav.settings_features', icon: 'pi pi-th-large' },
            { to: { name: 'admin.settings.demo' }, labelKey: 'nav.settings_demo', icon: 'pi pi-play' },
            { to: { name: 'admin.settings.packages' }, labelKey: 'nav.settings_packages', icon: 'pi pi-money-bill' },
            { to: { name: 'admin.settings.lead_cta' }, labelKey: 'nav.settings_lead_cta', icon: 'pi pi-send' },
        ],
    },
]
</script>

<template>
    <SakaiLayout title="Xorder" :role="role" mark="X" :nav="nav" />
</template>
