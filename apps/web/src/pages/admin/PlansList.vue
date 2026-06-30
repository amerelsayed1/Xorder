<script setup>
import { ref, onMounted } from 'vue'
import { useRouter, RouterLink } from 'vue-router'
import { useI18n } from 'vue-i18n'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import Icon from '@xorder/ui/Icon.vue'
import { confirm } from '@xorder/ui/confirm.js'

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
                    <tr class="text-left" style="color:var(--muted)">
                        <th class="px-5 py-3 font-medium" style="font-size:11px;letter-spacing:.06em;text-transform:uppercase">{{ t('plan.name') }}</th>
                        <th class="px-3 py-3 font-medium" style="font-size:11px;text-transform:uppercase">{{ t('plan.price') }}</th>
                        <th class="px-3 py-3 font-medium" style="font-size:11px;text-transform:uppercase">{{ t('plan.features') }}</th>
                        <th class="px-3 py-3 font-medium" style="font-size:11px;text-transform:uppercase">{{ t('common.status') }}</th>
                        <th class="px-5 py-3 font-medium text-end" style="font-size:11px;text-transform:uppercase">{{ t('common.actions') }}</th>
                    </tr>
                </thead>
                <tbody>
                    <tr v-if="loading"><td colspan="5" class="px-5 py-8 text-center" style="color:var(--muted)">{{ t('common.loading') }}</td></tr>
                    <tr v-else-if="!rows.length"><td colspan="5" class="px-5 py-8 text-center" style="color:var(--muted)">{{ t('plan.none') }}</td></tr>
                    <tr v-for="p in rows" :key="p.id" class="border-t cursor-pointer hover:bg-black/[.015]"
                        :style="{ borderColor: 'var(--line)', opacity: p.is_active ? 1 : 0.6 }"
                        @click="router.push({ name: 'admin.plans.edit', params: { id: p.id } })">
                        <td class="px-5 py-3 font-medium" style="color:var(--ink)">{{ p.name }}</td>
                        <td class="px-3 py-3" style="color:var(--body)">{{ price(p) }}</td>
                        <td class="px-3 py-3" style="color:var(--body)">{{ p.features.length }}</td>
                        <td class="px-3 py-3">
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
