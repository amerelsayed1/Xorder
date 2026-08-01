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
        <div class="flex items-start justify-between gap-3">
            <div>
                <h1 class="page-title">{{ t('nav.plans') }}</h1>
                <p class="page-sub">{{ t('plan.subtitle') }}</p>
            </div>
            <RouterLink :to="{ name: 'admin.plans.create' }" class="btn btn-accent"><Icon name="plus" :size="16" />{{ t('plan.create') }}</RouterLink>
        </div>

        <div class="card overflow-x-auto">
            <table class="w-full text-sm" style="min-width:640px">
                <thead>
                    <tr style="color:var(--muted)">
                        <th class="px-5 py-3 font-medium text-start" style="font-size:11px;letter-spacing:.06em;text-transform:uppercase">#</th>
                        <th class="px-5 py-3 font-medium text-start" style="font-size:11px;letter-spacing:.06em;text-transform:uppercase">{{ t('plan.name') }}</th>
                        <th class="px-3 py-3 font-medium text-center" style="font-size:11px;text-transform:uppercase">{{ t('plan.price') }}</th>
                        <th class="px-3 py-3 font-medium text-center" style="font-size:11px;text-transform:uppercase">{{ t('plan.branches') }}</th>
                        <th class="px-3 py-3 font-medium text-center" style="font-size:11px;text-transform:uppercase">{{ t('plan.entitlements') }}</th>
                        <th class="px-3 py-3 font-medium text-center" style="font-size:11px;text-transform:uppercase">{{ t('common.status') }}</th>
                        <th class="px-5 py-3 font-medium text-end" style="font-size:11px;text-transform:uppercase">{{ t('common.actions') }}</th>
                    </tr>
                </thead>
                <tbody>
                    <TableSkeleton v-if="loading" :cols="7" />
                    <tr v-else-if="!rows.length"><td colspan="7" class="px-5 py-8 text-center" style="color:var(--muted)">{{ t('plan.none') }}</td></tr>
                    <tr v-for="(p, idx) in rows" :key="p.id" class="border-t cursor-pointer hover:bg-black/[.015]"
                        :style="{ borderColor: 'var(--line)', opacity: p.is_active ? 1 : 0.6 }"
                        @click="router.push({ name: 'admin.plans.edit', params: { id: p.id } })">
                        <td class="px-5 py-3 text-start" style="color:var(--muted)">{{ idx + 1 }}</td>
                        <td class="px-5 py-3 font-medium text-start" style="color:var(--ink)">{{ p.name }}</td>
                        <td class="px-3 py-3 text-center" style="color:var(--body)">{{ price(p) }}</td>
                        <td class="px-3 py-3 text-center" style="color:var(--body)"><span class="badge badge-gray">{{ branchLimit(p) }}</span></td>
                        <td class="px-3 py-3">
                            <div class="flex flex-wrap justify-center gap-1" style="max-width:340px;margin-inline:auto">
                                <span v-for="k in planCaps(p)" :key="k" class="plan-cap">{{ t('feature.' + k) }}</span>
                                <span v-if="!planCaps(p).length" style="color:var(--muted)">—</span>
                            </div>
                        </td>
                        <td class="px-3 py-3 text-center">
                            <span class="badge" :class="p.is_active ? 'badge-green' : 'badge-gray'">{{ p.is_active ? t('plan.active') : t('plan.inactive') }}</span>
                        </td>
                        <td class="px-5 py-3 text-end whitespace-nowrap" @click.stop>
                            <div class="inline-flex items-center gap-2">
                                <RouterLink :to="{ name: 'admin.plans.edit', params: { id: p.id } }" class="btn btn-ghost" style="padding:5px 11px;font-size:12px">{{ t('common.edit') }}</RouterLink>
                                <button @click="removePlan(p)" :disabled="deleting === p.id" class="icon-btn icon-btn-danger" :title="t('common.delete')" :aria-label="t('common.delete')">
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
.plan-cap {
    font-size: 11.5px;
    font-weight: 600;
    padding: 2px 8px;
    border-radius: 999px;
    background: var(--accent-soft, color-mix(in srgb, var(--accent) 10%, transparent));
    color: var(--accent-dark, var(--accent));
    white-space: nowrap;
}
</style>
