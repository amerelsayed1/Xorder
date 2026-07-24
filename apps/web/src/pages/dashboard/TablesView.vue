<script setup>
import { ref, reactive, computed, onMounted, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import { withMinDuration } from '../../lib/minLoading.js'
import { pickLocalized } from '@xorder/ui/localize.js'
import Dialog from '@xorder/ui/Dialog.vue'
import ListSkeleton from '@xorder/ui/ListSkeleton.vue'
import StatusBadge from '@xorder/ui/StatusBadge.vue'
import FormError from '@xorder/ui/FormError.vue'
import Icon from '@xorder/ui/Icon.vue'
import { confirm } from '@xorder/ui/confirm.js'
import { useAuth } from '@xorder/api-client/auth.js'

const { t, locale } = useI18n()
const auth = useAuth()
const rows = ref([])
const areas = ref([])
const loading = ref(true)
const saving = ref(false)
const showModal = ref(false)
const editing = ref(null)
const errors = ref({})
const filters = reactive({ dining_area_id: '', status: '', search: '' })

const blank = () => ({ dining_area_id: '', label: '', seats_count: null, notes: '', is_active: true })
const form = reactive(blank())

const activeAreas = computed(() => areas.value.filter(a => a.is_active))

async function loadAreas() {
    const { data } = await api.get('api/dashboard/dining-areas')
    areas.value = data.data
}
async function loadTables() {
    loading.value = true
    const params = {}
    if (filters.dining_area_id) params.dining_area_id = filters.dining_area_id
    if (filters.status) params.status = filters.status
    if (filters.search) params.search = filters.search
    const { data } = await withMinDuration(api.get('api/dashboard/tables', { params }))
    rows.value = data.data
    loading.value = false
}
onMounted(async () => { await loadAreas(); await loadTables() })
watch(() => [filters.dining_area_id, filters.status], loadTables)

let searchTimer
watch(() => filters.search, () => { clearTimeout(searchTimer); searchTimer = setTimeout(loadTables, 300) })

function openCreate() {
    editing.value = null; errors.value = {}
    Object.assign(form, blank(), { dining_area_id: activeAreas.value[0]?.id || '' })
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
        if (editing.value) await api.put(`api/dashboard/tables/${editing.value.id}`, form)
        else await api.post('api/dashboard/tables', form)
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
            <button v-if="!auth.isReadOnly" @click="openCreate" :disabled="!activeAreas.length" class="btn btn-accent"><Icon name="plus" :size="16" />{{ t('common.create') }}</button>
        </div>

        <p v-if="!areas.length" class="card p-4 text-sm" style="color:var(--muted)">{{ t('tbl.no_area_first') }}</p>

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

        <div class="card overflow-hidden">
            <ListSkeleton v-if="loading" />
            <div v-else-if="!rows.length" class="p-8 text-center" style="color:var(--muted)">{{ t('tbl.none_tables') }}</div>
            <ul v-else>
                <li v-for="tbl in rows" :key="tbl.id" class="flex items-center gap-3 px-5 py-3 border-t first:border-t-0" style="border-color:var(--line)">
                    <div class="h-11 w-11 rounded-lg grid place-items-center flex-shrink-0" style="background:var(--accent-soft);color:var(--accent)"><Icon name="table" :size="22" /></div>
                    <div class="flex-1 min-w-0">
                        <div class="font-medium" style="color:var(--ink)">{{ tbl.label }}</div>
                        <div class="text-xs truncate" style="color:var(--muted)">{{ areaLabel(tbl.dining_area_id) }}</div>
                    </div>
                    <StatusBadge :value="tbl.is_active" :label="tbl.is_active ? t('common.active') : t('common.inactive')" />
                    <button v-if="!auth.isReadOnly" class="switch" :class="{ on: tbl.is_active }" @click="toggleActive(tbl)"></button>
                    <button @click="openQr(tbl)" class="icon-btn" :title="t('tbl.qr')"><Icon name="qr" :size="17" /></button>
                    <button v-if="!auth.isReadOnly" @click="openEdit(tbl)" class="icon-btn" :title="t('common.edit')"><Icon name="edit" :size="17" /></button>
                    <button v-if="!auth.isReadOnly" @click="remove(tbl)" class="icon-btn icon-btn-danger" :title="t('common.delete')"><Icon name="trash" :size="17" /></button>
                </li>
            </ul>
        </div>

        <!-- Create / edit modal -->
        <Dialog v-if="showModal" :title="editing ? t('common.edit') : t('tbl.tables_title')" @close="showModal = false">
            <div class="space-y-4">
                <label class="block"><span class="label">{{ t('tbl.area') }}</span>
                    <select v-model="form.dining_area_id" class="input">
                        <option v-for="a in activeAreas" :key="a.id" :value="a.id">{{ areaName(a) }}</option>
                    </select>
                    <FormError :errors="errors" field="dining_area_id" /></label>
                <label class="block"><span class="label">{{ t('tbl.label') }}</span>
                    <input v-model="form.label" class="input" />
                    <FormError :errors="errors" field="label" /></label>
                <label class="block"><span class="label">{{ t('tbl.notes') }}</span>
                    <textarea v-model="form.notes" rows="2" class="input"></textarea></label>
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
        </Dialog>

        <!-- QR modal -->
        <Dialog v-if="qrModal" :title="`${t('tbl.table')} : ${qrModal.table.label}`" @close="qrModal = null">
            <div class="space-y-4 text-center">
                <div v-if="qrLoading" class="py-10" style="color:var(--muted)">…</div>
                <div v-else class="mx-auto qr-box" v-html="qrModal.svg"></div>
                <p class="text-xs break-all" style="color:var(--muted)" dir="ltr">{{ qrModal.url }}</p>
                <p class="text-sm" style="color:var(--body)">{{ t('tbl.scan_hint') }}</p>
                <div class="flex justify-center gap-2 pt-1">
                    <button v-if="!auth.isReadOnly" @click="regenerateQr" class="btn btn-ghost">{{ t('tbl.qr_regenerate') }}</button>
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
</style>
