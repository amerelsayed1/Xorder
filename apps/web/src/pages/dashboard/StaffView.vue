<script setup>
import { ref, onMounted } from 'vue'
import { RouterLink } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { useAuth } from '@xorder/api-client/auth.js'
import { useCaps } from '../../lib/useCaps.js'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import Icon from '@xorder/ui/Icon.vue'
import TableSkeleton from '@xorder/ui/TableSkeleton.vue'
import { confirm } from '@xorder/ui/confirm.js'
import { alert } from '@xorder/ui/alert.js'
import { pickLocalized } from '@xorder/ui/localize.js'

const { t, locale } = useI18n()
const auth = useAuth()
// Per-action gates so the UI offers only what the API would accept.
const { canCreate, canUpdate, canDelete } = useCaps('staff')
const rows = ref([])
const loading = ref(true)
const busy = ref(null)

async function load() {
    loading.value = true
    try {
        const { data } = await api.get('api/dashboard/staff')
        rows.value = data.data
    } finally {
        loading.value = false
    }
}
onMounted(load)

// Roles are named per restaurant in both languages; fall back to the English
// name when a tenant left the Arabic one blank.
// The owner's access is implicit — no Role governs them — so the column says
// what is true rather than borrowing a role name that would not apply.
const roleLabel = (u) => u.is_owner
    ? t('team.owner_full_access')
    : (pickLocalized({ name_en: u.role_name, name_ar: u.role_name_ar }, 'name', locale.value) || u.role_name || '—')

async function resetPassword(u) {
    const ok = await confirm({
        title: t('team.reset_password_title', { name: u.name }),
        message: t('team.reset_password_message'),
        confirmText: t('team.reset_password_confirm'),
        cancelText: t('common.cancel'),
    })
    if (!ok) return
    busy.value = u.id
    try {
        await ensureCsrf()
        const { data } = await api.post(`api/dashboard/staff/${u.id}/reset-password`)
        await alert(t('team.new_password', { password: data.generated_password }))
    } catch (err) {
        alert(err.response?.data?.message || t('team.action_failed'))
    } finally {
        busy.value = null
    }
}

async function remove(u) {
    const ok = await confirm({
        title: t('team.delete_title', { name: u.name }),
        message: t('team.delete_message'),
        confirmText: t('team.delete_confirm'),
        cancelText: t('common.cancel'),
        danger: true,
    })
    if (!ok) return
    busy.value = u.id
    try {
        await ensureCsrf()
        await api.delete(`api/dashboard/staff/${u.id}`)
        await load()
    } catch (err) {
        alert(err.response?.data?.message || t('team.action_failed'))
    } finally {
        busy.value = null
    }
}
</script>

<template>
    <div class="space-y-5">
        <div class="flex items-start justify-between gap-3">
            <div>
                <h1 class="page-title">{{ t('team.staff_title') }}</h1>
                <p class="page-sub">{{ t('team.staff_sub') }}</p>
            </div>
            <div class="flex items-center gap-2">
                <RouterLink :to="{ name: 'dashboard.roles' }" class="btn btn-ghost"><i class="pi pi-shield" style="font-size:15px" aria-hidden="true"></i>{{ t('team.manage_roles') }}</RouterLink>
                <RouterLink v-if="canCreate" :to="{ name: 'dashboard.staff.create' }" class="btn btn-accent"><Icon name="plus" :size="16" />{{ t('team.add_staff') }}</RouterLink>
            </div>
        </div>

        <div class="card overflow-x-auto">
            <table class="w-full text-sm" style="min-width:640px">
                <thead>
                    <tr class="text-start" style="color:var(--muted)">
                        <th class="px-5 py-3 font-medium" style="font-size:11px;text-transform:uppercase">{{ t('team.name') }}</th>
                        <th class="px-3 py-3 font-medium" style="font-size:11px;text-transform:uppercase">{{ t('team.username') }}</th>
                        <th class="px-3 py-3 font-medium" style="font-size:11px;text-transform:uppercase">{{ t('team.email') }}</th>
                        <th class="px-3 py-3 font-medium" style="font-size:11px;text-transform:uppercase">{{ t('team.role') }}</th>
                        <th class="px-3 py-3 font-medium" style="font-size:11px;text-transform:uppercase">{{ t('common.status') }}</th>
                        <th class="px-5 py-3 font-medium text-end" style="font-size:11px;text-transform:uppercase">{{ t('common.actions') }}</th>
                    </tr>
                </thead>
                <tbody>
                    <TableSkeleton v-if="loading" :cols="6" />
                    <tr v-else-if="!rows.length"><td colspan="6" class="px-5 py-8 text-center" style="color:var(--muted)">{{ t('team.staff_empty') }}</td></tr>
                    <tr v-for="u in loading ? [] : rows" :key="u.id" class="border-t" :style="{ borderColor: 'var(--line)' }">
                        <td class="px-5 py-3 font-medium" style="color:var(--ink)">{{ u.name }}</td>
                        <td class="px-3 py-3 mono" style="color:var(--body)" dir="ltr">{{ u.username }}</td>
                        <td class="px-3 py-3" style="color:var(--body)" dir="ltr">{{ u.email || '—' }}</td>
                        <td class="px-3 py-3">
                            <span class="badge" :class="u.is_owner ? 'badge-amber' : 'badge-indigo'">{{ roleLabel(u) }}</span>
                        </td>
                        <td class="px-3 py-3">
                            <span class="badge" :class="u.status === 'ACTIVE' ? 'badge-green' : 'badge-gray'">{{ t(`status.${u.status}`) }}</span>
                        </td>
                        <td class="px-5 py-3 text-end whitespace-nowrap">
                            <!-- The owner is listed, never actioned: the API 404s on
                                 every write against that account, so offering the
                                 controls here would only produce dead buttons. -->
                            <span v-if="u.is_owner" class="text-xs" style="color:var(--muted)">{{ t('team.owner_not_editable') }}</span>
                            <div v-else class="inline-flex items-center gap-2">
                                <RouterLink v-if="canUpdate" :to="{ name: 'dashboard.staff.edit', params: { id: u.id } }" class="btn btn-ghost" style="padding:5px 11px;font-size:12px">{{ t('common.edit') }}</RouterLink>
                                <!-- Resetting a password edits the account rather than creating one. -->
                                <button v-if="canUpdate" @click="resetPassword(u)" :disabled="busy === u.id" class="btn btn-ghost" style="padding:5px 11px;font-size:12px">{{ t('team.reset_password') }}</button>
                                <button v-if="canDelete" @click="remove(u)" :disabled="busy === u.id" class="icon-btn icon-btn-danger" :title="t('team.delete_staff')" :aria-label="t('team.delete_staff')"><Icon name="trash" :size="16" /></button>
                            </div>
                        </td>
                    </tr>
                </tbody>
            </table>
        </div>
    </div>
</template>
