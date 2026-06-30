<script setup>
import PortalShell from '../../components/PortalShell.vue'

const nav = [
    { to: { name: 'admin.dashboard' }, labelKey: 'nav.dashboard', icon: '▦', end: true },
    { to: { name: 'admin.insights' }, labelKey: 'nav.insights', icon: '📊' },
    { to: { name: 'admin.restaurants' }, labelKey: 'nav.restaurants', icon: '▤' },
]
</script>

<template>
    <PortalShell title="QR Menu" role="Super Admin" mark="QM" theme="theme-indigo" :nav="nav" />
</template>
