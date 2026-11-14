<script setup>
import { reactive, ref, computed, onMounted, watch } from 'vue'
import { useRoute, useRouter, RouterLink } from 'vue-router'
import { useI18n } from 'vue-i18n'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import { useAuth } from '@xorder/api-client/auth.js'
import { useCaps } from '../../lib/useCaps.js'
import { currencyLabel } from '../../lib/currency.js'
import { pickLocalized } from '@xorder/ui/localize.js'
import ImageUploader from '@xorder/ui/ImageUploader.vue'
import FormError from '@xorder/ui/FormError.vue'
import Icon from '@xorder/ui/Icon.vue'
import Skeleton from '@xorder/ui/Skeleton.vue'
import { useMenuLang } from '../../lib/menuLang.js'

const route = useRoute()
const router = useRouter()
const { t, locale } = useI18n()
const { langs, bilingual } = useMenuLang()
const auth = useAuth()
// Saving is a create on a new item and an update on an existing one.
const { canCreate, canUpdate } = useCaps('menu')

const isEdit = computed(() => !!route.params.id)
const backArrow = computed(() => locale.value === 'ar' ? '→' : '←')
const cur = computed(() => currencyLabel(auth.restaurant?.currency, locale.value, auth.restaurant?.currency_symbol))

const categories = ref([])
const loading = ref(true)
const saving = ref(false)
const errors = ref({})
const form = reactive({
    category_id: '', name_en: '', name_ar: '', description_en: '', description_ar: '',
    price: '', discounted_price: '', image_url: '', is_available: true, is_featured: false,
    option_groups: [],
})

// --- option-group builder helpers ---
// Each entry carries a `ref`: 'inline' groups are typed for this item; 'shared'
// entries reference a reusable group from the extras library (edited elsewhere).
function addGroup() { form.option_groups.push({ ref: 'inline', name_en: '', name_ar: '', is_required: false, is_variant: false, max_select: 1, options: [] }) }
function removeGroup(i) { form.option_groups.splice(i, 1) }
function addOption(g) { g.options.push({ name_en: '', name_ar: '', price: '', discounted_price: '' }) }
function removeOption(g, i) { g.options.splice(i, 1) }

// --- variant (size) pricing ---
// A size group takes pricing over from the item: the chosen option REPLACES the
// item price, and the menu pre-selects the first option. So the first size of
// the first size group is the item's real, advertised price — reordering the
// sizes changes it, which is what the hint under the group warns about.
const variantGroup = computed(() => form.option_groups.find(g => g.is_variant))
const defaultSize = computed(() => (variantGroup.value?.options || []).find(o => o.is_available !== false) || null)

// Read-only look for the two price fields once sizes own the pricing.
const derivedInput = 'background:var(--page);color:var(--muted);cursor:not-allowed'

// Mirror that default into the read-only price fields as the owner types, so
// the form quotes what the diner pays without waiting for a round trip. The
// backend re-derives the same figure on save (VariantPricingService), which is
// what keeps it right when a shared library group changes later.
watch(defaultSize, (o) => {
    if (!o) return // no sizes → the item's own price stands, leave it alone
    // Match how save() serialises an option: a blank price is stored as 0.
    form.price = o.price === '' || o.price == null ? 0 : o.price
    form.discounted_price = o.discounted_price ?? ''
}, { deep: true, immediate: true })

// Flipping a group to "sizes" hands pricing to its options, so carry the price
// the owner already typed into the first size — otherwise it silently vanishes
// the moment the field above turns read-only.
function toggleVariant(g) {
    const wasFirst = !variantGroup.value
    g.is_variant = !g.is_variant
    if (!g.is_variant || !wasFirst) return

    if (!g.options.length) addOption(g)
    const first = g.options[0]
    if (first.price === '' || first.price == null) {
        first.price = form.price
        first.discounted_price = form.discounted_price
    }
}

// Validation errors on a nested option come back keyed by path
// (option_groups.0.options.1.discounted_price). Surface the first one under the
// group it belongs to, so a rejected sale price isn't a silent failed save.
function groupOptionError(gi) {
    const prefix = `option_groups.${gi}.options.`
    const key = Object.keys(errors.value).find(k => k.startsWith(prefix))
    return key ? errors.value[key][0] : ''
}

// --- shared extras library ---
const library = ref([])
const pickId = ref('')
// Library groups a diner would pick per item — excludes ones already attached
// and ones that auto-apply by category / to all items (managed under Extras).
const availableLibrary = computed(() => {
    const used = new Set(form.option_groups.filter(g => g.ref === 'shared').map(g => g.option_group_id))
    return library.value.filter(g => !used.has(g.id) && (g.apply_scope || 'items') === 'items')
})
function libLabel(g) { return pickLocalized(g, 'name', locale.value) || (locale.value === 'ar' ? g.name_en : g.name_ar) || '' }
function addFromLibrary() {
    const g = library.value.find(x => x.id === Number(pickId.value))
    if (!g) return
    // Snapshot name + options for read-only display; only the id is sent on save.
    form.option_groups.push({
        ref: 'shared', option_group_id: g.id,
        name_en: g.name_en || '', name_ar: g.name_ar || '',
        is_required: !!g.is_required, is_variant: !!g.is_variant, max_select: g.max_select || 1,
        // Sale price + availability come along too: for a size group they decide
        // which option is the default and what it costs (see defaultSize).
        options: (g.options || []).map(o => ({
            name_en: o.name_en || '', name_ar: o.name_ar || '',
            price: o.price ?? '', discounted_price: o.discounted_price ?? '', is_available: o.is_available !== false,
        })),
    })
    pickId.value = ''
}

function catName(id) {
    const c = categories.value.find(c => c.id === id)
    return c ? pickLocalized(c, 'name', locale.value) : ''
}

onMounted(async () => {
    try {
        const [cats, lib, item] = await Promise.all([
            api.get('api/dashboard/categories'),
            api.get('api/dashboard/option-groups'),
            isEdit.value ? api.get(`api/dashboard/items/${route.params.id}`) : Promise.resolve(null),
        ])
        categories.value = cats.data.data
        library.value = lib.data.data
        if (item) {
            const it = item.data.data
            Object.assign(form, {
                category_id: it.category_id, name_en: it.name_en || '', name_ar: it.name_ar || '',
                description_en: it.description_en || '', description_ar: it.description_ar || '',
                price: it.price, discounted_price: it.discounted_price || '', image_url: it.image_url || '',
                is_available: it.is_available, is_featured: it.is_featured,
                // A global group comes back with is_global=true → a library reference;
                // everything else is an inline group typed on this item.
                option_groups: (it.option_groups || []).map(g => g.is_global
                    ? {
                        ref: 'shared', option_group_id: g.id,
                        name_en: g.name_en || '', name_ar: g.name_ar || '',
                        is_required: !!g.is_required, is_variant: !!g.is_variant, max_select: g.max_select || 1,
                        options: (g.options || []).map(o => ({
                            name_en: o.name_en || '', name_ar: o.name_ar || '',
                            price: o.price ?? '', discounted_price: o.discounted_price ?? '', is_available: o.is_available !== false,
                        })),
                    }
                    : {
                        ref: 'inline', name_en: g.name_en || '', name_ar: g.name_ar || '',
                        is_required: !!g.is_required, is_variant: !!g.is_variant, max_select: g.max_select || 1,
                        options: (g.options || []).map(o => ({ name_en: o.name_en || '', name_ar: o.name_ar || '', price: o.price ?? '', discounted_price: o.discounted_price ?? '' })),
                    }),
            })
        } else {
            form.category_id = categories.value[0]?.id || ''
        }
    } catch (e) {
        console.error('Failed to load item form', e)
    } finally {
        loading.value = false
    }
})

function backToList() { router.push({ name: 'dashboard.items' }) }

async function save() {
    if (saving.value) return // guard against double-submit (double-click)
    saving.value = true
    errors.value = {}
    const payload = {
        ...form,
        discounted_price: form.discounted_price === '' ? null : form.discounted_price,
        // Shared entries send only a reference; inline entries send their full
        // definition. Array order is the display order for both (see backend).
        option_groups: form.option_groups.map(g => g.ref === 'shared'
            ? { ref: 'shared', option_group_id: g.option_group_id }
            : {
                ref: 'inline', name_en: g.name_en, name_ar: g.name_ar,
                is_required: g.is_variant ? true : g.is_required,
                is_variant: g.is_variant,
                max_select: g.is_variant ? 1 : (Number(g.max_select) || 1),
                options: g.options.map(o => ({
                    name_en: o.name_en, name_ar: o.name_ar,
                    price: o.price === '' ? 0 : Number(o.price),
                    // Only a size/variant option can carry a sale price — the
                    // backend drops it on add-on groups anyway, so don't send
                    // a stale value left behind by toggling the group off.
                    discounted_price: g.is_variant && o.discounted_price !== '' && o.discounted_price != null
                        ? Number(o.discounted_price)
                        : null,
                })),
            }),
    }
    try {
        await ensureCsrf()
        if (isEdit.value) await api.put(`api/dashboard/items/${route.params.id}`, payload)
        else await api.post('api/dashboard/items', payload)
        backToList()
    } catch (err) { errors.value = err.response?.data?.errors || {} }
    finally { saving.value = false }
}
</script>

<template>
    <div class="form-page">
        <RouterLink :to="{ name: 'dashboard.items' }" class="back-link">{{ backArrow }} {{ t('common.back') }}</RouterLink>
        <h1 class="page-title my-3">{{ isEdit ? t('item.edit_item') : t('item.new_item') }}</h1>

        <!-- Skeleton mirrors the final layout: basics, names, pricing, image, options. -->
        <div v-if="loading" class="space-y-5">
            <div v-for="n in 4" :key="n" class="card p-5 space-y-4">
                <Skeleton w="30%" h="16px" />
                <Skeleton w="100%" h="42px" rounded="10px" />
                <Skeleton w="100%" h="42px" rounded="10px" />
            </div>
        </div>

        <form v-else @submit.prevent="save" class="space-y-5">
            <!-- Basics: where it lives and whether the menu shows it. -->
            <section class="card p-5 space-y-4" aria-labelledby="if-basics">
                <h2 id="if-basics" class="h-card">{{ t('item.section_basics') }}</h2>
                <label class="block"><span class="label">{{ t('item.category') }}</span>
                    <select v-model="form.category_id" class="input">
                        <option v-for="c in categories" :key="c.id" :value="c.id">{{ catName(c.id) }}</option>
                    </select>
                    <FormError :errors="errors" field="category_id" /></label>
                <div class="toggle-row">
                    <label class="toggle-tile">
                        <button type="button" class="switch" role="switch" :aria-checked="form.is_available" :class="{ on: form.is_available }" @click="form.is_available = !form.is_available"></button>
                        <span>{{ t('common.available') }}</span>
                    </label>
                    <label class="toggle-tile">
                        <button type="button" class="star" :class="{ on: form.is_featured }" :aria-pressed="form.is_featured" @click="form.is_featured = !form.is_featured">★</button>
                        <span>{{ t('common.featured') }}</span>
                    </label>
                </div>
            </section>

            <!-- Name and description in each menu language. dir goes on the field,
                 not the label: the label text is in the UI language and must keep
                 the page direction. -->
            <section class="card p-5 space-y-4" aria-labelledby="if-names">
                <h2 id="if-names" class="h-card">{{ t('item.section_names') }}</h2>
                <div class="grid grid-cols-1 gap-4" :class="{ 'sm:grid-cols-2': bilingual }">
                    <label v-for="lng in langs" :key="'n' + lng" class="block min-w-0">
                        <span class="label">{{ bilingual ? t('common.name_' + lng) : t('common.name') }}</span>
                        <input v-model="form['name_' + lng]" class="input" :dir="lng === 'ar' ? 'rtl' : 'ltr'" />
                        <FormError :errors="errors" :field="'name_' + lng" /></label>
                </div>
                <div class="grid grid-cols-1 gap-4" :class="{ 'sm:grid-cols-2': bilingual }">
                    <label v-for="lng in langs" :key="'d' + lng" class="block min-w-0">
                        <span class="label">{{ bilingual ? t('common.description_' + lng) : t('common.description') }}</span>
                        <textarea v-model="form['description_' + lng]" rows="3" class="input" :dir="lng === 'ar' ? 'rtl' : 'ltr'"></textarea></label>
                </div>
            </section>

            <!-- Once the item has a size group these two are no longer the
                 owner's to set: they mirror the default (first) size, which
                 is what the menu card quotes and what an untouched add to
                 cart charges. Read-only rather than hidden so the figure
                 stays visible where managers expect to find it. -->
            <section class="card p-5 space-y-4" aria-labelledby="if-pricing">
                <h2 id="if-pricing" class="h-card">{{ t('item.section_pricing') }}</h2>
                <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
                    <label class="block"><span class="label">{{ t('item.price') }}<template v-if="cur"> ({{ cur }})</template></span>
                        <input v-model="form.price" type="number" step="0.01" min="0" class="input" inputmode="decimal"
                            :readonly="!!variantGroup" :style="variantGroup ? derivedInput : null" />
                        <FormError :errors="errors" field="price" /></label>
                    <label class="block"><span class="label">{{ t('item.discounted_price') }}</span>
                        <input v-model="form.discounted_price" type="number" step="0.01" min="0" class="input" inputmode="decimal"
                            :readonly="!!variantGroup" :style="variantGroup ? derivedInput : null" />
                        <FormError :errors="errors" field="discounted_price" /></label>
                </div>
                <p v-if="variantGroup" class="help">
                    {{ t('item.priced_by_size') }}
                </p>
            </section>

            <section class="card p-5 space-y-4" aria-labelledby="if-image">
                <h2 id="if-image" class="h-card">{{ t('common.image') }}</h2>
                <ImageUploader v-model="form.image_url" folder="items" :label="t('item.image')" />
            </section>

            <!-- Option groups builder -->
            <section class="card p-5 space-y-4" aria-labelledby="if-options">
                <div class="flex items-center justify-between gap-3 flex-wrap">
                    <h2 id="if-options" class="h-card">{{ t('item.options') }}</h2>
                    <div class="flex items-center gap-2 flex-wrap">
                        <!-- Attach a reusable group from the shared library -->
                        <select v-model="pickId" @change="addFromLibrary" class="input lib-select" :aria-label="t('item.add_from_library')">
                            <option value="">+ {{ t('item.add_from_library') }}</option>
                            <option v-for="g in availableLibrary" :key="g.id" :value="g.id">{{ libLabel(g) }}</option>
                        </select>
                        <button type="button" class="btn btn-ghost btn-sm touch" @click="addGroup">+ {{ t('item.add_group') }}</button>
                    </div>
                </div>
                <p v-if="!form.option_groups.length" class="help">{{ t('item.no_options') }}</p>

                <div class="space-y-3">
                <template v-for="(g, gi) in form.option_groups" :key="gi">
                    <!-- Shared library reference: read-only, edited under Extras -->
                    <div v-if="g.ref === 'shared'" class="grp grp-shared">
                        <div class="flex items-center gap-2">
                            <Icon name="link" :size="15" class="grp-link-ico" />
                            <div class="flex-1 min-w-0">
                                <div class="font-medium truncate" style="color:var(--ink)" :dir="locale === 'ar' ? 'rtl' : 'ltr'">{{ libLabel(g) }}</div>
                                <div class="text-xs" style="color:var(--body)">
                                    <span class="me-2 font-semibold" style="color:var(--p-primary-800)">{{ t('item.from_library') }}</span>
                                    <span>{{ (g.options || []).map(o => pickLocalized(o, 'name', locale) || o.name_en || o.name_ar).filter(Boolean).join('، ') }}</span>
                                </div>
                            </div>
                            <span v-if="g.is_variant" class="chip">{{ t('item.variant') }}</span>
                            <button type="button" class="icon-btn icon-btn-danger" :title="t('common.delete')" :aria-label="t('common.delete')" @click="removeGroup(gi)"><Icon name="close" :size="16" /></button>
                        </div>
                    </div>

                    <!-- Inline group: typed for this item only -->
                    <div v-else class="grp">
                        <div class="grid grid-cols-1 gap-2" :class="{ 'sm:grid-cols-2': bilingual }">
                            <input v-for="lng in langs" :key="'g' + lng" v-model="g['name_' + lng]" class="input grp-input"
                                :dir="lng === 'ar' ? 'rtl' : 'ltr'" :placeholder="t('item.group_name_' + lng)" :aria-label="t('item.group_name_' + lng)" />
                        </div>
                        <div class="flex items-center gap-4 flex-wrap mt-3">
                            <label class="toggle-inline">
                                <button type="button" class="switch" role="switch" :aria-checked="g.is_variant" :class="{ on: g.is_variant }" @click="toggleVariant(g)"></button>
                                {{ t('item.variant') }}
                            </label>
                            <label v-if="!g.is_variant" class="toggle-inline">
                                <button type="button" class="switch" role="switch" :aria-checked="g.is_required" :class="{ on: g.is_required }" @click="g.is_required = !g.is_required"></button>
                                {{ t('item.required') }}
                            </label>
                            <label v-if="!g.is_variant" class="toggle-inline">
                                {{ t('item.max_select') }}
                                <input v-model.number="g.max_select" type="number" min="1" class="input max-input" />
                            </label>
                            <button type="button" class="icon-btn icon-btn-danger ms-auto" :title="t('common.delete')" :aria-label="t('common.delete')" @click="removeGroup(gi)"><Icon name="trash" :size="16" /></button>
                        </div>
                        <p v-if="g.is_variant" class="help mt-2">{{ t('item.variant_hint') }}</p>
                        <div class="mt-3 space-y-2">
                            <div v-for="(o, oi) in g.options" :key="oi" class="opt-row">
                                <input v-for="lng in langs" :key="'o' + lng" v-model="o['name_' + lng]" class="input opt-name"
                                    :dir="lng === 'ar' ? 'rtl' : 'ltr'" :placeholder="t('item.option_' + lng)" :aria-label="t('item.option_' + lng)" />
                                <input v-model="o.price" type="number" step="0.01" min="0" class="input opt-price" inputmode="decimal" :placeholder="g.is_variant ? (cur || '0') : (cur || '+0')" :aria-label="t('item.price')" />
                                <!-- Sale price per size. Only a variant option gets
                                     one: there the option IS the item price, so a
                                     discount is meaningful. An add-on price is a
                                     delta, so discounting it makes no sense. -->
                                <input v-if="g.is_variant" v-model="o.discounted_price" type="number" step="0.01" min="0" inputmode="decimal"
                                    class="input opt-price" :placeholder="t('item.option_discount')" :aria-label="t('item.option_discount')" :title="t('item.option_discount_hint')" />
                                <!-- The size the menu pre-selects, and therefore
                                     the one the item's price mirrors. -->
                                <span v-if="o === defaultSize" class="chip whitespace-nowrap">{{ t('item.default_size') }}</span>
                                <button type="button" class="icon-btn icon-btn-danger" :title="t('common.delete')" :aria-label="t('common.delete')" @click="removeOption(g, oi)"><Icon name="close" :size="16" /></button>
                            </div>
                            <p v-if="groupOptionError(gi)" class="text-xs text-red-600 mt-1">{{ groupOptionError(gi) }}</p>
                            <button type="button" class="btn btn-ghost btn-sm touch" @click="addOption(g)">+ {{ t('item.add_option') }}</button>
                        </div>
                    </div>
                </template>
                </div>

                <RouterLink :to="{ name: 'dashboard.extras' }" class="manage-link">{{ t('item.manage_library') }} <span class="dir-arrow" aria-hidden="true">→</span></RouterLink>
            </section>

            <!-- Separate action row, pinned to the bottom edge while the form scrolls. -->
            <div class="action-bar">
                <RouterLink :to="{ name: 'dashboard.items' }" class="btn btn-ghost action-btn">{{ t('common.cancel') }}</RouterLink>
                <button type="submit" :disabled="saving || (isEdit ? !canUpdate : !canCreate)" class="btn btn-accent action-btn">
                    <Icon v-if="saving" name="loading" :size="16" class="animate-spin" />
                    {{ saving ? t('common.saving') : t('common.save') }}
                </button>
            </div>
        </form>
    </div>
</template>

<style scoped>
/* Colours come from the shared theme variables and the PrimeVue primary scale;
   no new hex values. */
.form-page { max-width: 48rem; }
.back-link { display: inline-block; font-size: 14.5px; color: var(--body); padding-block: 4px; }
.back-link:hover { color: var(--ink); text-decoration: underline; }
.help { font-size: 13.5px; color: var(--body); margin: 0; }
.touch { min-height: 40px; }

/* Read-only price fields (priced by size) stay readable, not greyed out. */
.input[readonly] { color: var(--body) !important; }

/* Availability / featured as two big tap targets */
.toggle-row { display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: 10px; }
.toggle-tile {
    display: flex; align-items: center; gap: 12px; min-height: 52px; padding: 0 14px;
    border: 1px solid var(--line); border-radius: 12px; background: var(--page);
    font-size: 15px; font-weight: 500; color: var(--ink); cursor: pointer;
}
.toggle-tile:hover { border-color: var(--muted); }
.toggle-inline { display: flex; align-items: center; gap: 8px; font-size: 14px; color: var(--body); }
.star { min-width: 30px; min-height: 30px; }

/* Option groups */
.lib-select { width: auto; min-width: 170px; margin-top: 0; padding-block: 8px; }
.grp { border-radius: 12px; padding: 14px; background: var(--page); border: 1px solid var(--line); }
.grp-shared { background: var(--accent-soft); border-color: var(--p-primary-300); }
.grp-link-ico { flex: none; color: var(--p-primary-700); }
.grp-input { margin-top: 0; }
.max-input { width: 72px; margin-top: 0; padding: 6px 8px; }
.chip { font-size: 12.5px; font-weight: 600; padding: 2px 10px; border-radius: 999px; background: var(--card); color: var(--p-primary-800); }
.opt-row { display: flex; flex-wrap: wrap; align-items: center; gap: 8px; }
.opt-row .input { margin-top: 0; }
.opt-name { flex: 1 1 140px; min-width: 0; }
.opt-price { flex: 0 0 96px; width: 96px; }
.manage-link { display: inline-block; font-size: 14px; font-weight: 500; color: var(--p-primary-700); }
.manage-link:hover { text-decoration: underline; }
[dir="rtl"] .dir-arrow { display: inline-block; transform: scaleX(-1); }

/* Action row */
.action-bar {
    position: sticky; bottom: 0; z-index: 5;
    display: flex; justify-content: flex-end; gap: 10px;
    padding: 12px 16px; border-radius: 15px;
    background: var(--card); border: 1px solid var(--line);
    box-shadow: 0 -4px 16px rgba(0, 0, 0, .06);
}
.action-btn { min-height: 46px; padding-inline: 22px; justify-content: center; }
@media (max-width: 639px) {
    .action-bar { padding: 10px 12px; }
    .action-btn { flex: 1 1 0; justify-content: center; }
}
</style>
