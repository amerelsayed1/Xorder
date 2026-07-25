<script setup>
import { computed } from 'vue'
import { useRestaurantIdentity } from '../composables/useRestaurantIdentity'

const props = defineProps({
    restaurant: Object,
    isAr: Boolean,
    t: Function,
    localize: Function,
})

const { primaryName: name, alternateName: altName, initial } = useRestaurantIdentity(props)
const tagline = computed(() => {
    const desc = props.localize(props.restaurant, 'description')
    const alt = altName.value && altName.value !== name.value ? altName.value : ''
    return [alt, desc].filter(Boolean).join(' · ')
})
</script>

<template>
    <section class="restaurant-hero" :aria-label="t('info')">
        <img v-if="restaurant.cover_image_url" class="hero-image" :src="restaurant.cover_image_url" :alt="name" fetchpriority="high" decoding="async" />
        <div class="hero-overlay"></div>

        <div class="restaurant-profile">
            <img v-if="restaurant.logo_url" :src="restaurant.logo_url" :alt="name" decoding="async" />
            <div v-else class="profile-fallback">{{ initial }}</div>
            <div class="restaurant-copy">
                <div class="restaurant-title-row">
                    <h1>{{ name }}</h1>
                </div>
                <p v-if="tagline">{{ tagline }}</p>
                <div class="restaurant-meta">
                    <span v-if="restaurant.address">⌖ {{ restaurant.address }}</span>
                    <span v-if="restaurant.opening_hours">◷ {{ restaurant.opening_hours }}</span>
                    <span v-if="restaurant.phone" dir="ltr">✆ {{ restaurant.phone }}</span>
                </div>
            </div>
        </div>
    </section>
</template>
