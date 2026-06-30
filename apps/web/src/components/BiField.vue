<script setup>
// Bilingual (EN + AR) text input pair used by the landing content editor.
defineProps({
    label: { type: String, default: '' },
    en: { type: String, default: '' },
    ar: { type: String, default: '' },
    textarea: { type: Boolean, default: false },
})
const emit = defineEmits(['update:en', 'update:ar'])
</script>

<template>
    <div>
        <div v-if="label" class="label">{{ label }}</div>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-2" :class="{ 'mt-1.5': label }">
            <component
                :is="textarea ? 'textarea' : 'input'"
                class="input"
                :rows="textarea ? 2 : undefined"
                placeholder="English"
                :value="en"
                @input="emit('update:en', $event.target.value)" />
            <component
                :is="textarea ? 'textarea' : 'input'"
                class="input"
                dir="rtl"
                :rows="textarea ? 2 : undefined"
                placeholder="العربية"
                :value="ar"
                @input="emit('update:ar', $event.target.value)" />
        </div>
    </div>
</template>
