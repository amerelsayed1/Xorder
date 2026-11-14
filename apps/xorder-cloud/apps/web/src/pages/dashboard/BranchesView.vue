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
import { useCaps } from '../../lib/useCaps.js'

const { t, locale } = useI18n()
const router = useRouter()
const auth = useAuth()
// Per-action gates so the UI offers only what the API would accept.
const { canCreate, canUpdate, canDelete } = useCaps('branches')
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
        <div class="flex flex-wrap items-start justify-between gap-3">
            <div class="min-w-0">
                <h1 class="page-title">{{ t('nav.branches') }}</h1>
                <p class="page-sub" style="color:var(--body)">{{ t('branch.subtitle', { count: rows.length }) }}</p>
            </div>
            <button v-if="canCreate && auth.hasFeature('multi_branch')" @click="openCreate" class="btn btn-accent act-btn"><Icon name="plus" :size="16" />{{ t('common.create') }}</button>
        </div>

        <div class="card overflow-hidden">
            <ListSkeleton v-if="loading" />
            <div v-else-if="!rows.length" class="empty">
                <span class="empty-ico" aria-hidden="true"><Icon name="building" :size="22" /></span>
                <p class="empty-text">{{ t('branch.none') }}</p>
                <button v-if="canCreate && auth.hasFeature('multi_branch')" class="btn btn-accent act-btn" @click="openCreate"><Icon name="plus" :size="16" />{{ t('common.create') }}</button>
            </div>
            <ul v-else>
                <li v-for="b in rows" :key="b.id" class="row">
                    <div class="row-main">
                        <div class="row-ico" aria-hidden="true"><Icon name="building" :size="18" /></div>
                        <div class="flex-1 min-w-0">
                            <div class="row-name truncate">{{ branchName(b) }}</div>
                            <div class="row-sub truncate">{{ b.address || '—' }}</div>
                        </div>
                    </div>
                    <div class="row-side">
                        <StatusBadge :value="b.is_open" :label="b.is_open ? t('branch.open') : t('branch.closed')" />
                        <button v-if="canUpdate" type="button" class="switch" :class="{ on: b.is_open }" role="switch"
                            :aria-checked="b.is_open" :aria-label="t('branch.is_open')" :title="t('branch.is_open')" @click="toggleOpen(b)"></button>
                        <button v-if="canUpdate" @click="openEdit(b)" class="icon-btn" :title="t('common.edit')" :aria-label="t('common.edit')"><Icon name="edit" :size="17" /></button>
                        <button v-if="canDelete" @click="remove(b)" class="icon-btn icon-btn-danger" :title="t('common.delete')" :aria-label="t('common.delete')"><Icon name="trash" :size="17" /></button>
                    </div>
                </li>
            </ul>
        </div>
    </div>
</template>

<style scoped>
/* Colours come from the shared theme variables only. */
.row { display: flex; flex-wrap: wrap; align-items: center; gap: 8px 12px; padding: 10px 20px; min-height: 64px;
    border-top: 1px solid var(--line); transition: background .15s; }
.row:first-child { border-top: 0; }
.row:hover { background: var(--page); }
.row-main { display: flex; align-items: center; gap: 12px; flex: 1 1 220px; min-width: 0; }
.row-side { display: flex; align-items: center; gap: 8px; margin-inline-start: auto; }
.row-ico { width: 44px; height: 44px; border-radius: 10px; display: grid; place-items: center; flex: none;
    background: var(--accent-soft); color: var(--p-primary-700); }
.row-name { font-size: 15.5px; font-weight: 600; color: var(--ink); }
.row-sub { font-size: 13.5px; color: var(--body); margin-top: 1px; }

.empty { display: flex; flex-direction: column; align-items: center; gap: 8px; padding: 40px 20px; text-align: center; }
.empty-ico { width: 48px; height: 48px; border-radius: 14px; display: grid; place-items: center;
    background: var(--accent-soft); color: var(--p-primary-700); }
.empty-text { font-size: 15.5px; font-weight: 600; color: var(--ink); }
.empty .btn { margin-top: 6px; }

@media (max-width: 640px) {
    .row { padding-inline: 14px; }
    .row-side { width: 100%; justify-content: flex-end; }
    .row-side .icon-btn { width: 44px; height: 44px; }
    .act-btn { min-height: 44px; justify-content: center; }
}
</style>
