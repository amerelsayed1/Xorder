<script setup>
import { reactive, ref, computed, onMounted } from 'vue'
import { useRoute, useRouter, RouterLink } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { useAuth } from '@xorder/api-client/auth.js'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import FormError from '@xorder/ui/FormError.vue'
import { capabilityGroupLabel } from '../../lib/capabilities.js'

const route = useRoute()
const router = useRouter()
const { t, locale } = useI18n()
const auth = useAuth()

const isEdit = computed(() => !!route.params.id)
const backArrow = computed(() => locale.value === 'ar' ? '→' : '←')

const form = reactive({ name: '', name_ar: '', capabilities: [] })
const errors = ref({})
const saving = ref(false)
const isSystem = ref(false)

// The catalogue comes from the server (App\Enums\TenantCapability) rather than a
// hard-coded list, so a new capability shows up here without a frontend change.
// Only the ones the signed-in user holds are offered: the API rejects granting
// above yourself, so offering more would just produce a validation error.
const catalogue = ref([])
const grantable = computed(() => catalogue.value.filter((c) => auth.can(c.value)))
// Verb columns, in the order a person reads them. A resource only offers the
// verbs its endpoints support, so cells can be empty — orders are never
// created or deleted from the dashboard.
const ACTIONS = ['view', 'create', 'update', 'delete']

// One row per resource, carrying the capability (if any) for each verb.
const rows = computed(() => {
    const byResource = new Map()
    for (const cap of catalogue.value) {
        if (!byResource.has(cap.resource)) {
            byResource.set(cap.resource, { resource: cap.resource, group: cap.group, cells: {} })
        }
        byResource.get(cap.resource).cells[cap.action] = cap
    }
    return [...byResource.values()]
})

// Rows stay grouped under the same headings as before.
const rowGroups = computed(() => {
    const out = new Map()
    for (const row of rows.value) {
        if (!out.has(row.group)) out.set(row.group, [])
        out.get(row.group).push(row)
    }
    return [...out.entries()].map(([key, list]) => ({ key, rows: list }))
})

const groups = computed(() => {
    const out = new Map()
    for (const cap of grantable.value) {
        if (!out.has(cap.group)) out.set(cap.group, [])
        out.get(cap.group).push(cap)
    }
    return [...out.entries()].map(([key, caps]) => ({ key, caps }))
})

const groupLabel = (key) => capabilityGroupLabel(t, key)

// "manage" implies "view" on the server; mirror that here so the checkboxes
// can't show a state the server would silently correct.
const impliedBy = computed(() => {
    const m = new Map()
    for (const cap of catalogue.value) if (cap.implies) m.set(cap.value, cap.implies)
    return m
})
const isLockedView = (value) => form.capabilities.some((c) => impliedBy.value.get(c) === value)

function toggle(value) {
    const i = form.capabilities.indexOf(value)
    if (i === -1) {
        form.capabilities.push(value)
        const implied = impliedBy.value.get(value)
        if (implied && !form.capabilities.includes(implied)) form.capabilities.push(implied)
    } else if (!isLockedView(value)) {
        form.capabilities.splice(i, 1)
    }
}

const selectAll = () => { form.capabilities = grantable.value.map((c) => c.value) }
const clearAll = () => { form.capabilities = [] }

onMounted(async () => {
    const { data } = await api.get('api/dashboard/roles/capabilities')
    catalogue.value = data.data
    if (isEdit.value) {
        const { data: role } = await api.get(`api/dashboard/roles/${route.params.id}`)
        form.name = role.data.name
        form.name_ar = role.data.name_ar || ''
        form.capabilities = [...role.data.capabilities]
        isSystem.value = role.data.is_system
    }
})

async function submit() {
    errors.value = {}
    saving.value = true
    try {
        await ensureCsrf()
        const payload = { name: form.name, name_ar: form.name_ar || null, capabilities: form.capabilities }
        if (isEdit.value) await api.put(`api/dashboard/roles/${route.params.id}`, payload)
        else await api.post('api/dashboard/roles', payload)
        router.push({ name: 'dashboard.roles' })
    } catch (err) {
        errors.value = err.response?.data?.errors || {}
    } finally {
        saving.value = false
    }
}
</script>

<template>
    <div class="max-w-3xl">
        <RouterLink :to="{ name: 'dashboard.roles' }" class="text-sm" style="color:var(--muted)">{{ backArrow }} {{ t('common.back') }}</RouterLink>
        <h1 class="page-title my-3">{{ isEdit ? t('team.edit_role') : t('team.add_role') }}</h1>

        <form @submit.prevent="submit" class="space-y-5">
            <div class="card p-6 space-y-4">
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                    <label class="block" dir="ltr"><span class="label">{{ t('team.role_name') }}</span>
                        <input v-model="form.name" class="input" />
                        <FormError :errors="errors" field="name" /></label>
                    <label class="block" dir="rtl"><span class="label">{{ t('team.role_name_ar') }}</span>
                        <input v-model="form.name_ar" class="input" />
                        <FormError :errors="errors" field="name_ar" /></label>
                </div>
                <p v-if="isSystem" class="text-xs" style="color:var(--muted)">{{ t('team.system_role') }}</p>
            </div>

            <div class="card p-6 space-y-4">
                <div class="flex items-start justify-between gap-3">
                    <div>
                        <h2 class="h-card">{{ t('team.capabilities') }}</h2>
                        <p class="page-sub">{{ t('team.capabilities_hint') }}</p>
                    </div>
                    <div class="flex items-center gap-2">
                        <button type="button" class="btn btn-ghost btn-sm" @click="selectAll">{{ t('team.select_all') }}</button>
                        <button type="button" class="btn btn-ghost btn-sm" @click="clearAll">{{ t('team.clear_all') }}</button>
                    </div>
                </div>

                <div class="perm-grid">
                    <div class="perm-head">
                        <span></span>
                        <span v-for="a in ACTIONS" :key="a" class="perm-action">{{ t('capaction.' + a) }}</span>
                    </div>

                    <template v-for="g in rowGroups" :key="g.key">
                        <div class="perm-group">{{ groupLabel(g.key) }}</div>
                        <div v-for="row in g.rows" :key="row.resource" class="perm-row">
                            <span class="perm-resource">{{ t('capres.' + row.resource) }}</span>
                            <span v-for="a in ACTIONS" :key="a" class="perm-cell">
                                <input
                                    v-if="row.cells[a]"
                                    type="checkbox"
                                    :aria-label="t('capres.' + row.resource) + ' — ' + t('capaction.' + a)"
                                    :checked="form.capabilities.includes(row.cells[a].value)"
                                    :disabled="isLockedView(row.cells[a].value)"
                                    :title="isLockedView(row.cells[a].value) ? t('team.view_locked') : ''"
                                    @change="toggle(row.cells[a].value)" />
                                <span v-else class="perm-na">—</span>
                            </span>
                        </div>
                    </template>
                </div>

                <FormError :errors="errors" field="capabilities" />
            </div>

            <div class="flex justify-end gap-2">
                <RouterLink :to="{ name: 'dashboard.roles' }" class="btn btn-ghost">{{ t('common.cancel') }}</RouterLink>
                <button type="submit" :disabled="saving" class="btn btn-accent">{{ saving ? t('common.saving') : (isEdit ? t('admin.save_changes') : t('team.add_role')) }}</button>
            </div>
        </form>
    </div>
</template>

<style scoped>
.perm-grid { width: 100%; overflow-x: auto; }
.perm-head, .perm-row {
    display: grid; grid-template-columns: minmax(140px, 1fr) repeat(4, 68px);
    align-items: center; gap: 4px;
}
.perm-head { padding-bottom: 6px; border-bottom: 1px solid var(--line); }
.perm-action { font-size: 12px; color: var(--muted); text-align: center; }
.perm-group {
    font-size: 12px; font-weight: 600; color: var(--muted);
    margin-top: 14px; margin-bottom: 4px; text-transform: uppercase; letter-spacing: .04em;
}
.perm-row { padding: 7px 0; border-bottom: 1px solid var(--line); }
.perm-row:last-child { border-bottom: 0; }
.perm-resource { font-size: 14px; color: var(--body); }
.perm-cell { text-align: center; }
.perm-cell input { accent-color: var(--accent); cursor: pointer; }
.perm-cell input:disabled { cursor: not-allowed; opacity: .55; }
.perm-na { color: var(--line); font-size: 13px; }
</style>
