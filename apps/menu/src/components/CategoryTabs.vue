<script setup>
import { ref, watch } from 'vue'
import { OFFERS_CATEGORY_GLYPH, menuCategoryGlyph } from '../lib/menuCategories'

const props = defineProps({
    navCats: Array,
    activeCat: String,
    search: String,
    t: Function,
    localize: Function,
})

defineEmits(['selectCategory', 'update:search'])

const scrollContainer = ref(null)

const label = (cat) => {
    if (cat.isOffers) return props.t('offers')
    return props.localize(cat.category)
}

const glyph = (cat) => {
    if (cat.isOffers) return OFFERS_CATEGORY_GLYPH
    const categoryIndex = props.navCats
        .filter(entry => entry.category)
        .findIndex(entry => entry.id === cat.id)
    return menuCategoryGlyph(Math.max(0, categoryIndex))
}

watch(
    () => props.activeCat,
    () => {
        setTimeout(() => {
            const activeBtn = scrollContainer.value?.querySelector(`[data-chip="${props.activeCat}"]`)
            activeBtn?.scrollIntoView({ inline: 'center', block: 'nearest', behavior: 'smooth' })
        }, 0)
    },
    { immediate: true }
)
</script>

<template>
    <section class="menu-toolbar" :aria-label="t('search_menu')">
        <div ref="scrollContainer" class="category-list">
            <button
                v-for="cat in navCats"
                :key="cat.id"
                :data-chip="cat.id"
                class="category"
                :class="{ active: activeCat === cat.id }"
                @click="$emit('selectCategory', cat.id)"
            >
                <span>{{ glyph(cat) }}</span>{{ label(cat) }}
            </button>
        </div>
        <label class="search-box">
            <span>⌕</span>
            <input
                :placeholder="t('search_menu')"
                :aria-label="t('search_menu')"
                :value="search"
                @input="$emit('update:search', $event.target.value)"
            />
        </label>
    </section>
</template>
