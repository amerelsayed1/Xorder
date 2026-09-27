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
        <div class="flex flex-wrap items-start justify-between gap-3">
            <div>
                <h1 class="page-title">{{ t('purchasing.invoices_title') }}</h1>
                <p class="page-sub">{{ t('purchasing.invoices_sub') }}</p>
            </div>
            <RouterLink v-if="canWrite" :to="{ name: 'dashboard.purchasing.invoices.create', query: filters.supplier_id ? { supplier_id: filters.supplier_id } : {} }" class="btn btn-accent">
                <Icon name="plus" :size="16" />{{ t('purchasing.new_invoice') }}
            </RouterLink>
        </div>

        <div v-if="lookups" class="flex flex-wrap items-center gap-3">
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
            <button v-if="orderId" type="button" class="btn btn-ghost btn-sm" @click="clearOrder">
                {{ t('purchasing.purchase_order') }} <span class="mono" dir="ltr">#{{ orderId }}</span> <Icon name="close" :size="14" />
            </button>
        </div>

        <ErrorState v-if="failed" :message="t('common.error')" @retry="load" />

        <div v-else class="card overflow-hidden">
            <div v-if="!loading && !rows.length" class="p-8 text-center space-y-1">
                <div v-if="filtered" class="text-sm" style="color:var(--muted)">{{ t('purchasing.none_invoices_match') }}</div>
                <template v-else>
                    <div class="font-medium" style="color:var(--ink)">{{ t('purchasing.none_invoices') }}</div>
                    <div class="text-sm" style="color:var(--muted)">{{ t('purchasing.none_invoices_hint') }}</div>
                </template>
            </div>
            <div v-else class="overflow-x-auto">
                <table class="w-full text-sm">
                    <thead>
                        <tr style="color:var(--muted)">
                            <th class="px-5 py-3 text-start font-medium">{{ t('purchasing.invoice_number') }}</th>
                            <th class="px-5 py-3 text-start font-medium">{{ t('purchasing.supplier') }}</th>
                            <th v-if="branches.length > 1" class="px-5 py-3 text-start font-medium">{{ t('purchasing.branch') }}</th>
                            <th class="px-5 py-3 text-start font-medium">{{ t('purchasing.issued_at') }}</th>
                            <th class="px-5 py-3 text-start font-medium">{{ t('purchasing.due_at') }}</th>
                            <th class="px-5 py-3 text-end font-medium">{{ t('purchasing.total') }}</th>
                            <th class="px-5 py-3 text-end font-medium">{{ t('purchasing.outstanding') }}</th>
                            <th class="px-5 py-3 text-start font-medium">{{ t('common.status') }}</th>
                        </tr>
                    </thead>
                    <tbody>
                        <TableSkeleton v-if="loading" :cols="branches.length > 1 ? 8 : 7" />
                        <template v-else>
                            <tr v-for="i in rows" :key="i.id" class="border-t cursor-pointer hover:bg-black/[.02]" style="border-color:var(--line)" @click="router.push({ name: 'dashboard.purchasing.invoice', params: { id: i.id } })">
                                <td class="px-5 py-3"><span class="mono" dir="ltr" style="color:var(--ink)">{{ i.number }}</span></td>
                                <td class="px-5 py-3" style="color:var(--ink)">{{ i.supplier_name }}</td>
                                <td v-if="branches.length > 1" class="px-5 py-3" style="color:var(--body)">{{ nameOf(i.branch) }}</td>
                                <td class="px-5 py-3 whitespace-nowrap" style="color:var(--body)">{{ fmtDay(i.issued_at, locale) }}</td>
                                <td class="px-5 py-3 whitespace-nowrap" style="color:var(--body)">
                                    {{ fmtDay(i.due_at, locale) }}
                                    <div v-if="i.days_late" class="text-xs" style="color:var(--red)">{{ t('purchasing.days_late', { n: i.days_late }) }}</div>
                                </td>
                                <td class="px-5 py-3 text-end"><span class="mono">{{ show(i, i.total_minor) }}</span></td>
                                <td class="px-5 py-3 text-end"><span class="mono">{{ i.is_voided ? '—' : show(i, i.outstanding_minor) }}</span></td>
                                <td class="px-5 py-3"><span class="badge" :class="invoiceBadge(i.state)">{{ t('purchasing.invoice_states.' + i.state) }}</span></td>
                            </tr>
                        </template>
                    </tbody>
                </table>
            </div>
            <div v-if="!loading && lastPage > 1" class="flex items-center justify-end gap-2 px-4 py-3 border-t" style="border-color:var(--line)">
                <button type="button" class="btn btn-ghost btn-sm" :disabled="page <= 1" @click="go(page - 1)">{{ t('common.previous') }}</button>
                <span class="mono text-xs" dir="ltr" style="color:var(--muted)">{{ page }} / {{ lastPage }}</span>
                <button type="button" class="btn btn-ghost btn-sm" :disabled="page >= lastPage" @click="go(page + 1)">{{ t('common.next') }}</button>
            </div>
        </div>
    </div>
</template>
