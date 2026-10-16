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
        <div class="flex items-start justify-between gap-3">
            <div>
                <h1 class="page-title">{{ t('tbl.tables_title') }}</h1>
                <p class="page-sub">{{ t('tbl.tables_sub', { count: rows.length }) }}</p>
            </div>
            <div class="flex items-center gap-2">
                <button v-if="rows.length" class="btn btn-ghost" :disabled="!!downloading" @click="downloadAllQr">
                    <Icon v-if="allDownloading" name="loading" :size="16" class="animate-spin" />
                    <Icon v-else name="download" :size="16" />
                    {{ t('tbl.download_all', { n: rows.length }) }}
                </button>
                <button v-if="canCreate" @click="openCreate" :disabled="!activeAreas.length" class="btn btn-accent"><Icon name="plus" :size="16" />{{ t('common.create') }}</button>
            </div>
        </div>

        <p v-if="!failed && !loading && !areas.length" class="card p-4 text-sm" style="color:var(--muted)">{{ t('tbl.no_area_first') }}</p>

        <div class="flex flex-wrap gap-2">
            <select v-model="filters.dining_area_id" class="input" style="max-width:14rem">
                <option value="">{{ t('tbl.all_areas') }}</option>
                <option v-for="a in areas" :key="a.id" :value="a.id">{{ areaName(a) }}</option>
            </select>
            <select v-model="filters.status" class="input" style="max-width:11rem">
                <option value="">{{ t('tbl.all_status') }}</option>
                <option value="active">{{ t('common.active') }}</option>
                <option value="inactive">{{ t('common.inactive') }}</option>
            </select>
            <input v-model="filters.search" class="input" style="max-width:14rem" :placeholder="t('tbl.search_tables')" />
        </div>

        <!-- Bulk action bar — appears once one or more rows are ticked. -->
        <div v-if="canDelete && selected.size" class="bulk-bar">
            <span class="bulk-count">{{ t('tbl.selected_count', { n: selected.size }) }}</span>
            <button class="btn btn-ghost btn-sm" @click="clearSelection">{{ t('tbl.clear_selection') }}</button>
            <button class="btn btn-accent btn-sm" :disabled="!!downloading" @click="bulkDownloadQr">
                <Icon v-if="bulkDownloading" name="loading" :size="15" class="animate-spin" />
                <Icon v-else name="download" :size="15" />
                {{ t('tbl.download_selected') }}
            </button>
            <button class="btn btn-danger btn-sm" :disabled="bulkDeleting" @click="bulkRemove">
                <Icon v-if="bulkDeleting" name="loading" :size="15" class="animate-spin" />
                <Icon v-else name="trash" :size="15" />
                {{ t('tbl.delete_selected') }}
            </button>
        </div>

        <div class="card overflow-hidden">
            <ListSkeleton v-if="loading" />
            <div v-else-if="failed === 'plan'" class="p-8 text-center text-sm" style="color:var(--muted)">{{ t('tbl.not_in_plan') }}</div>
            <ErrorState v-else-if="failed" @retry="load" />
            <div v-else-if="!rows.length" class="p-8 text-center" style="color:var(--muted)">{{ t('tbl.none_tables') }}</div>
            <template v-else>
                <!-- Select-all header (only when the user can delete). -->
                <div v-if="canDelete" class="flex items-center gap-3 px-5 py-2.5 tbl-head" style="border-color:var(--line)">
                    <input type="checkbox" class="row-check" :checked="allSelected"
                        :indeterminate.prop="someSelected" :aria-label="t('tbl.select_all')" @change="toggleAll" />
                    <span class="tbl-num" style="color:var(--muted)">#</span>
                    <span class="text-xs" style="color:var(--muted)">{{ t('tbl.select_all') }}</span>
                </div>
                <ul>
                    <li v-for="(tbl, i) in rows" :key="tbl.id" class="flex items-center gap-3 px-5 py-3 border-t first:border-t-0"
                        :class="{ 'row-selected': selected.has(tbl.id) }" style="border-color:var(--line)">
                        <input v-if="canDelete" type="checkbox" class="row-check" :checked="selected.has(tbl.id)"
                            :aria-label="tbl.label" @change="toggleSelect(tbl.id)" />
                        <span class="tbl-num" style="color:var(--muted)">{{ i + 1 }}</span>
                        <div class="h-11 w-11 rounded-lg grid place-items-center flex-shrink-0" style="background:var(--accent-soft);color:var(--accent)"><Icon name="table" :size="22" /></div>
                        <div class="flex-1 min-w-0">
                            <div class="font-medium" style="color:var(--ink)">{{ tbl.label }}</div>
                            <div class="text-xs truncate" style="color:var(--muted)">{{ areaLabel(tbl.dining_area_id) }}</div>
                        </div>
                        <StatusBadge :value="tbl.is_active" :label="tbl.is_active ? t('common.active') : t('common.inactive')" />
                        <button v-if="canUpdate" class="switch" :class="{ on: tbl.is_active }" @click="toggleActive(tbl)"></button>
                        <button @click="openQr(tbl)" class="icon-btn" :title="t('tbl.qr')"><Icon name="qr" :size="17" /></button>
                        <button v-if="canUpdate" @click="openEdit(tbl)" class="icon-btn" :title="t('common.edit')"><Icon name="edit" :size="17" /></button>
                        <button v-if="canDelete" @click="remove(tbl)" class="icon-btn icon-btn-danger" :title="t('common.delete')"><Icon name="trash" :size="17" /></button>
                    </li>
                </ul>
            </template>
        </div>

        <!-- Create / edit modal -->
        <Dialog v-if="showModal" :title="editing ? t('common.edit') : t('tbl.tables_title')" @close="showModal = false">
            <div class="space-y-4">
                <!-- Create only: toggle to add a numbered batch in one save. -->
                <label v-if="!editing" class="flex items-center gap-2 text-sm" style="color:var(--body)">
                    <button type="button" class="switch" :class="{ on: bulkMode }" @click="bulkMode = !bulkMode"></button>
                    {{ t('tbl.add_multiple') }}
                </label>
                <label class="block"><span class="label">{{ t('tbl.area') }}</span>
                    <select v-model="form.dining_area_id" class="input">
                        <option v-for="a in activeAreas" :key="a.id" :value="a.id">{{ areaName(a) }}</option>
                    </select>
                    <FormError :errors="errors" field="dining_area_id" /></label>

                <!-- Bulk create: one field per table name; Enter adds another. -->
                <template v-if="bulkMode && !editing">
                    <div class="block">
                        <span class="label">{{ t('tbl.table_names') }}</span>
                        <div ref="labelList" class="space-y-2">
                            <div v-for="(lbl, i) in form.labels" :key="i" class="flex items-center gap-2">
                                <span class="tbl-num" style="color:var(--muted)">{{ i + 1 }}</span>
                                <input v-model="form.labels[i]" class="input tbl-label-input flex-1"
                                    :placeholder="t('tbl.label')" @keydown.enter.prevent="addLabelField(i)" />
                                <button v-if="form.labels.length > 1" type="button" class="icon-btn icon-btn-danger"
                                    :title="t('common.delete')" @click="removeLabelField(i)"><Icon name="trash" :size="16" /></button>
                            </div>
                        </div>
                        <button type="button" class="btn btn-ghost btn-sm mt-2" @click="addLabelField(form.labels.length - 1)">
                            <Icon name="plus" :size="15" />{{ t('tbl.add_name') }}
                        </button>
                        <FormError :errors="errors" field="labels" />
                        <p class="text-xs mt-1" style="color:var(--muted)">{{ t('tbl.enter_hint') }}</p>
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
                <label class="flex items-center gap-2 text-sm" style="color:var(--body)">
                    <button type="button" class="switch" :class="{ on: form.is_active }" @click="form.is_active = !form.is_active"></button>
                    {{ t('common.active') }}
                </label>
                <div class="flex justify-end gap-2 pt-2">
                    <button @click="showModal = false" :disabled="saving" class="btn btn-ghost">{{ t('common.cancel') }}</button>
                    <button @click="save" :disabled="saving || (bulkMode && !editing && !bulkCount)" class="btn btn-accent">
                        <Icon v-if="saving" name="loading" :size="16" class="animate-spin" />
                        {{ saving ? t('common.saving') : (bulkMode && !editing && bulkCount ? t('tbl.save_count', { n: bulkCount }) : t('common.save')) }}
                    </button>
                </div>
            </div>
        </Dialog>

        <!-- QR modal -->
        <Dialog v-if="qrModal" :title="`${t('tbl.table')} : ${qrModal.table.label}`" @close="qrModal = null">
            <div class="space-y-4 text-center">
                <div v-if="qrLoading" class="py-10" style="color:var(--muted)">…</div>
                <div v-else class="mx-auto qr-box" v-html="qrModal.svg"></div>
                <p class="text-xs break-all" style="color:var(--muted)" dir="ltr">{{ qrModal.url }}</p>
                <p class="text-sm" style="color:var(--body)">{{ t('tbl.scan_hint') }}</p>
                <div class="flex justify-center gap-2 pt-1">
                    <button v-if="canUpdate" @click="regenerateQr" class="btn btn-ghost">{{ t('tbl.qr_regenerate') }}</button>
                    <button @click="downloadQr" class="btn btn-accent"><Icon name="download" :size="16" />{{ t('tbl.qr_download') }}</button>
                </div>
            </div>
        </Dialog>
    </div>
</template>

<style scoped>
/* The QR SVG is generated at a fixed pixel size; make it fit its box so it
   never overflows onto the URL/hint text below. */
.qr-box { width: 15rem; height: 15rem; }
.qr-box :deep(svg) { width: 100%; height: 100%; display: block; }

/* Row number + multi-select */
.tbl-num { flex: none; width: 1.75rem; text-align: center; font-size: 12.5px; font-variant-numeric: tabular-nums; }
.tbl-head { border-bottom: 1px solid var(--line); background: var(--page); }
.row-check { flex: none; width: 16px; height: 16px; accent-color: var(--accent); cursor: pointer; }
.row-selected { background: var(--accent-soft); }

/* Bulk action bar surfaced above the list for the current selection. */
.bulk-bar {
    display: flex; align-items: center; gap: 10px;
    padding: 10px 14px; border-radius: 12px;
    background: var(--accent-soft); border: 1px solid var(--accent);
}
.bulk-count { font-weight: 600; font-size: 13.5px; color: var(--accent); margin-inline-end: auto; }
.btn-danger { background: var(--red); color: #fff; border-color: var(--red); }
.btn-danger:hover:not(:disabled) { filter: brightness(.94); }
.btn-danger:disabled { opacity: .6; cursor: default; }
</style>
