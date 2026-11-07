<script setup>
import { ref, onMounted } from 'vue'
import { useRouter, RouterLink } from 'vue-router'
import { useI18n } from 'vue-i18n'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import Icon from '@xorder/ui/Icon.vue'
import TableSkeleton from '@xorder/ui/TableSkeleton.vue'
import { confirm } from '@xorder/ui/confirm.js'
import { alert } from '@xorder/ui/alert.js'

const router = useRouter()
const { t } = useI18n()
const rows = ref([])
const loading = ref(true)
const deleting = ref(null)

async function load() {
    loading.value = true
    try {
        const { data } = await api.get('api/admin/plans')
        rows.value = data.data
    } finally {
        loading.value = false
    }
}
onMounted(load)

const price = (p) => p.price == null ? t('plan.free') : `${p.price.toLocaleString()} ${p.currency_symbol}`

// Effective branch allowance: without the multi_branch feature a plan is capped
// at its single primary branch; with it, max_branches bounds the count (null =
// unlimited).
const branchLimit = (p) => {
    if (!(p.feature_keys || []).includes('multi_branch')) return '1'
    return p.max_branches == null ? '∞' : String(p.max_branches)
}

// Capability chips: collapse pickup+delivery into one, and surface the customer
// directory (implied by having any ordering — it's captured from orders).
const planCaps = (p) => {
    const fk = p.feature_keys || []
    const caps = []
    const seen = new Set()
    const add = (k) => { if (!seen.has(k)) { seen.add(k); caps.push(k) } }
    for (const k of fk) {
        if (k === 'customer_tracking') continue // derived from ordering below
        if (k === 'pickup' || k === 'delivery') add('pickup_delivery')
        else add(k)
    }
    if (fk.includes('whatsapp_ordering') || fk.includes('system_ordering')) add('customer_tracking')
    return caps
}

async function removePlan(p) {
    const ok = await confirm({
        title: t('plan.delete_title'),
        message: t('plan.delete_message'),
        confirmText: t('common.delete'),
        cancelText: t('common.cancel'),
        danger: true,
    })
    if (!ok) return
    deleting.value = p.id
    try {
        await ensureCsrf()
        await api.delete(`api/admin/plans/${p.id}`)
        await load()
    } catch (err) {
        alert(t('common.error'))
    } finally {
        deleting.value = null
    }
}
</script>

<template>
    <div class="space-y-5">
        <div class="flex flex-wrap items-start justify-between gap-3">
            <div>
                <h1 class="page-title">{{ t('nav.plans') }}</h1>
                <p class="page-sub" style="color:var(--body)">{{ t('plan.subtitle') }}</p>
            </div>
            <RouterLink :to="{ name: 'admin.plans.create' }" class="btn btn-accent cta"><Icon name="plus" :size="16" />{{ t('plan.create') }}</RouterLink>
        </div>

        <div class="card tbl-card">
            <table class="w-full">
                <thead>
                    <tr>
                        <th class="th text-start">#</th>
                        <th class="th text-start">{{ t('plan.name') }}</th>
                        <th class="th text-end">{{ t('plan.price') }}</th>
                        <th class="th text-center">{{ t('plan.branches') }}</th>
                        <th class="th text-start">{{ t('plan.entitlements') }}</th>
                        <th class="th text-start">{{ t('common.status') }}</th>
                        <th class="th text-end">{{ t('common.actions') }}</th>
                    </tr>
                </thead>
                <tbody>
                    <TableSkeleton v-if="loading" :cols="7" />
                    <tr v-else-if="!rows.length">
                        <td colspan="7">
                            <div class="empty">
                                <span class="empty-ico"><Icon name="star" :size="22" /></span>
                                <p>{{ t('plan.none') }}</p>
                                <RouterLink :to="{ name: 'admin.plans.create' }" class="btn btn-accent btn-sm"><Icon name="plus" :size="14" />{{ t('plan.create') }}</RouterLink>
                            </div>
                        </td>
                    </tr>
                    <tr v-for="(p, idx) in rows" :key="p.id" class="row"
                        :class="{ 'is-off': !p.is_active }"
                        @click="router.push({ name: 'admin.plans.edit', params: { id: p.id } })">
                        <td class="td num" style="color:var(--body)">{{ idx + 1 }}</td>
                        <td class="td">
                            <RouterLink :to="{ name: 'admin.plans.edit', params: { id: p.id } }" class="plan-name" @click.stop>{{ p.name }}</RouterLink>
                        </td>
                        <td class="td text-end num" style="color:var(--ink);font-weight:600;white-space:nowrap">{{ price(p) }}</td>
                        <td class="td text-center"><span class="badge badge-gray">{{ branchLimit(p) }}</span></td>
                        <td class="td">
                            <div class="flex flex-wrap gap-1.5" style="max-width:360px">
                                <span v-for="k in planCaps(p)" :key="k" class="plan-cap">{{ t('feature.' + k) }}</span>
                                <span v-if="!planCaps(p).length" style="color:var(--body)">—</span>
                            </div>
                        </td>
                        <td class="td">
                            <span class="badge" :class="p.is_active ? 'badge-green' : 'badge-gray'"><span class="dot"></span>{{ p.is_active ? t('plan.active') : t('plan.inactive') }}</span>
                        </td>
                        <td class="td text-end whitespace-nowrap" @click.stop>
                            <div class="inline-flex items-center gap-2">
                                <RouterLink :to="{ name: 'admin.plans.edit', params: { id: p.id } }" class="btn btn-ghost btn-sm act">{{ t('common.edit') }}</RouterLink>
                                <button type="button" @click="removePlan(p)" :disabled="deleting === p.id" class="icon-btn icon-btn-danger act-icon" :title="t('common.delete')" :aria-label="t('common.delete')">
                                    <Icon name="trash" :size="16" />
                                </button>
                            </div>
                        </td>
                    </tr>
                </tbody>
            </table>
        </div>
    </div>
</template>

<style scoped>
.badge.badge-gray { color: var(--body); }
.cta { min-height: 44px; }

/* Wide table scrolls inside its card instead of breaking the page. */
.tbl-card { overflow-x: auto; }
.tbl-card table { min-width: 760px; font-size: 14.5px; }
.th { padding: 11px 16px; font-size: 12.5px; font-weight: 600; color: var(--body); background: var(--page); border-bottom: 1px solid var(--line); }
.th:first-child, .td:first-child { padding-inline-start: 20px; }
.th:last-child, .td:last-child { padding-inline-end: 20px; }
.td { padding: 12px 16px; min-height: 56px; vertical-align: middle; }
.row { border-top: 1px solid var(--line); cursor: pointer; transition: background .15s; }
.row:hover { background: var(--page); }
.row:hover .plan-name { color: var(--p-primary-700); }
.is-off .plan-name { color: var(--body); }
.num { font-variant-numeric: tabular-nums; }
.plan-name { font-size: 15px; font-weight: 600; color: var(--ink); }
.plan-cap {
    font-size: 12px;
    font-weight: 600;
    padding: 2px 9px;
    border-radius: 999px;
    background: var(--accent-soft);
    color: var(--p-primary-800);
    white-space: nowrap;
}
.act { min-height: 36px; }
.act-icon { width: 36px; height: 36px; color: var(--red); }
.empty { display: flex; flex-direction: column; align-items: center; gap: 12px; padding: 44px 16px; text-align: center; color: var(--body); }
.empty-ico { width: 48px; height: 48px; border-radius: 14px; display: grid; place-items: center; background: var(--accent-soft); color: var(--p-primary-700); }
@media (max-width: 640px) {
    .act { min-height: 44px; }
    .act-icon { width: 44px; height: 44px; }
}
</style>
