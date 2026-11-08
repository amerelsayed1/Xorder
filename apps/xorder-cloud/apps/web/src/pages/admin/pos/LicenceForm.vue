<script setup>
import { reactive, ref, computed, onMounted, watch, nextTick } from 'vue'
import { useRouter, RouterLink } from 'vue-router'
import { useI18n } from 'vue-i18n'
import api from '@xorder/api-client/api.js'
import Icon from '@xorder/ui/Icon.vue'
import Modal from '@xorder/ui/Modal.vue'
import FormError from '@xorder/ui/FormError.vue'
import { focusFirstError } from '@xorder/ui/focusFirstError.js'

const router = useRouter()
const { t, locale } = useI18n()
const backArrow = computed(() => locale.value === 'ar' ? '→' : '←')

// The two CURRENT DeploymentMode.wire values — the model collapsed to
// cloud/offline. Legacy branch_server/standalone stay parseable server-side
// for already-signed licences but are no longer issuable from this form.
// Exactly one (owner, 2026-11-08): the till is two apps, XOrder POS - Cloud
// and XOrder POS - Offline, and each refuses a licence covering both. Still
// sent as a one-value modes[]: that is the signed claim's shape.
const MODES = ['cloud', 'offline']

// Screen order, not the server's rules order.
const FIELD_ORDER = [
    'restaurant_id', 'plan_id', 'issued_at', 'expires_at',
    'modes', 'max_terminals', 'max_offline_days', 'grace_days', 'warn_days', 'notes',
]

const today = new Date().toISOString().slice(0, 10)
const nextYear = new Date(Date.now() + 365 * 864e5).toISOString().slice(0, 10)

const form = reactive({
    restaurant_id: '',
    plan_id: '',
    issued_at: today,
    expires_at: nextYear,
    grace_days: 14,
    warn_days: 30,
    max_terminals: 1,
    // Blank = unlimited, which is the right answer for a cloud terminal. Only
    // an islanded till needs a check-in window.
    max_offline_days: '',
    modes: ['cloud'],
    notes: '',
})

const restaurants = ref([])
const plans = ref([])

// Choosing a client prefills their CURRENT subscription plan — the system
// already knows it, and re-asking invites a mismatch. Still just a prefill
// (D6): the admin can switch to another plan or to "no plan (bespoke terms)",
// and the licence keeps its own copy of whatever is chosen.
watch(() => form.restaurant_id, (id) => {
    const r = restaurants.value.find((x) => x.id === Number(id))
    if (!r) return
    const plan = plans.value.find((p) => p.name === r.subscription_plan)
    form.plan_id = plan ? plan.id : ''
})
const errors = ref({})
const saving = ref(false)

// The issued key, held only long enough to show it once.
const issued = ref(null)
const acknowledged = ref(false)
const copied = ref(false)

const planFeatures = computed(() => {
    const plan = plans.value.find((p) => p.id === Number(form.plan_id))
    return plan?.feature_keys || []
})

onMounted(async () => {
    const [r, p] = await Promise.all([
        api.get('api/admin/restaurants'),
        api.get('api/admin/plans', { params: { active_only: true } }),
    ])
    restaurants.value = r.data.data
    plans.value = p.data.data
})

async function submit() {
    errors.value = {}
    saving.value = true
    try {
        const { data } = await api.post('api/admin/pos/licences', {
            restaurant_id: Number(form.restaurant_id),
            plan_id: form.plan_id === '' ? null : Number(form.plan_id),
            issued_at: form.issued_at,
            expires_at: form.expires_at,
            grace_days: Number(form.grace_days),
            warn_days: Number(form.warn_days),
            max_terminals: Number(form.max_terminals),
            max_offline_days: form.max_offline_days === '' ? null : Number(form.max_offline_days),
            // The plan only prefills the entitlement set — the licence carries
            // its own copy, so editing the plan later cannot silently change
            // what a customer was sold.
            features: planFeatures.value,
            modes: form.modes,
            notes: form.notes || null,
        })
        issued.value = data
    } catch (err) {
        errors.value = err.response?.data?.errors || {}
        // Same reason as the offline form: the button is at the bottom and the
        // bad field is usually above the fold.
        await nextTick()
        focusFirstError(errors.value, FIELD_ORDER)
    } finally {
        saving.value = false
    }
}

async function copyKey() {
    await navigator.clipboard.writeText(issued.value.activation_key)
    copied.value = true
}

function downloadFile() {
    const blob = new Blob([JSON.stringify(issued.value.file, null, 2)], { type: 'application/json' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `${issued.value.data.licence_ref}.xlic`
    a.click()
    URL.revokeObjectURL(url)
}

function finish() {
    router.push({ name: 'admin.licences.show', params: { id: issued.value.data.id } })
}
</script>

<template>
    <div class="max-w-2xl">
        <RouterLink :to="{ name: 'admin.licences' }" class="back-link">{{ backArrow }} {{ t('common.back') }}</RouterLink>
        <h1 class="page-title mb-4">{{ t('licence.issue') }}</h1>

        <form @submit.prevent="submit" class="space-y-5">
            <section class="card p-5 space-y-4">
                <div class="sec-head"><h2 class="h-card">{{ t('licence.sec_client') }}</h2></div>
                <label class="block">
                    <span class="label">{{ t('licence.restaurant') }}</span>
                    <select v-model="form.restaurant_id" class="input">
                        <option value="" disabled>{{ t('licence.pick_restaurant') }}</option>
                        <option v-for="r in restaurants" :key="r.id" :value="r.id">{{ r.name_en || r.name_ar || r.slug }}</option>
                    </select>
                    <FormError :errors="errors" field="restaurant_id" />
                </label>

                <label class="block">
                    <span class="label">{{ t('licence.plan') }}</span>
                    <select v-model="form.plan_id" class="input">
                        <option value="">{{ t('licence.no_plan') }}</option>
                        <option v-for="p in plans" :key="p.id" :value="p.id">{{ p.name }}</option>
                    </select>
                    <p class="help">{{ t('licence.plan_hint') }}</p>
                    <FormError :errors="errors" field="plan_id" />
                </label>
            </section>

            <section class="card p-5 space-y-4">
                <div class="sec-head"><h2 class="h-card">{{ t('licence.sec_term') }}</h2></div>
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                    <label class="block">
                        <span class="label">{{ t('licence.issued_at') }}</span>
                        <input v-model="form.issued_at" type="date" class="input" />
                        <FormError :errors="errors" field="issued_at" />
                    </label>
                    <label class="block">
                        <span class="label">{{ t('licence.expires_at') }}</span>
                        <input v-model="form.expires_at" type="date" class="input" />
                        <FormError :errors="errors" field="expires_at" />
                    </label>
                </div>
            </section>

            <section class="card p-5 space-y-4">
                <div class="sec-head"><h2 class="h-card">{{ t('licence.sec_limits') }}</h2></div>
                <div class="block">
                    <span class="label">{{ t('licence.modes') }}</span>
                    <p class="help" style="margin-top:0;margin-bottom:8px">{{ t('licence.modes_hint') }}</p>
                    <div class="grid grid-cols-1 sm:grid-cols-3 gap-2">
                        <label v-for="m in MODES" :key="m" class="opt cursor-pointer items-center">
                            <input type="radio" name="licence-mode" :checked="form.modes.includes(m)" @change="form.modes = [m]" class="h-4 w-4" />
                            <span class="text-sm">{{ t('licence.mode.' + m) }}</span>
                        </label>
                    </div>
                    <FormError :errors="errors" field="modes" />
                </div>

                <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                    <label class="block">
                        <span class="label">{{ t('licence.max_terminals') }}</span>
                        <input v-model="form.max_terminals" type="number" min="1" class="input" />
                        <p class="help">{{ t('licence.max_terminals_hint') }}</p>
                        <FormError :errors="errors" field="max_terminals" />
                    </label>
                    <label class="block">
                        <span class="label">{{ t('licence.max_offline_days') }}</span>
                        <input v-model="form.max_offline_days" type="number" min="1" class="input" :placeholder="t('licence.unlimited')" />
                        <p class="help">{{ t('licence.max_offline_days_hint') }}</p>
                        <FormError :errors="errors" field="max_offline_days" />
                    </label>
                </div>

                <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                    <label class="block">
                        <span class="label">{{ t('licence.grace_days') }}</span>
                        <input v-model="form.grace_days" type="number" min="0" class="input" />
                        <p class="help">{{ t('licence.grace_days_hint') }}</p>
                        <FormError :errors="errors" field="grace_days" />
                    </label>
                    <label class="block">
                        <span class="label">{{ t('licence.warn_days') }}</span>
                        <input v-model="form.warn_days" type="number" min="0" class="input" />
                        <p class="help">{{ t('licence.warn_days_hint') }}</p>
                        <FormError :errors="errors" field="warn_days" />
                    </label>
                </div>

                <label class="block">
                    <span class="label">{{ t('licence.notes') }}</span>
                    <textarea v-model="form.notes" rows="2" class="input"></textarea>
                    <p class="help">{{ t('licence.notes_hint') }}</p>
                </label>
            </section>

            <div class="form-bar">
                <button type="submit" class="btn btn-accent" :disabled="saving || !form.restaurant_id">{{ t('licence.issue') }}</button>
                <RouterLink :to="{ name: 'admin.licences' }" class="btn btn-ghost">{{ t('common.cancel') }}</RouterLink>
            </div>
        </form>

        <!--
            The key is shown ONCE. The server keeps only an HMAC of it, so there
            is no "show it again" — closing this without copying means reissuing.
            Hence the explicit acknowledgement rather than a dismissable sheet.
        -->
        <Modal v-if="issued" :title="t('licence.issued_title')" :subtitle="t('licence.issued_subtitle')" @close="() => {}">
            <div class="space-y-5">
                <div class="warn-box">
                    <p class="text-sm" style="color:var(--ink)">{{ t('licence.key_once_warning') }}</p>
                </div>

                <div>
                    <span class="label">{{ t('licence.activation_key') }}</span>
                    <div class="flex flex-wrap items-stretch gap-2 mt-1.5">
                        <code class="mono key-box" dir="ltr">{{ issued.activation_key }}</code>
                        <button type="button" class="btn btn-ghost" @click="copyKey">
                            <Icon :name="copied ? 'check' : 'copy'" :size="15" />{{ copied ? t('common.copied') : t('common.copy') }}
                        </button>
                    </div>
                </div>

                <div>
                    <span class="label">{{ t('licence.offline_delivery') }}</span>
                    <p class="help" style="margin-top:0;margin-bottom:8px">{{ t('licence.offline_delivery_hint') }}</p>
                    <button type="button" class="btn btn-ghost" @click="downloadFile">
                        <Icon name="download" :size="15" />{{ t('licence.download') }}
                    </button>
                </div>

                <label class="opt text-sm cursor-pointer">
                    <input type="checkbox" v-model="acknowledged" class="h-4 w-4 mt-0.5" />
                    <span>{{ t('licence.key_acknowledge') }}</span>
                </label>

                <button type="button" class="btn btn-accent w-full" :disabled="!acknowledged" @click="finish">{{ t('common.done') }}</button>
            </div>
        </Modal>
    </div>
</template>

<style scoped>
/* Colours come from the shared theme variables and the PrimeVue primary scale. */
.back-link { display: inline-flex; align-items: center; min-height: 44px; font-size: 14px; font-weight: 500; color: var(--body); }
.back-link:hover { color: var(--ink); }

/* Modal labels are block-level here (the theme's .label is inline, written for forms) */
.label { display: block; margin-bottom: 2px; }
.help { display: block; margin-top: 6px; font-size: 13px; line-height: 1.5; color: var(--body); }

.sec-head { display: flex; flex-direction: column; gap: 2px; }
.sec-head p { font-size: 13.5px; color: var(--body); }

/* Checkbox / radio rows as selectable tiles */
.opt { display: flex; align-items: flex-start; gap: 10px; padding: 12px 14px; border: 1px solid var(--line);
    border-radius: 12px; color: var(--ink); background: var(--card); min-height: 48px; }
.opt:hover { border-color: var(--muted); }
.opt:has(input:checked) { border-color: var(--accent); background: var(--accent-soft); }
.opt-hint { display: block; margin-top: 2px; font-size: 13px; color: var(--body); }

/* Sticky action row: the submit button stays in reach on a long form */
.form-bar { position: sticky; bottom: 0; z-index: 10; display: flex; flex-wrap: wrap; gap: 12px; padding: 14px 0;
    background: var(--page); border-top: 1px solid var(--line); }
.form-bar .btn { min-height: 44px; }

.note { display: flex; align-items: flex-start; gap: 12px; padding: 14px 16px; border-radius: 12px;
    background: var(--card); border: 1px solid var(--line); }
.note-ico { color: var(--body); flex: none; margin-top: 1px; }

/* Issued-key modal */
.warn-box { padding: 12px 14px; border-radius: 12px; background: var(--amber-soft); border: 1px solid var(--accent); }
.key-box { flex: 1 1 220px; min-width: 0; display: flex; align-items: center; padding: 10px 14px; border-radius: 10px;
    border: 1px solid var(--line); background: var(--page); font-size: 16px; letter-spacing: .08em; color: var(--ink);
    overflow-wrap: anywhere; }
</style>
