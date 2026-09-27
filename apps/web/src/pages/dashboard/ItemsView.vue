<script setup>
import { ref, onMounted, computed } from 'vue'
import { useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import { withMinDuration } from '../../lib/minLoading.js'
import { useAuth } from '@xorder/api-client/auth.js'
import { useCaps } from '../../lib/useCaps.js'
import { currencyLabel } from '../../lib/currency.js'
import { pickLocalized } from '@xorder/ui/localize.js'
import Modal from '@xorder/ui/Modal.vue'
import ListSkeleton from '@xorder/ui/ListSkeleton.vue'
import Icon from '@xorder/ui/Icon.vue'
import { confirm } from '@xorder/ui/confirm.js'
import { alert } from '@xorder/ui/alert.js'

const { t, locale } = useI18n()
const router = useRouter()
const auth = useAuth()
// Per-action gates so the UI offers only what the API would accept.
const { canCreate, canUpdate, canDelete } = useCaps('menu')
const cur = computed(() => currencyLabel(auth.restaurant?.currency, locale.value, auth.restaurant?.currency_symbol))
const items = ref([])
const categories = ref([])
const loading = ref(true)

// `filterCat` is either a category id or the 'all' sentinel — the category
// rail's first entry, which drops the category narrowing and shows the whole
// menu (and, in exchange, an extra Category column).
const ALL = 'all'
const filterCat = ref('')
const showCat = computed(() => filterCat.value === ALL)

const search = ref('')      // item search (name, either language)
const catSearch = ref('')   // narrows the category rail itself
const avail = ref('all')    // 'all' | 'on' | 'off'
const view = ref('table')   // 'table' | 'grid'

// Item ids whose image_url failed to load (dead/broken link) — they fall back
// to the meal-icon placeholder instead of the browser's broken-image glyph.
const failedImg = ref(new Set())
function onImgError(id) { failedImg.value.add(id) }

// Every item of the selected category, in menu order — the API returns them
// sorted by display_order within each category. This is the list reordering
// acts on, which is why it is kept separate from the narrowed views below.
const categoryItems = computed(() => showCat.value
    ? items.value
    : items.value.filter(i => i.category_id === Number(filterCat.value)))

const availFiltered = computed(() => {
    if (avail.value === 'all') return categoryItems.value
    const want = avail.value === 'on'
    return categoryItems.value.filter(i => !!i.is_available === want)
})

const filtered = computed(() => {
    const q = search.value.trim().toLowerCase()
    if (!q) return availFiltered.value
    return availFiltered.value.filter(i =>
        (i.name_en || '').toLowerCase().includes(q) || (i.name_ar || '').toLowerCase().includes(q))
})

// Reordering takes each row's new position from its index, so it only means
// anything while the whole category is on screen. Under a search, an
// availability filter, or the "all categories" view, the hidden rows would be
// silently renumbered from a subset, so the handles come off rather than
// quietly doing the wrong thing.
const reorderable = computed(() => canUpdate.value
    && !search.value.trim()
    && avail.value === 'all'
    && !showCat.value
    && !!filterCat.value)

// Says why the handles are there and — more usefully — why they are not, since
// a filter silently removing them would read as a bug.
const reorderHint = computed(() => {
    if (!canUpdate.value || showCat.value || filtered.value.length < 2) return ''
    if (search.value.trim()) return t('item.reorder_search_hint')
    if (avail.value !== 'all') return t('item.reorder_filter_hint')
    return t('item.reorder_hint')
})

// --- Category rail ---------------------------------------------------------

const catCount = (id) => items.value.filter(i => i.category_id === id).length
const hiddenCount = computed(() => items.value.filter(i => !i.is_available).length)

// The rail's own search narrows the category list. "All items" is a view, not
// a category, so a rail search drops it rather than matching it by name.
const railCats = computed(() => {
    const q = catSearch.value.trim().toLowerCase()
    if (!q) return categories.value
    return categories.value.filter(c => pickLocalized(c, 'name', locale.value).toLowerCase().includes(q)
        || (c.name_en || '').toLowerCase().includes(q)
        || (c.name_ar || '').toLowerCase().includes(q))
})
const railEmpty = computed(() => catSearch.value.trim() && !railCats.value.length)

const catTitle = computed(() => showCat.value ? t('item.all_categories') : catName(Number(filterCat.value)))

function pickCat(key) {
    filterCat.value = key
    clearSelection()
}

async function load() {
    loading.value = true
    try {
        const [it, cats] = await withMinDuration(Promise.all([
            api.get('api/dashboard/items'),
            api.get('api/dashboard/categories'),
        ]))
        items.value = it.data.data
        // Only active categories are manageable here — items of inactive
        // categories are hidden (backend filters them too), so an inactive
        // category has nothing to show and is dropped from the rail/count.
        categories.value = cats.data.data.filter(c => c.is_active)
        // Default to a real category rather than "all", so the menu order is
        // editable the moment the page opens.
        if (filterCat.value !== ALL && !categories.value.some(c => c.id === filterCat.value))
            filterCat.value = categories.value[0]?.id ?? ''
        clearSelection()
    } catch (e) {
        console.error('Failed to load menu items', e)
    } finally {
        loading.value = false
    }
}
onMounted(load)

// --- Multi-select / bulk actions ---
// Selection is keyed by item id and persists across search/category filtering
// so a user can narrow the list, tick a few, change the filter, tick more,
// then act on the whole set at once.
const selected = ref(new Set())
function toggleSelect(id) {
    if (selected.value.has(id)) selected.value.delete(id)
    else selected.value.add(id)
}
function clearSelection() { selected.value.clear() }
// Select-all reflects only the rows currently visible under the active filter.
const allFilteredSelected = computed(() =>
    filtered.value.length > 0 && filtered.value.every(i => selected.value.has(i.id)))
const someFilteredSelected = computed(() =>
    filtered.value.some(i => selected.value.has(i.id)) && !allFilteredSelected.value)
function toggleAll() {
    if (allFilteredSelected.value) filtered.value.forEach(i => selected.value.delete(i.id))
    else filtered.value.forEach(i => selected.value.add(i.id))
}
const bulkDeleting = ref(false)
async function bulkRemove() {
    const ids = [...selected.value]
    if (!ids.length || bulkDeleting.value || bulkBusy.value) return
    const ok = await confirm({
        title: t('common.delete'),
        message: t('item.confirm_delete_selected', { n: ids.length }),
        confirmText: t('common.delete'),
        cancelText: t('common.cancel'),
        danger: true,
    })
    if (!ok) return
    bulkDeleting.value = true
    try {
        await ensureCsrf()
        await api.delete('api/dashboard/items/bulk', { data: { ids } })
        await load()
    } catch (err) {
        alert(t('common.delete_failed'))
    } finally {
        bulkDeleting.value = false
    }
}

// Show/hide the whole selection. There is no bulk availability endpoint — the
// API exposes availability one item at a time — so this fans out and reports
// if any single call failed, then reloads so the page shows what actually
// landed rather than what was asked for.
const bulkBusy = ref('')
async function bulkAvailability(value) {
    const ids = [...selected.value]
    if (!ids.length || bulkBusy.value || bulkDeleting.value) return
    bulkBusy.value = value ? 'show' : 'hide'
    try {
        await ensureCsrf()
        const results = await Promise.allSettled(ids.map(id =>
            api.patch(`api/dashboard/items/${id}/availability`, { is_available: value })))
        if (results.some(r => r.status === 'rejected')) alert(t('item.bulk_availability_failed'))
        await load()
    } finally {
        bulkBusy.value = ''
    }
}

function catName(id) {
    const c = categories.value.find(c => c.id === id)
    return c ? pickLocalized(c, 'name', locale.value) : ''
}
const itemName = (it) => pickLocalized(it, 'name', locale.value)
const itemAltName = (it) => locale.value === 'ar' ? (it.name_en || '') : (it.name_ar || '')
const itemDescription = (it) => pickLocalized(it, 'description', locale.value)
const itemInitial = (it) => (itemName(it) || '').charAt(0)
const hasImage = (it) => !!it.image_url && !failedImg.value.has(it.id)

// --- Table column structure ------------------------------------------------
// The column list is computed rather than written in CSS because two of the
// columns come and go (Select with the delete capability, Category only in the
// "all" view). It is published as `--items-cols-wide`; the stylesheet decides
// whether that or the narrow list is in force, so the media query still wins.
const colsWide = computed(() => [
    canDelete.value ? '40px' : null,
    '84px',                 /* No. + reorder handle/arrows */
    'minmax(200px, 2.4fr)', /* Product (image + name) */
    showCat.value ? 'minmax(110px, 1fr)' : null,
    'minmax(96px, 0.8fr)',  /* Price */
    '52px',                 /* Featured */
    '110px',                /* Available */
    '84px',                 /* Actions */
].filter(Boolean).join(' '))

// The width below which the table scrolls sideways rather than squeezing the
// columns past legibility. Tracks the same two optional columns.
const tableMin = computed(() =>
    `${672 + (showCat.value ? 118 : 0) + (canDelete.value ? 48 : 0)}px`)

// Narrow screens drop Category and Featured entirely (see the media query).
const colsNarrow = computed(() => [
    canDelete.value ? '36px' : null,
    '40px',
    'minmax(0, 2fr)',
    'minmax(96px, 1fr)',
    '104px',
    '92px',
].filter(Boolean).join(' '))

// --- Menu order (display_order within the selected category) ---------------

// Write a new order for the current category back into the master list and
// persist it. Optimistic: the rows have already moved on screen, so a failure
// reloads to snap back to the server's truth rather than leaving the two
// disagreeing. Only this category's ids are sent — the endpoint takes an
// arbitrary set, and touching the others would be a lie about what changed.
async function applyOrder(ordered) {
    const moved = new Set(ordered.map(i => i.id))
    ordered.forEach((it, idx) => { it.display_order = idx })
    items.value = [...items.value.filter(i => !moved.has(i.id)), ...ordered]
    try {
        await ensureCsrf()
        await api.patch('api/dashboard/items/reorder', {
            order: ordered.map((it, idx) => ({ id: it.id, display_order: idx })),
        })
    } catch (err) {
        alert(err.response?.data?.message || t('item.reorder_failed'))
        await load()
    }
}

// Arrow buttons: the keyboard- and touch-reachable path to the same result,
// since a drag is neither.
async function move(index, dir) {
    const target = index + dir
    const arr = categoryItems.value.slice()
    if (target < 0 || target >= arr.length) return
    ;[arr[index], arr[target]] = [arr[target], arr[index]]
    await applyOrder(arr)
}

const dragIndex = ref(null)   // row being dragged
const overIndex = ref(null)   // row currently hovered as drop target
const dragReady = ref(false)  // only allow a drag that started on the handle
function onDragStart(i, ev) {
    if (!reorderable.value) return
    dragIndex.value = i
    ev.dataTransfer.effectAllowed = 'move'
    // Firefox will not start a drag unless some data is set.
    ev.dataTransfer.setData('text/plain', String(i))
}
function onDragOver(i) {
    if (dragIndex.value === null) return
    overIndex.value = i
}
function onDrop(i) {
    const from = dragIndex.value
    resetDrag()
    if (from === null || from === i) return
    const arr = categoryItems.value.slice()
    const [row] = arr.splice(from, 1)
    arr.splice(i, 0, row)
    applyOrder(arr)
}
function resetDrag() {
    dragIndex.value = null
    overIndex.value = null
    dragReady.value = false
}

function goCreate() {
    if (!categories.value.length) return
    router.push({ name: 'dashboard.items.create' })
}
function goEdit(it) { router.push({ name: 'dashboard.items.edit', params: { id: it.id } }) }
// The rail's "+" leads to the categories page, which is where a category is
// actually created — there is no create-category route of its own.
function goCategories() { router.push({ name: 'dashboard.categories' }) }
async function toggleAvail(it) {
    await ensureCsrf()
    await api.patch(`api/dashboard/items/${it.id}/availability`, { is_available: !it.is_available })
    it.is_available = !it.is_available
}
async function toggleFeatured(it) {
    await ensureCsrf()
    await api.put(`api/dashboard/items/${it.id}`, { is_featured: !it.is_featured })
    it.is_featured = !it.is_featured
}
async function remove(it) {
    const ok = await confirm({
        title: t('common.delete'),
        message: t('common.confirm_delete'),
        confirmText: t('common.delete'),
        cancelText: t('common.cancel'),
        danger: true,
    })
    if (!ok) return
    try {
        await ensureCsrf()
        await api.delete(`api/dashboard/items/${it.id}`)
        await load()
    } catch (err) {
        alert(t('common.delete_failed'))
    }
}

// --- CSV / Excel import ---
const showImport = ref(false)
const importing = ref(false)
const importFile = ref(null)
const importResult = ref(null)
const importError = ref('')

function openImport() {
    importFile.value = null
    importResult.value = null
    importError.value = ''
    showImport.value = true
}
function onImportFile(e) {
    importFile.value = e.target.files?.[0] || null
    importResult.value = null
    importError.value = ''
}

// A ready-to-fill import template. A bilingual menu gets both-language columns
// (the same layout the export emits and the importer accepts) so AR + EN can
// both be captured; a single-language menu gets a simpler one-language sheet in
// its default language.
function downloadTemplate() {
    // Bilingual unless explicitly turned off — matches how the menu app decides
    // (bilingual !== false), so legacy rows with a null flag still get both columns.
    const bilingual = auth.restaurant?.bilingual !== false
    const ar = auth.restaurant?.default_language !== 'en'
    let headers, sample
    if (bilingual) {
        headers = ['category_en', 'category_ar', 'name_en', 'name_ar', 'description_en', 'description_ar', 'price', 'discounted_price', 'available', 'featured', 'image_url']
        sample = ['Drinks', 'مشروبات', 'Espresso', 'قهوة سادة', 'Freshly brewed', 'قهوة عربية طازجة', '30', '', 'yes', 'no', 'https://example.com/coffee.jpg']
    } else {
        headers = ['category', 'name', 'description', 'price', 'discounted_price', 'available', 'featured', 'image_url']
        sample = ar
            ? ['مشروبات', 'قهوة سادة', 'قهوة عربية طازجة', '30', '', 'نعم', 'لا', 'https://example.com/coffee.jpg']
            : ['Drinks', 'Espresso', 'Freshly brewed', '30', '', 'yes', 'no', 'https://example.com/coffee.jpg']
    }
    const esc = v => /[",\n]/.test(v) ? `"${v.replace(/"/g, '""')}"` : v
    const csv = '﻿' + [headers.map(esc).join(','), sample.map(esc).join(',')].join('\n')
    const url = URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8;' }))
    const a = document.createElement('a')
    a.href = url; a.download = 'menu-template.csv'; a.click()
    URL.revokeObjectURL(url)
}

// --- CSV / Excel export ---
// A read (works even in read-only mode). Streams the menu in the same column
// layout the importer accepts, so export → edit → import round-trips cleanly.
const exporting = ref('')
const showExportMenu = ref(false)
async function doExport(format) {
    showExportMenu.value = false
    if (exporting.value) return
    exporting.value = format
    try {
        const res = await api.get('api/dashboard/items/export', { params: { format }, responseType: 'blob' })
        const blobUrl = URL.createObjectURL(res.data)
        const a = document.createElement('a')
        a.href = blobUrl
        a.download = `menu.${format === 'xlsx' ? 'xlsx' : 'csv'}`
        a.click()
        URL.revokeObjectURL(blobUrl)
    } catch (err) {
        alert(t('import.export_failed'))
    } finally {
        exporting.value = ''
    }
}

async function submitImport() {
    if (!importFile.value || importing.value) return
    importing.value = true
    importError.value = ''
    importResult.value = null
    try {
        await ensureCsrf()
        const fd = new FormData()
        fd.append('file', importFile.value)
        const { data } = await api.post('api/dashboard/items/import', fd, { headers: { 'Content-Type': 'multipart/form-data' } })
        importResult.value = data.data
        await load()
    } catch (err) {
        importError.value = err.response?.data?.message || t('import.failed')
    } finally {
        importing.value = false
    }
}
</script>

<template>
    <div class="items-page">
        <!-- Page heading + the actions that apply to the menu as a whole. -->
        <div class="flex flex-wrap items-end justify-between gap-4">
            <div>
                <h1 class="page-title">{{ t('nav.items') }}</h1>
                <p class="page-sub">
                    {{ t('item.subtitle', { items: items.length, categories: categories.length }) }}
                    <template v-if="hiddenCount"> · {{ t('item.hidden_count', { n: hiddenCount }) }}</template>
                </p>
            </div>
            <div class="flex items-center gap-2">
                <!-- Export is a read: available even in read-only mode. -->
                <div class="relative">
                    <button @click="showExportMenu = !showExportMenu" :disabled="!!exporting || !items.length" class="btn btn-ghost">
                        <Icon name="download" :size="16" />{{ exporting ? t('import.exporting') : t('import.export') }}
                    </button>
                    <template v-if="showExportMenu">
                        <div class="fixed inset-0 z-10" @click="showExportMenu = false"></div>
                        <div class="absolute z-20 mt-1 min-w-[9rem] rounded-xl py-1 inset-inline-end-0" style="background:var(--card, #fff);border:1px solid var(--line);box-shadow:0 8px 24px rgba(0,0,0,.12)">
                            <button @click="doExport('csv')" class="flex w-full items-center gap-2 px-3 py-2 text-sm text-start hover:opacity-80"><Icon name="download" :size="15" />{{ t('import.export_csv') }}</button>
                            <button @click="doExport('xlsx')" class="flex w-full items-center gap-2 px-3 py-2 text-sm text-start hover:opacity-80"><Icon name="download" :size="15" />{{ t('import.export_xlsx') }}</button>
                        </div>
                    </template>
                </div>
                <button v-if="canCreate" @click="openImport" class="btn btn-ghost"><Icon name="upload" :size="16" />{{ t('import.button') }}</button>
                <button v-if="canCreate" @click="goCreate" :disabled="!categories.length" class="btn btn-accent"><Icon name="plus" :size="16" />{{ t('common.create') }}</button>
            </div>
        </div>
        <p v-if="!categories.length && !loading" class="text-sm" style="color:var(--amber)">{{ t('item.create_category_first') }}</p>

        <!-- Category rail + the item list it selects. Below 900px the rail
             becomes a horizontal strip above the list. -->
        <div class="items-layout">
            <aside class="cat-rail card">
                <div class="cat-rail-head">
                    <span class="cat-rail-title">{{ t('nav.categories') }}</span>
                    <button v-if="canCreate" class="cat-add" :title="t('item.new_category')"
                        :aria-label="t('item.new_category')" @click="goCategories"><Icon name="plus" :size="14" /></button>
                </div>
                <div class="cat-rail-search">
                    <span class="cat-rail-search-ico"><Icon name="search" :size="14" /></span>
                    <input v-model="catSearch" :placeholder="t('item.search_categories')" class="cat-rail-input" />
                </div>
                <p v-if="railEmpty" class="cat-rail-empty">{{ t('item.no_categories_match') }}</p>
                <div v-else class="cat-rail-list">
                    <button v-if="!catSearch.trim()" class="cat-row" :class="{ active: showCat }" @click="pickCat(ALL)">
                        <span class="cat-row-line"></span>
                        <span class="cat-row-name">{{ t('item.all_categories') }}</span>
                        <span class="cat-row-count">{{ items.length }}</span>
                    </button>
                    <button v-for="c in railCats" :key="c.id" class="cat-row" :class="{ active: filterCat === c.id }" @click="pickCat(c.id)">
                        <span class="cat-row-line"></span>
                        <span class="cat-row-name">{{ catName(c.id) }}</span>
                        <span class="cat-row-count">{{ catCount(c.id) }}</span>
                    </button>
                </div>
            </aside>

            <div class="items-main">
                <div class="flex items-baseline gap-3">
                    <h2 class="cat-title">{{ catTitle }}</h2>
                    <span class="text-sm" style="color:var(--muted)">{{ t('item.count_label', { n: filtered.length }) }}</span>
                </div>

                <!-- Toolbar: item search, availability filter, view switch. -->
                <div class="items-toolbar">
                    <div class="relative items-search">
                        <span class="absolute top-1/2 -translate-y-1/2 pointer-events-none" style="inset-inline-start:12px;color:var(--muted)"><Icon name="search" :size="17" /></span>
                        <input v-model="search" :placeholder="t('item.search_placeholder')" class="input" style="padding-inline-start:38px;margin-top:0" />
                    </div>
                    <div class="seg">
                        <button class="seg-btn" :class="{ on: avail === 'all' }" @click="avail = 'all'">{{ t('item.avail_all') }}</button>
                        <button class="seg-btn" :class="{ on: avail === 'on' }" @click="avail = 'on'">{{ t('item.avail_on') }}</button>
                        <button class="seg-btn" :class="{ on: avail === 'off' }" @click="avail = 'off'">{{ t('item.avail_off') }}</button>
                    </div>
                    <div class="toolbar-gap"></div>
                    <div class="seg">
                        <button class="seg-btn seg-ico" :class="{ on: view === 'table' }" :title="t('item.view_table')"
                            :aria-label="t('item.view_table')" @click="view = 'table'"><Icon name="menu" :size="16" /></button>
                        <button class="seg-btn seg-ico" :class="{ on: view === 'grid' }" :title="t('item.view_grid')"
                            :aria-label="t('item.view_grid')" @click="view = 'grid'"><Icon name="grid" :size="16" /></button>
                    </div>
                </div>

                <!-- Bulk action bar — appears once one or more rows are ticked. -->
                <div v-if="selected.size && (canUpdate || canDelete)" class="bulk-bar">
                    <span class="bulk-count">{{ t('item.selected_count', { n: selected.size }) }}</span>
                    <button v-if="canUpdate" class="bulk-btn" :disabled="!!bulkBusy || bulkDeleting" @click="bulkAvailability(true)">{{ t('item.show_selected') }}</button>
                    <button v-if="canUpdate" class="bulk-btn" :disabled="!!bulkBusy || bulkDeleting" @click="bulkAvailability(false)">{{ t('item.hide_selected') }}</button>
                    <button v-if="canDelete" class="bulk-btn bulk-btn-danger" :disabled="bulkDeleting || !!bulkBusy" @click="bulkRemove">{{ t('common.delete') }}</button>
                    <button class="bulk-close" :title="t('item.clear_selection')" :aria-label="t('item.clear_selection')" @click="clearSelection"><Icon name="close" :size="16" /></button>
                </div>

                <ListSkeleton v-if="loading" class="card" />

                <!-- Table view -->
                <div v-else-if="view === 'table'" class="card overflow-hidden">
                    <div class="items-scroll">
                        <!--
                          Single shared column structure for header + every row.
                          Both use `.items-row`, whose `grid-template-columns`
                          comes from the one `--items-cols` token on
                          `.items-table`. Change a width once and the header and
                          all rows update together.
                        -->
                        <div class="items-table" :class="{ 'select-mode': canDelete }"
                            :style="{ '--items-cols-wide': colsWide, '--items-cols-narrow': colsNarrow, '--items-min': tableMin }" role="table">
                            <div class="items-row items-head" role="row">
                                <div v-if="canDelete" role="columnheader" class="col-center col-select">
                                    <input type="checkbox" class="row-check" :checked="allFilteredSelected"
                                        :indeterminate.prop="someFilteredSelected" :aria-label="t('item.select_all')"
                                        :disabled="!filtered.length" @change="toggleAll" />
                                </div>
                                <div role="columnheader" class="col-order">#</div>
                                <div role="columnheader">{{ t('item.item') }}</div>
                                <div v-if="showCat" role="columnheader" class="col-cat">{{ t('item.category') }}</div>
                                <div role="columnheader">{{ t('item.price') }}</div>
                                <div role="columnheader" class="col-feat col-center">★</div>
                                <div role="columnheader" class="col-center">{{ t('common.available') }}</div>
                                <div role="columnheader" class="col-actions">{{ t('common.actions') }}</div>
                            </div>
                            <div v-for="(it, idx) in filtered" :key="it.id" class="items-row items-body-row"
                                :class="{ 'row-selected': selected.has(it.id), 'row-dragging': dragIndex === idx, 'row-drop': overIndex === idx && dragIndex !== null && dragIndex !== idx }"
                                :draggable="reorderable && dragReady"
                                @dragstart="onDragStart(idx, $event)"
                                @dragover.prevent="onDragOver(idx)"
                                @drop.prevent="onDrop(idx)"
                                @dragend="resetDrag"
                                role="row">
                                <div v-if="canDelete" role="cell" class="col-center col-select">
                                    <input type="checkbox" class="row-check" :checked="selected.has(it.id)"
                                        :aria-label="itemName(it)" @change="toggleSelect(it.id)" />
                                </div>
                                <div role="cell" class="col-order">
                                    <button v-if="reorderable" class="drag-handle" :title="t('item.drag_to_reorder')"
                                        :aria-label="t('item.drag_to_reorder')"
                                        @mousedown="dragReady = true" @touchstart.passive="dragReady = true"
                                        @mouseup="dragReady = false"><Icon name="grip" :size="16" fill /></button>
                                    <span class="row-num">{{ idx + 1 }}</span>
                                    <div v-if="reorderable" class="order-arrows">
                                        <button @click="move(idx, -1)" :disabled="idx === 0" class="icon-btn"
                                            :aria-label="t('item.move_up')"><Icon name="chevronUp" :size="14" /></button>
                                        <button @click="move(idx, 1)" :disabled="idx === filtered.length - 1" class="icon-btn"
                                            :aria-label="t('item.move_down')"><Icon name="chevronDown" :size="14" /></button>
                                    </div>
                                </div>
                                <div role="cell">
                                    <div class="flex items-center gap-3 min-w-0 product-cell">
                                        <img v-if="hasImage(it)" :src="it.image_url" @error="onImgError(it.id)" class="row-thumb object-cover" alt="" />
                                        <div v-else class="row-thumb row-thumb-blank">{{ itemInitial(it) }}</div>
                                        <div class="min-w-0 product-info">
                                            <div class="font-medium truncate" style="color:var(--ink)">{{ itemName(it) }}</div>
                                            <div v-if="itemAltName(it)" class="text-xs truncate" style="color:var(--muted)" :dir="locale === 'ar' ? 'ltr' : 'rtl'">{{ itemAltName(it) }}</div>
                                            <div v-if="itemDescription(it)" class="text-xs truncate" style="color:var(--body)">{{ itemDescription(it) }}</div>
                                        </div>
                                    </div>
                                </div>
                                <div v-if="showCat" role="cell" class="col-cat">
                                    <span class="cat-tag">{{ catName(it.category_id) }}</span>
                                </div>
                                <div role="cell" class="whitespace-nowrap">
                                    <span class="price tabular">{{ it.discounted_price || it.price }} {{ cur }}</span>
                                    <span v-if="it.discounted_price" class="text-xs line-through ms-1" style="color:var(--muted)">{{ it.price }} {{ cur }}</span>
                                </div>
                                <div role="cell" class="col-feat col-center">
                                    <button v-if="canUpdate" class="star" :class="{ on: it.is_featured }" :title="t('common.featured')" @click="toggleFeatured(it)">★</button>
                                </div>
                                <div role="cell" class="col-center">
                                    <button v-if="canUpdate" class="avail-toggle" @click="toggleAvail(it)">
                                        <span class="switch" :class="{ on: it.is_available }"></span>
                                        <span class="avail-label" :class="{ on: it.is_available }">{{ it.is_available ? t('common.available') : t('item.hidden') }}</span>
                                    </button>
                                    <span v-else class="avail-label" :class="{ on: it.is_available }">{{ it.is_available ? t('common.available') : t('item.hidden') }}</span>
                                </div>
                                <div role="cell" class="col-actions whitespace-nowrap">
                                    <div class="inline-flex items-center gap-1">
                                        <button v-if="canUpdate" @click="goEdit(it)" class="icon-btn" :title="t('common.edit')"><Icon name="edit" :size="17" /></button>
                                        <button v-if="canDelete" @click="remove(it)" class="icon-btn icon-btn-danger" :title="t('common.delete')"><Icon name="trash" :size="17" /></button>
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>
                    <div v-if="!filtered.length" class="items-empty">{{ items.length ? t('item.no_match') : t('common.none') }}</div>
                    <div class="items-foot">
                        <span>{{ reorderHint }}</span>
                        <span>{{ t('item.count_label', { n: filtered.length }) }}</span>
                    </div>
                </div>

                <!-- Card view -->
                <template v-else>
                    <div v-if="!filtered.length" class="card items-empty">{{ items.length ? t('item.no_match') : t('common.none') }}</div>
                    <div v-else class="items-grid">
                        <div v-for="it in filtered" :key="it.id" class="item-card" :class="{ selected: selected.has(it.id) }">
                            <div class="item-card-media">
                                <img v-if="hasImage(it)" :src="it.image_url" @error="onImgError(it.id)" alt="" />
                                <span v-else class="item-card-initial">{{ itemInitial(it) }}</span>
                                <input v-if="canDelete" type="checkbox" class="row-check item-card-check"
                                    :checked="selected.has(it.id)" :aria-label="itemName(it)" @change="toggleSelect(it.id)" />
                                <button v-if="canUpdate" class="item-card-star" :class="{ on: it.is_featured }"
                                    :title="t('common.featured')" @click="toggleFeatured(it)"><Icon name="star" :size="16" :fill="it.is_featured" /></button>
                            </div>
                            <div class="item-card-body">
                                <div class="item-card-cat">{{ catName(it.category_id) }}</div>
                                <div class="item-card-name">{{ itemName(it) }}</div>
                                <div v-if="itemAltName(it)" class="item-card-alt" :dir="locale === 'ar' ? 'ltr' : 'rtl'">{{ itemAltName(it) }}</div>
                            </div>
                            <div class="item-card-foot">
                                <span class="price tabular">{{ it.discounted_price || it.price }} {{ cur }}</span>
                                <div class="flex items-center gap-1">
                                    <button v-if="canUpdate" class="switch" :class="{ on: it.is_available }"
                                        :title="it.is_available ? t('common.available') : t('item.hidden')" @click="toggleAvail(it)"></button>
                                    <button v-if="canUpdate" @click="goEdit(it)" class="icon-btn" :title="t('common.edit')"><Icon name="edit" :size="16" /></button>
                                    <button v-if="canDelete" @click="remove(it)" class="icon-btn icon-btn-danger" :title="t('common.delete')"><Icon name="trash" :size="16" /></button>
                                </div>
                            </div>
                        </div>
                    </div>
                </template>
            </div>
        </div>

        <!-- Import from CSV / Excel -->
        <Modal v-if="showImport" :title="t('import.title')" @close="showImport = false">
            <div class="space-y-4">
                <p class="text-sm" style="color:var(--body)">{{ t('import.help') }}</p>
                <div class="rounded-xl p-3 text-xs" style="background:var(--page);border:1px solid var(--line);color:var(--muted)">
                    {{ t('import.columns_help') }}
                </div>
                <button type="button" class="btn btn-ghost btn-sm" @click="downloadTemplate">
                    <Icon name="download" :size="15" />{{ t('import.template') }}
                </button>

                <label class="block">
                    <span class="label">{{ t('import.choose_file') }}</span>
                    <input type="file" accept=".csv,.xlsx,.xls,text/csv" class="input" @change="onImportFile" />
                    <span class="text-xs" style="color:var(--muted)">{{ t('import.formats') }}</span>
                </label>

                <p v-if="importError" class="text-sm" style="color:var(--red, #dc2626)">{{ importError }}</p>

                <!-- Result summary -->
                <div v-if="importResult" class="rounded-xl p-3 space-y-2" style="background:var(--page);border:1px solid var(--line)">
                    <div class="flex flex-wrap gap-x-4 gap-y-1 text-sm" style="color:var(--ink)">
                        <span>✓ {{ t('import.created', { n: importResult.items_created }) }}</span>
                        <span>↻ {{ t('import.updated', { n: importResult.items_updated }) }}</span>
                        <span v-if="importResult.categories_created">＋ {{ t('import.cats_created', { n: importResult.categories_created }) }}</span>
                        <span v-if="importResult.skipped">⊘ {{ t('import.skipped', { n: importResult.skipped }) }}</span>
                    </div>
                    <div v-if="importResult.errors?.length" class="text-xs space-y-1" style="color:var(--muted);max-height:150px;overflow:auto">
                        <div class="font-medium" style="color:var(--amber)">{{ t('import.errors') }}</div>
                        <div v-for="(er, i) in importResult.errors" :key="i">{{ t('import.row', { n: er.row }) }}: {{ er.message }}</div>
                    </div>
                </div>

                <div class="flex justify-end gap-2 pt-2">
                    <button @click="showImport = false" :disabled="importing" class="btn btn-ghost">{{ importResult ? t('common.close') : t('common.cancel') }}</button>
                    <button v-if="!importResult" @click="submitImport" :disabled="importing || !importFile" class="btn btn-accent">
                        <Icon v-if="importing" name="loading" :size="16" class="animate-spin" />
                        {{ importing ? t('import.uploading') : t('import.button') }}
                    </button>
                </div>
            </div>
        </Modal>
    </div>
</template>

<style scoped>
.items-page { display: flex; flex-direction: column; gap: 20px; }

/* ── Page shell ───────────────────────────────────────────────────
   Category rail beside the list on desktop; stacked on narrow screens,
   where the rail turns into a horizontal strip of category buttons. */
.items-layout {
    display: grid;
    grid-template-columns: minmax(0, 1fr);
    gap: 16px;
    align-items: start;
}
@media (min-width: 900px) {
    .items-layout { grid-template-columns: 220px minmax(0, 1fr); gap: 16px 20px; }
}
.items-main { min-width: 0; display: flex; flex-direction: column; gap: 16px; }
.cat-title { font-family: var(--font-display); font-weight: 700; font-size: 18px; color: var(--ink); margin: 0; }

/* ── Category rail ──────────────────────────────────────────────── */
.cat-rail {
    display: flex;
    flex-direction: column;
    overflow: hidden;
    min-width: 0;
}
@media (min-width: 900px) {
    /* Sticks under the 64px topbar so the categories stay reachable while a
       long item list scrolls past them. */
    .cat-rail { position: sticky; top: 76px; max-height: calc(100vh - 96px); }
}
.cat-rail-head {
    display: flex; align-items: center; justify-content: space-between;
    padding: 12px 12px 8px 10px;
}
.cat-rail-title { font-size: 13px; font-weight: 600; color: var(--body); }
.cat-add {
    width: 28px; height: 28px; border: 0; border-radius: 8px; cursor: pointer;
    display: grid; place-items: center;
    background: var(--accent-soft); color: var(--accent);
    transition: filter .15s;
}
.cat-add:hover { filter: brightness(.95); }
.cat-rail-search { position: relative; margin: 0 10px 8px; }
.cat-rail-search-ico {
    position: absolute; top: 50%; transform: translateY(-50%);
    inset-inline-start: 10px; color: var(--muted); pointer-events: none; display: flex;
}
.cat-rail-input {
    width: 100%; height: 34px; padding-inline: 30px 10px;
    border: 1px solid var(--line); border-radius: 8px;
    background: var(--page); color: var(--ink); font-size: 13px; font-family: inherit;
}
.cat-rail-input:focus { outline: none; border-color: var(--accent); background: var(--card); }
.cat-rail-empty { padding: 14px; font-size: 13px; color: var(--muted); text-align: center; margin: 0; }
.cat-rail-list {
    overflow: auto;
    padding: 0 8px 8px;
    display: flex;
    flex-direction: row;   /* narrow: a horizontal strip */
    gap: 4px;
}
@media (min-width: 900px) {
    .cat-rail-list { flex-direction: column; gap: 2px; }
}
.cat-row {
    flex: none;
    display: flex; align-items: center; gap: 10px;
    width: auto;
    padding: 9px 10px;
    border: 0; border-radius: 8px;
    background: transparent;
    font-family: inherit; font-size: 14px; color: var(--body);
    cursor: pointer; text-align: start;
    transition: background .15s, color .15s;
}
@media (min-width: 900px) { .cat-row { width: 100%; } }
.cat-row:hover { background: var(--page); color: var(--ink); }
.cat-row.active { background: var(--accent-soft); color: var(--ink); font-weight: 600; }
.cat-row-line { width: 3px; height: 16px; border-radius: 2px; background: transparent; flex: none; }
.cat-row.active .cat-row-line { background: var(--accent); }
.cat-row-name { flex: 1; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.cat-row-count {
    font-family: var(--font-mono); font-size: 11.5px; font-weight: 600;
    padding: 1px 7px; border-radius: 999px;
    background: var(--gray-soft); color: var(--muted);
}
.cat-row.active .cat-row-count { background: var(--accent); color: #fff; }

/* ── Toolbar ────────────────────────────────────────────────────── */
.items-toolbar { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; }
.items-search { flex: 1 1 220px; max-width: 380px; }
.toolbar-gap { flex: 1 1 0; }
.seg {
    display: flex; gap: 2px; padding: 3px;
    background: var(--gray-soft); border-radius: 10px;
}
.seg-btn {
    height: 34px; padding: 0 14px; border: 0; border-radius: 8px;
    background: transparent; color: var(--body);
    font-family: inherit; font-size: 13.5px; font-weight: 500; cursor: pointer;
    display: inline-flex; align-items: center; justify-content: center;
    transition: background .15s, color .15s, box-shadow .15s;
}
.seg-btn:hover { color: var(--ink); }
.seg-btn.on { background: var(--card); color: var(--ink); box-shadow: 0 1px 2px rgba(0, 0, 0, .12); }
.seg-ico { width: 38px; padding: 0; }

/* ── Bulk action bar ────────────────────────────────────────────── */
.bulk-bar {
    display: flex; align-items: center; gap: 8px;
    padding: 10px 10px 10px 12px;
    border-radius: 12px;
    background: var(--ink); color: #fff;
}
.bulk-count { font-weight: 600; font-size: 14px; margin-inline-end: auto; }
.bulk-btn {
    height: 34px; padding: 0 12px; border-radius: 8px; cursor: pointer;
    border: 1px solid rgba(255, 255, 255, .22);
    background: transparent; color: #fff;
    font-family: inherit; font-size: 13.5px;
    transition: background .15s;
}
.bulk-btn:hover:not(:disabled) { background: rgba(255, 255, 255, .12); }
.bulk-btn:disabled { opacity: .5; cursor: not-allowed; }
.bulk-btn-danger { background: var(--red); border-color: var(--red); font-weight: 500; }
.bulk-btn-danger:hover:not(:disabled) { background: var(--red); filter: brightness(1.1); }
.bulk-close {
    width: 34px; height: 34px; border: 0; border-radius: 8px; cursor: pointer;
    background: transparent; color: rgba(255, 255, 255, .65);
    display: grid; place-items: center;
}
.bulk-close:hover { color: #fff; background: rgba(255, 255, 255, .12); }

/* ── Shared table column structure ───────────────────────────────
   ONE source of truth for the column widths. `.items-row` is used by
   the header and every body row, so they can never drift apart. The
   two candidate lists come from the component (the Select and Category
   columns come and go); this decides which one is in force, so the
   media query below still wins over the inline custom properties. */
.items-scroll { overflow-x: auto; }
.items-table { --items-cols: var(--items-cols-wide); width: 100%; min-width: var(--items-min); }
.items-row {
    display: grid;
    grid-template-columns: var(--items-cols);
    align-items: center;
    column-gap: 8px;
}
.items-row > * {
    padding: 12px;
    min-width: 0;            /* let cells shrink + truncate instead of forcing overflow */
    text-align: start;       /* logical alignment → correct in both LTR and RTL */
}
.items-row > *:first-child { padding-inline-start: 20px; }
.items-row > *:last-child  { padding-inline-end: 20px; }
.items-head {
    background: var(--page);
    border-bottom: 1px solid var(--line);
    color: var(--muted);
    font-size: 11px;
    font-weight: 500;
    letter-spacing: .06em;
    text-transform: uppercase;
}
.items-body-row { border-top: 1px solid var(--line); }
.items-head + .items-body-row { border-top: 0; }
.items-body-row:hover { background: var(--accent-soft); }
.col-center  { text-align: center; }
.col-actions { text-align: end; }

.row-thumb {
    flex: none; width: 48px; height: 48px; border-radius: 10px;
}
.row-thumb-blank {
    display: grid; place-items: center;
    background: var(--gray-soft); color: var(--muted);
    font-family: var(--font-display); font-weight: 600; font-size: 17px;
}
.cat-tag {
    display: inline-block; max-width: 100%;
    font-size: 12.5px; padding: 3px 10px; border-radius: 999px;
    background: var(--gray-soft); color: var(--body);
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
}
.tabular { font-variant-numeric: tabular-nums; }

/* Availability reads as a switch plus the word for its state, so the
   meaning does not rest on colour alone. */
.avail-toggle {
    display: inline-flex; align-items: center; gap: 8px;
    border: 0; background: transparent; padding: 0; cursor: pointer;
    font-family: inherit;
}
.avail-label { font-size: 13px; font-weight: 500; color: var(--muted); }
.avail-label.on { color: var(--green); }

.items-empty { padding: 56px 24px; text-align: center; color: var(--muted); font-size: 14px; }
.items-foot {
    display: flex; align-items: center; justify-content: space-between; gap: 12px;
    padding: 12px 16px;
    background: var(--page);
    border-top: 1px solid var(--line);
    font-size: 12.5px; color: var(--muted);
}

/* Product info column follows the active language / page direction: the
   name(s) + description align to the reading edge, never centered. */
.product-info { display: flex; flex-direction: column; }
/* Plain `row` + the inherited direction mirrors correctly: in RTL the image
   (first DOM child) lands at the right reading edge with the text to its left;
   in LTR it stays on the left. The group packs to the reading edge on its own. */
[dir="rtl"] .product-cell { flex-direction: row; direction: rtl; justify-content: flex-start; }
[dir="ltr"] .product-cell { flex-direction: row; direction: ltr; justify-content: flex-start; }
/* Every line takes the full column width so its own text-align is what
   decides the edge — not the flex item's content-sized cross position. */
.product-info > * { width: 100%; max-width: 100%; }
[dir="rtl"] .product-info { direction: rtl; align-items: flex-end; }
[dir="rtl"] .product-info > * { text-align: right !important; }
[dir="ltr"] .product-info { direction: ltr; align-items: flex-start; }
[dir="ltr"] .product-info > * { text-align: left !important; }

@media (max-width: 639px) {
    /* Category + Featured collapse; the remaining columns stay aligned. */
    .items-table { --items-cols: var(--items-cols-narrow); min-width: 0; }
    .col-cat, .col-feat { display: none; }
    .avail-label { display: none; }
    .row-thumb { width: 40px; height: 40px; }
}

/* ── Multi-select ──────────────────────────────────────────────── */
.col-select { padding-inline: 8px; }
.row-check {
    width: 16px;
    height: 16px;
    accent-color: var(--accent);
    cursor: pointer;
    vertical-align: middle;
}
.items-body-row.row-selected { background: var(--accent-soft); }

/* Menu-order cell: grip, position number, and the up/down pair that does the
   same job for touch and keyboard, where dragging is not an option. */
.col-order { display: flex; align-items: center; gap: 4px; }
.col-order .drag-handle {
    flex: none;
    display: grid;
    place-items: center;
    width: 22px;
    height: 26px;
    border: 0;
    background: transparent;
    border-radius: 6px;
    color: var(--muted);
    cursor: grab;
    touch-action: none;
}
.col-order .drag-handle:hover { color: var(--ink); background: var(--accent-soft); }
.col-order .drag-handle:active { cursor: grabbing; }
.col-order .row-num {
    flex: none;
    min-width: 18px;
    text-align: center;
    font-size: 13px;
    font-weight: 600;
    color: var(--muted);
    font-variant-numeric: tabular-nums;
}
.order-arrows { display: flex; flex-direction: column; flex: none; }
.order-arrows .icon-btn { width: 22px; height: 15px; }

.items-body-row.row-dragging { opacity: .5; }
.items-body-row.row-drop { box-shadow: inset 0 2px 0 0 var(--accent); }

/* ── Card view ─────────────────────────────────────────────────── */
.items-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(230px, 1fr));
    gap: 16px;
}
.item-card {
    background: var(--card);
    border: 1px solid var(--line);
    border-radius: 14px;
    overflow: hidden;
    display: flex;
    flex-direction: column;
    transition: border-color .15s;
}
.item-card.selected { border-color: var(--accent); }
/* Fixed height, not an aspect ratio: menu photos arrive at every shape, and
   a ratio still let each card size itself from its own image, so no two cards
   in a row lined up. A fixed box crops them all to the same window. */
.item-card-media {
    position: relative;
    height: 180px;
    flex: none;
    background: var(--gray-soft);
    display: grid;
    place-items: center;
    overflow: hidden;
}
/* Taken out of flow: as a grid item the image's intrinsic height sizes the
   row and wins over `aspect-ratio`, so cards ended up as tall as their
   photos and no two were the same height. */
.item-card-media > img { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: cover; }
.item-card-initial { font-family: var(--font-display); font-size: 40px; font-weight: 600; color: var(--muted); }
.item-card-check { position: absolute; top: 12px; inset-inline-end: 12px; width: 17px; height: 17px; }
.item-card-star {
    position: absolute; top: 8px; inset-inline-start: 8px;
    width: 32px; height: 32px; border: 0; border-radius: 50%; cursor: pointer;
    background: var(--card); color: var(--muted);
    display: grid; place-items: center;
    box-shadow: 0 1px 3px rgba(0, 0, 0, .12);
}
.item-card-star.on { color: #e0a82e; }
.item-card-body { padding: 14px 14px 12px; display: flex; flex-direction: column; gap: 3px; flex: 1 0 auto; min-width: 0; }
.item-card-cat { font-size: 12px; color: var(--muted); }
.item-card-name { font-size: 15px; font-weight: 600; color: var(--ink); }
.item-card-alt { font-size: 12px; color: var(--muted); text-align: start; }
.item-card-foot {
    display: flex; align-items: center; justify-content: space-between; gap: 8px;
    padding: 10px 12px;
    border-top: 1px solid var(--line);
}
</style>
