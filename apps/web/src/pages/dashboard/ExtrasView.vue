<script setup>
import { ref, reactive, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import { withMinDuration } from '../../lib/minLoading.js'
import { useAuth } from '@xorder/api-client/auth.js'
import { useCaps } from '../../lib/useCaps.js'
import { pickLocalized } from '@xorder/ui/localize.js'
import { currencyLabel } from '../../lib/currency.js'
import Modal from '@xorder/ui/Modal.vue'
import ListSkeleton from '@xorder/ui/ListSkeleton.vue'
import FormError from '@xorder/ui/FormError.vue'
import Icon from '@xorder/ui/Icon.vue'
import { confirm } from '@xorder/ui/confirm.js'
import { alert } from '@xorder/ui/alert.js'
import { useMenuLang } from '../../lib/menuLang.js'

const { t, locale } = useI18n()
const { langs, bilingual } = useMenuLang()
const auth = useAuth()
// Per-action gates so the UI offers only what the API would accept.
const { canCreate, canUpdate, canDelete } = useCaps('menu')
const cur = () => currencyLabel(auth.restaurant?.currency, locale.value, auth.restaurant?.currency_symbol)

const rows = ref([])
const categories = ref([])
const loading = ref(true)
const saving = ref(false)
const showModal = ref(false)
const editing = ref(null)
const errors = ref({})
const form = reactive({ name_en: '', name_ar: '', display_name_en: '', display_name_ar: '', is_required: false, is_variant: false, max_select: 1, apply_scope: 'items', category_ids: [], options: [] })

async function load() {
    loading.value = true
    const [groups, cats] = await withMinDuration(Promise.all([
        api.get('api/dashboard/option-groups'),
        api.get('api/dashboard/categories'),
    ]))
    rows.value = groups.data.data
    categories.value = cats.data.data
    loading.value = false
}
onMounted(load)

function catName(c) { return pickLocalized(c, 'name', locale.value) || c.name_en || c.name_ar || '' }
function toggleCategory(id) {
    const i = form.category_ids.indexOf(id)
    if (i === -1) form.category_ids.push(id)
    else form.category_ids.splice(i, 1)
}
// Human summary of where a saved group applies, for the list row.
function scopeSummary(g) {
    if (g.apply_scope === 'all') return t('extras.applies_all')
    if (g.apply_scope === 'categories') return t('extras.applies_categories', { n: g.category_ids?.length || 0 })
    return g.items_count ? t('extras.used_by', { n: g.items_count }) : t('extras.not_used')
}

// --- option builder helpers ---
function addOption() { form.options.push({ name_en: '', name_ar: '', price: '', discounted_price: '' }) }

// Nested option errors come back keyed by path (options.1.discounted_price);
// show the first one under the list so a rejected sale price is visible.
function optionError() {
    const key = Object.keys(errors.value).find(k => k.startsWith('options.'))
    return key ? errors.value[key][0] : ''
}
function removeOption(i) { form.options.splice(i, 1) }

function groupName(g) { return pickLocalized(g, 'name', locale.value) }

// What a diner actually sees above this group's choices. Shown under the row
// only when it differs from the library name — repeating an identical string
// would just be noise on every row that never needed the split.
function menuName(g) {
    const shown = pickLocalized(g, 'display_name', locale.value)
    return shown && shown !== groupName(g) ? shown : ''
}

function openCreate() {
    editing.value = null; errors.value = {}
    Object.assign(form, { name_en: '', name_ar: '', display_name_en: '', display_name_ar: '', is_required: false, is_variant: false, max_select: 1, apply_scope: 'items', category_ids: [], options: [] })
    showModal.value = true
}
function openEdit(g) {
    editing.value = g; errors.value = {}
    Object.assign(form, {
        name_en: g.name_en || '', name_ar: g.name_ar || '',
        display_name_en: g.display_name_en || '', display_name_ar: g.display_name_ar || '',
        is_required: !!g.is_required, is_variant: !!g.is_variant, max_select: g.max_select || 1,
        apply_scope: g.apply_scope || 'items', category_ids: [...(g.category_ids || [])],
        options: (g.options || []).map(o => ({ name_en: o.name_en || '', name_ar: o.name_ar || '', price: o.price ?? '', discounted_price: o.discounted_price ?? '' })),
    })
    showModal.value = true
}
async function save() {
    if (saving.value) return // guard against double-submit (double-click)
    saving.value = true
    errors.value = {}
    const payload = {
        name_en: form.name_en, name_ar: form.name_ar,
        // Sent even when blank: an empty value is the instruction to drop the
        // separate heading and fall back to the library name.
        display_name_en: form.display_name_en, display_name_ar: form.display_name_ar,
        is_required: form.is_variant ? true : form.is_required,
        is_variant: form.is_variant,
        max_select: form.is_variant ? 1 : (Number(form.max_select) || 1),
        apply_scope: form.apply_scope,
        category_ids: form.apply_scope === 'categories' ? form.category_ids : [],
        options: form.options.map(o => ({
            name_en: o.name_en, name_ar: o.name_ar,
            price: o.price === '' ? 0 : Number(o.price),
            // Sale price only applies to a size/variant group (see ItemForm).
            discounted_price: form.is_variant && o.discounted_price !== '' && o.discounted_price != null
                ? Number(o.discounted_price)
                : null,
        })),
    }
    try {
        await ensureCsrf()
        if (editing.value) await api.put(`api/dashboard/option-groups/${editing.value.id}`, payload)
        else await api.post('api/dashboard/option-groups', payload)
        showModal.value = false
        await load()
    } catch (err) { errors.value = err.response?.data?.errors || {} }
    finally { saving.value = false }
}
async function remove(g) {
    const ok = await confirm({
        title: t('common.delete'),
        message: g.items_count ? t('extras.delete_warning', { n: g.items_count }) : t('common.confirm_delete'),
        confirmText: t('common.delete'),
        cancelText: t('common.cancel'),
        danger: true,
    })
    if (!ok) return
    try {
        await ensureCsrf()
        await api.delete(`api/dashboard/option-groups/${g.id}`)
        await load()
    } catch (err) { alert(err.response?.data?.message || t('common.delete_failed')) }
}
</script>

<template>
    <div class="space-y-5">
        <div class="flex flex-wrap items-end justify-between gap-4">
            <div class="min-w-0">
                <h1 class="page-title">{{ t('extras.title') }}</h1>
                <p class="page-sub" style="color:var(--body)">{{ t('extras.subtitle') }}</p>
            </div>
            <button v-if="canCreate" @click="openCreate" class="btn btn-accent head-btn"><Icon name="plus" :size="16" />{{ t('extras.new') }}</button>
        </div>

        <div class="card overflow-hidden">
            <ListSkeleton v-if="loading" />

            <!-- Empty library: one sentence and the primary action. -->
            <div v-else-if="!rows.length" class="empty-card">
                <span class="empty-ico"><Icon name="plus" :size="28" /></span>
                <p class="empty-body">{{ t('extras.none') }}</p>
                <div v-if="canCreate" class="empty-actions">
                    <button class="btn btn-accent head-btn" @click="openCreate"><Icon name="plus" :size="16" />{{ t('extras.new') }}</button>
                </div>
            </div>

            <ul v-else>
                <li v-for="g in rows" :key="g.id" class="row">
                    <div class="row-ico">
                        <Icon :name="g.is_variant ? 'utensils' : 'plus'" :size="18" />
                    </div>
                    <div class="flex-1 min-w-0">
                        <div class="row-name truncate" :dir="locale === 'ar' ? 'rtl' : 'ltr'">{{ groupName(g) }}</div>
                        <div v-if="menuName(g)" class="row-sub truncate" :dir="locale === 'ar' ? 'rtl' : 'ltr'">
                            {{ t('extras.shown_as', { name: menuName(g) }) }}
                        </div>
                        <div class="row-sub">
                            {{ t('extras.options_summary', { n: g.options?.length || 0 }) }}
                            · <span :class="g.apply_scope !== 'items' || g.items_count ? 'row-scope' : ''">{{ scopeSummary(g) }}</span>
                        </div>
                    </div>
                    <span v-if="g.is_variant" class="badge chip">{{ t('item.variant') }}</span>
                    <div class="row-actions">
                        <button v-if="canUpdate" @click="openEdit(g)" class="icon-btn" :title="t('common.edit')" :aria-label="t('common.edit')"><Icon name="edit" :size="17" /></button>
                        <button v-if="canDelete" @click="remove(g)" class="icon-btn icon-btn-danger" :title="t('common.delete')" :aria-label="t('common.delete')"><Icon name="trash" :size="17" /></button>
                    </div>
                </li>
            </ul>
        </div>

        <Modal v-if="showModal" :title="editing ? t('extras.edit') : t('extras.new')" @close="showModal = false">
            <div class="space-y-4">
                <!-- Two names, because one string cannot do both jobs: this list
                     is browsed by an owner with dozens of groups, while the menu
                     heading is read by a diner choosing. -->
                <section class="card p-4 space-y-4">
                    <h3 class="h-card">{{ t('extras.section_names') }}</h3>
                    <div class="grid grid-cols-1 gap-3" :class="{ 'sm:grid-cols-2': bilingual }">
                        <label v-for="lng in langs" :key="'g' + lng" class="block min-w-0" :dir="lng === 'ar' ? 'rtl' : 'ltr'">
                            <span class="label">{{ bilingual ? t('extras.library_name_' + lng) : t('extras.library_name') }}</span>
                            <input v-model="form['name_' + lng]" class="input" :placeholder="t('item.group_name_' + lng)" />
                            <FormError :errors="errors" :field="'name_' + lng" />
                        </label>
                    </div>
                    <p class="help">{{ t('extras.library_name_hint') }}</p>

                    <div class="grid grid-cols-1 gap-3" :class="{ 'sm:grid-cols-2': bilingual }">
                        <label v-for="lng in langs" :key="'d' + lng" class="block min-w-0" :dir="lng === 'ar' ? 'rtl' : 'ltr'">
                            <span class="label">{{ bilingual ? t('extras.menu_name_' + lng) : t('extras.menu_name') }}</span>
                            <input v-model="form['display_name_' + lng]" class="input"
                                :placeholder="form['name_' + lng] || t('extras.menu_name_ph')" />
                            <FormError :errors="errors" :field="'display_name_' + lng" />
                        </label>
                    </div>
                    <p class="help">{{ t('extras.menu_name_hint') }}</p>
                </section>

                <!-- Choice rules -->
                <section class="card p-4 space-y-3">
                    <h3 class="h-card">{{ t('extras.section_rules') }}</h3>
                    <div class="flex items-center gap-x-5 gap-y-3 flex-wrap">
                        <label class="toggle-inline">
                            <button type="button" class="switch" role="switch" :aria-checked="form.is_variant" :class="{ on: form.is_variant }" @click="form.is_variant = !form.is_variant"></button>
                            {{ t('item.variant') }}
                        </label>
                        <label v-if="!form.is_variant" class="toggle-inline">
                            <button type="button" class="switch" role="switch" :aria-checked="form.is_required" :class="{ on: form.is_required }" @click="form.is_required = !form.is_required"></button>
                            {{ t('item.required') }}
                        </label>
                        <label v-if="!form.is_variant" class="toggle-inline">
                            {{ t('item.max_select') }}
                            <input v-model.number="form.max_select" type="number" min="1" class="input max-input" />
                        </label>
                    </div>
                    <p v-if="form.is_variant" class="help">{{ t('item.variant_hint') }}</p>
                </section>

                <!-- Where this extra applies: general (all items), per-category, or hand-picked items. -->
                <section class="card p-4 space-y-3">
                    <h3 class="h-card">{{ t('extras.apply_to') }}</h3>
                    <div class="flex flex-wrap gap-2" role="group" :aria-label="t('extras.apply_to')">
                        <button v-for="opt in ['all', 'categories', 'items']" :key="opt" type="button"
                            class="btn btn-sm scope-btn" :class="form.apply_scope === opt ? 'btn-accent' : 'btn-ghost'"
                            :aria-pressed="form.apply_scope === opt"
                            @click="form.apply_scope = opt">{{ t('extras.scope_' + opt) }}</button>
                    </div>
                    <p v-if="form.apply_scope === 'items'" class="help">{{ t('extras.scope_items_hint') }}</p>
                    <div v-else-if="form.apply_scope === 'categories'" class="space-y-2">
                        <p class="help">{{ t('extras.pick_categories') }}</p>
                        <div class="flex flex-wrap gap-2">
                            <label v-for="c in categories" :key="c.id" class="cat-chip"
                                :class="{ on: form.category_ids.includes(c.id) }">
                                <input type="checkbox" class="sr-only" :checked="form.category_ids.includes(c.id)" @change="toggleCategory(c.id)" />
                                {{ catName(c) }}
                            </label>
                        </div>
                        <FormError :errors="errors" field="category_ids" />
                    </div>
                </section>

                <section class="card p-4 space-y-3">
                    <h3 class="h-card">{{ t('item.options') }}</h3>
                    <div class="space-y-2">
                        <div v-for="(o, oi) in form.options" :key="oi" class="opt-row">
                            <input v-for="lng in langs" :key="'o' + lng" v-model="o['name_' + lng]" class="input opt-name"
                                :dir="lng === 'ar' ? 'rtl' : 'ltr'" :placeholder="t('item.option_' + lng)" :aria-label="t('item.option_' + lng)" />
                            <input v-model="o.price" type="number" step="0.01" min="0" class="input opt-price" inputmode="decimal" :aria-label="t('item.price')" :placeholder="form.is_variant ? (cur() || '0') : (cur() || '+0')" />
                            <input v-if="form.is_variant" v-model="o.discounted_price" type="number" step="0.01" min="0" inputmode="decimal"
                                class="input opt-price" :placeholder="t('item.option_discount')" :aria-label="t('item.option_discount')" :title="t('item.option_discount_hint')" />
                            <button type="button" class="icon-btn icon-btn-danger" :title="t('common.delete')" :aria-label="t('common.delete')" @click="removeOption(oi)"><Icon name="close" :size="16" /></button>
                        </div>
                        <p v-if="optionError()" class="text-xs text-red-600">{{ optionError() }}</p>
                        <button type="button" class="btn btn-ghost btn-sm touch" @click="addOption">+ {{ t('item.add_option') }}</button>
                    </div>
                </section>

                <div class="modal-actions">
                    <button @click="showModal = false" :disabled="saving" class="btn btn-ghost action-btn">{{ t('common.cancel') }}</button>
                    <button @click="save" :disabled="saving" class="btn btn-accent action-btn">
                        <Icon v-if="saving" name="loading" :size="16" class="animate-spin" />
                        {{ saving ? t('common.saving') : t('common.save') }}
                    </button>
                </div>
            </div>
        </Modal>
    </div>
</template>

<style scoped>
/* Colours come from the shared theme variables and the PrimeVue primary scale;
   no new hex values. */
.head-btn { min-height: 44px; }
.help { font-size: 13.5px; color: var(--body); margin: 0; }
.touch { min-height: 40px; }

/* List rows */
.row { display: flex; align-items: center; gap: 12px; padding: 12px 20px; min-height: 68px;
    border-top: 1px solid var(--line); transition: background .15s; }
.row:first-child { border-top: 0; }
.row:hover { background: var(--page); }
.row-ico { width: 44px; height: 44px; border-radius: 10px; display: grid; place-items: center; flex: none;
    background: var(--accent-soft); color: var(--p-primary-700); }
.row-name { font-size: 15.5px; font-weight: 600; color: var(--ink); }
.row-sub { font-size: 13px; color: var(--body); }
.row-scope { color: var(--p-primary-800); font-weight: 600; }
.chip { background: var(--accent-soft); color: var(--p-primary-800); flex: none; }
.row-actions { display: flex; align-items: center; gap: 2px; flex: none; }
@media (max-width: 639px) {
    .row { padding: 10px 12px; gap: 10px; }
    .row-ico { width: 40px; height: 40px; }
    .row-actions .icon-btn { width: 44px; height: 44px; }
}

/* Empty state */
.empty-card { padding: 56px 24px; display: flex; flex-direction: column; align-items: center; text-align: center; gap: 8px; }
.empty-ico { width: 60px; height: 60px; border-radius: 16px; display: grid; place-items: center;
    background: var(--accent-soft); color: var(--p-primary-700); margin-bottom: 8px; }
.empty-body { font-size: 15px; color: var(--body); max-width: 420px; margin: 0; }
.empty-actions { display: flex; flex-wrap: wrap; justify-content: center; gap: 10px; margin-top: 12px; }

/* Form */
.toggle-inline { display: flex; align-items: center; gap: 10px; font-size: 14.5px; color: var(--ink); }
.max-input { width: 72px; margin-top: 0; padding: 6px 8px; }
.scope-btn { min-height: 40px; }
.cat-chip {
    display: inline-flex; align-items: center; min-height: 40px; padding: 0 14px; border-radius: 10px; cursor: pointer;
    border: 1px solid var(--line); background: var(--card); color: var(--body); font-size: 14.5px;
}
.cat-chip:hover { border-color: var(--muted); }
.cat-chip.on { border-color: var(--accent); background: var(--accent-soft); color: var(--p-primary-800); font-weight: 600; }
.cat-chip:focus-within { outline: 2px solid var(--accent); outline-offset: 1px; }
.opt-row { display: flex; flex-wrap: wrap; align-items: center; gap: 8px; }
.opt-row .input { margin-top: 0; }
.opt-name { flex: 1 1 140px; min-width: 0; }
.opt-price { flex: 0 0 96px; width: 96px; }

/* Modal action row: separated from the form and pinned while it scrolls. */
.modal-actions {
    position: sticky; bottom: 0; z-index: 2;
    display: flex; justify-content: flex-end; gap: 10px;
    margin: 8px -24px -24px; padding: 14px 24px;
    background: var(--page); border-top: 1px solid var(--line);
}
.action-btn { min-height: 44px; justify-content: center; }
@media (max-width: 479px) { .action-btn { flex: 1 1 0; } }
</style>
