<script setup>
import { ref } from 'vue'
import { useI18n } from 'vue-i18n'
import api, { ensureCsrf } from '@xorder/api-client/api.js'

const props = defineProps({
    modelValue: { type: String, default: '' },
    folder: { type: String, default: 'uploads' },
    label: { type: String, default: '' },
})
const emit = defineEmits(['update:modelValue'])
const { t } = useI18n()

const uploading = ref(false)
const error = ref('')

async function onChange(e) {
    const file = e.target.files?.[0]
    if (!file) return
    error.value = ''
    uploading.value = true
    try {
        await ensureCsrf()
        const form = new FormData()
        form.append('image', file)
        form.append('folder', props.folder)
        const { data } = await api.post('api/uploads/image', form)
        emit('update:modelValue', data.data.url)
    } catch (err) {
        error.value = err.response?.data?.message || t('common.upload_failed')
    } finally {
        uploading.value = false
    }
}
</script>

<template>
    <div>
        <span class="label">{{ label || t('common.image') }}</span>
        <div class="mt-1.5 flex items-center gap-3">
            <img v-if="modelValue" :src="modelValue" alt=""
                class="h-14 w-14 rounded-lg object-cover border" style="border-color:var(--line)" />
            <div v-else class="h-14 w-14 rounded-lg grid place-items-center text-lg"
                style="background:var(--accent-soft);color:var(--muted)">⬆</div>
            <label class="btn btn-ghost cursor-pointer">
                {{ uploading ? '…' : t('common.upload') }}
                <input type="file" accept="image/*" class="hidden" @change="onChange" />
            </label>
        </div>
        <p v-if="error" class="text-xs mt-1" style="color:#c0392b">{{ error }}</p>
    </div>
</template>
