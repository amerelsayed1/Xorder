<script setup>
import { ref, reactive, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import { withMinDuration } from '../../lib/minLoading.js'
import { useAuth } from '@xorder/api-client/auth.js'
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
const cur = () => currencyLabel(auth.restaurant?.currency, locale.value, auth.restaurant?.currency_symbol)

const rows = ref([])
const categories = ref([])
const loading = ref(true)
const saving = ref(false)
const showModal = ref(false)
const editing = ref(null)
const errors = ref({})
const form = reactive({ name_en: '', name_ar: '', is_required: false, is_variant: false, max_select: 1, apply_scope: 'items', category_ids: [], options: [] })

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

function openCreate() {
    editing.value = null; errors.value = {}
    Object.assign(form, { name_en: '', name_ar: '', is_required: false, is_variant: false, max_select: 1, apply_scope: 'items', category_ids: [], options: [] })
    showModal.value = true
}
function openEdit(g) {
    editing.value = g; errors.value = {}
    Object.assign(form, {
        name_en: g.name_en || '', name_ar: g.name_ar || '',
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
        <div class="flex items-start justify-between gap-3">
            <div>
                <h1 class="page-title">{{ t('extras.title') }}</h1>
                <p class="page-sub">{{ t('extras.subtitle') }}</p>
            </div>
            <button v-if="!auth.isReadOnly" @click="openCreate" class="btn btn-accent"><Icon name="plus" :size="16" />{{ t('extras.new') }}</button>
        </div>

        <div class="card overflow-hidden">
            <ListSkeleton v-if="loading" />
            <div v-else-if="!rows.length" class="p-8 text-center" style="color:var(--muted)">{{ t('extras.none') }}</div>
            <ul v-else>
                <li v-for="g in rows" :key="g.id" class="flex items-center gap-3 px-5 py-3 border-t first:border-t-0" style="border-color:var(--line)">
                    <div class="h-11 w-11 rounded-lg grid place-items-center flex-shrink-0" style="background:var(--accent-soft);color:var(--accent)">
                        <Icon :name="g.is_variant ? 'utensils' : 'plus'" :size="18" />
                    </div>
                    <div class="flex-1 min-w-0">
                        <div class="font-medium truncate" style="color:var(--ink)" :dir="locale === 'ar' ? 'rtl' : 'ltr'">{{ groupName(g) }}</div>
                        <div class="text-xs" style="color:var(--muted)">
                            {{ t('extras.options_summary', { n: g.options?.length || 0 }) }}
                            · <span :style="g.apply_scope !== 'items' || g.items_count ? 'color:var(--accent)' : ''">{{ scopeSummary(g) }}</span>
                        </div>
                    </div>
                    <span v-if="g.is_variant" class="text-xs px-2 py-0.5 rounded-full" style="background:var(--accent-soft);color:var(--accent)">{{ t('item.variant') }}</span>
                    <button v-if="!auth.isReadOnly" @click="openEdit(g)" class="icon-btn" :title="t('common.edit')"><Icon name="edit" :size="17" /></button>
                    <button v-if="!auth.isReadOnly" @click="remove(g)" class="icon-btn icon-btn-danger" :title="t('common.delete')"><Icon name="trash" :size="17" /></button>
                </li>
            </ul>
        </div>

        <Modal v-if="showModal" :title="editing ? t('extras.edit') : t('extras.new')" @close="showModal = false">
            <div class="space-y-4">
                <div class="grid grid-cols-1 gap-2" :class="{ 'sm:grid-cols-2': bilingual }">
                    <label v-for="lng in langs" :key="'g' + lng" class="block" :dir="lng === 'ar' ? 'rtl' : 'ltr'">
                        <span class="label">{{ bilingual ? t('common.name_' + lng) : t('common.name') }}</span>
                        <input v-model="form['name_' + lng]" class="input" :placeholder="t('item.group_name_' + lng)" />
                        <FormError :errors="errors" :field="'name_' + lng" />
                    </label>
                </div>
                <div class="flex items-center gap-4 flex-wrap">
                    <label class="flex items-center gap-2 text-sm" style="color:var(--body)">
                        <button type="button" class="switch" :class="{ on: form.is_variant }" @click="form.is_variant = !form.is_variant"></button>
                        {{ t('item.variant') }}
                    </label>
                    <label v-if="!form.is_variant" class="flex items-center gap-2 text-sm" style="color:var(--body)">
                        <button type="button" class="switch" :class="{ on: form.is_required }" @click="form.is_required = !form.is_required"></button>
                        {{ t('item.required') }}
                    </label>
                    <label v-if="!form.is_variant" class="flex items-center gap-2 text-sm" style="color:var(--body)">
                        {{ t('item.max_select') }}
                        <input v-model.number="form.max_select" type="number" min="1" class="input" style="width:64px;padding:5px 8px" />
                    </label>
                </div>
                <p v-if="form.is_variant" class="text-xs" style="color:var(--muted)">{{ t('item.variant_hint') }}</p>

                <!-- Where this extra applies: general (all items), per-category, or hand-picked items. -->
                <div class="space-y-2 pt-1">
                    <span class="label">{{ t('extras.apply_to') }}</span>
                    <div class="flex flex-wrap gap-2">
                        <button v-for="opt in ['all', 'categories', 'items']" :key="opt" type="button"
                            class="btn btn-sm" :class="form.apply_scope === opt ? 'btn-accent' : 'btn-ghost'"
                            @click="form.apply_scope = opt">{{ t('extras.scope_' + opt) }}</button>
                    </div>
                    <p v-if="form.apply_scope === 'items'" class="text-xs" style="color:var(--muted)">{{ t('extras.scope_items_hint') }}</p>
                    <div v-else-if="form.apply_scope === 'categories'" class="space-y-1">
                        <p class="text-xs" style="color:var(--muted)">{{ t('extras.pick_categories') }}</p>
                        <div class="flex flex-wrap gap-2">
                            <label v-for="c in categories" :key="c.id"
                                class="flex items-center gap-1.5 text-sm px-2.5 py-1 rounded-lg cursor-pointer border"
                                :style="form.category_ids.includes(c.id) ? 'border-color:var(--accent);background:var(--accent-soft);color:var(--accent)' : 'border-color:var(--line);color:var(--body)'">
                                <input type="checkbox" class="sr-only" :checked="form.category_ids.includes(c.id)" @change="toggleCategory(c.id)" />
                                {{ catName(c) }}
                            </label>
                        </div>
                        <FormError :errors="errors" field="category_ids" />
                    </div>
                </div>

                <div class="space-y-2">
                    <div v-for="(o, oi) in form.options" :key="oi" class="flex items-center gap-2">
                        <input v-for="lng in langs" :key="'o' + lng" v-model="o['name_' + lng]" class="input flex-1"
                            :dir="lng === 'ar' ? 'rtl' : 'ltr'" :placeholder="t('item.option_' + lng)" />
                        <input v-model="o.price" type="number" step="0.01" min="0" class="input" style="width:90px" :placeholder="form.is_variant ? (cur() || '0') : (cur() || '+0')" />
                        <input v-if="form.is_variant" v-model="o.discounted_price" type="number" step="0.01" min="0"
                            class="input" style="width:90px" :placeholder="t('item.option_discount')" :title="t('item.option_discount_hint')" />
                        <button type="button" class="icon-btn icon-btn-danger" :title="t('common.delete')" @click="removeOption(oi)"><Icon name="close" :size="16" /></button>
                    </div>
                    <p v-if="optionError()" class="text-xs text-red-600">{{ optionError() }}</p>
                    <button type="button" class="btn btn-ghost btn-sm" @click="addOption">+ {{ t('item.add_option') }}</button>
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
