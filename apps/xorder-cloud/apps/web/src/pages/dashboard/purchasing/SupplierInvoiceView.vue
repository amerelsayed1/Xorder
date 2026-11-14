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
        <button type="button" class="back" @click="router.push({ name: 'dashboard.purchasing.invoices' })">
            <Icon name="chevronDown" :size="16" class="rotate-90 rtl:-rotate-90" />{{ t('purchasing.invoices_title') }}
        </button>

        <ErrorState v-if="failed" :message="t('common.error')" @retry="load" />

        <div v-else-if="loading || !invoice" class="space-y-5">
            <div class="card p-5 space-y-3">
                <Skeleton w="40%" h="28px" /><Skeleton w="60%" h="14px" />
                <Skeleton w="100%" h="56px" />
            </div>
            <Skeleton w="100%" h="220px" rounded="15px" />
        </div>

        <template v-else>
            <!-- Document header -->
            <header class="card doc-head">
                <div class="flex flex-wrap items-start justify-between gap-4">
                    <div class="min-w-0 space-y-1.5">
                        <h1 class="page-title doc-title flex flex-wrap items-center gap-x-3 gap-y-2">
                            <span class="mono" dir="ltr">{{ invoice.number }}</span>
                            <span class="badge" :class="invoiceBadge(invoice.state)">{{ t('purchasing.invoice_states.' + invoice.state) }}</span>
                        </h1>
                        <p class="doc-sub">
                            <RouterLink :to="{ name: 'dashboard.purchasing.supplier', params: { id: invoice.supplier_id } }">{{ invoice.supplier_name }}</RouterLink>
                            · {{ nameOf(invoice.branch) }}
                        </p>
                    </div>
                    <div v-if="canWrite" class="actions">
                        <RouterLink v-if="invoice.can_edit" :to="{ name: 'dashboard.purchasing.invoices.edit', params: { id: invoice.id } }" class="btn btn-ghost">
                            <Icon name="edit" :size="16" />{{ t('purchasing.edit_invoice') }}
                        </RouterLink>
                        <button v-if="invoice.can_pay" type="button" class="btn btn-accent" @click="recordPayment">{{ t('purchasing.record_payment') }}</button>
                        <div v-if="invoice.can_void" class="actions-danger">
                            <button type="button" class="btn btn-danger" :disabled="busy" @click="voidErrors = {}; showVoid = true">{{ t('purchasing.void_invoice') }}</button>
                        </div>
                    </div>
                </div>

                <dl class="doc-meta">
                    <div><dt>{{ t('purchasing.issued_at') }}</dt><dd>{{ fmtDay(invoice.issued_at, locale) }}</dd></div>
                    <div>
                        <dt>{{ t('purchasing.due_at') }}</dt>
                        <dd>{{ fmtDay(invoice.due_at, locale) }}<span v-if="invoice.days_late" class="meta-late">{{ t('purchasing.days_late', { n: invoice.days_late }) }}</span></dd>
                    </div>
                    <div v-if="invoice.note" class="span-2"><dt>{{ t('purchasing.notes') }}</dt><dd class="meta-note">{{ invoice.note }}</dd></div>
                </dl>
            </header>

            <div v-if="invoice.is_voided" class="note note-gray" role="status">
                <i class="pi pi-ban" aria-hidden="true" />
                <span>
                    {{ t('purchasing.voided_on', { date: fmtDate(invoice.voided_at, locale) }) }}:
                    {{ t('purchasing.invoice_void_reasons.' + invoice.void_reason) }}<span v-if="invoice.void_note"> · {{ invoice.void_note }}</span>
                </span>
            </div>
            <div v-else-if="locked && canWrite" class="note note-amber" role="status"><i class="pi pi-lock" aria-hidden="true" /><span>{{ t('purchasing.invoice_locked_note') }}</span></div>

            <!-- Line items, then the totals block (total, paid, still owed) -->
            <section class="card overflow-hidden">
                <div v-if="invoice.lines && invoice.lines.length" class="dtable-wrap">
                    <table class="dtable">
                        <thead>
                            <tr>
                                <th>{{ t('purchasing.line_description') }}</th>
                                <th class="num">{{ t('purchasing.quantity') }}</th>
                                <th class="num">{{ t('purchasing.unit_cost') }}</th>
                                <th class="num">{{ t('purchasing.tax_rate') }}</th>
                                <th class="num">{{ t('purchasing.line_total') }}</th>
                            </tr>
                        </thead>
                        <tbody>
                            <tr v-for="l in invoice.lines" :key="l.id">
                                <td class="primary">{{ l.description }}</td>
                                <td class="num"><span class="mono" dir="ltr">{{ formatMilli(l.quantity_milli) }}</span></td>
                                <td class="num"><span class="mono">{{ show(l.unit_cost_minor) }}</span></td>
                                <td class="num"><span class="mono" dir="ltr">{{ bpToPercent(l.tax_rate_bp) }}%</span></td>
                                <td class="num strong"><span class="mono">{{ show(l.line_total_minor) }}</span></td>
                            </tr>
                        </tbody>
                    </table>
                </div>
                <div class="totals-wrap" :class="invoice.lines && invoice.lines.length ? '' : 'no-lines'">
                    <div class="totals">
                        <div class="totals-row"><span>{{ t('purchasing.subtotal_derived') }}</span><span class="mono">{{ show(invoice.subtotal_minor) }}</span></div>
                        <div class="totals-row"><span>{{ t('purchasing.tax') }}</span><span class="mono">{{ show(invoice.tax_minor) }}</span></div>
                        <div class="totals-row totals-grand"><span>{{ t('purchasing.total') }}</span><span class="mono">{{ show(invoice.total_minor) }}</span></div>
                        <div class="totals-row totals-sep"><span>{{ t('purchasing.paid') }}</span><span class="mono">{{ show(invoice.paid_minor) }}</span></div>
                        <div class="totals-row totals-due"><span>{{ t('purchasing.outstanding') }}</span><span class="mono">{{ show(invoice.outstanding_minor) }}</span></div>
                    </div>
                </div>
            </section>

            <!-- Comparison with the purchase order (information only) -->
            <section v-if="po" class="card kv-card">
                <div class="flex flex-wrap items-center justify-between gap-2 mb-2">
                    <h2 class="h-card">{{ t('purchasing.against_order') }}</h2>
                    <RouterLink :to="{ name: 'dashboard.purchasing.order', params: { id: po.id } }" class="mono list-link" dir="ltr">{{ po.reference }}</RouterLink>
                </div>
                <div class="kv-row"><span>{{ t('purchasing.ordered_total') }}</span><span class="mono">{{ show(po.ordered_total_minor) }}</span></div>
                <div class="kv-row"><span>{{ t('purchasing.received_value') }}</span><span class="mono">{{ show(po.received_value_minor) }}</span></div>
                <div class="kv-row"><span>{{ t('purchasing.received_total') }}</span><span class="mono">{{ show(po.received_total_minor) }}</span></div>
                <div class="kv-row"><span style="color:var(--ink);font-weight:600">{{ t('purchasing.variance') }}</span>
                    <span class="mono" :class="variance === 0 ? 'tone-green' : 'tone-warn'">{{ show(variance) }}</span></div>
                <p class="text-sm mt-2" style="color:var(--body)">{{ varianceText }}. {{ t('purchasing.variance_hint') }}</p>
            </section>
            <p v-else-if="invoice.purchase_order_reference" class="text-sm" style="color:var(--body)">{{ t('purchasing.purchase_order') }}: <span class="mono" dir="ltr">{{ invoice.purchase_order_reference }}</span></p>

            <!-- Payments applied to this invoice -->
            <section class="card overflow-hidden">
                <h2 class="section-title">{{ t('purchasing.payments_against') }}</h2>
                <p v-if="!invoice.allocations || !invoice.allocations.length" class="px-5 pb-5 text-sm" style="color:var(--body)">{{ t('purchasing.none_payments_against') }}</p>
                <ul v-else>
                    <li v-for="a in invoice.allocations" :key="a.id" class="line-row">
                        <RouterLink :to="{ name: 'dashboard.purchasing.payment', params: { id: a.supplier_payment_id } }">{{ t('purchasing.payment_ref', { id: a.supplier_payment_id }) }}</RouterLink>
                        <span v-if="a.payment">{{ fmtDay(a.payment.paid_at, locale) }} · {{ t('purchasing.methods.' + a.payment.method) }}<span v-if="a.payment.reference"> · <span class="mono" dir="ltr">{{ a.payment.reference }}</span></span></span>
                        <span v-if="a.payment?.is_voided" class="badge badge-gray">{{ t('purchasing.voided') }}</span>
                        <span class="line-amount mono" :class="a.payment?.is_voided ? 'strike' : ''">{{ show(a.amount_minor) }}</span>
                    </li>
                </ul>
            </section>
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
.meta-late { display: block; margin-top: 2px; font-size: 13px; font-weight: 600; color: var(--red); }
.actions { display: flex; flex-wrap: wrap; align-items: center; gap: 8px; }
.actions .btn { min-height: 44px; }
.actions-danger { margin-inline-start: 4px; padding-inline-start: 12px; border-inline-start: 1px solid var(--line); }
.actions-danger:first-child { margin: 0; padding: 0; border: 0; }
.btn-danger { background: var(--card); color: var(--red); border-color: var(--line); }
.btn-danger:hover:not(:disabled) { border-color: var(--red); background: var(--red-soft); }
@media (max-width: 639px) { .actions { width: 100%; } .actions > .btn { flex: 1 1 auto; justify-content: center; } }
.note { display: flex; align-items: flex-start; gap: 10px; padding: 12px 14px; border-radius: 12px; font-size: 14.5px; line-height: 1.5; }
.note > i { margin-top: 3px; flex: none; }
.note-amber { background: var(--amber-soft); color: var(--p-primary-800); }
.note-gray { background: var(--gray-soft); color: var(--ink); }
.dtable-wrap { overflow-x: auto; }
.dtable { width: 100%; min-width: 640px; border-collapse: collapse; font-size: 15px; }
.dtable th { padding: 12px 16px; font-size: 13px; font-weight: 600; color: var(--body); background: var(--page); text-align: start; white-space: nowrap; }
.dtable td { padding: 14px 16px; border-top: 1px solid var(--line); color: var(--body); vertical-align: middle; }
.dtable .num { text-align: end; white-space: nowrap; }
.dtable td.num { color: var(--ink); }
.dtable .strong { font-weight: 600; color: var(--ink); }
.dtable .primary { color: var(--ink); font-weight: 500; }
.dtable .nowrap { white-space: nowrap; }
.dtable tbody tr.row-link { cursor: pointer; transition: background .15s; }
.dtable tbody tr.row-link:hover { background: var(--page); }
.dtable tbody tr.row-link:focus-visible { outline: 2px solid var(--accent); outline-offset: -2px; }
.dtable .sub { display: block; margin-top: 2px; font-size: 13px; color: var(--body); }
.totals-wrap { display: flex; justify-content: flex-end; padding: 16px 20px 20px; border-top: 1px solid var(--line); background: var(--page); }
.totals { width: 100%; max-width: 340px; }
.totals-row { display: flex; justify-content: space-between; gap: 12px; padding: 5px 0; font-size: 15px; color: var(--body); }
.totals-row .mono { color: var(--ink); }
.totals-grand { align-items: baseline; margin-top: 8px; padding-top: 12px; border-top: 1px solid var(--line); font-family: var(--font-display); font-weight: 700; font-size: 17px; color: var(--ink); }
.totals-grand .mono { font-size: 26px; line-height: 1.1; }
.section-title { padding: 16px 20px 8px; font-family: var(--font-display); font-weight: 600; font-size: 16.5px; color: var(--ink); }
.list-link { font-size: 14.5px; font-weight: 500; color: var(--p-primary-700); }
.list-link:hover { text-decoration: underline; }
.line-row { display: flex; flex-wrap: wrap; align-items: center; gap: 6px 14px; min-height: 52px; padding: 10px 20px; border-top: 1px solid var(--line); font-size: 15px; color: var(--body); }
.line-row a { color: var(--p-primary-700); font-weight: 500; }
.line-row a:hover { text-decoration: underline; }
.line-amount { margin-inline-start: auto; font-weight: 600; color: var(--ink); }
.kv-card { padding: 20px; }
.kv-row { display: flex; justify-content: space-between; gap: 12px; padding: 7px 0; font-size: 15px; color: var(--body); }
.kv-row + .kv-row { border-top: 1px solid var(--line); }
.kv-row .mono { color: var(--ink); font-weight: 600; }
.tone-green { color: var(--green) !important; }
.tone-warn { color: var(--p-primary-800) !important; }
.totals-sep { margin-top: 10px; padding-top: 10px; border-top: 1px dashed var(--line); }
.totals-due { align-items: baseline; font-weight: 700; color: var(--ink); }
.totals-due .mono { font-size: 19px; }
.strike { text-decoration: line-through; }
.no-lines { border-top: 0; }
</style>
