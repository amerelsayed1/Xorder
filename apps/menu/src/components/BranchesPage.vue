<script setup>
defineProps({
    branches: Array,
    t: Function,
    accent: String,
})

defineEmits(['goHome'])
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
                        <p v-if="branch.hours">⏰ {{ branch.hours }}</p>
                        <p v-if="branch.phone">📞 {{ branch.phone }}</p>
                    </div>
                    <div class="flex gap-2">
                        <a v-if="branch.map_url" :href="branch.map_url" target="_blank" rel="noopener" class="flex-1 px-4 py-2 rounded-lg text-sm font-semibold text-center transition" :style="{ background: accent + '22', color: accent }">Map</a>
                        <a v-if="branch.phone" :href="`tel:${branch.phone}`" class="flex-1 px-4 py-2 rounded-lg text-sm font-semibold text-center transition" :style="{ background: accent + '22', color: accent }">Call</a>
                    </div>
                </div>
            </div>
        </div>
    </div>
</template>
