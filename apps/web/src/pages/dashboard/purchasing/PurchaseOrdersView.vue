<script setup>
import { ref, reactive, computed, onMounted, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRouter } from 'vue-router'
import api from '@xorder/api-client/api.js'
import { useAuth } from '@xorder/api-client/auth.js'
import { withMinDuration } from '../../../lib/minLoading.js'
import { pickLocalized } from '@xorder/ui/localize.js'
import TableSkeleton from '@xorder/ui/TableSkeleton.vue'
import ErrorState from '@xorder/ui/ErrorState.vue'
import Icon from '@xorder/ui/Icon.vue'
import { statusBadge, STATUSES, fmtDate, money } from './format.js'

// CB-09 slice b. Purchase orders, per branch, newest first, filterable by
// branch, status and supplier. Totals come from the server: the snapshot
// taken at send, or for a draft the live figure with the same arithmetic.
const { t, locale } = useI18n()
const router = useRouter()
const auth = useAuth()
const canWrite = computed(() => auth.can('purchase.manage') && !auth.isReadOnly)

const rows = ref([])
const lookups = ref(null)
const filters = reactive({ branch_id: '', status: '', supplier_id: '' })
const page = ref(1)
const lastPage = ref(1)
const total = ref(0)
const loading = ref(true)
const failed = ref(false)

async function load() {
    loading.value = true
    failed.value = false
    try {
        const params = { page: page.value }
        for (const [k, v] of Object.entries(filters)) if (v !== '') params[k] = v
        const [orders, lk] = await withMinDuration(Promise.all([
            api.get('api/dashboard/purchase-orders', { params }),
            lookups.value ? Promise.resolve(null) : api.get('api/dashboard/purchasing/lookups'),
        ]))
        rows.value = orders.data.data
        lastPage.value = orders.data.meta?.last_page || 1
        total.value = orders.data.meta?.total ?? rows.value.length
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

const filtered = computed(() => Object.values(filters).some((v) => v !== ''))
const nameOf = (s) => (s ? (pickLocalized(s, 'name', locale.value) || s.name_en || s.name_ar || `#${s.id}`) : '')
const branches = computed(() => lookups.value?.branches || [])
const suppliers = computed(() => lookups.value?.suppliers || [])
const refOf = (o) => o.reference || t('purchasing.draft_ref', { id: o.id })

function open(o) {
    router.push({ name: 'dashboard.purchasing.order', params: { id: o.id } })
}
</script>

<template>
    <div class="space-y-5">
        <div class="flex flex-wrap items-start justify-between gap-3">
            <div>
                <h1 class="page-title">{{ t('purchasing.orders_title') }}</h1>
                <p class="page-sub">{{ t('purchasing.orders_sub') }}</p>
            </div>
            <RouterLink v-if="canWrite" :to="{ name: 'dashboard.purchasing.orders.create' }" class="btn btn-accent">
                <Icon name="plus" :size="16" />{{ t('purchasing.new_order') }}
            </RouterLink>
        </div>

        <div v-if="lookups" class="flex flex-wrap items-center gap-3">
            <select v-if="branches.length > 1" v-model="filters.branch_id" class="input" style="max-width: 220px" :aria-label="t('purchasing.branch')">
                <option value="">{{ t('purchasing.all_branches') }}</option>
                <option v-for="b in branches" :key="b.id" :value="b.id">{{ nameOf(b) }}</option>
            </select>
            <select v-model="filters.status" class="input" style="max-width: 200px" :aria-label="t('common.status')">
                <option value="">{{ t('purchasing.all_statuses') }}</option>
                <option v-for="s in STATUSES" :key="s" :value="s">{{ t('purchasing.status.' + s) }}</option>
            </select>
            <select v-model="filters.supplier_id" class="input" style="max-width: 240px" :aria-label="t('purchasing.supplier')">
                <option value="">{{ t('purchasing.all_suppliers') }}</option>
                <option v-for="s in suppliers" :key="s.id" :value="s.id">{{ nameOf(s) }}{{ s.is_active ? '' : ' ' + t('purchasing.retired_suffix') }}</option>
            </select>
        </div>

        <ErrorState v-if="failed" :message="t('common.error')" @retry="load" />

        <div v-else class="card overflow-hidden">
            <div v-if="!loading && !rows.length" class="p-8 text-center space-y-1">
                <template v-if="filtered">
                    <div class="text-sm" style="color:var(--muted)">{{ t('purchasing.none_orders_match') }}</div>
                </template>
                <template v-else>
                    <div class="font-medium" style="color:var(--ink)">{{ t('purchasing.none_orders') }}</div>
                    <div class="text-sm" style="color:var(--muted)">{{ t('purchasing.none_orders_hint') }}</div>
                </template>
            </div>
            <div v-else class="overflow-x-auto">
                <table class="w-full text-sm">
                    <thead>
                        <tr style="color:var(--muted)">
                            <th class="px-5 py-3 text-start font-medium">{{ t('purchasing.reference') }}</th>
                            <th class="px-5 py-3 text-start font-medium">{{ t('purchasing.supplier') }}</th>
                            <th v-if="branches.length > 1" class="px-5 py-3 text-start font-medium">{{ t('purchasing.branch') }}</th>
                            <th class="px-5 py-3 text-start font-medium">{{ t('common.status') }}</th>
                            <th class="px-5 py-3 text-start font-medium">{{ t('purchasing.ordered_on') }}</th>
                            <th class="px-5 py-3 text-end font-medium">{{ t('purchasing.total') }}</th>
                        </tr>
                    </thead>
                    <tbody>
                        <TableSkeleton v-if="loading" :cols="branches.length > 1 ? 6 : 5" />
                        <template v-else>
                            <tr v-for="o in rows" :key="o.id" class="border-t cursor-pointer hover:bg-black/[.02]" style="border-color:var(--line)" @click="open(o)">
                                <td class="px-5 py-3"><span class="mono" dir="ltr" style="color:var(--ink)">{{ refOf(o) }}</span></td>
                                <td class="px-5 py-3" style="color:var(--ink)">{{ o.supplier_name }}</td>
                                <td v-if="branches.length > 1" class="px-5 py-3" style="color:var(--body)">{{ nameOf(o.branch) }}</td>
                                <td class="px-5 py-3">
                                    <span class="badge" :class="statusBadge(o.status)">{{ t('purchasing.status.' + o.status) }}</span>
                                    <span v-if="o.closed_short" class="text-xs ms-1" style="color:var(--muted)">{{ t('purchasing.closed_short_tag') }}</span>
                                </td>
                                <td class="px-5 py-3 whitespace-nowrap" style="color:var(--body)">{{ fmtDate(o.ordered_at, locale) || '—' }}</td>
                                <td class="px-5 py-3 text-end"><span class="mono" dir="ltr">{{ money(o.totals.total_minor, o.exponent, o.currency, locale) }}</span></td>
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
