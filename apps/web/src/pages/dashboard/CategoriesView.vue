<script setup>
import { ref, reactive, computed, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import { withMinDuration } from '../../lib/minLoading.js'
import { useAuth } from '@xorder/api-client/auth.js'
import { pickLocalized } from '@xorder/ui/localize.js'
import Modal from '@xorder/ui/Modal.vue'
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
const form = reactive({ name_en: '', name_ar: '', description_en: '', description_ar: '', image_url: '', is_active: true })

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
    Object.assign(form, { name_en: '', name_ar: '', description_en: '', description_ar: '', image_url: '', is_active: true })
    showModal.value = true
}
function openEdit(c) {
    editing.value = c; errors.value = {}
    Object.assign(form, { name_en: c.name_en || '', name_ar: c.name_ar || '',
        description_en: c.description_en || '', description_ar: c.description_ar || '',
        image_url: c.image_url || '', is_active: c.is_active })
    showModal.value = true
}
async function save() {
    if (saving.value) return // guard against double-submit (double-click)
    saving.value = true
    errors.value = {}
    try {
        await ensureCsrf()
        if (editing.value) await api.put(`api/dashboard/categories/${editing.value.id}`, form)
        else await api.post('api/dashboard/categories', form)
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
async function move(index, dir) {
    const target = index + dir
    if (target < 0 || target >= rows.value.length) return
    const a = rows.value[index], b = rows.value[target]
    await ensureCsrf()
    await api.patch('api/dashboard/categories/reorder', {
        order: [{ id: a.id, display_order: target }, { id: b.id, display_order: index }],
    })
    await load()
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
                <li v-for="(c, i) in rows" :key="c.id" class="flex items-center gap-3 px-5 py-3 border-t first:border-t-0" :class="{ 'row-selected': selected.has(c.id) }" style="border-color:var(--line)">
                    <input v-if="!auth.isReadOnly" type="checkbox" class="row-check" :checked="selected.has(c.id)" :aria-label="categoryName(c)" @change="toggleSelect(c.id)" />
                    <span class="row-num">{{ i + 1 }}</span>
                    <div v-if="!auth.isReadOnly" class="flex flex-col">
                        <button @click="move(i, -1)" :disabled="i === 0" class="icon-btn" style="width:24px;height:18px"><Icon name="chevronUp" :size="15" /></button>
                        <button @click="move(i, 1)" :disabled="i === rows.length - 1" class="icon-btn" style="width:24px;height:18px"><Icon name="chevronDown" :size="15" /></button>
                    </div>
                    <img v-if="c.image_url" :src="c.image_url" class="h-11 w-11 rounded-lg object-cover" />
                    <div v-else class="h-11 w-11 rounded-lg grid place-items-center flex-shrink-0" style="background:var(--accent-soft);color:var(--accent)"><Icon name="categories" :size="18" /></div>
                    <div class="flex-1 min-w-0">
                        <div class="font-medium" style="color:var(--ink)">{{ categoryName(c) }}</div>
                        <div class="text-xs" style="color:var(--muted)">
                            <span v-if="categoryAltName(c)" :dir="locale === 'ar' ? 'ltr' : 'rtl'">{{ categoryAltName(c) }} · </span>{{ t('admin.item_count', { count: c.items_count }) }}
                        </div>
                    </div>
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
