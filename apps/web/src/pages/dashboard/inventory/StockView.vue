<script setup>
import { ref, computed, onMounted, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRouter } from 'vue-router'
import api from '@xorder/api-client/api.js'
import { withMinDuration } from '../../../lib/minLoading.js'
import { pickLocalized } from '@xorder/ui/localize.js'
import TableSkeleton from '@xorder/ui/TableSkeleton.vue'
import ErrorState from '@xorder/ui/ErrorState.vue'
import { money, qty } from '../purchasing/format.js'

// CB-09 slice b. RECEIVED TO DATE, per branch, at the moving average.
// Deliberately never called "on hand": tills don't deduct stock when they
// sell (D4), so this only ever goes up. The heading and the note say so in
// both languages. Read-only: a figure changes only by receiving goods.
const { t, locale } = useI18n()
const router = useRouter()

const rows = ref([])
const meta = ref({ value_minor: 0, exponent: 2, currency: null })
const branches = ref([])
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
        if (lookups) branches.value = lookups.data.data.branches
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

function openMovements(row) {
    router.push({ name: 'dashboard.inventory.movements', params: { itemId: row.stock_item_id }, query: { branch_id: row.branch_id } })
}
</script>

<template>
    <div class="space-y-5">
        <div>
            <h1 class="page-title">{{ t('purchasing.stock_title') }}</h1>
            <p class="page-sub">{{ t('purchasing.stock_sub') }}</p>
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
            <div v-if="!loading && !rows.length" class="p-8 text-center space-y-1">
                <div class="font-medium" style="color:var(--ink)">{{ t('purchasing.none_stock') }}</div>
                <div class="text-sm" style="color:var(--muted)">{{ t('purchasing.none_stock_hint') }}</div>
            </div>
            <div v-else class="overflow-x-auto">
                <table class="w-full text-sm">
                    <thead>
                        <tr class="text-start" style="color:var(--muted)">
                            <th class="px-5 py-3 text-start font-medium">{{ t('purchasing.item') }}</th>
                            <th v-if="showBranch" class="px-5 py-3 text-start font-medium">{{ t('purchasing.branch') }}</th>
                            <th class="px-5 py-3 text-end font-medium">{{ t('purchasing.received_to_date') }}</th>
                            <th class="px-5 py-3 text-end font-medium">{{ t('purchasing.average_cost') }}</th>
                            <th class="px-5 py-3 text-end font-medium">{{ t('purchasing.value') }}</th>
                        </tr>
                    </thead>
                    <tbody>
                        <TableSkeleton v-if="loading" :cols="showBranch ? 5 : 4" />
                        <template v-else>
                            <tr v-for="r in rows" :key="r.id" class="border-t cursor-pointer hover:bg-black/[.02]" style="border-color:var(--line)" @click="openMovements(r)">
                                <td class="px-5 py-3" style="color:var(--ink)">
                                    <span class="font-medium">{{ nameOf(r.stock_item) }}</span>
                                    <span v-if="r.stock_item && !r.stock_item.is_active" class="text-xs" style="color:var(--muted)"> {{ t('purchasing.retired_suffix') }}</span>
                                </td>
                                <td v-if="showBranch" class="px-5 py-3" style="color:var(--body)">{{ branchName(r.branch_id) }}</td>
                                <td class="px-5 py-3 text-end"><span class="mono" dir="ltr">{{ qty(r.received_milli, r.unit_code) }}</span></td>
                                <td class="px-5 py-3 text-end"><span class="mono" dir="ltr">{{ cost(r.average_cost_minor) }}</span></td>
                                <td class="px-5 py-3 text-end"><span class="mono" dir="ltr">{{ cost(r.value_minor) }}</span></td>
                            </tr>
                        </template>
                    </tbody>
                    <tfoot v-if="!loading && rows.length">
                        <tr class="border-t font-medium" style="border-color:var(--line);color:var(--ink)">
                            <td class="px-5 py-3" :colspan="showBranch ? 4 : 3">{{ t('purchasing.total_value') }}</td>
                            <td class="px-5 py-3 text-end"><span class="mono" dir="ltr">{{ cost(meta.value_minor) }}</span></td>
                        </tr>
                    </tfoot>
                </table>
            </div>
        </div>
    </div>
</template>
