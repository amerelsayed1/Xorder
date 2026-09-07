<script setup>
import { reactive, ref, computed, onMounted, watch } from 'vue'
import { useRoute, useRouter, RouterLink } from 'vue-router'
import { useI18n } from 'vue-i18n'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import ImageUploader from '@xorder/ui/ImageUploader.vue'
import FormError from '@xorder/ui/FormError.vue'
import { collectPhoneErrors } from '../../lib/phone.js'
import { collectEmailErrors } from '../../lib/email.js'
import { menuHostSuffix } from '../../lib/host.js'

const route = useRoute()
const router = useRouter()
const { t, locale } = useI18n()

const isEdit = computed(() => !!route.params.id)
const backArrow = computed(() => locale.value === 'ar' ? '→' : '←')
const forwardArrow = computed(() => locale.value === 'ar' ? '←' : '→')
// The menu lives at {slug}.xorder.io, so show a trailing ".xorder.io" suffix
// after the slug input (".localhost:8080" in local dev).
const slugSuffix = menuHostSuffix

const form = reactive({
    name_en: '', name_ar: '', slug: '',
    description_en: '', description_ar: '',
    phone: '', whatsapp_number: '', address: '', opening_hours: '',
    logo_url: '', cover_image_url: '',
    brand_color: '#f89a06', secondary_color: '',
    menu_layout: 'photo',
    default_language: 'ar',
    bilingual: true,
    currency: 'EGP',
    ordering_mode: 'whatsapp',
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
// Public-menu presentation themes; labels resolve via t('restaurant.menu_layout_*').
const menuLayouts = ['photo', 'text-grid', 'text-list']

// How this client's TILLS run, carried on the licence issued with the tenant.
//
// The POS reads `modes` off the licence and offers only what is in it — the
// wizard asks for the licence before it asks for the mode, precisely so an
// operator is never given a choice they did not buy. Until this existed the
// server fell back to ['cloud'] for every tenant created here, so an offline
// deployment could not be sold from this screen at all: it had to be issued
// afterwards from the standalone licence form, and the till in the meantime
// reported "not licensed for this mode".
//
// Never submitted empty. An empty modes[] parses to an empty set on the till,
// every mode then fails, and that reads to a cashier as a bricked terminal.
const POS_MODES = ['cloud', 'offline']
const licenceModes = ref(['cloud'])
function togglePosMode(mode, on) {
    const i = licenceModes.value.indexOf(mode)
    if (on && i < 0) licenceModes.value.push(mode)
    else if (!on && i >= 0 && licenceModes.value.length > 1) licenceModes.value.splice(i, 1)
}
const errors = ref({})
const saving = ref(false)
const generatedPassword = ref('')
// The licence issued alongside the tenant, and its activation key. The key
// exists in that ONE response and nowhere else — the server keeps only an HMAC
// — so it has to be shown before this screen is left. The tenant it belongs to
// has zero terminals at this point, which is the intended outcome.
const createdLicence = ref(null)
const activationKey = ref('')
const createdRestaurantId = ref(null)
// True once creation succeeded, even when no password was generated — the
// banner still has an activation key to hand over.
const createdDone = ref(false)
const slugTouched = ref(false)
// Name of the custom plan already created this session, so a re-submit after a
// restaurant-validation error doesn't try to create a duplicate plan.
const createdCustomPlan = ref('')

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

// Edit form binds language straight to form.bilingual + form.default_language
// (the create wizard's langConfig ref isn't hydrated on edit). One 3-way toggle
// drives both: single-language modes pin the default_language and turn bilingual
// off; bilingual keeps both languages with the AR/EN switcher.
const editLangValue = computed(() =>
    form.bilingual ? 'bilingual' : (form.default_language === 'en' ? 'en_only' : 'ar_only'))
function setEditLang(opt) {
    if (opt === 'bilingual') {
        form.bilingual = true
        if (!form.default_language) form.default_language = 'ar'
    } else {
        form.bilingual = false
        form.default_language = opt === 'en_only' ? 'en' : 'ar'
    }
}

const branchEnabled = ref(true)
const branch = reactive({
    name_en: '', name_ar: '', code: '', city: '', country: '',
    phone: '', whatsapp_number: '', supported_order_types: ['dine_in'],
})
const ALL_ORDER_TYPES = ['dine_in', 'pickup', 'delivery']
// Supported countries (ISO 3166-1 alpha-2). Short list for now.
const branchCountries = ['EG', 'SA', 'AE']
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
    // customer_tracking has no prerequisite: customers are captured on every
    // ordering type (system orders and WhatsApp checkout alike).
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

// ---- Plan selection: pick an existing plan, or build a custom one inline. ----
// A custom plan is created as a real (inactive) Plan row just before the
// restaurant, then attached by name. Entitlements resolve by plan name, so this
// keeps the "features are strictly the plan's" rule intact — without adding a
// row to the public pricing catalog (is_active stays false).
const planMode = ref('existing') // 'existing' | 'custom'
const custom = reactive({
    name: '', price: '',
    max_branches: '', max_items: '', max_categories: '',
})
const customOrdering = reactive({
    channel: '', waPickup: false, waDelivery: false,
    tableOrdering: false, tableBillRequests: false, onlineOrdering: false, onPickup: false, onDelivery: false,
})
function setCustomChannel(ch) {
    customOrdering.channel = ch
    // Clear the other channel's sub-selection so no stale flags leak on save.
    if (ch === 'whatsapp') {
        customOrdering.tableOrdering = customOrdering.tableBillRequests = customOrdering.onlineOrdering = customOrdering.onPickup = customOrdering.onDelivery = false
    } else {
        customOrdering.waPickup = customOrdering.waDelivery = false
    }
}
// Bill requests are a dine-in feature — drop them if table ordering is turned off.
watch(() => customOrdering.tableOrdering, (on) => { if (!on) customOrdering.tableBillRequests = false })
/** Expand the custom ordering selection to feature flags (mirrors PlanForm). */
function customOrderingKeys() {
    const keys = new Set()
    if (customOrdering.channel === 'whatsapp') {
        keys.add('whatsapp_ordering')
        if (customOrdering.waPickup) keys.add('pickup')
        if (customOrdering.waDelivery) keys.add('delivery')
    } else if (customOrdering.channel === 'system') {
        if (customOrdering.tableOrdering) {
            keys.add('system_ordering'); keys.add('dine_in'); keys.add('table_management')
            if (customOrdering.tableBillRequests) keys.add('bill_requests')
        }
        if (customOrdering.onlineOrdering) {
            keys.add('system_ordering')
            if (customOrdering.onPickup) keys.add('pickup')
            if (customOrdering.onDelivery) keys.add('delivery')
        }
    }
    return [...keys]
}
// bill_requests is not here — it's a dine-in sub-option nested under table ordering.
const customCapabilityKeys = ['qr_menu', 'internal_reviews', 'product_analytics', 'multi_branch']
const customCapabilities = ref([])
function toggleCustomCapability(key, on) {
    const i = customCapabilities.value.indexOf(key)
    if (on && i < 0) customCapabilities.value.push(key)
    else if (!on && i >= 0) customCapabilities.value.splice(i, 1)
}
const customFeatureKeys = computed(() => [...new Set([...customCapabilities.value, ...customOrderingKeys()])])
// Prefill a sensible name the first time custom mode is chosen.
watch(planMode, (m) => {
    if (m === 'custom' && !custom.name.trim()) {
        const base = (form.name_en || form.name_ar || form.slug || '').trim()
        if (base) custom.name = `${base} — Custom`
    }
})

// The plan currently driving capabilities: the picked catalog plan, or a
// synthetic view of the inline custom builder. Everything downstream (feature
// preview, branch limit, ordering mode) keys off this.
const effectivePlan = computed(() => {
    if (planMode.value === 'custom') {
        return {
            feature_keys: customFeatureKeys.value,
            max_branches: custom.max_branches === '' ? null : Number(custom.max_branches),
        }
    }
    return plans.value.find(p => p.name === form.subscription_plan) || null
})
const derivedFeatureKeys = computed(() => {
    const resolved = resolveKeys(effectivePlan.value?.feature_keys || [])
    return featureDisplayOrder.filter(k => resolved.has(k))
})
const enabledFeatureLabels = computed(() => derivedFeatureKeys.value.map(k => t(`feature.${k}`)))

// Preview chips: present the ordering flags as the three ordering types (to
// match the plan editor), and the rest as their own capability labels.
const ORDERING_FLAGS = ['whatsapp_ordering', 'system_ordering', 'dine_in', 'pickup', 'delivery', 'table_management', 'customer_tracking']
const previewChips = computed(() => {
    const has = (k) => derivedFeatureKeys.value.includes(k)
    const fulfill = [has('pickup') && t('feature.pickup'), has('delivery') && t('feature.delivery')].filter(Boolean).join(', ')
    const chips = []
    if (has('whatsapp_ordering')) chips.push(fulfill ? `${t('plan.ordering_whatsapp')} (${fulfill})` : t('plan.ordering_whatsapp'))
    if (has('system_ordering')) {
        if (has('dine_in') || has('table_management')) chips.push(t('plan.ordering_table'))
        if (has('pickup') || has('delivery')) chips.push(fulfill ? `${t('plan.ordering_online')} (${fulfill})` : t('plan.ordering_online'))
    }
    for (const k of derivedFeatureKeys.value) {
        if (!ORDERING_FLAGS.includes(k)) chips.push(t(`feature.${k}`))
    }
    return chips
})

// Supported order types are limited to the channels the plan grants: dine_in /
// pickup / delivery are themselves plan features, so a branch can't offer an
// order type the restaurant isn't entitled to. A QR-only plan grants none.
const orderTypes = computed(() => ALL_ORDER_TYPES.filter(tp => derivedFeatureKeys.value.includes(tp)))
// When the plan changes, drop any now-ungranted selection; default to every
// granted type when the selection would otherwise be empty.
watch(orderTypes, (avail) => {
    branch.supported_order_types = branch.supported_order_types.filter(tp => avail.includes(tp))
    if (avail.length && branch.supported_order_types.length === 0) {
        branch.supported_order_types = [...avail]
    }
}, { immediate: true })

// The branch step depends on the chosen plan: a plan must be selected first,
// and its max_branches (null = unlimited) must permit at least the one branch
// the wizard creates. If the plan changes to one that disallows branches,
// disable the branch so the user can't submit an over-limit configuration.
const planBranchLimit = computed(() => {
    const mb = effectivePlan.value?.max_branches
    return (mb === null || mb === undefined) ? null : Number(mb) // null = unlimited
})
const branchAllowed = computed(() => {
    if (!effectivePlan.value) return false // must pick a plan before adding branches
    return planBranchLimit.value === null || planBranchLimit.value >= 1
})
watch(branchAllowed, (ok) => { if (!ok) branchEnabled.value = false })

// The ordering-mode choice is capped to the channels the selected plan grants.
// The two channels are mutually exclusive: even when both are entitled the owner
// picks one — WhatsApp or system, never both.
const orderingModeOptions = computed(() => {
    const has = (k) => derivedFeatureKeys.value.includes(k)
    if (has('whatsapp_ordering') && has('system_ordering')) return ['whatsapp', 'system']
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
            // A QR-only plan grants no order types, so don't require one; when the
            // plan does grant channels, at least one must be selected.
            return ((showEn.value && branch.name_en.trim()) || (showAr.value && branch.name_ar.trim()))
                && (orderTypes.value.length === 0 || branch.supported_order_types.length > 0)
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

// Live per-field validation: revalidate a single field as the user types, so
// format errors surface immediately instead of only on submit. The collectors
// treat empty as valid, so untouched/optional fields stay clean.
function setFieldError(field, msgs) {
    const next = { ...errors.value }
    if (msgs) next[field] = msgs
    else delete next[field]
    errors.value = next
}
function validateEmailField() {
    setFieldError('admin.email', collectEmailErrors({ 'admin.email': form.admin.email }, t('restaurant.email_invalid'))['admin.email'])
}
function validatePhoneField(field) {
    const value = field.startsWith('branch.') ? branch[field.slice(7)] : form[field]
    setFieldError(field, collectPhoneErrors({ [field]: value }, t('restaurant.phone_invalid'))[field])
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
    if (/^(features|subscription_plan|licence\.)/.test(key)) return 4
    return 3
}

async function submitEdit() {
    errors.value = {}
    const phoneErrors = collectPhoneErrors(
        { phone: form.phone, whatsapp_number: form.whatsapp_number },
        t('restaurant.phone_invalid'),
    )
    if (Object.keys(phoneErrors).length) {
        errors.value = phoneErrors
        currentStep.value = stepForError(Object.keys(phoneErrors)[0])
        return
    }
    saving.value = true
    try {
        await ensureCsrf()
        // Subscription (plan/status/dates) is managed on the Subscription section,
        // not here — drop those fields so saving this form can't revert a change
        // made there. Features are derived from the plan server-side; the edit load
        // populates form.features, which the update request rejects — drop it too.
        const payload = { ...form }
        delete payload.admin; delete payload.features
        delete payload.subscription_plan; delete payload.subscription_status
        delete payload.subscription_start_date; delete payload.subscription_end_date
        await api.put(`api/admin/restaurants/${route.params.id}`, payload)
        router.push({ name: 'admin.restaurants.show', params: { id: route.params.id } })
    } catch (err) {
        errors.value = err.response?.data?.errors || {}
    } finally {
        saving.value = false
    }
}

async function submitCreate() {
    errors.value = {}
    const phoneFields = { phone: form.phone, whatsapp_number: form.whatsapp_number }
    if (branchEnabled.value) {
        phoneFields['branch.phone'] = branch.phone
        phoneFields['branch.whatsapp_number'] = branch.whatsapp_number
    }
    const clientErrors = {
        ...collectPhoneErrors(phoneFields, t('restaurant.phone_invalid')),
        ...collectEmailErrors({ 'admin.email': form.admin.email }, t('restaurant.email_invalid')),
    }
    if (planMode.value === 'custom' && !custom.name.trim()) {
        clientErrors.subscription_plan = [t('wizard.custom_plan_name_required')]
    }
    if (Object.keys(clientErrors).length) {
        errors.value = clientErrors
        currentStep.value = stepForError(Object.keys(clientErrors)[0])
        return
    }
    saving.value = true
    try {
        await ensureCsrf()
        // Create the custom plan first (inactive, so it stays off the public
        // pricing page), then attach the restaurant to it by name.
        if (planMode.value === 'custom') {
            const name = custom.name.trim()
            if (createdCustomPlan.value !== name) {
                try {
                    const { data: planRes } = await api.post('api/admin/plans', {
                        name,
                        price: custom.price === '' ? null : Number(custom.price),
                        currency: form.currency,
                        feature_keys: customFeatureKeys.value,
                        max_branches: custom.max_branches === '' ? null : Number(custom.max_branches),
                        max_items: custom.max_items === '' ? null : Number(custom.max_items),
                        max_categories: custom.max_categories === '' ? null : Number(custom.max_categories),
                        is_active: false,
                        is_recommended: false,
                        sort_order: 0,
                    })
                    createdCustomPlan.value = planRes.data.name
                } catch (err) {
                    const pe = err.response?.data?.errors || {}
                    // Surface the plan-name collision on the field shown in step 4.
                    errors.value = pe.name ? { subscription_plan: pe.name, ...pe } : pe
                    currentStep.value = 4
                    saving.value = false
                    return
                }
            }
            form.subscription_plan = createdCustomPlan.value
        }
        form.bilingual = langConfig.value === 'bilingual'
        form.default_language = primaryLanguage.value
        // Features are derived from the plan server-side — send the plan, not flags.
        const payload = { ...form }
        if (branchEnabled.value) payload.branch = { ...branch }
        // The licence is minted inside the same transaction as the tenant, so
        // this is the only chance to say what it covers.
        payload.licence = { ...(payload.licence || {}), modes: [...licenceModes.value] }
        const { data } = await api.post('api/admin/restaurants', payload)
        createdLicence.value = data.licence || null
        activationKey.value = data.activation_key || ''
        createdRestaurantId.value = data.data.id
        // Either secret keeps the operator on this screen: both are shown once.
        if (data.generated_password) generatedPassword.value = data.generated_password
        else if (activationKey.value) createdDone.value = true
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

        <!-- Created: the two one-shot secrets, then where to go next. -->
        <div v-if="generatedPassword || createdDone" class="card p-5 mb-4" style="border-color:var(--green);background:var(--green-soft)">
            <div v-if="generatedPassword">
                <p class="font-medium" style="color:var(--green)">{{ t('restaurant.generated_password') }}</p>
                <p class="mono text-2xl mt-1" style="color:var(--ink)">{{ generatedPassword }}</p>
                <p class="text-sm mt-1" style="color:var(--green)">{{ t('restaurant.generated_password_note') }}</p>
            </div>

            <!-- The licence is created WITH the client, in the same
                 transaction — if this block is missing, so is the client. -->
            <div v-if="activationKey" :class="generatedPassword ? 'mt-4 pt-4 border-t' : ''" style="border-color:var(--green)">
                <p class="font-medium" style="color:var(--green)">{{ t('restaurant.created_licence_title') }}</p>
                <p v-if="createdLicence" class="mono text-sm mt-1" style="color:var(--body)">{{ createdLicence.licence_ref }}</p>
                <p class="label mt-2">{{ t('licence.activation_key') }}</p>
                <p class="mono text-2xl" style="color:var(--ink)">{{ activationKey }}</p>
                <p class="text-sm mt-1" style="color:var(--green)">{{ t('licence.key_once_warning') }}</p>
            </div>

            <!-- Terminals are not part of creating a client. Said out loud so
                 an empty terminal list does not read as a failed setup. -->
            <p class="text-sm mt-4" style="color:var(--green)">{{ t('restaurant.created_licence_note') }}</p>

            <div class="flex flex-wrap gap-2 mt-3">
                <RouterLink v-if="createdRestaurantId" :to="{ name: 'admin.restaurants.show', params: { id: createdRestaurantId } }" class="btn btn-dark">
                    {{ t('common.done') }} {{ forwardArrow }}
                </RouterLink>
                <RouterLink :to="{ name: 'admin.restaurants' }" class="btn btn-ghost">{{ t('admin.manage_restaurants') }}</RouterLink>
            </div>
        </div>

        <!-- ===================== EDIT MODE (single form) ===================== -->
        <form v-if="!generatedPassword && !createdDone && isEdit" @submit.prevent="submitEdit" class="space-y-5">
            <div class="card p-6 space-y-4">
                <h2 class="h-card">{{ t('admin.restaurant') }}</h2>
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                    <label class="block"><span class="label">{{ t('common.name_en') }}</span>
                        <input v-model="form.name_en" class="input" />
                        <FormError :errors="errors" field="name_en" /></label>
                    <label class="block"><span class="label">{{ t('common.name_ar') }}</span>
                        <input v-model="form.name_ar" class="input" dir="rtl" /></label>
                </div>
                <label class="block"><span class="label">{{ t('restaurant.slug') }}</span>
                    <div dir="ltr" class="flex items-center mt-1.5 rounded-lg border overflow-hidden" style="border-color:var(--line)">
                        <input v-model="form.slug" class="flex-1 px-3 py-2.5 text-sm mono" style="border:0;outline:0;background:var(--card);color:var(--ink)" />
                        <span class="mono text-sm px-3 py-2.5" style="background:var(--page);color:var(--muted)">{{ slugSuffix }}</span>
                    </div>
                    <p class="text-xs mt-1" style="color:var(--amber)">{{ t('restaurant.slug_warning') }}</p>
                    <FormError :errors="errors" field="slug" /></label>
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                    <label class="block"><span class="label">{{ t('restaurant.phone') }}</span><input v-model="form.phone" @input="validatePhoneField('phone')" class="input" dir="ltr" data-en-digits />
                        <FormError :errors="errors" field="phone" /></label>
                    <label class="block"><span class="label">{{ t('restaurant.whatsapp') }}</span><input v-model="form.whatsapp_number" @input="validatePhoneField('whatsapp_number')" class="input" dir="ltr" data-en-digits />
                        <FormError :errors="errors" field="whatsapp_number" /></label>
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
                <div>
                    <span class="label">{{ t('restaurant.menu_layout') }}</span>
                    <select v-model="form.menu_layout" class="input mt-1.5">
                        <option v-for="m in menuLayouts" :key="m" :value="m">{{ t('restaurant.menu_layout_' + m.replace('-', '_')) }}</option>
                    </select>
                    <span class="block text-xs mt-1.5" style="color:var(--muted)">{{ t('restaurant.menu_layout_hint') }}</span>
                    <FormError :errors="errors" field="menu_layout" />
                </div>
                <div>
                    <span class="label">{{ t('restaurant.language') }}</span>
                    <div class="flex gap-2 mt-1.5 flex-wrap">
                        <button v-for="opt in ['ar_only', 'en_only', 'bilingual']" :key="opt" type="button" @click="setEditLang(opt)"
                            class="btn" :class="editLangValue === opt ? 'btn-dark' : 'btn-ghost'">{{ langOptionLabel(opt) }}</button>
                    </div>
                    <span class="block text-xs mt-1.5" style="color:var(--muted)">{{ t('restaurant.bilingual_hint') }}</span>
                    <!-- Bilingual clients choose which language the menu opens in by default. -->
                    <div v-if="editLangValue === 'bilingual'" class="mt-3">
                        <span class="label">{{ t('wizard.primary_language') }}</span>
                        <div class="flex gap-2 mt-1.5">
                            <button v-for="lng in ['ar', 'en']" :key="lng" type="button" @click="form.default_language = lng"
                                class="btn" :class="form.default_language === lng ? 'btn-dark' : 'btn-ghost'">{{ t(`languages.${lng}`) }}</button>
                        </div>
                        <p class="text-xs mt-1.5" style="color:var(--muted)">{{ t('wizard.primary_help') }}</p>
                    </div>
                    <FormError :errors="errors" field="default_language" />
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

            <!-- Plan & subscription are managed on the restaurant's Subscription
                 section (RestaurantDetails), not here — keeping them in both places
                 let this form silently revert a plan change made there. -->

            <div class="flex justify-end gap-2">
                <RouterLink :to="{ name: 'admin.restaurants' }" class="btn btn-ghost">{{ t('common.cancel') }}</RouterLink>
                <button type="submit" :disabled="saving" class="btn btn-accent">{{ saving ? t('common.saving') : t('admin.save_changes') }}</button>
            </div>
        </form>

        <!-- ===================== CREATE MODE (wizard) ===================== -->
        <div v-else-if="!generatedPassword && !createdDone">
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
                    <label v-if="showAr" class="block"><span class="label">{{ nameLabelAr }}</span>
                        <input v-model="form.name_ar" class="input" dir="rtl" />
                        <FormError :errors="errors" field="name_ar" /></label>
                </div>
                <label class="block"><span class="label">{{ t('restaurant.slug') }}</span>
                    <div dir="ltr" class="flex items-center mt-1.5 rounded-lg border overflow-hidden" style="border-color:var(--line)">
                        <input v-model="form.slug" @input="slugTouched = true" class="flex-1 px-3 py-2.5 text-sm mono" style="border:0;outline:0;background:var(--card);color:var(--ink)" />
                        <span class="mono text-sm px-3 py-2.5" style="background:var(--page);color:var(--muted)">{{ slugSuffix }}</span>
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
                    <label class="block"><span class="label">{{ t('restaurant.admin_name') }}</span>
                        <input v-model="form.admin.name" class="input" />
                        <FormError :errors="errors" field="admin.name" /></label>
                    <label class="block mt-3"><span class="label">{{ t('restaurant.admin_username') }}</span>
                        <input v-model="form.admin.username" type="text" autocapitalize="none" spellcheck="false" class="input" dir="ltr" />
                        <span class="block text-xs mt-1" style="color:var(--muted)">{{ t('restaurant.admin_username_hint') }}</span>
                        <FormError :errors="errors" field="admin.username" /></label>
                    <label class="block mt-3"><span class="label">{{ t('restaurant.admin_email') }}</span>
                        <input v-model="form.admin.email" @input="validateEmailField" type="email" class="input" />
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
                    <label class="block"><span class="label">{{ t('restaurant.phone') }}</span><input v-model="form.phone" @input="validatePhoneField('phone')" class="input" dir="ltr" data-en-digits />
                        <FormError :errors="errors" field="phone" /></label>
                    <label class="block"><span class="label">{{ t('restaurant.whatsapp') }}</span><input v-model="form.whatsapp_number" @input="validatePhoneField('whatsapp_number')" class="input" dir="ltr" data-en-digits />
                        <FormError :errors="errors" field="whatsapp_number" /></label>
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
                <p v-if="!effectivePlan" class="text-sm rounded-lg p-3" style="background:var(--page);color:var(--muted)">{{ t('wizard.branch_needs_plan') }}</p>
                <p v-else-if="!branchAllowed" class="text-sm rounded-lg p-3" style="background:var(--page);color:var(--muted)">{{ t('wizard.branch_not_in_plan') }}</p>
                <p v-if="branchAllowed && planBranchLimit !== null" class="text-xs" style="color:var(--muted)">{{ t('wizard.branch_limit', { n: planBranchLimit }) }}</p>
                <p v-if="branchAllowed && !branchEnabled" class="text-sm rounded-lg p-3" style="background:var(--page);color:var(--muted)">{{ t('wizard.branch_skip_note') }}</p>
                <template v-if="branchAllowed && branchEnabled">
                    <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                        <label v-if="showEn" class="block"><span class="label">{{ nameLabelEn }}</span>
                            <input v-model="branch.name_en" class="input" />
                            <FormError :errors="errors" field="branch.name_en" /></label>
                        <label v-if="showAr" class="block"><span class="label">{{ nameLabelAr }}</span>
                            <input v-model="branch.name_ar" class="input" dir="rtl" /></label>
                    </div>
                    <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
                        <label class="block"><span class="label">{{ t('wizard.branch_code') }}</span><input v-model="branch.code" class="input" /></label>
                        <label class="block"><span class="label">{{ t('wizard.branch_city') }}</span><input v-model="branch.city" class="input" /></label>
                        <label class="block"><span class="label">{{ t('wizard.branch_country') }}</span>
                            <select v-model="branch.country" class="input">
                                <option value="">{{ t('wizard.branch_country_select') }}</option>
                                <option v-for="c in branchCountries" :key="c" :value="c">{{ t(`country.${c}`) }}</option>
                            </select></label>
                    </div>
                    <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                        <label class="block"><span class="label">{{ t('restaurant.phone') }}</span><input v-model="branch.phone" @input="validatePhoneField('branch.phone')" class="input" dir="ltr" data-en-digits />
                            <FormError :errors="errors" field="branch.phone" /></label>
                        <label class="block"><span class="label">{{ t('restaurant.whatsapp') }}</span><input v-model="branch.whatsapp_number" @input="validatePhoneField('branch.whatsapp_number')" class="input" dir="ltr" data-en-digits />
                            <FormError :errors="errors" field="branch.whatsapp_number" /></label>
                    </div>
                    <div>
                        <span class="label">{{ t('wizard.order_types') }}</span>
                        <div v-if="orderTypes.length" class="flex flex-wrap gap-2 mt-1.5">
                            <button v-for="tp in orderTypes" :key="tp" type="button" @click="toggleOrderType(tp)"
                                class="btn" :class="branch.supported_order_types.includes(tp) ? 'btn-dark' : 'btn-ghost'">{{ t(`order_type.${tp}`) }}</button>
                        </div>
                        <p v-else class="text-sm rounded-lg p-3 mt-1.5" style="background:var(--page);color:var(--muted)">{{ t('wizard.order_types_none') }}</p>
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

                <!-- Creation only: the licence is minted with the tenant, and
                     editing one afterwards is the standalone licence form's job. -->
                <div v-if="!isEdit" class="space-y-2 pb-2" style="border-bottom:1px solid var(--line)">
                    <span class="label">{{ t('licence.modes') }}</span>
                    <p class="text-xs" style="color:var(--muted)">{{ t('licence.modes_hint') }}</p>
                    <div class="grid grid-cols-1 sm:grid-cols-2 gap-2">
                        <label v-for="m in POS_MODES" :key="m" class="flex items-center gap-2 rounded-lg border p-2.5 cursor-pointer"
                            :style="{ borderColor: licenceModes.includes(m) ? 'var(--accent)' : 'var(--line)' }">
                            <input type="checkbox" :checked="licenceModes.includes(m)"
                                @change="togglePosMode(m, $event.target.checked)" class="h-4 w-4" />
                            <span class="text-sm" style="color:var(--ink)">{{ t('licence.mode.' + m) }}</span>
                        </label>
                    </div>
                    <FormError :errors="errors" field="licence.modes" />
                </div>

                <div>
                    <span class="label">{{ t('wizard.plan_group') }}</span>
                    <div class="flex gap-2 mt-1.5">
                        <button type="button" @click="planMode = 'existing'" class="btn" :class="planMode === 'existing' ? 'btn-dark' : 'btn-ghost'">{{ t('wizard.plan_existing') }}</button>
                        <button type="button" @click="planMode = 'custom'" class="btn" :class="planMode === 'custom' ? 'btn-dark' : 'btn-ghost'">{{ t('wizard.plan_custom') }}</button>
                    </div>
                </div>

                <label v-if="planMode === 'existing'" class="block">
                    <select v-model="form.subscription_plan" class="input">
                        <option value="">{{ t('wizard.select_plan') }}</option>
                        <option v-for="p in plans" :key="p.id" :value="p.name">{{ p.name }}</option>
                    </select>
                    <span class="block text-xs mt-1" style="color:var(--muted)">{{ t('wizard.plan_help') }}</span>
                    <FormError :errors="errors" field="subscription_plan" /></label>

                <!-- Custom plan builder — mirrors the plan editor; saved as an inactive plan. -->
                <div v-else class="space-y-4 rounded-lg p-4" style="border:1px solid var(--line);background:var(--page)">
                    <p class="text-xs" style="color:var(--muted)">{{ t('wizard.custom_plan_note') }}</p>
                    <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
                        <label class="block sm:col-span-2"><span class="label">{{ t('wizard.custom_plan_name') }}</span>
                            <input v-model="custom.name" class="input" />
                            <FormError :errors="errors" field="subscription_plan" /></label>
                        <label class="block"><span class="label">{{ t('plan.price') }}</span>
                            <input v-model="custom.price" type="number" min="0" step="0.01" class="input" data-en-digits :placeholder="t('plan.price_hint')" /></label>
                    </div>

                    <div class="block">
                        <span class="label">{{ t('plan.ordering') }}</span>
                        <div class="grid grid-cols-1 sm:grid-cols-2 gap-2 mt-1">
                            <label class="flex items-center gap-2 rounded-lg border p-2.5 cursor-pointer" :style="{ borderColor: customOrdering.channel === 'whatsapp' ? 'var(--accent)' : 'var(--line)' }">
                                <input type="radio" name="custom-channel" :checked="customOrdering.channel === 'whatsapp'" @change="setCustomChannel('whatsapp')" class="h-4 w-4" />
                                <span class="text-sm" style="color:var(--ink)">{{ t('plan.ordering_whatsapp') }}</span>
                            </label>
                            <label class="flex items-center gap-2 rounded-lg border p-2.5 cursor-pointer" :style="{ borderColor: customOrdering.channel === 'system' ? 'var(--accent)' : 'var(--line)' }">
                                <input type="radio" name="custom-channel" :checked="customOrdering.channel === 'system'" @change="setCustomChannel('system')" class="h-4 w-4" />
                                <span class="text-sm" style="color:var(--ink)">{{ t('plan.ordering_system') }}</span>
                            </label>
                        </div>
                        <div v-if="customOrdering.channel === 'whatsapp'" class="mt-2 ps-3 border-s-2" style="border-color:var(--line)">
                            <span class="text-xs" style="color:var(--muted)">{{ t('plan.ordering_fulfillment') }}</span>
                            <div class="flex gap-4 mt-1">
                                <label class="flex items-center gap-2 text-sm cursor-pointer"><input type="checkbox" v-model="customOrdering.waPickup" class="h-4 w-4" />{{ t('feature.pickup') }}</label>
                                <label class="flex items-center gap-2 text-sm cursor-pointer"><input type="checkbox" v-model="customOrdering.waDelivery" class="h-4 w-4" />{{ t('feature.delivery') }}</label>
                            </div>
                        </div>
                        <div v-else-if="customOrdering.channel === 'system'" class="mt-2 ps-3 border-s-2 space-y-2" style="border-color:var(--line)">
                            <label class="flex items-center gap-2 text-sm cursor-pointer"><input type="checkbox" v-model="customOrdering.tableOrdering" class="h-4 w-4" />{{ t('plan.ordering_table') }}</label>
                            <div v-if="customOrdering.tableOrdering" class="ps-6">
                                <label class="flex items-center gap-2 text-sm cursor-pointer"><input type="checkbox" v-model="customOrdering.tableBillRequests" class="h-4 w-4" />{{ t('feature.bill_requests') }}</label>
                            </div>
                            <label class="flex items-center gap-2 text-sm cursor-pointer"><input type="checkbox" v-model="customOrdering.onlineOrdering" class="h-4 w-4" />{{ t('plan.ordering_online') }}</label>
                            <div v-if="customOrdering.onlineOrdering" class="ps-6">
                                <span class="text-xs" style="color:var(--muted)">{{ t('plan.ordering_fulfillment') }}</span>
                                <div class="flex gap-4 mt-1">
                                    <label class="flex items-center gap-2 text-sm cursor-pointer"><input type="checkbox" v-model="customOrdering.onPickup" class="h-4 w-4" />{{ t('feature.pickup') }}</label>
                                    <label class="flex items-center gap-2 text-sm cursor-pointer"><input type="checkbox" v-model="customOrdering.onDelivery" class="h-4 w-4" />{{ t('feature.delivery') }}</label>
                                </div>
                            </div>
                        </div>
                        <FormError :errors="errors" field="feature_keys" />
                    </div>

                    <div class="block">
                        <span class="label">{{ t('plan.capabilities') }}</span>
                        <div class="grid grid-cols-1 sm:grid-cols-2 gap-2 mt-1">
                            <label v-for="key in customCapabilityKeys" :key="key" class="flex items-center gap-2 rounded-lg border p-2.5 cursor-pointer" style="border-color:var(--line)">
                                <input type="checkbox" :checked="customCapabilities.includes(key)" @change="toggleCustomCapability(key, $event.target.checked)" class="h-4 w-4" />
                                <span class="text-sm" style="color:var(--ink)">{{ t(`feature.${key}`) }}</span>
                            </label>
                        </div>
                    </div>

                    <div class="block">
                        <span class="label">{{ t('plan.limits') }}</span>
                        <p class="text-xs mb-2" style="color:var(--muted)">{{ t('plan.limits_hint') }}</p>
                        <div class="grid grid-cols-1 sm:grid-cols-3 gap-4 items-start">
                            <label class="block"><span class="label">{{ t('plan.max_branches') }}</span>
                                <input v-model="custom.max_branches" type="number" min="1" step="1" class="input" data-en-digits :placeholder="t('plan.unlimited')" />
                                <FormError :errors="errors" field="max_branches" /></label>
                            <label class="block"><span class="label">{{ t('plan.max_items') }}</span>
                                <input v-model="custom.max_items" type="number" min="1" step="1" class="input" data-en-digits :placeholder="t('plan.unlimited')" />
                                <FormError :errors="errors" field="max_items" /></label>
                            <label class="block"><span class="label">{{ t('plan.max_categories') }}</span>
                                <input v-model="custom.max_categories" type="number" min="1" step="1" class="input" data-en-digits :placeholder="t('plan.unlimited')" />
                                <FormError :errors="errors" field="max_categories" /></label>
                        </div>
                    </div>
                </div>

                <div class="pt-2" style="border-top:1px solid var(--line)">
                    <h3 class="label" style="margin:0">{{ t('wizard.features_derived') }}</h3>
                    <div v-if="derivedFeatureKeys.length" class="flex flex-wrap gap-2 mt-2">
                        <span v-for="(chip, i) in previewChips" :key="i" class="rounded-full px-3 py-1 text-xs" style="background:var(--page);border:1px solid var(--line);color:var(--ink)">{{ chip }}</span>
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
