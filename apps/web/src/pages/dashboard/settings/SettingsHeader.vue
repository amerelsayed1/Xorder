<script setup>
// The header above every settings section: breadcrumb, title, description and
// the section's own actions. It lives inside each section rather than in the
// shell so the buttons keep their handlers and their capability gates — a
// shell-owned header would have to receive them second-hand.
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute } from 'vue-router'

defineProps({
    title: { type: String, required: true },
    desc: { type: String, default: '' },
})

const { t } = useI18n()
// The same header serves the Team pages, which sit under their own crumb.
const route = useRoute()
const crumb = computed(() => t(route.meta.crumbKey || 'settings_shell.title'))
</script>

<template>
    <header class="set-head">
        <div class="set-head-text">
            <span class="set-crumb">{{ crumb }}</span>
            <h1 class="set-title">{{ title }}</h1>
            <p v-if="desc" class="set-desc">{{ desc }}</p>
        </div>
        <div v-if="$slots.actions" class="set-head-actions">
            <slot name="actions" />
        </div>
    </header>
</template>
