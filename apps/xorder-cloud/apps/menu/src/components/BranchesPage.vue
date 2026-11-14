<script setup>
import { safeUrl } from '../lib/safeUrl'

defineProps({
    branches: Array,
    t: Function,
    accent: String,
})

defineEmits(['goHome'])

// Saturday-first to match the Arabic week, mirroring the dashboard editor and
// the restaurant info modal.
const DAY_KEYS = ['sat', 'sun', 'mon', 'tue', 'wed', 'thu', 'fri']

const hasStructured = (bh) =>
    bh && DAY_KEYS.some((k) => {
        const d = bh[k]
        return d && (d.closed || d.always || (d.open && d.close))
    })

// Every day flagged always-open → show a single "Open 24 hours" line.
const is24_7 = (bh) => bh && DAY_KEYS.every((k) => bh[k]?.always)

// Compact per-day rows for the branch card.
const dayRows = (bh) => DAY_KEYS.map((k) => ({ key: k, data: bh?.[k] || {} }))
</script>

<template>
    <div class="max-w-6xl mx-auto px-4 py-6">
        <button class="mb-6 px-4 py-2 rounded-lg text-sm font-semibold" :style="{ color: accent }" @click="$emit('goHome')">← {{ t('home') }}</button>
        <h2 class="text-2xl font-bold mb-6">{{ t('branches') }}</h2>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div v-for="branch in branches" :key="branch.id" class="rounded-2xl overflow-hidden border border-stone-200/70 hover:shadow-lg transition">
                <div class="p-6">
                    <h3 class="text-lg font-bold mb-2">{{ branch.name_en || branch.name_ar }}</h3>
                    <div class="space-y-2 text-sm text-stone-600 mb-4">
                        <p v-if="branch.address">📍 {{ branch.address }}</p>
                        <p v-if="branch.phone">📞 {{ branch.phone }}</p>

                        <div v-if="is24_7(branch.business_hours)" class="flex items-start gap-1">
                            <span>⏰</span><span>{{ t('open_24h') }}</span>
                        </div>
                        <div v-else-if="hasStructured(branch.business_hours)" class="flex items-start gap-1">
                            <span>⏰</span>
                            <ul class="flex-1 space-y-0.5">
                                <li v-for="row in dayRows(branch.business_hours)" :key="row.key" class="flex justify-between gap-3">
                                    <span>{{ t('d_' + row.key) }}</span>
                                    <span v-if="row.data.closed">{{ t('closed') }}</span>
                                    <span v-else-if="row.data.always">{{ t('open_24h') }}</span>
                                    <span v-else-if="row.data.open && row.data.close" dir="ltr">{{ row.data.open }} – {{ row.data.close }}</span>
                                    <span v-else>—</span>
                                </li>
                            </ul>
                        </div>
                        <p v-else-if="branch.opening_hours">⏰ {{ branch.opening_hours }}</p>
                    </div>
                    <div class="flex gap-2">
                        <a v-if="safeUrl(branch.map_url)" :href="safeUrl(branch.map_url)" target="_blank" rel="noopener" class="flex-1 px-4 py-2 rounded-lg text-sm font-semibold text-center transition" :style="{ background: accent + '22', color: accent }">{{ t('directions') }}</a>
                        <a v-if="branch.phone" :href="`tel:${branch.phone}`" class="flex-1 px-4 py-2 rounded-lg text-sm font-semibold text-center transition" :style="{ background: accent + '22', color: accent }">{{ t('call') }}</a>
                    </div>
                </div>
            </div>
        </div>
    </div>
</template>
