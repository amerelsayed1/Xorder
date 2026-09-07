<script setup>
// The header above every settings section: breadcrumb, title, description and
// the section's own actions. It lives inside each section rather than in the
// shell so the buttons keep their handlers and their capability gates — a
// shell-owned header would have to receive them second-hand.
import { useI18n } from 'vue-i18n'

defineProps({
    title: { type: String, required: true },
    desc: { type: String, default: '' },
})

const { t } = useI18n()
</script>

<template>
    <header class="set-head">
        <div class="set-head-text">
            <span class="set-crumb">{{ t('settings_shell.title') }}</span>
            <h1 class="set-title">{{ title }}</h1>
            <p v-if="desc" class="set-desc">{{ desc }}</p>
        </div>
        <div v-if="$slots.actions" class="set-head-actions">
            <slot name="actions" />
        </div>
    </header>
</template>
