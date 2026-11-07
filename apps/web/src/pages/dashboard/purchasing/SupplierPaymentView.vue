<script setup>
import { ref, computed, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute, useRouter } from 'vue-router'
import api from '@xorder/api-client/api.js'
import { useAuth } from '@xorder/api-client/auth.js'
import { withMinDuration } from '../../../lib/minLoading.js'
import { pickLocalized } from '@xorder/ui/localize.js'
import Skeleton from '@xorder/ui/Skeleton.vue'
import ErrorState from '@xorder/ui/ErrorState.vue'
import Icon from '@xorder/ui/Icon.vue'
import { alert } from '@xorder/ui/alert.js'
import ReasonDialog from './ReasonDialog.vue'
import { PAYMENT_VOID_REASONS, fmtDay, fmtDate, money } from './format.js'

// CB-09 slice c. One supplier payment: where it went (invoices), what stayed
// on account, and the till pay-out it came out of, if any. Voiding keeps it on
// record and gives back whatever it paid on each invoice.
const { t, locale } = useI18n()
const route = useRoute()
const router = useRouter()
const auth = useAuth()
const canWrite = computed(() => auth.can('purchase.manage') && !auth.isReadOnly)

const payment = ref(null)
const loading = ref(true)
const failed = ref(false)
const busy = ref(false)
const showVoid = ref(false)
const voidErrors = ref({})

async function load() {
    loading.value = true
    failed.value = false
    try {
        const { data } = await withMinDuration(api.get(`api/dashboard/supplier-payments/${route.params.id}`))
        payment.value = data.data
    } catch {
        failed.value = true
    } finally {
        loading.value = false
    }
}
onMounted(load)

const nameOf = (s) => (s ? (pickLocalized(s, 'name', locale.value) || s.name_en || s.name_ar || `#${s.id}`) : '')
const show = (minor) => money(minor, payment.value?.exponent, payment.value?.currency, locale.value)

async function submitVoid({ reason, note }) {
    busy.value = true
    voidErrors.value = {}
    try {
        const { data } = await api.post(`api/dashboard/supplier-payments/${payment.value.id}/void`, { reason, note })
        payment.value = data.data
        showVoid.value = false
    } catch (err) {
        voidErrors.value = err.response?.data?.errors || {}
        if (err.response?.status === 409) { showVoid.value = false; alert(err.response.data.message); load() }
        else if (!Object.keys(voidErrors.value).length) alert(err.response?.data?.message || t('common.error'))
    } finally {
        busy.value = false
    }
}
</script>

<template>
    <div class="space-y-5">
        <button type="button" class="back" @click="router.push({ name: 'dashboard.purchasing.payments' })">
            <Icon name="chevronDown" :size="16" class="rotate-90 rtl:-rotate-90" />{{ t('purchasing.payments_title') }}
        </button>

        <ErrorState v-if="failed" :message="t('common.error')" @retry="load" />

        <div v-else-if="loading || !payment" class="space-y-5">
            <div class="card p-5 space-y-3">
                <Skeleton w="40%" h="28px" /><Skeleton w="60%" h="14px" />
                <Skeleton w="100%" h="56px" />
            </div>
            <Skeleton w="100%" h="160px" rounded="15px" />
        </div>

        <template v-else>
            <!-- Document header -->
            <header class="card doc-head">
                <div class="flex flex-wrap items-start justify-between gap-4">
                    <div class="min-w-0 space-y-1.5">
                        <h1 class="page-title doc-title flex flex-wrap items-center gap-x-3 gap-y-2">
                            <span>{{ t('purchasing.payment_ref', { id: payment.id }) }}</span>
                            <span v-if="payment.is_voided" class="badge badge-gray">{{ t('purchasing.voided') }}</span>
                        </h1>
                        <p class="doc-sub">
                            <RouterLink :to="{ name: 'dashboard.purchasing.supplier', params: { id: payment.supplier_id } }">{{ payment.supplier_name }}</RouterLink>
                            · {{ nameOf(payment.branch) }}
                        </p>
                    </div>
                    <div v-if="canWrite && payment.can_void" class="actions">
                        <div class="actions-danger">
                            <button type="button" class="btn btn-danger" :disabled="busy" @click="voidErrors = {}; showVoid = true">{{ t('purchasing.void_payment') }}</button>
                        </div>
                    </div>
                </div>

                <dl class="doc-meta">
                    <div><dt>{{ t('purchasing.paid_at') }}</dt><dd>{{ fmtDay(payment.paid_at, locale) }}</dd></div>
                    <div><dt>{{ t('purchasing.method') }}</dt><dd>{{ t('purchasing.methods.' + payment.method) }}</dd></div>
                    <div class="span-2"><dt>{{ t('purchasing.payment_reference') }}</dt><dd class="mono"><span dir="ltr">{{ payment.reference || '—' }}</span></dd></div>
                    <div v-if="payment.cash_movement" class="span-all">
                        <dt>{{ t('purchasing.till_payout') }}</dt>
                        <dd>{{ fmtDate(payment.cash_movement.occurred_at, locale, { time: true }) }} · <span class="mono">{{ show(payment.cash_movement.amount_minor) }}</span> · {{ payment.cash_movement.reason }}</dd>
                    </div>
                    <div v-if="payment.note" class="span-all"><dt>{{ t('purchasing.notes') }}</dt><dd class="meta-note">{{ payment.note }}</dd></div>
                </dl>
            </header>

            <div v-if="payment.is_voided" class="note note-gray" role="status">
                <i class="pi pi-ban" aria-hidden="true" />
                <span>
                    {{ t('purchasing.voided_on', { date: fmtDate(payment.voided_at, locale) }) }}:
                    {{ t('purchasing.payment_void_reasons.' + payment.void_reason) }}<span v-if="payment.void_note"> · {{ payment.void_note }}</span>
                </span>
            </div>

            <!-- Where the money went: the amount is the dominant figure -->
            <section class="card overflow-hidden">
                <h2 class="section-title">{{ t('purchasing.allocations') }}</h2>
                <p v-if="!payment.allocations || !payment.allocations.length" class="px-5 pb-5 text-sm" style="color:var(--body)">{{ t('purchasing.on_account_hint') }}</p>
                <ul v-else>
                    <li v-for="a in payment.allocations" :key="a.id" class="line-row">
                        <RouterLink :to="{ name: 'dashboard.purchasing.invoice', params: { id: a.supplier_invoice_id } }" class="mono" dir="ltr">{{ a.invoice?.number || '#' + a.supplier_invoice_id }}</RouterLink>
                        <span v-if="a.invoice">{{ t('purchasing.due_at') }} {{ fmtDay(a.invoice.due_at, locale) }}</span>
                        <span class="line-amount mono" :class="payment.is_voided ? 'strike' : ''">{{ show(a.amount_minor) }}</span>
                    </li>
                </ul>
                <div class="totals-wrap">
                    <div class="totals">
                        <div class="totals-row"><span>{{ t('purchasing.allocated') }}</span><span class="mono" :class="payment.is_voided ? 'strike' : ''">{{ show(payment.allocated_minor) }}</span></div>
                        <div class="totals-row"><span>{{ t('purchasing.on_account') }}</span><span class="mono" :class="payment.is_voided ? 'strike' : ''">{{ show(payment.on_account_minor) }}</span></div>
                        <div class="totals-row totals-grand"><span>{{ t('purchasing.amount') }}</span><span class="mono" :class="payment.is_voided ? 'strike' : ''">{{ show(payment.amount_minor) }}</span></div>
                    </div>
                </div>
            </section>
        </template>

        <ReasonDialog
            v-if="showVoid"
            :title="t('purchasing.void_payment_title')"
            :subtitle="payment ? t('purchasing.payment_ref', { id: payment.id }) : ''"
            :message="t('purchasing.void_payment_message')"
            :reasons="PAYMENT_VOID_REASONS"
            label-prefix="purchasing.payment_void_reasons"
            :confirm-text="t('purchasing.void_payment')"
            :busy="busy"
            :errors="voidErrors"
            @submit="submitVoid"
            @close="showVoid = false"
        />
    </div>
</template>

<style scoped>
/* Presentation only: theme variables and the PrimeVue primary scale; no new hex values. */
.back { display: inline-flex; align-items: center; gap: 6px; min-height: 36px; font-size: 14.5px; font-weight: 500; color: var(--body); }
.back:hover { color: var(--p-primary-700); }
.badge-amber { color: var(--p-primary-800); }
.badge-gray { color: var(--body); }
.badge-red { color: var(--red); }
.doc-head { padding: 20px; }
.doc-title { font-family: var(--font-display); font-weight: 700; font-size: 26px; line-height: 1.2; color: var(--ink); }
.doc-sub { font-size: 15px; color: var(--body); }
.doc-sub a { color: var(--p-primary-700); font-weight: 500; }
.doc-sub a:hover { text-decoration: underline; }
.doc-meta { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 16px 20px; margin: 18px 0 0; padding-top: 18px; border-top: 1px solid var(--line); }
@media (min-width: 640px) { .doc-meta { grid-template-columns: repeat(4, minmax(0, 1fr)); } }
.doc-meta dt { font-size: 13.5px; color: var(--body); }
.doc-meta dd { margin: 2px 0 0; font-size: 15px; font-weight: 500; color: var(--ink); overflow-wrap: anywhere; }
.doc-meta .span-all { grid-column: 1 / -1; }
.doc-meta .span-2 { grid-column: span 2 / span 2; }
.doc-meta .meta-note { font-weight: 400; color: var(--body); white-space: pre-line; }
.actions { display: flex; flex-wrap: wrap; align-items: center; gap: 8px; }
.actions .btn { min-height: 44px; }
.actions-danger { margin-inline-start: 4px; padding-inline-start: 12px; border-inline-start: 1px solid var(--line); }
.actions-danger:first-child { margin: 0; padding: 0; border: 0; }
.btn-danger { background: var(--card); color: var(--red); border-color: var(--line); }
.btn-danger:hover:not(:disabled) { border-color: var(--red); background: var(--red-soft); }
@media (max-width: 639px) { .actions { width: 100%; } .actions > .btn { flex: 1 1 auto; justify-content: center; } }
.note { display: flex; align-items: flex-start; gap: 10px; padding: 12px 14px; border-radius: 12px; font-size: 14.5px; line-height: 1.5; }
.note > i { margin-top: 3px; flex: none; }
.note-gray { background: var(--gray-soft); color: var(--ink); }
.totals-wrap { display: flex; justify-content: flex-end; padding: 16px 20px 20px; border-top: 1px solid var(--line); background: var(--page); }
.totals { width: 100%; max-width: 340px; }
.totals-row { display: flex; justify-content: space-between; gap: 12px; padding: 5px 0; font-size: 15px; color: var(--body); }
.totals-row .mono { color: var(--ink); }
.totals-grand { align-items: baseline; margin-top: 8px; padding-top: 12px; border-top: 1px solid var(--line); font-family: var(--font-display); font-weight: 700; font-size: 17px; color: var(--ink); }
.totals-grand .mono { font-size: 26px; line-height: 1.1; }
.section-title { padding: 16px 20px 8px; font-family: var(--font-display); font-weight: 600; font-size: 16.5px; color: var(--ink); }
.line-row { display: flex; flex-wrap: wrap; align-items: center; gap: 6px 14px; min-height: 52px; padding: 10px 20px; border-top: 1px solid var(--line); font-size: 15px; color: var(--body); }
.line-row a { color: var(--p-primary-700); font-weight: 500; }
.line-row a:hover { text-decoration: underline; }
.line-amount { margin-inline-start: auto; font-weight: 600; color: var(--ink); }
.strike { text-decoration: line-through; }
</style>
