<script setup>
import { reactive, ref, computed, onMounted } from 'vue'
import { useRoute, useRouter, RouterLink } from 'vue-router'
import { useI18n } from 'vue-i18n'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import FormError from '@xorder/ui/FormError.vue'

const route = useRoute()
const router = useRouter()
const { t, locale } = useI18n()

const isEdit = computed(() => !!route.params.id)
const backArrow = computed(() => locale.value === 'ar' ? '→' : '←')
const form = reactive({
    name: '', price: '', currency: 'EGP', feature_keys: [],
    // Resource caps. Blank = unlimited (stored as null). max_branches only bites
    // when the plan also grants multi_branch; a single-branch plan is capped at
    // its one primary branch by the multi_branch feature gate regardless.
    max_branches: '', max_items: '',
    is_active: true, is_recommended: false, sort_order: 0,
})
const currencies = ['EGP', 'SAR', 'AED', 'USD', 'KWD', 'QAR', 'BHD', 'OMR', 'JOD', 'EUR', 'GBP']

// Capability flags a plan can grant. Prerequisites (e.g. table_management→dine_in,
// customer_tracking→system_ordering) are auto-expanded server-side, so the admin
// only checks the headline capabilities.
const entitlementKeys = [
    'qr_menu', 'whatsapp_ordering', 'system_ordering', 'customer_tracking',
    'table_management', 'bill_requests', 'internal_reviews', 'product_analytics',
    'dine_in', 'pickup', 'delivery', 'multi_branch',
]
function toggleEntitlement(key, on) {
    const i = form.feature_keys.indexOf(key)
    if (on && i < 0) form.feature_keys.push(key)
    else if (!on && i >= 0) form.feature_keys.splice(i, 1)
}
const errors = ref({})
const saving = ref(false)

onMounted(async () => {
    if (isEdit.value) {
        const { data } = await api.get(`api/admin/plans/${route.params.id}`)
        const p = data.data
        Object.assign(form, {
            name: p.name,
            price: p.price ?? '',
            currency: p.currency,
            feature_keys: Array.isArray(p.feature_keys) ? [...p.feature_keys] : [],
            max_branches: p.max_branches ?? '',
            max_items: p.max_items ?? '',
            is_active: p.is_active,
            is_recommended: p.is_recommended ?? false,
            sort_order: p.sort_order,
        })
    }
})

async function submit() {
    errors.value = {}; saving.value = true
    try {
        await ensureCsrf()
        const payload = {
            name: form.name,
            price: form.price === '' ? null : Number(form.price),
            currency: form.currency,
            feature_keys: [...form.feature_keys],
            max_branches: form.max_branches === '' ? null : Number(form.max_branches),
            max_items: form.max_items === '' ? null : Number(form.max_items),
            is_active: form.is_active,
            is_recommended: form.is_recommended,
            sort_order: Number(form.sort_order) || 0,
        }
        if (isEdit.value) {
            await api.put(`api/admin/plans/${route.params.id}`, payload)
        } else {
            await api.post('api/admin/plans', payload)
        }
        router.push({ name: 'admin.plans' })
    } catch (err) {
        errors.value = err.response?.data?.errors || {}
    } finally {
        saving.value = false
    }
}
</script>

<template>
    <div class="max-w-2xl">
        <RouterLink :to="{ name: 'admin.plans' }" class="text-sm" style="color:var(--muted)">{{ backArrow }} {{ t('common.back') }}</RouterLink>
        <h1 class="page-title my-3">{{ isEdit ? t('plan.edit') : t('plan.create') }}</h1>

        <form @submit.prevent="submit" class="space-y-5">
            <div class="card p-6 space-y-4">
                <label class="block"><span class="label">{{ t('plan.name') }}</span>
                    <input v-model="form.name" class="input" />
                    <FormError :errors="errors" field="name" /></label>

                <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
                    <label class="block sm:col-span-2"><span class="label">{{ t('plan.price') }}</span>
                        <input v-model="form.price" type="number" min="0" step="0.01" class="input" :placeholder="t('plan.price_hint')" />
                        <FormError :errors="errors" field="price" /></label>
                    <label class="block"><span class="label">{{ t('restaurant.currency') }}</span>
                        <select v-model="form.currency" class="input">
                            <option v-for="c in currencies" :key="c" :value="c">{{ c }}</option>
                        </select></label>
                </div>

                <div class="block">
                    <span class="label">{{ t('plan.entitlements') }}</span>
                    <p class="text-xs mb-2" style="color:var(--muted)">{{ t('plan.entitlements_hint') }}</p>
                    <div class="grid grid-cols-1 sm:grid-cols-2 gap-2">
                        <label v-for="key in entitlementKeys" :key="key" class="flex items-center gap-2 rounded-lg border p-2.5 cursor-pointer" style="border-color:var(--line)">
                            <input type="checkbox" :checked="form.feature_keys.includes(key)" @change="toggleEntitlement(key, $event.target.checked)" class="h-4 w-4" />
                            <span class="text-sm" style="color:var(--ink)">{{ t(`feature.${key}`) }}</span>
                        </label>
                    </div>
                    <FormError :errors="errors" field="feature_keys" />
                </div>

                <div class="block">
                    <span class="label">{{ t('plan.limits') }}</span>
                    <p class="text-xs mb-2" style="color:var(--muted)">{{ t('plan.limits_hint') }}</p>
                    <div class="grid grid-cols-1 sm:grid-cols-2 gap-4 items-start">
                        <label class="block"><span class="label">{{ t('plan.max_branches') }}</span>
                            <input v-model="form.max_branches" type="number" min="1" step="1" class="input" :placeholder="t('plan.unlimited')" />
                            <span class="block text-xs mt-0.5" style="color:var(--muted)">{{ t('plan.max_branches_hint') }}</span>
                            <FormError :errors="errors" field="max_branches" /></label>
                        <label class="block"><span class="label">{{ t('plan.max_items') }}</span>
                            <input v-model="form.max_items" type="number" min="1" step="1" class="input" :placeholder="t('plan.unlimited')" />
                            <span class="block text-xs mt-0.5" style="color:var(--muted)">{{ t('plan.max_items_hint') }}</span>
                            <FormError :errors="errors" field="max_items" /></label>
                    </div>
                </div>

                <div class="grid grid-cols-1 sm:grid-cols-2 gap-4 items-start">
                    <label class="block"><span class="label">{{ t('plan.sort_order') }}</span>
                        <input v-model="form.sort_order" type="number" min="0" class="input" /></label>
                    <label class="flex items-start gap-3 rounded-lg border p-3 cursor-pointer mt-6" style="border-color:var(--line)">
                        <input v-model="form.is_active" type="checkbox" class="mt-0.5 h-4 w-4" />
                        <span>
                            <span class="label" style="margin:0">{{ t('plan.active') }}</span>
                            <span class="block text-xs mt-0.5" style="color:var(--muted)">{{ t('plan.active_hint') }}</span>
                        </span>
                    </label>
                    <label class="flex items-start gap-3 rounded-lg border p-3 cursor-pointer" style="border-color:var(--line)">
                        <input v-model="form.is_recommended" type="checkbox" class="mt-0.5 h-4 w-4" />
                        <span>
                            <span class="label" style="margin:0">{{ t('plan.recommended') }}</span>
                            <span class="block text-xs mt-0.5" style="color:var(--muted)">{{ t('plan.recommended_hint') }}</span>
                        </span>
                    </label>
                </div>
            </div>

            <div class="flex justify-end gap-2">
                <RouterLink :to="{ name: 'admin.plans' }" class="btn btn-ghost">{{ t('common.cancel') }}</RouterLink>
                <button type="submit" :disabled="saving" class="btn btn-accent">
                    {{ saving ? t('common.saving') : (isEdit ? t('admin.save_changes') : t('plan.create')) }}
                </button>
            </div>
        </form>
    </div>
</template>
