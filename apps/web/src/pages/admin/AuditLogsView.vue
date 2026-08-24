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
    <div class="portal theme-indigo">
        <div class="max-w-5xl mx-auto px-5 py-7 space-y-5">
            <!-- Header -->
            <div>
                <h1 class="page-title">{{ t('audit.title') }}</h1>
                <p class="page-sub">{{ t('audit.subtitle', { n: total }) }}</p>
            </div>

            <!-- Filters -->
            <div class="card p-4 space-y-3">
                <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
                    <label class="block">
                        <span class="label">{{ t('audit.tenant') }}</span>
                        <select v-model="filters.restaurant_id" class="input" @change="applyFilters">
                            <option value="">{{ t('audit.all_tenants') }}</option>
                            <option v-for="tn in opts.tenants" :key="tn.id" :value="tn.id">{{ tn.name }}</option>
                        </select>
                    </label>
                    <label class="block">
                        <span class="label">{{ t('audit.client') }}</span>
                        <select v-model="filters.actor_id" class="input" @change="applyFilters">
                            <option value="">{{ t('audit.all_clients') }}</option>
                            <option v-for="ac in opts.actors" :key="ac.id" :value="ac.id">
                                {{ ac.name }}<template v-if="ac.role"> — {{ roleLabel(ac.role) }}</template>
                            </option>
                        </select>
                    </label>
                    <label class="block">
                        <span class="label">{{ t('audit.category') }}</span>
                        <select v-model="filters.category" class="input" @change="applyFilters">
                            <option value="">{{ t('audit.all_categories') }}</option>
                            <option v-for="c in opts.categories" :key="c" :value="c">{{ catLabel(c) }}</option>
                        </select>
                    </label>
                    <label class="block">
                        <span class="label">{{ t('audit.from') }}</span>
                        <input v-model="filters.from" type="date" class="input" @change="applyFilters" />
                    </label>
                    <label class="block">
                        <span class="label">{{ t('audit.to') }}</span>
                        <input v-model="filters.to" type="date" class="input" @change="applyFilters" />
                    </label>
                    <label class="block">
                        <span class="label">{{ t('audit.details') }}</span>
                        <input v-model="filters.search" class="input" :placeholder="t('audit.search')" @keyup.enter="applyFilters" />
                    </label>
                </div>
                <div class="flex justify-end">
                    <button class="btn btn-ghost btn-sm" @click="clearFilters"><Icon name="x" :size="14" />{{ t('audit.clear') }}</button>
                </div>
            </div>

            <!-- Daily log files — the trail is stored as one file per day -->
            <ActivityFilesPanel :active-date="activeDay" @select="showDay" />

            <!-- Feed -->
            <div class="card p-4">
                <AuditLogList :rows="rows" :loading="loading" :show-tenant="true" />
            </div>

            <!-- Pagination -->
            <div v-if="lastPage > 1" class="flex items-center justify-center gap-3">
                <button class="btn btn-ghost btn-sm" :disabled="page <= 1 || loading" @click="load(page - 1)">‹</button>
                <span class="text-sm" style="color:var(--muted)">{{ page }} / {{ lastPage }}</span>
                <button class="btn btn-ghost btn-sm" :disabled="page >= lastPage || loading" @click="load(page + 1)">›</button>
            </div>
        </div>
    </div>
</template>

<style scoped>
.btn-sm { padding: 5px 11px; font-size: 12px; }
</style>
