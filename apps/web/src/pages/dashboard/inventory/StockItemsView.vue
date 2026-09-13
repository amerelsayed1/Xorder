<script setup>
import { ref, reactive, computed, onMounted, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import api from '@xorder/api-client/api.js'
import { useAuth } from '@xorder/api-client/auth.js'
import { withMinDuration } from '../../../lib/minLoading.js'
import { pickLocalized } from '@xorder/ui/localize.js'
import { useMenuLang } from '../../../lib/menuLang.js'
import Dialog from '@xorder/ui/Dialog.vue'
import ListSkeleton from '@xorder/ui/ListSkeleton.vue'
import ErrorState from '@xorder/ui/ErrorState.vue'
import StatusBadge from '@xorder/ui/StatusBadge.vue'
import FormError from '@xorder/ui/FormError.vue'
import Icon from '@xorder/ui/Icon.vue'
import { confirm } from '@xorder/ui/confirm.js'
import { alert } from '@xorder/ui/alert.js'

// CB-09 slice b. What a business buys and counts: its own table, optionally
// linked to one menu item, never counted against the menu's item limit.
// The unit is locked while any branch holds stock of the item or it sits on
// a draft or open order; the server decides that under a lock, and
// `holds_stock` / `on_open_order` only let the form say so up front.
// purchase.manage opens the page and gates writes (see SuppliersView).
const { t, locale } = useI18n()
const auth = useAuth()
const canWrite = computed(() => auth.can('purchase.manage') && !auth.isReadOnly)
const { langs, bilingual } = useMenuLang()

const rows = ref([])
const units = ref([])
const menuItems = ref([])
const loading = ref(true)
const failed = ref(false)
const search = ref('')
const showRetired = ref(false)

async function load() {
    loading.value = true
    failed.value = false
    try {
        const [items, lookups] = await withMinDuration(Promise.all([
            api.get('api/dashboard/stock-items'),
            api.get('api/dashboard/purchasing/lookups'),
        ]))
        rows.value = items.data.data
        units.value = lookups.data.data.units
        menuItems.value = lookups.data.data.menu_items
    } catch {
        failed.value = true
    } finally {
        loading.value = false
    }
}
onMounted(load)

const nameOf = (s) => pickLocalized(s, 'name', locale.value) || s.name_en || s.name_ar || `#${s.id}`
const unitOf = (code) => units.value.find((u) => u.code === code)
const unitName = (code) => { const u = unitOf(code); return u ? (pickLocalized(u, 'name', locale.value) || code) : code }
const menuName = (id) => { const m = menuItems.value.find((x) => x.id === id); return m ? nameOf(m) : `#${id}` }

const visible = computed(() => {
    const q = search.value.trim().toLowerCase()
    return rows.value
        .filter((s) => showRetired.value || s.is_active)
        .filter((s) => !q || [s.name_en, s.name_ar, s.sku].some((v) => v && String(v).toLowerCase().includes(q)))
        .sort((a, b) => (b.is_active - a.is_active) || nameOf(a).localeCompare(nameOf(b), locale.value))
})
const retiredCount = computed(() => rows.value.filter((s) => !s.is_active).length)

// ------------------------------------------------------------------ editor
const showModal = ref(false)
const editing = ref(null)
const errors = ref({})
const saving = ref(false)
const blank = () => ({ name_en: '', name_ar: '', sku: '', unit_code: '', menu_item_id: '', is_active: true })
const form = reactive(blank())

const unitLocked = computed(() => !!editing.value && (editing.value.holds_stock || editing.value.on_open_order))
// A retired unit is never offered, except the one this item already has.
const unitOptions = computed(() => units.value.filter((u) => u.is_active || u.code === editing.value?.unit_code))
// A menu item is counted by one stock item at most.
const menuOptions = computed(() => {
    const taken = new Set(rows.value.filter((r) => r.menu_item_id && r.id !== editing.value?.id).map((r) => r.menu_item_id))
    return menuItems.value.filter((m) => !taken.has(m.id))
})

function openCreate() {
    editing.value = null
    errors.value = {}
    Object.assign(form, blank(), { unit_code: unitOptions.value[0]?.code || '' })
    showModal.value = true
}
function openEdit(s) {
    editing.value = s
    errors.value = {}
    Object.assign(form, blank(), fromRow(s))
    showModal.value = true
}
function fromRow(s) {
    return {
        name_en: s.name_en || '', name_ar: s.name_ar || '', sku: s.sku || '',
        unit_code: s.unit_code, menu_item_id: s.menu_item_id ?? '', is_active: !!s.is_active,
    }
}

// Linking a menu item fills an empty name from it. Never the other way:
// editing a stock item never renames the menu.
watch(() => form.menu_item_id, (id) => {
    if (!id || !showModal.value) return
    const m = menuItems.value.find((x) => x.id === Number(id))
    if (!m) return
    if (!form.name_en && !form.name_ar) {
        form.name_en = m.name_en || ''
        form.name_ar = m.name_ar || ''
    }
})

function payload(src) {
    return {
        name_en: src.name_en || null,
        name_ar: src.name_ar || null,
        sku: src.sku || null,
        unit_code: src.unit_code,
        menu_item_id: src.menu_item_id ? Number(src.menu_item_id) : null,
        is_active: !!src.is_active,
    }
}

function replaceRow(row) {
    const i = rows.value.findIndex((x) => x.id === row.id)
    if (i === -1) rows.value.push(row)
    else rows.value.splice(i, 1, row)
}

async function save() {
    if (saving.value) return
    saving.value = true
    errors.value = {}
    try {
        const { data } = editing.value
            ? await api.put(`api/dashboard/stock-items/${editing.value.id}`, payload(form))
            : await api.post('api/dashboard/stock-items', payload(form))
        replaceRow(data.data)
        showModal.value = false
    } catch (err) {
        errors.value = err.response?.data?.errors || {}
        if (!Object.keys(errors.value).length) alert(err.response?.data?.message || t('common.error'))
    } finally {
        saving.value = false
    }
}

async function setActive(s, active) {
    if (!active) {
        const ok = await confirm({
            title: t('purchasing.retire_item_title'),
            message: t('purchasing.retire_item_message', { name: nameOf(s) }),
            confirmText: t('purchasing.retire'),
            cancelText: t('common.cancel'),
        })
        if (!ok) return
    }
    try {
        const { data } = await api.put(`api/dashboard/stock-items/${s.id}`, payload({ ...fromRow(s), is_active: active }))
        replaceRow(data.data)
    } catch (err) {
        alert(err.response?.data?.message || t('common.error'))
    }
}
</script>

<template>
    <div class="space-y-5">
        <div class="flex flex-wrap items-start justify-between gap-3">
            <div>
                <h1 class="page-title">{{ t('purchasing.stock_items_title') }}</h1>
                <p class="page-sub">{{ t('purchasing.stock_items_sub') }}</p>
            </div>
            <button v-if="canWrite && !loading && !failed" type="button" class="btn btn-accent" @click="openCreate">
                <Icon name="plus" :size="16" />{{ t('purchasing.add_stock_item') }}
            </button>
        </div>

        <ErrorState v-if="failed" :message="t('common.error')" @retry="load" />

        <template v-else>
            <div v-if="!loading && rows.length" class="flex flex-wrap items-center gap-3">
                <input v-model="search" class="input" style="max-width: 360px" :placeholder="t('purchasing.search_stock_items')" />
                <label v-if="retiredCount" class="flex items-center gap-2 text-sm cursor-pointer" style="color:var(--body)">
                    <input v-model="showRetired" type="checkbox" class="h-4 w-4" />
                    {{ t('purchasing.show_retired') }} <span class="mono" dir="ltr">({{ retiredCount }})</span>
                </label>
            </div>

            <div class="card overflow-hidden">
                <ListSkeleton v-if="loading" />
                <div v-else-if="!rows.length" class="p-8 text-center space-y-1">
                    <div class="font-medium" style="color:var(--ink)">{{ t('purchasing.none_stock_items') }}</div>
                    <div class="text-sm" style="color:var(--muted)">{{ t('purchasing.none_stock_items_hint') }}</div>
                </div>
                <div v-else-if="!visible.length" class="p-8 text-center text-sm" style="color:var(--muted)">{{ t('purchasing.none_stock_items_match') }}</div>
                <ul v-else>
                    <li v-for="s in visible" :key="s.id" class="flex items-center gap-3 px-5 py-3 border-t first:border-t-0" style="border-color:var(--line)" :style="s.is_active ? '' : 'opacity:.65'">
                        <div class="h-11 w-11 rounded-lg grid place-items-center flex-shrink-0 mono text-sm" dir="ltr" style="background:var(--accent-soft);color:var(--accent)">{{ s.unit_code }}</div>
                        <div class="flex-1 min-w-0">
                            <div class="font-medium flex flex-wrap items-center gap-2" style="color:var(--ink)">
                                {{ nameOf(s) }}
                                <span v-if="s.sku" class="mono text-xs rounded px-1.5 py-0.5" dir="ltr" style="background:var(--page);color:var(--muted)">{{ s.sku }}</span>
                            </div>
                            <div class="text-xs truncate" style="color:var(--muted)">
                                {{ unitName(s.unit_code) }}
                                <span v-if="s.menu_item_id"> · <i class="pi pi-link" aria-hidden="true"></i> {{ menuName(s.menu_item_id) }}</span>
                            </div>
                        </div>
                        <StatusBadge :value="s.is_active" :label="s.is_active ? t('common.active') : t('purchasing.retired')" />
                        <RouterLink :to="{ name: 'dashboard.inventory.movements', params: { itemId: s.id } }" class="btn btn-ghost btn-sm">{{ t('purchasing.view_movements') }}</RouterLink>
                        <button v-if="canWrite" type="button" class="icon-btn" :title="t('common.edit')" :aria-label="t('common.edit')" @click="openEdit(s)"><Icon name="edit" :size="17" /></button>
                        <button v-if="canWrite && s.is_active" type="button" class="btn btn-ghost btn-sm" @click="setActive(s, false)">{{ t('purchasing.retire') }}</button>
                        <button v-else-if="canWrite" type="button" class="btn btn-ghost btn-sm" @click="setActive(s, true)">{{ t('purchasing.reactivate') }}</button>
                    </li>
                </ul>
            </div>
        </template>

        <Dialog v-if="showModal" :title="editing ? t('purchasing.edit_stock_item') : t('purchasing.add_stock_item')" @close="showModal = false">
            <form class="space-y-4" @submit.prevent="save">
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                    <label v-for="lng in langs" :key="'n' + lng" class="block" :dir="lng === 'ar' ? 'rtl' : 'ltr'">
                        <span class="label">{{ bilingual ? t('common.name_' + lng) : t('common.name') }}</span>
                        <input v-model="form['name_' + lng]" class="input" maxlength="160" />
                        <FormError :errors="errors" :field="'name_' + lng" />
                    </label>
                </div>
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                    <label class="block"><span class="label">{{ t('purchasing.unit') }}</span>
                        <select v-model="form.unit_code" class="input" :disabled="unitLocked">
                            <option v-for="u in unitOptions" :key="u.code" :value="u.code">{{ u.code }} · {{ unitName(u.code) }}{{ u.is_active ? '' : ' ' + t('purchasing.retired_suffix') }}</option>
                        </select>
                        <span class="text-xs" style="color:var(--muted)">{{ unitLocked ? t('purchasing.unit_locked_hint') : t('purchasing.unit_hint') }}</span>
                        <FormError :errors="errors" field="unit_code" /></label>
                    <label class="block"><span class="label">{{ t('purchasing.sku') }}</span>
                        <input v-model="form.sku" class="input mono" dir="ltr" maxlength="64" spellcheck="false" />
                        <span class="text-xs" style="color:var(--muted)">{{ t('purchasing.sku_hint') }}</span>
                        <FormError :errors="errors" field="sku" /></label>
                </div>
                <label class="block"><span class="label">{{ t('purchasing.menu_item') }}</span>
                    <select v-model="form.menu_item_id" class="input">
                        <option value="">{{ t('purchasing.menu_item_none') }}</option>
                        <option v-for="m in menuOptions" :key="m.id" :value="m.id">{{ nameOf(m) }}</option>
                    </select>
                    <span class="text-xs" style="color:var(--muted)">{{ t('purchasing.menu_item_hint') }}</span>
                    <FormError :errors="errors" field="menu_item_id" /></label>
                <label v-if="editing" class="flex items-center gap-2 text-sm" style="color:var(--body)">
                    <button type="button" class="switch" :class="{ on: form.is_active }" :aria-pressed="form.is_active" @click="form.is_active = !form.is_active"></button>
                    {{ t('common.active') }}
                </label>
                <div class="flex justify-end gap-2 pt-2">
                    <button type="button" class="btn btn-ghost" :disabled="saving" @click="showModal = false">{{ t('common.cancel') }}</button>
                    <button type="submit" class="btn btn-accent" :disabled="saving">
                        <Icon v-if="saving" name="loading" :size="16" class="animate-spin" />
                        {{ saving ? t('common.saving') : t('common.save') }}
                    </button>
                </div>
            </form>
        </Dialog>
    </div>
</template>
