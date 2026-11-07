<script setup>
import { ref, reactive, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import { withMinDuration } from '../../lib/minLoading.js'
import { useAuth } from '@xorder/api-client/auth.js'
import { useCaps } from '../../lib/useCaps.js'
import { currencyLabel } from '../../lib/currency.js'
import { pickLocalized } from '@xorder/ui/localize.js'
import Modal from '@xorder/ui/Modal.vue'
import ListSkeleton from '@xorder/ui/ListSkeleton.vue'
import StatusBadge from '@xorder/ui/StatusBadge.vue'
import ImageUploader from '@xorder/ui/ImageUploader.vue'
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

function addGroup() { form.groups.push({ name_en: '', name_ar: '', max_select: 1, is_variant: false, items: [] }) }
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
            name_en: g.name_en || '', name_ar: g.name_ar || '', max_select: g.max_select || 1, is_variant: !!g.is_variant,
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
            name_en: g.name_en, name_ar: g.name_ar,
            max_select: g.is_variant ? 1 : (Number(g.max_select) || 1),
            is_variant: g.is_variant,
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
        <div class="flex flex-wrap items-end justify-between gap-4">
            <div class="min-w-0">
                <h1 class="page-title">{{ t('nav.combos') }}</h1>
                <p class="page-sub" style="color:var(--body)">{{ t('combo.subtitle', { count: rows.length }) }}</p>
            </div>
            <button v-if="canCreate" @click="openCreate" class="btn btn-accent head-btn"><Icon name="plus" :size="16" />{{ t('common.create') }}</button>
        </div>

        <div class="card overflow-hidden">
            <ListSkeleton v-if="loading" />

            <!-- No combos yet: one sentence and the primary action. -->
            <div v-else-if="!rows.length" class="empty-card">
                <span class="empty-ico"><Icon name="star" :size="28" /></span>
                <p class="empty-body">{{ t('combo.none') }}</p>
                <div v-if="canCreate" class="empty-actions">
                    <button class="btn btn-accent head-btn" @click="openCreate"><Icon name="plus" :size="16" />{{ t('common.create') }}</button>
                </div>
            </div>

            <ul v-else>
                <li v-for="c in rows" :key="c.id" class="row" :class="{ 'row-off': !c.is_active }">
                    <div class="row-main">
                        <img v-if="c.image_url" :src="c.image_url" class="row-thumb" alt="" />
                        <div v-else class="row-thumb row-thumb-blank" aria-hidden="true"><Icon name="star" :size="18" /></div>
                        <div class="flex-1 min-w-0">
                            <div class="row-name truncate">{{ comboName(c) }}</div>
                            <div class="row-sub">
                                <span class="tabular">{{ t('combo.from') }} <strong class="row-price">{{ c.base_price }} {{ cur() }}</strong></span>
                                · {{ (c.groups || []).length }} {{ t('combo.groups') }}
                            </div>
                        </div>
                    </div>
                    <div class="row-controls">
                        <StatusBadge :value="c.is_active" :label="c.is_active ? t('common.active') : t('common.inactive')" />
                        <button v-if="canUpdate" class="switch" :class="{ on: c.is_active }" role="switch" :aria-checked="c.is_active"
                            :aria-label="comboName(c) + ' — ' + t('common.active')" @click="toggle(c)"></button>
                        <button v-if="canUpdate" @click="openEdit(c)" class="icon-btn" :title="t('common.edit')" :aria-label="t('common.edit')"><Icon name="edit" :size="17" /></button>
                        <button v-if="canDelete" @click="remove(c)" class="icon-btn icon-btn-danger" :title="t('common.delete')" :aria-label="t('common.delete')"><Icon name="trash" :size="17" /></button>
                    </div>
                </li>
            </ul>
        </div>

        <Modal v-if="showModal" :title="editing ? t('common.edit') : t('nav.combos')" @close="showModal = false">
            <div class="space-y-4">
                <!-- Basics: names and descriptions in each menu language, and whether it is on the menu. -->
                <section class="card p-4 space-y-4">
                    <h3 class="h-card">{{ t('item.section_names') }}</h3>
                    <div class="grid grid-cols-1 gap-3" :class="{ 'sm:grid-cols-2': bilingual }">
                        <label v-for="lng in langs" :key="'n' + lng" class="block min-w-0" :dir="lng === 'ar' ? 'rtl' : 'ltr'">
                            <span class="label">{{ bilingual ? t('common.name_' + lng) : t('common.name') }}</span>
                            <input v-model="form['name_' + lng]" class="input" />
                            <FormError :errors="errors" :field="'name_' + lng" /></label>
                    </div>
                    <label v-for="lng in langs" :key="'d' + lng" class="block" :dir="lng === 'ar' ? 'rtl' : 'ltr'">
                        <span class="label">{{ bilingual ? t('common.description_' + lng) : t('common.description') }}</span>
                        <textarea v-model="form['description_' + lng]" rows="2" class="input"></textarea></label>
                    <label class="toggle-inline">
                        <button type="button" class="switch" role="switch" :aria-checked="form.is_active" :class="{ on: form.is_active }" @click="form.is_active = !form.is_active"></button>
                        {{ t('common.active') }}
                    </label>
                </section>

                <section class="card p-4 space-y-3">
                    <h3 class="h-card">{{ t('item.section_pricing') }}</h3>
                    <label class="block" style="max-width:220px"><span class="label">{{ t('combo.base_price') }}<template v-if="cur()"> ({{ cur() }})</template></span>
                        <input v-model="form.base_price" type="number" step="0.01" min="0" class="input" inputmode="decimal" />
                        <FormError :errors="errors" field="base_price" /></label>
                </section>

                <section class="card p-4 space-y-3">
                    <h3 class="h-card">{{ t('common.image') }}</h3>
                    <ImageUploader v-model="form.image_url" folder="combos" :label="t('item.image')" />
                </section>

                <!-- Groups builder -->
                <section class="card p-4 space-y-3">
                    <div class="flex items-center justify-between gap-3 flex-wrap">
                        <h3 class="h-card">{{ t('combo.groups') }}</h3>
                        <button type="button" class="btn btn-ghost btn-sm touch" @click="addGroup">+ {{ t('item.add_group') }}</button>
                    </div>
                    <p v-if="!form.groups.length" class="help">{{ t('combo.no_groups') }}</p>
                    <div v-for="(g, gi) in form.groups" :key="gi" class="grp">
                        <div class="grid grid-cols-1 gap-2" :class="{ 'sm:grid-cols-2': bilingual }">
                            <input v-for="lng in langs" :key="'g' + lng" v-model="g['name_' + lng]" class="input grp-input"
                                :dir="lng === 'ar' ? 'rtl' : 'ltr'" :placeholder="lng === 'ar' ? t('item.group_name_ar') : t('combo.group_name_en')"
                                :aria-label="lng === 'ar' ? t('item.group_name_ar') : t('combo.group_name_en')" />
                        </div>
                        <div class="flex items-center gap-4 flex-wrap mt-3">
                            <label class="toggle-inline toggle-sm">
                                <button type="button" class="switch" role="switch" :aria-checked="g.is_variant" :class="{ on: g.is_variant }" @click="g.is_variant = !g.is_variant"></button>
                                {{ t('item.variant') }}
                            </label>
                            <label v-if="!g.is_variant" class="toggle-inline toggle-sm">
                                {{ t('item.max_select') }}
                                <input v-model.number="g.max_select" type="number" min="1" class="input max-input" />
                            </label>
                            <button type="button" class="icon-btn icon-btn-danger ms-auto" :title="t('common.delete')" :aria-label="t('common.delete')" @click="removeGroup(gi)"><Icon name="trash" :size="16" /></button>
                        </div>
                        <p v-if="g.is_variant" class="help mt-2">{{ t('item.variant_hint') }}</p>
                        <div class="mt-3 space-y-2">
                            <div v-for="(it, ii) in g.items" :key="ii" class="opt-row">
                                <select v-model="it.menu_item_id" class="input opt-name" :aria-label="t('combo.add_item')">
                                    <option v-for="mi in menuItems" :key="mi.id" :value="mi.id">{{ itemName(mi.id) }}</option>
                                </select>
                                <input v-model="it.extra_price" type="number" step="0.01" min="0" class="input opt-price" inputmode="decimal" :aria-label="t('item.price')" :placeholder="g.is_variant ? '0' : '+0'" />
                                <button type="button" class="icon-btn icon-btn-danger" :title="t('common.delete')" :aria-label="t('common.delete')" @click="removeItem(g, ii)"><Icon name="close" :size="16" /></button>
                            </div>
                            <button type="button" class="btn btn-ghost btn-sm touch" :disabled="!menuItems.length" @click="addItem(g)">+ {{ t('combo.add_item') }}</button>
                        </div>
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
.tabular { font-variant-numeric: tabular-nums; }

/* List rows: image + name/price on one side, state + actions on the other.
   On a phone the controls wrap under the name instead of squeezing it. */
.row { display: flex; flex-wrap: wrap; align-items: center; gap: 8px 16px; padding: 12px 20px; min-height: 68px;
    border-top: 1px solid var(--line); transition: background .15s; }
.row:first-child { border-top: 0; }
.row:hover { background: var(--page); }
.row-main { display: flex; align-items: center; gap: 12px; flex: 1 1 220px; min-width: 0; }
.row-thumb { width: 48px; height: 48px; border-radius: 10px; object-fit: cover; flex: none; }
.row-thumb-blank { display: grid; place-items: center; background: var(--accent-soft); color: var(--p-primary-700); }
.row-name { font-size: 15.5px; font-weight: 600; color: var(--ink); }
.row-sub { font-size: 13.5px; color: var(--body); }
.row-price { color: var(--ink); font-weight: 700; }
.row-off .row-main { opacity: .7; }
.row-controls { display: flex; align-items: center; gap: 8px; flex: none; margin-inline-start: auto; }
@media (max-width: 639px) {
    .row { padding: 10px 12px; }
    .row-controls { width: 100%; justify-content: flex-end; }
    .row-controls .icon-btn { width: 44px; height: 44px; }
}

/* Empty state */
.empty-card { padding: 56px 24px; display: flex; flex-direction: column; align-items: center; text-align: center; gap: 8px; }
.empty-ico { width: 60px; height: 60px; border-radius: 16px; display: grid; place-items: center;
    background: var(--accent-soft); color: var(--p-primary-700); margin-bottom: 8px; }
.empty-body { font-size: 15px; color: var(--body); max-width: 420px; margin: 0; }
.empty-actions { display: flex; flex-wrap: wrap; justify-content: center; gap: 10px; margin-top: 12px; }

/* Form */
.toggle-inline { display: flex; align-items: center; gap: 10px; font-size: 14.5px; color: var(--ink); }
.toggle-sm { font-size: 14px; color: var(--body); gap: 8px; }
.max-input { width: 72px; margin-top: 0; padding: 6px 8px; }
.grp { border-radius: 12px; padding: 14px; background: var(--page); border: 1px solid var(--line); }
.grp-input { margin-top: 0; }
.opt-row { display: flex; flex-wrap: wrap; align-items: center; gap: 8px; }
.opt-row .input { margin-top: 0; }
.opt-name { flex: 1 1 160px; min-width: 0; }
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
