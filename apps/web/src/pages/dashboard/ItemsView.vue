<script setup>
import { ref, reactive, onMounted, computed } from 'vue'
import { useI18n } from 'vue-i18n'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import { withMinDuration } from '../../lib/minLoading.js'
import { useAuth } from '@xorder/api-client/auth.js'
import { currencyLabel } from '../../lib/currency.js'
import { pickLocalized } from '@xorder/ui/localize.js'
import Modal from '@xorder/ui/Modal.vue'
import ListSkeleton from '@xorder/ui/ListSkeleton.vue'
import ImageUploader from '@xorder/ui/ImageUploader.vue'
import FormError from '@xorder/ui/FormError.vue'
import Icon from '@xorder/ui/Icon.vue'
import { confirm } from '@xorder/ui/confirm.js'
import { useMenuLang } from '../../lib/menuLang.js'

const { t, locale } = useI18n()
const { langs, bilingual } = useMenuLang()
const auth = useAuth()
const cur = computed(() => currencyLabel(auth.restaurant?.currency, locale.value, auth.restaurant?.currency_symbol))
const items = ref([])
const categories = ref([])
const loading = ref(true)
const saving = ref(false)
const filterCat = ref('')
const search = ref('')
const showModal = ref(false)
const editing = ref(null)
const errors = ref({})
const form = reactive({
    category_id: '', name_en: '', name_ar: '', description_en: '', description_ar: '',
    price: '', discounted_price: '', image_url: '', is_available: true, is_featured: false,
    option_groups: [],
})

// --- option-group builder helpers ---
function addGroup() { form.option_groups.push({ name_en: '', name_ar: '', is_required: false, max_select: 1, options: [] }) }
function removeGroup(i) { form.option_groups.splice(i, 1) }
function addOption(g) { g.options.push({ name_en: '', name_ar: '', price: '' }) }
function removeOption(g, i) { g.options.splice(i, 1) }

const filtered = computed(() => {
    let list = filterCat.value
        ? items.value.filter(i => i.category_id === Number(filterCat.value))
        : items.value
    const q = search.value.trim().toLowerCase()
    if (q) list = list.filter(i =>
        (i.name_en || '').toLowerCase().includes(q) || (i.name_ar || '').toLowerCase().includes(q))
    return list
})

async function load() {
    loading.value = true
    try {
        const [it, cats] = await withMinDuration(Promise.all([
            api.get('api/dashboard/items'),
            api.get('api/dashboard/categories'),
        ]))
        items.value = it.data.data
        categories.value = cats.data.data
    } catch (e) {
        console.error('Failed to load menu items', e)
    } finally {
        loading.value = false
    }
}
onMounted(load)

function catName(id) {
    const c = categories.value.find(c => c.id === id)
    return c ? pickLocalized(c, 'name', locale.value) : ''
}
const itemName = (it) => pickLocalized(it, 'name', locale.value)
const itemAltName = (it) => locale.value === 'ar' ? (it.name_en || '') : (it.name_ar || '')
function openCreate() {
    editing.value = null; errors.value = {}
    Object.assign(form, { category_id: categories.value[0]?.id || '', name_en: '', name_ar: '',
        description_en: '', description_ar: '', price: '', discounted_price: '', image_url: '',
        is_available: true, is_featured: false, option_groups: [] })
    showModal.value = true
}
function openEdit(it) {
    editing.value = it; errors.value = {}
    Object.assign(form, { category_id: it.category_id, name_en: it.name_en || '', name_ar: it.name_ar || '',
        description_en: it.description_en || '', description_ar: it.description_ar || '',
        price: it.price, discounted_price: it.discounted_price || '', image_url: it.image_url || '',
        is_available: it.is_available, is_featured: it.is_featured,
        option_groups: (it.option_groups || []).map(g => ({
            name_en: g.name_en || '', name_ar: g.name_ar || '',
            is_required: !!g.is_required, max_select: g.max_select || 1,
            options: (g.options || []).map(o => ({ name_en: o.name_en || '', name_ar: o.name_ar || '', price: o.price ?? '' })),
        })) })
    showModal.value = true
}
async function save() {
    if (saving.value) return // guard against double-submit (double-click)
    saving.value = true
    errors.value = {}
    const payload = {
        ...form,
        discounted_price: form.discounted_price === '' ? null : form.discounted_price,
        option_groups: form.option_groups.map(g => ({
            name_en: g.name_en, name_ar: g.name_ar,
            is_required: g.is_required, max_select: Number(g.max_select) || 1,
            options: g.options.map(o => ({ name_en: o.name_en, name_ar: o.name_ar, price: o.price === '' ? 0 : Number(o.price) })),
        })),
    }
    try {
        await ensureCsrf()
        if (editing.value) await api.put(`api/dashboard/items/${editing.value.id}`, payload)
        else await api.post('api/dashboard/items', payload)
        showModal.value = false
        await load()
    } catch (err) { errors.value = err.response?.data?.errors || {} }
    finally { saving.value = false }
}
async function toggleAvail(it) {
    await ensureCsrf()
    await api.patch(`api/dashboard/items/${it.id}/availability`, { is_available: !it.is_available })
    it.is_available = !it.is_available
}
async function toggleFeatured(it) {
    await ensureCsrf()
    await api.put(`api/dashboard/items/${it.id}`, { is_featured: !it.is_featured })
    it.is_featured = !it.is_featured
}
async function remove(it) {
    const ok = await confirm({
        title: t('common.delete'),
        message: t('common.confirm_delete'),
        confirmText: t('common.delete'),
        cancelText: t('common.cancel'),
        danger: true,
    })
    if (!ok) return
    try {
        await ensureCsrf()
        await api.delete(`api/dashboard/items/${it.id}`)
        await load()
    } catch (err) {
        alert(t('common.delete_failed'))
    }
}

// --- CSV / Excel import ---
const showImport = ref(false)
const importing = ref(false)
const importFile = ref(null)
const importResult = ref(null)
const importError = ref('')

function openImport() {
    importFile.value = null
    importResult.value = null
    importError.value = ''
    showImport.value = true
}
function onImportFile(e) {
    importFile.value = e.target.files?.[0] || null
    importResult.value = null
    importError.value = ''
}

// A ready-to-fill template in the restaurant's own default language.
function downloadTemplate() {
    const ar = auth.restaurant?.default_language !== 'en'
    const headers = ['category', 'name', 'description', 'price', 'discounted_price', 'available', 'featured']
    const sample = ar
        ? ['مشروبات', 'قهوة سادة', 'قهوة عربية طازجة', '30', '', 'نعم', 'لا']
        : ['Drinks', 'Espresso', 'Freshly brewed', '30', '', 'yes', 'no']
    const csv = '﻿' + [headers.join(','), sample.map(v => /[",\n]/.test(v) ? `"${v.replace(/"/g, '""')}"` : v).join(',')].join('\n')
    const url = URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8;' }))
    const a = document.createElement('a')
    a.href = url; a.download = 'menu-template.csv'; a.click()
    URL.revokeObjectURL(url)
}

async function submitImport() {
    if (!importFile.value || importing.value) return
    importing.value = true
    importError.value = ''
    importResult.value = null
    try {
        await ensureCsrf()
        const fd = new FormData()
        fd.append('file', importFile.value)
        const { data } = await api.post('api/dashboard/items/import', fd, { headers: { 'Content-Type': 'multipart/form-data' } })
        importResult.value = data.data
        await load()
    } catch (err) {
        importError.value = err.response?.data?.message || t('import.failed')
    } finally {
        importing.value = false
    }
}
</script>

<template>
    <div class="space-y-5">
        <div class="flex flex-wrap items-start justify-between gap-3">
            <div>
                <h1 class="page-title">{{ t('nav.items') }}</h1>
                <p class="page-sub">{{ t('item.subtitle', { items: items.length, categories: categories.length }) }}</p>
            </div>
            <div class="flex items-center gap-2">
                <button @click="openImport" class="btn btn-ghost"><Icon name="upload" :size="16" />{{ t('import.button') }}</button>
                <button @click="openCreate" :disabled="!categories.length" class="btn btn-accent"><Icon name="plus" :size="16" />{{ t('common.create') }}</button>
            </div>
        </div>
        <p v-if="!categories.length" class="text-sm" style="color:var(--amber)">{{ t('item.create_category_first') }}</p>

        <!-- Toolbar -->
        <div class="flex flex-wrap items-center gap-3">
            <div class="relative" style="max-width:280px;width:100%">
                <span class="absolute top-1/2 -translate-y-1/2 inset-inline-start-3 pointer-events-none" style="inset-inline-start:12px;color:var(--muted)"><Icon name="search" :size="17" /></span>
                <input v-model="search" :placeholder="t('common.search')" class="input" style="padding-inline-start:38px" />
            </div>
            <div class="cat-filter">
                <button class="cat-chip" :class="{ active: filterCat === '' }" @click="filterCat = ''">{{ t('common.all') }}</button>
                <button v-for="c in categories" :key="c.id" class="cat-chip" :class="{ active: filterCat === c.id }" @click="filterCat = c.id">
                    {{ catName(c.id) }}
                </button>
            </div>
        </div>

        <!-- Table -->
        <div class="card overflow-hidden">
            <ListSkeleton v-if="loading" />
            <div v-else-if="!filtered.length" class="p-8 text-center" style="color:var(--muted)">{{ t('common.none') }}</div>
            <table v-else class="w-full text-sm">
                <thead>
                    <tr class="text-left" style="color:var(--muted)">
                        <th class="font-medium px-5 py-3" style="font-size:11px;letter-spacing:.06em;text-transform:uppercase">{{ t('item.item') }}</th>
                        <th class="font-medium px-3 py-3 hidden sm:table-cell" style="font-size:11px;text-transform:uppercase">{{ t('item.category') }}</th>
                        <th class="font-medium px-3 py-3" style="font-size:11px;text-transform:uppercase">{{ t('item.price') }}</th>
                        <th class="font-medium px-3 py-3 hidden sm:table-cell" style="font-size:11px;text-transform:uppercase">★</th>
                        <th class="font-medium px-3 py-3" style="font-size:11px;text-transform:uppercase">{{ t('common.available') }}</th>
                        <th class="px-5 py-3"></th>
                    </tr>
                </thead>
                <tbody>
                    <tr v-for="it in filtered" :key="it.id" class="border-t" style="border-color:var(--line)">
                        <td class="px-5 py-3">
                            <div class="flex items-center gap-3">
                                <img v-if="it.image_url" :src="it.image_url" class="h-11 w-11 rounded-lg object-cover flex-shrink-0" />
                                <div v-else class="h-11 w-11 rounded-lg flex-shrink-0" style="background:var(--accent-soft)"></div>
                                <div class="min-w-0">
                                    <div class="font-medium" style="color:var(--ink)">{{ itemName(it) }}</div>
                                    <div v-if="itemAltName(it)" class="text-xs" style="color:var(--muted)" :dir="locale === 'ar' ? 'ltr' : 'rtl'">{{ itemAltName(it) }}</div>
                                </div>
                            </div>
                        </td>
                        <td class="px-3 py-3 hidden sm:table-cell" style="color:var(--body)">{{ catName(it.category_id) }}</td>
                        <td class="px-3 py-3 whitespace-nowrap">
                            <span class="price">{{ it.discounted_price || it.price }} {{ cur }}</span>
                            <span v-if="it.discounted_price" class="text-xs line-through ms-1" style="color:var(--muted)">{{ it.price }} {{ cur }}</span>
                        </td>
                        <td class="px-3 py-3 hidden sm:table-cell">
                            <button class="star" :class="{ on: it.is_featured }" @click="toggleFeatured(it)">★</button>
                        </td>
                        <td class="px-3 py-3">
                            <button class="switch" :class="{ on: it.is_available }" @click="toggleAvail(it)"></button>
                        </td>
                        <td class="px-5 py-3 text-end whitespace-nowrap">
                            <div class="inline-flex items-center gap-1">
                                <button @click="openEdit(it)" class="icon-btn" :title="t('common.edit')"><Icon name="edit" :size="17" /></button>
                                <button @click="remove(it)" class="icon-btn icon-btn-danger" :title="t('common.delete')"><Icon name="trash" :size="17" /></button>
                            </div>
                        </td>
                    </tr>
                </tbody>
            </table>
        </div>

        <Modal v-if="showModal" :title="editing ? t('common.edit') : t('common.create')" @close="showModal = false">
            <div class="space-y-4">
                <label class="block"><span class="label">{{ t('item.category') }}</span>
                    <select v-model="form.category_id" class="input">
                        <option v-for="c in categories" :key="c.id" :value="c.id">{{ catName(c.id) }}</option>
                    </select>
                    <FormError :errors="errors" field="category_id" /></label>
                <label v-for="lng in langs" :key="'n' + lng" class="block" :dir="lng === 'ar' ? 'rtl' : 'ltr'">
                    <span class="label">{{ bilingual ? t('common.name_' + lng) : t('common.name') }}</span>
                    <input v-model="form['name_' + lng]" class="input" />
                    <FormError :errors="errors" :field="'name_' + lng" /></label>
                <label v-for="lng in langs" :key="'d' + lng" class="block" :dir="lng === 'ar' ? 'rtl' : 'ltr'">
                    <span class="label">{{ bilingual ? t('common.description_' + lng) : t('common.description') }}</span>
                    <textarea v-model="form['description_' + lng]" rows="2" class="input"></textarea></label>
                <div class="grid grid-cols-2 gap-3">
                    <label class="block"><span class="label">{{ t('item.price') }}<template v-if="cur"> ({{ cur }})</template></span>
                        <input v-model="form.price" type="number" step="0.01" min="0" class="input" />
                        <FormError :errors="errors" field="price" /></label>
                    <label class="block"><span class="label">{{ t('item.discounted_price') }}</span>
                        <input v-model="form.discounted_price" type="number" step="0.01" min="0" class="input" />
                        <FormError :errors="errors" field="discounted_price" /></label>
                </div>
                <ImageUploader v-model="form.image_url" folder="items" :label="t('item.image')" />
                <div class="flex gap-5">
                    <label class="flex items-center gap-2 text-sm" style="color:var(--body)">
                        <button type="button" class="switch" :class="{ on: form.is_available }" @click="form.is_available = !form.is_available"></button>
                        {{ t('common.available') }}
                    </label>
                    <label class="flex items-center gap-2 text-sm" style="color:var(--body)">
                        <button type="button" class="star" :class="{ on: form.is_featured }" @click="form.is_featured = !form.is_featured">★</button>
                        {{ t('common.featured') }}
                    </label>
                </div>
                <!-- Option groups builder -->
                <div class="pt-2 border-t" style="border-color:var(--line)">
                    <div class="flex items-center justify-between mb-2">
                        <span class="label">{{ t('item.options') }}</span>
                        <button type="button" class="btn btn-ghost btn-sm" @click="addGroup">+ {{ t('item.add_group') }}</button>
                    </div>
                    <p v-if="!form.option_groups.length" class="text-xs" style="color:var(--muted)">{{ t('item.no_options') }}</p>
                    <div v-for="(g, gi) in form.option_groups" :key="gi" class="rounded-xl p-3 mb-3" style="background:var(--page);border:1px solid var(--line)">
                        <div class="grid grid-cols-1 gap-2" :class="{ 'sm:grid-cols-2': bilingual }">
                            <input v-for="lng in langs" :key="'g' + lng" v-model="g['name_' + lng]" class="input"
                                :dir="lng === 'ar' ? 'rtl' : 'ltr'" :placeholder="t('item.group_name_' + lng)" />
                        </div>
                        <div class="flex items-center gap-4 flex-wrap mt-2">
                            <label class="flex items-center gap-2 text-xs" style="color:var(--body)">
                                <button type="button" class="switch" :class="{ on: g.is_required }" @click="g.is_required = !g.is_required"></button>
                                {{ t('item.required') }}
                            </label>
                            <label class="flex items-center gap-2 text-xs" style="color:var(--body)">
                                {{ t('item.max_select') }}
                                <input v-model.number="g.max_select" type="number" min="1" class="input" style="width:64px;padding:5px 8px" />
                            </label>
                            <button type="button" class="icon-btn icon-btn-danger ms-auto" :title="t('common.delete')" @click="removeGroup(gi)"><Icon name="trash" :size="16" /></button>
                        </div>
                        <div class="mt-2 space-y-2">
                            <div v-for="(o, oi) in g.options" :key="oi" class="flex items-center gap-2">
                                <input v-for="lng in langs" :key="'o' + lng" v-model="o['name_' + lng]" class="input flex-1"
                                    :dir="lng === 'ar' ? 'rtl' : 'ltr'" :placeholder="t('item.option_' + lng)" />
                                <input v-model="o.price" type="number" step="0.01" min="0" class="input" style="width:90px" :placeholder="cur || '+0'" />
                                <button type="button" class="icon-btn icon-btn-danger" :title="t('common.delete')" @click="removeOption(g, oi)"><Icon name="close" :size="16" /></button>
                            </div>
                            <button type="button" class="btn btn-ghost btn-sm" @click="addOption(g)">+ {{ t('item.add_option') }}</button>
                        </div>
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

        <!-- Import from CSV / Excel -->
        <Modal v-if="showImport" :title="t('import.title')" @close="showImport = false">
            <div class="space-y-4">
                <p class="text-sm" style="color:var(--body)">{{ t('import.help') }}</p>
                <div class="rounded-xl p-3 text-xs" style="background:var(--page);border:1px solid var(--line);color:var(--muted)">
                    {{ t('import.columns_help') }}
                </div>
                <button type="button" class="btn btn-ghost btn-sm" @click="downloadTemplate">
                    <Icon name="download" :size="15" />{{ t('import.template') }}
                </button>

                <label class="block">
                    <span class="label">{{ t('import.choose_file') }}</span>
                    <input type="file" accept=".csv,.xlsx,.xls,text/csv" class="input" @change="onImportFile" />
                    <span class="text-xs" style="color:var(--muted)">{{ t('import.formats') }}</span>
                </label>

                <p v-if="importError" class="text-sm" style="color:var(--red, #dc2626)">{{ importError }}</p>

                <!-- Result summary -->
                <div v-if="importResult" class="rounded-xl p-3 space-y-2" style="background:var(--page);border:1px solid var(--line)">
                    <div class="flex flex-wrap gap-x-4 gap-y-1 text-sm" style="color:var(--ink)">
                        <span>✓ {{ t('import.created', { n: importResult.items_created }) }}</span>
                        <span>↻ {{ t('import.updated', { n: importResult.items_updated }) }}</span>
                        <span v-if="importResult.categories_created">＋ {{ t('import.cats_created', { n: importResult.categories_created }) }}</span>
                        <span v-if="importResult.skipped">⊘ {{ t('import.skipped', { n: importResult.skipped }) }}</span>
                    </div>
                    <div v-if="importResult.errors?.length" class="text-xs space-y-1" style="color:var(--muted);max-height:150px;overflow:auto">
                        <div class="font-medium" style="color:var(--amber)">{{ t('import.errors') }}</div>
                        <div v-for="(er, i) in importResult.errors" :key="i">{{ t('import.row', { n: er.row }) }}: {{ er.message }}</div>
                    </div>
                </div>

                <div class="flex justify-end gap-2 pt-2">
                    <button @click="showImport = false" :disabled="importing" class="btn btn-ghost">{{ importResult ? t('common.close') : t('common.cancel') }}</button>
                    <button v-if="!importResult" @click="submitImport" :disabled="importing || !importFile" class="btn btn-accent">
                        <Icon v-if="importing" name="loading" :size="16" class="animate-spin" />
                        {{ importing ? t('import.uploading') : t('import.button') }}
                    </button>
                </div>
            </div>
        </Modal>
    </div>
</template>

<style scoped>
/* Horizontal chip filter — handles many categories (with long bilingual
   names) without wrapping into tall cramped tabs like the segmented control. */
.cat-filter {
    display: flex;
    gap: 6px;
    flex: 1 1 100%;
    min-width: 0;
    overflow-x: auto;
    padding-bottom: 4px;
    scrollbar-width: thin;
}
.cat-filter::-webkit-scrollbar { height: 5px; }
.cat-filter::-webkit-scrollbar-thumb { background: var(--line); border-radius: 999px; }
.cat-chip {
    flex: none;
    white-space: nowrap;
    font-family: var(--font-display);
    font-weight: 600;
    font-size: 13px;
    line-height: 1.2;
    padding: 8px 15px;
    border-radius: 999px;
    border: 1px solid var(--line);
    background: var(--card);
    color: var(--muted);
    cursor: pointer;
    transition: color .15s, background .15s, border-color .15s;
}
.cat-chip:hover { border-color: var(--accent); color: var(--accent); }
.cat-chip.active {
    background: var(--accent);
    border-color: var(--accent);
    color: #fff;
}
</style>
