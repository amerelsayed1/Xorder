<script setup>
import { ref, reactive, computed, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import { withMinDuration } from '../../lib/minLoading.js'
import { pickLocalized } from '@xorder/ui/localize.js'
import { useMenuLang } from '../../lib/menuLang.js'
import Dialog from '@xorder/ui/Dialog.vue'
import ListSkeleton from '@xorder/ui/ListSkeleton.vue'
import StatusBadge from '@xorder/ui/StatusBadge.vue'
import FormError from '@xorder/ui/FormError.vue'
import Icon from '@xorder/ui/Icon.vue'
import { confirm } from '@xorder/ui/confirm.js'
import { alert } from '@xorder/ui/alert.js'
import { useAuth } from '@xorder/api-client/auth.js'
import { useCaps } from '../../lib/useCaps.js'

const { t, locale } = useI18n()
const auth = useAuth()
// Per-action gates so the UI offers only what the API would accept.
const { canCreate, canUpdate, canDelete } = useCaps('tables')
const { langs, bilingual } = useMenuLang()
const rows = ref([])
const branches = ref([])
const loading = ref(true)
const saving = ref(false)
const showModal = ref(false)
const editing = ref(null)
const errors = ref({})
const blank = () => ({ branch_id: '', name_en: '', name_ar: '', type: 'indoor', display_order: 0, is_active: true })
const form = reactive(blank())

async function load() {
    loading.value = true
    const [areas, brs] = await withMinDuration(Promise.all([
        api.get('api/dashboard/dining-areas'),
        api.get('api/dashboard/branches'),
    ]))
    rows.value = areas.data.data
    branches.value = brs.data.data
    loading.value = false
}
onMounted(load)

function openCreate() {
    editing.value = null; errors.value = {}
    Object.assign(form, blank(), { branch_id: branches.value[0]?.id || '' })
    syncTypeMode()
    showModal.value = true
}
function openEdit(a) {
    editing.value = a; errors.value = {}
    Object.assign(form, blank(), {
        branch_id: a.branch_id, name_en: a.name_en || '', name_ar: a.name_ar || '',
        type: a.type || 'indoor', display_order: a.display_order || 0, is_active: a.is_active,
    })
    syncTypeMode()
    showModal.value = true
}
async function save(addAnother = false) {
    if (saving.value) return
    saving.value = true; errors.value = {}
    try {
        await ensureCsrf()
        if (editing.value) await api.put(`api/dashboard/dining-areas/${editing.value.id}`, form)
        else await api.post('api/dashboard/dining-areas', form)
        await load()
        if (addAnother && !editing.value) {
            // Keep the dialog open for the next area — clear the names but keep
            // the branch, type and status so consecutive areas are quick to add.
            Object.assign(form, blank(), {
                branch_id: form.branch_id, type: form.type, is_active: form.is_active,
            })
            errors.value = {}
        } else {
            showModal.value = false
        }
    } catch (err) { errors.value = err.response?.data?.errors || {} }
    finally { saving.value = false }
}
async function toggleActive(a) {
    await ensureCsrf()
    await api.patch(`api/dashboard/dining-areas/${a.id}/status`, { is_active: !a.is_active })
    a.is_active = !a.is_active
}
async function remove(a) {
    const ok = await confirm({
        title: t('common.delete'), message: t('common.confirm_delete'),
        confirmText: t('common.delete'), cancelText: t('common.cancel'), danger: true,
    })
    if (!ok) return
    try {
        await ensureCsrf()
        await api.delete(`api/dashboard/dining-areas/${a.id}`)
        await load()
    } catch (err) { alert(err.response?.data?.message || t('common.delete_failed')) }
}

const areaName = (a) => pickLocalized(a, 'name', locale.value)
// Localize the built-in Indoor/Outdoor presets; show a custom type as entered.
const typeLabel = (type) => (['indoor', 'outdoor'].includes(type) ? t(`tbl.type_${type}`) : type)
const branchName = (b) => pickLocalized(b, 'name', locale.value)
const branchLabel = (id) => { const b = branches.value.find(x => x.id === id); return b ? branchName(b) : '—' }

// Area type: Indoor / Outdoor presets, or a custom label (Garden, Rooftop, VIP…).
const typeMode = ref('indoor') // 'indoor' | 'outdoor' | 'custom'
function syncTypeMode() {
    typeMode.value = ['indoor', 'outdoor'].includes(form.type) ? form.type : (form.type ? 'custom' : 'indoor')
}
function onTypeModeChange() {
    if (typeMode.value !== 'custom') form.type = typeMode.value
    else if (['indoor', 'outdoor'].includes(form.type)) form.type = ''
}
</script>

<template>
    <div class="space-y-5">
        <div class="flex flex-wrap items-start justify-between gap-3">
            <div class="min-w-0">
                <h1 class="page-title">{{ t('tbl.areas_title') }}</h1>
                <p class="page-sub" style="color:var(--body)">{{ t('tbl.areas_sub', { count: rows.length }) }}</p>
            </div>
            <button v-if="canCreate" @click="openCreate" :disabled="!branches.length" class="btn btn-accent act-btn"><Icon name="plus" :size="16" />{{ t('common.create') }}</button>
        </div>

        <!-- Guidance, not a warning: areas only matter to venues with seating. -->
        <div v-if="!loading && !branches.length" class="note" role="note">
            <span class="note-ico" aria-hidden="true"><Icon name="info" :size="18" /></span>
            <p class="note-title">{{ t('tbl.no_branch_first') }}</p>
        </div>

        <div class="card overflow-hidden">
            <ListSkeleton v-if="loading" />
            <div v-else-if="!rows.length" class="empty">
                <span class="empty-ico" aria-hidden="true"><Icon name="store" :size="22" /></span>
                <p class="empty-text">{{ t('tbl.none_areas') }}</p>
                <p class="empty-sub">{{ t('tbl.optional_areas_note') }}</p>
                <button v-if="canCreate && branches.length" class="btn btn-accent act-btn" @click="openCreate"><Icon name="plus" :size="16" />{{ t('common.create') }}</button>
            </div>
            <ul v-else>
                <li v-for="a in rows" :key="a.id" class="row">
                    <div class="row-main">
                        <div class="row-ico" aria-hidden="true"><Icon name="store" :size="18" /></div>
                        <div class="flex-1 min-w-0">
                            <div class="row-name truncate">{{ areaName(a) }}</div>
                            <div class="row-sub truncate">{{ branchLabel(a.branch_id) }} · {{ typeLabel(a.type) }} · {{ t('tbl.tables_count', { count: a.tables_count ?? 0 }) }}</div>
                        </div>
                    </div>
                    <div class="row-side">
                        <StatusBadge :value="a.is_active" :label="a.is_active ? t('common.active') : t('common.inactive')" />
                        <button v-if="canUpdate" type="button" class="switch" :class="{ on: a.is_active }" role="switch"
                            :aria-checked="a.is_active" :aria-label="a.is_active ? t('common.active') : t('common.inactive')" @click="toggleActive(a)"></button>
                        <button v-if="canUpdate" @click="openEdit(a)" class="icon-btn" :title="t('common.edit')" :aria-label="t('common.edit')"><Icon name="edit" :size="17" /></button>
                        <button v-if="canDelete" @click="remove(a)" class="icon-btn icon-btn-danger" :title="t('common.delete')" :aria-label="t('common.delete')"><Icon name="trash" :size="17" /></button>
                    </div>
                </li>
            </ul>
        </div>

        <Dialog v-if="showModal" :title="editing ? t('common.edit') : t('tbl.areas_title')" @close="showModal = false">
            <div class="space-y-4">
                <label class="block"><span class="label">{{ t('tbl.branch') }}</span>
                    <select v-model="form.branch_id" class="input">
                        <option v-for="b in branches" :key="b.id" :value="b.id">{{ branchName(b) }}</option>
                    </select>
                    <FormError :errors="errors" field="branch_id" /></label>
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                    <label v-for="lng in langs" :key="'n' + lng" class="block" :dir="lng === 'ar' ? 'rtl' : 'ltr'">
                        <span class="label">{{ bilingual ? t('common.name_' + lng) : t('common.name') }}</span>
                        <input v-model="form['name_' + lng]" class="input" />
                        <FormError :errors="errors" :field="'name_' + lng" /></label>
                </div>
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                    <label class="block"><span class="label">{{ t('tbl.type') }}</span>
                        <select v-model="typeMode" @change="onTypeModeChange" class="input">
                            <option value="indoor">{{ t('tbl.type_indoor') }}</option>
                            <option value="outdoor">{{ t('tbl.type_outdoor') }}</option>
                            <option value="custom">{{ t('tbl.type_custom') }}</option>
                        </select>
                        <input v-if="typeMode === 'custom'" v-model="form.type" class="input mt-2" :placeholder="t('tbl.type_custom_ph')" /></label>
                    <label class="block"><span class="label">{{ t('tbl.display_order') }}</span>
                        <input v-model.number="form.display_order" type="number" min="0" class="input" /></label>
                </div>
                <label class="toggle-line">
                    <button type="button" class="switch" :class="{ on: form.is_active }" role="switch" :aria-checked="form.is_active" @click="form.is_active = !form.is_active"></button>
                    {{ t('common.active') }}
                </label>
                <div class="flex flex-wrap justify-end gap-2 pt-3 form-actions">
                    <button @click="showModal = false" :disabled="saving" class="btn btn-ghost act-btn">{{ t('common.cancel') }}</button>
                    <button v-if="!editing" @click="save(true)" :disabled="saving" class="btn btn-ghost act-btn">{{ t('tbl.save_add_another') }}</button>
                    <button @click="save()" :disabled="saving" class="btn btn-accent act-btn">
                        <Icon v-if="saving" name="loading" :size="16" class="animate-spin" />
                        {{ saving ? t('common.saving') : t('common.save') }}
                    </button>
                </div>
            </div>
        </Dialog>
    </div>
</template>

<style scoped>
/* Colours come from the shared theme variables only. */

/* Guidance note: calm, not an error. */
.note { display: flex; align-items: center; gap: 12px; padding: 14px 16px; border-radius: 12px;
    background: var(--accent-soft); border: 1px solid var(--line); }
.note-ico { width: 32px; height: 32px; border-radius: 9px; display: grid; place-items: center; flex: none;
    background: var(--card); color: var(--p-primary-700); }
.note-title { font-size: 14.5px; font-weight: 600; color: var(--ink); }

/* Rows */
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

/* Empty state: friendly, centred, not an error */
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
}
</style>
