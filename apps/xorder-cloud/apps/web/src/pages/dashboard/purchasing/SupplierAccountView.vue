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
        <button type="button" class="back" @click="router.push({ name: 'dashboard.purchasing.suppliers' })">
            <Icon name="chevronDown" :size="16" class="rotate-90 rtl:-rotate-90" />{{ t('purchasing.suppliers_title') }}
        </button>

        <ErrorState v-if="failed" :message="t('common.error')" @retry="load" />

        <div v-else-if="!account" class="space-y-5">
            <div class="card p-5 space-y-3"><Skeleton w="40%" h="28px" /><Skeleton w="60%" h="14px" /></div>
            <div class="grid grid-cols-2 lg:grid-cols-4 gap-3">
                <Skeleton v-for="n in 4" :key="n" w="100%" h="92px" rounded="15px" />
            </div>
            <Skeleton w="100%" h="220px" rounded="15px" />
        </div>

        <template v-else>
            <div class="flex flex-wrap items-start justify-between gap-4">
                <div class="min-w-0">
                    <h1 class="page-title flex flex-wrap items-center gap-2">
                        {{ nameOf(account.supplier) }}
                        <span v-if="!account.supplier.is_active" class="badge badge-gray">{{ t('purchasing.retired') }}</span>
                    </h1>
                    <p class="page-sub" style="color:var(--body)">{{ t('purchasing.account_sub') }}</p>
                </div>
                <div v-if="canWrite" class="actions">
                    <RouterLink :to="{ name: 'dashboard.purchasing.invoices.create', query }" class="btn btn-ghost"><Icon name="plus" :size="16" />{{ t('purchasing.new_invoice') }}</RouterLink>
                    <RouterLink :to="{ name: 'dashboard.purchasing.payments.create', query }" class="btn btn-accent">{{ t('purchasing.record_payment') }}</RouterLink>
                </div>
            </div>

            <div class="filters">
                <select v-if="branches.length > 1" v-model="branchId" class="input" style="max-width: 220px" :aria-label="t('purchasing.branch')">
                    <option value="">{{ t('purchasing.all_branches') }}</option>
                    <option v-for="b in branches" :key="b.id" :value="b.id">{{ nameOf(b) }}</option>
                </select>
                <span class="text-sm" style="color:var(--body)">{{ t('purchasing.as_of', { date: fmtDay(account.as_of, locale) }) }}</span>
            </div>

            <!-- What is owed first, then what is late; the rest is supporting context -->
            <section class="grid grid-cols-2 lg:grid-cols-4 gap-3" :style="loading ? 'opacity:.6' : ''">
                <div class="stat acct-hero">
                    <div class="stat-label" style="color:var(--body)">{{ inCredit ? t('purchasing.in_credit') : t('purchasing.outstanding_balance') }}</div>
                    <div class="stat-num mono" :class="inCredit ? 'tone-green' : ''"><span>{{ show(Math.abs(f.outstanding_minor || 0)) }}</span></div>
                </div>
                <div class="stat" :class="f.overdue_minor ? 'acct-late' : ''">
                    <div class="stat-label" style="color:var(--body)">{{ t('purchasing.overdue') }}</div>
                    <div class="stat-num mono" :class="f.overdue_minor ? 'tone-red' : ''"><span>{{ show(f.overdue_minor) }}</span></div>
                </div>
                <div class="stat">
                    <div class="stat-label" style="color:var(--body)">{{ t('purchasing.on_account') }}</div>
                    <div class="stat-num mono"><span>{{ show(f.on_account_minor) }}</span></div>
                </div>
                <div class="stat acct-pair">
                    <div class="pair-row"><span>{{ t('purchasing.invoiced') }}</span><span class="mono"><span>{{ show(f.invoiced_minor) }}</span></span></div>
                    <div class="pair-row"><span>{{ t('purchasing.paid_total') }}</span><span class="mono"><span>{{ show(f.paid_minor) }}</span></span></div>
                </div>
            </section>

            <div class="segmented tabs" role="tablist">
                <button v-for="k in ['statement', 'open', 'payments']" :key="k" type="button" role="tab" :class="tab === k ? 'active' : ''" :aria-selected="tab === k" @click="tab = k">
                    {{ k === 'statement' ? t('purchasing.statement') : k === 'open' ? t('purchasing.open_invoices') : t('purchasing.all_payments_list') }}
                    <span v-if="k === 'open'" class="mono" dir="ltr">({{ account.open_invoices.length }})</span>
                </button>
            </div>

            <div v-if="tab === 'statement'" class="card overflow-hidden">
                <div v-if="!account.statement.length" class="empty">
                    <div class="empty-ico"><i class="pi pi-book" aria-hidden="true" /></div>
                    <p class="empty-text">{{ t('purchasing.none_statement') }}</p>
                </div>
                <div v-else class="dtable-wrap">
                    <table class="dtable">
                        <thead>
                            <tr>
                                <th>{{ t('purchasing.date') }}</th>
                                <th>{{ t('purchasing.document') }}</th>
                                <th v-if="branches.length > 1 && !branchId">{{ t('purchasing.branch') }}</th>
                                <th class="num">{{ t('purchasing.debit') }}</th>
                                <th class="num">{{ t('purchasing.credit') }}</th>
                                <th class="num">{{ t('purchasing.running_balance') }}</th>
                            </tr>
                        </thead>
                        <tbody>
                            <tr v-for="row in account.statement" :key="row.kind + row.id" class="row-link" tabindex="0" @click="openRow(row)" @keydown.enter.self="openRow(row)">
                                <td class="nowrap">{{ fmtDay(row.date, locale) }}</td>
                                <td class="primary">
                                    <template v-if="row.kind === 'invoice'">{{ t('purchasing.invoice') }} <span class="mono" dir="ltr">{{ row.number }}</span></template>
                                    <template v-else>{{ t('purchasing.methods.' + row.method) }}<span v-if="row.reference"> · <span class="mono" dir="ltr">{{ row.reference }}</span></span></template>
                                </td>
                                <td v-if="branches.length > 1 && !branchId">{{ branchName(row.branch_id) }}</td>
                                <td class="num"><span class="mono">{{ row.debit_minor ? show(row.debit_minor) : '' }}</span></td>
                                <td class="num"><span class="mono">{{ row.credit_minor ? show(row.credit_minor) : '' }}</span></td>
                                <td class="num strong"><span class="mono">{{ show(row.balance_minor) }}</span></td>
                            </tr>
                        </tbody>
                    </table>
                </div>
                <p v-if="account.statement.length" class="px-5 py-3 text-sm" style="border-top:1px solid var(--line);color:var(--body)">{{ t('purchasing.statement_reconciles') }}</p>
            </div>

            <div v-else-if="tab === 'open'" class="card overflow-hidden">
                <div v-if="!account.open_invoices.length" class="empty">
                    <div class="empty-ico"><i class="pi pi-check" aria-hidden="true" /></div>
                    <p class="empty-text">{{ t('purchasing.none_open_invoices') }}</p>
                </div>
                <div v-else class="dtable-wrap">
                    <table class="dtable">
                        <thead>
                            <tr>
                                <th>{{ t('purchasing.invoice_number') }}</th>
                                <th>{{ t('purchasing.due_at') }}</th>
                                <th class="num">{{ t('purchasing.total') }}</th>
                                <th class="num">{{ t('purchasing.paid') }}</th>
                                <th class="num">{{ t('purchasing.outstanding') }}</th>
                            </tr>
                        </thead>
                        <tbody>
                            <tr v-for="i in account.open_invoices" :key="i.id" class="row-link" tabindex="0" @click="router.push({ name: 'dashboard.purchasing.invoice', params: { id: i.id } })" @keydown.enter.self="router.push({ name: 'dashboard.purchasing.invoice', params: { id: i.id } })">
                                <td class="primary"><span class="mono" dir="ltr">{{ i.number }}</span></td>
                                <td class="nowrap">
                                    {{ fmtDay(i.due_at, locale) }}
                                    <span v-if="i.days_late" class="meta-late">{{ t('purchasing.days_late', { n: i.days_late }) }}</span>
                                </td>
                                <td class="num"><span class="mono">{{ show(i.total_minor) }}</span></td>
                                <td class="num"><span class="mono">{{ show(i.paid_minor) }}</span></td>
                                <td class="num strong"><span class="mono">{{ show(i.outstanding_minor) }}</span></td>
                            </tr>
                        </tbody>
                    </table>
                </div>
            </div>

            <div v-else class="card overflow-hidden">
                <div v-if="!account.payments.length" class="empty">
                    <div class="empty-ico"><i class="pi pi-wallet" aria-hidden="true" /></div>
                    <p class="empty-text">{{ t('purchasing.none_payments') }}</p>
                </div>
                <div v-else class="dtable-wrap">
                    <table class="dtable">
                        <thead>
                            <tr>
                                <th>{{ t('purchasing.paid_at') }}</th>
                                <th>{{ t('purchasing.method') }}</th>
                                <th class="num">{{ t('purchasing.amount') }}</th>
                                <th class="num">{{ t('purchasing.allocated') }}</th>
                                <th class="num">{{ t('purchasing.on_account') }}</th>
                            </tr>
                        </thead>
                        <tbody>
                            <tr v-for="p in account.payments" :key="p.id" class="row-link" tabindex="0" @click="router.push({ name: 'dashboard.purchasing.payment', params: { id: p.id } })" @keydown.enter.self="router.push({ name: 'dashboard.purchasing.payment', params: { id: p.id } })">
                                <td class="nowrap">{{ fmtDay(p.paid_at, locale) }}</td>
                                <td class="primary">
                                    {{ t('purchasing.methods.' + p.method) }}<span v-if="p.reference"> · <span class="mono" dir="ltr">{{ p.reference }}</span></span>
                                    <span v-if="p.is_voided" class="badge badge-gray ms-1">{{ t('purchasing.voided') }}</span>
                                </td>
                                <td class="num strong"><span class="mono" :class="p.is_voided ? 'strike' : ''">{{ show(p.amount_minor) }}</span></td>
                                <td class="num"><span class="mono">{{ show(p.allocated_minor) }}</span></td>
                                <td class="num"><span class="mono">{{ p.is_voided ? '—' : show(p.on_account_minor) }}</span></td>
                            </tr>
                        </tbody>
                    </table>
                </div>
            </div>
        </template>
    </div>
</template>

<style scoped>
/* Presentation only: theme variables and the PrimeVue primary scale; no new hex values. */
.back { display: inline-flex; align-items: center; gap: 6px; min-height: 36px; font-size: 14.5px; font-weight: 500; color: var(--body); }
.back:hover { color: var(--p-primary-700); }
.badge-amber { color: var(--p-primary-800); }
.badge-gray { color: var(--body); }
.badge-red { color: var(--red); }
.meta-late { display: block; margin-top: 2px; font-size: 13px; font-weight: 600; color: var(--red); }
.actions { display: flex; flex-wrap: wrap; align-items: center; gap: 8px; }
.actions .btn { min-height: 44px; }
@media (max-width: 639px) { .actions { width: 100%; } .actions > .btn { flex: 1 1 auto; justify-content: center; } }
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
.filters { display: flex; flex-wrap: wrap; align-items: center; gap: 10px; }
.filters .input { margin-top: 0; width: auto; min-height: 44px; }
.empty { padding: 40px 20px; text-align: center; }
.empty-ico { width: 48px; height: 48px; margin: 0 auto 12px; border-radius: 50%; display: grid; place-items: center; background: var(--accent-soft); color: var(--p-primary-700); font-size: 20px; }
.empty-text { margin-top: 4px; font-size: 14.5px; color: var(--body); }
.tone-green { color: var(--green) !important; }
.tone-red { color: var(--red) !important; }
.strike { text-decoration: line-through; }
.stat .mono { font-size: clamp(18px, 4.8vw, 24px); line-height: 1.15; overflow-wrap: anywhere; }
.acct-hero { border-color: var(--accent); background: var(--accent-soft); }
.acct-late { background: var(--red-soft); }
.acct-pair { display: flex; flex-direction: column; justify-content: center; gap: 8px; }
.pair-row { display: flex; justify-content: space-between; align-items: baseline; gap: 10px; font-size: 14.5px; color: var(--body); }
.pair-row .mono { font-size: 16px; font-weight: 600; color: var(--ink); line-height: 1.2; }
.tabs { max-width: 100%; overflow-x: auto; }
.tabs button { min-height: 40px; white-space: nowrap; }
.tabs button { color: var(--body); }
.tabs button.active { color: var(--ink); }
</style>
