<script setup>
import { ref, watch, onMounted, nextTick } from 'vue'

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

function scrollActiveIntoView(behavior) {
    const el = scrollContainer.value
    if (!el || !props.activeCat) return
    const activeBtn = el.querySelector(`[data-chip="${props.activeCat}"]`)
    activeBtn?.scrollIntoView({ inline: 'center', block: 'nearest', behavior })
}

// First paint: RTL horizontal scrollers don't agree on an initial scroll offset
// (Chromium starts at scroll-start, iOS Safari at the far end), so the active
// tab — always the first category — can begin off-screen. Position it once the
// container ref and chip widths are actually measured (onMounted + double rAF),
// instantly, rather than racing a bare setTimeout(0) that can fire before mount.
onMounted(() => {
    requestAnimationFrame(() => requestAnimationFrame(() => scrollActiveIntoView('auto')))
})

// Later category changes (scroll-spy or a tap) glide the strip to the new tab.
watch(() => props.activeCat, () => nextTick(() => scrollActiveIntoView('smooth')))
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
                {{ label(cat) }}
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
