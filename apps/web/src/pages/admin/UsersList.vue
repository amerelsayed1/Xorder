<script setup>
import { ref, onMounted } from 'vue'
import { RouterLink } from 'vue-router'
import { useI18n } from 'vue-i18n'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import Icon from '@xorder/ui/Icon.vue'
import TableSkeleton from '@xorder/ui/TableSkeleton.vue'
import { confirm } from '@xorder/ui/confirm.js'
import { alert } from '@xorder/ui/alert.js'

const { t } = useI18n()
const rows = ref([])
const loading = ref(true)
const busy = ref(null)

async function load() {
    loading.value = true
    try {
        const { data } = await api.get('api/admin/users')
        rows.value = data.data
    } finally {
        loading.value = false
    }
}
onMounted(load)

// Role → chip colour. Purely cosmetic; the label comes from i18n.
const roleBadge = (role) => ({
    SUPER_ADMIN: 'badge-indigo', ADMIN: 'badge-indigo', MODERATOR: 'badge-amber',
    SALES: 'badge-green', SUPPORT: 'badge-gray',
}[role] || 'badge-gray')
const roleLabel = (role) => t(`roles.${role.toLowerCase()}`)
const isSuperAdmin = (u) => u.role === 'SUPER_ADMIN'

async function resetPassword(u) {
    const ok = await confirm({
        title: t('users.reset_password_title', { name: u.name }),
        message: t('users.reset_password_message'),
        confirmText: t('users.reset_password_confirm'),
        cancelText: t('common.cancel'),
    })
    if (!ok) return
    busy.value = u.id
    try {
        await ensureCsrf()
        const { data } = await api.post(`api/admin/users/${u.id}/reset-password`)
        await alert(t('users.new_password', { password: data.generated_password }))
    } catch (err) {
        alert(t('users.action_failed'))
    } finally {
        busy.value = null
    }
}

async function remove(u) {
    const ok = await confirm({
        title: t('users.delete_title', { name: u.name }),
        message: t('users.delete_message'),
        confirmText: t('users.delete_confirm'),
        cancelText: t('common.cancel'),
        danger: true,
    })
    if (!ok) return
    busy.value = u.id
    try {
        await ensureCsrf()
        await api.delete(`api/admin/users/${u.id}`)
        await load()
    } catch (err) {
        alert(t('users.action_failed'))
    } finally {
        busy.value = null
    }
}
</script>

<template>
    <div class="space-y-5">
        <div class="flex items-start justify-between gap-3">
            <div>
                <h1 class="page-title">{{ t('nav.users') }}</h1>
                <p class="page-sub">{{ t('users.subtitle') }}</p>
            </div>
            <RouterLink :to="{ name: 'admin.users.create' }" class="btn btn-accent"><Icon name="plus" :size="16" />{{ t('users.add_user') }}</RouterLink>
        </div>

        <div class="card overflow-x-auto">
            <table class="w-full text-sm" style="min-width:640px">
                <thead>
                    <tr class="text-start" style="color:var(--muted)">
                        <th class="px-5 py-3 font-medium" style="font-size:11px;text-transform:uppercase">{{ t('users.name') }}</th>
                        <th class="px-3 py-3 font-medium" style="font-size:11px;text-transform:uppercase">{{ t('users.username') }}</th>
                        <th class="px-3 py-3 font-medium" style="font-size:11px;text-transform:uppercase">{{ t('users.email') }}</th>
                        <th class="px-3 py-3 font-medium" style="font-size:11px;text-transform:uppercase">{{ t('users.role') }}</th>
                        <th class="px-3 py-3 font-medium" style="font-size:11px;text-transform:uppercase">{{ t('common.status') }}</th>
                        <th class="px-5 py-3 font-medium text-end" style="font-size:11px;text-transform:uppercase">{{ t('common.actions') }}</th>
                    </tr>
                </thead>
                <tbody>
                    <TableSkeleton v-if="loading" :cols="6" />
                    <tr v-else-if="!rows.length"><td colspan="6" class="px-5 py-8 text-center" style="color:var(--muted)">{{ t('users.empty') }}</td></tr>
                    <tr v-for="u in loading ? [] : rows" :key="u.id" class="border-t" :style="{ borderColor: 'var(--line)' }">
                        <td class="px-5 py-3 font-medium" style="color:var(--ink)">{{ u.name }}</td>
                        <td class="px-3 py-3 mono" style="color:var(--body)">{{ u.username }}</td>
                        <td class="px-3 py-3" style="color:var(--body)">{{ u.email }}</td>
                        <td class="px-3 py-3"><span class="badge" :class="roleBadge(u.role)">{{ roleLabel(u.role) }}</span></td>
                        <td class="px-3 py-3">
                            <span class="badge" :class="u.status === 'ACTIVE' ? 'badge-green' : 'badge-gray'">{{ t(`status.${u.status}`) }}</span>
                        </td>
                        <td class="px-5 py-3 text-end whitespace-nowrap">
                            <!-- Super Admin owner accounts are managed out-of-band, so no controls. -->
                            <div v-if="!isSuperAdmin(u)" class="inline-flex items-center gap-2">
                                <RouterLink :to="{ name: 'admin.users.edit', params: { id: u.id } }" class="btn btn-ghost" style="padding:5px 11px;font-size:12px">{{ t('common.edit') }}</RouterLink>
                                <button @click="resetPassword(u)" :disabled="busy === u.id" class="btn btn-ghost" style="padding:5px 11px;font-size:12px">{{ t('users.reset_password') }}</button>
                                <button @click="remove(u)" :disabled="busy === u.id" class="icon-btn icon-btn-danger" :title="t('users.delete_user')" :aria-label="t('users.delete_user')"><Icon name="trash" :size="16" /></button>
                            </div>
                            <span v-else class="text-xs" style="color:var(--muted)">{{ t('users.owner_account') }}</span>
                        </td>
                    </tr>
                </tbody>
            </table>
        </div>
    </div>
</template>
