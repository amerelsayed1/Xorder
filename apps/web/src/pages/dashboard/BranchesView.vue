<script setup>
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import { withMinDuration } from '../../lib/minLoading.js'
import { pickLocalized } from '@xorder/ui/localize.js'
import ListSkeleton from '@xorder/ui/ListSkeleton.vue'
import StatusBadge from '@xorder/ui/StatusBadge.vue'
import Icon from '@xorder/ui/Icon.vue'
import { confirm } from '@xorder/ui/confirm.js'
import { alert } from '@xorder/ui/alert.js'
import { useAuth } from '@xorder/api-client/auth.js'

const { t, locale } = useI18n()
const router = useRouter()
const auth = useAuth()
const rows = ref([])
const loading = ref(true)

async function load() {
    loading.value = true
    const { data } = await withMinDuration(api.get('api/dashboard/branches'))
    rows.value = data.data
    loading.value = false
}
onMounted(load)

function openCreate() { router.push({ name: 'dashboard.branches.create' }) }
function openEdit(b) { router.push({ name: 'dashboard.branches.edit', params: { id: b.id } }) }

async function toggleOpen(b) {
    await ensureCsrf()
    await api.patch(`api/dashboard/branches/${b.id}/status`, { is_open: !b.is_open })
    b.is_open = !b.is_open
}
async function remove(b) {
    const ok = await confirm({
        title: t('common.delete'),
        message: t('common.confirm_delete'),
        confirmText: t('common.delete'),
        cancelText: t('common.cancel'),
        danger: true,
    })
    if (!ok) return
    try {
        await ensureCsrf()
        await api.delete(`api/dashboard/branches/${b.id}`)
        await load()
    } catch (err) { alert(t('common.delete_failed')) }
}

const branchName = (b) => pickLocalized(b, 'name', locale.value)
</script>

<template>
    <div class="space-y-5">
        <div class="flex items-start justify-between gap-3">
            <div>
                <h1 class="page-title">{{ t('nav.branches') }}</h1>
                <p class="page-sub">{{ t('branch.subtitle', { count: rows.length }) }}</p>
            </div>
            <button v-if="!auth.isReadOnly && auth.hasFeature('multi_branch')" @click="openCreate" class="btn btn-accent"><Icon name="plus" :size="16" />{{ t('common.create') }}</button>
        </div>

        <div class="card overflow-hidden">
            <ListSkeleton v-if="loading" />
            <div v-else-if="!rows.length" class="p-8 text-center" style="color:var(--muted)">{{ t('branch.none') }}</div>
            <ul v-else>
                <li v-for="b in rows" :key="b.id" class="flex items-center gap-3 px-5 py-3 border-t first:border-t-0" style="border-color:var(--line)">
                    <div class="h-11 w-11 rounded-lg grid place-items-center flex-shrink-0" style="background:var(--accent-soft);color:var(--accent)"><Icon name="building" :size="18" /></div>
                    <div class="flex-1 min-w-0">
                        <div class="font-medium" style="color:var(--ink)">{{ branchName(b) }}</div>
                        <div class="text-xs truncate" style="color:var(--muted)">{{ b.address || '—' }}</div>
                    </div>
                    <StatusBadge :value="b.is_open" :label="b.is_open ? t('branch.open') : t('branch.closed')" />
                    <button v-if="!auth.isReadOnly" class="switch" :class="{ on: b.is_open }" :title="t('branch.is_open')" @click="toggleOpen(b)"></button>
                    <button v-if="!auth.isReadOnly" @click="openEdit(b)" class="icon-btn" :title="t('common.edit')"><Icon name="edit" :size="17" /></button>
                    <button v-if="!auth.isReadOnly" @click="remove(b)" class="icon-btn icon-btn-danger" :title="t('common.delete')"><Icon name="trash" :size="17" /></button>
                </li>
            </ul>
        </div>
    </div>
</template>
