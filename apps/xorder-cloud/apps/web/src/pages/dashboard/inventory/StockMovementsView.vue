<script setup>
import { ref, computed, onMounted, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute, useRouter } from 'vue-router'
import api from '@xorder/api-client/api.js'
import { withMinDuration } from '../../../lib/minLoading.js'
import { pickLocalized } from '@xorder/ui/localize.js'
import TableSkeleton from '@xorder/ui/TableSkeleton.vue'
import ErrorState from '@xorder/ui/ErrorState.vue'
import Icon from '@xorder/ui/Icon.vue'
import { fmtDate, money, qty } from '../purchasing/format.js'
import { formatMilli } from '../../../lib/quantity.js'

// CB-09 slice b. One stock item's ledger, newest first. Append-only: each
// row records the position that resulted from it, so this page is also how
// anyone checks a "recorded stock" figure by eye. Since slice d it also
// lists openings, waste, adjustments and counts, each with its reason.
const { t, locale } = useI18n()
const route = useRoute()
const router = useRouter()

const item = ref(null)
const rows = ref([])
const branches = ref([])
const meta = ref({ exponent: 2, currency: null })
const page = ref(1)
const lastPage = ref(1)
const branchId = ref(route.query.branch_id ? Number(route.query.branch_id) : '')
const loading = ref(true)
const failed = ref(false)

async function load() {
    loading.value = true
    failed.value = false
    try {
        const id = route.params.itemId
        const params = { page: page.value, ...(branchId.value ? { branch_id: branchId.value } : {}) }
        const [it, moves, lookups] = await withMinDuration(Promise.all([
            item.value ? Promise.resolve(null) : api.get(`api/dashboard/stock-items/${id}`),
            api.get(`api/dashboard/stock-items/${id}/movements`, { params }),
            branches.value.length ? Promise.resolve(null) : api.get('api/dashboard/purchasing/lookups'),
        ]))
        if (it) item.value = it.data.data
        if (lookups) {
            branches.value = lookups.data.data.branches
            meta.value = { exponent: lookups.data.data.exponent, currency: lookups.data.data.currency }
        }
        rows.value = moves.data.data
        lastPage.value = moves.data.last_page || 1
    } catch {
        failed.value = true
    } finally {
        loading.value = false
    }
}
onMounted(load)
watch(branchId, () => { page.value = 1; load() })
function go(p) { page.value = p; load() }

const nameOf = (s) => (s ? (pickLocalized(s, 'name', locale.value) || s.name_en || s.name_ar || `#${s.id}`) : '')
const branchName = (id) => nameOf(branches.value.find((b) => b.id === id)) || `#${id}`
const cost = (minor) => money(minor, meta.value.exponent, meta.value.currency, locale.value)
const signed = (m) => (m.quantity_milli > 0 ? '+' : '') + formatMilli(m.quantity_milli) + ' ' + m.unit_code
const showBranch = computed(() => !branchId.value && branches.value.length > 1)
</script>

<template>
    <div class="space-y-5">
        <button type="button" class="back" @click="router.push({ name: 'dashboard.inventory.stock' })">
            <Icon name="chevronDown" :size="16" class="rotate-90 rtl:-rotate-90" />{{ t('purchasing.stock_title') }}
        </button>

        <div>
            <h1 class="page-title">{{ item ? nameOf(item) : t('purchasing.movements_title') }}</h1>
            <p class="page-sub" style="color:var(--body)">{{ t('purchasing.movements_sub') }}</p>
        </div>

        <div v-if="branches.length > 1" class="filters">
            <select v-model="branchId" class="input" style="max-width: 260px" :aria-label="t('purchasing.branch')">
                <option value="">{{ t('purchasing.all_branches') }}</option>
                <option v-for="b in branches" :key="b.id" :value="b.id">{{ nameOf(b) }}</option>
            </select>
        </div>

        <ErrorState v-if="failed" :message="t('common.error')" @retry="load" />

        <div v-else class="card overflow-hidden">
            <div v-if="!loading && !rows.length" class="empty">
                <div class="empty-ico"><i class="pi pi-history" aria-hidden="true" /></div>
                <p class="empty-text">{{ t('purchasing.none_movements') }}</p>
            </div>
            <div v-else class="overflow-x-auto">
                <table class="dtable">
                    <thead>
                        <tr>
                            <th>{{ t('purchasing.date') }}</th>
                            <th v-if="showBranch">{{ t('purchasing.branch') }}</th>
                            <th>{{ t('purchasing.kind') }}</th>
                            <th class="num">{{ t('purchasing.quantity') }}</th>
                            <th class="num">{{ t('purchasing.unit_cost') }}</th>
                            <th class="num">{{ t('purchasing.balance_after') }}</th>
                            <th class="num">{{ t('purchasing.average_after') }}</th>
                            <th>{{ t('purchasing.reference') }}</th>
                            <th>{{ t('purchasing.by') }}</th>
                        </tr>
                    </thead>
                    <tbody>
                        <TableSkeleton v-if="loading" :cols="showBranch ? 9 : 8" />
                        <template v-else>
                            <tr v-for="m in rows" :key="m.id">
                                <td class="nowrap">{{ fmtDate(m.occurred_at, locale, { time: true }) }}</td>
                                <td v-if="showBranch">{{ branchName(m.branch_id) }}</td>
                                <td class="primary">
                                    <div>{{ t('purchasing.kinds.' + m.kind) }}</div>
                                    <!-- Slice d: an entry that is not a delivery says why, and any note. -->
                                    <div v-if="m.reason" class="sub">{{ t('purchasing.stock_reasons.' + m.reason) }}</div>
                                    <div v-if="m.note && !m.purchase_order_id" class="sub max-w-[16rem] truncate" :title="m.note">{{ m.note }}</div>
                                </td>
                                <td class="num strong"><span class="mono" dir="ltr">{{ signed(m) }}</span></td>
                                <td class="num"><span class="mono">{{ cost(m.unit_cost_minor) }}</span></td>
                                <td class="num"><span class="mono" dir="ltr">{{ qty(m.balance_milli, m.unit_code) }}</span></td>
                                <td class="num"><span class="mono">{{ cost(m.average_cost_minor) }}</span></td>
                                <td>
                                    <RouterLink v-if="m.purchase_order_id" :to="{ name: 'dashboard.purchasing.order', params: { id: m.purchase_order_id } }" class="mono list-link" dir="ltr">{{ m.purchase_order_reference || ('#' + m.purchase_order_id) }}</RouterLink>
                                </td>
                                <td>{{ m.created_by || '' }}</td>
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
.back { display: inline-flex; align-items: center; gap: 6px; min-height: 36px; font-size: 14.5px; font-weight: 500; color: var(--body); }
.back:hover { color: var(--p-primary-700); }
.note { display: flex; align-items: flex-start; gap: 10px; padding: 12px 14px; border-radius: 12px; font-size: 14.5px; line-height: 1.5; }
.note > i { margin-top: 3px; flex: none; }
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
.empty-text { margin-top: 4px; font-size: 14.5px; color: var(--body); }
.list-link { font-size: 14.5px; font-weight: 500; color: var(--p-primary-700); }
.list-link:hover { text-decoration: underline; }
.dtable .btn { min-height: 40px; }
.dtable { min-width: 900px; }
</style>
