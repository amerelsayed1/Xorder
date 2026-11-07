<script setup>
import { ref, computed, onMounted, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRouter } from 'vue-router'
import api from '@xorder/api-client/api.js'
import { useAuth } from '@xorder/api-client/auth.js'
import { withMinDuration } from '../../../lib/minLoading.js'
import { pickLocalized } from '@xorder/ui/localize.js'
import TableSkeleton from '@xorder/ui/TableSkeleton.vue'
import ErrorState from '@xorder/ui/ErrorState.vue'
import { money, qty } from '../purchasing/format.js'
import StockAdjustDialog from './StockAdjustDialog.vue'
import PageTabs from '../../../components/PageTabs.vue'
import { STOCK_TABS } from '../tabs.config.js'

// CB-09. RECORDED STOCK, per branch, at the moving average: deliveries
// received (slice b) plus opening stock and adjustments, less waste (slice
// d). Slice b headed it "Received to date"; once waste can lower it that is
// no longer true, and it is still not "on hand", because tills don't deduct
// stock when they sell (D4). The heading and the note say so in both
// languages. The figure changes only by a new movement: a delivery, or an
// entry from the adjust dialog. Nothing here edits a level.
const { t, locale } = useI18n()
const router = useRouter()
const auth = useAuth()
const canWrite = computed(() => auth.can('purchase.manage') && !auth.isReadOnly)

const rows = ref([])
const meta = ref({ value_minor: 0, exponent: 2, currency: null })
const branches = ref([])
const items = ref([])
const units = ref([])
const branchId = ref('')
const loading = ref(true)
const failed = ref(false)

async function load() {
    loading.value = true
    failed.value = false
    try {
        const params = branchId.value ? { branch_id: branchId.value } : {}
        const [levels, lookups] = await withMinDuration(Promise.all([
            api.get('api/dashboard/stock-levels', { params }),
            branches.value.length ? Promise.resolve(null) : api.get('api/dashboard/purchasing/lookups'),
        ]))
        rows.value = levels.data.data
        meta.value = levels.data.meta
        if (lookups) {
            branches.value = lookups.data.data.branches
            items.value = lookups.data.data.stock_items
            units.value = lookups.data.data.units
        }
    } catch {
        failed.value = true
    } finally {
        loading.value = false
    }
}
onMounted(load)
watch(branchId, load)

const nameOf = (s) => (s ? (pickLocalized(s, 'name', locale.value) || s.name_en || s.name_ar || `#${s.id}`) : '')
const branchName = (id) => nameOf(branches.value.find((b) => b.id === id)) || `#${id}`
const showBranch = computed(() => !branchId.value && branches.value.length > 1)
const cost = (minor) => money(minor, meta.value.exponent, meta.value.currency, locale.value)
// quantity_milli since slice d; received_milli is the same figure's old name.
const recorded = (r) => r.quantity_milli ?? r.received_milli

function openMovements(row) {
    router.push({ name: 'dashboard.inventory.movements', params: { itemId: row.stock_item_id }, query: { branch_id: row.branch_id } })
}

// ------------------------------------------------------ slice d: entries
const dialog = ref(null) // { opening, branchId, stockItemId }
const canOpenDialog = computed(() => canWrite.value && items.value.length > 0)
function openDialog(opening, row = null) {
    dialog.value = {
        opening,
        branchId: row ? row.branch_id : (branchId.value || ''),
        stockItemId: row ? row.stock_item_id : '',
    }
}
function saved() {
    dialog.value = null
    load()
}
</script>

<template>
    <div class="space-y-5">
        <PageTabs :tabs="STOCK_TABS" />

        <div class="flex flex-wrap items-start justify-between gap-3">
            <div>
                <h1 class="page-title">{{ t('purchasing.stock_title') }}</h1>
                <p class="page-sub" style="color:var(--body)">{{ t('purchasing.stock_sub') }}</p>
            </div>
            <div v-if="canOpenDialog" class="head-actions flex flex-wrap gap-2">
                <button type="button" class="btn btn-ghost" @click="openDialog(true)">{{ t('purchasing.adj_opening') }}</button>
                <button type="button" class="btn btn-accent" @click="openDialog(false)">{{ t('purchasing.adj_stock') }}</button>
            </div>
        </div>

        <div class="note note-amber" role="note">
            <i class="pi pi-info-circle" aria-hidden="true"></i>
            <span>{{ t('purchasing.stock_not_on_hand') }}</span>
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
                <div class="empty-ico"><i class="pi pi-box" aria-hidden="true" /></div>
                <div class="empty-title">{{ t('purchasing.none_stock') }}</div>
                <p class="empty-text">{{ t('purchasing.none_stock_hint') }}</p>
                <button v-if="canOpenDialog" type="button" class="btn btn-accent mt-4" @click="openDialog(true)">{{ t('purchasing.adj_opening') }}</button>
            </div>
            <div v-else class="overflow-x-auto">
                <table class="dtable">
                    <thead>
                        <tr>
                            <th>{{ t('purchasing.item') }}</th>
                            <th v-if="showBranch">{{ t('purchasing.branch') }}</th>
                            <th class="num">{{ t('purchasing.recorded_stock_col') }}</th>
                            <th class="num">{{ t('purchasing.average_cost') }}</th>
                            <th class="num">{{ t('purchasing.value') }}</th>
                            <th v-if="canWrite"><span class="sr-only">{{ t('purchasing.adj_action') }}</span></th>
                        </tr>
                    </thead>
                    <tbody>
                        <TableSkeleton v-if="loading" :cols="(showBranch ? 5 : 4) + (canWrite ? 1 : 0)" />
                        <template v-else>
                            <tr v-for="r in rows" :key="r.id" class="row-link" tabindex="0" @click="openMovements(r)" @keydown.enter.self="openMovements(r)">
                                <td class="primary">
                                    <span class="font-medium">{{ nameOf(r.stock_item) }}</span>
                                    <span v-if="r.stock_item && !r.stock_item.is_active" class="text-sm" style="color:var(--body)"> {{ t('purchasing.retired_suffix') }}</span>
                                </td>
                                <td v-if="showBranch">{{ branchName(r.branch_id) }}</td>
                                <td class="num">
                                    <span class="mono" dir="ltr" :style="recorded(r) < 0 ? 'color:var(--red)' : ''">{{ qty(recorded(r), r.unit_code) }}</span>
                                </td>
                                <td class="num"><span class="mono">{{ cost(r.average_cost_minor) }}</span></td>
                                <td class="num strong"><span class="mono">{{ cost(r.value_minor) }}</span></td>
                                <td v-if="canWrite" class="num">
                                    <button type="button" class="btn btn-ghost btn-sm" @click.stop="openDialog(false, r)">{{ t('purchasing.adj_action') }}</button>
                                </td>
                            </tr>
                        </template>
                    </tbody>
                    <tfoot v-if="!loading && rows.length">
                        <tr class="tfoot-row">
                            <td class="foot-label" :colspan="showBranch ? 4 : 3">{{ t('purchasing.total_value') }}</td>
                            <td class="num foot-total"><span class="mono">{{ cost(meta.value_minor) }}</span></td>
                            <td v-if="canWrite"></td>
                        </tr>
                    </tfoot>
                </table>
            </div>
        </div>

        <StockAdjustDialog
            v-if="dialog"
            :opening="dialog.opening"
            :branches="branches"
            :items="items"
            :units="units"
            :exponent="meta.exponent ?? 2"
            :currency="meta.currency"
            :branch-id="dialog.branchId"
            :stock-item-id="dialog.stockItemId"
            @saved="saved"
            @close="dialog = null"
        />
    </div>
</template>

<style scoped>
/* Presentation only: theme variables and the PrimeVue primary scale; no new hex values. */
.note { display: flex; align-items: flex-start; gap: 10px; padding: 12px 14px; border-radius: 12px; font-size: 14.5px; line-height: 1.5; }
.note > i { margin-top: 3px; flex: none; }
.note-amber { background: var(--amber-soft); color: var(--p-primary-800); }
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
.empty-title { font-weight: 600; color: var(--ink); }
.empty-text { margin-top: 4px; font-size: 14.5px; color: var(--body); }
.tfoot-row td { background: var(--page); border-top: 2px solid var(--line); font-weight: 700; color: var(--ink); }
.foot-total .mono { font-family: var(--font-display); font-size: 20px; }
.dtable .btn { min-height: 40px; }
</style>
