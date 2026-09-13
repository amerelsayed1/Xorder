<script setup>
import { ref, computed, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute, useRouter } from 'vue-router'
import api from '@xorder/api-client/api.js'
import { useAuth } from '@xorder/api-client/auth.js'
import { withMinDuration } from '../../../lib/minLoading.js'
import { pickLocalized } from '@xorder/ui/localize.js'
import { bpToPercent } from '../../../lib/money.js'
import { formatMilli } from '../../../lib/quantity.js'
import Skeleton from '@xorder/ui/Skeleton.vue'
import ErrorState from '@xorder/ui/ErrorState.vue'
import Icon from '@xorder/ui/Icon.vue'
import { alert } from '@xorder/ui/alert.js'
import ReasonDialog from './ReasonDialog.vue'
import { invoiceBadge, INVOICE_VOID_REASONS, fmtDay, fmtDate, money } from './format.js'

// CB-09 slice c. One supplier invoice: its figures, what was paid against it,
// and, when it bills a purchase order, what that order actually received,
// for comparison only. An invoice never reprices stock.
//
// Edit and void are offered only while nothing live is allocated to it; the
// server re-checks under a lock on the invoice row, so a page left open while
// someone paid it gets a 409, shown, and then the page reloads.
const { t, locale } = useI18n()
const route = useRoute()
const router = useRouter()
const auth = useAuth()
const canWrite = computed(() => auth.can('purchase.manage') && !auth.isReadOnly)

const invoice = ref(null)
const loading = ref(true)
const failed = ref(false)
const busy = ref(false)
const showVoid = ref(false)
const voidErrors = ref({})

async function load() {
    loading.value = true
    failed.value = false
    try {
        const { data } = await withMinDuration(api.get(`api/dashboard/supplier-invoices/${route.params.id}`))
        invoice.value = data.data
    } catch {
        failed.value = true
    } finally {
        loading.value = false
    }
}
onMounted(load)

const nameOf = (s) => (s ? (pickLocalized(s, 'name', locale.value) || s.name_en || s.name_ar || `#${s.id}`) : '')
const show = (minor) => money(minor, invoice.value?.exponent, invoice.value?.currency, locale.value)
const po = computed(() => invoice.value?.purchase_order)
const variance = computed(() => po.value?.variance_minor ?? null)
const varianceText = computed(() => {
    if (variance.value === null) return ''
    if (variance.value === 0) return t('purchasing.variance_none')
    const abs = show(Math.abs(variance.value))
    return variance.value > 0 ? t('purchasing.variance_over', { amount: abs }) : t('purchasing.variance_under', { amount: abs })
})
const locked = computed(() => invoice.value && !invoice.value.is_voided && invoice.value.paid_minor > 0)

async function submitVoid({ reason, note }) {
    busy.value = true
    voidErrors.value = {}
    try {
        const { data } = await api.post(`api/dashboard/supplier-invoices/${invoice.value.id}/void`, { reason, note })
        invoice.value = data.data
        showVoid.value = false
    } catch (err) {
        voidErrors.value = err.response?.data?.errors || {}
        if (err.response?.status === 409) { showVoid.value = false; alert(err.response.data.message); load() }
        else if (!Object.keys(voidErrors.value).length) alert(err.response?.data?.message || t('common.error'))
    } finally {
        busy.value = false
    }
}

function recordPayment() {
    const i = invoice.value
    router.push({ name: 'dashboard.purchasing.payments.create', query: { supplier_id: i.supplier_id, branch_id: i.branch_id, invoice_id: i.id } })
}
</script>

<template>
    <div class="space-y-5">
        <button type="button" class="flex items-center gap-1.5 text-sm" style="color:var(--muted)" @click="router.push({ name: 'dashboard.purchasing.invoices' })">
            <Icon name="chevronDown" :size="16" class="rotate-90 rtl:-rotate-90" />{{ t('purchasing.invoices_title') }}
        </button>

        <ErrorState v-if="failed" :message="t('common.error')" @retry="load" />

        <div v-else-if="loading || !invoice" class="card p-5 space-y-3">
            <Skeleton w="40%" h="22px" /><Skeleton w="60%" h="14px" /><Skeleton w="100%" h="120px" />
        </div>

        <template v-else>
            <div class="flex flex-wrap items-start justify-between gap-3">
                <div class="space-y-1">
                    <h1 class="page-title flex flex-wrap items-center gap-2">
                        <span class="mono" dir="ltr">{{ invoice.number }}</span>
                        <span class="badge" :class="invoiceBadge(invoice.state)">{{ t('purchasing.invoice_states.' + invoice.state) }}</span>
                    </h1>
                    <p class="page-sub">
                        <RouterLink :to="{ name: 'dashboard.purchasing.supplier', params: { id: invoice.supplier_id } }" class="underline">{{ invoice.supplier_name }}</RouterLink>
                        · {{ nameOf(invoice.branch) }}
                    </p>
                </div>
                <div v-if="canWrite" class="flex flex-wrap gap-2">
                    <RouterLink v-if="invoice.can_edit" :to="{ name: 'dashboard.purchasing.invoices.edit', params: { id: invoice.id } }" class="btn btn-ghost">
                        <Icon name="edit" :size="16" />{{ t('purchasing.edit_invoice') }}
                    </RouterLink>
                    <button v-if="invoice.can_void" type="button" class="btn btn-ghost" :disabled="busy" @click="voidErrors = {}; showVoid = true">{{ t('purchasing.void_invoice') }}</button>
                    <button v-if="invoice.can_pay" type="button" class="btn btn-accent" @click="recordPayment">{{ t('purchasing.record_payment') }}</button>
                </div>
            </div>

            <div v-if="invoice.is_voided" class="card p-3 text-sm" style="background:var(--gray-soft);color:var(--ink)">
                {{ t('purchasing.voided_on', { date: fmtDate(invoice.voided_at, locale) }) }}:
                {{ t('purchasing.invoice_void_reasons.' + invoice.void_reason) }}<span v-if="invoice.void_note"> · {{ invoice.void_note }}</span>
            </div>
            <div v-else-if="locked && canWrite" class="card p-3 text-sm" style="background:var(--amber-soft);color:var(--ink)">{{ t('purchasing.invoice_locked_note') }}</div>

            <div class="card p-5 grid grid-cols-2 sm:grid-cols-4 gap-4 text-sm">
                <div><div style="color:var(--muted)">{{ t('purchasing.issued_at') }}</div><div style="color:var(--ink)">{{ fmtDay(invoice.issued_at, locale) }}</div></div>
                <div><div style="color:var(--muted)">{{ t('purchasing.due_at') }}</div>
                    <div style="color:var(--ink)">{{ fmtDay(invoice.due_at, locale) }}</div>
                    <div v-if="invoice.days_late" class="text-xs" style="color:var(--red)">{{ t('purchasing.days_late', { n: invoice.days_late }) }}</div></div>
                <div><div style="color:var(--muted)">{{ t('purchasing.paid') }}</div><div class="mono" dir="ltr" style="color:var(--ink)">{{ show(invoice.paid_minor) }}</div></div>
                <div><div style="color:var(--muted)">{{ t('purchasing.outstanding') }}</div><div class="mono font-semibold" dir="ltr" style="color:var(--ink)">{{ show(invoice.outstanding_minor) }}</div></div>
                <div v-if="invoice.note" class="col-span-2 sm:col-span-4"><div style="color:var(--muted)">{{ t('purchasing.notes') }}</div><div class="whitespace-pre-line" style="color:var(--body)">{{ invoice.note }}</div></div>
            </div>

            <div class="card overflow-hidden">
                <div v-if="invoice.lines && invoice.lines.length" class="overflow-x-auto">
                    <table class="w-full text-sm">
                        <thead>
                            <tr style="color:var(--muted)">
                                <th class="px-4 py-3 text-start font-medium">{{ t('purchasing.line_description') }}</th>
                                <th class="px-4 py-3 text-end font-medium">{{ t('purchasing.quantity') }}</th>
                                <th class="px-4 py-3 text-end font-medium">{{ t('purchasing.unit_cost') }}</th>
                                <th class="px-4 py-3 text-end font-medium">{{ t('purchasing.tax_rate') }}</th>
                                <th class="px-4 py-3 text-end font-medium">{{ t('purchasing.line_total') }}</th>
                            </tr>
                        </thead>
                        <tbody>
                            <tr v-for="l in invoice.lines" :key="l.id" class="border-t" style="border-color:var(--line)">
                                <td class="px-4 py-3" style="color:var(--ink)">{{ l.description }}</td>
                                <td class="px-4 py-3 text-end"><span class="mono" dir="ltr">{{ formatMilli(l.quantity_milli) }}</span></td>
                                <td class="px-4 py-3 text-end"><span class="mono" dir="ltr">{{ show(l.unit_cost_minor) }}</span></td>
                                <td class="px-4 py-3 text-end"><span class="mono" dir="ltr">{{ bpToPercent(l.tax_rate_bp) }}%</span></td>
                                <td class="px-4 py-3 text-end"><span class="mono" dir="ltr">{{ show(l.line_total_minor) }}</span></td>
                            </tr>
                        </tbody>
                    </table>
                </div>
                <div class="px-4 py-3 space-y-1 text-sm" :class="invoice.lines && invoice.lines.length ? 'border-t' : ''" style="border-color:var(--line)">
                    <div class="flex justify-between gap-3"><span style="color:var(--muted)">{{ t('purchasing.subtotal_derived') }}</span><span class="mono" dir="ltr">{{ show(invoice.subtotal_minor) }}</span></div>
                    <div class="flex justify-between gap-3"><span style="color:var(--muted)">{{ t('purchasing.tax') }}</span><span class="mono" dir="ltr">{{ show(invoice.tax_minor) }}</span></div>
                    <div class="flex justify-between gap-3 font-semibold" style="color:var(--ink)"><span>{{ t('purchasing.total') }}</span><span class="mono" dir="ltr">{{ show(invoice.total_minor) }}</span></div>
                </div>
            </div>

            <div v-if="po" class="card p-5 space-y-2 text-sm">
                <div class="flex flex-wrap items-center justify-between gap-2">
                    <h2 class="font-semibold" style="color:var(--ink)">{{ t('purchasing.against_order') }}</h2>
                    <RouterLink :to="{ name: 'dashboard.purchasing.order', params: { id: po.id } }" class="mono underline" dir="ltr">{{ po.reference }}</RouterLink>
                </div>
                <div class="flex justify-between gap-3"><span style="color:var(--muted)">{{ t('purchasing.ordered_total') }}</span><span class="mono" dir="ltr">{{ show(po.ordered_total_minor) }}</span></div>
                <div class="flex justify-between gap-3"><span style="color:var(--muted)">{{ t('purchasing.received_value') }}</span><span class="mono" dir="ltr">{{ show(po.received_value_minor) }}</span></div>
                <div class="flex justify-between gap-3"><span style="color:var(--muted)">{{ t('purchasing.received_total') }}</span><span class="mono" dir="ltr">{{ show(po.received_total_minor) }}</span></div>
                <div class="flex justify-between gap-3 font-medium"><span style="color:var(--ink)">{{ t('purchasing.variance') }}</span>
                    <span class="mono" dir="ltr" :style="variance === 0 ? 'color:var(--green)' : 'color:var(--amber)'">{{ show(variance) }}</span></div>
                <p class="text-xs" style="color:var(--muted)">{{ varianceText }}. {{ t('purchasing.variance_hint') }}</p>
            </div>
            <p v-else-if="invoice.purchase_order_reference" class="text-sm" style="color:var(--muted)">{{ t('purchasing.purchase_order') }}: <span class="mono" dir="ltr">{{ invoice.purchase_order_reference }}</span></p>

            <div class="card overflow-hidden">
                <div class="px-5 py-3 font-semibold" style="color:var(--ink)">{{ t('purchasing.payments_against') }}</div>
                <div v-if="!invoice.allocations || !invoice.allocations.length" class="px-5 pb-5 text-sm" style="color:var(--muted)">{{ t('purchasing.none_payments_against') }}</div>
                <ul v-else>
                    <li v-for="a in invoice.allocations" :key="a.id" class="flex flex-wrap items-center gap-3 px-5 py-3 border-t text-sm" style="border-color:var(--line)" :style="a.payment?.is_voided ? 'opacity:.6' : ''">
                        <RouterLink :to="{ name: 'dashboard.purchasing.payment', params: { id: a.supplier_payment_id } }" class="underline">{{ t('purchasing.payment_ref', { id: a.supplier_payment_id }) }}</RouterLink>
                        <span v-if="a.payment" style="color:var(--body)">{{ fmtDay(a.payment.paid_at, locale) }} · {{ t('purchasing.methods.' + a.payment.method) }}<span v-if="a.payment.reference"> · <span class="mono" dir="ltr">{{ a.payment.reference }}</span></span></span>
                        <span v-if="a.payment?.is_voided" class="badge badge-gray">{{ t('purchasing.voided') }}</span>
                        <span class="ms-auto mono" dir="ltr" :style="a.payment?.is_voided ? 'text-decoration:line-through' : ''">{{ show(a.amount_minor) }}</span>
                    </li>
                </ul>
            </div>
        </template>

        <ReasonDialog
            v-if="showVoid"
            :title="t('purchasing.void_invoice_title')"
            :subtitle="invoice?.number || ''"
            :message="t('purchasing.void_invoice_message')"
            :reasons="INVOICE_VOID_REASONS"
            label-prefix="purchasing.invoice_void_reasons"
            :confirm-text="t('purchasing.void_invoice')"
            :busy="busy"
            :errors="voidErrors"
            @submit="submitVoid"
            @close="showVoid = false"
        />
    </div>
</template>
