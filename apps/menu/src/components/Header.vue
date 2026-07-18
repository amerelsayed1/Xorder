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
                    <span class="cart-glyph" aria-hidden="true">
                        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
                            <path d="M6 2 3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4Z" />
                            <path d="M3 6h18" />
                            <path d="M16 10a4 4 0 0 1-8 0" />
                        </svg>
                    </span>
                    <b>{{ t('cart') }}</b>
                    <i>{{ cartCount }}</i>
                </button>

                <div v-if="bilingual" class="language-switch" :aria-label="isAr ? 'اختيار اللغة' : 'Choose language'">
                    <button :class="{ active: locale === 'ar' }" @click="$emit('changeLocale', 'ar')">ع</button>
                    <button :class="{ active: locale === 'en' }" @click="$emit('changeLocale', 'en')">EN</button>
                </div>

                <a v-if="waDigits" class="contact-button" :href="`https://wa.me/${waDigits}`" target="_blank" rel="noreferrer">
                    <span class="whatsapp-dot" aria-hidden="true">
                        <svg viewBox="0 0 24 24" fill="currentColor">
                            <path d="M17.472 14.382c-.297-.149-1.758-.867-2.03-.967-.273-.099-.471-.148-.67.15-.197.297-.767.966-.94 1.164-.173.199-.347.223-.644.075-.297-.15-1.255-.463-2.39-1.475-.883-.788-1.48-1.761-1.653-2.059-.173-.297-.018-.458.13-.606.134-.133.298-.347.446-.52.149-.174.198-.298.298-.497.099-.198.05-.371-.025-.52-.075-.149-.669-1.612-.916-2.207-.242-.579-.487-.5-.669-.51-.173-.008-.371-.01-.57-.01-.198 0-.52.074-.792.372-.272.297-1.04 1.016-1.04 2.479 0 1.462 1.065 2.875 1.213 3.074.149.198 2.096 3.2 5.077 4.487.71.306 1.263.489 1.694.626.712.226 1.36.194 1.872.118.571-.085 1.758-.719 2.006-1.413.248-.694.248-1.289.173-1.413-.074-.124-.272-.198-.57-.347m-5.421 7.403h-.004a9.87 9.87 0 0 1-5.031-1.378l-.361-.214-3.741.982.998-3.648-.235-.374a9.86 9.86 0 0 1-1.51-5.26c.002-5.45 4.436-9.884 9.888-9.884 2.64 0 5.122 1.03 6.988 2.898a9.825 9.825 0 0 1 2.893 6.994c-.003 5.45-4.437 9.885-9.885 9.885M20.52 3.449C18.24 1.245 15.24 0 12.045 0 5.463 0 .104 5.359.101 11.892c0 2.096.549 4.14 1.595 5.945L0 24l6.335-1.652a12.062 12.062 0 0 0 5.71 1.454h.006c6.585 0 11.946-5.36 11.949-11.896 0-3.176-1.24-6.165-3.495-8.411" />
                        </svg>
                    </span>
                    <em>{{ t('contact_wa') }}</em>
                </a>
            </div>
        </div>
    </header>
</template>
