<script setup>
import { ref, reactive, onMounted, computed } from 'vue'
import { useI18n } from 'vue-i18n'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import { useAuth } from '@xorder/api-client/auth.js'
import { pickLocalized } from '@xorder/ui/localize.js'
import Modal from '@xorder/ui/Modal.vue'
import ImageUploader from '@xorder/ui/ImageUploader.vue'
import FormError from '@xorder/ui/FormError.vue'
import Icon from '@xorder/ui/Icon.vue'
import { confirm } from '@xorder/ui/confirm.js'

const { t, locale } = useI18n()
const auth = useAuth()
const cur = computed(() => auth.restaurant?.currency_symbol || '')
const items = ref([])
const categories = ref([])
const loading = ref(true)
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
        const [it, cats] = await Promise.all([
            api.get('api/dashboard/items'),
            api.get('api/dashboard/categories'),
        ])
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
</script>

<template>
    <div class="space-y-5">
        <div class="flex flex-wrap items-start justify-between gap-3">
            <div>
                <h1 class="page-title">{{ t('nav.items') }}</h1>
                <p class="page-sub">{{ t('item.subtitle', { items: items.length, categories: categories.length }) }}</p>
            </div>
            <button @click="openCreate" :disabled="!categories.length" class="btn btn-accent"><Icon name="plus" :size="16" />{{ t('common.create') }}</button>
        </div>
        <p v-if="!categories.length" class="text-sm" style="color:var(--amber)">{{ t('item.create_category_first') }}</p>

        <!-- Toolbar -->
        <div class="flex flex-wrap items-center gap-3">
            <div class="relative" style="max-width:280px;width:100%">
                <span class="absolute top-1/2 -translate-y-1/2 inset-inline-start-3 pointer-events-none" style="inset-inline-start:12px;color:var(--muted)"><Icon name="search" :size="17" /></span>
                <input v-model="search" :placeholder="t('common.search')" class="input" style="padding-inline-start:38px" />
            </div>
            <div class="segmented overflow-x-auto">
                <button :class="{ active: filterCat === '' }" @click="filterCat = ''">{{ t('common.all') }}</button>
                <button v-for="c in categories" :key="c.id" :class="{ active: filterCat === c.id }" @click="filterCat = c.id">
                    {{ catName(c.id) }}
                </button>
            </div>
        </div>

        <!-- Table -->
        <div class="card overflow-hidden">
            <div v-if="loading" class="p-8 text-center" style="color:var(--muted)">{{ t('common.loading') }}</div>
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
                <label class="block"><span class="label">{{ t('common.name_en') }}</span>
                    <input v-model="form.name_en" class="input" />
                    <FormError :errors="errors" field="name_en" /></label>
                <label class="block" dir="rtl"><span class="label">{{ t('common.name_ar') }}</span>
                    <input v-model="form.name_ar" class="input" /></label>
                <label class="block"><span class="label">{{ t('common.description_en') }}</span>
                    <textarea v-model="form.description_en" rows="2" class="input"></textarea></label>
                <label class="block" dir="rtl"><span class="label">{{ t('common.description_ar') }}</span>
                    <textarea v-model="form.description_ar" rows="2" class="input"></textarea></label>
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
                        <div class="grid grid-cols-1 sm:grid-cols-2 gap-2">
                            <input v-model="g.name_en" class="input" :placeholder="t('item.group_name_en')" />
                            <input v-model="g.name_ar" class="input" dir="rtl" :placeholder="t('item.group_name_ar')" />
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
                                <input v-model="o.name_en" class="input flex-1" :placeholder="t('item.option_en')" />
                                <input v-model="o.name_ar" class="input flex-1" dir="rtl" :placeholder="t('item.option_ar')" />
                                <input v-model="o.price" type="number" step="0.01" min="0" class="input" style="width:90px" :placeholder="cur || '+0'" />
                                <button type="button" class="icon-btn icon-btn-danger" :title="t('common.delete')" @click="removeOption(g, oi)"><Icon name="close" :size="16" /></button>
                            </div>
                            <button type="button" class="btn btn-ghost btn-sm" @click="addOption(g)">+ {{ t('item.add_option') }}</button>
                        </div>
                    </div>
                </div>

                <div class="flex justify-end gap-2 pt-2">
                    <button @click="showModal = false" class="btn btn-ghost">{{ t('common.cancel') }}</button>
                    <button @click="save" class="btn btn-accent">{{ t('common.save') }}</button>
                </div>
            </div>
        </Modal>
    </div>
</template>
