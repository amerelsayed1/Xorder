<script setup>
import { ref, reactive, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import api, { ensureCsrf } from '../../lib/api'
import Modal from '../../components/Modal.vue'
import StatusBadge from '../../components/StatusBadge.vue'
import ImageUploader from '../../components/ImageUploader.vue'
import FormError from '../../components/FormError.vue'

const { t } = useI18n()
const rows = ref([])
const loading = ref(true)
const showModal = ref(false)
const editing = ref(null)
const errors = ref({})
const form = reactive({ name_en: '', name_ar: '', description_en: '', description_ar: '', image_url: '', is_active: true })

async function load() {
    loading.value = true
    const { data } = await api.get('api/dashboard/categories')
    rows.value = data.data
    loading.value = false
}
onMounted(load)

function openCreate() {
    editing.value = null; errors.value = {}
    Object.assign(form, { name_en: '', name_ar: '', description_en: '', description_ar: '', image_url: '', is_active: true })
    showModal.value = true
}
function openEdit(c) {
    editing.value = c; errors.value = {}
    Object.assign(form, { name_en: c.name_en || '', name_ar: c.name_ar || '',
        description_en: c.description_en || '', description_ar: c.description_ar || '',
        image_url: c.image_url || '', is_active: c.is_active })
    showModal.value = true
}
async function save() {
    errors.value = {}
    try {
        await ensureCsrf()
        if (editing.value) await api.put(`api/dashboard/categories/${editing.value.id}`, form)
        else await api.post('api/dashboard/categories', form)
        showModal.value = false
        await load()
    } catch (err) { errors.value = err.response?.data?.errors || {} }
}
async function toggle(c) {
    await ensureCsrf()
    await api.patch(`api/dashboard/categories/${c.id}/status`, { is_active: !c.is_active })
    c.is_active = !c.is_active
}
async function remove(c) {
    if (!confirm(t('common.confirm_delete'))) return
    try {
        await ensureCsrf()
        await api.delete(`api/dashboard/categories/${c.id}`)
        await load()
    } catch (err) { alert(err.response?.data?.message || 'Delete failed') }
}
async function move(index, dir) {
    const target = index + dir
    if (target < 0 || target >= rows.value.length) return
    const a = rows.value[index], b = rows.value[target]
    await ensureCsrf()
    await api.patch('api/dashboard/categories/reorder', {
        order: [{ id: a.id, display_order: target }, { id: b.id, display_order: index }],
    })
    await load()
}
</script>

<template>
    <div class="space-y-5">
        <div class="flex items-start justify-between gap-3">
            <div>
                <h1 class="page-title">{{ t('nav.categories') }}</h1>
                <p class="page-sub">{{ rows.length }} categories · drag order with the arrows.</p>
            </div>
            <button @click="openCreate" class="btn btn-accent">+ {{ t('common.create') }}</button>
        </div>

        <div class="card overflow-hidden">
            <div v-if="loading" class="p-8 text-center" style="color:var(--muted)">{{ t('common.loading') }}</div>
            <div v-else-if="!rows.length" class="p-8 text-center" style="color:var(--muted)">{{ t('common.none') }}</div>
            <ul v-else>
                <li v-for="(c, i) in rows" :key="c.id" class="flex items-center gap-3 px-5 py-3.5 border-t first:border-t-0" style="border-color:var(--line)">
                    <div class="flex flex-col leading-none" style="color:var(--muted)">
                        <button @click="move(i, -1)" :disabled="i === 0" class="disabled:opacity-25 text-xs">▲</button>
                        <button @click="move(i, 1)" :disabled="i === rows.length - 1" class="disabled:opacity-25 text-xs">▼</button>
                    </div>
                    <img v-if="c.image_url" :src="c.image_url" class="h-10 w-10 rounded-lg object-cover" />
                    <div class="flex-1 min-w-0">
                        <div class="font-medium" style="color:var(--ink)">{{ c.name_en || c.name_ar }}</div>
                        <div class="text-xs" style="color:var(--muted)">
                            <span dir="rtl">{{ c.name_ar }}</span> · {{ c.items_count }} items
                        </div>
                    </div>
                    <StatusBadge :value="c.is_active" :label="c.is_active ? t('common.active') : t('common.inactive')" />
                    <button class="switch" :class="{ on: c.is_active }" @click="toggle(c)"></button>
                    <button @click="openEdit(c)" class="text-sm underline" style="color:var(--body)">{{ t('common.edit') }}</button>
                    <button @click="remove(c)" class="text-sm underline" style="color:#c0392b">{{ t('common.delete') }}</button>
                </li>
            </ul>
        </div>

        <Modal v-if="showModal" :title="editing ? t('common.edit') : t('common.create')" @close="showModal = false">
            <div class="space-y-4">
                <label class="block"><span class="label">{{ t('common.name_en') }}</span>
                    <input v-model="form.name_en" class="input" />
                    <FormError :errors="errors" field="name_en" /></label>
                <label class="block" dir="rtl"><span class="label">{{ t('common.name_ar') }}</span>
                    <input v-model="form.name_ar" class="input" />
                    <FormError :errors="errors" field="name_ar" /></label>
                <label class="block"><span class="label">{{ t('common.description_en') }}</span>
                    <textarea v-model="form.description_en" rows="2" class="input"></textarea></label>
                <ImageUploader v-model="form.image_url" folder="categories" label="Category image" />
                <label class="flex items-center gap-2 text-sm" style="color:var(--body)">
                    <button type="button" class="switch" :class="{ on: form.is_active }" @click="form.is_active = !form.is_active"></button>
                    {{ t('common.active') }}
                </label>
                <div class="flex justify-end gap-2 pt-2">
                    <button @click="showModal = false" class="btn btn-ghost">{{ t('common.cancel') }}</button>
                    <button @click="save" class="btn btn-accent">{{ t('common.save') }}</button>
                </div>
            </div>
        </Modal>
    </div>
</template>
