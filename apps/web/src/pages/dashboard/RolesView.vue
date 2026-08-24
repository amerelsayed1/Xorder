<script setup>
import { ref, onMounted } from 'vue'
import { RouterLink } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { useAuth } from '@xorder/api-client/auth.js'
import { useCaps } from '../../lib/useCaps.js'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import Icon from '@xorder/ui/Icon.vue'
import Modal from '@xorder/ui/Modal.vue'
import TableSkeleton from '@xorder/ui/TableSkeleton.vue'
import { confirm } from '@xorder/ui/confirm.js'
import { alert } from '@xorder/ui/alert.js'
import { pickLocalized } from '@xorder/ui/localize.js'
import { capabilityLabel } from '../../lib/capabilities.js'

const { t, locale } = useI18n()
const auth = useAuth()
// Per-action gates so the UI offers only what the API would accept.
const { canCreate, canUpdate, canDelete } = useCaps('staff')
const rows = ref([])
const loading = ref(true)
const busy = ref(null)

// Deleting a role that people still hold needs somewhere to move them to; the
// server refuses without it, so ask here rather than showing that as an error.
const reassign = ref(null)
const reassignTo = ref('')

async function load() {
    loading.value = true
    try {
        const { data } = await api.get('api/dashboard/roles')
        rows.value = data.data
    } finally {
        loading.value = false
    }
}
onMounted(load)

const roleLabel = (r) => pickLocalized({ name_en: r.name, name_ar: r.name_ar }, 'name', locale.value) || r.name
const capLabel = (value) => capabilityLabel(t, value)

async function remove(role) {
    if (role.users_count > 0) {
        reassign.value = role
        reassignTo.value = rows.value.find((r) => r.id !== role.id)?.id ?? ''
        return
    }
    const ok = await confirm({
        title: t('team.delete_role_title', { name: roleLabel(role) }),
        message: t('team.delete_role_message'),
        confirmText: t('team.delete_role_confirm'),
        cancelText: t('common.cancel'),
        danger: true,
    })
    if (!ok) return
    await destroy(role)
}

async function destroy(role, reassignToId = null) {
    busy.value = role.id
    try {
        await ensureCsrf()
        await api.delete(`api/dashboard/roles/${role.id}`, {
            data: reassignToId ? { reassign_to: reassignToId } : {},
        })
        reassign.value = null
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
                <h1 class="page-title">{{ t('team.roles_title') }}</h1>
                <p class="page-sub">{{ t('team.roles_sub') }}</p>
            </div>
            <div class="flex items-center gap-2">
                <RouterLink :to="{ name: 'dashboard.staff' }" class="btn btn-ghost"><i class="pi pi-users" style="font-size:15px" aria-hidden="true"></i>{{ t('team.staff_title') }}</RouterLink>
                <RouterLink v-if="canCreate" :to="{ name: 'dashboard.roles.create' }" class="btn btn-accent"><Icon name="plus" :size="16" />{{ t('team.add_role') }}</RouterLink>
            </div>
        </div>

        <div class="card overflow-x-auto">
            <table class="w-full text-sm" style="min-width:640px">
                <thead>
                    <tr class="text-start" style="color:var(--muted)">
                        <th class="px-5 py-3 font-medium" style="font-size:11px;text-transform:uppercase">{{ t('team.role') }}</th>
                        <th class="px-3 py-3 font-medium" style="font-size:11px;text-transform:uppercase">{{ t('team.capabilities') }}</th>
                        <th class="px-3 py-3 font-medium" style="font-size:11px;text-transform:uppercase">{{ t('team.staff_title') }}</th>
                        <th class="px-5 py-3 font-medium text-end" style="font-size:11px;text-transform:uppercase">{{ t('common.actions') }}</th>
                    </tr>
                </thead>
                <tbody>
                    <TableSkeleton v-if="loading" :cols="4" />
                    <tr v-else-if="!rows.length"><td colspan="4" class="px-5 py-8 text-center" style="color:var(--muted)">{{ t('team.roles_empty') }}</td></tr>
                    <tr v-for="r in loading ? [] : rows" :key="r.id" class="border-t align-top" :style="{ borderColor: 'var(--line)' }">
                        <td class="px-5 py-3">
                            <div class="font-medium" style="color:var(--ink)">{{ roleLabel(r) }}</div>
                            <span v-if="r.is_system" class="badge badge-gray mt-1">{{ t('team.system_role') }}</span>
                        </td>
                        <td class="px-3 py-3">
                            <div class="flex flex-wrap gap-1" style="max-width:420px">
                                <span v-for="c in r.capabilities" :key="c" class="badge badge-indigo">{{ capLabel(c) }}</span>
                            </div>
                        </td>
                        <td class="px-3 py-3" style="color:var(--body)">{{ t('team.holders', r.users_count ?? 0, { count: r.users_count ?? 0 }) }}</td>
                        <td class="px-5 py-3 text-end whitespace-nowrap">
                            <div class="inline-flex items-center gap-2">
                                <RouterLink v-if="canUpdate" :to="{ name: 'dashboard.roles.edit', params: { id: r.id } }" class="btn btn-ghost" style="padding:5px 11px;font-size:12px">{{ t('common.edit') }}</RouterLink>
                                <!-- Built-in roles are editable but permanent, so a tenant always has one to assign. -->
                                <button v-if="canDelete && !r.is_system" @click="remove(r)" :disabled="busy === r.id" class="icon-btn icon-btn-danger" :title="t('team.delete_role')" :aria-label="t('team.delete_role')"><Icon name="trash" :size="16" /></button>
                            </div>
                        </td>
                    </tr>
                </tbody>
            </table>
        </div>

        <Modal v-if="reassign" :title="t('team.reassign_title', { name: roleLabel(reassign) })" @close="reassign = null">
            <div class="space-y-4">
                <p class="text-sm" style="color:var(--body)">{{ t('team.reassign_message') }}</p>
                <label class="block"><span class="label">{{ t('team.reassign_label') }}</span>
                    <select v-model="reassignTo" class="input">
                        <option value="" disabled>{{ t('team.select_role') }}</option>
                        <option v-for="r in rows.filter((x) => x.id !== reassign.id)" :key="r.id" :value="r.id">{{ roleLabel(r) }}</option>
                    </select>
                </label>
                <div class="flex justify-end gap-2 pt-2">
                    <button class="btn btn-ghost" @click="reassign = null">{{ t('common.cancel') }}</button>
                    <button class="btn btn-dark" :disabled="!reassignTo || busy === reassign.id" @click="destroy(reassign, reassignTo)">{{ t('team.reassign_confirm') }}</button>
                </div>
            </div>
        </Modal>
    </div>
</template>
