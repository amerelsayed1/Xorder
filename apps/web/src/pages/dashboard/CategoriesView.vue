<script setup>
import { ref, reactive, computed, onMounted, onBeforeUnmount } from 'vue'
import { RouterLink } from 'vue-router'
import { useI18n } from 'vue-i18n'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import { withMinDuration } from '../../lib/minLoading.js'
import { useCaps } from '../../lib/useCaps.js'
import { pickLocalized } from '@xorder/ui/localize.js'
import Modal from '@xorder/ui/Modal.vue'
import BusinessHoursEditor from '../../components/BusinessHoursEditor.vue'
import ListSkeleton from '@xorder/ui/ListSkeleton.vue'
import ImageUploader from '@xorder/ui/ImageUploader.vue'
import FormError from '@xorder/ui/FormError.vue'
import Icon from '@xorder/ui/Icon.vue'
import { confirm } from '@xorder/ui/confirm.js'
import { alert } from '@xorder/ui/alert.js'
import { useMenuLang } from '../../lib/menuLang.js'

const { t, locale } = useI18n()
const { langs, bilingual } = useMenuLang()
// Per-action gates so the UI offers only what the API would accept.
const { canCreate, canUpdate, canDelete } = useCaps('menu')

const rows = ref([])
const loading = ref(true)
const saving = ref(false)
const showModal = ref(false)
const editing = ref(null)
const errors = ref({})
const form = reactive({ name_en: '', name_ar: '', description_en: '', description_ar: '', image_url: '', is_active: true, availability_hours: {} })

// Whether this category is served on a schedule at all. Kept beside the hours
// rather than inferred from them: the editor always holds seven populated rows
// once opened, so "has hours" would read true the moment it was glanced at.
const timed = ref(false)
function toggleTimed() {
    timed.value = !timed.value
    if (!timed.value) form.availability_hours = {}
}

async function load() {
    loading.value = true
    const { data } = await withMinDuration(api.get('api/dashboard/categories'))
    rows.value = data.data
    clearSelection() // dropped ids (e.g. after a delete) shouldn't linger selected
    loading.value = false
}
onMounted(load)

// --- Search + filters ------------------------------------------------------
// Filter pills work off the full list so the counts don't shift as the user
// types; the search only narrows what the row list renders.
const q = ref('')
const filter = ref('all')
const query = computed(() => q.value.trim().toLowerCase())
const hasFilters = computed(() => filter.value !== 'all' || query.value.length > 0)
function resetFilters() { q.value = ''; filter.value = 'all' }

const visibleCount = computed(() => rows.value.filter(c => c.is_active).length)
const itemsTotal = computed(() => rows.value.reduce((a, c) => a + (c.items_count || 0), 0))

const filterCounts = computed(() => ({
    all: rows.value.length,
    vis: visibleCount.value,
    hid: rows.value.length - visibleCount.value,
    empty: rows.value.filter(c => !c.items_count).length,
}))
const filterPills = computed(() => [
    { key: 'all', label: t('category.filter_all'), count: filterCounts.value.all },
    { key: 'vis', label: t('category.filter_visible'), count: filterCounts.value.vis },
    { key: 'hid', label: t('category.filter_hidden'), count: filterCounts.value.hid },
    { key: 'empty', label: t('category.filter_empty'), count: filterCounts.value.empty },
])

const shown = computed(() => rows.value.filter((c) => {
    if (filter.value === 'vis' && !c.is_active) return false
    if (filter.value === 'hid' && c.is_active) return false
    if (filter.value === 'empty' && c.items_count) return false
    if (query.value) {
        const ar = (c.name_ar || '').toLowerCase()
        const en = (c.name_en || '').toLowerCase()
        if (!ar.includes(query.value) && !en.includes(query.value)) return false
    }
    return true
}))
const noResults = computed(() => rows.value.length > 0 && shown.value.length === 0)

// Reordering only makes sense on the true list — a filtered/searched view
// hides context, so drop targets and adjacency lose meaning.
const canReorder = computed(() => !hasFilters.value)

// --- Multi-select / bulk actions ---
const selected = ref(new Set())
function toggleSelect(id) {
    if (selected.value.has(id)) selected.value.delete(id)
    else selected.value.add(id)
}
function clearSelection() { selected.value.clear() }
const allSelected = computed(() => shown.value.length > 0 && shown.value.every(c => selected.value.has(c.id)))
function toggleAll() {
    if (allSelected.value) shown.value.forEach(c => selected.value.delete(c.id))
    else shown.value.forEach(c => selected.value.add(c.id))
}
const selectedCount = computed(() => selected.value.size)

const bulkBusy = ref(false)
async function bulkSetVisibility(active) {
    const ids = [...selected.value]
    if (!ids.length || bulkBusy.value) return
    bulkBusy.value = true
    // Optimistic: flip locally, then push each change. On failure reload to
    // snap back to the server's truth — the API takes one row per PATCH.
    const before = rows.value.map(c => ({ id: c.id, is_active: c.is_active }))
    rows.value = rows.value.map(c => ids.includes(c.id) ? { ...c, is_active: active } : c)
    try {
        await ensureCsrf()
        for (const id of ids) {
            await api.patch(`api/dashboard/categories/${id}/status`, { is_active: active })
        }
        clearSelection()
    } catch (err) {
        rows.value = rows.value.map(c => {
            const prev = before.find(b => b.id === c.id)
            return prev ? { ...c, is_active: prev.is_active } : c
        })
        alert(err.response?.data?.message || t('common.save_failed'))
    } finally {
        bulkBusy.value = false
    }
}
async function bulkRemove() {
    const ids = [...selected.value]
    if (!ids.length || bulkBusy.value) return
    const ok = await confirm({
        title: t('common.delete'),
        message: t('category.confirm_delete_selected', { n: ids.length }),
        confirmText: t('common.delete'),
        cancelText: t('common.cancel'),
        danger: true,
    })
    if (!ok) return
    bulkBusy.value = true
    try {
        await ensureCsrf()
        await api.delete('api/dashboard/categories/bulk', { data: { ids } })
        await load()
    } catch (err) {
        alert(err.response?.data?.message || t('common.delete_failed'))
    } finally {
        bulkBusy.value = false
    }
}

function openCreate() {
    editing.value = null; errors.value = {}
    Object.assign(form, { name_en: '', name_ar: '', description_en: '', description_ar: '', image_url: '', is_active: true, availability_hours: {} })
    timed.value = false
    showModal.value = true
}
function openEdit(c) {
    editing.value = c; errors.value = {}
    Object.assign(form, { name_en: c.name_en || '', name_ar: c.name_ar || '',
        description_en: c.description_en || '', description_ar: c.description_ar || '',
        image_url: c.image_url || '', is_active: c.is_active,
        availability_hours: c.availability_hours || {} })
    timed.value = !!c.availability_hours
    showModal.value = true
}
async function save() {
    if (saving.value) return // guard against double-submit (double-click)
    saving.value = true
    errors.value = {}
    try {
        await ensureCsrf()
        // null, not {}: the API treats an absent schedule as "served whenever
        // the menu is", and an empty object would be indistinguishable from a
        // schedule the owner meant to fill in.
        const payload = { ...form, availability_hours: timed.value ? form.availability_hours : null }
        if (editing.value) await api.put(`api/dashboard/categories/${editing.value.id}`, payload)
        else await api.post('api/dashboard/categories', payload)
        showModal.value = false
        await load()
    } catch (err) { errors.value = err.response?.data?.errors || {} }
    finally { saving.value = false }
}
async function toggle(c) {
    // Optimistic: flip locally, then reconcile with the server. Rolling back
    // on failure is the honest way to keep the switch honest.
    const before = c.is_active
    c.is_active = !before
    try {
        await ensureCsrf()
        await api.patch(`api/dashboard/categories/${c.id}/status`, { is_active: c.is_active })
    } catch (err) {
        c.is_active = before
        alert(err.response?.data?.message || t('common.save_failed'))
    }
}
async function remove(c) {
    const ok = await confirm({
        title: t('common.delete'),
        message: c.items_count ? t('category.delete_warning', { count: c.items_count }) : t('common.confirm_delete'),
        confirmText: t('common.delete'),
        cancelText: t('common.cancel'),
        danger: true,
    })
    if (!ok) return
    try {
        await ensureCsrf()
        await api.delete(`api/dashboard/categories/${c.id}`)
        await load()
    } catch (err) { alert(err.response?.data?.message || t('common.delete_failed')) }
}

// --- Reorder with undo toast ----------------------------------------------
// Persist the current row order (display_order = array position) to the API.
async function persistOrder(order = null) {
    const payload = order || rows.value.map((c, idx) => ({ id: c.id, display_order: idx }))
    try {
        await ensureCsrf()
        await api.patch('api/dashboard/categories/reorder', { order: payload })
        return true
    } catch (err) {
        alert(err.response?.data?.message || t('category.reorder_failed'))
        await load()
        return false
    }
}

// The row order the user saw before the last reorder committed. Populated
// only while the toast is up; undo restores it and re-persists.
const previousOrder = ref(null)
const toast = ref('')
let toastTimer = null
function showToast(message) {
    toast.value = message
    clearTimeout(toastTimer)
    toastTimer = setTimeout(() => {
        toast.value = ''
        previousOrder.value = null
    }, 4500)
}
async function undoReorder() {
    if (!previousOrder.value) return
    const snapshot = previousOrder.value
    previousOrder.value = null
    clearTimeout(toastTimer)
    toast.value = ''
    rows.value = snapshot
    await persistOrder()
}
onBeforeUnmount(() => clearTimeout(toastTimer))

async function commitReorder(before) {
    const ok = await persistOrder()
    if (!ok) return
    previousOrder.value = before
    showToast(t('category.reorder_saved'))
}

// --- Drag-and-drop reordering (grab the handle) ---
const dragIndex = ref(null)   // row being dragged (index in rows.value)
const overIndex = ref(null)   // row currently hovered as drop target
const dragReady = ref(false)  // only allow drag when initiated from the handle
function onDragStart(i, ev) {
    if (!canUpdate.value || !canReorder.value) return
    dragIndex.value = i
    ev.dataTransfer.effectAllowed = 'move'
    // Firefox requires data to be set for the drag to fire.
    ev.dataTransfer.setData('text/plain', String(i))
}
function onDragOver(i) {
    if (dragIndex.value === null) return
    overIndex.value = i
}
async function onDrop(i) {
    const from = dragIndex.value
    resetDrag()
    if (from === null || from === i) return
    const before = rows.value.slice()
    const arr = rows.value.slice()
    const [moved] = arr.splice(from, 1)
    arr.splice(i, 0, moved)
    rows.value = arr
    await commitReorder(before)
}
function resetDrag() {
    dragIndex.value = null
    overIndex.value = null
    dragReady.value = false
}

// --- Presentational helpers ----------------------------------------------
const categoryName = (c) => pickLocalized(c, 'name', locale.value)
const categoryAltName = (c) => locale.value === 'ar' ? (c.name_en || '') : (c.name_ar || '')
// The row index within the ORIGINAL list — needed because a filtered view
// hides drag anyway, and other operations (edit, delete) don't need it.
function indexOf(c) { return rows.value.indexOf(c) }
</script>

<template>
    <div class="cat-page">
        <!-- Header -->
        <div class="flex flex-wrap items-end justify-between gap-4">
            <div>
                <h1 class="page-title">{{ t('nav.categories') }}</h1>
                <p class="page-sub">{{ t('category.subtitle', { count: rows.length, visible: visibleCount, items: itemsTotal }) }}</p>
            </div>
            <button v-if="canCreate" @click="openCreate" class="btn btn-accent"><Icon name="plus" :size="16" />{{ t('category.new_category') }}</button>
        </div>

        <!-- Toolbar: search + filter pills + clear -->
        <div v-if="!loading && rows.length" class="cat-toolbar">
            <div class="cat-search">
                <Icon name="search" :size="16" class="cat-search-ico" />
                <input v-model="q" type="search" class="input cat-search-input" :placeholder="t('category.search_placeholder')" />
            </div>
            <div class="seg">
                <button v-for="f in filterPills" :key="f.key" class="seg-btn" :class="{ on: filter === f.key }" @click="filter = f.key">
                    {{ f.label }}<span class="seg-count mono">{{ f.count }}</span>
                </button>
            </div>
            <button v-if="hasFilters" @click="resetFilters" class="cat-clear">{{ t('category.clear_filters') }}</button>
        </div>

        <p v-if="!loading && rows.length && !canReorder && canUpdate" class="cat-lock-hint">{{ t('category.drag_locked') }}</p>

        <!-- Bulk actions (dark, when items are selected) -->
        <div v-if="selectedCount" class="bulk-bar">
            <span class="bulk-count">{{ t('category.selected_count', { n: selectedCount }) }}</span>
            <span class="flex-1"></span>
            <button v-if="canUpdate" class="bulk-btn" :disabled="bulkBusy" @click="bulkSetVisibility(true)">{{ t('category.bulk_show') }}</button>
            <button v-if="canUpdate" class="bulk-btn" :disabled="bulkBusy" @click="bulkSetVisibility(false)">{{ t('category.bulk_hide') }}</button>
            <button v-if="canDelete" class="bulk-btn bulk-btn-danger" :disabled="bulkBusy" @click="bulkRemove">{{ t('common.delete') }}</button>
            <button class="bulk-btn bulk-btn-ghost" @click="clearSelection">{{ t('category.clear_selection') }}</button>
        </div>

        <!-- Table card -->
        <div class="card cat-card">
            <ListSkeleton v-if="loading" />
            <div v-else-if="!rows.length" class="p-8 text-center" style="color:var(--muted)">{{ t('common.none') }}</div>
            <div v-else class="cat-scroll">
                <div class="cat-inner">
                    <!-- Column header -->
                    <div class="cat-row cat-head">
                        <div></div>
                        <input v-if="canDelete" type="checkbox" class="row-check" :checked="allSelected" :aria-label="t('common.select_all')" @change="toggleAll" />
                        <div v-else></div>
                        <div>{{ t('category.col_name') }}</div>
                        <div>{{ t('category.col_items') }}</div>
                        <div>{{ t('category.col_visibility') }}</div>
                        <div></div>
                    </div>

                    <div v-if="noResults" class="cat-empty">
                        <div class="cat-empty-title">{{ t('category.no_results_title') }}</div>
                        <div class="cat-empty-body">{{ t('category.no_results_body') }}</div>
                    </div>

                    <div
                        v-for="c in shown"
                        :key="c.id"
                        class="cat-row cat-data"
                        :class="{ 'row-selected': selected.has(c.id), 'row-dragging': dragIndex === indexOf(c), 'row-drop': overIndex === indexOf(c) && dragIndex !== null && dragIndex !== indexOf(c) }"
                        :draggable="canUpdate && canReorder && dragReady"
                        @dragstart="onDragStart(indexOf(c), $event)"
                        @dragover.prevent="onDragOver(indexOf(c))"
                        @drop.prevent="onDrop(indexOf(c))"
                        @dragend="resetDrag"
                    >
                        <!-- Drag handle: only arms the row while the mouse is held on it, so
                             the rest of the row (checkbox, name link) doesn't trigger drag. -->
                        <button
                            v-if="canUpdate"
                            class="drag-handle"
                            :class="{ locked: !canReorder }"
                            :title="canReorder ? t('category.drag_to_reorder') : t('category.drag_locked')"
                            :aria-label="t('category.drag_to_reorder')"
                            :disabled="!canReorder"
                            @mousedown="canReorder && (dragReady = true)"
                            @touchstart.passive="canReorder && (dragReady = true)"
                            @mouseup="dragReady = false"
                        ><Icon name="grip" :size="16" fill /></button>
                        <div v-else></div>

                        <input
                            v-if="canDelete"
                            type="checkbox"
                            class="row-check"
                            :checked="selected.has(c.id)"
                            :aria-label="categoryName(c)"
                            @change="toggleSelect(c.id)"
                        />
                        <div v-else></div>

                        <!-- Name + English alt-name + optional timed badge. The
                             design's row is name-only — the thumbnail lives on
                             the Items page, not here. -->
                        <div class="cat-name-cell">
                            <div class="min-w-0 flex-1 cat-info">
                                <div class="cat-name" :class="{ dim: !c.is_active }">{{ categoryName(c) }}</div>
                                <div v-if="categoryAltName(c)" class="cat-alt" :dir="locale === 'ar' ? 'ltr' : 'rtl'">{{ categoryAltName(c) }}</div>
                            </div>
                            <span v-if="c.availability_hours" class="badge badge-gray">{{ t('category.timed_badge') }}</span>
                        </div>

                        <!-- Item count (linked). Empty categories get the accent-dark tint
                             to distinguish "0 items" from a real count without adding a
                             separate badge. -->
                        <RouterLink :to="{ name: 'dashboard.items' }" class="cat-count" :class="{ empty: !c.items_count }">
                            <span class="mono">{{ c.items_count }}</span>
                            <span>{{ c.items_count ? t('category.items_word') : t('category.empty_word') }}</span>
                        </RouterLink>

                        <!-- Visibility switch + label -->
                        <button
                            v-if="canUpdate"
                            class="vis-toggle"
                            role="switch"
                            :aria-checked="c.is_active"
                            @click="toggle(c)"
                        >
                            <span class="vis-track" :class="{ on: c.is_active }"><span class="vis-knob"></span></span>
                            <span class="vis-label" :class="{ on: c.is_active }">{{ c.is_active ? t('category.visible_label') : t('category.hidden_label') }}</span>
                        </button>
                        <div v-else></div>

                        <!-- Row actions -->
                        <div class="cat-actions">
                            <button v-if="canUpdate" @click="openEdit(c)" class="icon-btn" :title="t('common.edit')" :aria-label="t('common.edit')"><Icon name="edit" :size="16" /></button>
                            <button v-if="canDelete" @click="remove(c)" class="icon-btn" :title="t('common.delete')" :aria-label="t('common.delete')"><Icon name="trash" :size="16" /></button>
                        </div>
                    </div>
                </div>
            </div>
        </div>

        <!-- Undo toast after reorder -->
        <transition name="cat-toast">
            <div v-if="toast" class="cat-toast">
                <span class="cat-toast-dot"></span>
                <span>{{ toast }}</span>
                <button v-if="previousOrder" @click="undoReorder" class="cat-toast-btn">{{ t('common.undo') }}</button>
            </div>
        </transition>

        <Modal v-if="showModal" :title="editing ? t('common.edit') : t('common.create')" @close="showModal = false">
            <div class="space-y-4">
                <label v-for="lng in langs" :key="'n' + lng" class="block" :dir="lng === 'ar' ? 'rtl' : 'ltr'">
                    <span class="label">{{ bilingual ? t('common.name_' + lng) : t('common.name') }}</span>
                    <input v-model="form['name_' + lng]" class="input" />
                    <FormError :errors="errors" :field="'name_' + lng" /></label>
                <label v-for="lng in langs" :key="'d' + lng" class="block" :dir="lng === 'ar' ? 'rtl' : 'ltr'">
                    <span class="label">{{ bilingual ? t('common.description_' + lng) : t('common.description') }}</span>
                    <textarea v-model="form['description_' + lng]" rows="2" class="input"></textarea></label>
                <ImageUploader v-model="form.image_url" folder="categories" :label="t('category.image')" />
                <label class="flex items-center gap-2 text-sm" style="color:var(--body)">
                    <button type="button" class="switch" :class="{ on: form.is_active }" @click="form.is_active = !form.is_active"></button>
                    {{ t('common.active') }}
                </label>

                <!-- Serving times. Off by default and hidden until asked for, so
                     the common category (served all day) keeps a two-field form
                     instead of paying for a seven-row editor it never needs. -->
                <div>
                    <label class="flex items-center gap-2 text-sm" style="color:var(--body)">
                        <button type="button" class="switch" :class="{ on: timed }" @click="toggleTimed"></button>
                        {{ t('category.timed') }}
                    </label>
                    <p class="text-xs" style="color:var(--muted);margin-top:4px">{{ t('category.timed_hint') }}</p>
                    <div v-if="timed" style="margin-top:10px">
                        <BusinessHoursEditor v-model="form.availability_hours" :disabled="!canUpdate" />
                        <FormError :errors="errors" field="availability_hours" />
                    </div>
                </div>
                <div class="flex justify-end gap-2 pt-2">
                    <button @click="showModal = false" :disabled="saving" class="btn btn-ghost">{{ t('common.cancel') }}</button>
                    <button @click="save" :disabled="saving" class="btn btn-accent">
                        <Icon v-if="saving" name="loading" :size="16" class="animate-spin" />
                        {{ saving ? t('common.saving') : t('common.save') }}
                    </button>
                </div>
            </div>
        </Modal>
    </div>
</template>

<style scoped>
.cat-page { display: flex; flex-direction: column; gap: 20px; }
.mono { font-family: var(--font-mono); font-variant-numeric: tabular-nums; }

/* ── Toolbar: search + filter pills ────────────────────────────── */
.cat-toolbar { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; }
.cat-search { position: relative; flex: 1 1 220px; max-width: 380px; }
.cat-search-ico { position: absolute; top: 12px; inset-inline-end: 12px; color: var(--muted); pointer-events: none; }
.cat-search-input { height: 40px; padding-inline-end: 38px; }
.cat-clear {
    height: 40px; padding: 0 10px; border: 0; background: transparent;
    font-family: inherit; font-size: 13px; font-weight: 500; color: var(--accent);
    cursor: pointer; white-space: nowrap;
}
.seg { display: inline-flex; background: var(--gray-soft); border-radius: 10px; padding: 3px; gap: 2px; }
.seg-btn {
    height: 34px; padding: 0 14px; white-space: nowrap; border: 0; border-radius: 8px;
    display: inline-flex; align-items: center; gap: 6px;
    background: transparent; color: var(--body);
    font-family: inherit; font-size: 13px; font-weight: 500; cursor: pointer;
    transition: background .15s, color .15s, box-shadow .15s;
}
.seg-btn.on { background: var(--card); color: var(--ink); font-weight: 600; box-shadow: 0 1px 2px rgba(0, 0, 0, .08); }
.seg-count { font-size: 11.5px; color: var(--muted); }

.cat-lock-hint { font-size: 12.5px; color: var(--muted); margin: -8px 0 0; }

/* ── Bulk-action bar (dark) ────────────────────────────────────── */
.bulk-bar {
    display: flex; align-items: center; gap: 6px; flex-wrap: wrap;
    padding: 8px 8px 8px 12px; background: var(--ink); color: #fff; border-radius: 12px;
}
[dir="rtl"] .bulk-bar { padding: 8px 12px 8px 8px; }
.bulk-count { padding: 0 8px; font-size: 13.5px; font-weight: 600; }
.bulk-btn {
    height: 34px; padding: 0 12px; white-space: nowrap; border: 0; border-radius: 8px;
    background: #2B2620; color: #fff; font-family: inherit; font-size: 13px; cursor: pointer;
    transition: background .15s;
}
.bulk-btn:hover:not(:disabled) { background: #3A342C; }
.bulk-btn:disabled { opacity: .55; cursor: default; }
.bulk-btn-danger { color: #F2A49D; }
.bulk-btn-ghost { background: transparent; color: #C4BCB1; }
.bulk-btn-ghost:hover { background: rgba(255, 255, 255, .06); }

/* ── Category table ────────────────────────────────────────────── */
.cat-card { overflow: hidden; }
.cat-scroll { overflow-x: auto; }
/* Enough room for the widest row (name + count + toggle + actions) without
   crowding — anything narrower and the columns start clipping into each other. */
.cat-inner { min-width: 620px; }
.cat-row {
    display: grid;
    grid-template-columns: 24px 20px minmax(200px, 1fr) 90px 140px 80px;
    align-items: center; gap: 14px; padding: 0 16px;
}
.cat-head {
    height: 44px; background: var(--page); border-bottom: 1px solid var(--line);
    font-size: 12.5px; font-weight: 600; color: var(--body);
}
.cat-data {
    min-height: 68px; background: var(--card);
    border-bottom: 1px solid var(--line); transition: background .15s;
}
.cat-data:last-child { border-bottom: 0; }
.cat-data:hover { background: #FCFBF9; }
.cat-data.row-selected { background: #FFFAF4; }
.cat-data.row-dragging { opacity: .45; }
.cat-data.row-drop { box-shadow: inset 0 2px 0 0 var(--accent); }

.row-check { width: 16px; height: 16px; accent-color: var(--accent); cursor: pointer; }

.drag-handle {
    display: grid; place-items: center; width: 24px; height: 36px;
    border: 0; background: transparent; border-radius: 6px;
    color: var(--muted); cursor: grab; touch-action: none;
    transition: background .15s, color .15s;
}
.drag-handle:hover:not(.locked) { background: var(--gray-soft); color: var(--ink); }
.drag-handle:active { cursor: grabbing; }
.drag-handle.locked { color: color-mix(in srgb, var(--muted) 55%, transparent); cursor: not-allowed; }

/* Name cell: AR + EN stack (+ optional timed badge). Design has no thumbnail
   here — the image lives on the Items page. */
.cat-name-cell { display: flex; align-items: center; gap: 12px; min-width: 0; }
.cat-info { display: flex; flex-direction: column; gap: 2px; min-width: 0; }
.cat-name {
    font-size: 14.5px; font-weight: 600; color: var(--ink);
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
}
.cat-name.dim { color: var(--muted); }
.cat-alt {
    font-size: 12px; color: var(--muted);
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
}
/* Force alt-name to the reading edge even though its dir is opposite. */
[dir="rtl"] .cat-alt { text-align: right; }
[dir="ltr"] .cat-alt { text-align: left; }

/* Item-count link. Accent-dark tone for "empty" makes it a mild flag, not
   alarm — an empty category is normal at the start, not an error. */
.cat-count {
    display: inline-flex; align-items: baseline; gap: 4px;
    font-size: 13.5px; color: #4A443C; text-decoration: none;
}
.cat-count:hover { color: var(--accent-dark); }
.cat-count .mono { font-weight: 600; color: inherit; }
.cat-count.empty { color: #B85E05; }

/* Track/knob toggle. Green when on ("visible to diners"), warm-gray when off.
   Design slides the knob along the reading axis: in RTL "on" pulls the knob
   toward the LEFT (end of the row), "off" leaves it at the RIGHT (start). */
.vis-toggle {
    display: inline-flex; align-items: center; gap: 10px;
    border: 0; background: transparent; padding: 4px 0; cursor: pointer;
    font-family: inherit; font-size: 13px; color: var(--muted);
}
.vis-track {
    position: relative; width: 36px; height: 20px; border-radius: 999px;
    background: #D6CFC4; transition: background .15s; flex: none;
}
.vis-track.on { background: #2F7D4F; }
.vis-knob {
    position: absolute; top: 2px; right: 2px;
    width: 16px; height: 16px; border-radius: 50%; background: #fff;
    box-shadow: 0 1px 2px rgba(0, 0, 0, .2);
    transition: right .15s;
}
.vis-track.on .vis-knob { right: 18px; }
.vis-label.on { color: #2F7D4F; }

.cat-actions { display: flex; align-items: center; gap: 2px; justify-content: flex-end; }

/* No-results (empty) state inside the table */
.cat-empty {
    padding: 48px 20px; text-align: center;
    display: flex; flex-direction: column; align-items: center; gap: 8px;
    background: var(--card);
}
.cat-empty-title { font-size: 15px; font-weight: 600; color: var(--ink); }
.cat-empty-body { font-size: 13.5px; color: var(--muted); }

/* ── Undo toast ─────────────────────────────────────────────────── */
.cat-toast {
    position: fixed; bottom: 24px; left: 50%; transform: translateX(-50%);
    z-index: 15; display: flex; align-items: center; gap: 14px;
    padding: 10px 10px 10px 16px; background: var(--ink); color: #fff;
    border-radius: 12px; box-shadow: 0 10px 30px rgba(31, 27, 22, .25);
    font-size: 13.5px;
}
[dir="rtl"] .cat-toast { padding: 10px 16px 10px 10px; }
.cat-toast-dot { width: 8px; height: 8px; border-radius: 50%; background: #5BBE82; flex: none; }
.cat-toast-btn {
    height: 32px; padding: 0 12px; white-space: nowrap; border: 0; border-radius: 8px;
    background: #2B2620; color: #F7B26A;
    font-family: inherit; font-size: 13px; font-weight: 600; cursor: pointer;
}
.cat-toast-enter-from, .cat-toast-leave-to { opacity: 0; transform: translate(-50%, 10px); }
.cat-toast-enter-active, .cat-toast-leave-active { transition: opacity .18s, transform .18s; }
</style>
