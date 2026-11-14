<script setup>
import { reactive, ref, computed, watch, nextTick } from 'vue'
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

// Screen order, which is NOT the order the server validates in — that follows
// its rules array. The topmost error is the one to scroll to.
const FIELD_ORDER = [
    'customer_name', 'customer_slug', 'contact_name', 'contact_phone', 'contact_email',
    'issued_at', 'expires_at', 'lifetime',
    'max_terminals', 'max_users', 'max_offline_days', 'grace_days', 'warn_days', 'notes',
]

const today = new Date().toISOString().slice(0, 10)
const nextYear = new Date(Date.now() + 365 * 864e5).toISOString().slice(0, 10)

const form = reactive({
    customer_name: '',
    customer_slug: '',
    contact_name: '',
    contact_email: '',
    contact_phone: '',
    issued_at: today,
    expires_at: nextYear,
    lifetime: false,
    grace_days: 14,
    warn_days: 30,
    max_terminals: 1,
    // Blank = unlimited. The two numbers below are what an offline licence
    // actually sells — there is no feature ladder on a machine we do not run.
    max_users: '',
    // Blank = never has to come back, which is the honest answer for a site
    // with no internet at all. A number here means the till stops opening new
    // shifts if it has not checked in within that window.
    max_offline_days: '',
    notes: '',
})

const errors = ref({})
const saving = ref(false)

const issued = ref(null)
const acknowledged = ref(false)
const copied = ref(false)

// Typing the business name suggests the identifier, until the operator edits
// it themselves — after that it is theirs and nothing overwrites it.
const slugTouched = ref(false)
watch(() => form.customer_name, (name) => {
    if (slugTouched.value) return
    form.customer_slug = name
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, '-')
        .replace(/^-+|-+$/g, '')
        .slice(0, 64)
})

async function submit() {
    errors.value = {}
    saving.value = true
    try {
        const { data } = await api.post('api/admin/pos/licences/offline', {
            customer_name: form.customer_name,
            customer_slug: form.customer_slug,
            contact_name: form.contact_name || null,
            contact_email: form.contact_email || null,
            contact_phone: form.contact_phone || null,
            issued_at: form.issued_at,
            // Omitted entirely when the licence was sold outright — the server
            // excludes the rule rather than accepting a date it would ignore.
            expires_at: form.lifetime ? null : form.expires_at,
            lifetime: form.lifetime,
            grace_days: Number(form.grace_days),
            warn_days: Number(form.warn_days),
            max_terminals: Number(form.max_terminals),
            max_users: form.max_users === '' ? null : Number(form.max_users),
            max_offline_days: form.max_offline_days === '' ? null : Number(form.max_offline_days),
            // No `features` and no `plan_id`: the server grants every feature
            // to an offline licence and refuses to take either from input.
            notes: form.notes || null,
        })
        issued.value = data
    } catch (err) {
        errors.value = err.response?.data?.errors || {}
        // The submit button is at the foot of a form whose first bad field is
        // usually off the top of the screen. Without this the operator sees a
        // button that appears to do nothing.
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

const canSubmit = computed(() => form.customer_name.trim() !== '' && form.customer_slug.trim() !== '')
</script>

<!--
    An offline customer: licensed, but not hosted.

    Everything this form does NOT ask for is the point. No admin email and
    password, because there is no account here to sign into. No branches,
    because theirs live in their own database. No subscription, because there is
    nothing here to subscribe to. What the platform keeps is the licence
    management minimum — who owns it, what they bought, when it lapses, whether
    it is revoked — and the customer's operational data never leaves their site.
-->
<template>
    <div class="max-w-2xl">
        <RouterLink :to="{ name: 'admin.licences.new' }" class="back-link">{{ backArrow }} {{ t('common.back') }}</RouterLink>
        <h1 class="page-title">{{ t('licence.offline_issue') }}</h1>
        <p class="page-sub mb-4" style="color:var(--body)">{{ t('licence.offline_issue_sub') }}</p>

        <form @submit.prevent="submit" class="space-y-5">
            <section class="card p-5 space-y-4">
                <div class="sec-head"><h2 class="h-card">{{ t('licence.sec_customer') }}</h2></div>
                <label class="block">
                    <span class="label">{{ t('licence.customer_name') }}</span>
                    <input v-model="form.customer_name" class="input" :placeholder="t('licence.customer_name_hint')" />
                    <FormError :errors="errors" field="customer_name" />
                </label>

                <label class="block">
                    <span class="label">{{ t('licence.customer_slug') }}</span>
                    <input v-model="form.customer_slug" class="input mono" dir="ltr" @input="slugTouched = true" />
                    <p class="help">{{ t('licence.customer_slug_hint') }}</p>
                    <FormError :errors="errors" field="customer_slug" />
                </label>

                <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                    <label class="block">
                        <span class="label">{{ t('licence.contact_name') }}</span>
                        <input v-model="form.contact_name" class="input" />
                        <FormError :errors="errors" field="contact_name" />
                    </label>
                    <label class="block">
                        <span class="label">{{ t('licence.contact_phone') }}</span>
                        <input v-model="form.contact_phone" class="input" dir="ltr" inputmode="tel" />
                        <FormError :errors="errors" field="contact_phone" />
                    </label>
                </div>

                <label class="block">
                    <span class="label">{{ t('licence.contact_email') }}</span>
                    <input v-model="form.contact_email" type="email" class="input" dir="ltr" />
                    <p class="help">{{ t('licence.contact_hint') }}</p>
                    <FormError :errors="errors" field="contact_email" />
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
                        <input v-model="form.expires_at" type="date" class="input" :disabled="form.lifetime" />
                        <FormError :errors="errors" field="expires_at" />
                    </label>
                </div>

                <label class="opt text-sm cursor-pointer">
                    <input type="checkbox" v-model="form.lifetime" class="h-4 w-4 mt-0.5" />
                    <span>
                        {{ t('licence.lifetime') }}
                        <span class="opt-hint">{{ t('licence.lifetime_hint') }}</span>
                    </span>
                </label>
            </section>

            <section class="card p-5 space-y-4">
                <!-- What this licence sells. Not features — capacity. -->
                <div class="sec-head">
                    <h2 class="h-card">{{ t('licence.capacity') }}</h2>
                    <p>{{ t('licence.capacity_hint') }}</p>
                </div>

                <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                    <label class="block">
                        <span class="label">{{ t('licence.max_terminals') }}</span>
                        <input v-model="form.max_terminals" type="number" min="1" class="input" />
                        <p class="help">{{ t('licence.max_terminals_offline_hint') }}</p>
                        <FormError :errors="errors" field="max_terminals" />
                    </label>
                    <label class="block">
                        <span class="label">{{ t('licence.max_users') }}</span>
                        <input v-model="form.max_users" type="number" min="1" class="input" :placeholder="t('licence.unlimited')" />
                        <p class="help">{{ t('licence.max_users_hint') }}</p>
                        <FormError :errors="errors" field="max_users" />
                    </label>
                </div>

                <label class="block">
                    <span class="label">{{ t('licence.max_offline_days') }}</span>
                    <input v-model="form.max_offline_days" type="number" min="1" class="input" :placeholder="t('licence.never')" />
                    <p class="help">{{ t('licence.max_offline_days_offline_hint') }}</p>
                    <FormError :errors="errors" field="max_offline_days" />
                </label>

                <div v-if="!form.lifetime" class="grid grid-cols-1 sm:grid-cols-2 gap-4">
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

            <!-- Both stated, not chosen. The mode: cloud means syncing to a
                 tenant and this customer is deliberately not one. The features:
                 gating them on a machine we do not run is a promise we cannot
                 keep, so the customer gets the whole product and the licence
                 sells capacity instead. -->
            <div class="note">
                <Icon name="info" :size="18" class="note-ico" />
                <p class="text-sm" style="color:var(--body)">
                    {{ t('licence.offline_all_features') }}
                    <span class="block mt-1">{{ t('licence.offline_mode_fixed') }}</span>
                </p>
            </div>

            <div class="form-bar">
                <button type="submit" class="btn btn-accent" :disabled="saving || !canSubmit">{{ t('licence.issue') }}</button>
                <RouterLink :to="{ name: 'admin.licences' }" class="btn btn-ghost">{{ t('common.cancel') }}</RouterLink>
            </div>
        </form>

        <!--
            The key is shown ONCE. The server keeps only an HMAC of it, so there
            is no "show it again" — closing this without copying means reissuing.
            For an offline site the FILE is usually the real delivery: it is what
            a till with no internet can be activated from.
        -->
        <Modal v-if="issued" :title="t('licence.issued_title')" :subtitle="t('licence.offline_issued_subtitle')" @close="() => {}">
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
