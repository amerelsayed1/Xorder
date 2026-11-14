<script setup>
// A row of tabs across sibling list pages that share one sidebar entry
// (Purchasing: orders / invoices / payments; Stock: levels / items). Each tab
// is a real route, so the URL says which one is open and the back button works.
// A tab stays lit on its detail pages via route-name prefix, like the sidebar.
import { RouterLink, useRoute } from 'vue-router'
import { useI18n } from 'vue-i18n'

defineProps({
    // [{ to: { name }, labelKey, match?: [route-name prefixes] }]
    tabs: { type: Array, required: true },
})

const { t } = useI18n()
const route = useRoute()
const isActive = (tab) => {
    const name = String(route.name || '')
    return (tab.match || [tab.to.name]).some((p) => name.startsWith(p))
}
</script>

<template>
    <nav class="page-tabs" role="tablist">
        <RouterLink v-for="tab in tabs" :key="tab.to.name" :to="tab.to"
            class="page-tab" :class="{ active: isActive(tab) }"
            role="tab" :aria-selected="isActive(tab)" :aria-current="isActive(tab) ? 'page' : undefined">
            {{ t(tab.labelKey) }}
        </RouterLink>
    </nav>
</template>

<style scoped>
.page-tabs { display: flex; gap: 4px; overflow-x: auto; border-bottom: 1px solid var(--line); scrollbar-width: none; }
.page-tabs::-webkit-scrollbar { display: none; }
.page-tab { flex: none; padding: 10px 16px; margin-bottom: -1px; border-bottom: 2px solid transparent;
    font-size: 14px; font-weight: 500; color: var(--muted); text-decoration: none; white-space: nowrap;
    transition: color .15s, border-color .15s; }
.page-tab:hover { color: var(--ink); }
.page-tab.active { color: var(--accent-dark, var(--ink)); border-bottom-color: var(--accent); font-weight: 600; }
</style>
