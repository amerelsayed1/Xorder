<script setup>
import Icon from '@xorder/ui/Icon.vue'

defineProps({
    title: { type: String, required: true },
    open: { type: Boolean, default: false },
})
</script>

<template>
    <details class="card mt-5 admin-section" :open="open">
        <summary class="p-5 flex items-center justify-between gap-3 cursor-pointer select-none">
            <h2 class="h-card">{{ title }}</h2>
            <span class="flex items-center gap-4">
                <!-- Header controls must not toggle the section -->
                <span v-if="$slots.actions" class="flex items-center gap-3" @click.stop>
                    <slot name="actions" />
                </span>
                <Icon name="chevronDown" :size="16" class="chev" style="color:var(--muted)" />
            </span>
        </summary>
        <div class="px-5 pb-5">
            <slot />
        </div>
    </details>
</template>

<style scoped>
summary { list-style: none; }
summary::-webkit-details-marker { display: none; }
.chev { transition: transform 0.2s ease; flex-shrink: 0; }
details[open] .chev { transform: rotate(180deg); }
</style>
