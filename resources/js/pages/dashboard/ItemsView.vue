<script setup>
import { ref, reactive, onMounted, computed } from 'vue'
import { useI18n } from 'vue-i18n'
import api, { ensureCsrf } from '../../lib/api'
import Modal from '../../components/Modal.vue'
import ImageUploader from '../../components/ImageUploader.vue'
import FormError from '../../components/FormError.vue'

const { t } = useI18n()
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
})

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
    const [it, cats] = await Promise.all([
        api.get('api/dashboard/items'),
        api.get('api/dashboard/categories'),
    ])
    items.value = it.data.data
    categories.value = cats.data.data
    loading.value = false
}
onMounted(load)

function catName(id) {
    const c = categories.value.find(c => c.id === id)
    return c ? (c.name_en || c.name_ar) : ''
}
function openCreate() {
    editing.value = null; errors.value = {}
    Object.assign(form, { category_id: categories.value[0]?.id || '', name_en: '', name_ar: '',
        description_en: '', description_ar: '', price: '', discounted_price: '', image_url: '',
        is_available: true, is_featured: false })
    showModal.value = true
}
function openEdit(it) {
    editing.value = it; errors.value = {}
    Object.assign(form, { category_id: it.category_id, name_en: it.name_en || '', name_ar: it.name_ar || '',
        description_en: it.description_en || '', description_ar: it.description_ar || '',
        price: it.price, discounted_price: it.discounted_price || '', image_url: it.image_url || '',
        is_available: it.is_available, is_featured: it.is_featured })
    showModal.value = true
}
async function save() {
    errors.value = {}
    const payload = { ...form, discounted_price: form.discounted_price === '' ? null : form.discounted_price }
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
    if (!confirm(t('common.confirm_delete'))) return
    await ensureCsrf()
    await api.delete(`api/dashboard/items/${it.id}`)
    await load()
}
</script>

<template>
    <div class="space-y-5">
        <div class="flex flex-wrap items-start justify-between gap-3">
            <div>
                <h1 class="page-title">{{ t('nav.items') }}</h1>
                <p class="page-sub">{{ items.length }} items across {{ categories.length }} categories.</p>
            </div>
            <button @click="openCreate" :disabled="!categories.length" class="btn btn-accent">+ {{ t('common.create') }}</button>
        </div>
        <p v-if="!categories.length" class="text-sm" style="color:var(--amber)">Create a category first.</p>

        <!-- Toolbar -->
        <div class="flex flex-wrap items-center gap-3">
            <input v-model="search" :placeholder="t('common.search')" class="input" style="max-width:280px" />
            <div class="segmented overflow-x-auto">
                <button :class="{ active: filterCat === '' }" @click="filterCat = ''">All</button>
                <button v-for="c in categories" :key="c.id" :class="{ active: filterCat === c.id }" @click="filterCat = c.id">
                    {{ c.name_en || c.name_ar }}
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
                        <th class="font-medium px-5 py-3" style="font-size:11px;letter-spacing:.06em;text-transform:uppercase">Item</th>
                        <th class="font-medium px-3 py-3 hidden sm:table-cell" style="font-size:11px;text-transform:uppercase">Category</th>
                        <th class="font-medium px-3 py-3" style="font-size:11px;text-transform:uppercase">Price</th>
                        <th class="font-medium px-3 py-3 hidden sm:table-cell" style="font-size:11px;text-transform:uppercase">★</th>
                        <th class="font-medium px-3 py-3" style="font-size:11px;text-transform:uppercase">On</th>
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
                                    <div class="font-medium" style="color:var(--ink)">{{ it.name_en || it.name_ar }}</div>
                                    <div class="text-xs" style="color:var(--muted)" dir="rtl">{{ it.name_ar }}</div>
                                </div>
                            </div>
                        </td>
                        <td class="px-3 py-3 hidden sm:table-cell" style="color:var(--body)">{{ catName(it.category_id) }}</td>
                        <td class="px-3 py-3 whitespace-nowrap">
                            <span class="price">{{ it.discounted_price || it.price }}</span>
                            <span v-if="it.discounted_price" class="text-xs line-through ms-1" style="color:var(--muted)">{{ it.price }}</span>
                        </td>
                        <td class="px-3 py-3 hidden sm:table-cell">
                            <button class="star" :class="{ on: it.is_featured }" @click="toggleFeatured(it)">★</button>
                        </td>
                        <td class="px-3 py-3">
                            <button class="switch" :class="{ on: it.is_available }" @click="toggleAvail(it)"></button>
                        </td>
                        <td class="px-5 py-3 text-end whitespace-nowrap">
                            <button @click="openEdit(it)" class="text-sm underline" style="color:var(--body)">{{ t('common.edit') }}</button>
                            <button @click="remove(it)" class="text-sm underline ms-3" style="color:#c0392b">{{ t('common.delete') }}</button>
                        </td>
                    </tr>
                </tbody>
            </table>
        </div>

        <Modal v-if="showModal" :title="editing ? t('common.edit') : t('common.create')" @close="showModal = false">
            <div class="space-y-4">
                <label class="block"><span class="label">{{ t('item.category') }}</span>
                    <select v-model="form.category_id" class="input">
                        <option v-for="c in categories" :key="c.id" :value="c.id">{{ c.name_en || c.name_ar }}</option>
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
                    <label class="block"><span class="label">{{ t('item.price') }}</span>
                        <input v-model="form.price" type="number" step="0.01" min="0" class="input" />
                        <FormError :errors="errors" field="price" /></label>
                    <label class="block"><span class="label">{{ t('item.discounted_price') }}</span>
                        <input v-model="form.discounted_price" type="number" step="0.01" min="0" class="input" />
                        <FormError :errors="errors" field="discounted_price" /></label>
                </div>
                <ImageUploader v-model="form.image_url" folder="items" label="Item image" />
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
                <div class="flex justify-end gap-2 pt-2">
                    <button @click="showModal = false" class="btn btn-ghost">{{ t('common.cancel') }}</button>
                    <button @click="save" class="btn btn-accent">{{ t('common.save') }}</button>
                </div>
            </div>
        </Modal>
    </div>
</template>
