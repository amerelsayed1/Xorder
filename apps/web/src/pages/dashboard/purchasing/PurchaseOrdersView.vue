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
import PageTabs from '../../../components/PageTabs.vue'
import { PURCHASING_TABS } from '../tabs.config.js'

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
        <PageTabs :tabs="PURCHASING_TABS" />

        <div class="flex flex-wrap items-start justify-between gap-3">
            <div class="min-w-0">
                <h1 class="page-title">{{ t('purchasing.orders_title') }}</h1>
                <p class="page-sub" style="color:var(--body)">{{ t('purchasing.orders_sub') }}</p>
            </div>
            <RouterLink v-if="canWrite" :to="{ name: 'dashboard.purchasing.orders.create' }" class="btn btn-accent new-btn">
                <Icon name="plus" :size="16" />{{ t('purchasing.new_order') }}
            </RouterLink>
        </div>

        <div v-if="lookups" class="filters">
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
            <div v-if="!loading && !rows.length" class="empty">
                <div class="empty-ico"><i class="pi pi-shopping-cart" aria-hidden="true" /></div>
                <template v-if="filtered">
                    <p class="empty-text">{{ t('purchasing.none_orders_match') }}</p>
                </template>
                <template v-else>
                    <div class="empty-title">{{ t('purchasing.none_orders') }}</div>
                    <p class="empty-text">{{ t('purchasing.none_orders_hint') }}</p>
                    <RouterLink v-if="canWrite" :to="{ name: 'dashboard.purchasing.orders.create' }" class="btn btn-accent mt-4">
                        <Icon name="plus" :size="16" />{{ t('purchasing.new_order') }}
                    </RouterLink>
                </template>
            </div>
            <div v-else class="dtable-wrap">
                <table class="dtable">
                    <thead>
                        <tr>
                            <th>{{ t('purchasing.reference') }}</th>
                            <th>{{ t('purchasing.supplier') }}</th>
                            <th v-if="branches.length > 1">{{ t('purchasing.branch') }}</th>
                            <th>{{ t('common.status') }}</th>
                            <th>{{ t('purchasing.ordered_on') }}</th>
                            <th class="num">{{ t('purchasing.total') }}</th>
                        </tr>
                    </thead>
                    <tbody>
                        <TableSkeleton v-if="loading" :cols="branches.length > 1 ? 6 : 5" />
                        <template v-else>
                            <tr v-for="o in rows" :key="o.id" class="row-link" tabindex="0" @click="open(o)" @keydown.enter.self="open(o)">
                                <td class="primary"><span class="mono" dir="ltr">{{ refOf(o) }}</span></td>
                                <td class="primary">{{ o.supplier_name }}</td>
                                <td v-if="branches.length > 1">{{ nameOf(o.branch) }}</td>
                                <td class="nowrap">
                                    <span class="badge" :class="statusBadge(o.status)">{{ t('purchasing.status.' + o.status) }}</span>
                                    <span v-if="o.closed_short" class="short-tag">{{ t('purchasing.closed_short_tag') }}</span>
                                </td>
                                <td class="nowrap">{{ fmtDate(o.ordered_at, locale) || '—' }}</td>
                                <td class="num strong"><span class="mono">{{ money(o.totals.total_minor, o.exponent, o.currency, locale) }}</span></td>
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
.totals { width: 100%; max-width: 340px; }
.pager { display: flex; align-items: center; justify-content: flex-end; gap: 8px; padding: 12px 16px; border-top: 1px solid var(--line); }
.pager .btn { min-height: 40px; }
.pager-info { font-size: 13.5px; color: var(--body); }
.filters { display: flex; flex-wrap: wrap; align-items: center; gap: 10px; }
.filters .input { margin-top: 0; width: auto; min-height: 44px; }
.empty { padding: 40px 20px; text-align: center; }
.empty-ico { width: 48px; height: 48px; margin: 0 auto 12px; border-radius: 50%; display: grid; place-items: center; background: var(--accent-soft); color: var(--p-primary-700); font-size: 20px; }
.empty-title { font-weight: 600; color: var(--ink); }
.empty-text { margin-top: 4px; font-size: 14.5px; color: var(--body); }
.short-tag { margin-inline-start: 6px; font-size: 13px; color: var(--body); }
.new-btn { min-height: 44px; }
</style>
