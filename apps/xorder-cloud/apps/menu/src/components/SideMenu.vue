<script setup>
import { useRestaurantIdentity } from '../composables/useRestaurantIdentity'

const props = defineProps({
    isOpen: Boolean,
    hasBranches: Boolean,
    waDigits: String,
    restaurant: Object,
    isAr: Boolean,
    t: Function,
})

defineEmits(['close', 'goHome', 'goBranches'])

const { primaryName: name, initial } = useRestaurantIdentity(props)
</script>

<template>
    <Teleport to="body">
        <div v-if="isOpen" class="side-backdrop" @click.self="$emit('close')">
            <nav class="side-panel">
                <div class="side-brand">
                    <img v-if="restaurant?.logo_url" :src="restaurant.logo_url" alt="" />
                    <div v-else class="brand-fallback">{{ initial }}</div>
                    <strong>{{ name }}</strong>
                </div>
                <button class="side-link" @click="$emit('goHome')"><span>✦</span>{{ t('home') }}</button>
                <button v-if="hasBranches" class="side-link" @click="$emit('goBranches')"><span>⌖</span>{{ t('branches') }}</button>
                <a
                    v-if="waDigits"
                    :href="`https://wa.me/${waDigits}`"
                    target="_blank"
                    rel="noopener"
                    class="side-link green"
                >
                    <span>◉</span>{{ t('contact') }}
                </a>
            </nav>
        </div>
    </Teleport>
</template>
