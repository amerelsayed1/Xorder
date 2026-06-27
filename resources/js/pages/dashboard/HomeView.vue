<script setup>
import { ref, onMounted } from 'vue'
import { RouterLink } from 'vue-router'
import { useI18n } from 'vue-i18n'
import api from '../../lib/api'

const { t } = useI18n()
const stats = ref(null)
const qr = ref(null)

onMounted(async () => {
    const { data } = await api.get('api/dashboard/stats')
    stats.value = data.data
    const q = await api.get('api/dashboard/qr')
    qr.value = q.data.data
})

function copyUrl() {
    if (stats.value) navigator.clipboard?.writeText(stats.value.public_url)
}
</script>

<template>
    <div v-if="stats" class="space-y-6">
        <!-- Header -->
        <div class="flex flex-wrap items-start justify-between gap-3">
            <div>
                <h1 class="page-title">{{ t('nav.dashboard') }}</h1>
                <p class="page-sub">Here's how your menu is doing today.</p>
            </div>
            <div class="flex items-center gap-2">
                <a :href="stats.public_url" target="_blank" class="btn btn-ghost">↗ View menu</a>
                <RouterLink :to="{ name: 'dashboard.items' }" class="btn btn-accent">+ Add item</RouterLink>
            </div>
        </div>

        <!-- Stat cards -->
        <div class="grid grid-cols-2 lg:grid-cols-4 gap-4">
            <div class="stat">
                <div class="stat-label">{{ t('stats.total_categories') }}</div>
                <div class="stat-num">{{ stats.total_categories }}</div>
            </div>
            <div class="stat">
                <div class="stat-label">{{ t('stats.total_items') }}</div>
                <div class="stat-num">{{ stats.total_items }}</div>
            </div>
            <div class="stat">
                <div class="stat-label">{{ t('stats.available_items') }}</div>
                <div class="stat-num" style="color:var(--green)">{{ stats.available_items }}</div>
            </div>
            <div class="stat">
                <div class="stat-label">{{ t('stats.unavailable_items') }}</div>
                <div class="stat-num" style="color:var(--accent)">{{ stats.unavailable_items }}</div>
            </div>
        </div>

        <!-- Two-column area -->
        <div class="grid gap-6 lg:grid-cols-2">
            <!-- Left column -->
            <div class="space-y-6">
                <!-- Public URL -->
                <div class="card p-5">
                    <h2 class="h-card mb-3">{{ t('restaurant.public_url') }}</h2>
                    <div class="flex items-center gap-3">
                        <div class="url-chip flex-1 min-w-0">{{ stats.public_url }}</div>
                        <button @click="copyUrl" class="btn btn-ghost">Copy</button>
                    </div>
                </div>

                <!-- Quick actions -->
                <div class="card p-5">
                    <h2 class="h-card mb-3">{{ t('stats.quick_actions') }}</h2>
                    <div class="flex flex-wrap gap-2">
                        <RouterLink :to="{ name: 'dashboard.categories' }" class="btn btn-dark">+ {{ t('nav.categories') }}</RouterLink>
                        <RouterLink :to="{ name: 'dashboard.items' }" class="btn btn-dark">+ {{ t('nav.items') }}</RouterLink>
                        <RouterLink :to="{ name: 'dashboard.profile' }" class="btn btn-ghost">{{ t('nav.profile') }}</RouterLink>
                    </div>
                </div>
            </div>

            <!-- Right column: dark QR card -->
            <div v-if="qr" class="qr-card flex flex-col items-center justify-center">
                <h2 class="text-lg font-semibold" style="font-family:var(--font-display)">Your QR code</h2>
                <p class="text-sm mt-1" style="color:rgba(255,255,255,.55)">Print it for tables &amp; takeaway</p>
                <div class="bg-white p-3 rounded-xl mt-5">
                    <div v-html="qr.svg" class="qrbox h-40 w-40"></div>
                </div>
                <div class="flex gap-2 mt-5">
                    <a href="/api/dashboard/qr/download" target="_blank" class="btn btn-ghost">Download PNG</a>
                    <RouterLink :to="{ name: 'dashboard.qr' }" class="btn btn-dark">Open</RouterLink>
                </div>
            </div>
        </div>
    </div>
</template>
