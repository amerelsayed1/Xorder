<script setup>
import { ref, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import api from '@xorder/api-client/api.js'
import Icon from '@xorder/ui/Icon.vue'
import { alert } from '@xorder/ui/alert.js'

const { t } = useI18n()
const qr = ref(null)
const copied = ref(false)

onMounted(async () => {
    const { data } = await api.get('api/dashboard/qr')
    qr.value = data.data
})
// JWT-Bearer API: fetch the PNG through the authed client (a bare window.open
// carries no Authorization header and 401s), then save the blob.
async function download() {
    try {
        const res = await api.get('api/dashboard/qr/download', { responseType: 'blob' })
        const blobUrl = URL.createObjectURL(res.data)
        const a = document.createElement('a')
        a.href = blobUrl; a.download = 'qr-menu.png'; a.click()
        URL.revokeObjectURL(blobUrl)
    } catch (err) { alert(err.response?.data?.message || t('admin.download_failed')) }
}
function copyUrl() {
    if (!qr.value) return
    navigator.clipboard?.writeText(qr.value.public_url)
    copied.value = true
    setTimeout(() => (copied.value = false), 1600)
}
</script>

<template>
    <div v-if="qr" class="space-y-5">
        <div>
            <h1 class="page-title">{{ t('nav.qr') }}</h1>
            <p class="page-sub">{{ t('dashboard.qr_help') }}</p>
        </div>

        <div class="qr-card max-w-md mx-auto">
            <h2 class="text-lg font-semibold" style="font-family:var(--font-display)">{{ t('dashboard.qr_title') }}</h2>
            <p class="text-sm mt-1" style="color:rgba(255,255,255,.55)">{{ t('dashboard.qr_scan_help') }}</p>
            <div class="bg-white p-4 rounded-2xl mt-5 inline-block">
                <div v-html="qr.svg" class="qrbox h-56 w-56"></div>
            </div>
            <div class="url-chip mt-5 text-center" style="background:rgba(255,255,255,.08);border-color:rgba(255,255,255,.14);color:#fff">{{ qr.public_url }}</div>
            <div class="flex gap-2 justify-center mt-5">
                <button @click="download" class="btn btn-ghost"><Icon name="download" :size="16" />{{ t('admin.download_png') }}</button>
                <button @click="copyUrl" class="btn btn-dark"><Icon :name="copied ? 'check' : 'copy'" :size="16" />{{ copied ? t('common.copied') : t('dashboard.copy_link') }}</button>
            </div>
        </div>
    </div>
</template>
