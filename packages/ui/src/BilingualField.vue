<script setup>
import { useI18n } from 'vue-i18n'

defineProps({
    modelAr: { type: String, default: '' },
    modelEn: { type: String, default: '' },
    labelKey: { type: String, default: 'common.name' },
    textarea: { type: Boolean, default: false },
})
const emit = defineEmits(['update:modelAr', 'update:modelEn'])
const { t } = useI18n()
</script>

<template>
    <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
        <label class="block">
            <span class="text-sm text-gray-600">{{ t(labelKey + '_en') }}</span>
            <component :is="textarea ? 'textarea' : 'input'"
                :value="modelEn"
                @input="emit('update:modelEn', $event.target.value)"
                class="mt-1 w-full rounded-lg border border-gray-300 px-3 py-2 text-sm" />
        </label>
        <label class="block" dir="rtl">
            <span class="text-sm text-gray-600">{{ t(labelKey + '_ar') }}</span>
            <component :is="textarea ? 'textarea' : 'input'"
                :value="modelAr"
                @input="emit('update:modelAr', $event.target.value)"
                class="mt-1 w-full rounded-lg border border-gray-300 px-3 py-2 text-sm" />
        </label>
    </div>
</template>
