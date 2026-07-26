<script setup>
import { ref, computed, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import Icon from '@xorder/ui/Icon.vue'
import Modal from '@xorder/ui/Modal.vue'
import TableSkeleton from '@xorder/ui/TableSkeleton.vue'

const { t } = useI18n()

const STATUSES = ['NEW', 'CONTACTED', 'DEMO_SCHEDULED', 'PROPOSAL_SENT', 'WON', 'LOST']
const badgeClass = {
    NEW: 'badge-amber', CONTACTED: 'badge-gray', DEMO_SCHEDULED: 'badge-gray',
    PROPOSAL_SENT: 'badge-gray', WON: 'badge-green', LOST: 'badge-red',
}

const rows = ref([])
const counts = ref({})
const total = ref(0)
const loading = ref(true)
const statusFilter = ref('')
const search = ref('')

// Slide-over editor state
const active = ref(null)
const editStatus = ref('NEW')
const editNotes = ref('')
const saving = ref(false)

const exportHref = computed(() => {
    const base = api.defaults.baseURL || '/'
    return `${base.endsWith('/') ? base : base + '/'}api/admin/leads/export`
})

async function load() {
    loading.value = true
    try {
        const { data } = await api.get('api/admin/leads', {
            params: { status: statusFilter.value || undefined, q: search.value || undefined },
        })
        rows.value = data.data
        counts.value = data.meta?.counts || {}
        total.value = data.meta?.total ?? data.data.length
    } finally {
        loading.value = false
    }
}
onMounted(load)

function setFilter(s) { statusFilter.value = s; load() }

function openLead(lead) {
    active.value = lead
    editStatus.value = lead.status
    editNotes.value = lead.notes || ''
}
function closeLead() { active.value = null }

async function saveLead() {
    saving.value = true
    try {
        await ensureCsrf()
        const { data } = await api.patch(`api/admin/leads/${active.value.id}`, {
            status: editStatus.value,
            notes: editNotes.value,
        })
        const i = rows.value.findIndex((r) => r.id === active.value.id)
        if (i !== -1) rows.value[i] = data.data
        closeLead()
        load()
    } finally {
        saving.value = false
    }
}

const fmtDate = (iso) => iso ? new Date(iso).toLocaleDateString() : ''
</script>

<template>
    <div class="portal theme-indigo">
        <div class="max-w-5xl mx-auto px-5 py-7 space-y-5">
            <!-- Header -->
            <div class="flex items-start justify-between gap-3 flex-wrap">
                <div>
                    <h1 class="page-title">{{ t('leads.title') }}</h1>
                    <p class="page-sub">{{ t('leads.subtitle', { n: total }) }}</p>
                </div>
                <a :href="exportHref" target="_blank" rel="noopener" class="btn btn-ghost">
                    <Icon name="download" :size="16" />{{ t('leads.export') }}
                </a>
            </div>

            <!-- Filters -->
            <div class="flex items-center gap-2 flex-wrap">
                <button class="chip" :class="{ 'chip-on': statusFilter === '' }" @click="setFilter('')">
                    {{ t('common.all') }} <span class="chip-count">{{ total }}</span>
                </button>
                <button v-for="s in STATUSES" :key="s" class="chip" :class="{ 'chip-on': statusFilter === s }" @click="setFilter(s)">
                    {{ t('leads.status.' + s) }} <span v-if="counts[s]" class="chip-count">{{ counts[s] }}</span>
                </button>
            </div>

            <div class="flex items-center gap-2">
                <input v-model="search" class="input" :placeholder="t('leads.search')" @keyup.enter="load" />
                <button class="btn btn-ghost" @click="load">{{ t('common.search') }}</button>
            </div>

            <!-- Table -->
            <div class="card overflow-x-auto">
                <table class="w-full text-sm" style="min-width:720px">
                    <thead>
                        <tr class="text-left" style="color:var(--muted)">
                            <th class="px-5 py-3 font-medium" style="font-size:11px;text-transform:uppercase">#</th>
                            <th class="px-5 py-3 font-medium" style="font-size:11px;text-transform:uppercase">{{ t('leads.restaurant') }}</th>
                            <th class="px-3 py-3 font-medium" style="font-size:11px;text-transform:uppercase">{{ t('leads.contact') }}</th>
                            <th class="px-3 py-3 font-medium" style="font-size:11px;text-transform:uppercase">{{ t('leads.whatsapp') }}</th>
                            <th class="px-3 py-3 font-medium" style="font-size:11px;text-transform:uppercase">{{ t('leads.city') }}</th>
                            <th class="px-3 py-3 font-medium" style="font-size:11px;text-transform:uppercase">{{ t('common.status') }}</th>
                            <th class="px-5 py-3 font-medium text-end" style="font-size:11px;text-transform:uppercase">{{ t('leads.created') }}</th>
                        </tr>
                    </thead>
                    <tbody>
                        <TableSkeleton v-if="loading" :cols="7" />
                        <tr v-else-if="!rows.length"><td colspan="7" class="px-5 py-8 text-center" style="color:var(--muted)">{{ t('leads.none') }}</td></tr>
                        <tr v-for="(lead, idx) in rows" :key="lead.id" class="border-t cursor-pointer hover:bg-black/[.015]"
                            :style="{ borderColor: 'var(--line)' }" @click="openLead(lead)">
                            <td class="px-5 py-3" style="color:var(--muted)">{{ idx + 1 }}</td>
                            <td class="px-5 py-3 font-medium" style="color:var(--ink)">{{ lead.restaurant_name }}</td>
                            <td class="px-3 py-3" style="color:var(--body)">{{ lead.contact_name || '—' }}</td>
                            <td class="px-3 py-3" style="color:var(--body)" dir="ltr">{{ lead.whatsapp }}</td>
                            <td class="px-3 py-3" style="color:var(--body)">{{ lead.city || '—' }}</td>
                            <td class="px-3 py-3"><span class="badge" :class="badgeClass[lead.status]">{{ t('leads.status.' + lead.status) }}</span></td>
                            <td class="px-5 py-3 text-end whitespace-nowrap" style="color:var(--muted)">{{ fmtDate(lead.created_at) }}</td>
                        </tr>
                    </tbody>
                </table>
            </div>
        </div>

        <!-- Lead detail / editor -->
        <Modal v-if="active" :title="active.restaurant_name" :subtitle="t('leads.detail_sub')" @close="closeLead">
            <div class="space-y-4">
                <div class="grid grid-cols-2 gap-3 text-sm">
                    <div><div class="label">{{ t('leads.contact') }}</div><div style="color:var(--ink)">{{ active.contact_name || '—' }}</div></div>
                    <div><div class="label">{{ t('leads.whatsapp') }}</div><div style="color:var(--ink)" dir="ltr">{{ active.whatsapp }}</div></div>
                    <div><div class="label">{{ t('leads.city') }}</div><div style="color:var(--ink)">{{ active.city || '—' }}</div></div>
                    <div><div class="label">{{ t('leads.business') }}</div><div style="color:var(--ink)">{{ active.business_type || '—' }}</div></div>
                    <div class="col-span-2"><div class="label">{{ t('leads.source') }}</div><div style="color:var(--ink)">{{ active.source || '—' }}</div></div>
                </div>
                <div v-if="active.message">
                    <div class="label">{{ t('leads.message') }}</div>
                    <p class="text-sm mt-1" style="color:var(--body)">{{ active.message }}</p>
                </div>

                <a v-if="active.whatsapp" :href="`https://wa.me/${active.whatsapp.replace(/[^0-9]/g, '')}`" target="_blank" rel="noopener"
                    class="btn btn-ghost btn-sm" style="color:var(--green)">{{ t('leads.open_whatsapp') }}</a>

                <hr style="border-color:var(--line)" />

                <label class="block">
                    <span class="label">{{ t('common.status') }}</span>
                    <select v-model="editStatus" class="input mt-1.5">
                        <option v-for="s in STATUSES" :key="s" :value="s">{{ t('leads.status.' + s) }}</option>
                    </select>
                </label>
                <label class="block">
                    <span class="label">{{ t('leads.notes') }}</span>
                    <textarea v-model="editNotes" rows="4" class="input mt-1.5" :placeholder="t('leads.notes_hint')"></textarea>
                </label>

                <div class="flex justify-end gap-2 pt-2">
                    <button class="btn btn-ghost" @click="closeLead">{{ t('common.cancel') }}</button>
                    <button class="btn btn-accent" :disabled="saving" @click="saveLead">{{ saving ? t('common.saving') : t('common.save') }}</button>
                </div>
            </div>
        </Modal>
    </div>
</template>

<style scoped>
.chip { display: inline-flex; align-items: center; gap: 7px; padding: 7px 14px; border-radius: 20px;
    border: 1px solid var(--line); background: var(--card); color: var(--body); font-size: 13.5px; font-weight: 600; cursor: pointer; }
.chip-on { background: var(--accent); color: #fff; border-color: var(--accent); }
.chip-count { font-size: 11.5px; opacity: .8; }
.btn-sm { padding: 5px 11px; font-size: 12px; }
</style>
