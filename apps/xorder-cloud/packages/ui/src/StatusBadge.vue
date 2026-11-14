<script setup>
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'

const props = defineProps({
    value: { type: [String, Boolean], required: true },
    label: { type: String, default: null },
    dot: { type: Boolean, default: true },
})

const map = {
    ACTIVE: 'badge-green',
    SUSPENDED: 'badge-red',
    ARCHIVED: 'badge-gray',
    EXPIRED: 'badge-red',
    TRIAL: 'badge-amber',
    true: 'badge-green',
    false: 'badge-gray',
}
const { t } = useI18n()
const cls = computed(() => map[String(props.value)] ?? 'badge-gray')
const text = computed(() => {
    if (props.label) return props.label
    const value = String(props.value)
    if (value === 'true') return t('common.active')
    if (value === 'false') return t('common.inactive')
    if (['ACTIVE', 'SUSPENDED', 'ARCHIVED'].includes(value)) return t('status.' + value)
    if (['TRIAL', 'EXPIRED'].includes(value)) return t('subscription_status.' + value)
    return value
})
const showDot = computed(() => props.dot && ['ACTIVE', 'SUSPENDED', 'ARCHIVED', 'true', 'false'].includes(String(props.value)))
</script>

<template>
    <span class="badge" :class="cls">
        <span v-if="showDot" class="dot"></span>{{ text }}
    </span>
</template>
