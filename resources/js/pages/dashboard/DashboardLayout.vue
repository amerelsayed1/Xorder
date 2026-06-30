<script setup>
import { computed } from 'vue'
import PortalShell from '../../components/PortalShell.vue'
import { useAuth } from '../../stores/auth'

const auth = useAuth()
const r = computed(() => auth.restaurant)
const title = computed(() => r.value?.name_en || r.value?.name_ar || 'Restaurant')
const mark = computed(() => (title.value || 'R').trim().charAt(0).toUpperCase())

const nav = [
    { to: { name: 'dashboard.home' }, labelKey: 'nav.dashboard', icon: '▦', end: true },
    { to: { name: 'dashboard.insights' }, labelKey: 'nav.insights', icon: '📊' },
    { to: { name: 'dashboard.items' }, labelKey: 'nav.items', icon: '☰' },
    { to: { name: 'dashboard.categories' }, labelKey: 'nav.categories', icon: '▤' },
    { to: { name: 'dashboard.qr' }, labelKey: 'nav.qr', icon: '▢' },
    { to: { name: 'dashboard.profile' }, labelKey: 'nav.profile', icon: '◈' },
]
</script>

<template>
    <PortalShell :title="title" role="Restaurant Admin" :mark="mark" theme="theme-warm" :nav="nav" />
</template>
