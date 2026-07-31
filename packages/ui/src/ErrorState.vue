<script setup>
import { useI18n } from 'vue-i18n'
import Icon from './Icon.vue'

// A load-failure state with a retry action, used wherever a fetch can fail —
// distinct from an empty state so "something broke" never reads as "no data".
defineProps({
    message: { type: String, default: null },
})
const emit = defineEmits(['retry'])
const { t } = useI18n()
</script>

<template>
    <div class="card p-8 text-center space-y-3">
        <Icon name="alert" :size="28" style="color:var(--amber);margin-inline:auto" />
        <p class="text-sm" style="color:var(--muted)">{{ message || t('common.error') }}</p>
        <button @click="emit('retry')" class="btn btn-ghost btn-sm mx-auto">
            <Icon name="loading" :size="15" />{{ t('common.retry') }}
        </button>
    </div>
</template>
