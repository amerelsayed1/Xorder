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
        <button type="button" class="flex items-center gap-1.5 text-sm" style="color:var(--muted)" @click="router.push({ name: 'dashboard.inventory.stock' })">
            <Icon name="chevronDown" :size="16" class="rotate-90 rtl:-rotate-90" />{{ t('purchasing.stock_title') }}
        </button>

        <div>
            <h1 class="page-title">{{ item ? nameOf(item) : t('purchasing.movements_title') }}</h1>
            <p class="page-sub">{{ t('purchasing.movements_sub') }}</p>
        </div>

        <div v-if="branches.length > 1" class="flex flex-wrap items-center gap-3">
            <select v-model="branchId" class="input" style="max-width: 260px" :aria-label="t('purchasing.branch')">
                <option value="">{{ t('purchasing.all_branches') }}</option>
                <option v-for="b in branches" :key="b.id" :value="b.id">{{ nameOf(b) }}</option>
            </select>
        </div>

        <ErrorState v-if="failed" :message="t('common.error')" @retry="load" />

        <div v-else class="card overflow-hidden">
            <div v-if="!loading && !rows.length" class="p-8 text-center text-sm" style="color:var(--muted)">{{ t('purchasing.none_movements') }}</div>
            <div v-else class="overflow-x-auto">
                <table class="w-full text-sm">
                    <thead>
                        <tr style="color:var(--muted)">
                            <th class="px-4 py-3 text-start font-medium">{{ t('purchasing.date') }}</th>
                            <th v-if="showBranch" class="px-4 py-3 text-start font-medium">{{ t('purchasing.branch') }}</th>
                            <th class="px-4 py-3 text-start font-medium">{{ t('purchasing.kind') }}</th>
                            <th class="px-4 py-3 text-end font-medium">{{ t('purchasing.quantity') }}</th>
                            <th class="px-4 py-3 text-end font-medium">{{ t('purchasing.unit_cost') }}</th>
                            <th class="px-4 py-3 text-end font-medium">{{ t('purchasing.balance_after') }}</th>
                            <th class="px-4 py-3 text-end font-medium">{{ t('purchasing.average_after') }}</th>
                            <th class="px-4 py-3 text-start font-medium">{{ t('purchasing.reference') }}</th>
                            <th class="px-4 py-3 text-start font-medium">{{ t('purchasing.by') }}</th>
                        </tr>
                    </thead>
                    <tbody>
                        <TableSkeleton v-if="loading" :cols="showBranch ? 9 : 8" />
                        <template v-else>
                            <tr v-for="m in rows" :key="m.id" class="border-t" style="border-color:var(--line)">
                                <td class="px-4 py-3 whitespace-nowrap" style="color:var(--body)">{{ fmtDate(m.occurred_at, locale, { time: true }) }}</td>
                                <td v-if="showBranch" class="px-4 py-3" style="color:var(--body)">{{ branchName(m.branch_id) }}</td>
                                <td class="px-4 py-3" style="color:var(--ink)">
                                    <div>{{ t('purchasing.kinds.' + m.kind) }}</div>
                                    <!-- Slice d: an entry that is not a delivery says why, and any note. -->
                                    <div v-if="m.reason" class="text-xs" style="color:var(--muted)">{{ t('purchasing.stock_reasons.' + m.reason) }}</div>
                                    <div v-if="m.note && !m.purchase_order_id" class="text-xs max-w-[16rem] truncate" style="color:var(--muted)" :title="m.note">{{ m.note }}</div>
                                </td>
                                <td class="px-4 py-3 text-end"><span class="mono" dir="ltr">{{ signed(m) }}</span></td>
                                <td class="px-4 py-3 text-end"><span class="mono" dir="ltr">{{ cost(m.unit_cost_minor) }}</span></td>
                                <td class="px-4 py-3 text-end"><span class="mono" dir="ltr">{{ qty(m.balance_milli, m.unit_code) }}</span></td>
                                <td class="px-4 py-3 text-end"><span class="mono" dir="ltr">{{ cost(m.average_cost_minor) }}</span></td>
                                <td class="px-4 py-3">
                                    <RouterLink v-if="m.purchase_order_id" :to="{ name: 'dashboard.purchasing.order', params: { id: m.purchase_order_id } }" class="mono" dir="ltr" style="color:var(--accent)">{{ m.purchase_order_reference || ('#' + m.purchase_order_id) }}</RouterLink>
                                </td>
                                <td class="px-4 py-3" style="color:var(--muted)">{{ m.created_by || '' }}</td>
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
