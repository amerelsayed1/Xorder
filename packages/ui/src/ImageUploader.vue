<script setup>
import { ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { useImageUpload } from './composables/useImageUpload'

const props = defineProps({
    modelValue: { type: String, default: '' },
    folder: { type: String, default: 'uploads' },
    label: { type: String, default: '' },
})

const emit = defineEmits(['update:modelValue'])
const { t } = useI18n()
const { uploading, error, uploadFile, validateImageUrl, clearError } = useImageUpload()

const urlInput = ref('')
const showUrlInput = ref(false)

async function onChange(e) {
    const file = e.target.files?.[0]
    if (!file) return

    clearError()
    try {
        const url = await uploadFile(file, props.folder)
        emit('update:modelValue', url)
    } catch (err) {
        // Error is already set in the composable
    }
}

function addUrl() {
    if (!validateImageUrl(urlInput.value)) return

    emit('update:modelValue', urlInput.value.trim())
    urlInput.value = ''
    showUrlInput.value = false
}

function clearImage() {
    emit('update:modelValue', '')
    clearError()
}
</script>

<template>
    <div>
        <span class="label">{{ label || t('common.image') }}</span>
        <div class="mt-1.5 space-y-3">
            <!-- Current Image Preview -->
            <div v-if="modelValue" class="flex items-center gap-3">
                <img :src="modelValue" alt="" class="h-16 w-16 rounded-lg object-cover border" style="border-color:var(--line)" />
                <button type="button" @click="clearImage" class="btn btn-ghost btn-sm" style="color: var(--red)">
                    {{ t('common.clear') }}
                </button>
            </div>

            <!-- Two Upload Options -->
            <div v-else class="space-y-2">
                <!-- Option 1: Upload File -->
                <label class="block border-2 border-dashed rounded-lg p-4 cursor-pointer hover:bg-gray-50 transition text-center">
                    <div style="color:var(--muted)" class="text-sm font-medium">{{ uploading ? '…' : t('common.upload') }}</div>
                    <div style="color:var(--muted)" class="text-xs mt-1">{{ t('item.image') }} (JPG, PNG, GIF)</div>
                    <input type="file" accept="image/*" class="hidden" @change="onChange" :disabled="uploading" />
                </label>

                <!-- Option 2: Paste URL -->
                <div class="border-2 border-dashed rounded-lg p-4">
                    <input
                        v-model="urlInput"
                        type="url"
                        placeholder="https://example.com/image.jpg"
                        class="input w-full text-sm"
                        @keyup.enter="addUrl"
                    />
                    <div class="flex gap-2 mt-2">
                        <button type="button" @click="addUrl" class="btn btn-accent btn-sm flex-1">{{ t('common.save') }} URL</button>
                        <button type="button" @click="urlInput = ''" class="btn btn-ghost btn-sm">{{ t('common.clear') }}</button>
                    </div>
                </div>
            </div>
        </div>
        <p v-if="error" class="text-xs mt-2" style="color:#c0392b">{{ error }}</p>
    </div>
</template>
