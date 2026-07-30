<script setup>
import { ref, onMounted, computed } from 'vue'
import { useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import { withMinDuration } from '../../lib/minLoading.js'
import { useAuth } from '@xorder/api-client/auth.js'
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
const cur = computed(() => currencyLabel(auth.restaurant?.currency, locale.value, auth.restaurant?.currency_symbol))
const items = ref([])
const categories = ref([])
const loading = ref(true)
const filterCat = ref('')
const search = ref('')

// Item ids whose image_url failed to load (dead/broken link) — they fall back
// to the meal-icon placeholder instead of the browser's broken-image glyph.
const failedImg = ref(new Set())
function onImgError(id) { failedImg.value.add(id) }

const filtered = computed(() => {
    let list = filterCat.value
        ? items.value.filter(i => i.category_id === Number(filterCat.value))
        : items.value
    const q = search.value.trim().toLowerCase()
    if (q) list = list.filter(i =>
        (i.name_en || '').toLowerCase().includes(q) || (i.name_ar || '').toLowerCase().includes(q))
    return list
})

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
        // category has nothing to show and is dropped from the chips/count.
        categories.value = cats.data.data.filter(c => c.is_active)
        // No "All" chip — default to (and keep) a real category selection.
        if (!categories.value.some(c => c.id === filterCat.value))
            filterCat.value = categories.value[0]?.id ?? ''
        clearSelection()
    } catch (e) {
        console.error('Failed to load menu items', e)
    } finally {
        loading.value = false
    }
}
onMounted(load)

// --- Multi-select / bulk delete ---
// Selection is keyed by item id and persists across search/category filtering
// so a user can narrow the list, tick a few, change the filter, tick more,
// then delete the whole set at once.
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
    if (!ids.length || bulkDeleting.value) return
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

function catName(id) {
    const c = categories.value.find(c => c.id === id)
    return c ? pickLocalized(c, 'name', locale.value) : ''
}
const itemName = (it) => pickLocalized(it, 'name', locale.value)
const itemAltName = (it) => locale.value === 'ar' ? (it.name_en || '') : (it.name_ar || '')
const itemDescription = (it) => pickLocalized(it, 'description', locale.value)
function goCreate() {
    if (!categories.value.length) return
    router.push({ name: 'dashboard.items.create' })
}
function goEdit(it) { router.push({ name: 'dashboard.items.edit', params: { id: it.id } }) }
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
    <div class="space-y-5">
      <!-- Sticky header: title, actions, search + category filter, and the
           bulk-action bar stay pinned under the topbar while the table scrolls. -->
      <div class="items-header">
        <div class="flex flex-wrap items-start justify-between gap-3">
            <div>
                <h1 class="page-title">{{ t('nav.items') }}</h1>
                <p class="page-sub">{{ t('item.subtitle', { items: items.length, categories: categories.length }) }}</p>
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
                <button v-if="!auth.isReadOnly" @click="openImport" class="btn btn-ghost"><Icon name="upload" :size="16" />{{ t('import.button') }}</button>
                <button v-if="!auth.isReadOnly" @click="goCreate" :disabled="!categories.length" class="btn btn-accent"><Icon name="plus" :size="16" />{{ t('common.create') }}</button>
            </div>
        </div>
        <p v-if="!categories.length" class="text-sm" style="color:var(--amber)">{{ t('item.create_category_first') }}</p>

        <!-- Toolbar -->
        <div class="flex flex-wrap items-center gap-3">
            <div class="relative" style="max-width:280px;width:100%">
                <span class="absolute top-1/2 -translate-y-1/2 inset-inline-start-3 pointer-events-none" style="inset-inline-start:12px;color:var(--muted)"><Icon name="search" :size="17" /></span>
                <input v-model="search" :placeholder="t('common.search')" class="input" style="padding-inline-start:38px" />
            </div>
            <div class="cat-filter">
                <button v-for="c in categories" :key="c.id" class="cat-chip" :class="{ active: filterCat === c.id }" @click="filterCat = c.id">
                    {{ catName(c.id) }}
                </button>
            </div>
        </div>

        <!-- Bulk action bar — appears once one or more rows are ticked. -->
        <div v-if="!auth.isReadOnly && selected.size" class="bulk-bar">
            <span class="bulk-count">{{ t('item.selected_count', { n: selected.size }) }}</span>
            <button class="btn btn-ghost btn-sm" @click="clearSelection">{{ t('item.clear_selection') }}</button>
            <button class="btn btn-danger btn-sm" :disabled="bulkDeleting" @click="bulkRemove">
                <Icon v-if="bulkDeleting" name="loading" :size="15" class="animate-spin" />
                <Icon v-else name="trash" :size="15" />
                {{ t('item.delete_selected') }}
            </button>
        </div>
      </div>

        <!-- Table -->
        <div class="card overflow-hidden">
            <ListSkeleton v-if="loading" />
            <div v-else-if="!filtered.length" class="p-8 text-center" style="color:var(--muted)">{{ t('common.none') }}</div>
            <!--
              Single shared column structure for header + every row.
              Both the header and each body row use `.items-row`, whose
              `grid-template-columns` comes from the one `--items-cols` token
              defined on `.items-table`. Change a width there once and the
              header and all rows update together — no per-row adjustments,
              no separate flex layouts, no absolute positioning.
              Visual (RTL) order: Product | Category | Price | Featured | Available | Actions
            -->
            <div v-else class="items-table" :class="{ 'select-mode': !auth.isReadOnly }" role="table">
                <div class="items-row items-head" role="row">
                    <div v-if="!auth.isReadOnly" role="columnheader" class="col-center col-select">
                        <input type="checkbox" class="row-check" :checked="allFilteredSelected"
                            :indeterminate.prop="someFilteredSelected" :aria-label="t('item.select_all')"
                            @change="toggleAll" />
                    </div>
                    <div role="columnheader" class="col-center">#</div>
                    <div role="columnheader">{{ t('item.item') }}</div>
                    <div role="columnheader" class="col-cat">{{ t('item.category') }}</div>
                    <div role="columnheader">{{ t('item.price') }}</div>
                    <div role="columnheader" class="col-feat col-center">★</div>
                    <div role="columnheader" class="col-center">{{ t('common.available') }}</div>
                    <div role="columnheader" class="col-actions">{{ t('common.actions') }}</div>
                </div>
                <div v-for="(it, idx) in filtered" :key="it.id" class="items-row items-body-row" :class="{ 'row-selected': selected.has(it.id) }" role="row">
                    <div v-if="!auth.isReadOnly" role="cell" class="col-center col-select">
                        <input type="checkbox" class="row-check" :checked="selected.has(it.id)"
                            :aria-label="itemName(it)" @change="toggleSelect(it.id)" />
                    </div>
                    <div role="cell" class="col-center" style="color:var(--muted)">{{ idx + 1 }}</div>
                    <div role="cell">
                        <div class="flex items-center gap-3 min-w-0">
                            <img v-if="it.image_url && !failedImg.has(it.id)" :src="it.image_url" @error="onImgError(it.id)" class="h-11 w-11 rounded-lg object-cover flex-shrink-0" />
                            <div v-else class="h-11 w-11 rounded-lg flex-shrink-0 flex items-center justify-center" style="background:var(--accent-soft);color:var(--accent)"><Icon name="utensils" :size="20" /></div>
                            <div class="min-w-0">
                                <div class="font-medium truncate" style="color:var(--ink)">{{ itemName(it) }}</div>
                                <div v-if="itemAltName(it)" class="text-xs truncate" style="color:var(--muted)" :dir="locale === 'ar' ? 'ltr' : 'rtl'">{{ itemAltName(it) }}</div>
                                <div v-if="itemDescription(it)" class="text-xs truncate" style="color:var(--body)">{{ itemDescription(it) }}</div>
                            </div>
                        </div>
                    </div>
                    <div role="cell" class="col-cat truncate" style="color:var(--body)">{{ catName(it.category_id) }}</div>
                    <div role="cell" class="whitespace-nowrap">
                        <span class="price">{{ it.discounted_price || it.price }} {{ cur }}</span>
                        <span v-if="it.discounted_price" class="text-xs line-through ms-1" style="color:var(--muted)">{{ it.price }} {{ cur }}</span>
                    </div>
                    <div role="cell" class="col-feat col-center">
                        <button v-if="!auth.isReadOnly" class="star" :class="{ on: it.is_featured }" @click="toggleFeatured(it)">★</button>
                    </div>
                    <div role="cell" class="col-center">
                        <button v-if="!auth.isReadOnly" class="switch" :class="{ on: it.is_available }" @click="toggleAvail(it)"></button>
                    </div>
                    <div role="cell" class="col-actions whitespace-nowrap">
                        <div class="inline-flex items-center gap-1">
                            <button v-if="!auth.isReadOnly" @click="goEdit(it)" class="icon-btn" :title="t('common.edit')"><Icon name="edit" :size="17" /></button>
                            <button v-if="!auth.isReadOnly" @click="remove(it)" class="icon-btn icon-btn-danger" :title="t('common.delete')"><Icon name="trash" :size="17" /></button>
                        </div>
                    </div>
                </div>
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
/* ── Sticky header ────────────────────────────────────────────────
   Pins the title, actions, search + category filter, and the bulk bar
   just under the fixed 64px topbar so the item table scrolls beneath
   them. The negative inline margins + matching padding let the page
   background bleed edge-to-edge, hiding rows that slide under it, while
   the content stays aligned with the container below. */
.items-header {
    position: sticky;
    top: 64px;
    z-index: 20;
    display: flex;
    flex-direction: column;
    gap: 20px;                 /* keep the space-y-5 rhythm inside the wrapper */
    background: var(--page);
    margin-inline: -28px;
    padding: 16px 28px 14px;
    border-bottom: 1px solid var(--line);
}
@media (max-width: 640px) {
    .items-header { margin-inline: 0; padding-inline: 0; }
}

/* ── Shared table column structure ───────────────────────────────
   ONE source of truth for the column widths. `.items-row` is used by
   the header and every body row, so they can never drift apart. Order
   matches the RTL visual order: Product | Category | Price | Featured
   | Available | Actions. Adjust widths here once → header + rows follow. */
.items-table {
    --items-cols:
        48px                 /* No. */
        minmax(320px, 2fr)   /* Product (image + name) */
        minmax(180px, 1fr)   /* Category */
        minmax(140px, 0.8fr) /* Price */
        100px                /* Featured */
        120px                /* Available */
        110px;               /* Actions */
    width: 100%;
    overflow-x: auto;        /* keeps columns aligned; scrolls instead of breaking on narrow desktops */
}
/* When selection is enabled, prepend a fixed checkbox column ahead of "#". */
.items-table.select-mode {
    --items-cols:
        44px                 /* Select */
        48px                 /* No. */
        minmax(320px, 2fr)   /* Product (image + name) */
        minmax(180px, 1fr)   /* Category */
        minmax(140px, 0.8fr) /* Price */
        100px                /* Featured */
        120px                /* Available */
        110px;               /* Actions */
}
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
    color: var(--muted);
    font-size: 11px;
    font-weight: 500;
    letter-spacing: .06em;
    text-transform: uppercase;
}
.items-body-row { border-top: 1px solid var(--line); }
.items-body-row:hover { background: var(--accent-soft); }
/* Same alignment applied to header AND body cell of a column (req. 6). */
.col-center  { text-align: center; }
.col-actions { text-align: end; }

@media (max-width: 639px) {
    /* Category + Featured collapse; the remaining 4 columns stay aligned. */
    .items-table {
        --items-cols:
            40px                 /* No. */
            minmax(0, 2fr)       /* Product */
            minmax(120px, 1fr)   /* Price */
            100px                /* Available */
            100px;               /* Actions */
    }
    .items-table.select-mode {
        --items-cols:
            36px                 /* Select */
            40px                 /* No. */
            minmax(0, 2fr)       /* Product */
            minmax(120px, 1fr)   /* Price */
            100px                /* Available */
            100px;               /* Actions */
    }
    .col-cat, .col-feat { display: none; }
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

/* Sticky bar that surfaces bulk actions for the current selection. */
.bulk-bar {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 10px 14px;
    border-radius: 12px;
    background: var(--accent-soft);
    border: 1px solid var(--accent);
}
.bulk-count {
    font-weight: 600;
    font-size: 13.5px;
    color: var(--accent);
    margin-inline-end: auto;
}
.btn-danger { background: var(--red); color: #fff; border-color: var(--red); }
.btn-danger:hover:not(:disabled) { filter: brightness(.94); }
.btn-danger:disabled { opacity: .6; cursor: default; }

/* Horizontal chip filter — handles many categories (with long bilingual
   names) without wrapping into tall cramped tabs like the segmented control. */
.cat-filter {
    display: flex;
    gap: 6px;
    flex: 1 1 100%;
    min-width: 0;
    overflow-x: auto;
    padding-bottom: 4px;
    scrollbar-width: thin;
}
.cat-filter::-webkit-scrollbar { height: 5px; }
.cat-filter::-webkit-scrollbar-thumb { background: var(--line); border-radius: 999px; }
.cat-chip {
    flex: none;
    white-space: nowrap;
    font-family: var(--font-display);
    font-weight: 600;
    font-size: 13px;
    line-height: 1.2;
    padding: 8px 15px;
    border-radius: 999px;
    border: 1px solid var(--line);
    background: var(--card);
    color: var(--muted);
    cursor: pointer;
    transition: color .15s, background .15s, border-color .15s;
}
.cat-chip:hover { border-color: var(--accent); color: var(--accent); }
.cat-chip.active {
    background: var(--accent);
    border-color: var(--accent);
    color: #fff;
}
</style>
