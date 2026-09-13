<script setup>
import { ref, reactive, computed, onMounted, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute, useRouter } from 'vue-router'
import api from '@xorder/api-client/api.js'
import { withMinDuration } from '../../../lib/minLoading.js'
import { pickLocalized } from '@xorder/ui/localize.js'
import { amountToMinor, minorToAmount, percentToBp, bpToPercent } from '../../../lib/money.js'
import { parseQuantity, formatMilli, costAt, orderTotals, taxWithinBp } from '../../../lib/quantity.js'
import ListSkeleton from '@xorder/ui/ListSkeleton.vue'
import ErrorState from '@xorder/ui/ErrorState.vue'
import FormError from '@xorder/ui/FormError.vue'
import Icon from '@xorder/ui/Icon.vue'
import { alert } from '@xorder/ui/alert.js'
import { money, todayLocal, addDays } from './format.js'

// CB-09 slice c. Enter or edit a supplier invoice, written whole.
//
// Two ways, as a bookkeeper works:
//   - the total off the paper, with the tax as an amount or as the rate
//     INSIDE the total (the till's taxWithinBp);
//   - itemised lines, whose total and tax the server computes (tax rounded
//     per rate, as on a purchase order).
// An optional sent purchase order of the same supplier and branch shows what
// was received beside the total, for comparison only: an invoice never
// changes the cost of stock.
//
// No float anywhere: amounts via lib/money.js (digit strings), quantities via
// lib/quantity.js, previews on BigInt. The server is authoritative.
const { t, locale } = useI18n()
const route = useRoute()
const router = useRouter()

const isEdit = computed(() => !!route.params.id)
const lookups = ref({ branches: [], suppliers: [], exponent: 2, currency: null })
const original = ref(null)
const orders = ref([])
const linked = ref(null)
const loading = ref(true)
const failed = ref(false)
const saving = ref(false)
const errors = ref({})
const dueTouched = ref(false)

let seq = 0
const blankLine = () => ({ key: ++seq, description: '', quantity: '1', unit_cost: '', tax_rate: '' })
const form = reactive({
    supplier_id: '', branch_id: '', purchase_order_id: '', number: '', issued_at: todayLocal(), due_at: '', note: '',
    mode: 'total', total: '', tax_mode: 'amount', tax: '', tax_rate: '', lines: [],
})

const exponent = computed(() => original.value?.exponent ?? lookups.value.exponent ?? 2)
const currency = computed(() => original.value?.currency ?? lookups.value.currency)
const show = (minor) => money(minor, exponent.value, currency.value, locale.value)
const nameOf = (s) => (s ? (pickLocalized(s, 'name', locale.value) || s.name_en || s.name_ar || `#${s.id}`) : '')
const supplierOf = (id) => lookups.value.suppliers.find((s) => s.id === Number(id))
const terms = computed(() => supplierOf(form.supplier_id)?.payment_term_days ?? 0)
const branchOptions = computed(() => lookups.value.branches.filter((b) => b.is_active || b.id === original.value?.branch_id))
const supplierOptions = computed(() => lookups.value.suppliers.filter((s) => s.is_active || s.id === original.value?.supplier_id || s.id === Number(route.query.supplier_id)))

// The due date follows the supplier's terms until somebody types one.
function defaultDue() {
    if (!dueTouched.value && form.issued_at) form.due_at = addDays(form.issued_at, terms.value)
}
watch(() => [form.supplier_id, form.issued_at], defaultDue)

async function loadLinked() {
    linked.value = null
    if (!form.purchase_order_id) return
    try {
        const { data } = await api.get(`api/dashboard/purchase-orders/${form.purchase_order_id}`)
        linked.value = data.data
    } catch {
        linked.value = null
    }
}
watch(() => form.purchase_order_id, loadLinked)

// Sent orders of this supplier at this branch (a draft was never sent, so it
// can't be billed; the server refuses it too).
async function loadOrders() {
    orders.value = []
    if (!form.supplier_id || !form.branch_id) return
    try {
        const { data } = await api.get('api/dashboard/purchase-orders', { params: { supplier_id: form.supplier_id, branch_id: form.branch_id } })
        orders.value = data.data.filter((o) => o.status !== 'draft')
    } catch {
        orders.value = []
    }
    const l = linked.value
    if (l && l.supplier_id === Number(form.supplier_id) && l.branch_id === Number(form.branch_id) && !orders.value.some((o) => o.id === l.id)) {
        orders.value.unshift(l)
    }
    if (form.purchase_order_id && !orders.value.some((o) => o.id === Number(form.purchase_order_id))) form.purchase_order_id = ''
}
watch(() => [form.supplier_id, form.branch_id], loadOrders)

async function load() {
    loading.value = true
    failed.value = false
    try {
        const [lk, inv] = await withMinDuration(Promise.all([
            api.get('api/dashboard/purchasing/lookups'),
            isEdit.value ? api.get(`api/dashboard/supplier-invoices/${route.params.id}`) : Promise.resolve(null),
        ]))
        lookups.value = lk.data.data
        if (inv) {
            const i = inv.data.data
            // Paid or voided: shown, never edited (the server refuses too).
            if (!i.can_edit) {
                router.replace({ name: 'dashboard.purchasing.invoice', params: { id: i.id } })
                return
            }
            original.value = i
            dueTouched.value = true
            if (i.purchase_order_id) { form.purchase_order_id = i.purchase_order_id; await loadLinked() }
            Object.assign(form, {
                supplier_id: i.supplier_id, branch_id: i.branch_id, number: i.number,
                issued_at: i.issued_at, due_at: i.due_at, note: i.note || '',
                mode: i.lines?.length ? 'lines' : 'total',
                total: minorToAmount(i.total_minor, i.exponent), tax_mode: 'amount', tax: minorToAmount(i.tax_minor, i.exponent),
                lines: (i.lines || []).map((l) => ({
                    key: ++seq, description: l.description, quantity: formatMilli(l.quantity_milli),
                    unit_cost: minorToAmount(l.unit_cost_minor, i.exponent), tax_rate: l.tax_rate_bp ? bpToPercent(l.tax_rate_bp) : '',
                })),
            })
        } else {
            const active = lookups.value.branches.filter((b) => b.is_active)
            if (active.length === 1) form.branch_id = active[0].id
            if (route.query.supplier_id) form.supplier_id = Number(route.query.supplier_id)
            if (route.query.branch_id) form.branch_id = Number(route.query.branch_id)
            if (route.query.purchase_order_id) {
                form.purchase_order_id = Number(route.query.purchase_order_id)
                await loadLinked()
                if (linked.value) { form.supplier_id = linked.value.supplier_id; form.branch_id = linked.value.branch_id }
            }
            defaultDue()
        }
        if (!form.lines.length) form.lines = [blankLine()]
    } catch {
        failed.value = true
    } finally {
        loading.value = false
    }
}
onMounted(load)

const valid = (n) => Number.isSafeInteger(n) && n >= 0
function parsedLine(l) {
    return {
        milli: parseQuantity(l.quantity),
        cost: amountToMinor(l.unit_cost, exponent.value),
        bp: l.tax_rate === '' || l.tax_rate == null ? 0 : percentToBp(l.tax_rate),
    }
}
function lineTotal(l) {
    const p = parsedLine(l)
    return valid(p.milli) && p.milli > 0 && valid(p.cost) ? costAt(p.milli, p.cost) : null
}
const typedTotal = computed(() => amountToMinor(form.total, exponent.value))
const typedRate = computed(() => (form.tax_rate === '' ? 0 : percentToBp(form.tax_rate)))
const typedTax = computed(() => (form.tax === '' ? 0 : amountToMinor(form.tax, exponent.value)))

// What the server will store, previewed with the same integer arithmetic.
const preview = computed(() => {
    if (form.mode === 'lines') {
        return orderTotals(form.lines.map((l) => {
            const p = parsedLine(l)
            return { quantity_milli: valid(p.milli) && p.milli > 0 ? p.milli : NaN, unit_cost_minor: valid(p.cost) ? p.cost : NaN, tax_rate_bp: valid(p.bp) ? p.bp : 0 }
        }))
    }
    const total = typedTotal.value
    if (!valid(total)) return null
    let tax = 0
    if (form.tax_mode === 'rate') tax = valid(typedRate.value) && typedRate.value <= 10000 ? taxWithinBp(total, typedRate.value) : 0
    else tax = valid(typedTax.value) ? typedTax.value : 0
    return { subtotal_minor: total - tax, tax_minor: tax, total_minor: total }
})
const variance = computed(() => (linked.value && preview.value ? preview.value.total_minor - (linked.value.received_total_minor ?? 0) : null))

function addLine() { form.lines.push(blankLine()) }
function removeLine(i) { form.lines.splice(i, 1) }

function validate() {
    const e = {}
    if (!form.supplier_id) e.supplier_id = [t('purchasing.pick_supplier')]
    if (!form.branch_id) e.branch_id = [t('purchasing.pick_branch')]
    if (!form.number.trim()) e.number = [t('purchasing.number_required')]
    if (!form.issued_at) e.issued_at = [t('purchasing.pick_date')]
    if (form.mode === 'lines') {
        if (!form.lines.length) e.lines = [t('purchasing.no_lines_yet')]
        form.lines.forEach((l, i) => {
            const p = parsedLine(l)
            if (!l.description.trim()) e[`lines.${i}.description`] = [t('purchasing.line_description_required')]
            if (!valid(p.milli) || p.milli <= 0) e[`lines.${i}.quantity_milli`] = [t('purchasing.quantity_invalid')]
            if (!valid(p.cost)) e[`lines.${i}.unit_cost_minor`] = [t('purchasing.amount_invalid')]
            if (!valid(p.bp) || p.bp > 10000) e[`lines.${i}.tax_rate_bp`] = [t('purchasing.rate_invalid')]
        })
    } else {
        if (!valid(typedTotal.value) || typedTotal.value <= 0) e.total_minor = [t('purchasing.amount_required')]
        if (form.tax_mode === 'rate' && (!valid(typedRate.value) || typedRate.value > 10000)) e.tax_rate_bp = [t('purchasing.rate_invalid')]
        if (form.tax_mode === 'amount' && !valid(typedTax.value)) e.tax_minor = [t('purchasing.amount_invalid')]
        else if (form.tax_mode === 'amount' && valid(typedTotal.value) && typedTax.value > typedTotal.value) e.tax_minor = [t('purchasing.tax_over_total')]
    }
    return e
}

function payload() {
    const base = {
        supplier_id: Number(form.supplier_id),
        branch_id: Number(form.branch_id),
        purchase_order_id: form.purchase_order_id ? Number(form.purchase_order_id) : null,
        number: form.number.trim(),
        issued_at: form.issued_at,
        due_at: form.due_at || null,
        note: form.note || null,
    }
    if (form.mode === 'lines') {
        return {
            ...base,
            lines: form.lines.map((l) => {
                const p = parsedLine(l)
                return { description: l.description.trim(), quantity_milli: p.milli, unit_cost_minor: p.cost, tax_rate_bp: p.bp }
            }),
        }
    }
    return form.tax_mode === 'rate'
        ? { ...base, total_minor: typedTotal.value, tax_rate_bp: typedRate.value }
        : { ...base, total_minor: typedTotal.value, tax_minor: typedTax.value }
}

async function save() {
    if (saving.value) return
    errors.value = validate()
    if (Object.keys(errors.value).length) return
    saving.value = true
    try {
        const { data } = isEdit.value
            ? await api.put(`api/dashboard/supplier-invoices/${route.params.id}`, payload())
            : await api.post('api/dashboard/supplier-invoices', payload())
        router.push({ name: 'dashboard.purchasing.invoice', params: { id: data.data.id } })
    } catch (err) {
        errors.value = err.response?.data?.errors || {}
        if (!Object.keys(errors.value).length) alert(err.response?.data?.message || t('common.error'))
    } finally {
        saving.value = false
    }
}

function back() {
    if (isEdit.value) router.push({ name: 'dashboard.purchasing.invoice', params: { id: route.params.id } })
    else router.push({ name: 'dashboard.purchasing.invoices' })
}
</script>

<template>
    <div class="space-y-5">
        <button type="button" class="flex items-center gap-1.5 text-sm" style="color:var(--muted)" @click="back">
            <Icon name="chevronDown" :size="16" class="rotate-90 rtl:-rotate-90" />{{ t('purchasing.invoices_title') }}
        </button>

        <div>
            <h1 class="page-title">{{ isEdit ? t('purchasing.edit_invoice') : t('purchasing.new_invoice') }}</h1>
            <p class="page-sub">{{ t('purchasing.variance_hint') }}</p>
        </div>

        <ErrorState v-if="failed" :message="t('common.error')" @retry="load" />
        <div v-else-if="loading" class="card"><ListSkeleton /></div>

        <form v-else class="space-y-5" @submit.prevent="save">
            <div class="card p-5 space-y-4">
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                    <label class="block"><span class="label">{{ t('purchasing.supplier') }}</span>
                        <select v-model="form.supplier_id" class="input">
                            <option value="" disabled>{{ t('purchasing.pick_supplier') }}</option>
                            <option v-for="s in supplierOptions" :key="s.id" :value="s.id">{{ nameOf(s) }}{{ s.is_active ? '' : ' ' + t('purchasing.retired_suffix') }}</option>
                        </select>
                        <FormError :errors="errors" field="supplier_id" /></label>
                    <label class="block"><span class="label">{{ t('purchasing.branch') }}</span>
                        <select v-model="form.branch_id" class="input">
                            <option value="" disabled>{{ t('purchasing.pick_branch') }}</option>
                            <option v-for="b in branchOptions" :key="b.id" :value="b.id">{{ nameOf(b) }}</option>
                        </select>
                        <FormError :errors="errors" field="branch_id" /></label>
                    <label class="block"><span class="label">{{ t('purchasing.invoice_number') }}</span>
                        <input v-model="form.number" class="input mono" dir="ltr" maxlength="64" autocomplete="off" />
                        <span class="text-xs" style="color:var(--muted)">{{ t('purchasing.invoice_number_hint') }}</span>
                        <FormError :errors="errors" field="number" /></label>
                    <label class="block"><span class="label">{{ t('purchasing.purchase_order') }}</span>
                        <select v-model="form.purchase_order_id" class="input" :disabled="!form.supplier_id || !form.branch_id">
                            <option value="">{{ t('purchasing.no_purchase_order') }}</option>
                            <option v-for="o in orders" :key="o.id" :value="o.id">{{ o.reference }} · {{ t('purchasing.status.' + o.status) }}</option>
                        </select>
                        <span class="text-xs" style="color:var(--muted)">{{ t('purchasing.purchase_order_hint') }}</span>
                        <FormError :errors="errors" field="purchase_order_id" /></label>
                    <label class="block"><span class="label">{{ t('purchasing.issued_at') }}</span>
                        <input v-model="form.issued_at" type="date" class="input" dir="ltr" />
                        <FormError :errors="errors" field="issued_at" /></label>
                    <label class="block"><span class="label">{{ t('purchasing.due_at') }}</span>
                        <input v-model="form.due_at" type="date" class="input" dir="ltr" @input="dueTouched = true" />
                        <span v-if="!dueTouched" class="text-xs" style="color:var(--muted)">{{ t('purchasing.due_hint', { n: terms }) }}</span>
                        <FormError :errors="errors" field="due_at" /></label>
                </div>
                <label class="block"><span class="label">{{ t('purchasing.notes') }}</span>
                    <textarea v-model="form.note" class="input" rows="2" maxlength="2000"></textarea>
                    <FormError :errors="errors" field="note" /></label>
            </div>

            <div class="card p-5 space-y-4">
                <fieldset class="flex flex-wrap items-center gap-4">
                    <legend class="label">{{ t('purchasing.entry_mode') }}</legend>
                    <label class="flex items-center gap-2 text-sm cursor-pointer" style="color:var(--body)"><input v-model="form.mode" type="radio" value="total" class="h-4 w-4" />{{ t('purchasing.mode_total') }}</label>
                    <label class="flex items-center gap-2 text-sm cursor-pointer" style="color:var(--body)"><input v-model="form.mode" type="radio" value="lines" class="h-4 w-4" />{{ t('purchasing.mode_lines') }}</label>
                </fieldset>

                <div v-if="form.mode === 'total'" class="grid grid-cols-1 sm:grid-cols-3 gap-3 items-start">
                    <label class="block"><span class="label">{{ t('purchasing.invoice_total') }}</span>
                        <input v-model="form.total" class="input mono" dir="ltr" inputmode="decimal" data-en-digits autocomplete="off" />
                        <FormError :errors="errors" field="total_minor" /></label>
                    <fieldset class="block">
                        <legend class="label">{{ t('purchasing.tax_mode') }}</legend>
                        <div class="flex flex-wrap gap-3 py-2">
                            <label class="flex items-center gap-2 text-sm cursor-pointer" style="color:var(--body)"><input v-model="form.tax_mode" type="radio" value="amount" class="h-4 w-4" />{{ t('purchasing.tax_as_amount') }}</label>
                            <label class="flex items-center gap-2 text-sm cursor-pointer" style="color:var(--body)"><input v-model="form.tax_mode" type="radio" value="rate" class="h-4 w-4" />{{ t('purchasing.tax_as_rate') }}</label>
                        </div>
                    </fieldset>
                    <label v-if="form.tax_mode === 'amount'" class="block"><span class="label">{{ t('purchasing.tax_amount') }}</span>
                        <input v-model="form.tax" class="input mono" dir="ltr" inputmode="decimal" data-en-digits placeholder="0" autocomplete="off" />
                        <FormError :errors="errors" field="tax_minor" /></label>
                    <label v-else class="block"><span class="label">{{ t('purchasing.tax_included_rate') }}</span>
                        <input v-model="form.tax_rate" class="input mono" dir="ltr" inputmode="decimal" data-en-digits placeholder="14" autocomplete="off" />
                        <span v-if="preview" class="text-xs" style="color:var(--muted)">{{ t('purchasing.tax_worked_out', { amount: show(preview.tax_minor) }) }}</span>
                        <FormError :errors="errors" field="tax_rate_bp" /></label>
                </div>

                <div v-else class="space-y-3">
                    <p class="text-sm" style="color:var(--muted)">{{ t('purchasing.lines_optional_hint') }}</p>
                    <FormError :errors="errors" field="lines" />
                    <div v-for="(l, i) in form.lines" :key="l.key" class="rounded-lg border p-3 grid grid-cols-2 sm:grid-cols-[2fr_1fr_1fr_1fr_auto] gap-3 items-start" style="border-color:var(--line)">
                        <label class="block col-span-2 sm:col-span-1"><span class="label">{{ t('purchasing.line_description') }}</span>
                            <input v-model="l.description" class="input" maxlength="200" />
                            <FormError :errors="errors" :field="`lines.${i}.description`" /></label>
                        <label class="block"><span class="label">{{ t('purchasing.quantity') }}</span>
                            <input v-model="l.quantity" class="input mono" dir="ltr" inputmode="decimal" data-en-digits autocomplete="off" />
                            <FormError :errors="errors" :field="`lines.${i}.quantity_milli`" /></label>
                        <label class="block"><span class="label">{{ t('purchasing.unit_cost') }}</span>
                            <input v-model="l.unit_cost" class="input mono" dir="ltr" inputmode="decimal" data-en-digits autocomplete="off" />
                            <FormError :errors="errors" :field="`lines.${i}.unit_cost_minor`" /></label>
                        <label class="block"><span class="label">{{ t('purchasing.tax_rate') }}</span>
                            <input v-model="l.tax_rate" class="input mono" dir="ltr" inputmode="decimal" data-en-digits placeholder="0" autocomplete="off" />
                            <FormError :errors="errors" :field="`lines.${i}.tax_rate_bp`" /></label>
                        <div class="block">
                            <span class="label">{{ t('purchasing.line_total') }}</span>
                            <div class="flex items-center justify-between gap-2 py-2">
                                <span class="mono" dir="ltr" style="color:var(--ink)">{{ lineTotal(l) == null ? '—' : show(lineTotal(l)) }}</span>
                                <button type="button" class="icon-btn" :title="t('purchasing.remove_line')" :aria-label="t('purchasing.remove_line')" @click="removeLine(i)"><Icon name="close" :size="16" /></button>
                            </div>
                        </div>
                    </div>
                    <button type="button" class="btn btn-ghost btn-sm" @click="addLine"><Icon name="plus" :size="15" />{{ t('purchasing.add_line') }}</button>
                </div>

                <div class="border-t pt-3 space-y-1 text-sm" style="border-color:var(--line)">
                    <div class="flex justify-between gap-3"><span style="color:var(--muted)">{{ t('purchasing.subtotal_derived') }}</span><span class="mono" dir="ltr">{{ preview ? show(preview.subtotal_minor) : '—' }}</span></div>
                    <div class="flex justify-between gap-3"><span style="color:var(--muted)">{{ t('purchasing.tax') }}</span><span class="mono" dir="ltr">{{ preview ? show(preview.tax_minor) : '—' }}</span></div>
                    <div class="flex justify-between gap-3 font-semibold" style="color:var(--ink)"><span>{{ t('purchasing.total') }}</span><span class="mono" dir="ltr">{{ preview ? show(preview.total_minor) : '—' }}</span></div>
                    <p class="text-xs pt-1" style="color:var(--muted)">{{ t('purchasing.preview_note') }}</p>
                </div>

                <div v-if="linked" class="rounded-lg p-3 text-sm space-y-1" style="background:var(--page)">
                    <div class="font-medium" style="color:var(--ink)">{{ t('purchasing.against_order') }} <span class="mono" dir="ltr">{{ linked.reference }}</span></div>
                    <div class="flex justify-between gap-3"><span style="color:var(--muted)">{{ t('purchasing.received_total') }}</span><span class="mono" dir="ltr">{{ show(linked.received_total_minor) }}</span></div>
                    <div v-if="variance !== null" class="flex justify-between gap-3"><span style="color:var(--muted)">{{ t('purchasing.variance') }}</span>
                        <span class="mono" dir="ltr" :style="variance === 0 ? 'color:var(--green)' : 'color:var(--amber)'">{{ show(variance) }}</span></div>
                    <p class="text-xs" style="color:var(--muted)">{{ t('purchasing.variance_hint') }}</p>
                </div>
            </div>

            <div class="flex justify-end gap-2">
                <button type="button" class="btn btn-ghost" :disabled="saving" @click="back">{{ t('common.cancel') }}</button>
                <button type="submit" class="btn btn-accent" :disabled="saving">
                    <Icon v-if="saving" name="loading" :size="16" class="animate-spin" />
                    {{ saving ? t('common.saving') : t('common.save') }}
                </button>
            </div>
        </form>
    </div>
</template>
