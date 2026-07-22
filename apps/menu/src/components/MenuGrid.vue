<script setup>
import { computed, nextTick, onMounted, onUnmounted, ref, watch } from 'vue'
import { OFFERS_CATEGORY_GLYPH, menuCategoryGlyph } from '../lib/menuCategories'

const props = defineProps({
    categories: Array,
    combos: Array,
    search: String,
    // Display-only menus (plan grants no ordering channel) hide the quick-add
    // button; the card still opens the item modal for viewing.
    orderingEnabled: { type: Boolean, default: true },
    t: Function,
    money: Function,
    localize: Function,
})

const emit = defineEmits(['openModal', 'activeSection'])

const menuRoot = ref(null)
let scrollFrame = null
let lastActiveSection = null

function updateActiveSection() {
    scrollFrame = null

    const sectionElements = [...(menuRoot.value?.querySelectorAll('[data-category-id]') || [])]
    if (!sectionElements.length) return

    const toolbarBottom = document.querySelector('.menu-toolbar')?.getBoundingClientRect().bottom || 0
    const activationLine = toolbarBottom
    let currentSection = sectionElements[0].dataset.categoryId

    for (const section of sectionElements) {
        if (section.getBoundingClientRect().top > activationLine) break
        currentSection = section.dataset.categoryId
    }

    if (currentSection !== lastActiveSection) {
        lastActiveSection = currentSection
        emit('activeSection', currentSection)
    }
}

function scheduleActiveSectionUpdate() {
    if (scrollFrame !== null) return
    scrollFrame = window.requestAnimationFrame(updateActiveSection)
}

onMounted(() => {
    window.addEventListener('scroll', scheduleActiveSectionUpdate, { passive: true })
    window.addEventListener('resize', scheduleActiveSectionUpdate, { passive: true })
    scheduleActiveSectionUpdate()
})

onUnmounted(() => {
    window.removeEventListener('scroll', scheduleActiveSectionUpdate)
    window.removeEventListener('resize', scheduleActiveSectionUpdate)
    if (scrollFrame !== null) window.cancelAnimationFrame(scrollFrame)
})

function matches(item) {
    const q = (props.search || '').trim().toLowerCase()
    if (!q) return true
    const hay = [
        props.localize(item),
        props.localize(item, 'description'),
        item.name_ar, item.name_en,
    ].filter(Boolean).join(' ').toLowerCase()
    return hay.includes(q)
}

const sections = computed(() => {
    const list = []

    if ((props.combos || []).length) {
        list.push({
            id: 'offers',
            kind: 'combo',
            title: props.t('offers'),
            glyph: OFFERS_CATEGORY_GLYPH,
            image: null,
            items: props.combos.filter(matches),
        })
    }

    (props.categories || []).forEach((c, i) => {
        list.push({
            id: `cat-${c.id}`,
            kind: 'item',
            title: props.localize(c),
            glyph: menuCategoryGlyph(i),
            image: c.image_url,
            items: (c.items || []).filter(matches),
        })
    })

    return list.filter(s => s.items.length > 0)
})

watch(sections, async () => {
    await nextTick()
    scheduleActiveSectionUpdate()
})

const totalCount = computed(() => sections.value.reduce((n, s) => n + s.items.length, 0))

const countText = (n) => `${n} ${n === 1 ? props.t('item_count') : props.t('items_count')}`

const priceOf = (section, item) => {
    if (section.kind === 'combo') return `${props.t('from')} ${props.money(item.base_price)}`
    return props.money(item.discounted_price ?? item.price)
}
</script>

<template>
    <div ref="menuRoot" class="content-layout">
        <section class="menu-content">
            <section
                v-for="section in sections"
                :id="`section-${section.id}`"
                :key="section.id"
                :data-category-id="section.id"
                class="category-section"
            >
                <div class="section-heading">
                    <div>
                        <span class="section-icon">
                            <img v-if="section.image" :src="section.image" :alt="section.title" />
                            <template v-else>{{ section.glyph }}</template>
                        </span>
                        <h2>{{ section.title }}</h2>
                    </div>
                    <span>{{ countText(section.items.length) }}</span>
                </div>

                <div class="product-grid">
                    <article
                        v-for="item in section.items"
                        :key="item.id"
                        class="product-card"
                        :class="{ unavailable: item.is_available === false }"
                        role="button"
                        :tabindex="item.is_available === false ? -1 : 0"
                        @click="item.is_available !== false && $emit('openModal', section.kind, item)"
                        @keydown.enter="item.is_available !== false && $emit('openModal', section.kind, item)"
                    >
                        <div class="product-image-wrap">
                            <img v-if="item.image_url" v-img-fade :src="item.image_url" :alt="localize(item)" loading="lazy" decoding="async" />
                            <div v-else class="image-placeholder">{{ section.glyph }}</div>
                            <span v-if="item.is_featured && item.is_available !== false" class="popular-badge">{{ t('popular') }}</span>
                            <span v-if="item.is_available === false" class="unavailable-badge">{{ t('item_unavailable') }}</span>
                        </div>
                        <div class="product-body">
                            <div class="product-title-row">
                                <h3>{{ localize(item) }}</h3>
                                <strong>
                                    <span v-if="section.kind === 'item' && item.discounted_price" class="old-price">{{ money(item.price) }}</span>
                                    {{ priceOf(section, item) }}
                                </strong>
                            </div>
                            <p>{{ localize(item, 'description') }}</p>
                            <button
                                v-if="item.is_available !== false && orderingEnabled"
                                class="add-button"
                                :aria-label="`${t('add')} ${localize(item)}`"
                                @click.stop="$emit('openModal', section.kind, item)"
                            >
                                <span>+</span> {{ t('add') }}
                            </button>
                        </div>
                    </article>
                </div>
            </section>

            <div v-if="totalCount === 0" class="no-results">
                <span>⌕</span>
                <h3>{{ t('no_results_title') }}</h3>
                <p>{{ t('no_results_hint') }}</p>
            </div>
        </section>
    </div>
</template>
