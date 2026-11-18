<script setup>
// Counter QR (guest paging, shared QR): the restaurant's ONE standing QR. Print it
// once and put it where customers wait. A customer scans it, types the number on
// their slip, and follows their order on their phone. Read-only: nothing here is
// edited, only shown and downloaded, so it stays usable on a lapsed plan.
import { ref, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import api from '@xorder/api-client/api.js'
import ListSkeleton from '@xorder/ui/ListSkeleton.vue'
import ErrorState from '@xorder/ui/ErrorState.vue'
import SettingsHeader from './SettingsHeader.vue'

const { t } = useI18n()

const loading = ref(true)
const failed = ref(false)
const svg = ref('')
const url = ref('')
const slug = ref('')

async function load() {
    loading.value = true
    failed.value = false
    try {
        const { data } = await api.get('api/dashboard/pager-qr')
        svg.value = data.data.svg
        url.value = data.data.join_url
        slug.value = new URL(data.data.join_url, window.location.origin).hostname.split('.')[0]
    } catch {
        failed.value = true
    } finally {
        loading.value = false
    }
}

async function download() {
    const res = await api.get('api/dashboard/pager-qr/download', { responseType: 'blob' })
    const blobUrl = URL.createObjectURL(res.data)
    const a = document.createElement('a')
    a.href = blobUrl
    a.download = `qr-counter-${slug.value || 'restaurant'}.png`
    a.click()
    URL.revokeObjectURL(blobUrl)
}

onMounted(load)
</script>

<template>
    <SettingsHeader :title="t('pagerQr.title')" :desc="t('pagerQr.intro')" />

    <div class="set-card">
        <ListSkeleton v-if="loading" :rows="3" />
        <ErrorState v-else-if="failed" @retry="load" />

        <div v-else class="pq">
            <div class="pq-code">
                <div class="pq-box" v-html="svg"></div>
                <button type="button" class="btn btn-dark" @click="download">{{ t('pagerQr.download') }}</button>
                <p class="pq-url" dir="ltr">{{ url }}</p>
            </div>

            <ol class="pq-steps">
                <li>{{ t('pagerQr.step1') }}</li>
                <li>{{ t('pagerQr.step2') }} <bdi class="pq-example" dir="ltr">MAIN-2026-000042</bdi></li>
                <li>{{ t('pagerQr.step3') }}</li>
            </ol>

            <p class="set-inset-hint">{{ t('pagerQr.note') }}</p>
        </div>
    </div>
</template>

<style scoped>
.pq { display: grid; gap: 24px; justify-items: start; }
.pq-code { display: grid; gap: 12px; justify-items: center; }
.pq-box { width: 15rem; height: 15rem; max-width: 100%; background: #fff; padding: 8px; border-radius: 12px; border: 1px solid var(--line); }
.pq-box :deep(svg) { width: 100%; height: 100%; display: block; }
.pq-url { margin: 0; font-size: 13px; color: var(--muted); word-break: break-all; text-align: center; }
.pq-steps { margin: 0; padding-inline-start: 1.25rem; display: grid; gap: 10px; max-width: 46ch; line-height: 1.55; }
.pq-example { white-space: nowrap; font-weight: 700; }
</style>
