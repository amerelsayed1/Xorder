<script setup>
import { reactive, ref, computed, onMounted } from 'vue'
import { useRoute, useRouter, RouterLink } from 'vue-router'
import { useI18n } from 'vue-i18n'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import { useAuth } from '@xorder/api-client/auth.js'
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
function addGroup() { form.option_groups.push({ name_en: '', name_ar: '', is_required: false, is_variant: false, max_select: 1, options: [] }) }
function removeGroup(i) { form.option_groups.splice(i, 1) }
function addOption(g) { g.options.push({ name_en: '', name_ar: '', price: '' }) }
function removeOption(g, i) { g.options.splice(i, 1) }

function catName(id) {
    const c = categories.value.find(c => c.id === id)
    return c ? pickLocalized(c, 'name', locale.value) : ''
}

onMounted(async () => {
    try {
        const [cats, item] = await Promise.all([
            api.get('api/dashboard/categories'),
            isEdit.value ? api.get(`api/dashboard/items/${route.params.id}`) : Promise.resolve(null),
        ])
        categories.value = cats.data.data
        if (item) {
            const it = item.data.data
            Object.assign(form, {
                category_id: it.category_id, name_en: it.name_en || '', name_ar: it.name_ar || '',
                description_en: it.description_en || '', description_ar: it.description_ar || '',
                price: it.price, discounted_price: it.discounted_price || '', image_url: it.image_url || '',
                is_available: it.is_available, is_featured: it.is_featured,
                option_groups: (it.option_groups || []).map(g => ({
                    name_en: g.name_en || '', name_ar: g.name_ar || '',
                    is_required: !!g.is_required, is_variant: !!g.is_variant, max_select: g.max_select || 1,
                    options: (g.options || []).map(o => ({ name_en: o.name_en || '', name_ar: o.name_ar || '', price: o.price ?? '' })),
                })),
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
        option_groups: form.option_groups.map(g => ({
            name_en: g.name_en, name_ar: g.name_ar,
            is_required: g.is_variant ? true : g.is_required,
            is_variant: g.is_variant,
            max_select: g.is_variant ? 1 : (Number(g.max_select) || 1),
            options: g.options.map(o => ({ name_en: o.name_en, name_ar: o.name_ar, price: o.price === '' ? 0 : Number(o.price) })),
        })),
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
    <div class="max-w-2xl">
        <RouterLink :to="{ name: 'dashboard.items' }" class="text-sm" style="color:var(--muted)">{{ backArrow }} {{ t('common.back') }}</RouterLink>
        <h1 class="page-title my-3">{{ isEdit ? t('item.edit_item') : t('item.new_item') }}</h1>

        <div v-if="loading" class="card p-6 space-y-5">
            <div v-for="n in 4" :key="n" class="space-y-2.5">
                <Skeleton w="28%" h="13px" />
                <Skeleton w="100%" h="40px" rounded="10px" />
            </div>
        </div>

        <form v-else @submit.prevent="save" class="space-y-5">
            <div class="card p-6 space-y-4">
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
            </div>

            <!-- Option groups builder -->
            <div class="card p-6">
                <div class="flex items-center justify-between mb-2">
                    <span class="label" style="margin:0">{{ t('item.options') }}</span>
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
                            <button type="button" class="switch" :class="{ on: g.is_variant }" @click="g.is_variant = !g.is_variant"></button>
                            {{ t('item.variant') }}
                        </label>
                        <label v-if="!g.is_variant" class="flex items-center gap-2 text-xs" style="color:var(--body)">
                            <button type="button" class="switch" :class="{ on: g.is_required }" @click="g.is_required = !g.is_required"></button>
                            {{ t('item.required') }}
                        </label>
                        <label v-if="!g.is_variant" class="flex items-center gap-2 text-xs" style="color:var(--body)">
                            {{ t('item.max_select') }}
                            <input v-model.number="g.max_select" type="number" min="1" class="input" style="width:64px;padding:5px 8px" />
                        </label>
                        <button type="button" class="icon-btn icon-btn-danger ms-auto" :title="t('common.delete')" @click="removeGroup(gi)"><Icon name="trash" :size="16" /></button>
                    </div>
                    <p v-if="g.is_variant" class="text-xs mt-1" style="color:var(--muted)">{{ t('item.variant_hint') }}</p>
                    <div class="mt-2 space-y-2">
                        <div v-for="(o, oi) in g.options" :key="oi" class="flex items-center gap-2">
                            <input v-for="lng in langs" :key="'o' + lng" v-model="o['name_' + lng]" class="input flex-1"
                                :dir="lng === 'ar' ? 'rtl' : 'ltr'" :placeholder="t('item.option_' + lng)" />
                            <input v-model="o.price" type="number" step="0.01" min="0" class="input" style="width:90px" :placeholder="g.is_variant ? (cur || '0') : (cur || '+0')" />
                            <button type="button" class="icon-btn icon-btn-danger" :title="t('common.delete')" @click="removeOption(g, oi)"><Icon name="close" :size="16" /></button>
                        </div>
                        <button type="button" class="btn btn-ghost btn-sm" @click="addOption(g)">+ {{ t('item.add_option') }}</button>
                    </div>
                </div>
            </div>

            <div class="flex justify-end gap-2">
                <RouterLink :to="{ name: 'dashboard.items' }" class="btn btn-ghost">{{ t('common.cancel') }}</RouterLink>
                <button type="submit" :disabled="saving || auth.isReadOnly" class="btn btn-accent">
                    <Icon v-if="saving" name="loading" :size="16" class="animate-spin" />
                    {{ saving ? t('common.saving') : t('common.save') }}
                </button>
            </div>
        </form>
    </div>
</template>
