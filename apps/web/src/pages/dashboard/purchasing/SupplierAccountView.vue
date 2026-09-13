<script setup>
import { ref, computed, onMounted, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute, useRouter } from 'vue-router'
import api from '@xorder/api-client/api.js'
import { useAuth } from '@xorder/api-client/auth.js'
import { withMinDuration } from '../../../lib/minLoading.js'
import { pickLocalized } from '@xorder/ui/localize.js'
import Skeleton from '@xorder/ui/Skeleton.vue'
import ErrorState from '@xorder/ui/ErrorState.vue'
import Icon from '@xorder/ui/Icon.vue'
import { fmtDay, money } from './format.js'

// CB-09 slice c. A supplier's account: what is owed, what is late, what is on
// account, the statement with its running balance, the open invoices and the
// payments. All of it is DERIVED by the server from the live invoices and
// payments every time it is read; no balance is stored anywhere, so there is
// nothing to fall out of step. The statement's closing balance is the balance
// owed, by construction (the server's tests assert it).
//
// On-account money reduces the balance but not what is overdue: nobody said
// which bill it was for (the till's rule).
const { t, locale } = useI18n()
const route = useRoute()
const router = useRouter()
const auth = useAuth()
const canWrite = computed(() => auth.can('purchase.manage') && !auth.isReadOnly)

const account = ref(null)
const branches = ref([])
const branchId = ref('')
const tab = ref('statement')
const loading = ref(true)
const failed = ref(false)

async function load() {
    loading.value = true
    failed.value = false
    try {
        const params = branchId.value ? { branch_id: branchId.value } : {}
        const [acc, lk] = await withMinDuration(Promise.all([
            api.get(`api/dashboard/suppliers/${route.params.id}/account`, { params }),
            branches.value.length ? Promise.resolve(null) : api.get('api/dashboard/purchasing/lookups'),
        ]))
        account.value = acc.data.data
        if (lk) branches.value = lk.data.data.branches
    } catch {
        failed.value = true
    } finally {
        loading.value = false
    }
}
onMounted(load)
watch(branchId, load)

const nameOf = (s) => (s ? (pickLocalized(s, 'name', locale.value) || s.name_en || s.name_ar || `#${s.id}`) : '')
const branchName = (id) => nameOf(branches.value.find((b) => b.id === id))
const show = (minor) => money(minor, account.value?.exponent, account.value?.currency, locale.value)
const f = computed(() => account.value?.figures || {})
const inCredit = computed(() => (f.value.outstanding_minor ?? 0) < 0)
const query = computed(() => ({ supplier_id: route.params.id, ...(branchId.value ? { branch_id: branchId.value } : {}) }))

function openRow(row) {
    if (row.kind === 'invoice') router.push({ name: 'dashboard.purchasing.invoice', params: { id: row.id } })
    else router.push({ name: 'dashboard.purchasing.payment', params: { id: row.id } })
}
</script>

<template>
    <div class="space-y-5">
        <button type="button" class="flex items-center gap-1.5 text-sm" style="color:var(--muted)" @click="router.push({ name: 'dashboard.purchasing.suppliers' })">
            <Icon name="chevronDown" :size="16" class="rotate-90 rtl:-rotate-90" />{{ t('purchasing.suppliers_title') }}
        </button>

        <ErrorState v-if="failed" :message="t('common.error')" @retry="load" />

        <div v-else-if="!account" class="card p-5 space-y-3">
            <Skeleton w="40%" h="22px" /><Skeleton w="60%" h="14px" /><Skeleton w="100%" h="160px" />
        </div>

        <template v-else>
            <div class="flex flex-wrap items-start justify-between gap-3">
                <div class="space-y-1">
                    <h1 class="page-title flex flex-wrap items-center gap-2">
                        {{ nameOf(account.supplier) }}
                        <span v-if="!account.supplier.is_active" class="badge badge-gray">{{ t('purchasing.retired') }}</span>
                    </h1>
                    <p class="page-sub">{{ t('purchasing.account_sub') }}</p>
                </div>
                <div v-if="canWrite" class="flex flex-wrap gap-2">
                    <RouterLink :to="{ name: 'dashboard.purchasing.invoices.create', query }" class="btn btn-ghost"><Icon name="plus" :size="16" />{{ t('purchasing.new_invoice') }}</RouterLink>
                    <RouterLink :to="{ name: 'dashboard.purchasing.payments.create', query }" class="btn btn-accent">{{ t('purchasing.record_payment') }}</RouterLink>
                </div>
            </div>

            <div class="flex flex-wrap items-center gap-3">
                <select v-if="branches.length > 1" v-model="branchId" class="input" style="max-width: 220px" :aria-label="t('purchasing.branch')">
                    <option value="">{{ t('purchasing.all_branches') }}</option>
                    <option v-for="b in branches" :key="b.id" :value="b.id">{{ nameOf(b) }}</option>
                </select>
                <span class="text-xs" style="color:var(--muted)">{{ t('purchasing.as_of', { date: fmtDay(account.as_of, locale) }) }}</span>
            </div>

            <div class="grid grid-cols-2 lg:grid-cols-5 gap-3" :style="loading ? 'opacity:.6' : ''">
                <div class="card p-4">
                    <div class="text-xs" style="color:var(--muted)">{{ inCredit ? t('purchasing.in_credit') : t('purchasing.outstanding_balance') }}</div>
                    <div class="mono text-lg font-semibold" dir="ltr" :style="inCredit ? 'color:var(--green)' : 'color:var(--ink)'">{{ show(Math.abs(f.outstanding_minor || 0)) }}</div>
                </div>
                <div class="card p-4">
                    <div class="text-xs" style="color:var(--muted)">{{ t('purchasing.overdue') }}</div>
                    <div class="mono text-lg font-semibold" dir="ltr" :style="f.overdue_minor ? 'color:var(--red)' : 'color:var(--ink)'">{{ show(f.overdue_minor) }}</div>
                </div>
                <div class="card p-4">
                    <div class="text-xs" style="color:var(--muted)">{{ t('purchasing.on_account') }}</div>
                    <div class="mono text-lg font-semibold" dir="ltr" style="color:var(--ink)">{{ show(f.on_account_minor) }}</div>
                </div>
                <div class="card p-4">
                    <div class="text-xs" style="color:var(--muted)">{{ t('purchasing.invoiced') }}</div>
                    <div class="mono text-lg" dir="ltr" style="color:var(--ink)">{{ show(f.invoiced_minor) }}</div>
                </div>
                <div class="card p-4">
                    <div class="text-xs" style="color:var(--muted)">{{ t('purchasing.paid_total') }}</div>
                    <div class="mono text-lg" dir="ltr" style="color:var(--ink)">{{ show(f.paid_minor) }}</div>
                </div>
            </div>

            <div class="flex flex-wrap gap-2" role="tablist">
                <button v-for="k in ['statement', 'open', 'payments']" :key="k" type="button" role="tab" class="btn btn-sm" :class="tab === k ? 'btn-accent' : 'btn-ghost'" :aria-selected="tab === k" @click="tab = k">
                    {{ k === 'statement' ? t('purchasing.statement') : k === 'open' ? t('purchasing.open_invoices') : t('purchasing.all_payments_list') }}
                    <span v-if="k === 'open'" class="mono" dir="ltr">({{ account.open_invoices.length }})</span>
                </button>
            </div>

            <div v-if="tab === 'statement'" class="card overflow-hidden">
                <div v-if="!account.statement.length" class="p-8 text-center text-sm" style="color:var(--muted)">{{ t('purchasing.none_statement') }}</div>
                <div v-else class="overflow-x-auto">
                    <table class="w-full text-sm">
                        <thead>
                            <tr style="color:var(--muted)">
                                <th class="px-4 py-3 text-start font-medium">{{ t('purchasing.date') }}</th>
                                <th class="px-4 py-3 text-start font-medium">{{ t('purchasing.document') }}</th>
                                <th v-if="branches.length > 1 && !branchId" class="px-4 py-3 text-start font-medium">{{ t('purchasing.branch') }}</th>
                                <th class="px-4 py-3 text-end font-medium">{{ t('purchasing.debit') }}</th>
                                <th class="px-4 py-3 text-end font-medium">{{ t('purchasing.credit') }}</th>
                                <th class="px-4 py-3 text-end font-medium">{{ t('purchasing.running_balance') }}</th>
                            </tr>
                        </thead>
                        <tbody>
                            <tr v-for="row in account.statement" :key="row.kind + row.id" class="border-t cursor-pointer hover:bg-black/[.02]" style="border-color:var(--line)" @click="openRow(row)">
                                <td class="px-4 py-3 whitespace-nowrap" style="color:var(--body)">{{ fmtDay(row.date, locale) }}</td>
                                <td class="px-4 py-3" style="color:var(--ink)">
                                    <template v-if="row.kind === 'invoice'">{{ t('purchasing.invoice') }} <span class="mono" dir="ltr">{{ row.number }}</span></template>
                                    <template v-else>{{ t('purchasing.methods.' + row.method) }}<span v-if="row.reference"> · <span class="mono" dir="ltr">{{ row.reference }}</span></span></template>
                                </td>
                                <td v-if="branches.length > 1 && !branchId" class="px-4 py-3" style="color:var(--body)">{{ branchName(row.branch_id) }}</td>
                                <td class="px-4 py-3 text-end"><span class="mono" dir="ltr">{{ row.debit_minor ? show(row.debit_minor) : '' }}</span></td>
                                <td class="px-4 py-3 text-end"><span class="mono" dir="ltr">{{ row.credit_minor ? show(row.credit_minor) : '' }}</span></td>
                                <td class="px-4 py-3 text-end"><span class="mono font-medium" dir="ltr">{{ show(row.balance_minor) }}</span></td>
                            </tr>
                        </tbody>
                    </table>
                </div>
                <p v-if="account.statement.length" class="px-4 py-3 border-t text-xs" style="border-color:var(--line);color:var(--muted)">{{ t('purchasing.statement_reconciles') }}</p>
            </div>

            <div v-else-if="tab === 'open'" class="card overflow-hidden">
                <div v-if="!account.open_invoices.length" class="p-8 text-center text-sm" style="color:var(--muted)">{{ t('purchasing.none_open_invoices') }}</div>
                <div v-else class="overflow-x-auto">
                    <table class="w-full text-sm">
                        <thead>
                            <tr style="color:var(--muted)">
                                <th class="px-4 py-3 text-start font-medium">{{ t('purchasing.invoice_number') }}</th>
                                <th class="px-4 py-3 text-start font-medium">{{ t('purchasing.due_at') }}</th>
                                <th class="px-4 py-3 text-end font-medium">{{ t('purchasing.total') }}</th>
                                <th class="px-4 py-3 text-end font-medium">{{ t('purchasing.paid') }}</th>
                                <th class="px-4 py-3 text-end font-medium">{{ t('purchasing.outstanding') }}</th>
                            </tr>
                        </thead>
                        <tbody>
                            <tr v-for="i in account.open_invoices" :key="i.id" class="border-t cursor-pointer hover:bg-black/[.02]" style="border-color:var(--line)" @click="router.push({ name: 'dashboard.purchasing.invoice', params: { id: i.id } })">
                                <td class="px-4 py-3"><span class="mono" dir="ltr" style="color:var(--ink)">{{ i.number }}</span></td>
                                <td class="px-4 py-3 whitespace-nowrap" style="color:var(--body)">
                                    {{ fmtDay(i.due_at, locale) }}
                                    <div v-if="i.days_late" class="text-xs" style="color:var(--red)">{{ t('purchasing.days_late', { n: i.days_late }) }}</div>
                                </td>
                                <td class="px-4 py-3 text-end"><span class="mono" dir="ltr">{{ show(i.total_minor) }}</span></td>
                                <td class="px-4 py-3 text-end"><span class="mono" dir="ltr">{{ show(i.paid_minor) }}</span></td>
                                <td class="px-4 py-3 text-end"><span class="mono font-medium" dir="ltr">{{ show(i.outstanding_minor) }}</span></td>
                            </tr>
                        </tbody>
                    </table>
                </div>
            </div>

            <div v-else class="card overflow-hidden">
                <div v-if="!account.payments.length" class="p-8 text-center text-sm" style="color:var(--muted)">{{ t('purchasing.none_payments') }}</div>
                <div v-else class="overflow-x-auto">
                    <table class="w-full text-sm">
                        <thead>
                            <tr style="color:var(--muted)">
                                <th class="px-4 py-3 text-start font-medium">{{ t('purchasing.paid_at') }}</th>
                                <th class="px-4 py-3 text-start font-medium">{{ t('purchasing.method') }}</th>
                                <th class="px-4 py-3 text-end font-medium">{{ t('purchasing.amount') }}</th>
                                <th class="px-4 py-3 text-end font-medium">{{ t('purchasing.allocated') }}</th>
                                <th class="px-4 py-3 text-end font-medium">{{ t('purchasing.on_account') }}</th>
                            </tr>
                        </thead>
                        <tbody>
                            <tr v-for="p in account.payments" :key="p.id" class="border-t cursor-pointer hover:bg-black/[.02]" style="border-color:var(--line)" :style="p.is_voided ? 'opacity:.6' : ''" @click="router.push({ name: 'dashboard.purchasing.payment', params: { id: p.id } })">
                                <td class="px-4 py-3 whitespace-nowrap" style="color:var(--body)">{{ fmtDay(p.paid_at, locale) }}</td>
                                <td class="px-4 py-3" style="color:var(--ink)">
                                    {{ t('purchasing.methods.' + p.method) }}<span v-if="p.reference"> · <span class="mono" dir="ltr">{{ p.reference }}</span></span>
                                    <span v-if="p.is_voided" class="badge badge-gray ms-1">{{ t('purchasing.voided') }}</span>
                                </td>
                                <td class="px-4 py-3 text-end"><span class="mono" dir="ltr" :style="p.is_voided ? 'text-decoration:line-through' : ''">{{ show(p.amount_minor) }}</span></td>
                                <td class="px-4 py-3 text-end"><span class="mono" dir="ltr">{{ show(p.allocated_minor) }}</span></td>
                                <td class="px-4 py-3 text-end"><span class="mono" dir="ltr">{{ p.is_voided ? '—' : show(p.on_account_minor) }}</span></td>
                            </tr>
                        </tbody>
                    </table>
                </div>
            </div>
        </template>
    </div>
</template>
