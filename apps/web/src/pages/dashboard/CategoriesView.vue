<script setup>
import { ref, reactive, computed, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import { withMinDuration } from '../../lib/minLoading.js'
import { useAuth } from '@xorder/api-client/auth.js'
import { pickLocalized } from '@xorder/ui/localize.js'
import Modal from '@xorder/ui/Modal.vue'
import BusinessHoursEditor from '../../components/BusinessHoursEditor.vue'
import ListSkeleton from '@xorder/ui/ListSkeleton.vue'
import StatusBadge from '@xorder/ui/StatusBadge.vue'
import ImageUploader from '@xorder/ui/ImageUploader.vue'
import FormError from '@xorder/ui/FormError.vue'
import Icon from '@xorder/ui/Icon.vue'
import { confirm } from '@xorder/ui/confirm.js'
import { alert } from '@xorder/ui/alert.js'
import { useMenuLang } from '../../lib/menuLang.js'

const { t, locale } = useI18n()
const { langs, bilingual } = useMenuLang()
const auth = useAuth()
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

// --- Multi-select / bulk delete ---
const selected = ref(new Set())
function toggleSelect(id) {
    if (selected.value.has(id)) selected.value.delete(id)
    else selected.value.add(id)
}
function clearSelection() { selected.value.clear() }
const allSelected = computed(() => rows.value.length > 0 && rows.value.every(c => selected.value.has(c.id)))
function toggleAll() {
    if (allSelected.value) clearSelection()
    else rows.value.forEach(c => selected.value.add(c.id))
}
const bulkDeleting = ref(false)
async function bulkRemove() {
    const ids = [...selected.value]
    if (!ids.length || bulkDeleting.value) return
    const ok = await confirm({
        title: t('common.delete'),
        message: t('category.confirm_delete_selected', { n: ids.length }),
        confirmText: t('common.delete'),
        cancelText: t('common.cancel'),
        danger: true,
    })
    if (!ok) return
    bulkDeleting.value = true
    try {
        await ensureCsrf()
        await api.delete('api/dashboard/categories/bulk', { data: { ids } })
        await load()
    } catch (err) {
        alert(err.response?.data?.message || t('common.delete_failed'))
    } finally {
        bulkDeleting.value = false
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
    await ensureCsrf()
    await api.patch(`api/dashboard/categories/${c.id}/status`, { is_active: !c.is_active })
    c.is_active = !c.is_active
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
// Persist the current row order (display_order = array position) to the API.
// The local array is already in the desired order, so this is optimistic:
// on failure we reload to snap back to the server's truth.
async function persistOrder() {
    const order = rows.value.map((c, idx) => ({ id: c.id, display_order: idx }))
    try {
        await ensureCsrf()
        await api.patch('api/dashboard/categories/reorder', { order })
    } catch (err) {
        alert(err.response?.data?.message || t('category.reorder_failed'))
        await load()
    }
}
async function move(index, dir) {
    const target = index + dir
    if (target < 0 || target >= rows.value.length) return
    const arr = rows.value.slice()
    ;[arr[index], arr[target]] = [arr[target], arr[index]]
    rows.value = arr
    await persistOrder()
}

// --- Drag-and-drop reordering (grab the handle) ---
const dragIndex = ref(null)   // row being dragged
const overIndex = ref(null)   // row currently hovered as drop target
const dragReady = ref(false)  // only allow drag when initiated from the handle
function onDragStart(i, ev) {
    if (auth.isReadOnly) return
    dragIndex.value = i
    ev.dataTransfer.effectAllowed = 'move'
    // Firefox requires data to be set for the drag to fire.
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
    const arr = rows.value.slice()
    const [moved] = arr.splice(from, 1)
    arr.splice(i, 0, moved)
    rows.value = arr
    persistOrder()
}
function resetDrag() {
    dragIndex.value = null
    overIndex.value = null
    dragReady.value = false
}

const categoryName = (c) => pickLocalized(c, 'name', locale.value)
const categoryAltName = (c) => locale.value === 'ar' ? (c.name_en || '') : (c.name_ar || '')
</script>

<template>
    <div class="space-y-5">
        <div class="flex items-start justify-between gap-3">
            <div>
                <h1 class="page-title">{{ t('nav.categories') }}</h1>
                <p class="page-sub">{{ t('category.subtitle', { count: rows.length }) }}</p>
            </div>
            <button v-if="!auth.isReadOnly" @click="openCreate" class="btn btn-accent"><Icon name="plus" :size="16" />{{ t('common.create') }}</button>
        </div>

        <!-- Bulk-action bar for the current selection -->
        <div v-if="!auth.isReadOnly && selected.size" class="bulk-bar">
            <span class="bulk-count">{{ t('category.selected_count', { n: selected.size }) }}</span>
            <button class="btn btn-ghost btn-sm" @click="clearSelection">{{ t('category.clear_selection') }}</button>
            <button class="btn btn-danger btn-sm" :disabled="bulkDeleting" @click="bulkRemove">
                <Icon v-if="bulkDeleting" name="loading" :size="15" class="animate-spin" />
                <Icon v-else name="trash" :size="15" />
                {{ t('category.delete_selected') }}
            </button>
        </div>

        <div class="card overflow-hidden">
            <ListSkeleton v-if="loading" />
            <div v-else-if="!rows.length" class="p-8 text-center" style="color:var(--muted)">{{ t('common.none') }}</div>
            <template v-else>
                <label v-if="!auth.isReadOnly" class="flex items-center gap-3 px-5 py-2.5 text-xs" style="color:var(--muted);border-bottom:1px solid var(--line)">
                    <input type="checkbox" class="row-check" :checked="allSelected" @change="toggleAll" />
                    <span>{{ t('common.select_all') }}</span>
                </label>
            <ul>
                <li v-for="(c, i) in rows" :key="c.id"
                    class="flex items-center gap-3 px-5 py-3 border-t first:border-t-0"
                    :class="{ 'row-selected': selected.has(c.id), 'row-dragging': dragIndex === i, 'row-drop': overIndex === i && dragIndex !== null && dragIndex !== i }"
                    style="border-color:var(--line)"
                    :draggable="!auth.isReadOnly && dragReady"
                    @dragstart="onDragStart(i, $event)"
                    @dragover.prevent="onDragOver(i)"
                    @drop.prevent="onDrop(i)"
                    @dragend="resetDrag">
                    <input v-if="!auth.isReadOnly" type="checkbox" class="row-check" :checked="selected.has(c.id)" :aria-label="categoryName(c)" @change="toggleSelect(c.id)" />
                    <button v-if="!auth.isReadOnly" class="drag-handle" :title="t('category.drag_to_reorder')" :aria-label="t('category.drag_to_reorder')"
                        @mousedown="dragReady = true" @touchstart.passive="dragReady = true" @mouseup="dragReady = false"><Icon name="grip" :size="16" fill /></button>
                    <span class="row-num">{{ i + 1 }}</span>
                    <div v-if="!auth.isReadOnly" class="flex flex-col">
                        <button @click="move(i, -1)" :disabled="i === 0" class="icon-btn" style="width:24px;height:18px"><Icon name="chevronUp" :size="15" /></button>
                        <button @click="move(i, 1)" :disabled="i === rows.length - 1" class="icon-btn" style="width:24px;height:18px"><Icon name="chevronDown" :size="15" /></button>
                    </div>
                    <img v-if="c.image_url" :src="c.image_url" class="h-11 w-11 rounded-lg object-cover" />
                    <div v-else class="h-11 w-11 rounded-lg grid place-items-center flex-shrink-0" style="background:var(--accent-soft);color:var(--accent)"><Icon name="categories" :size="18" /></div>
                    <div class="flex-1 min-w-0 cat-info">
                        <div class="font-medium" style="color:var(--ink)">{{ categoryName(c) }}</div>
                        <div v-if="categoryAltName(c)" class="text-xs cat-alt" style="color:var(--muted)" :dir="locale === 'ar' ? 'ltr' : 'rtl'">{{ categoryAltName(c) }}</div>
                        <div class="text-xs" style="color:var(--muted)">{{ t('admin.item_count', { count: c.items_count }) }}</div>
                    </div>
                    <span v-if="c.availability_hours" class="badge badge-gray">{{ t('category.timed_badge') }}</span>
                    <StatusBadge :value="c.is_active" :label="c.is_active ? t('common.active') : t('common.inactive')" />
                    <button v-if="!auth.isReadOnly" class="switch" :class="{ on: c.is_active }" @click="toggle(c)"></button>
                    <button v-if="!auth.isReadOnly" @click="openEdit(c)" class="icon-btn" :title="t('common.edit')"><Icon name="edit" :size="17" /></button>
                    <button v-if="!auth.isReadOnly" @click="remove(c)" class="icon-btn icon-btn-danger" :title="t('common.delete')"><Icon name="trash" :size="17" /></button>
                </li>
            </ul>
            </template>
        </div>

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
                        <BusinessHoursEditor v-model="form.availability_hours" :disabled="auth.isReadOnly" />
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
.row-check {
    width: 16px;
    height: 16px;
    accent-color: var(--accent);
    cursor: pointer;
    flex: none;
}
/* Serial number reflecting each category's display order. */
.row-num {
    flex: none;
    min-width: 22px;
    text-align: center;
    font-size: 13px;
    font-weight: 600;
    color: var(--muted);
    font-variant-numeric: tabular-nums;
}
li.row-selected { background: var(--accent-soft); }

/* Category name / English name / item count each on their own line, all
   aligned to the active reading edge. The count sits on a separate row from
   the (opposite-direction) English name so RTL no longer jams them together. */
[dir="rtl"] .cat-info, [dir="rtl"] .cat-alt { text-align: right; }
[dir="ltr"] .cat-info, [dir="ltr"] .cat-alt { text-align: left; }

/* Drag-and-drop reordering */
.drag-handle {
    flex: none;
    display: grid;
    place-items: center;
    width: 24px;
    height: 28px;
    border-radius: 7px;
    color: var(--muted);
    cursor: grab;
    touch-action: none;
}
.drag-handle:hover { color: var(--ink); background: var(--accent-soft); }
.drag-handle:active { cursor: grabbing; }
li.row-dragging { opacity: .5; }
li.row-drop { box-shadow: inset 0 2px 0 0 var(--accent); }

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
</style>
