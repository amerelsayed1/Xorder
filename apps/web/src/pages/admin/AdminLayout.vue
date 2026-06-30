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
    { to: { name: 'admin.landing' }, labelKey: 'nav.landing', icon: 'pi pi-megaphone' },
    { to: { name: 'admin.leads' }, labelKey: 'nav.leads', icon: 'pi pi-inbox' },
]
</script>

<template>
    <SakaiLayout title="Xorder" :role="role" mark="X" :nav="nav" />
</template>
