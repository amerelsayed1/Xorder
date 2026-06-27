<script setup>
import { computed } from 'vue'

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
const cls = computed(() => map[String(props.value)] ?? 'badge-gray')
const text = computed(() => props.label ?? String(props.value))
const showDot = computed(() => props.dot && ['ACTIVE', 'SUSPENDED', 'ARCHIVED', 'true', 'false'].includes(String(props.value)))
</script>

<template>
    <span class="badge" :class="cls">
        <span v-if="showDot" class="dot"></span>{{ text }}
    </span>
</template>
