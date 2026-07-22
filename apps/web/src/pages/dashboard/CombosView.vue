<script setup>
import { ref, reactive, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import { withMinDuration } from '../../lib/minLoading.js'
import { useAuth } from '@xorder/api-client/auth.js'
import { currencyLabel } from '../../lib/currency.js'
import { pickLocalized } from '@xorder/ui/localize.js'
import Modal from '@xorder/ui/Modal.vue'
import ListSkeleton from '@xorder/ui/ListSkeleton.vue'
import StatusBadge from '@xorder/ui/StatusBadge.vue'
import ImageUploader from '@xorder/ui/ImageUploader.vue'
import FormError from '@xorder/ui/FormError.vue'
import Icon from '@xorder/ui/Icon.vue'
import { confirm } from '@xorder/ui/confirm.js'
import { useMenuLang } from '../../lib/menuLang.js'

const { t, locale } = useI18n()
const { langs, bilingual } = useMenuLang()
const auth = useAuth()
const cur = () => currencyLabel(auth.restaurant?.currency, locale.value, auth.restaurant?.currency_symbol)
const rows = ref([])
const menuItems = ref([])
const loading = ref(true)
const saving = ref(false)
const showModal = ref(false)
const editing = ref(null)
const errors = ref({})
const blank = () => ({ name_en: '', name_ar: '', description_en: '', description_ar: '', image_url: '', base_price: '', is_active: true, groups: [] })
const form = reactive(blank())

async function load() {
    loading.value = true
    try {
        const [cb, it] = await withMinDuration(Promise.all([
            api.get('api/dashboard/combos'),
            api.get('api/dashboard/items'),
        ]))
        rows.value = cb.data.data
        menuItems.value = it.data.data
    } finally { loading.value = false }
}
onMounted(load)

const itemName = (id) => {
    const it = menuItems.value.find(i => i.id === id)
    return it ? pickLocalized(it, 'name', locale.value) : '—'
}
const comboName = (c) => pickLocalized(c, 'name', locale.value)

function addGroup() { form.groups.push({ name_en: '', name_ar: '', max_select: 1, items: [] }) }
function removeGroup(i) { form.groups.splice(i, 1) }
function addItem(g) { g.items.push({ menu_item_id: menuItems.value[0]?.id || '', extra_price: '' }) }
function removeItem(g, i) { g.items.splice(i, 1) }

function openCreate() {
    editing.value = null; errors.value = {}
    Object.assign(form, blank())
    showModal.value = true
}
function openEdit(c) {
    editing.value = c; errors.value = {}
    Object.assign(form, blank(), {
        name_en: c.name_en || '', name_ar: c.name_ar || '',
        description_en: c.description_en || '', description_ar: c.description_ar || '',
        image_url: c.image_url || '', base_price: c.base_price, is_active: c.is_active,
        groups: (c.groups || []).map(g => ({
            name_en: g.name_en || '', name_ar: g.name_ar || '', max_select: g.max_select || 1,
            items: (g.items || []).map(it => ({ menu_item_id: it.menu_item_id, extra_price: it.extra_price ?? '' })),
        })),
    })
    showModal.value = true
}
async function save() {
    if (saving.value) return // guard against double-submit (double-click)
    saving.value = true
    errors.value = {}
    const payload = {
        ...form,
        base_price: form.base_price === '' ? 0 : Number(form.base_price),
        groups: form.groups.map(g => ({
            name_en: g.name_en, name_ar: g.name_ar, max_select: Number(g.max_select) || 1,
            items: g.items.filter(it => it.menu_item_id).map(it => ({
                menu_item_id: Number(it.menu_item_id),
                extra_price: it.extra_price === '' ? 0 : Number(it.extra_price),
            })),
        })),
    }
    try {
        await ensureCsrf()
        if (editing.value) await api.put(`api/dashboard/combos/${editing.value.id}`, payload)
        else await api.post('api/dashboard/combos', payload)
        showModal.value = false
        await load()
    } catch (err) { errors.value = err.response?.data?.errors || {} }
    finally { saving.value = false }
}
async function toggle(c) {
    await ensureCsrf()
    await api.patch(`api/dashboard/combos/${c.id}/status`, { is_active: !c.is_active })
    c.is_active = !c.is_active
}
async function remove(c) {
    const ok = await confirm({ title: t('common.delete'), message: t('common.confirm_delete'), confirmText: t('common.delete'), cancelText: t('common.cancel'), danger: true })
    if (!ok) return
    try { await ensureCsrf(); await api.delete(`api/dashboard/combos/${c.id}`); await load() }
    catch (err) { alert(t('common.delete_failed')) }
}
</script>

<template>
    <div class="space-y-5">
        <div class="flex items-start justify-between gap-3">
            <div>
                <h1 class="page-title">{{ t('nav.combos') }}</h1>
                <p class="page-sub">{{ t('combo.subtitle', { count: rows.length }) }}</p>
            </div>
            <button v-if="!auth.isReadOnly" @click="openCreate" class="btn btn-accent"><Icon name="plus" :size="16" />{{ t('common.create') }}</button>
        </div>

        <div class="card overflow-hidden">
            <ListSkeleton v-if="loading" />
            <div v-else-if="!rows.length" class="p-8 text-center" style="color:var(--muted)">{{ t('combo.none') }}</div>
            <ul v-else>
                <li v-for="c in rows" :key="c.id" class="flex items-center gap-3 px-5 py-3 border-t first:border-t-0" style="border-color:var(--line)">
                    <img v-if="c.image_url" :src="c.image_url" class="h-11 w-11 rounded-lg object-cover" />
                    <div v-else class="h-11 w-11 rounded-lg grid place-items-center flex-shrink-0" style="background:var(--accent-soft);color:var(--accent)"><Icon name="star" :size="18" /></div>
                    <div class="flex-1 min-w-0">
                        <div class="font-medium" style="color:var(--ink)">{{ comboName(c) }}</div>
                        <div class="text-xs" style="color:var(--muted)">{{ t('combo.from') }} {{ c.base_price }} {{ cur() }} · {{ (c.groups || []).length }} {{ t('combo.groups') }}</div>
                    </div>
                    <StatusBadge :value="c.is_active" :label="c.is_active ? t('common.active') : t('common.inactive')" />
                    <button v-if="!auth.isReadOnly" class="switch" :class="{ on: c.is_active }" @click="toggle(c)"></button>
                    <button v-if="!auth.isReadOnly" @click="openEdit(c)" class="icon-btn" :title="t('common.edit')"><Icon name="edit" :size="17" /></button>
                    <button v-if="!auth.isReadOnly" @click="remove(c)" class="icon-btn icon-btn-danger" :title="t('common.delete')"><Icon name="trash" :size="17" /></button>
                </li>
            </ul>
        </div>

        <Modal v-if="showModal" :title="editing ? t('common.edit') : t('nav.combos')" @close="showModal = false">
            <div class="space-y-4">
                <div class="grid grid-cols-1 gap-3" :class="{ 'sm:grid-cols-2': bilingual }">
                    <label v-for="lng in langs" :key="'n' + lng" class="block" :dir="lng === 'ar' ? 'rtl' : 'ltr'">
                        <span class="label">{{ bilingual ? t('common.name_' + lng) : t('common.name') }}</span>
                        <input v-model="form['name_' + lng]" class="input" />
                        <FormError :errors="errors" :field="'name_' + lng" /></label>
                </div>
                <label v-for="lng in langs" :key="'d' + lng" class="block" :dir="lng === 'ar' ? 'rtl' : 'ltr'">
                    <span class="label">{{ bilingual ? t('common.description_' + lng) : t('common.description') }}</span>
                    <textarea v-model="form['description_' + lng]" rows="2" class="input"></textarea></label>
                <label class="block" style="max-width:200px"><span class="label">{{ t('combo.base_price') }}<template v-if="cur()"> ({{ cur() }})</template></span>
                    <input v-model="form.base_price" type="number" step="0.01" min="0" class="input" />
                    <FormError :errors="errors" field="base_price" /></label>
                <ImageUploader v-model="form.image_url" folder="combos" :label="t('item.image')" />

                <!-- Groups builder -->
                <div class="pt-2 border-t" style="border-color:var(--line)">
                    <div class="flex items-center justify-between mb-2">
                        <span class="label">{{ t('combo.groups') }}</span>
                        <button type="button" class="btn btn-ghost btn-sm" @click="addGroup">+ {{ t('item.add_group') }}</button>
                    </div>
                    <p v-if="!form.groups.length" class="text-xs" style="color:var(--muted)">{{ t('combo.no_groups') }}</p>
                    <div v-for="(g, gi) in form.groups" :key="gi" class="rounded-xl p-3 mb-3" style="background:var(--page);border:1px solid var(--line)">
                        <div class="grid grid-cols-1 gap-2" :class="{ 'sm:grid-cols-2': bilingual }">
                            <input v-for="lng in langs" :key="'g' + lng" v-model="g['name_' + lng]" class="input"
                                :dir="lng === 'ar' ? 'rtl' : 'ltr'" :placeholder="lng === 'ar' ? t('item.group_name_ar') : t('combo.group_name_en')" />
                        </div>
                        <div class="flex items-center gap-4 flex-wrap mt-2">
                            <label class="flex items-center gap-2 text-xs" style="color:var(--body)">
                                {{ t('item.max_select') }}
                                <input v-model.number="g.max_select" type="number" min="1" class="input" style="width:64px;padding:5px 8px" />
                            </label>
                            <button type="button" class="icon-btn icon-btn-danger ms-auto" :title="t('common.delete')" @click="removeGroup(gi)"><Icon name="trash" :size="16" /></button>
                        </div>
                        <div class="mt-2 space-y-2">
                            <div v-for="(it, ii) in g.items" :key="ii" class="flex items-center gap-2">
                                <select v-model="it.menu_item_id" class="input flex-1">
                                    <option v-for="mi in menuItems" :key="mi.id" :value="mi.id">{{ itemName(mi.id) }}</option>
                                </select>
                                <input v-model="it.extra_price" type="number" step="0.01" min="0" class="input" style="width:90px" :placeholder="'+0'" />
                                <button type="button" class="icon-btn icon-btn-danger" :title="t('common.delete')" @click="removeItem(g, ii)"><Icon name="close" :size="16" /></button>
                            </div>
                            <button type="button" class="btn btn-ghost btn-sm" :disabled="!menuItems.length" @click="addItem(g)">+ {{ t('combo.add_item') }}</button>
                        </div>
                    </div>
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
        </Modal>
    </div>
</template>
