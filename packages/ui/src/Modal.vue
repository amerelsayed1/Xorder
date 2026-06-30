<script setup>
import Icon from './Icon.vue'
defineProps({ title: { type: String, default: '' }, subtitle: { type: String, default: '' } })
const emit = defineEmits(['close'])
</script>

<template>
    <!-- Right slide-over sheet (matches the handoff create/detail pattern) -->
    <div class="sheet-overlay" @click.self="emit('close')">
        <div class="sheet">
            <div class="flex items-start justify-between px-6 py-4 border-b" style="border-color:var(--line)">
                <div>
                    <h3 class="page-title" style="font-size:18px">{{ title }}</h3>
                    <p v-if="subtitle" class="page-sub">{{ subtitle }}</p>
                </div>
                <button class="icon-btn" style="color:var(--muted)" @click="emit('close')"><Icon name="close" :size="20" /></button>
            </div>
            <div class="p-6">
                <slot />
            </div>
        </div>
    </div>
</template>
