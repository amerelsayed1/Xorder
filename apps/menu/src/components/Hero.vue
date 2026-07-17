<script setup>
import { ref, computed, watch, onMounted, onUnmounted } from 'vue'
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

const infoOpen = ref(false)
const copied = ref(false)

watch(infoOpen, (open) => {
    document.body.style.overflow = open ? 'hidden' : ''
})

function closeInfoOnEscape(event) {
    if (event.key === 'Escape') infoOpen.value = false
}

onMounted(() => window.addEventListener('keydown', closeInfoOnEscape))
onUnmounted(() => {
    window.removeEventListener('keydown', closeInfoOnEscape)
    document.body.style.overflow = ''
})

// One of the two hero actions: native share sheet when available (mobile),
// clipboard copy elsewhere.
async function share() {
    const payload = { title: name.value, url: window.location.href }
    if (navigator.share) {
        try { await navigator.share(payload) } catch { /* user dismissed */ }
        return
    }
    try {
        await navigator.clipboard.writeText(payload.url)
        copied.value = true
        setTimeout(() => (copied.value = false), 1800)
    } catch { /* clipboard unavailable */ }
}
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

        <div class="hero-buttons">
            <button @click="infoOpen = true">ⓘ {{ t('info') }}</button>
            <button @click="share">↗ {{ copied ? t('link_copied') : t('share') }}</button>
        </div>
    </section>

    <Teleport to="body">
        <div v-if="infoOpen" class="modal-backdrop" @click.self="infoOpen = false">
            <div class="simple-dialog" role="dialog" aria-modal="true">
                <button class="modal-close" :aria-label="t('close')" @click="infoOpen = false">×</button>
                <h2>{{ name }}</h2>
                <p v-if="localize(restaurant, 'description')" style="color:var(--muted);font-size:13px;line-height:1.7;margin:0">{{ localize(restaurant, 'description') }}</p>
                <div class="info-rows">
                    <div v-if="restaurant.address" class="info-row"><span>⌖</span>{{ restaurant.address }}</div>
                    <div v-if="restaurant.opening_hours" class="info-row"><span>◷</span>{{ restaurant.opening_hours }}</div>
                    <div v-if="restaurant.phone" class="info-row"><span>✆</span><a :href="`tel:${restaurant.phone}`" dir="ltr" style="text-decoration:none;color:inherit">{{ restaurant.phone }}</a></div>
                </div>
                <button class="dialog-button" @click="infoOpen = false">{{ t('close') }}</button>
            </div>
        </div>
    </Teleport>
</template>
