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
    name: '', price: '', currency: 'EGP',
    // Resource caps. Blank = unlimited (stored as null). max_branches only bites
    // when the plan also grants multi_branch; a single-branch plan is capped at
    // its one primary branch by the multi_branch feature gate regardless.
    max_branches: '', max_items: '',
    is_active: true, is_recommended: false, sort_order: 0,
})
const currencies = ['EGP', 'SAR', 'AED', 'USD', 'KWD', 'QAR', 'BHD', 'OMR', 'JOD', 'EUR', 'GBP']

// Ordering is modelled as one exclusive channel (WhatsApp XOR System), each
// with its own fulfillment. It expands to the underlying feature flags on save
// and collapses back from them on load — the flags stay the source of truth,
// but the Super Admin thinks in the three ordering types we present.
const ordering = reactive({
    channel: '',          // '' | 'whatsapp' | 'system'
    waPickup: false, waDelivery: false,
    tableOrdering: false,
    onlineOrdering: false,
    onPickup: false, onDelivery: false,
})
function setChannel(ch) {
    ordering.channel = ch
    // Clear the other channel's sub-selection so no stale flags leak on save.
    if (ch === 'whatsapp') {
        ordering.tableOrdering = ordering.onlineOrdering = ordering.onPickup = ordering.onDelivery = false
    } else {
        ordering.waPickup = ordering.waDelivery = false
    }
}
/** Expand the ordering selection to feature flags. */
function orderingKeys() {
    const keys = new Set()
    if (ordering.channel === 'whatsapp') {
        keys.add('whatsapp_ordering')
        if (ordering.waPickup) keys.add('pickup')
        if (ordering.waDelivery) keys.add('delivery')
    } else if (ordering.channel === 'system') {
        if (ordering.tableOrdering) { keys.add('system_ordering'); keys.add('dine_in'); keys.add('table_management') }
        if (ordering.onlineOrdering) {
            keys.add('system_ordering')
            if (ordering.onPickup) keys.add('pickup')
            if (ordering.onDelivery) keys.add('delivery')
        }
    }
    return [...keys]
}
/** Collapse stored feature flags back into the ordering selection. */
function loadOrdering(keys) {
    const has = (k) => keys.includes(k)
    if (has('system_ordering') || has('dine_in') || has('table_management')) {
        ordering.channel = 'system' // if a legacy plan had both channels, System wins
        ordering.tableOrdering = has('dine_in') || has('table_management')
        ordering.onlineOrdering = has('system_ordering') && (has('pickup') || has('delivery'))
        ordering.onPickup = has('pickup')
        ordering.onDelivery = has('delivery')
    } else if (has('whatsapp_ordering')) {
        ordering.channel = 'whatsapp'
        ordering.waPickup = has('pickup')
        ordering.waDelivery = has('delivery')
    }
}

// Non-ordering capabilities the admin toggles directly. customer_tracking is
// gone — customers are captured on every plan now.
const capabilityKeys = ['qr_menu', 'bill_requests', 'internal_reviews', 'product_analytics', 'multi_branch']
const capabilities = ref([])
function toggleCapability(key, on) {
    const i = capabilities.value.indexOf(key)
    if (on && i < 0) capabilities.value.push(key)
    else if (!on && i >= 0) capabilities.value.splice(i, 1)
}
// The full flag set the plan will persist.
const featureKeys = computed(() => [...new Set([...capabilities.value, ...orderingKeys()])])
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
            max_branches: p.max_branches ?? '',
            max_items: p.max_items ?? '',
            is_active: p.is_active,
            is_recommended: p.is_recommended ?? false,
            sort_order: p.sort_order,
        })
        const keys = Array.isArray(p.feature_keys) ? p.feature_keys : []
        loadOrdering(keys)
        capabilities.value = capabilityKeys.filter((k) => keys.includes(k))
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
            feature_keys: featureKeys.value,
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
                    <span class="label">{{ t('plan.ordering') }}</span>
                    <p class="text-xs mb-2" style="color:var(--muted)">{{ t('plan.ordering_hint') }}</p>

                    <!-- Channel: WhatsApp XOR System -->
                    <div class="grid grid-cols-1 sm:grid-cols-2 gap-2">
                        <label class="flex items-center gap-2 rounded-lg border p-2.5 cursor-pointer" :style="{ borderColor: ordering.channel === 'whatsapp' ? 'var(--accent)' : 'var(--line)' }">
                            <input type="radio" name="channel" :checked="ordering.channel === 'whatsapp'" @change="setChannel('whatsapp')" class="h-4 w-4" />
                            <span class="text-sm" style="color:var(--ink)">{{ t('plan.ordering_whatsapp') }}</span>
                        </label>
                        <label class="flex items-center gap-2 rounded-lg border p-2.5 cursor-pointer" :style="{ borderColor: ordering.channel === 'system' ? 'var(--accent)' : 'var(--line)' }">
                            <input type="radio" name="channel" :checked="ordering.channel === 'system'" @change="setChannel('system')" class="h-4 w-4" />
                            <span class="text-sm" style="color:var(--ink)">{{ t('plan.ordering_system') }}</span>
                        </label>
                    </div>

                    <!-- WhatsApp fulfillment -->
                    <div v-if="ordering.channel === 'whatsapp'" class="mt-2 ps-3 border-s-2" style="border-color:var(--line)">
                        <span class="text-xs" style="color:var(--muted)">{{ t('plan.ordering_fulfillment') }}</span>
                        <div class="flex gap-4 mt-1">
                            <label class="flex items-center gap-2 text-sm cursor-pointer"><input type="checkbox" v-model="ordering.waPickup" class="h-4 w-4" />{{ t('feature.pickup') }}</label>
                            <label class="flex items-center gap-2 text-sm cursor-pointer"><input type="checkbox" v-model="ordering.waDelivery" class="h-4 w-4" />{{ t('feature.delivery') }}</label>
                        </div>
                    </div>

                    <!-- System sub-types -->
                    <div v-else-if="ordering.channel === 'system'" class="mt-2 ps-3 border-s-2 space-y-2" style="border-color:var(--line)">
                        <label class="flex items-center gap-2 text-sm cursor-pointer"><input type="checkbox" v-model="ordering.tableOrdering" class="h-4 w-4" />{{ t('plan.ordering_table') }}</label>
                        <label class="flex items-center gap-2 text-sm cursor-pointer"><input type="checkbox" v-model="ordering.onlineOrdering" class="h-4 w-4" />{{ t('plan.ordering_online') }}</label>
                        <div v-if="ordering.onlineOrdering" class="ps-6">
                            <span class="text-xs" style="color:var(--muted)">{{ t('plan.ordering_fulfillment') }}</span>
                            <div class="flex gap-4 mt-1">
                                <label class="flex items-center gap-2 text-sm cursor-pointer"><input type="checkbox" v-model="ordering.onPickup" class="h-4 w-4" />{{ t('feature.pickup') }}</label>
                                <label class="flex items-center gap-2 text-sm cursor-pointer"><input type="checkbox" v-model="ordering.onDelivery" class="h-4 w-4" />{{ t('feature.delivery') }}</label>
                            </div>
                        </div>
                    </div>
                    <FormError :errors="errors" field="feature_keys" />
                </div>

                <div class="block">
                    <span class="label">{{ t('plan.capabilities') }}</span>
                    <div class="grid grid-cols-1 sm:grid-cols-2 gap-2 mt-1">
                        <label v-for="key in capabilityKeys" :key="key" class="flex items-center gap-2 rounded-lg border p-2.5 cursor-pointer" style="border-color:var(--line)">
                            <input type="checkbox" :checked="capabilities.includes(key)" @change="toggleCapability(key, $event.target.checked)" class="h-4 w-4" />
                            <span class="text-sm" style="color:var(--ink)">{{ t(`feature.${key}`) }}</span>
                        </label>
                    </div>
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
