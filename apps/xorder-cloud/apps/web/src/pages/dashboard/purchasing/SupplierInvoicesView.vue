<script setup>
import { ref, reactive, computed, onMounted, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute, useRouter } from 'vue-router'
import api from '@xorder/api-client/api.js'
import { useAuth } from '@xorder/api-client/auth.js'
import { withMinDuration } from '../../../lib/minLoading.js'
import { pickLocalized } from '@xorder/ui/localize.js'
import TableSkeleton from '@xorder/ui/TableSkeleton.vue'
import ErrorState from '@xorder/ui/ErrorState.vue'
import Icon from '@xorder/ui/Icon.vue'
import { invoiceBadge, INVOICE_STATES, fmtDay, money } from './format.js'
import PageTabs from '../../../components/PageTabs.vue'
import { PURCHASING_TABS } from '../tabs.config.js'

// CB-09 slice c. Supplier invoices, newest first, filterable by branch,
// supplier and state. Paid, outstanding and the state are derived by the
// server from the live payments allocated to each invoice; nothing here adds
// money up. An invoice never changes the cost of stock.
const { t, locale } = useI18n()
const route = useRoute()
const router = useRouter()
const auth = useAuth()
const canWrite = computed(() => auth.can('purchase.manage') && !auth.isReadOnly)

const rows = ref([])
const lookups = ref(null)
const filters = reactive({
    branch_id: route.query.branch_id ? Number(route.query.branch_id) : '',
    supplier_id: route.query.supplier_id ? Number(route.query.supplier_id) : '',
    state: typeof route.query.state === 'string' ? route.query.state : '',
})
// Arrived from a purchase order's "Invoices" link.
const orderId = ref(route.query.purchase_order_id ? Number(route.query.purchase_order_id) : null)
const page = ref(1)
const lastPage = ref(1)
const loading = ref(true)
const failed = ref(false)

async function load() {
    loading.value = true
    failed.value = false
    try {
        const params = { page: page.value }
        for (const [k, v] of Object.entries(filters)) if (v !== '') params[k] = v
        if (orderId.value) params.purchase_order_id = orderId.value
        const [list, lk] = await withMinDuration(Promise.all([
            api.get('api/dashboard/supplier-invoices', { params }),
            lookups.value ? Promise.resolve(null) : api.get('api/dashboard/purchasing/lookups'),
        ]))
        rows.value = list.data.data
        lastPage.value = list.data.meta?.last_page || 1
        if (lk) lookups.value = lk.data.data
    } catch {
        failed.value = true
    } finally {
        loading.value = false
    }
}
onMounted(load)
watch(filters, () => { page.value = 1; load() }, { deep: true })
function go(p) { page.value = p; load() }
function clearOrder() { orderId.value = null; router.replace({ query: {} }); load() }

const filtered = computed(() => Object.values(filters).some((v) => v !== '') || !!orderId.value)
const nameOf = (s) => (s ? (pickLocalized(s, 'name', locale.value) || s.name_en || s.name_ar || `#${s.id}`) : '')
const branches = computed(() => lookups.value?.branches || [])
const suppliers = computed(() => lookups.value?.suppliers || [])
const show = (i, minor) => money(minor, i.exponent, i.currency, locale.value)
</script>

<template>
    <div class="space-y-5">
        <PageTabs :tabs="PURCHASING_TABS" />

        <div class="flex flex-wrap items-start justify-between gap-3">
            <div class="min-w-0">
                <h1 class="page-title">{{ t('purchasing.invoices_title') }}</h1>
                <p class="page-sub" style="color:var(--body)">{{ t('purchasing.invoices_sub') }}</p>
            </div>
            <RouterLink v-if="canWrite" :to="{ name: 'dashboard.purchasing.invoices.create', query: filters.supplier_id ? { supplier_id: filters.supplier_id } : {} }" class="btn btn-accent new-btn">
                <Icon name="plus" :size="16" />{{ t('purchasing.new_invoice') }}
            </RouterLink>
        </div>

        <div v-if="lookups" class="filters">
            <select v-if="branches.length > 1" v-model="filters.branch_id" class="input" style="max-width: 220px" :aria-label="t('purchasing.branch')">
                <option value="">{{ t('purchasing.all_branches') }}</option>
                <option v-for="b in branches" :key="b.id" :value="b.id">{{ nameOf(b) }}</option>
            </select>
            <select v-model="filters.supplier_id" class="input" style="max-width: 240px" :aria-label="t('purchasing.supplier')">
                <option value="">{{ t('purchasing.all_suppliers') }}</option>
                <option v-for="s in suppliers" :key="s.id" :value="s.id">{{ nameOf(s) }}{{ s.is_active ? '' : ' ' + t('purchasing.retired_suffix') }}</option>
            </select>
            <select v-model="filters.state" class="input" style="max-width: 180px" :aria-label="t('common.status')">
                <option value="">{{ t('purchasing.all_states') }}</option>
                <option v-for="s in INVOICE_STATES" :key="s" :value="s">{{ t('purchasing.invoice_states.' + s) }}</option>
            </select>
            <button v-if="orderId" type="button" class="btn btn-ghost btn-sm chip-btn" @click="clearOrder">
                {{ t('purchasing.purchase_order') }} <span class="mono" dir="ltr">#{{ orderId }}</span> <Icon name="close" :size="14" />
            </button>
        </div>

        <ErrorState v-if="failed" :message="t('common.error')" @retry="load" />

        <div v-else class="card overflow-hidden">
            <div v-if="!loading && !rows.length" class="empty">
                <div class="empty-ico"><i class="pi pi-file" aria-hidden="true" /></div>
                <p v-if="filtered" class="empty-text">{{ t('purchasing.none_invoices_match') }}</p>
                <template v-else>
                    <div class="empty-title">{{ t('purchasing.none_invoices') }}</div>
                    <p class="empty-text">{{ t('purchasing.none_invoices_hint') }}</p>
                    <RouterLink v-if="canWrite" :to="{ name: 'dashboard.purchasing.invoices.create' }" class="btn btn-accent mt-4">
                        <Icon name="plus" :size="16" />{{ t('purchasing.new_invoice') }}
                    </RouterLink>
                </template>
            </div>
            <div v-else class="dtable-wrap">
                <table class="dtable">
                    <thead>
                        <tr>
                            <th>{{ t('purchasing.invoice_number') }}</th>
                            <th>{{ t('purchasing.supplier') }}</th>
                            <th v-if="branches.length > 1">{{ t('purchasing.branch') }}</th>
                            <th>{{ t('purchasing.issued_at') }}</th>
                            <th>{{ t('purchasing.due_at') }}</th>
                            <th class="num">{{ t('purchasing.total') }}</th>
                            <th class="num">{{ t('purchasing.outstanding') }}</th>
                            <th>{{ t('common.status') }}</th>
                        </tr>
                    </thead>
                    <tbody>
                        <TableSkeleton v-if="loading" :cols="branches.length > 1 ? 8 : 7" />
                        <template v-else>
                            <tr v-for="i in rows" :key="i.id" class="row-link" tabindex="0" @click="router.push({ name: 'dashboard.purchasing.invoice', params: { id: i.id } })" @keydown.enter.self="router.push({ name: 'dashboard.purchasing.invoice', params: { id: i.id } })">
                                <td class="primary"><span class="mono" dir="ltr">{{ i.number }}</span></td>
                                <td class="primary">{{ i.supplier_name }}</td>
                                <td v-if="branches.length > 1">{{ nameOf(i.branch) }}</td>
                                <td class="nowrap">{{ fmtDay(i.issued_at, locale) }}</td>
                                <td class="nowrap">
                                    {{ fmtDay(i.due_at, locale) }}
                                    <span v-if="i.days_late" class="meta-late">{{ t('purchasing.days_late', { n: i.days_late }) }}</span>
                                </td>
                                <td class="num"><span class="mono">{{ show(i, i.total_minor) }}</span></td>
                                <td class="num strong"><span class="mono">{{ i.is_voided ? '—' : show(i, i.outstanding_minor) }}</span></td>
                                <td class="nowrap"><span class="badge" :class="invoiceBadge(i.state)">{{ t('purchasing.invoice_states.' + i.state) }}</span></td>
                            </tr>
                        </template>
                    </tbody>
                </table>
            </div>
            <div v-if="!loading && lastPage > 1" class="pager">
                <button type="button" class="btn btn-ghost btn-sm" :disabled="page <= 1" @click="go(page - 1)">{{ t('common.previous') }}</button>
                <span class="mono pager-info" dir="ltr">{{ page }} / {{ lastPage }}</span>
                <button type="button" class="btn btn-ghost btn-sm" :disabled="page >= lastPage" @click="go(page + 1)">{{ t('common.next') }}</button>
            </div>
        </div>
    </div>
</template>

<style scoped>
/* Presentation only: theme variables and the PrimeVue primary scale; no new hex values. */
.badge-amber { color: var(--p-primary-800); }
.badge-gray { color: var(--body); }
.badge-red { color: var(--red); }
.meta-late { display: block; margin-top: 2px; font-size: 13px; font-weight: 600; color: var(--red); }
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
.pager { display: flex; align-items: center; justify-content: flex-end; gap: 8px; padding: 12px 16px; border-top: 1px solid var(--line); }
.pager .btn { min-height: 40px; }
.pager-info { font-size: 13.5px; color: var(--body); }
.filters { display: flex; flex-wrap: wrap; align-items: center; gap: 10px; }
.filters .input { margin-top: 0; width: auto; min-height: 44px; }
.empty { padding: 40px 20px; text-align: center; }
.empty-ico { width: 48px; height: 48px; margin: 0 auto 12px; border-radius: 50%; display: grid; place-items: center; background: var(--accent-soft); color: var(--p-primary-700); font-size: 20px; }
.empty-title { font-weight: 600; color: var(--ink); }
.empty-text { margin-top: 4px; font-size: 14.5px; color: var(--body); }
.new-btn { min-height: 44px; }
.chip-btn { min-height: 44px; }
</style>
