<script setup>
import { useRestaurantIdentity } from '../composables/useRestaurantIdentity'

const props = defineProps({
    restaurant: Object,
    cartCount: Number,
    bilingual: Boolean,
    isAr: Boolean,
    waDigits: String,
    orderingEnabled: Boolean,
    locale: String,
    t: Function,
})

defineEmits(['openCart', 'changeLocale', 'openMenu'])

const { primaryName: name, alternateName: altName, initial } = useRestaurantIdentity(props)
</script>

<template>
    <header class="topbar">
        <div class="topbar-inner">
            <div class="brand">
                <button class="menu-button" :aria-label="t('home')" @click="$emit('openMenu')">☰</button>
                <img v-if="restaurant.logo_url" :src="restaurant.logo_url" :alt="name" />
                <div v-else class="brand-fallback">{{ initial }}</div>
                <div class="brand-copy">
                    <strong>{{ name }}</strong>
                    <span v-if="altName && altName !== name">{{ altName }}</span>
                </div>
            </div>

            <div class="top-actions">
                <button v-if="orderingEnabled" class="header-cart-button" :aria-label="t('cart')" @click="$emit('openCart')">
                    <span class="cart-glyph">▱</span>
                    <b>{{ t('cart') }}</b>
                    <i>{{ cartCount }}</i>
                </button>

                <div v-if="bilingual" class="language-switch" :aria-label="isAr ? 'اختيار اللغة' : 'Choose language'">
                    <button :class="{ active: locale === 'ar' }" @click="$emit('changeLocale', 'ar')">ع</button>
                    <button :class="{ active: locale === 'en' }" @click="$emit('changeLocale', 'en')">EN</button>
                </div>

                <a v-if="waDigits" class="contact-button" :href="`https://wa.me/${waDigits}`" target="_blank" rel="noreferrer">
                    <span class="whatsapp-dot">◉</span>
                    <em>{{ t('contact_wa') }}</em>
                </a>
            </div>
        </div>
    </header>
</template>
