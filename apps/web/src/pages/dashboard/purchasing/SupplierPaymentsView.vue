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
import { fmtDay, money } from './format.js'
import PageTabs from '../../../components/PageTabs.vue'
import { PURCHASING_TABS } from '../tabs.config.js'

// CB-09 slice c. Supplier payments, newest first. A voided payment stays on
// the list, flagged; it no longer counts anywhere. What went on invoices and
// what is on account come from the server.
const { t, locale } = useI18n()
const route = useRoute()
const router = useRouter()
const auth = useAuth()
const canWrite = computed(() => auth.can('purchase.manage') && !auth.isReadOnly)

const rows = ref([])
const lookups = ref(null)
const filters = reactive({
    branch_id: '',
    supplier_id: route.query.supplier_id ? Number(route.query.supplier_id) : '',
    state: '',
})
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
        const [list, lk] = await withMinDuration(Promise.all([
            api.get('api/dashboard/supplier-payments', { params }),
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

const filtered = computed(() => Object.values(filters).some((v) => v !== ''))
const nameOf = (s) => (s ? (pickLocalized(s, 'name', locale.value) || s.name_en || s.name_ar || `#${s.id}`) : '')
const branches = computed(() => lookups.value?.branches || [])
const suppliers = computed(() => lookups.value?.suppliers || [])
const show = (p, minor) => money(minor, p.exponent, p.currency, locale.value)
</script>

<template>
    <div class="space-y-5">
        <PageTabs :tabs="PURCHASING_TABS" />

        <div class="flex flex-wrap items-start justify-between gap-3">
            <div>
                <h1 class="page-title">{{ t('purchasing.payments_title') }}</h1>
                <p class="page-sub">{{ t('purchasing.payments_sub') }}</p>
            </div>
            <RouterLink v-if="canWrite" :to="{ name: 'dashboard.purchasing.payments.create', query: filters.supplier_id ? { supplier_id: filters.supplier_id } : {} }" class="btn btn-accent">
                <Icon name="plus" :size="16" />{{ t('purchasing.new_payment') }}
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
                <option value="">{{ t('purchasing.all_payments') }}</option>
                <option value="live">{{ t('purchasing.payment_states.live') }}</option>
                <option value="voided">{{ t('purchasing.payment_states.voided') }}</option>
            </select>
        </div>

        <ErrorState v-if="failed" :message="t('common.error')" @retry="load" />

        <div v-else class="card overflow-hidden">
            <div v-if="!loading && !rows.length" class="p-8 text-center space-y-1">
                <div v-if="filtered" class="text-sm" style="color:var(--muted)">{{ t('purchasing.none_payments_match') }}</div>
                <template v-else>
                    <div class="font-medium" style="color:var(--ink)">{{ t('purchasing.none_payments') }}</div>
                    <div class="text-sm" style="color:var(--muted)">{{ t('purchasing.none_payments_hint') }}</div>
                </template>
            </div>
            <div v-else class="overflow-x-auto">
                <table class="w-full text-sm">
                    <thead>
                        <tr style="color:var(--muted)">
                            <th class="px-5 py-3 text-start font-medium">{{ t('purchasing.paid_at') }}</th>
                            <th class="px-5 py-3 text-start font-medium">{{ t('purchasing.supplier') }}</th>
                            <th v-if="branches.length > 1" class="px-5 py-3 text-start font-medium">{{ t('purchasing.branch') }}</th>
                            <th class="px-5 py-3 text-start font-medium">{{ t('purchasing.method') }}</th>
                            <th class="px-5 py-3 text-end font-medium">{{ t('purchasing.amount') }}</th>
                            <th class="px-5 py-3 text-end font-medium">{{ t('purchasing.on_account') }}</th>
                        </tr>
                    </thead>
                    <tbody>
                        <TableSkeleton v-if="loading" :cols="branches.length > 1 ? 6 : 5" />
                        <template v-else>
                            <tr v-for="p in rows" :key="p.id" class="border-t cursor-pointer hover:bg-black/[.02]" style="border-color:var(--line)" :style="p.is_voided ? 'opacity:.6' : ''" @click="router.push({ name: 'dashboard.purchasing.payment', params: { id: p.id } })">
                                <td class="px-5 py-3 whitespace-nowrap" style="color:var(--body)">{{ fmtDay(p.paid_at, locale) }}</td>
                                <td class="px-5 py-3" style="color:var(--ink)">
                                    {{ p.supplier_name }}
                                    <span v-if="p.is_voided" class="badge badge-gray ms-1">{{ t('purchasing.voided') }}</span>
                                </td>
                                <td v-if="branches.length > 1" class="px-5 py-3" style="color:var(--body)">{{ nameOf(p.branch) }}</td>
                                <td class="px-5 py-3" style="color:var(--body)">
                                    {{ t('purchasing.methods.' + p.method) }}<span v-if="p.reference"> · <span class="mono" dir="ltr">{{ p.reference }}</span></span>
                                </td>
                                <td class="px-5 py-3 text-end"><span class="mono" :style="p.is_voided ? 'text-decoration:line-through' : ''">{{ show(p, p.amount_minor) }}</span></td>
                                <td class="px-5 py-3 text-end"><span class="mono">{{ p.is_voided ? '—' : show(p, p.on_account_minor) }}</span></td>
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
