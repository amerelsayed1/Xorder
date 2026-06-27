<script setup>
import { ref, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import api from '../../lib/api'

const { t } = useI18n()
const qr = ref(null)

onMounted(async () => {
    const { data } = await api.get('api/dashboard/qr')
    qr.value = data.data
})
function download() { window.open('/api/dashboard/qr/download', '_blank') }
function copyUrl() { if (qr.value) navigator.clipboard?.writeText(qr.value.public_url) }
</script>

<template>
    <div v-if="qr" class="space-y-5">
        <div>
            <h1 class="page-title">{{ t('nav.qr') }}</h1>
            <p class="page-sub">Print it for tables & takeaway.</p>
        </div>

        <div class="qr-card max-w-md mx-auto">
            <h2 class="text-lg font-semibold" style="font-family:var(--font-display)">Your QR code</h2>
            <p class="text-sm mt-1" style="color:rgba(255,255,255,.55)">Scan to open the public menu</p>
            <div class="bg-white p-4 rounded-2xl mt-5 inline-block">
                <div v-html="qr.svg" class="qrbox h-56 w-56"></div>
            </div>
            <div class="url-chip mt-5 text-center" style="background:rgba(255,255,255,.08);border-color:rgba(255,255,255,.14);color:#fff">{{ qr.public_url }}</div>
            <div class="flex gap-2 justify-center mt-5">
                <button @click="download" class="btn btn-ghost">Download PNG</button>
                <button @click="copyUrl" class="btn btn-dark">Copy link</button>
            </div>
        </div>
    </div>
</template>
