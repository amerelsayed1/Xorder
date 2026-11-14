<script setup>
import { ref, reactive, computed, onMounted } from 'vue'
import { useRoute } from 'vue-router'
import { useI18n } from 'vue-i18n'
import api from '@xorder/api-client/api.js'
import Icon from '@xorder/ui/Icon.vue'
import AuditLogList from '../../components/AuditLogList.vue'
import ActivityFilesPanel from '../../components/ActivityFilesPanel.vue'

const { t } = useI18n()
const route = useRoute()

const rows = ref([])
const loading = ref(true)
const total = ref(0)
const page = ref(1)
const lastPage = ref(1)

const opts = reactive({ tenants: [], actors: [], categories: [] })
const filters = reactive({
    restaurant_id: route.query.restaurant_id || '',
    actor_id: '',
    category: '',
    search: '',
    // Arriving from a restaurant's Activity tab pins the range to one day.
    from: route.query.from || '',
    to: route.query.to || '',
})

async function loadOptions() {
    const { data } = await api.get('api/admin/audit-logs/filters')
    opts.tenants = data.data.tenants
    opts.actors = data.data.actors
    opts.categories = data.data.categories
}

const activeDay = computed(() => (filters.from && filters.from === filters.to ? filters.from : ''))

// Clicking a day narrows the feed to it rather than navigating away.
function showDay(date) {
    filters.from = date
    filters.to = date
    load(1)
}


async function load(toPage = 1) {
    loading.value = true
    page.value = toPage
    try {
        const params = { page: toPage, per_page: 30 }
        for (const [k, v] of Object.entries(filters)) if (v) params[k] = v
        const { data } = await api.get('api/admin/audit-logs', { params })
        rows.value = data.data
        total.value = data.meta?.total ?? data.data.length
        lastPage.value = data.meta?.last_page ?? 1
    } finally {
        loading.value = false
    }
}

function applyFilters() { load(1) }
function clearFilters() {
    Object.assign(filters, { restaurant_id: '', actor_id: '', category: '', search: '', from: '', to: '' })
    load(1)
}

onMounted(async () => { await loadOptions(); await load(1) })

const roleLabel = (role) => role ? (t(`audit.role.${role}`) === `audit.role.${role}` ? role : t(`audit.role.${role}`)) : ''
const catLabel = (cat) => t(`audit.cat.${cat}`) === `audit.cat.${cat}` ? cat : t(`audit.cat.${cat}`)
</script>

<template>
    <div class="space-y-5">
        <!-- Header -->
        <div>
            <h1 class="page-title">{{ t('audit.title') }}</h1>
            <p class="page-sub" style="color:var(--body)">{{ t('audit.subtitle', { n: total }) }}</p>
        </div>

        <!-- Filters: who/where first, then when, then free text -->
        <section class="card p-4 space-y-3" role="search" :aria-label="t('audit.title')">
            <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
                <label class="block">
                    <span class="label">{{ t('audit.tenant') }}</span>
                    <select v-model="filters.restaurant_id" class="input fld" @change="applyFilters">
                        <option value="">{{ t('audit.all_tenants') }}</option>
                        <option v-for="tn in opts.tenants" :key="tn.id" :value="tn.id">{{ tn.name }}</option>
                    </select>
                </label>
                <label class="block">
                    <span class="label">{{ t('audit.client') }}</span>
                    <select v-model="filters.actor_id" class="input fld" @change="applyFilters">
                        <option value="">{{ t('audit.all_clients') }}</option>
                        <option v-for="ac in opts.actors" :key="ac.id" :value="ac.id">
                            {{ ac.name }}<template v-if="ac.role"> — {{ roleLabel(ac.role) }}</template>
                        </option>
                    </select>
                </label>
                <label class="block">
                    <span class="label">{{ t('audit.category') }}</span>
                    <select v-model="filters.category" class="input fld" @change="applyFilters">
                        <option value="">{{ t('audit.all_categories') }}</option>
                        <option v-for="c in opts.categories" :key="c" :value="c">{{ catLabel(c) }}</option>
                    </select>
                </label>
                <label class="block">
                    <span class="label">{{ t('audit.from') }}</span>
                    <input v-model="filters.from" type="date" class="input fld" @change="applyFilters" />
                </label>
                <label class="block">
                    <span class="label">{{ t('audit.to') }}</span>
                    <input v-model="filters.to" type="date" class="input fld" @change="applyFilters" />
                </label>
                <label class="block">
                    <span class="label">{{ t('audit.details') }}</span>
                    <input v-model="filters.search" class="input fld" :placeholder="t('audit.search')" @keyup.enter="applyFilters" />
                </label>
            </div>
            <div class="flex justify-end">
                <button type="button" class="btn btn-ghost btn-sm clear" @click="clearFilters"><Icon name="close" :size="14" />{{ t('audit.clear') }}</button>
            </div>
        </section>

        <!-- Daily log files — the trail is stored as one file per day -->
        <ActivityFilesPanel :active-date="activeDay" @select="showDay" />

        <!-- Feed -->
        <section class="card p-4" :aria-busy="loading" :aria-label="t('audit.title')">
            <AuditLogList :rows="rows" :loading="loading" :show-tenant="true" />
        </section>

        <!-- Pagination -->
        <nav v-if="lastPage > 1" class="flex items-center justify-center gap-3" :aria-label="t('audit.title')">
            <button type="button" class="btn btn-ghost pager" :disabled="page <= 1 || loading" :aria-label="t('common.previous')" @click="load(page - 1)">‹</button>
            <span class="text-sm" style="color:var(--body)">{{ page }} / {{ lastPage }}</span>
            <button type="button" class="btn btn-ghost pager" :disabled="page >= lastPage || loading" :aria-label="t('common.next')" @click="load(page + 1)">›</button>
        </nav>
    </div>
</template>

<style scoped>
.fld { min-height: 44px; }
.clear { min-height: 36px; }
.pager { min-width: 44px; min-height: 44px; justify-content: center; font-size: 18px; }
</style>
