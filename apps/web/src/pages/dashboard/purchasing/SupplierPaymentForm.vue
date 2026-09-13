<script setup>
import { ref, reactive, computed, onMounted, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute, useRouter } from 'vue-router'
import api from '@xorder/api-client/api.js'
import { withMinDuration } from '../../../lib/minLoading.js'
import { pickLocalized } from '@xorder/ui/localize.js'
import { amountToMinor, minorToAmount } from '../../../lib/money.js'
import ListSkeleton from '@xorder/ui/ListSkeleton.vue'
import ErrorState from '@xorder/ui/ErrorState.vue'
import FormError from '@xorder/ui/FormError.vue'
import Icon from '@xorder/ui/Icon.vue'
import { alert } from '@xorder/ui/alert.js'
import { money, fmtDay, fmtDate, todayLocal, PAYMENT_METHODS } from './format.js'

// CB-09 slice c. Record a payment to a supplier and point it at the invoices
// it settles. Whatever is not allocated stays ON ACCOUNT: it reduces what is
// owed without clearing any particular bill (the till's rule).
//
// Each allocation is capped at what is still owed on that invoice. The page
// checks it for comfort; the server checks it for real, under a lock on the
// invoice row, so two people paying the same bill at once can never overpay
// it. A refusal names the room actually left, and the open invoices reload.
//
// A payment is never edited. A wrong one is voided and entered again.
const { t, locale } = useI18n()
const route = useRoute()
const router = useRouter()

const lookups = ref({ branches: [], suppliers: [], exponent: 2, currency: null })
const loading = ref(true)
const failed = ref(false)
const saving = ref(false)
const errors = ref({})
const rowErrors = ref({})

const form = reactive({
    supplier_id: '', branch_id: '', method: 'bank_transfer', amount: '', paid_at: todayLocal(),
    reference: '', note: '', pos_cash_movement_id: '',
})
const open = ref([])
const openLoading = ref(false)
const payouts = ref([])
let presetInvoice = route.query.invoice_id ? Number(route.query.invoice_id) : null

const exponent = computed(() => lookups.value.exponent ?? 2)
const show = (minor) => money(minor, exponent.value, lookups.value.currency, locale.value)
const nameOf = (s) => (s ? (pickLocalized(s, 'name', locale.value) || s.name_en || s.name_ar || `#${s.id}`) : '')
const branchOptions = computed(() => lookups.value.branches.filter((b) => b.is_active))
const supplierOptions = computed(() => lookups.value.suppliers.filter((s) => s.is_active || s.id === Number(form.supplier_id)))
const valid = (n) => Number.isSafeInteger(n) && n >= 0

async function load() {
    loading.value = true
    failed.value = false
    try {
        const { data } = await withMinDuration(api.get('api/dashboard/purchasing/lookups'))
        lookups.value = data.data
        const active = branchOptions.value
        if (active.length === 1) form.branch_id = active[0].id
        if (route.query.supplier_id) form.supplier_id = Number(route.query.supplier_id)
        if (route.query.branch_id) form.branch_id = Number(route.query.branch_id)
    } catch {
        failed.value = true
    } finally {
        loading.value = false
    }
}
onMounted(load)

// The supplier's open invoices at this branch, oldest due first. Amounts
// typed so far are kept across a reload (after a refusal).
async function loadOpen() {
    const kept = Object.fromEntries(open.value.map((r) => [r.id, r.alloc]))
    open.value = []
    if (!form.supplier_id || !form.branch_id) return
    openLoading.value = true
    try {
        const { data } = await api.get('api/dashboard/supplier-invoices', {
            params: { supplier_id: form.supplier_id, branch_id: form.branch_id, state: 'open', per_page: 100 },
        })
        open.value = data.data
            .slice()
            .sort((a, b) => a.due_at.localeCompare(b.due_at) || a.id - b.id)
            .map((i) => ({ ...i, alloc: kept[i.id] ?? '' }))
        if (presetInvoice) {
            const row = open.value.find((r) => r.id === presetInvoice)
            if (row) {
                row.alloc = minorToAmount(row.outstanding_minor, row.exponent)
                if (form.amount === '') form.amount = row.alloc
            }
            presetInvoice = null
        }
    } catch {
        open.value = []
    } finally {
        openLoading.value = false
    }
}
watch(() => [form.supplier_id, form.branch_id], loadOpen)

const amountMinor = computed(() => amountToMinor(form.amount, exponent.value))
const allocOf = (row) => (row.alloc === '' || row.alloc == null ? 0 : amountToMinor(row.alloc, exponent.value))
const allocated = computed(() => open.value.reduce((sum, r) => { const m = allocOf(r); return sum + (valid(m) ? m : 0) }, 0))
const onAccount = computed(() => (valid(amountMinor.value) ? amountMinor.value - allocated.value : null))

// Oldest due first, never more than is owed on each, never more than the payment.
function fillOldest() {
    if (!valid(amountMinor.value)) return
    let left = amountMinor.value
    for (const row of open.value) {
        const take = Math.min(left, row.outstanding_minor)
        row.alloc = take > 0 ? minorToAmount(take, exponent.value) : ''
        left -= Math.max(take, 0)
    }
}
function clearAllocations() { for (const row of open.value) row.alloc = '' }

// Design D13: cash that left a till drawer may name the synced pay-out. Only
// unlinked pay-outs of exactly this amount at this branch are offered.
let payoutTimer = null
async function loadPayouts() {
    payouts.value = []
    if (form.method !== 'cash' || !form.branch_id || !valid(amountMinor.value) || amountMinor.value <= 0) {
        form.pos_cash_movement_id = ''
        return
    }
    try {
        const { data } = await api.get('api/dashboard/purchasing/drawer-payouts', { params: { branch_id: form.branch_id, amount_minor: amountMinor.value } })
        payouts.value = data.data
    } catch {
        payouts.value = []
    }
    if (form.pos_cash_movement_id && !payouts.value.some((p) => p.id === Number(form.pos_cash_movement_id))) form.pos_cash_movement_id = ''
}
watch(() => [form.method, form.branch_id, amountMinor.value], () => {
    clearTimeout(payoutTimer)
    payoutTimer = setTimeout(loadPayouts, 300)
})

function validate() {
    const e = {}
    const rows = {}
    if (!form.supplier_id) e.supplier_id = [t('purchasing.pick_supplier')]
    if (!form.branch_id) e.branch_id = [t('purchasing.pick_branch')]
    if (!valid(amountMinor.value) || amountMinor.value <= 0) e.amount_minor = [t('purchasing.amount_required')]
    if (!form.paid_at) e.paid_at = [t('purchasing.pick_date')]
    for (const r of open.value) {
        const m = allocOf(r)
        if (!valid(m)) rows[r.id] = [t('purchasing.amount_invalid')]
        else if (m > r.outstanding_minor) rows[r.id] = [t('purchasing.allocation_over_room', { amount: show(r.outstanding_minor) })]
    }
    if (valid(amountMinor.value) && allocated.value > amountMinor.value) e.allocations = [t('purchasing.allocations_over_amount')]
    rowErrors.value = rows
    return Object.keys(rows).length ? { ...e, _rows: true } : e
}

async function save() {
    if (saving.value) return
    errors.value = validate()
    if (Object.keys(errors.value).length) return
    const sent = open.value.filter((r) => allocOf(r) > 0)
    saving.value = true
    try {
        const { data } = await api.post('api/dashboard/supplier-payments', {
            supplier_id: Number(form.supplier_id),
            branch_id: Number(form.branch_id),
            method: form.method,
            amount_minor: amountMinor.value,
            paid_at: form.paid_at,
            reference: form.reference.trim() || null,
            note: form.note || null,
            pos_cash_movement_id: form.pos_cash_movement_id ? Number(form.pos_cash_movement_id) : null,
            allocations: sent.map((r) => ({ supplier_invoice_id: r.id, amount_minor: allocOf(r) })),
        })
        router.push({ name: 'dashboard.purchasing.payment', params: { id: data.data.id } })
    } catch (err) {
        const raw = err.response?.data?.errors || {}
        // allocations.N.* → the row it was about.
        const rows = {}
        const rest = {}
        for (const [key, msgs] of Object.entries(raw)) {
            const m = /^allocations\.(\d+)\./.exec(key)
            if (m && sent[Number(m[1])]) rows[sent[Number(m[1])].id] = msgs
            else rest[key] = msgs
        }
        rowErrors.value = rows
        errors.value = rest
        if (!Object.keys(raw).length) alert(err.response?.data?.message || t('common.error'))
        // Somebody paid one of these since the page loaded: show the real room.
        if (err.response?.status === 409) loadOpen()
    } finally {
        saving.value = false
    }
}
</script>

<template>
    <div class="space-y-5">
        <button type="button" class="flex items-center gap-1.5 text-sm" style="color:var(--muted)" @click="router.push({ name: 'dashboard.purchasing.payments' })">
            <Icon name="chevronDown" :size="16" class="rotate-90 rtl:-rotate-90" />{{ t('purchasing.payments_title') }}
        </button>

        <div>
            <h1 class="page-title">{{ t('purchasing.new_payment') }}</h1>
            <p class="page-sub">{{ t('purchasing.allocate_hint') }}</p>
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
                    <label class="block"><span class="label">{{ t('purchasing.amount') }}</span>
                        <input v-model="form.amount" class="input mono" dir="ltr" inputmode="decimal" data-en-digits autocomplete="off" />
                        <FormError :errors="errors" field="amount_minor" /></label>
                    <label class="block"><span class="label">{{ t('purchasing.paid_at') }}</span>
                        <input v-model="form.paid_at" type="date" class="input" dir="ltr" />
                        <FormError :errors="errors" field="paid_at" /></label>
                    <label class="block"><span class="label">{{ t('purchasing.method') }}</span>
                        <select v-model="form.method" class="input">
                            <option v-for="m in PAYMENT_METHODS" :key="m" :value="m">{{ t('purchasing.methods.' + m) }}</option>
                        </select>
                        <FormError :errors="errors" field="method" /></label>
                    <label class="block"><span class="label">{{ t('purchasing.payment_reference') }}</span>
                        <input v-model="form.reference" class="input mono" dir="ltr" maxlength="120" autocomplete="off" />
                        <span class="text-xs" style="color:var(--muted)">{{ t('purchasing.payment_reference_hint') }}</span>
                        <FormError :errors="errors" field="reference" /></label>
                </div>
                <label v-if="form.method === 'cash' && form.branch_id" class="block">
                    <span class="label">{{ t('purchasing.drawer') }}</span>
                    <select v-model="form.pos_cash_movement_id" class="input">
                        <option value="">{{ t('purchasing.drawer_none') }}</option>
                        <option v-for="p in payouts" :key="p.id" :value="p.id">{{ fmtDate(p.occurred_at, locale, { time: true }) }} · {{ show(p.amount_minor) }} · {{ p.reason }}</option>
                    </select>
                    <span class="text-xs" style="color:var(--muted)">{{ payouts.length ? t('purchasing.drawer_hint') : t('purchasing.drawer_none_found') }}</span>
                    <FormError :errors="errors" field="pos_cash_movement_id" />
                </label>
                <label class="block"><span class="label">{{ t('purchasing.notes') }}</span>
                    <textarea v-model="form.note" class="input" rows="2" maxlength="2000"></textarea>
                    <FormError :errors="errors" field="note" /></label>
            </div>

            <div class="card p-5 space-y-3">
                <div class="flex flex-wrap items-center justify-between gap-3">
                    <h2 class="font-semibold" style="color:var(--ink)">{{ t('purchasing.allocate') }}</h2>
                    <div v-if="open.length" class="flex gap-2">
                        <button type="button" class="btn btn-ghost btn-sm" :disabled="!valid(amountMinor)" @click="fillOldest">{{ t('purchasing.allocate_oldest') }}</button>
                        <button type="button" class="btn btn-ghost btn-sm" @click="clearAllocations">{{ t('purchasing.clear_allocations') }}</button>
                    </div>
                </div>
                <FormError :errors="errors" field="allocations" />

                <p v-if="!form.supplier_id || !form.branch_id" class="text-sm" style="color:var(--muted)">{{ t('purchasing.pick_supplier_branch_first') }}</p>
                <ListSkeleton v-else-if="openLoading" />
                <p v-else-if="!open.length" class="text-sm" style="color:var(--muted)">{{ t('purchasing.no_open_invoices') }}</p>
                <div v-else class="overflow-x-auto">
                    <table class="w-full text-sm">
                        <thead>
                            <tr style="color:var(--muted)">
                                <th class="px-3 py-2 text-start font-medium">{{ t('purchasing.invoice_number') }}</th>
                                <th class="px-3 py-2 text-start font-medium">{{ t('purchasing.due_at') }}</th>
                                <th class="px-3 py-2 text-end font-medium">{{ t('purchasing.total') }}</th>
                                <th class="px-3 py-2 text-end font-medium">{{ t('purchasing.outstanding') }}</th>
                                <th class="px-3 py-2 text-end font-medium">{{ t('purchasing.allocated') }}</th>
                            </tr>
                        </thead>
                        <tbody>
                            <tr v-for="r in open" :key="r.id" class="border-t align-top" style="border-color:var(--line)">
                                <td class="px-3 py-2"><span class="mono" dir="ltr" style="color:var(--ink)">{{ r.number }}</span></td>
                                <td class="px-3 py-2 whitespace-nowrap" style="color:var(--body)">
                                    {{ fmtDay(r.due_at, locale) }}
                                    <div v-if="r.days_late" class="text-xs" style="color:var(--red)">{{ t('purchasing.days_late', { n: r.days_late }) }}</div>
                                </td>
                                <td class="px-3 py-2 text-end"><span class="mono" dir="ltr">{{ show(r.total_minor) }}</span></td>
                                <td class="px-3 py-2 text-end"><span class="mono" dir="ltr">{{ show(r.outstanding_minor) }}</span></td>
                                <td class="px-3 py-2" style="min-width: 9rem">
                                    <input v-model="r.alloc" class="input mono text-end" dir="ltr" inputmode="decimal" data-en-digits placeholder="0" autocomplete="off" :aria-label="t('purchasing.allocated') + ' ' + r.number" />
                                    <FormError :errors="rowErrors" :field="String(r.id)" />
                                </td>
                            </tr>
                        </tbody>
                    </table>
                </div>

                <div class="border-t pt-3 space-y-1 text-sm" style="border-color:var(--line)">
                    <div class="flex justify-between gap-3"><span style="color:var(--muted)">{{ t('purchasing.amount') }}</span><span class="mono" dir="ltr">{{ valid(amountMinor) ? show(amountMinor) : '—' }}</span></div>
                    <div class="flex justify-between gap-3"><span style="color:var(--muted)">{{ t('purchasing.allocated') }}</span><span class="mono" dir="ltr">{{ show(allocated) }}</span></div>
                    <div class="flex justify-between gap-3 font-semibold" :style="onAccount !== null && onAccount < 0 ? 'color:var(--red)' : 'color:var(--ink)'">
                        <span>{{ t('purchasing.on_account') }}</span><span class="mono" dir="ltr">{{ onAccount === null ? '—' : show(onAccount) }}</span>
                    </div>
                    <p class="text-xs pt-1" style="color:var(--muted)">{{ t('purchasing.on_account_hint') }}</p>
                </div>
            </div>

            <div class="flex justify-end gap-2">
                <button type="button" class="btn btn-ghost" :disabled="saving" @click="router.push({ name: 'dashboard.purchasing.payments' })">{{ t('common.cancel') }}</button>
                <button type="submit" class="btn btn-accent" :disabled="saving">
                    <Icon v-if="saving" name="loading" :size="16" class="animate-spin" />
                    {{ saving ? t('common.saving') : t('purchasing.new_payment') }}
                </button>
            </div>
        </form>
    </div>
</template>
