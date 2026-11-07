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

// A resource whose verbs are not CRUD cannot be expressed as a row of four
// checkboxes, and forcing it into one is not a cosmetic problem: `pos` has ten
// verbs (operate, refund, shift_open, provision…), none of which is
// view/create/update/delete, so its row rendered as four dashes and NO POS
// capability could be granted to any custom role at all. Only the owner could
// use a till, because RESTAURANT_ADMIN holds every capability implicitly
// rather than through this grid.
//
// Split by shape rather than by naming `pos`: any resource the server adds
// later with its own verbs gets a usable editor without a frontend change,
// which is the same reason the catalogue is fetched instead of hardcoded.
const fitsMatrix = (row) => Object.keys(row.cells).every((a) => ACTIONS.includes(a))

// Rows stay grouped under the same headings as before.
const rowGroups = computed(() => {
    const out = new Map()
    for (const row of rows.value) {
        if (!fitsMatrix(row)) continue
        if (!out.has(row.group)) out.set(row.group, [])
        out.get(row.group).push(row)
    }
    return [...out.entries()].map(([key, list]) => ({ key, rows: list }))
})

/// Resources with off-matrix verbs, each as a labelled list of its own.
const listGroups = computed(() => {
    const out = new Map()
    for (const row of rows.value) {
        if (fitsMatrix(row)) continue
        if (!out.has(row.group)) out.set(row.group, [])
        // Catalogue order, which is the enum's order — the server decides how
        // these read, and it lists `operate` first for a reason.
        out.get(row.group).push({
            resource: row.resource,
            caps: catalogue.value.filter((c) => c.resource === row.resource),
        })
    }
    return [...out.entries()].map(([key, list]) => ({ key, resources: list }))
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
        <RouterLink :to="{ name: 'dashboard.roles' }" class="back-link">{{ backArrow }} {{ t('common.back') }}</RouterLink>
        <h1 class="page-title mt-2 mb-4">{{ isEdit ? t('team.edit_role') : t('team.add_role') }}</h1>

        <form @submit.prevent="submit" class="space-y-5">
            <!-- Names -->
            <section class="card p-5 sm:p-6 space-y-4" aria-labelledby="rf-names">
                <h2 id="rf-names" class="h-card">{{ t('team.sec_role') }}</h2>
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                    <label class="block" dir="ltr"><span class="label">{{ t('team.role_name') }}</span>
                        <input v-model="form.name" class="input" />
                        <FormError :errors="errors" field="name" /></label>
                    <label class="block" dir="rtl"><span class="label">{{ t('team.role_name_ar') }}</span>
                        <input v-model="form.name_ar" class="input" />
                        <FormError :errors="errors" field="name_ar" /></label>
                </div>
                <p v-if="isSystem" class="sys-note"><span class="chip">{{ t('team.system_role') }}</span></p>
            </section>

            <!-- Permissions -->
            <section class="card p-5 sm:p-6 space-y-4" aria-labelledby="rf-perms">
                <div class="flex flex-wrap items-start justify-between gap-3">
                    <div class="min-w-0">
                        <h2 id="rf-perms" class="h-card">{{ t('team.capabilities') }}</h2>
                        <p class="page-sub" style="color:var(--body)">{{ t('team.capabilities_hint') }}</p>
                    </div>
                    <div class="flex items-center gap-2">
                        <button type="button" class="btn btn-ghost btn-sm act-btn" @click="selectAll">{{ t('team.select_all') }}</button>
                        <button type="button" class="btn btn-ghost btn-sm act-btn" @click="clearAll">{{ t('team.clear_all') }}</button>
                    </div>
                </div>

                <!-- One block per functional area: a heading, the verb columns, then
                     its resources. Every block repeats the verb header so a row is
                     never far from the column it belongs to. -->
                <div class="perm-grid">
                    <section v-for="g in rowGroups" :key="g.key" class="perm-sec">
                        <div class="perm-group">{{ groupLabel(g.key) }}</div>
                        <div class="perm-head" aria-hidden="true">
                            <span></span>
                            <span v-for="a in ACTIONS" :key="a" class="perm-action">{{ t('capaction.' + a) }}</span>
                        </div>
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
                                <span v-else class="perm-na" aria-hidden="true">—</span>
                            </span>
                        </div>
                    </section>
                </div>

                <!-- Resources whose verbs are not CRUD. Rendered as their own
                     labelled list rather than squeezed into the matrix above,
                     because a checkbox under a "Delete" column that actually
                     means "close a shift and count the drawer" is worse than
                     no checkbox at all. -->
                <section v-for="g in listGroups" :key="g.key" class="perm-sec">
                    <div class="perm-group">{{ groupLabel(g.key) }}</div>
                    <div v-for="r in g.resources" :key="r.resource" class="perm-res">
                        <p class="perm-resource-head">{{ t('capres.' + r.resource) }}</p>
                        <div class="perm-list">
                            <label v-for="cap in r.caps" :key="cap.value" class="perm-list-row">
                                <input
                                    type="checkbox"
                                    :checked="form.capabilities.includes(cap.value)"
                                    :disabled="isLockedView(cap.value)"
                                    :title="isLockedView(cap.value) ? t('team.view_locked') : ''"
                                    @change="toggle(cap.value)" />
                                <span>{{ t('capaction.' + cap.action) }}</span>
                            </label>
                        </div>
                    </div>
                </section>

                <FormError :errors="errors" field="capabilities" />
            </section>

            <!-- Sticky action row -->
            <div class="action-bar">
                <RouterLink :to="{ name: 'dashboard.roles' }" class="btn btn-ghost act-btn">{{ t('common.cancel') }}</RouterLink>
                <button type="submit" :disabled="saving" class="btn btn-accent act-btn">{{ saving ? t('common.saving') : (isEdit ? t('admin.save_changes') : t('team.add_role')) }}</button>
            </div>
        </form>
    </div>
</template>

<style scoped>
/* Colours come from the shared theme variables only. */
.back-link { display: inline-flex; align-items: center; min-height: 32px; font-size: 14px; color: var(--p-primary-700); }
.back-link:hover { text-decoration: underline; }
.act-btn { min-height: 44px; justify-content: center; }
.chip { display: inline-flex; align-items: center; padding: 3px 10px; border-radius: 999px; font-size: 12.5px; font-weight: 600;
    background: var(--gray-soft); color: var(--body); }

/* ---- Permission matrix ---- */
.perm-grid { display: flex; flex-direction: column; gap: 14px; overflow-x: auto; }
.perm-sec { border: 1px solid var(--line); border-radius: 12px; overflow: hidden; min-width: 300px; }
/* Area heading: a tinted strip so groups scan as blocks */
.perm-group { padding: 10px 14px; background: var(--page); border-bottom: 1px solid var(--line);
    font-size: 14px; font-weight: 700; color: var(--ink); }
.perm-head, .perm-row {
    display: grid; grid-template-columns: minmax(110px, 1fr) repeat(4, 64px);
    align-items: center; gap: 2px; padding-inline: 14px;
}
.perm-head { padding-block: 6px; border-bottom: 1px solid var(--line); }
.perm-action { font-size: 13px; font-weight: 600; color: var(--body); text-align: center; }
.perm-row { min-height: 46px; border-bottom: 1px solid var(--line); transition: background .15s; }
.perm-row:last-child { border-bottom: 0; }
.perm-row:hover { background: var(--page); }
.perm-resource { font-size: 14.5px; color: var(--ink); padding-block: 6px; }
.perm-cell { display: grid; place-items: center; min-height: 44px; }
.perm-cell input { width: 20px; height: 20px; accent-color: var(--accent); cursor: pointer; }
.perm-cell input:disabled { cursor: not-allowed; opacity: .55; }
.perm-na { color: var(--muted); font-size: 13px; }

/* Non-CRUD resources */
.perm-res { padding: 10px 14px 4px; }
.perm-res + .perm-res { border-top: 1px solid var(--line); }
.perm-resource-head { font-size: 14px; font-weight: 600; color: var(--ink); margin-bottom: 2px; }
.perm-list { display: grid; grid-template-columns: repeat(auto-fill, minmax(220px, 1fr)); column-gap: 16px; }
.perm-list-row { display: flex; align-items: center; gap: 10px; min-height: 44px; font-size: 14.5px; color: var(--body); cursor: pointer; }
.perm-list-row input { width: 18px; height: 18px; accent-color: var(--accent); cursor: pointer; flex: none; }
.perm-list-row input[disabled] { cursor: not-allowed; opacity: .55; }

/* Sticky save row */
.action-bar { position: sticky; bottom: 0; z-index: 5; display: flex; flex-wrap: wrap; justify-content: flex-end; gap: 10px;
    padding: 12px 16px; background: var(--card); border: 1px solid var(--line); border-radius: 15px;
    box-shadow: 0 -4px 14px rgba(0, 0, 0, .05); }

@media (max-width: 640px) {
    .perm-head, .perm-row { grid-template-columns: minmax(88px, 1fr) repeat(4, 46px); padding-inline: 10px; }
    .perm-action { font-size: 12px; }
    .action-bar .act-btn { flex: 1 1 0; }
}
</style>
