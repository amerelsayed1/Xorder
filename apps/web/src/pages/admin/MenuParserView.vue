<script setup>
import { ref } from 'vue'
import { useI18n } from 'vue-i18n'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import Icon from '@xorder/ui/Icon.vue'

const { t } = useI18n()
const file = ref(null)
const preview = ref(null)
const loading = ref(false)
const parsedItems = ref([])
const error = ref(null)
const copySuccess = ref(null)

function onFileSelected(e) {
    const selectedFile = e.target.files?.[0]
    if (!selectedFile) return

    file.value = selectedFile
    error.value = null
    parsedItems.value = []

    const reader = new FileReader()
    reader.onload = (event) => {
        preview.value = event.target?.result
    }
    reader.readAsDataURL(selectedFile)
}

async function parseMenu() {
    if (!file.value) {
        error.value = 'Please select an image'
        return
    }

    loading.value = true
    error.value = null

    try {
        await ensureCsrf()
        const formData = new FormData()
        formData.append('image', file.value)

        const response = await api.post('api/admin/menu-parser/parse', formData, {
            headers: {
                'Content-Type': 'multipart/form-data',
            },
        })

        parsedItems.value = response.data.data || []
    } catch (err) {
        error.value = err.response?.data?.error || 'Failed to parse menu. Please try again.'
        console.error('Parse error:', err)
    } finally {
        loading.value = false
    }
}

function copyToClipboard(text) {
    navigator.clipboard.writeText(text).then(() => {
        copySuccess.value = text
        setTimeout(() => {
            copySuccess.value = null
        }, 2000)
    })
}
</script>

<template>
    <div class="space-y-6">
        <div>
            <h1 class="page-title">{{ t('admin.menu_parser') }}</h1>
            <p class="page-sub">{{ t('admin.menu_parser_subtitle') }}</p>
        </div>

        <div class="card space-y-4">
            <div>
                <label class="block text-sm font-medium mb-2">{{ t('admin.upload_image') }}</label>
                <div class="border-2 border-dashed rounded-lg p-6 text-center cursor-pointer hover:bg-gray-50 transition"
                    @click="$refs.fileInput?.click()">
                    <Icon v-if="!preview" name="upload" :size="24" class="mx-auto mb-2 opacity-50" />
                    <img v-else :src="preview" alt="Preview" class="h-32 mx-auto mb-2 object-cover rounded" />
                    <p class="text-sm font-medium">{{ t('admin.click_to_upload') }}</p>
                    <p class="text-xs text-gray-500">{{ t('admin.image_formats') }}</p>
                </div>
                <input
                    ref="fileInput"
                    type="file"
                    accept="image/*"
                    class="hidden"
                    @change="onFileSelected"
                />
            </div>

            <div v-if="error" class="p-3 bg-red-100 text-red-700 rounded text-sm">
                {{ error }}
            </div>

            <button
                @click="parseMenu"
                :disabled="!file || loading"
                class="btn btn-accent w-full"
            >
                <Icon v-if="loading" name="loading" :size="16" class="animate-spin" />
                {{ loading ? t('common.loading') : t('admin.parse_menu') }}
            </button>
        </div>

        <div v-if="parsedItems.length > 0" class="card space-y-4">
            <div class="flex items-center justify-between">
                <h2 class="text-lg font-semibold">{{ t('admin.parsed_items') }} ({{ parsedItems.length }})</h2>
            </div>

            <div class="space-y-3 max-h-96 overflow-y-auto">
                <div
                    v-for="(item, index) in parsedItems"
                    :key="index"
                    class="border rounded-lg p-4 bg-gray-50 hover:bg-gray-100 transition"
                >
                    <div class="flex items-start justify-between gap-3">
                        <div class="flex-1">
                            <h3 class="font-semibold text-sm">{{ item.name }}</h3>
                            <p v-if="item.description" class="text-xs text-gray-600 mt-1">{{ item.description }}</p>
                            <p v-if="item.price" class="text-sm font-medium text-accent mt-2">
                                {{ item.price.toLocaleString() }}
                            </p>
                        </div>
                        <button
                            @click="copyToClipboard(JSON.stringify(item, null, 2))"
                            class="text-xs px-2 py-1 rounded hover:bg-gray-200 transition"
                        >
                            <Icon name="copy" :size="14" />
                        </button>
                    </div>
                </div>
            </div>

            <div v-if="copySuccess" class="p-2 bg-green-100 text-green-700 rounded text-xs text-center">
                Copied to clipboard
            </div>

            <details class="border rounded-lg p-3">
                <summary class="cursor-pointer font-medium text-sm">{{ t('admin.view_json') }}</summary>
                <pre class="mt-2 bg-gray-900 text-green-400 p-3 rounded text-xs overflow-x-auto">{{ JSON.stringify(parsedItems, null, 2) }}</pre>
            </details>
        </div>
    </div>
</template>
