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
import { useAuth } from '@xorder/api-client/auth.js'

const { t, locale } = useI18n()
const auth = useAuth()
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
async function save() {
    if (saving.value) return
    saving.value = true; errors.value = {}
    try {
        await ensureCsrf()
        if (editing.value) await api.put(`api/dashboard/dining-areas/${editing.value.id}`, form)
        else await api.post('api/dashboard/dining-areas', form)
        showModal.value = false
        await load()
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
        <div class="flex items-start justify-between gap-3">
            <div>
                <h1 class="page-title">{{ t('tbl.areas_title') }}</h1>
                <p class="page-sub">{{ t('tbl.areas_sub', { count: rows.length }) }}</p>
            </div>
            <button v-if="!auth.isReadOnly" @click="openCreate" :disabled="!branches.length" class="btn btn-accent"><Icon name="plus" :size="16" />{{ t('common.create') }}</button>
        </div>

        <p v-if="!loading && !branches.length" class="card p-4 text-sm" style="color:var(--muted)">{{ t('tbl.no_branch_first') }}</p>

        <div class="card overflow-hidden">
            <ListSkeleton v-if="loading" />
            <div v-else-if="!rows.length" class="p-8 text-center" style="color:var(--muted)">{{ t('tbl.none_areas') }}</div>
            <ul v-else>
                <li v-for="a in rows" :key="a.id" class="flex items-center gap-3 px-5 py-3 border-t first:border-t-0" style="border-color:var(--line)">
                    <div class="h-11 w-11 rounded-lg grid place-items-center flex-shrink-0" style="background:var(--accent-soft);color:var(--accent)"><Icon name="store" :size="18" /></div>
                    <div class="flex-1 min-w-0">
                        <div class="font-medium" style="color:var(--ink)">{{ areaName(a) }}</div>
                        <div class="text-xs truncate" style="color:var(--muted)">{{ branchLabel(a.branch_id) }} · {{ typeLabel(a.type) }} · {{ t('tbl.tables_count', { count: a.tables_count ?? 0 }) }}</div>
                    </div>
                    <StatusBadge :value="a.is_active" :label="a.is_active ? t('common.active') : t('common.inactive')" />
                    <button v-if="!auth.isReadOnly" class="switch" :class="{ on: a.is_active }" @click="toggleActive(a)"></button>
                    <button v-if="!auth.isReadOnly" @click="openEdit(a)" class="icon-btn" :title="t('common.edit')"><Icon name="edit" :size="17" /></button>
                    <button v-if="!auth.isReadOnly" @click="remove(a)" class="icon-btn icon-btn-danger" :title="t('common.delete')"><Icon name="trash" :size="17" /></button>
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
    </div>
</template>
