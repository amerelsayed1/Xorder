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
    <SettingsHeader class="roles-head" :title="t('team.roles_title')" :desc="t('team.roles_sub')">
        <template #actions>
            <RouterLink :to="{ name: 'dashboard.staff' }" class="set-btn act">{{ t('team.staff_title') }}</RouterLink>
            <RouterLink v-if="canCreate" :to="{ name: 'dashboard.roles.create' }" class="set-btn-primary act">
                <Icon name="plus" :size="15" />{{ t('team.add_role') }}
            </RouterLink>
        </template>
    </SettingsHeader>

    <!-- Skeleton mirrors a role card: header row + a block of chips -->
    <div v-if="loading" class="stack">
        <div v-for="n in 2" :key="n" class="card skel-card">
            <div class="set-skel" style="height:18px;width:30%;border-radius:6px"></div>
            <div class="set-skel" style="height:12px;width:20%;border-radius:6px"></div>
            <div style="display:flex;gap:8px;flex-wrap:wrap">
                <div v-for="m in 5" :key="m" class="set-skel" style="height:28px;width:90px;border-radius:999px"></div>
            </div>
        </div>
    </div>

    <div v-else-if="!rows.length" class="card empty">
        <span class="empty-ico" aria-hidden="true"><i class="pi pi-shield" style="font-size:22px"></i></span>
        <p class="empty-text">{{ t('team.roles_empty') }}</p>
        <RouterLink v-if="canCreate" :to="{ name: 'dashboard.roles.create' }" class="set-btn-primary act">
            <Icon name="plus" :size="15" />{{ t('team.add_role') }}
        </RouterLink>
    </div>

    <div v-else class="stack">
        <section v-for="r in rows" :key="r.id" class="card role">
            <div class="role-head">
                <div class="role-id">
                    <div class="role-name">
                        <h2 class="h-card truncate">{{ roleLabel(r) }}</h2>
                        <span v-if="r.is_system" class="chip">{{ t('team.system_role') }}</span>
                    </div>
                    <span class="role-meta">
                        {{ t('team.holders', r.users_count ?? 0, { count: r.users_count ?? 0 }) }}
                        · {{ t('team.perm_count', capCount(r), { count: capCount(r) }) }}
                    </span>
                </div>
                <div class="role-actions">
                    <button type="button" class="set-btn act" :aria-expanded="!!expanded[r.id]" @click="toggle(r)">
                        {{ expanded[r.id] ? t('team.hide_permissions') : t('team.show_permissions') }}
                    </button>
                    <RouterLink v-if="canUpdate" :to="{ name: 'dashboard.roles.edit', params: { id: r.id } }" class="set-btn act">{{ t('common.edit') }}</RouterLink>
                    <!-- Built-in roles are editable but permanent, so a tenant always has one to assign. -->
                    <button v-if="canDelete && !r.is_system" type="button" class="set-icon-danger act-icon" :disabled="busy === r.id"
                        :title="t('team.delete_role')" :aria-label="t('team.delete_role')" @click="remove(r)">
                        <Icon name="trash" :size="16" />
                    </button>
                </div>
            </div>

            <div class="role-body">
                <div v-for="g in visibleGroups(r)" :key="g.key" class="perm-group">
                    <span class="perm-title">{{ g.title }}</span>
                    <div class="perm-wrap">
                        <span v-for="c in g.caps" :key="c" class="perm">{{ capLabel(c) }}</span>
                    </div>
                </div>
                <p v-if="!capCount(r)" class="role-none">{{ t('team.no_permissions') }}</p>
                <button v-if="hasMore(r)" type="button" class="more-link" :aria-expanded="!!expanded[r.id]" @click="toggle(r)">
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
            <div class="flex flex-wrap justify-end gap-2 pt-2">
                <button class="btn btn-ghost act" @click="reassign = null">{{ t('common.cancel') }}</button>
                <button class="btn btn-dark act" :disabled="!reassignTo || busy === reassign.id" @click="destroy(reassign, reassignTo)">{{ t('team.reassign_confirm') }}</button>
            </div>
        </div>
    </Modal>
</template>

<style scoped>
/* Colours come from the shared theme variables only. The settings shell's
   own text is nudged to --body so secondary copy stays readable. */
.roles-head :deep(.set-desc), .roles-head :deep(.set-crumb) { color: var(--body); font-size: 14px; }

.stack { display: flex; flex-direction: column; gap: 14px; }
.skel-card { padding: 18px 20px; display: flex; flex-direction: column; gap: 14px; }

.role { overflow: hidden; }
.role-head { display: flex; flex-wrap: wrap; align-items: center; gap: 12px 16px; padding: 16px 20px; border-bottom: 1px solid var(--line); }
.role-id { flex: 1 1 220px; min-width: 0; display: flex; flex-direction: column; gap: 4px; }
.role-name { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; min-width: 0; }
.role-meta { font-size: 14px; color: var(--body); }
.role-actions { display: flex; align-items: center; gap: 8px; margin-inline-start: auto; flex-wrap: wrap; }
.role-body { padding: 16px 20px 18px; display: flex; flex-direction: column; gap: 16px; }
.role-none { font-size: 14px; color: var(--body); }

.chip { display: inline-flex; align-items: center; padding: 3px 10px; border-radius: 999px; font-size: 12.5px; font-weight: 600;
    background: var(--gray-soft); color: var(--body); }

.perm-group { display: flex; flex-direction: column; gap: 8px; }
.perm-title { font-size: 13px; font-weight: 600; color: var(--ink); }
.perm-wrap { display: flex; flex-wrap: wrap; gap: 7px; }
.perm { padding: 5px 12px; border-radius: 999px; background: var(--accent-soft); color: var(--p-primary-800); font-size: 13.5px; font-weight: 500; }
.more-link { align-self: flex-start; min-height: 36px; border: none; background: none; padding: 0; font: inherit; font-size: 14px;
    font-weight: 600; color: var(--p-primary-700); cursor: pointer; }
.more-link:hover { text-decoration: underline; }

.act { min-height: 40px; font-size: 14px; justify-content: center; }
.act-icon { width: 40px; height: 40px; }

.empty { display: flex; flex-direction: column; align-items: center; gap: 10px; padding: 40px 20px; text-align: center; }
.empty-ico { width: 48px; height: 48px; border-radius: 14px; display: grid; place-items: center;
    background: var(--accent-soft); color: var(--p-primary-700); }
.empty-text { font-size: 15.5px; font-weight: 600; color: var(--ink); }

@media (max-width: 640px) {
    .role-head, .role-body { padding-inline: 14px; }
    .role-actions { width: 100%; }
    .act { min-height: 44px; }
    .act-icon { width: 44px; height: 44px; }
}
</style>
