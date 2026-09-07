<script setup>
import { ref, reactive, computed, onMounted } from 'vue'
import { RouterLink } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { useCaps } from '../../lib/useCaps.js'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import Icon from '@xorder/ui/Icon.vue'
import Modal from '@xorder/ui/Modal.vue'
import { confirm } from '@xorder/ui/confirm.js'
import { alert } from '@xorder/ui/alert.js'
import { pickLocalized } from '@xorder/ui/localize.js'
import { capabilityLabel, capabilityGroupLabel } from '../../lib/capabilities.js'
import SettingsHeader from './settings/SettingsHeader.vue'

const { t, locale } = useI18n()
// Per-action gates so the UI offers only what the API would accept.
const { canCreate, canUpdate, canDelete } = useCaps('staff')
const rows = ref([])
const loading = ref(true)
const busy = ref(null)

// Deleting a role that people still hold needs somewhere to move them to; the
// server refuses without it, so ask here rather than showing that as an error.
const reassign = ref(null)
const reassignTo = ref('')

// The catalogue answers which functional area each capability belongs to. A
// role can carry forty of them, and forty identical chips in one flat row is
// a wall, not information — grouping is what makes it readable. Fetched rather
// than hardcoded, same as the role editor, so a new server capability lands
// here without a frontend change.
const capGroup = ref({})
// Catalogue order of the groups, so two roles list their areas in the same
// sequence no matter what order their own capability arrays happen to be in.
const groupOrder = ref([])

async function load() {
    loading.value = true
    try {
        const [list, cat] = await Promise.all([
            api.get('api/dashboard/roles'),
            // Grouping is a nicety; a role list that renders ungrouped chips is
            // still usable, so this never fails the page.
            api.get('api/dashboard/roles/capabilities').catch(() => null),
        ])
        rows.value = list.data.data
        if (cat) {
            const map = {}
            const order = []
            for (const c of cat.data.data ?? cat.data) {
                map[c.value] = c.group
                if (!order.includes(c.group)) order.push(c.group)
            }
            capGroup.value = map
            groupOrder.value = order
        }
    } finally {
        loading.value = false
    }
}
onMounted(load)

const roleLabel = (r) => pickLocalized({ name_en: r.name, name_ar: r.name_ar }, 'name', locale.value) || r.name
const capLabel = (value) => capabilityLabel(t, value)

// Collapsed shows the first group only, capped at six chips — enough to say
// what a role is about without the card swallowing the screen.
const COLLAPSED_CHIPS = 6
const expanded = reactive({})
const toggle = (r) => { expanded[r.id] = !expanded[r.id] }

// [{ key, title, caps }] in catalogue-group order, with anything the catalogue
// did not describe collected under a trailing "other" bucket.
function groupsFor(role) {
    const out = new Map()
    for (const value of role.capabilities || []) {
        const key = capGroup.value[value] || 'other'
        if (!out.has(key)) out.set(key, [])
        out.get(key).push(value)
    }
    const rank = (key) => {
        const i = groupOrder.value.indexOf(key)
        return i === -1 ? Number.MAX_SAFE_INTEGER : i
    }
    return [...out.entries()]
        .sort((a, b) => rank(a[0]) - rank(b[0]))
        .map(([key, caps]) => ({
            key,
            title: key === 'other' ? t('team.capabilities') : capabilityGroupLabel(t, key),
            caps,
        }))
}

// What the card actually renders, given its expanded state.
function visibleGroups(role) {
    const all = groupsFor(role)
    if (expanded[role.id] || !all.length) return all
    return [{ ...all[0], caps: all[0].caps.slice(0, COLLAPSED_CHIPS) }]
}

const capCount = (role) => (role.capabilities || []).length
const hasMore = (role) => capCount(role) > COLLAPSED_CHIPS

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
    <SettingsHeader :title="t('team.roles_title')" :desc="t('team.roles_sub')">
        <template #actions>
            <RouterLink :to="{ name: 'dashboard.staff' }" class="set-btn">{{ t('team.staff_title') }}</RouterLink>
            <RouterLink v-if="canCreate" :to="{ name: 'dashboard.roles.create' }" class="set-btn-primary">
                <Icon name="plus" :size="15" />{{ t('team.add_role') }}
            </RouterLink>
        </template>
    </SettingsHeader>

    <div v-if="loading" class="set-stack-lg">
        <div v-for="n in 2" :key="n" class="set-skel" style="height: 150px"></div>
    </div>

    <div v-else-if="!rows.length" class="set-card">
        <div class="set-empty">
            <span class="set-empty-title">{{ t('team.roles_empty') }}</span>
        </div>
    </div>

    <div v-else class="set-stack-lg">
        <section v-for="r in rows" :key="r.id" class="set-card">
            <div class="set-card-head">
                <div class="set-row-name">
                    <span class="set-card-title">{{ roleLabel(r) }}</span>
                    <span v-if="r.is_system" class="set-chip">{{ t('team.system_role') }}</span>
                </div>
                <span class="set-card-meta">
                    {{ t('team.holders', r.users_count ?? 0, { count: r.users_count ?? 0 }) }}
                    · {{ t('team.perm_count', capCount(r), { count: capCount(r) }) }}
                </span>
                <div class="set-row-actions">
                    <button type="button" class="set-btn set-btn-sm" :aria-expanded="!!expanded[r.id]" @click="toggle(r)">
                        {{ expanded[r.id] ? t('team.hide_permissions') : t('team.show_permissions') }}
                    </button>
                    <RouterLink v-if="canUpdate" :to="{ name: 'dashboard.roles.edit', params: { id: r.id } }" class="set-btn set-btn-sm">{{ t('common.edit') }}</RouterLink>
                    <!-- Built-in roles are editable but permanent, so a tenant always has one to assign. -->
                    <button v-if="canDelete && !r.is_system" type="button" class="set-icon-danger" :disabled="busy === r.id"
                        :title="t('team.delete_role')" :aria-label="t('team.delete_role')" @click="remove(r)">
                        <Icon name="trash" :size="16" />
                    </button>
                </div>
            </div>

            <div class="set-card-body">
                <div v-for="g in visibleGroups(r)" :key="g.key" class="set-perm-group">
                    <span class="set-perm-title">{{ g.title }}</span>
                    <div class="set-perm-wrap">
                        <span v-for="c in g.caps" :key="c" class="set-perm">{{ capLabel(c) }}</span>
                    </div>
                </div>
                <p v-if="!capCount(r)" class="set-empty-hint">{{ t('team.no_permissions') }}</p>
                <button v-if="hasMore(r)" type="button" class="set-link" @click="toggle(r)">
                    {{ expanded[r.id] ? t('team.hide_permissions') : t('team.show_all_permissions', { count: capCount(r) }) }}
                </button>
            </div>
        </section>
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
</template>

<style scoped>
.set-card-meta { font-size: 12.5px; color: var(--muted); }
</style>
