<script setup>
import { ref, computed, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import Icon from '@xorder/ui/Icon.vue'
import Modal from '@xorder/ui/Modal.vue'
import Skeleton from '@xorder/ui/Skeleton.vue'

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
    <div class="space-y-5">
        <!-- Header -->
        <div class="flex items-start justify-between gap-3 flex-wrap">
            <div>
                <h1 class="page-title">{{ t('leads.title') }}</h1>
                <p class="page-sub" style="color:var(--body)">{{ t('leads.subtitle', { n: total }) }}</p>
            </div>
            <a :href="exportHref" target="_blank" rel="noopener" class="btn btn-ghost cta">
                <Icon name="download" :size="16" />{{ t('leads.export') }}
            </a>
        </div>

        <!-- Pipeline filter: status chips with counts -->
        <div class="flex items-center gap-2 flex-wrap" role="group" :aria-label="t('common.status')">
            <button type="button" class="chip" :class="{ 'chip-on': statusFilter === '' }" :aria-pressed="statusFilter === ''" @click="setFilter('')">
                {{ t('common.all') }} <span class="chip-count">{{ total }}</span>
            </button>
            <button v-for="s in STATUSES" :key="s" type="button" class="chip" :class="{ 'chip-on': statusFilter === s }" :aria-pressed="statusFilter === s" @click="setFilter(s)">
                {{ t('leads.status.' + s) }} <span v-if="counts[s]" class="chip-count">{{ counts[s] }}</span>
            </button>
        </div>

        <form class="flex items-center gap-2" role="search" @submit.prevent="load">
            <div class="search">
                <Icon name="search" :size="16" class="search-ico" aria-hidden="true" />
                <input v-model="search" type="search" class="input search-input" :placeholder="t('leads.search')" :aria-label="t('leads.search')" />
            </div>
            <button type="submit" class="btn btn-ghost cta">{{ t('common.search') }}</button>
        </form>

        <!-- List -->
        <div class="card list-card">
            <div class="list-scroll">
                <div class="list-inner">
                    <div class="r-grid r-head" aria-hidden="true">
                        <span class="c-idx">#</span>
                        <span class="c-name">{{ t('leads.restaurant') }}</span>
                        <span class="c-contact">{{ t('leads.contact') }}</span>
                        <span class="c-wa">{{ t('leads.whatsapp') }}</span>
                        <span class="c-city">{{ t('leads.city') }}</span>
                        <span class="c-status">{{ t('common.status') }}</span>
                        <span class="c-created">{{ t('leads.created') }}</span>
                    </div>

                    <div v-if="loading" aria-hidden="true">
                        <div v-for="n in 6" :key="n" class="r-grid r-row">
                            <span class="c-idx"><Skeleton w="18px" h="12px" /></span>
                            <span class="c-name"><Skeleton w="60%" h="13px" /></span>
                            <span class="c-contact"><Skeleton w="70%" h="13px" /></span>
                            <span class="c-wa"><Skeleton w="90px" h="13px" /></span>
                            <span class="c-city"><Skeleton w="60%" h="13px" /></span>
                            <span class="c-status"><Skeleton w="84px" h="22px" rounded="999px" /></span>
                            <span class="c-created"><Skeleton w="70px" h="13px" /></span>
                        </div>
                    </div>

                    <div v-else-if="!rows.length" class="empty">
                        <span class="empty-ico"><Icon name="search" :size="22" /></span>
                        <p>{{ t('leads.none') }}</p>
                    </div>

                    <ul v-else>
                        <li v-for="(lead, idx) in rows" :key="lead.id" class="r-grid r-row r-link" @click="openLead(lead)">
                            <span class="c-idx num">{{ idx + 1 }}</span>
                            <span class="c-name min-w-0">
                                <button type="button" class="row-name truncate" @click.stop="openLead(lead)">{{ lead.restaurant_name }}</button>
                            </span>
                            <span class="c-contact truncate">{{ lead.contact_name || '—' }}</span>
                            <span class="c-wa" dir="ltr">{{ lead.whatsapp }}</span>
                            <span class="c-city truncate">{{ lead.city || '—' }}</span>
                            <span class="c-status"><span class="badge" :class="badgeClass[lead.status]">{{ t('leads.status.' + lead.status) }}</span></span>
                            <span class="c-created">{{ fmtDate(lead.created_at) }}</span>
                        </li>
                    </ul>
                </div>
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
                    class="btn btn-ghost cta" style="color:var(--green)">{{ t('leads.open_whatsapp') }}</a>

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
                    <button class="btn btn-ghost cta" @click="closeLead">{{ t('common.cancel') }}</button>
                    <button class="btn btn-accent cta" :disabled="saving" @click="saveLead">{{ saving ? t('common.saving') : t('common.save') }}</button>
                </div>
            </div>
        </Modal>
    </div>
</template>

<style scoped>
.badge.badge-amber { color: var(--p-primary-800); }
.badge.badge-gray { color: var(--body); }
.cta { min-height: 44px; justify-content: center; }

.chip { display: inline-flex; align-items: center; gap: 7px; min-height: 40px; padding: 6px 14px; border-radius: 20px;
    border: 1px solid var(--line); background: var(--card); color: var(--body); font-size: 14px; font-weight: 600; cursor: pointer;
    transition: border-color .15s; }
.chip:hover { border-color: var(--muted); }
.chip-on, .chip-on:hover { background: var(--ink); color: var(--card); border-color: var(--ink); }
.chip-count { font-size: 12.5px; font-weight: 600; opacity: .85; }

.search { position: relative; flex: 1 1 auto; max-width: 420px; }
.search-ico { position: absolute; inset-inline-start: 13px; top: 50%; transform: translateY(-50%); color: var(--body); pointer-events: none; }
.search-input { margin-top: 0; padding-inline-start: 38px; min-height: 44px; }

.list-card { overflow: hidden; }
.list-scroll { overflow-x: auto; }
.list-inner { min-width: 860px; }
.r-grid { display: grid; align-items: center; column-gap: 14px; padding: 0 20px;
    grid-template-columns: 30px minmax(0, 1.8fr) minmax(0, 1.3fr) 150px minmax(0, 1fr) 130px 100px; }
.r-head { padding-block: 11px; background: var(--page); border-bottom: 1px solid var(--line); font-size: 12.5px; font-weight: 600; color: var(--body); }
.r-row { padding-block: 12px; min-height: 56px; border-top: 1px solid var(--line); font-size: 14.5px; color: var(--body); }
ul > .r-row:first-child { border-top: none; }
.r-link { cursor: pointer; transition: background .15s; }
.r-link:hover { background: var(--page); }
.r-link:hover .row-name { color: var(--p-primary-700); }
.c-idx { text-align: end; color: var(--body); font-size: 14px; }
.c-created { text-align: end; white-space: nowrap; }
.num { font-variant-numeric: tabular-nums; }
.row-name { display: block; max-width: 100%; text-align: start; background: none; border: 0; padding: 0; cursor: pointer;
    font-size: 15px; font-weight: 600; color: var(--ink); }

.empty { display: flex; flex-direction: column; align-items: center; gap: 12px; padding: 48px 20px; text-align: center; color: var(--body); }
.empty-ico { width: 48px; height: 48px; border-radius: 14px; display: grid; place-items: center; background: var(--accent-soft); color: var(--p-primary-700); }

@media (max-width: 820px) {
    .list-inner { min-width: 0; }
    .r-head { display: none; }
    .r-grid { grid-template-columns: minmax(0, 1fr) auto; row-gap: 6px; padding: 14px 16px; align-items: start;
        grid-template-areas: "name status" "contact wa" "city created"; }
    .r-row { min-height: 0; }
    .c-idx { display: none; }
    .c-name { grid-area: name; }
    .c-status { grid-area: status; }
    .c-contact { grid-area: contact; }
    .c-wa { grid-area: wa; text-align: end; }
    .c-city { grid-area: city; }
    .c-created { grid-area: created; }
    .search { max-width: none; }
}
</style>
