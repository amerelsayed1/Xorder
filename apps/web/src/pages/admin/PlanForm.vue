<script setup>
import { reactive, ref, computed, onMounted } from 'vue'
import { useRoute, useRouter, RouterLink } from 'vue-router'
import { useI18n } from 'vue-i18n'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import FormError from '@xorder/ui/FormError.vue'
import Icon from '@xorder/ui/Icon.vue'

const route = useRoute()
const router = useRouter()
const { t, locale } = useI18n()

const isEdit = computed(() => !!route.params.id)
const backArrow = computed(() => locale.value === 'ar' ? '→' : '←')
const form = reactive({
    name: '', price: '', currency: 'EGP', features: [''], is_active: true, sort_order: 0,
})
const currencies = ['EGP', 'SAR', 'AED', 'USD', 'KWD', 'QAR', 'BHD', 'OMR', 'JOD', 'EUR', 'GBP']
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
            features: p.features.length ? [...p.features] : [''],
            is_active: p.is_active,
            sort_order: p.sort_order,
        })
    }
})

function addFeature() { form.features.push('') }
function removeFeature(i) { form.features.splice(i, 1); if (!form.features.length) form.features.push('') }

async function submit() {
    errors.value = {}; saving.value = true
    try {
        await ensureCsrf()
        const payload = {
            name: form.name,
            price: form.price === '' ? null : Number(form.price),
            currency: form.currency,
            features: form.features.map(f => f.trim()).filter(Boolean),
            is_active: form.is_active,
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
                    <span class="label">{{ t('plan.features') }}</span>
                    <p class="text-xs mb-2" style="color:var(--muted)">{{ t('plan.features_hint') }}</p>
                    <div class="space-y-2">
                        <div v-for="(f, i) in form.features" :key="i" class="flex items-center gap-2">
                            <input v-model="form.features[i]" class="input" style="margin-top:0" />
                            <button type="button" @click="removeFeature(i)" class="icon-btn" :aria-label="t('common.delete')"><Icon name="trash" :size="16" /></button>
                        </div>
                    </div>
                    <button type="button" @click="addFeature" class="btn btn-ghost btn-sm mt-2"><Icon name="plus" :size="14" />{{ t('plan.add_feature') }}</button>
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
