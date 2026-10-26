<script setup>
import { ref, reactive, computed, onMounted, watch, nextTick } from 'vue'
import { useI18n } from 'vue-i18n'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import { withMinDuration } from '../../lib/minLoading.js'
import { pickLocalized } from '@xorder/ui/localize.js'
import Dialog from '@xorder/ui/Dialog.vue'
import ListSkeleton from '@xorder/ui/ListSkeleton.vue'
import ErrorState from '@xorder/ui/ErrorState.vue'
import StatusBadge from '@xorder/ui/StatusBadge.vue'
import FormError from '@xorder/ui/FormError.vue'
import Icon from '@xorder/ui/Icon.vue'
import { confirm } from '@xorder/ui/confirm.js'
import { alert } from '@xorder/ui/alert.js'
import { useAuth } from '@xorder/api-client/auth.js'
import { useCaps } from '../../lib/useCaps.js'

const { t, locale } = useI18n()
const auth = useAuth()
// Per-action gates — a tables.view-only role sees the list and nothing else.
const { canCreate, canUpdate, canDelete } = useCaps('tables')
const rows = ref([])
const areas = ref([])
const loading = ref(true)
// Why the list is not showing, when it is not: a refused request leaves a
// sentence rather than a skeleton. 'plan' is the feature gate — table
// management is not in this restaurant's plan, which the sidebar already
// hides but a typed URL still reaches (16 Oct 2026).
const failed = ref(null)
const saving = ref(false)
const showModal = ref(false)
const editing = ref(null)
// Create-only: add many sequentially-numbered tables at once instead of
// reopening the dialog per table.
const bulkMode = ref(false)
const errors = ref({})
const filters = reactive({ dining_area_id: '', status: '', search: '' })

const blank = () => ({
    dining_area_id: '', label: '', seats_count: null, notes: '', is_active: true,
    // Bulk create: one entry per name field. Enter appends a field, Save creates
    // all the non-blank names at once.
    labels: [''],
})
const form = reactive(blank())

const activeAreas = computed(() => areas.value.filter(a => a.is_active))

// The list of name fields in bulk mode. `labelList` is the wrapping element so a
// freshly-added field can be focused by its DOM position after render.
const labelList = ref(null)
const bulkCount = computed(() =>
    form.labels.map(l => (l || '').trim()).filter(Boolean).length)

// --- Generate a numbered run (XORD-006) --------------------------------------
// "Table 1" … "Table 10" from a prefix, a start number and a quantity. It only
// fills the list below: the owner sees every name before anything is saved and
// can still edit or drop any of them. The server's 100-name ceiling is the real
// limit; this is the same number so the form refuses before the request does.
const MAX_GENERATED = 100
const gen = reactive({ prefix: '', start: 1, count: 10 })
const genValid = computed(() => {
    const start = Number(gen.start), count = Number(gen.count)
    return Number.isInteger(start) && start >= 0 && Number.isInteger(count) && count >= 1 && count <= MAX_GENERATED
})
const genNames = computed(() => {
    if (!genValid.value) return []
    const start = Number(gen.start)
    return Array.from({ length: Number(gen.count) }, (_, i) => `${gen.prefix}${start + i}`.trim())
})
function applyGenerated() {
    if (!genValid.value) return
    form.labels = [...genNames.value]
}
// Names repeated inside the list: the server would quietly collapse them, which
// reads as "I asked for ten and got nine". Say so before saving instead.
const repeatedLabels = computed(() => {
    const seen = new Set(), repeated = new Set()
    for (const raw of form.labels) {
        const name = (raw || '').trim()
        if (!name) continue
        if (seen.has(name)) repeated.add(name)
        seen.add(name)
    }
    return [...repeated]
})

async function addLabelField(afterIndex) {
    form.labels.splice(afterIndex + 1, 0, '')
    await nextTick()
    labelList.value?.querySelectorAll('input.tbl-label-input')?.[afterIndex + 1]?.focus()
}
function removeLabelField(index) {
    if (form.labels.length > 1) form.labels.splice(index, 1)
}

async function loadAreas() {
    const { data } = await api.get('api/dashboard/dining-areas')
    areas.value = data.data
}
async function loadTables() {
    loading.value = true
    failed.value = null
    const params = {}
    if (filters.dining_area_id) params.dining_area_id = filters.dining_area_id
    if (filters.status) params.status = filters.status
    if (filters.search) params.search = filters.search
    try {
        const { data } = await withMinDuration(api.get('api/dashboard/tables', { params }))
        rows.value = data.data
    } catch (err) {
        failed.value = err?.response?.status === 403 ? 'plan' : 'error'
    } finally {
        loading.value = false
    }
}
async function load() {
    try { await loadAreas() } catch (err) {
        // The areas call is the first past the feature gate; its refusal is
        // the page's, and the tables call would only say it again.
        failed.value = err?.response?.status === 403 ? 'plan' : 'error'
        loading.value = false
        return
    }
    await loadTables()
}
onMounted(load)
watch(() => [filters.dining_area_id, filters.status], loadTables)

let searchTimer
watch(() => filters.search, () => { clearTimeout(searchTimer); searchTimer = setTimeout(loadTables, 300) })

function openCreate() {
    editing.value = null; bulkMode.value = false; errors.value = {}
    gen.prefix = t('tbl.gen_default_prefix'); gen.start = 1; gen.count = 10
    Object.assign(form, blank(), {
        dining_area_id: activeAreas.value[0]?.id || '',
    })
    showModal.value = true
}
function openEdit(tbl) {
    editing.value = tbl; errors.value = {}
    Object.assign(form, blank(), {
        dining_area_id: tbl.dining_area_id, label: tbl.label,
        seats_count: tbl.seats_count, notes: tbl.notes || '', is_active: tbl.is_active,
    })
    showModal.value = true
}
async function save() {
    if (saving.value) return
    saving.value = true; errors.value = {}
    try {
        await ensureCsrf()
        if (editing.value) {
            await api.put(`api/dashboard/tables/${editing.value.id}`, form)
        } else if (bulkMode.value) {
            await api.post('api/dashboard/tables/bulk', {
                dining_area_id: form.dining_area_id,
                labels: form.labels.map(l => (l || '').trim()).filter(Boolean),
                is_active: form.is_active,
            })
        } else {
            await api.post('api/dashboard/tables', form)
        }
        showModal.value = false
        await loadTables()
    } catch (err) { errors.value = err.response?.data?.errors || {} }
    finally { saving.value = false }
}
async function toggleActive(tbl) {
    await ensureCsrf()
    await api.patch(`api/dashboard/tables/${tbl.id}/status`, { is_active: !tbl.is_active })
    tbl.is_active = !tbl.is_active
}
async function remove(tbl) {
    const ok = await confirm({
        title: t('common.delete'), message: t('common.confirm_delete'),
        confirmText: t('common.delete'), cancelText: t('common.cancel'), danger: true,
    })
    if (!ok) return
    try {
        await ensureCsrf()
        await api.delete(`api/dashboard/tables/${tbl.id}`)
        await loadTables()
    } catch (err) { alert(err.response?.data?.message || t('common.delete_failed')) }
}

// ---- Multi-select / bulk delete ----
const selected = ref(new Set())
function toggleSelect(id) {
    if (selected.value.has(id)) selected.value.delete(id)
    else selected.value.add(id)
}
function clearSelection() { selected.value.clear() }
const allSelected = computed(() =>
    rows.value.length > 0 && rows.value.every(r => selected.value.has(r.id)))
const someSelected = computed(() =>
    rows.value.some(r => selected.value.has(r.id)) && !allSelected.value)
function toggleAll() {
    if (allSelected.value) rows.value.forEach(r => selected.value.delete(r.id))
    else rows.value.forEach(r => selected.value.add(r.id))
}
const bulkDeleting = ref(false)
async function bulkRemove() {
    const ids = [...selected.value]
    if (!ids.length || bulkDeleting.value) return
    const ok = await confirm({
        title: t('common.delete'), message: t('tbl.confirm_delete_selected', { n: ids.length }),
        confirmText: t('common.delete'), cancelText: t('common.cancel'), danger: true,
    })
    if (!ok) return
    bulkDeleting.value = true
    try {
        await ensureCsrf()
        const { data } = await api.delete('api/dashboard/tables/bulk', { data: { ids } })
        clearSelection()
        await loadTables()
        if (data?.message) alert({ title: t('common.success'), message: data.message, variant: 'success' })
    } catch (err) { alert(err.response?.data?.message || t('common.delete_failed')) }
    finally { bulkDeleting.value = false }
}

// Download the QR PNGs for a set of tables as one ZIP. `scope` is only there to
// tell the two entry points apart so the spinner lands on the button that was
// actually clicked.
const downloading = ref('')
const bulkDownloading = computed(() => downloading.value === 'selected')
const allDownloading = computed(() => downloading.value === 'all')
async function downloadQrZip(ids, scope) {
    if (!ids.length || downloading.value) return
    downloading.value = scope
    try {
        const res = await api.post('api/dashboard/tables/qr/download-bulk', { ids }, { responseType: 'blob' })
        const blobUrl = URL.createObjectURL(res.data)
        const a = document.createElement('a')
        a.href = blobUrl; a.download = 'qr-tables.zip'; a.click()
        URL.revokeObjectURL(blobUrl)
    } catch (err) { alert(err.response?.data?.message || t('tbl.download_failed')) }
    finally { downloading.value = '' }
}
const bulkDownloadQr = () => downloadQrZip([...selected.value], 'selected')
// One click, no ticking required: everything currently listed (so the area /
// status / search filters above decide what lands in the ZIP).
const downloadAllQr = () => downloadQrZip(rows.value.map(r => r.id), 'all')

// ---- QR modal ----
const qrModal = ref(null) // { table, svg, url }
const qrLoading = ref(false)
async function openQr(tbl) {
    qrModal.value = { table: tbl, svg: '', url: '' }
    qrLoading.value = true
    const { data } = await api.get(`api/dashboard/tables/${tbl.id}/qr`)
    qrModal.value = { table: tbl, svg: data.data.svg, url: data.data.url }
    qrLoading.value = false
}
async function downloadQr() {
    const tbl = qrModal.value.table
    const res = await api.get(`api/dashboard/tables/${tbl.id}/qr/download`, { responseType: 'blob' })
    const blobUrl = URL.createObjectURL(res.data)
    const a = document.createElement('a')
    a.href = blobUrl; a.download = `qr-table-${tbl.public_token}.png`; a.click()
    URL.revokeObjectURL(blobUrl)
}
async function regenerateQr() {
    const ok = await confirm({
        title: t('tbl.qr_regenerate'), message: t('tbl.qr_regen_confirm'),
        confirmText: t('tbl.qr_regenerate'), cancelText: t('common.cancel'), danger: true,
    })
    if (!ok) return
    await ensureCsrf()
    const { data } = await api.post(`api/dashboard/tables/${qrModal.value.table.id}/qr/regenerate`)
    const updated = data.data
    const row = rows.value.find(r => r.id === updated.id)
    if (row) Object.assign(row, updated)
    await openQr(updated)
}

const areaName = (a) => pickLocalized(a, 'name', locale.value)
const areaLabel = (id) => { const a = areas.value.find(x => x.id === id); return a ? areaName(a) : '—' }
</script>

<template>
    <div class="space-y-5">
        <!-- Header: title + one-line subtitle, primary actions at the end -->
        <div class="flex flex-wrap items-start justify-between gap-3">
            <div class="min-w-0">
                <h1 class="page-title">{{ t('tbl.tables_title') }}</h1>
                <p class="page-sub" style="color:var(--body)">{{ t('tbl.tables_sub', { count: rows.length }) }}</p>
            </div>
            <div class="flex flex-wrap items-center gap-2">
                <button v-if="rows.length" class="btn btn-ghost act-btn" :disabled="!!downloading" @click="downloadAllQr">
                    <Icon v-if="allDownloading" name="loading" :size="16" class="animate-spin" />
                    <Icon v-else name="download" :size="16" />
                    {{ t('tbl.download_all', { n: rows.length }) }}
                </button>
                <button v-if="canCreate" @click="openCreate" :disabled="!activeAreas.length" class="btn btn-accent act-btn"><Icon name="plus" :size="16" />{{ t('common.create') }}</button>
            </div>
        </div>

        <!-- Tables are optional (counter cafes, food trucks and cloud kitchens have none).
             This is guidance, not a warning. -->
        <div v-if="!failed && !loading && !areas.length" class="note" role="note">
            <span class="note-ico" aria-hidden="true"><Icon name="info" :size="18" /></span>
            <div class="min-w-0">
                <p class="note-title">{{ t('tbl.no_area_first') }}</p>
                <p class="note-text">{{ t('tbl.optional_note') }}</p>
            </div>
        </div>

        <!-- Filters -->
        <div class="filters">
            <select v-model="filters.dining_area_id" class="input filter-sel" :aria-label="t('tbl.area')">
                <option value="">{{ t('tbl.all_areas') }}</option>
                <option v-for="a in areas" :key="a.id" :value="a.id">{{ areaName(a) }}</option>
            </select>
            <select v-model="filters.status" class="input filter-sel" :aria-label="t('common.status')">
                <option value="">{{ t('tbl.all_status') }}</option>
                <option value="active">{{ t('common.active') }}</option>
                <option value="inactive">{{ t('common.inactive') }}</option>
            </select>
            <input v-model="filters.search" class="input filter-search" :placeholder="t('tbl.search_tables')" :aria-label="t('tbl.search_tables')" />
        </div>

        <!-- Bulk action bar: appears once one or more rows are ticked. -->
        <div v-if="canDelete && selected.size" class="bulk-bar">
            <span class="bulk-count">{{ t('tbl.selected_count', { n: selected.size }) }}</span>
            <button class="btn btn-ghost btn-sm act-btn" @click="clearSelection">{{ t('tbl.clear_selection') }}</button>
            <button class="btn btn-accent btn-sm act-btn" :disabled="!!downloading" @click="bulkDownloadQr">
                <Icon v-if="bulkDownloading" name="loading" :size="15" class="animate-spin" />
                <Icon v-else name="download" :size="15" />
                {{ t('tbl.download_selected') }}
            </button>
            <button class="btn btn-danger btn-sm act-btn" :disabled="bulkDeleting" @click="bulkRemove">
                <Icon v-if="bulkDeleting" name="loading" :size="15" class="animate-spin" />
                <Icon v-else name="trash" :size="15" />
                {{ t('tbl.delete_selected') }}
            </button>
        </div>

        <div class="card overflow-hidden">
            <ListSkeleton v-if="loading" />
            <div v-else-if="failed === 'plan'" class="empty">
                <span class="empty-ico" aria-hidden="true"><Icon name="table" :size="22" /></span>
                <p class="empty-text">{{ t('tbl.not_in_plan') }}</p>
            </div>
            <ErrorState v-else-if="failed" @retry="load" />
            <div v-else-if="!rows.length" class="empty">
                <span class="empty-ico" aria-hidden="true"><Icon name="table" :size="22" /></span>
                <p class="empty-text">{{ t('tbl.none_tables') }}</p>
                <p class="empty-sub">{{ t('tbl.optional_note') }}</p>
                <button v-if="canCreate && activeAreas.length" class="btn btn-accent act-btn" @click="openCreate"><Icon name="plus" :size="16" />{{ t('common.create') }}</button>
            </div>
            <template v-else>
                <!-- Select-all header (only when the user can delete). -->
                <div v-if="canDelete" class="tbl-head">
                    <input type="checkbox" class="row-check" :checked="allSelected"
                        :indeterminate.prop="someSelected" :aria-label="t('tbl.select_all')" @change="toggleAll" />
                    <span class="text-sm" style="color:var(--body)">{{ t('tbl.select_all') }}</span>
                </div>
                <ul>
                    <li v-for="(tbl, i) in rows" :key="tbl.id" class="row" :class="{ 'row-selected': selected.has(tbl.id) }">
                        <div class="row-main">
                            <input v-if="canDelete" type="checkbox" class="row-check" :checked="selected.has(tbl.id)"
                                :aria-label="tbl.label" @change="toggleSelect(tbl.id)" />
                            <span class="tbl-num">{{ i + 1 }}</span>
                            <div class="row-ico" aria-hidden="true"><Icon name="table" :size="22" /></div>
                            <div class="flex-1 min-w-0">
                                <div class="row-name truncate">{{ tbl.label }}</div>
                                <div class="row-sub truncate">{{ areaLabel(tbl.dining_area_id) }}</div>
                            </div>
                        </div>
                        <div class="row-side">
                            <StatusBadge :value="tbl.is_active" :label="tbl.is_active ? t('common.active') : t('common.inactive')" />
                            <button v-if="canUpdate" type="button" class="switch" :class="{ on: tbl.is_active }" role="switch"
                                :aria-checked="tbl.is_active" :aria-label="tbl.is_active ? t('common.active') : t('common.inactive')" @click="toggleActive(tbl)"></button>
                            <button @click="openQr(tbl)" class="icon-btn" :title="t('tbl.qr')" :aria-label="t('tbl.qr')"><Icon name="qr" :size="17" /></button>
                            <button v-if="canUpdate" @click="openEdit(tbl)" class="icon-btn" :title="t('common.edit')" :aria-label="t('common.edit')"><Icon name="edit" :size="17" /></button>
                            <button v-if="canDelete" @click="remove(tbl)" class="icon-btn icon-btn-danger" :title="t('common.delete')" :aria-label="t('common.delete')"><Icon name="trash" :size="17" /></button>
                        </div>
                    </li>
                </ul>
            </template>
        </div>

        <!-- Create / edit modal -->
        <Dialog v-if="showModal" :title="editing ? t('common.edit') : t('tbl.tables_title')" @close="showModal = false">
            <div class="space-y-4">
                <!-- Create only: toggle to add a numbered batch in one save. -->
                <label v-if="!editing" class="toggle-line">
                    <button type="button" class="switch" :class="{ on: bulkMode }" role="switch" :aria-checked="bulkMode" @click="bulkMode = !bulkMode"></button>
                    {{ t('tbl.add_multiple') }}
                </label>
                <label class="block"><span class="label">{{ t('tbl.area') }}</span>
                    <select v-model="form.dining_area_id" class="input">
                        <option v-for="a in activeAreas" :key="a.id" :value="a.id">{{ areaName(a) }}</option>
                    </select>
                    <FormError :errors="errors" field="dining_area_id" /></label>

                <!-- Bulk create: one field per table name; Enter adds another. -->
                <template v-if="bulkMode && !editing">
                    <div class="gen-box" data-test="gen-box">
                        <span class="label">{{ t('tbl.gen_title') }}</span>
                        <div class="gen-row">
                            <label class="block"><span class="label">{{ t('tbl.gen_prefix') }}</span>
                                <input v-model="gen.prefix" class="input" :placeholder="t('tbl.gen_default_prefix')" data-test="gen-prefix" /></label>
                            <label class="block"><span class="label">{{ t('tbl.gen_start') }}</span>
                                <input v-model.number="gen.start" type="number" min="0" step="1" class="input" dir="ltr" data-test="gen-start" /></label>
                            <label class="block"><span class="label">{{ t('tbl.gen_count') }}</span>
                                <input v-model.number="gen.count" type="number" min="1" :max="MAX_GENERATED" step="1" class="input" dir="ltr" data-test="gen-count" /></label>
                        </div>
                        <p v-if="!genValid" class="text-sm" style="color:var(--danger, #b42318)" data-test="gen-invalid">{{ t('tbl.gen_invalid', { max: MAX_GENERATED }) }}</p>
                        <p v-else class="text-sm" style="color:var(--body)" data-test="gen-preview">{{ t('tbl.gen_preview', { first: genNames[0], last: genNames[genNames.length - 1] }) }}</p>
                        <button type="button" class="btn btn-ghost btn-sm" :disabled="!genValid" data-test="gen-apply" @click="applyGenerated">{{ t('tbl.gen_apply') }}</button>
                    </div>
                    <div class="block">
                        <span class="label">{{ t('tbl.table_names') }}</span>
                        <div ref="labelList" class="space-y-2 mt-1.5">
                            <div v-for="(lbl, i) in form.labels" :key="i" class="flex items-center gap-2">
                                <span class="tbl-num">{{ i + 1 }}</span>
                                <input v-model="form.labels[i]" class="input tbl-label-input flex-1" style="margin-top:0"
                                    :placeholder="t('tbl.label')" @keydown.enter.prevent="addLabelField(i)" />
                                <button v-if="form.labels.length > 1" type="button" class="icon-btn icon-btn-danger"
                                    :title="t('common.delete')" :aria-label="t('common.delete')" @click="removeLabelField(i)"><Icon name="trash" :size="16" /></button>
                            </div>
                        </div>
                        <button type="button" class="btn btn-ghost btn-sm mt-2" @click="addLabelField(form.labels.length - 1)">
                            <Icon name="plus" :size="15" />{{ t('tbl.add_name') }}
                        </button>
                        <FormError :errors="errors" field="labels" />
                        <p v-if="repeatedLabels.length" class="text-sm mt-1" style="color:var(--danger, #b42318)" data-test="repeated">{{ t('tbl.gen_duplicates', { names: repeatedLabels.join(', ') }) }}</p>
                        <p class="text-sm mt-1" style="color:var(--body)">{{ t('tbl.enter_hint') }}</p>
                    </div>
                </template>

                <!-- Single create / edit. -->
                <template v-else>
                    <label class="block"><span class="label">{{ t('tbl.label') }}</span>
                        <input v-model="form.label" class="input" />
                        <FormError :errors="errors" field="label" /></label>
                    <label class="block"><span class="label">{{ t('tbl.notes') }}</span>
                        <textarea v-model="form.notes" rows="2" class="input"></textarea></label>
                </template>
                <label class="toggle-line">
                    <button type="button" class="switch" :class="{ on: form.is_active }" role="switch" :aria-checked="form.is_active" @click="form.is_active = !form.is_active"></button>
                    {{ t('common.active') }}
                </label>
                <div class="flex flex-wrap justify-end gap-2 pt-3 form-actions">
                    <button @click="showModal = false" :disabled="saving" class="btn btn-ghost act-btn">{{ t('common.cancel') }}</button>
                    <button @click="save" :disabled="saving || (bulkMode && !editing && !bulkCount)" class="btn btn-accent act-btn">
                        <Icon v-if="saving" name="loading" :size="16" class="animate-spin" />
                        {{ saving ? t('common.saving') : (bulkMode && !editing && bulkCount ? t('tbl.save_count', { n: bulkCount }) : t('common.save')) }}
                    </button>
                </div>
            </div>
        </Dialog>

        <!-- QR modal -->
        <Dialog v-if="qrModal" :title="`${t('tbl.table')} : ${qrModal.table.label}`" @close="qrModal = null">
            <div class="space-y-4 text-center">
                <div v-if="qrLoading" class="py-10" style="color:var(--body)">…</div>
                <div v-else class="mx-auto qr-box" v-html="qrModal.svg"></div>
                <p class="text-xs break-all" style="color:var(--body)" dir="ltr">{{ qrModal.url }}</p>
                <p class="text-sm" style="color:var(--body)">{{ t('tbl.scan_hint') }}</p>
                <div class="flex flex-wrap justify-center gap-2 pt-1">
                    <button v-if="canUpdate" @click="regenerateQr" class="btn btn-ghost act-btn">{{ t('tbl.qr_regenerate') }}</button>
                    <button @click="downloadQr" class="btn btn-accent act-btn"><Icon name="download" :size="16" />{{ t('tbl.qr_download') }}</button>
                </div>
            </div>
        </Dialog>
    </div>
</template>

<style scoped>
/* Colours come from the shared theme variables only. */

/* The QR SVG is generated at a fixed pixel size; make it fit its box so it
   never overflows onto the URL/hint text below. */
.qr-box { width: 15rem; height: 15rem; max-width: 100%; }
.qr-box :deep(svg) { width: 100%; height: 100%; display: block; }

/* Guidance note (optional-feature hint), deliberately calm: not an error. */
.note { display: flex; align-items: flex-start; gap: 12px; padding: 14px 16px; border-radius: 12px;
    background: var(--accent-soft); border: 1px solid var(--line); }
.note-ico { width: 32px; height: 32px; border-radius: 9px; display: grid; place-items: center; flex: none;
    background: var(--card); color: var(--p-primary-700); }
.note-title { font-size: 14.5px; font-weight: 600; color: var(--ink); }
.note-text { font-size: 14px; color: var(--body); margin-top: 2px; line-height: 1.55; }

/* Filters */
.filters { display: flex; flex-wrap: wrap; gap: 10px; }
.filters .input { margin-top: 0; min-height: 44px; }
.filter-sel { flex: 1 1 150px; max-width: 14rem; }
.filter-search { flex: 2 1 200px; max-width: 18rem; }

/* Rows */
.tbl-head { display: flex; align-items: center; gap: 12px; padding: 10px 20px; border-bottom: 1px solid var(--line); background: var(--page); }
.row { display: flex; flex-wrap: wrap; align-items: center; gap: 8px 12px; padding: 10px 20px; min-height: 64px;
    border-top: 1px solid var(--line); transition: background .15s; }
.row:first-child { border-top: 0; }
.row:hover { background: var(--page); }
.row-main { display: flex; align-items: center; gap: 12px; flex: 1 1 220px; min-width: 0; }
.row-side { display: flex; align-items: center; gap: 8px; margin-inline-start: auto; }
.row-ico { width: 44px; height: 44px; border-radius: 10px; display: grid; place-items: center; flex: none;
    background: var(--accent-soft); color: var(--p-primary-700); }
.row-name { font-size: 15.5px; font-weight: 600; color: var(--ink); }
.row-sub { font-size: 13.5px; color: var(--body); margin-top: 1px; }
.tbl-num { flex: none; width: 1.5rem; text-align: center; font-size: 13px; font-variant-numeric: tabular-nums; color: var(--body); }
.row-check { flex: none; width: 18px; height: 18px; accent-color: var(--accent); cursor: pointer; }
.row-selected, .row-selected:hover { background: var(--accent-soft); }

/* Bulk action bar surfaced above the list for the current selection. */
.gen-box { display: grid; gap: 8px; padding: 12px; border: 1px solid var(--line, #e5e7eb); border-radius: 12px; }
.gen-row { display: grid; grid-template-columns: 2fr 1fr 1fr; gap: 10px; }
@media (max-width: 480px) { .gen-row { grid-template-columns: 1fr; } }
.bulk-bar { display: flex; flex-wrap: wrap; align-items: center; gap: 10px; padding: 10px 14px; border-radius: 12px;
    background: var(--accent-soft); border: 1px solid var(--accent); }
.bulk-count { font-weight: 700; font-size: 14.5px; color: var(--p-primary-800); margin-inline-end: auto; }
.btn-danger { background: var(--red); color: #fff; border-color: var(--red); }
.btn-danger:hover:not(:disabled) { filter: brightness(.94); }
.btn-danger:disabled { opacity: .6; cursor: default; }

/* Empty / plan-gated state: friendly, centred, not an error */
.empty { display: flex; flex-direction: column; align-items: center; gap: 8px; padding: 40px 20px; text-align: center; }
.empty-ico { width: 48px; height: 48px; border-radius: 14px; display: grid; place-items: center;
    background: var(--accent-soft); color: var(--p-primary-700); }
.empty-text { font-size: 15.5px; font-weight: 600; color: var(--ink); }
.empty-sub { font-size: 14px; color: var(--body); max-width: 440px; line-height: 1.55; }
.empty .btn { margin-top: 6px; }

.toggle-line { display: flex; align-items: center; gap: 10px; font-size: 14.5px; color: var(--body); min-height: 44px; }
.form-actions { border-top: 1px solid var(--line); }

@media (max-width: 640px) {
    .row { padding-inline: 14px; }
    .row-side { width: 100%; justify-content: flex-end; }
    .row-side .icon-btn { width: 44px; height: 44px; }
    .act-btn { min-height: 44px; justify-content: center; }
    .form-actions .act-btn { flex: 1 1 auto; }
    .filter-sel, .filter-search { max-width: none; flex-basis: 100%; }
}
</style>
