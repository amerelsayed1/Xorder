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
        await alert({
            title: t('common.success'),
            message: t('users.new_password', { password: data.generated_password }),
            variant: 'success',
        })
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
        <div class="flex flex-wrap items-start justify-between gap-3">
            <div>
                <h1 class="page-title">{{ t('nav.users') }}</h1>
                <p class="page-sub" style="color:var(--body)">{{ t('users.subtitle') }}</p>
            </div>
            <RouterLink :to="{ name: 'admin.users.create' }" class="btn btn-accent cta"><Icon name="plus" :size="16" />{{ t('users.add_user') }}</RouterLink>
        </div>

        <div class="card tbl-card">
            <table class="w-full">
                <thead>
                    <tr>
                        <th class="th text-start">{{ t('users.name') }}</th>
                        <th class="th text-start">{{ t('users.username') }}</th>
                        <th class="th text-start">{{ t('users.email') }}</th>
                        <th class="th text-start">{{ t('users.role') }}</th>
                        <th class="th text-start">{{ t('common.status') }}</th>
                        <th class="th text-end">{{ t('common.actions') }}</th>
                    </tr>
                </thead>
                <tbody>
                    <TableSkeleton v-if="loading" :cols="6" />
                    <tr v-else-if="!rows.length">
                        <td colspan="6">
                            <div class="empty">
                                <span class="empty-ico"><Icon name="building" :size="22" /></span>
                                <p>{{ t('users.empty') }}</p>
                                <RouterLink :to="{ name: 'admin.users.create' }" class="btn btn-accent btn-sm"><Icon name="plus" :size="14" />{{ t('users.add_user') }}</RouterLink>
                            </div>
                        </td>
                    </tr>
                    <tr v-for="u in loading ? [] : rows" :key="u.id" class="row">
                        <td class="td">
                            <div class="flex items-center gap-3 min-w-0">
                                <span class="initial">{{ (u.name || '?').trim().charAt(0).toUpperCase() }}</span>
                                <span class="u-name truncate">{{ u.name }}</span>
                            </div>
                        </td>
                        <td class="td mono" style="color:var(--body);font-size:13.5px">{{ u.username }}</td>
                        <td class="td" style="color:var(--body)">{{ u.email }}</td>
                        <td class="td"><span class="badge" :class="roleBadge(u.role)">{{ roleLabel(u.role) }}</span></td>
                        <td class="td">
                            <span class="badge" :class="u.status === 'ACTIVE' ? 'badge-green' : 'badge-gray'"><span class="dot"></span>{{ t(`status.${u.status}`) }}</span>
                        </td>
                        <td class="td text-end whitespace-nowrap">
                            <!-- Super Admin owner accounts are managed out-of-band, so no controls. -->
                            <div v-if="!isSuperAdmin(u)" class="inline-flex items-center gap-2">
                                <RouterLink :to="{ name: 'admin.users.edit', params: { id: u.id } }" class="btn btn-ghost btn-sm act">{{ t('common.edit') }}</RouterLink>
                                <button type="button" @click="resetPassword(u)" :disabled="busy === u.id" class="btn btn-ghost btn-sm act">{{ t('users.reset_password') }}</button>
                                <button type="button" @click="remove(u)" :disabled="busy === u.id" class="icon-btn icon-btn-danger act-icon" :title="t('users.delete_user')" :aria-label="t('users.delete_user')"><Icon name="trash" :size="16" /></button>
                            </div>
                            <span v-else class="badge badge-gray">{{ t('users.owner_account') }}</span>
                        </td>
                    </tr>
                </tbody>
            </table>
        </div>
    </div>
</template>

<style scoped>
.badge.badge-amber { color: var(--p-primary-800); }
.badge.badge-gray { color: var(--body); }
.badge.badge-indigo { color: var(--p-primary-800); }
.cta { min-height: 44px; }

.tbl-card { overflow-x: auto; }
.tbl-card table { min-width: 820px; font-size: 14.5px; }
.th { padding: 11px 16px; font-size: 12.5px; font-weight: 600; color: var(--body); background: var(--page); border-bottom: 1px solid var(--line); }
.th:first-child, .td:first-child { padding-inline-start: 20px; }
.th:last-child, .td:last-child { padding-inline-end: 20px; }
.td { padding: 12px 16px; vertical-align: middle; }
.row { border-top: 1px solid var(--line); transition: background .15s; }
.row:hover { background: var(--page); }
.u-name { font-size: 15px; font-weight: 600; color: var(--ink); max-width: 220px; }
.initial { width: 34px; height: 34px; border-radius: 50%; flex: none; display: grid; place-items: center;
    background: var(--accent-soft); color: var(--p-primary-700); font-weight: 700; font-size: 14px; }
.act { min-height: 36px; }
.act-icon { width: 36px; height: 36px; color: var(--red); }
.empty { display: flex; flex-direction: column; align-items: center; gap: 12px; padding: 44px 16px; text-align: center; color: var(--body); }
.empty-ico { width: 48px; height: 48px; border-radius: 14px; display: grid; place-items: center; background: var(--accent-soft); color: var(--p-primary-700); }
@media (max-width: 640px) {
    .act { min-height: 44px; }
    .act-icon { width: 44px; height: 44px; }
}
</style>
