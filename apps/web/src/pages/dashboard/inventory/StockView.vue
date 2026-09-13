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
        <div class="flex flex-wrap items-start justify-between gap-3">
            <div>
                <h1 class="page-title">{{ t('purchasing.stock_title') }}</h1>
                <p class="page-sub">{{ t('purchasing.stock_sub') }}</p>
            </div>
            <div v-if="canOpenDialog" class="flex flex-wrap gap-2">
                <button type="button" class="btn btn-ghost" @click="openDialog(true)">{{ t('purchasing.adj_opening') }}</button>
                <button type="button" class="btn btn-accent" @click="openDialog(false)">{{ t('purchasing.adj_stock') }}</button>
            </div>
        </div>

        <div class="card p-3 text-sm flex items-start gap-2" style="background:var(--amber-soft);color:var(--ink)">
            <i class="pi pi-info-circle mt-0.5" style="color:var(--amber)" aria-hidden="true"></i>
            <span>{{ t('purchasing.stock_not_on_hand') }}</span>
        </div>

        <div v-if="branches.length > 1" class="flex flex-wrap items-center gap-3">
            <select v-model="branchId" class="input" style="max-width: 260px" :aria-label="t('purchasing.branch')">
                <option value="">{{ t('purchasing.all_branches') }}</option>
                <option v-for="b in branches" :key="b.id" :value="b.id">{{ nameOf(b) }}</option>
            </select>
        </div>

        <ErrorState v-if="failed" :message="t('common.error')" @retry="load" />

        <div v-else class="card overflow-hidden">
            <div v-if="!loading && !rows.length" class="p-8 text-center space-y-3">
                <div class="space-y-1">
                    <div class="font-medium" style="color:var(--ink)">{{ t('purchasing.none_stock') }}</div>
                    <div class="text-sm" style="color:var(--muted)">{{ t('purchasing.none_stock_hint') }}</div>
                </div>
                <button v-if="canOpenDialog" type="button" class="btn btn-ghost btn-sm" @click="openDialog(true)">{{ t('purchasing.adj_opening') }}</button>
            </div>
            <div v-else class="overflow-x-auto">
                <table class="w-full text-sm">
                    <thead>
                        <tr class="text-start" style="color:var(--muted)">
                            <th class="px-5 py-3 text-start font-medium">{{ t('purchasing.item') }}</th>
                            <th v-if="showBranch" class="px-5 py-3 text-start font-medium">{{ t('purchasing.branch') }}</th>
                            <th class="px-5 py-3 text-end font-medium">{{ t('purchasing.recorded_stock_col') }}</th>
                            <th class="px-5 py-3 text-end font-medium">{{ t('purchasing.average_cost') }}</th>
                            <th class="px-5 py-3 text-end font-medium">{{ t('purchasing.value') }}</th>
                            <th v-if="canWrite" class="px-5 py-3"><span class="sr-only">{{ t('purchasing.adj_action') }}</span></th>
                        </tr>
                    </thead>
                    <tbody>
                        <TableSkeleton v-if="loading" :cols="(showBranch ? 5 : 4) + (canWrite ? 1 : 0)" />
                        <template v-else>
                            <tr v-for="r in rows" :key="r.id" class="border-t cursor-pointer hover:bg-black/[.02]" style="border-color:var(--line)" @click="openMovements(r)">
                                <td class="px-5 py-3" style="color:var(--ink)">
                                    <span class="font-medium">{{ nameOf(r.stock_item) }}</span>
                                    <span v-if="r.stock_item && !r.stock_item.is_active" class="text-xs" style="color:var(--muted)"> {{ t('purchasing.retired_suffix') }}</span>
                                </td>
                                <td v-if="showBranch" class="px-5 py-3" style="color:var(--body)">{{ branchName(r.branch_id) }}</td>
                                <td class="px-5 py-3 text-end">
                                    <span class="mono" dir="ltr" :style="recorded(r) < 0 ? 'color:var(--red)' : ''">{{ qty(recorded(r), r.unit_code) }}</span>
                                </td>
                                <td class="px-5 py-3 text-end"><span class="mono" dir="ltr">{{ cost(r.average_cost_minor) }}</span></td>
                                <td class="px-5 py-3 text-end"><span class="mono" dir="ltr">{{ cost(r.value_minor) }}</span></td>
                                <td v-if="canWrite" class="px-5 py-3 text-end">
                                    <button type="button" class="btn btn-ghost btn-sm" @click.stop="openDialog(false, r)">{{ t('purchasing.adj_action') }}</button>
                                </td>
                            </tr>
                        </template>
                    </tbody>
                    <tfoot v-if="!loading && rows.length">
                        <tr class="border-t font-medium" style="border-color:var(--line);color:var(--ink)">
                            <td class="px-5 py-3" :colspan="showBranch ? 4 : 3">{{ t('purchasing.total_value') }}</td>
                            <td class="px-5 py-3 text-end"><span class="mono" dir="ltr">{{ cost(meta.value_minor) }}</span></td>
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
