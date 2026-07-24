<script setup>
import { reactive, ref, computed, onMounted, watch } from 'vue'
import { useRoute, useRouter, RouterLink } from 'vue-router'
import { useI18n } from 'vue-i18n'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import ImageUploader from '@xorder/ui/ImageUploader.vue'
import FormError from '@xorder/ui/FormError.vue'
import { publicOrigin } from '../../lib/host.js'

const route = useRoute()
const router = useRouter()
const { t, locale } = useI18n()

const isEdit = computed(() => !!route.params.id)
const backArrow = computed(() => locale.value === 'ar' ? '→' : '←')
const forwardArrow = computed(() => locale.value === 'ar' ? '←' : '→')
const slugPrefix = `${publicOrigin()}/r/`

const form = reactive({
    name_en: '', name_ar: '', slug: '',
    description_en: '', description_ar: '',
    phone: '', whatsapp_number: '', address: '', opening_hours: '',
    logo_url: '', cover_image_url: '',
    brand_color: '#f89a06', secondary_color: '',
    default_language: 'ar',
    bilingual: true,
    currency: 'EGP',
    ordering_mode: 'both',
    status: 'ACTIVE', subscription_status: 'TRIAL',
    subscription_plan: '',
    admin: { name: '', username: '', email: '', password: '' },
})
const currencies = [
    { code: 'EGP', label: 'EGP — Egyptian Pound' },
    { code: 'SAR', label: 'SAR — Saudi Riyal' },
    { code: 'AED', label: 'AED — UAE Dirham' },
    { code: 'USD', label: 'USD — US Dollar' },
    { code: 'KWD', label: 'KWD — Kuwaiti Dinar' },
    { code: 'QAR', label: 'QAR — Qatari Riyal' },
    { code: 'BHD', label: 'BHD — Bahraini Dinar' },
    { code: 'OMR', label: 'OMR — Omani Rial' },
    { code: 'JOD', label: 'JOD — Jordanian Dinar' },
    { code: 'EUR', label: 'EUR — Euro' },
    { code: 'GBP', label: 'GBP — British Pound' },
]
const errors = ref({})
const saving = ref(false)
const generatedPassword = ref('')
const slugTouched = ref(false)

// ---- Wizard state (create mode) ----
const currentStep = ref(1)
const totalSteps = 6
const steps = computed(() => [
    { n: 1, label: t('wizard.step_language') },
    { n: 2, label: t('wizard.step_basics') },
    { n: 3, label: t('wizard.step_contact') },
    // Plan is chosen before branches so the branch step can enforce the plan's limit.
    { n: 4, label: t('wizard.step_features') },
    { n: 5, label: t('wizard.step_branch') },
    { n: 6, label: t('wizard.step_review') },
])

const langConfig = ref('bilingual') // 'ar_only' | 'en_only' | 'bilingual'
const primaryLanguage = ref('ar')
const showAr = computed(() => langConfig.value !== 'en_only')
const showEn = computed(() => langConfig.value !== 'ar_only')
const bilingualLang = computed(() => langConfig.value === 'bilingual')
// In single-language mode the "(English)/(Arabic)" qualifier is noise — there
// is only one name — so fall back to a plain "Name" label.
const nameLabelEn = computed(() => bilingualLang.value ? t('common.name_en') : t('common.name'))
const nameLabelAr = computed(() => bilingualLang.value ? t('common.name_ar') : t('common.name'))

function chooseLang(cfg) {
    langConfig.value = cfg
    if (cfg === 'ar_only') primaryLanguage.value = 'ar'
    else if (cfg === 'en_only') primaryLanguage.value = 'en'
}
function langOptionLabel(opt) {
    return t(`wizard.lang_${opt === 'ar_only' ? 'arabic_only' : opt === 'en_only' ? 'english_only' : 'bilingual'}`)
}

const branchEnabled = ref(true)
const branch = reactive({
    name_en: '', name_ar: '', code: '', city: '', country: '',
    phone: '', whatsapp_number: '', supported_order_types: ['dine_in'],
})
const orderTypes = ['dine_in', 'pickup', 'delivery']
function toggleOrderType(tp) {
    const i = branch.supported_order_types.indexOf(tp)
    if (i >= 0) branch.supported_order_types.splice(i, 1)
    else branch.supported_order_types.push(tp)
}

// Plan-driven capabilities. The plan strictly decides which features a client
// gets; the wizard just previews the resolved set. Prerequisites are expanded
// here to mirror Feature::resolve on the backend.
const plans = ref([])
const featureRequires = {
    bill_requests: ['table_management'],
    table_management: ['dine_in'],
    customer_tracking: ['system_ordering'],
}
// Display order for the derived-capabilities preview.
const featureDisplayOrder = [
    'qr_menu', 'whatsapp_ordering', 'system_ordering', 'customer_tracking',
    'dine_in', 'pickup', 'delivery',
    'table_management', 'bill_requests', 'internal_reviews', 'product_analytics',
    'multi_branch',
]

/** Expand feature keys with their prerequisites (mirrors Feature::resolve). */
function resolveKeys(keys) {
    const set = new Set(keys)
    let changed = true
    while (changed) {
        changed = false
        for (const k of [...set]) {
            for (const p of (featureRequires[k] || [])) {
                if (!set.has(p)) { set.add(p); changed = true }
            }
        }
    }
    return set
}

const selectedPlan = computed(() => plans.value.find(p => p.name === form.subscription_plan) || null)
const derivedFeatureKeys = computed(() => {
    const resolved = resolveKeys(selectedPlan.value?.feature_keys || [])
    return featureDisplayOrder.filter(k => resolved.has(k))
})
const enabledFeatureLabels = computed(() => derivedFeatureKeys.value.map(k => t(`feature.${k}`)))

// The branch step depends on the chosen plan: a plan must be selected first,
// and its max_branches (null = unlimited) must permit at least the one branch
// the wizard creates. If the plan changes to one that disallows branches,
// disable the branch so the user can't submit an over-limit configuration.
const planBranchLimit = computed(() => {
    const mb = selectedPlan.value?.max_branches
    return (mb === null || mb === undefined) ? null : Number(mb) // null = unlimited
})
const branchAllowed = computed(() => {
    if (!selectedPlan.value) return false // must pick a plan before adding branches
    return planBranchLimit.value === null || planBranchLimit.value >= 1
})
watch(branchAllowed, (ok) => { if (!ok) branchEnabled.value = false })

// The ordering-mode choice is capped to the channels the selected plan grants:
// both WhatsApp + system → all three; only one entitled → that one.
const orderingModeOptions = computed(() => {
    const has = (k) => derivedFeatureKeys.value.includes(k)
    if (has('whatsapp_ordering') && has('system_ordering')) return ['both', 'whatsapp', 'system']
    if (has('whatsapp_ordering')) return ['whatsapp']
    if (has('system_ordering')) return ['system']
    return []
})
watch(orderingModeOptions, (opts) => {
    if (opts.length && !opts.includes(form.ordering_mode)) form.ordering_mode = opts[0]
}, { immediate: true })
const langConfigLabel = computed(() => langOptionLabel(langConfig.value))

const stepValid = computed(() => {
    switch (currentStep.value) {
        case 2:
            return (!showEn.value || !!form.name_en.trim())
                && (!showAr.value || !!form.name_ar.trim())
                && !!form.slug.trim()
                && !!form.admin.name.trim() && !!form.admin.username.trim()
        case 5:
            if (!branchEnabled.value) return true
            return (((showEn.value && branch.name_en.trim()) || (showAr.value && branch.name_ar.trim())) && branch.supported_order_types.length > 0)
        default:
            return true
    }
})

function next() { if (stepValid.value && currentStep.value < totalSteps) currentStep.value++ }
function back() { if (currentStep.value > 1) currentStep.value-- }
function goTo(n) { if (n <= currentStep.value) currentStep.value = n }

function autoSlug() {
    if (!isEdit.value && !slugTouched.value && showEn.value) {
        form.slug = (form.name_en || '').toLowerCase().trim()
            .replace(/[^a-z0-9\s-]/g, '').replace(/\s+/g, '-').replace(/-+/g, '-')
    }
}
function generatePassword() {
    const chars = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'
    form.admin.password = Array.from(crypto.getRandomValues(new Uint8Array(14))).map(b => chars[b % chars.length]).join('')
}

onMounted(async () => {
    // Active plans populate the plan picker; the picked plan drives capabilities.
    try {
        const { data } = await api.get('api/admin/plans', { params: { active_only: 1 } })
        plans.value = data.data || []
    } catch (err) { /* leave the picker empty on failure */ }

    if (isEdit.value) {
        const { data } = await api.get(`api/admin/restaurants/${route.params.id}`)
        Object.assign(form, { ...data.data, secondary_color: data.data.secondary_color || '', subscription_plan: data.data.subscription_plan || '' })
    }
})

function stepForError(key) {
    if (/^branch\./.test(key)) return 5
    if (/^(name_en|name_ar|slug|admin\.)/.test(key)) return 2
    if (/^(features|subscription_plan)/.test(key)) return 4
    return 3
}

async function submitEdit() {
    errors.value = {}; saving.value = true
    try {
        await ensureCsrf()
        // Features are derived from the plan server-side — send the plan, not flags.
        const payload = { ...form }; delete payload.admin
        await api.put(`api/admin/restaurants/${route.params.id}`, payload)
        router.push({ name: 'admin.restaurants.show', params: { id: route.params.id } })
    } catch (err) {
        errors.value = err.response?.data?.errors || {}
    } finally {
        saving.value = false
    }
}

async function submitCreate() {
    errors.value = {}; saving.value = true
    try {
        await ensureCsrf()
        form.bilingual = langConfig.value === 'bilingual'
        form.default_language = primaryLanguage.value
        // Features are derived from the plan server-side — send the plan, not flags.
        const payload = { ...form }
        if (branchEnabled.value) payload.branch = { ...branch }
        const { data } = await api.post('api/admin/restaurants', payload)
        if (data.generated_password) generatedPassword.value = data.generated_password
        else router.push({ name: 'admin.restaurants.show', params: { id: data.data.id } })
    } catch (err) {
        errors.value = err.response?.data?.errors || {}
        const first = Object.keys(errors.value)[0]
        if (first) currentStep.value = stepForError(first)
    } finally {
        saving.value = false
    }
}
</script>

<template>
    <div class="max-w-2xl">
        <RouterLink :to="{ name: 'admin.restaurants' }" class="text-sm" style="color:var(--muted)">{{ backArrow }} {{ t('common.back') }}</RouterLink>
        <h1 class="page-title my-3">{{ isEdit ? t('admin.edit_restaurant') : t('admin.create_restaurant') }}</h1>

        <!-- Generated password banner -->
        <div v-if="generatedPassword" class="card p-5 mb-4" style="border-color:var(--green);background:var(--green-soft)">
            <p class="font-medium" style="color:var(--green)">{{ t('restaurant.generated_password') }}</p>
            <p class="mono text-2xl mt-1" style="color:var(--ink)">{{ generatedPassword }}</p>
            <p class="text-sm mt-1" style="color:var(--green)">{{ t('restaurant.generated_password_note') }}</p>
            <RouterLink :to="{ name: 'admin.restaurants' }" class="btn btn-dark mt-3">{{ t('common.done') }} {{ forwardArrow }}</RouterLink>
        </div>

        <!-- ===================== EDIT MODE (single form) ===================== -->
        <form v-if="!generatedPassword && isEdit" @submit.prevent="submitEdit" class="space-y-5">
            <div class="card p-6 space-y-4">
                <h2 class="h-card">{{ t('admin.restaurant') }}</h2>
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                    <label class="block"><span class="label">{{ t('common.name_en') }}</span>
                        <input v-model="form.name_en" class="input" />
                        <FormError :errors="errors" field="name_en" /></label>
                    <label class="block" dir="rtl"><span class="label">{{ t('common.name_ar') }}</span>
                        <input v-model="form.name_ar" class="input" /></label>
                </div>
                <label class="block"><span class="label">{{ t('restaurant.slug') }}</span>
                    <div class="flex items-center mt-1.5 rounded-lg border overflow-hidden" style="border-color:var(--line)">
                        <span class="mono text-sm px-3 py-2.5" style="background:var(--page);color:var(--muted)">{{ slugPrefix }}</span>
                        <input v-model="form.slug" class="flex-1 px-3 py-2.5 text-sm mono" style="border:0;outline:0;background:var(--card);color:var(--ink)" />
                    </div>
                    <p class="text-xs mt-1" style="color:var(--amber)">{{ t('restaurant.slug_warning') }}</p>
                    <FormError :errors="errors" field="slug" /></label>
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                    <label class="block"><span class="label">{{ t('restaurant.phone') }}</span><input v-model="form.phone" class="input" /></label>
                    <label class="block"><span class="label">{{ t('restaurant.whatsapp') }}</span><input v-model="form.whatsapp_number" class="input" /></label>
                </div>
                <label class="block"><span class="label">{{ t('restaurant.address') }}</span><input v-model="form.address" class="input" /></label>
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                    <ImageUploader v-model="form.logo_url" folder="logos" :label="t('restaurant.logo')" />
                    <ImageUploader v-model="form.cover_image_url" folder="covers" :label="t('restaurant.cover_image')" />
                </div>
                <div class="grid grid-cols-3 gap-4 items-end">
                    <label class="block"><span class="label">{{ t('restaurant.brand_color') }}</span>
                        <input v-model="form.brand_color" type="color" class="mt-1.5 w-full h-11 rounded-lg border cursor-pointer" style="border-color:var(--line)" /></label>
                    <label class="block"><span class="label">{{ t('restaurant.secondary_color') }}</span>
                        <input v-model="form.secondary_color" type="color" class="mt-1.5 w-full h-11 rounded-lg border cursor-pointer" style="border-color:var(--line)" /></label>
                    <label class="block"><span class="label">{{ t('restaurant.currency') }}</span>
                        <select v-model="form.currency" class="input">
                            <option v-for="c in currencies" :key="c.code" :value="c.code">{{ c.label }}</option>
                        </select>
                        <FormError :errors="errors" field="currency" /></label>
                </div>
                <div v-if="orderingModeOptions.length > 1">
                    <span class="label">{{ t('restaurant.ordering_mode') }}</span>
                    <div class="flex gap-2 mt-1.5 flex-wrap">
                        <button v-for="m in orderingModeOptions" :key="m" type="button" @click="form.ordering_mode = m"
                            class="btn" :class="form.ordering_mode === m ? 'btn-dark' : 'btn-ghost'">{{ t('restaurant.ordering_mode_' + m) }}</button>
                    </div>
                    <span class="block text-xs mt-1.5" style="color:var(--muted)">{{ t('restaurant.ordering_mode_hint') }}</span>
                </div>
            </div>

            <!-- Plan & capabilities — the plan strictly decides what this client gets. -->
            <div class="card p-6 space-y-4">
                <h2 class="h-card">{{ t('wizard.features_title') }}</h2>
                <label class="block"><span class="label">{{ t('wizard.plan_group') }}</span>
                    <select v-model="form.subscription_plan" class="input">
                        <option value="">{{ t('wizard.select_plan') }}</option>
                        <option v-for="p in plans" :key="p.id" :value="p.name">{{ p.name }}</option>
                    </select>
                    <span class="block text-xs mt-1" style="color:var(--muted)">{{ t('wizard.plan_help') }}</span>
                    <FormError :errors="errors" field="subscription_plan" /></label>
                <div class="pt-2" style="border-top:1px solid var(--line)">
                    <h3 class="label" style="margin:0">{{ t('wizard.features_derived') }}</h3>
                    <div v-if="derivedFeatureKeys.length" class="flex flex-wrap gap-2 mt-2">
                        <span v-for="key in derivedFeatureKeys" :key="key" class="rounded-full px-3 py-1 text-xs" style="background:var(--page);border:1px solid var(--line);color:var(--ink)">{{ t(`feature.${key}`) }}</span>
                    </div>
                    <p v-else class="text-sm mt-2" style="color:var(--muted)">{{ t('wizard.features_derived_none') }}</p>
                </div>
            </div>

            <div class="flex justify-end gap-2">
                <RouterLink :to="{ name: 'admin.restaurants' }" class="btn btn-ghost">{{ t('common.cancel') }}</RouterLink>
                <button type="submit" :disabled="saving" class="btn btn-accent">{{ saving ? t('common.saving') : t('admin.save_changes') }}</button>
            </div>
        </form>

        <!-- ===================== CREATE MODE (wizard) ===================== -->
        <div v-else-if="!generatedPassword">
            <!-- Stepper header -->
            <div class="card p-4 mb-4">
                <div class="flex items-center justify-between gap-1">
                    <template v-for="(s, i) in steps" :key="s.n">
                        <button type="button" @click="goTo(s.n)"
                            class="flex items-center gap-2 text-sm"
                            :style="s.n > currentStep ? 'cursor:default;opacity:.55' : 'cursor:pointer'">
                            <span class="inline-flex items-center justify-center rounded-full h-7 w-7 text-xs font-semibold"
                                :style="s.n === currentStep ? 'background:var(--accent);color:#fff'
                                    : s.n < currentStep ? 'background:var(--green-soft);color:var(--green)'
                                    : 'background:var(--page);color:var(--muted)'">
                                {{ s.n < currentStep ? '✓' : s.n }}
                            </span>
                            <span class="hidden md:inline" :style="s.n === currentStep ? 'color:var(--ink);font-weight:600' : 'color:var(--muted)'">{{ s.label }}</span>
                        </button>
                        <span v-if="i < steps.length - 1" class="flex-1 h-px" style="background:var(--line)"></span>
                    </template>
                </div>
            </div>

            <!-- Step 1: Language -->
            <div v-show="currentStep === 1" class="card p-6 space-y-4">
                <div>
                    <h2 class="h-card">{{ t('wizard.lang_title') }}</h2>
                    <p class="text-sm mt-1" style="color:var(--muted)">{{ t('wizard.lang_help') }}</p>
                </div>
                <div class="grid grid-cols-1 sm:grid-cols-3 gap-3">
                    <button v-for="opt in ['ar_only', 'en_only', 'bilingual']" :key="opt" type="button" @click="chooseLang(opt)"
                        class="rounded-lg border p-4 text-start"
                        :style="langConfig === opt ? 'border-color:var(--accent);background:var(--accent-soft,rgba(248,154,6,.08))' : 'border-color:var(--line)'">
                        <span class="block font-medium" style="color:var(--ink)">{{ langOptionLabel(opt) }}</span>
                    </button>
                </div>
                <div v-if="langConfig === 'bilingual'">
                    <span class="label">{{ t('wizard.primary_language') }}</span>
                    <div class="flex gap-2 mt-1.5">
                        <button v-for="lng in ['ar', 'en']" :key="lng" type="button" @click="primaryLanguage = lng"
                            class="btn" :class="primaryLanguage === lng ? 'btn-dark' : 'btn-ghost'">{{ t(`languages.${lng}`) }}</button>
                    </div>
                    <p class="text-xs mt-1.5" style="color:var(--muted)">{{ t('wizard.primary_help') }}</p>
                </div>
            </div>

            <!-- Step 2: Basic info -->
            <div v-show="currentStep === 2" class="card p-6 space-y-4">
                <h2 class="h-card">{{ t('wizard.basics_title') }}</h2>
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                    <label v-if="showEn" class="block"><span class="label">{{ nameLabelEn }}</span>
                        <input v-model="form.name_en" @input="autoSlug" class="input" />
                        <FormError :errors="errors" field="name_en" /></label>
                    <label v-if="showAr" class="block" dir="rtl"><span class="label">{{ nameLabelAr }}</span>
                        <input v-model="form.name_ar" class="input" />
                        <FormError :errors="errors" field="name_ar" /></label>
                </div>
                <label class="block"><span class="label">{{ t('restaurant.slug') }}</span>
                    <div class="flex items-center mt-1.5 rounded-lg border overflow-hidden" style="border-color:var(--line)">
                        <span class="mono text-sm px-3 py-2.5" style="background:var(--page);color:var(--muted)">{{ slugPrefix }}</span>
                        <input v-model="form.slug" @input="slugTouched = true" class="flex-1 px-3 py-2.5 text-sm mono" style="border:0;outline:0;background:var(--card);color:var(--ink)" />
                    </div>
                    <FormError :errors="errors" field="slug" /></label>
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                    <label class="block"><span class="label">{{ t('restaurant.currency') }}</span>
                        <select v-model="form.currency" class="input">
                            <option v-for="c in currencies" :key="c.code" :value="c.code">{{ c.label }}</option>
                        </select>
                        <FormError :errors="errors" field="currency" /></label>
                    <label class="block"><span class="label">{{ t('common.status') }}</span>
                        <select v-model="form.status" class="input">
                            <option value="ACTIVE">{{ t('status.ACTIVE') }}</option>
                            <option value="SUSPENDED">{{ t('status.SUSPENDED') }}</option>
                        </select></label>
                </div>
                <div class="pt-2" style="border-top:1px solid var(--line)">
                    <h3 class="label" style="margin-bottom:.5rem">{{ t('admin.first_restaurant_admin') }}</h3>
                    <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                        <label class="block"><span class="label">{{ t('restaurant.admin_name') }}</span>
                            <input v-model="form.admin.name" class="input" />
                            <FormError :errors="errors" field="admin.name" /></label>
                        <label class="block" dir="ltr"><span class="label">{{ t('restaurant.admin_username') }}</span>
                            <input v-model="form.admin.username" type="text" autocapitalize="none" spellcheck="false" class="input" />
                            <span class="block text-xs mt-1" style="color:var(--muted)">{{ t('restaurant.admin_username_hint') }}</span>
                            <FormError :errors="errors" field="admin.username" /></label>
                    </div>
                    <label class="block mt-3"><span class="label">{{ t('restaurant.admin_email') }}</span>
                        <input v-model="form.admin.email" type="email" class="input" />
                        <FormError :errors="errors" field="admin.email" /></label>
                    <label class="block mt-3"><span class="label">{{ t('restaurant.admin_password') }}</span>
                        <div class="flex gap-2 mt-1.5">
                            <input v-model="form.admin.password" type="text" class="input" style="margin-top:0" :placeholder="t('restaurant.password_hint')" />
                            <button type="button" @click="generatePassword" class="btn btn-ghost whitespace-nowrap">{{ t('admin.generate_password') }}</button>
                        </div>
                        <FormError :errors="errors" field="admin.password" /></label>
                </div>
            </div>

            <!-- Step 3: Contact & branding -->
            <div v-show="currentStep === 3" class="card p-6 space-y-4">
                <h2 class="h-card">{{ t('wizard.contact_title') }}</h2>
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                    <label class="block"><span class="label">{{ t('restaurant.phone') }}</span><input v-model="form.phone" class="input" /></label>
                    <label class="block"><span class="label">{{ t('restaurant.whatsapp') }}</span><input v-model="form.whatsapp_number" class="input" /></label>
                </div>
                <label class="block"><span class="label">{{ t('restaurant.address') }}</span><input v-model="form.address" class="input" /></label>
                <label class="block"><span class="label">{{ t('restaurant.opening_hours') }}</span><input v-model="form.opening_hours" class="input" /></label>
                <h3 class="label pt-2" style="border-top:1px solid var(--line)">{{ t('wizard.branding_title') }}</h3>
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                    <ImageUploader v-model="form.logo_url" folder="logos" :label="t('restaurant.logo')" />
                    <ImageUploader v-model="form.cover_image_url" folder="covers" :label="t('restaurant.cover_image')" />
                </div>
                <div class="grid grid-cols-2 gap-4">
                    <label class="block"><span class="label">{{ t('restaurant.brand_color') }}</span>
                        <input v-model="form.brand_color" type="color" class="mt-1.5 w-full h-11 rounded-lg border cursor-pointer" style="border-color:var(--line)" /></label>
                    <label class="block"><span class="label">{{ t('restaurant.secondary_color') }}</span>
                        <input v-model="form.secondary_color" type="color" class="mt-1.5 w-full h-11 rounded-lg border cursor-pointer" style="border-color:var(--line)" /></label>
                </div>
            </div>

            <!-- Step 5: First branch -->
            <div v-show="currentStep === 5" class="card p-6 space-y-4">
                <div class="flex items-start justify-between gap-3">
                    <div>
                        <h2 class="h-card">{{ t('wizard.branch_title') }}</h2>
                        <p class="text-sm mt-1" style="color:var(--muted)">{{ t('wizard.branch_optional') }}</p>
                    </div>
                    <label v-if="branchAllowed" class="flex items-center gap-2 text-sm whitespace-nowrap">
                        <input type="checkbox" :checked="!branchEnabled" @change="branchEnabled = !branchEnabled" class="h-4 w-4" />
                        {{ t('wizard.branch_skip') }}
                    </label>
                </div>
                <!-- Branches require a plan, and the plan's limit gates the form. -->
                <p v-if="!selectedPlan" class="text-sm rounded-lg p-3" style="background:var(--page);color:var(--muted)">{{ t('wizard.branch_needs_plan') }}</p>
                <p v-else-if="!branchAllowed" class="text-sm rounded-lg p-3" style="background:var(--page);color:var(--muted)">{{ t('wizard.branch_not_in_plan') }}</p>
                <p v-if="branchAllowed && planBranchLimit !== null" class="text-xs" style="color:var(--muted)">{{ t('wizard.branch_limit', { n: planBranchLimit }) }}</p>
                <p v-if="branchAllowed && !branchEnabled" class="text-sm rounded-lg p-3" style="background:var(--page);color:var(--muted)">{{ t('wizard.branch_skip_note') }}</p>
                <template v-if="branchAllowed && branchEnabled">
                    <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                        <label v-if="showEn" class="block"><span class="label">{{ nameLabelEn }}</span>
                            <input v-model="branch.name_en" class="input" />
                            <FormError :errors="errors" field="branch.name_en" /></label>
                        <label v-if="showAr" class="block" dir="rtl"><span class="label">{{ nameLabelAr }}</span>
                            <input v-model="branch.name_ar" class="input" /></label>
                    </div>
                    <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
                        <label class="block"><span class="label">{{ t('wizard.branch_code') }}</span><input v-model="branch.code" class="input" /></label>
                        <label class="block"><span class="label">{{ t('wizard.branch_city') }}</span><input v-model="branch.city" class="input" /></label>
                        <label class="block"><span class="label">{{ t('wizard.branch_country') }}</span><input v-model="branch.country" maxlength="2" class="input" /></label>
                    </div>
                    <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                        <label class="block"><span class="label">{{ t('restaurant.phone') }}</span><input v-model="branch.phone" class="input" /></label>
                        <label class="block"><span class="label">{{ t('restaurant.whatsapp') }}</span><input v-model="branch.whatsapp_number" class="input" /></label>
                    </div>
                    <div>
                        <span class="label">{{ t('wizard.order_types') }}</span>
                        <div class="flex flex-wrap gap-2 mt-1.5">
                            <button v-for="tp in orderTypes" :key="tp" type="button" @click="toggleOrderType(tp)"
                                class="btn" :class="branch.supported_order_types.includes(tp) ? 'btn-dark' : 'btn-ghost'">{{ t(`order_type.${tp}`) }}</button>
                        </div>
                    </div>
                </template>
            </div>

            <!-- Step 4: Plan & features -->
            <div v-show="currentStep === 4" class="card p-6 space-y-4">
                <div>
                    <h2 class="h-card">{{ t('wizard.features_title') }}</h2>
                    <p class="text-sm mt-1" style="color:var(--muted)">{{ t('wizard.features_help') }}</p>
                </div>

                <div v-if="orderingModeOptions.length > 1" class="space-y-3 pb-2" style="border-bottom:1px solid var(--line)">
                    <h3 class="label" style="margin:0">{{ t('restaurant.ordering_mode') }}</h3>
                    <div class="flex gap-2 flex-wrap">
                        <button v-for="m in orderingModeOptions" :key="m" type="button" @click="form.ordering_mode = m"
                            class="btn" :class="form.ordering_mode === m ? 'btn-dark' : 'btn-ghost'">{{ t('restaurant.ordering_mode_' + m) }}</button>
                    </div>
                    <p class="text-xs" style="color:var(--muted)">{{ t('restaurant.ordering_mode_hint') }}</p>
                </div>

                <label class="block"><span class="label">{{ t('wizard.plan_group') }}</span>
                    <select v-model="form.subscription_plan" class="input">
                        <option value="">{{ t('wizard.select_plan') }}</option>
                        <option v-for="p in plans" :key="p.id" :value="p.name">{{ p.name }}</option>
                    </select>
                    <span class="block text-xs mt-1" style="color:var(--muted)">{{ t('wizard.plan_help') }}</span>
                    <FormError :errors="errors" field="subscription_plan" /></label>

                <div class="pt-2" style="border-top:1px solid var(--line)">
                    <h3 class="label" style="margin:0">{{ t('wizard.features_derived') }}</h3>
                    <div v-if="derivedFeatureKeys.length" class="flex flex-wrap gap-2 mt-2">
                        <span v-for="key in derivedFeatureKeys" :key="key" class="rounded-full px-3 py-1 text-xs" style="background:var(--page);border:1px solid var(--line);color:var(--ink)">{{ t(`feature.${key}`) }}</span>
                    </div>
                    <p v-else class="text-sm mt-2" style="color:var(--muted)">{{ t('wizard.features_derived_none') }}</p>
                </div>
            </div>

            <!-- Step 6: Review -->
            <div v-show="currentStep === 6" class="card p-6 space-y-4">
                <h2 class="h-card">{{ t('wizard.review_title') }}</h2>
                <dl class="space-y-3 text-sm">
                    <div class="flex justify-between gap-4">
                        <dt style="color:var(--muted)">{{ t('wizard.review_languages') }}</dt>
                        <dd class="text-end" style="color:var(--ink)">{{ langConfigLabel }} · {{ t('wizard.review_primary') }}: {{ t(`languages.${primaryLanguage}`) }}
                            <button type="button" @click="goTo(1)" class="ms-2" style="color:var(--accent)">{{ t('wizard.review_edit') }}</button></dd>
                    </div>
                    <div class="flex justify-between gap-4">
                        <dt style="color:var(--muted)">{{ t('admin.restaurant') }}</dt>
                        <dd class="text-end" style="color:var(--ink)">{{ showEn ? form.name_en : '' }}<span v-if="showEn && showAr"> · </span>{{ showAr ? form.name_ar : '' }}
                            <span class="mono" style="color:var(--muted)"> /{{ form.slug }}</span>
                            <button type="button" @click="goTo(2)" class="ms-2" style="color:var(--accent)">{{ t('wizard.review_edit') }}</button></dd>
                    </div>
                    <div class="flex justify-between gap-4">
                        <dt style="color:var(--muted)">{{ t('wizard.review_features') }}</dt>
                        <dd class="text-end" style="color:var(--ink)">{{ enabledFeatureLabels.length ? enabledFeatureLabels.join(', ') : t('wizard.review_features_none') }}
                            <button type="button" @click="goTo(4)" class="ms-2" style="color:var(--accent)">{{ t('wizard.review_edit') }}</button></dd>
                    </div>
                    <div class="flex justify-between gap-4">
                        <dt style="color:var(--muted)">{{ t('wizard.review_branch') }}</dt>
                        <dd class="text-end" style="color:var(--ink)">
                            <template v-if="branchEnabled">{{ showEn ? branch.name_en : branch.name_ar }} ({{ branch.supported_order_types.map(x => t(`order_type.${x}`)).join(', ') }})</template>
                            <template v-else>{{ t('wizard.review_no_branch') }}</template>
                            <button type="button" @click="goTo(5)" class="ms-2" style="color:var(--accent)">{{ t('wizard.review_edit') }}</button></dd>
                    </div>
                </dl>
                <div v-if="Object.keys(errors).length" class="rounded-lg p-3 text-sm" style="background:var(--red-soft,rgba(220,38,38,.08));color:var(--red,#dc2626)">
                    <p v-for="(msgs, field) in errors" :key="field">{{ Array.isArray(msgs) ? msgs[0] : msgs }}</p>
                </div>
            </div>

            <!-- Wizard nav -->
            <div class="flex justify-between gap-2 mt-4">
                <RouterLink :to="{ name: 'admin.restaurants' }" class="btn btn-ghost">{{ t('common.cancel') }}</RouterLink>
                <div class="flex gap-2">
                    <button v-if="currentStep > 1" type="button" @click="back" class="btn btn-ghost">{{ backArrow }} {{ t('wizard.back') }}</button>
                    <button v-if="currentStep < totalSteps" type="button" @click="next" :disabled="!stepValid" class="btn btn-dark">{{ t('wizard.next') }} {{ forwardArrow }}</button>
                    <button v-else type="button" @click="submitCreate" :disabled="saving" class="btn btn-accent">{{ saving ? t('common.saving') : t('wizard.create_client') }}</button>
                </div>
            </div>
        </div>
    </div>
</template>
