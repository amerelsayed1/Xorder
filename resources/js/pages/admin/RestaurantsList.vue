<script setup>
import { ref, onMounted, watch } from 'vue'
import { useRouter, RouterLink } from 'vue-router'
import api from '../../lib/api'
import StatusBadge from '../../components/StatusBadge.vue'

const router = useRouter()
const rows = ref([])
const loading = ref(true)
const search = ref('')
const status = ref('')
const counts = ref({ ALL: 0, ACTIVE: 0, SUSPENDED: 0, ARCHIVED: 0 })

let timer
async function load() {
    loading.value = true
    const { data } = await api.get('api/admin/restaurants', {
        params: { search: search.value || undefined, status: status.value || undefined },
    })
    rows.value = data.data
    loading.value = false
}
async function loadCounts() {
    const all = await api.get('api/admin/restaurants')
    counts.value.ALL = all.data.meta?.total ?? all.data.data.length
    for (const s of ['ACTIVE', 'SUSPENDED', 'ARCHIVED']) {
        const r = await api.get('api/admin/restaurants', { params: { status: s } })
        counts.value[s] = r.data.meta?.total ?? r.data.data.length
    }
}
onMounted(() => { load(); loadCounts() })
watch([search, status], () => { clearTimeout(timer); timer = setTimeout(load, 250) })

const palette = ['#b8431f', '#1f7a3d', '#3d4a7a', '#a9711a', '#6b748c', '#9a3717']
const avatarColor = (r) => palette[r.id % palette.length]
const initial = (r) => (r.name_en || r.name_ar || '?').trim().charAt(0).toUpperCase()
const fmtDate = (d) => d ? new Date(d).toLocaleDateString('en-US', { year: 'numeric', month: 'short', day: 'numeric' }) : ''
const subBadge = (s) => ({ ACTIVE: 'badge-indigo', TRIAL: 'badge-amber', EXPIRED: 'badge-red', SUSPENDED: 'badge-gray' }[s] || 'badge-gray')
const subLabel = (r) => r.subscription_status === 'ACTIVE' ? `${r.subscription_plan || 'Pro'} · Active` : r.subscription_status
const filters = [['', 'All'], ['ACTIVE', 'Active'], ['SUSPENDED', 'Suspended'], ['ARCHIVED', 'Archived']]
const countFor = (k) => k === '' ? counts.value.ALL : counts.value[k]
</script>

<template>
    <div class="space-y-5">
        <div class="flex items-start justify-between gap-3">
            <div>
                <h1 class="page-title">Restaurants</h1>
                <p class="page-sub">Onboard and manage every tenant.</p>
            </div>
            <RouterLink :to="{ name: 'admin.restaurants.create' }" class="btn btn-accent">+ Create restaurant</RouterLink>
        </div>

        <!-- Toolbar -->
        <div class="flex flex-wrap items-center gap-3">
            <input v-model="search" placeholder="Search by name or slug…" class="input" style="max-width:340px" />
            <div class="segmented overflow-x-auto">
                <button v-for="[val, label] in filters" :key="val" :class="{ active: status === val }" @click="status = val">
                    {{ label }}<span v-if="countFor(val) != null" style="opacity:.6"> ({{ countFor(val) }})</span>
                </button>
            </div>
        </div>

        <!-- Table -->
        <div class="card overflow-x-auto">
            <table class="w-full text-sm" style="min-width:720px">
                <thead>
                    <tr class="text-left" style="color:var(--muted)">
                        <th class="px-5 py-3 font-medium" style="font-size:11px;letter-spacing:.06em;text-transform:uppercase">Restaurant</th>
                        <th class="px-3 py-3 font-medium" style="font-size:11px;text-transform:uppercase">Status</th>
                        <th class="px-3 py-3 font-medium" style="font-size:11px;text-transform:uppercase">Subscription</th>
                        <th class="px-3 py-3 font-medium" style="font-size:11px;text-transform:uppercase">Items</th>
                        <th class="px-3 py-3 font-medium" style="font-size:11px;text-transform:uppercase">Created</th>
                        <th class="px-5 py-3 font-medium text-end" style="font-size:11px;text-transform:uppercase">Actions</th>
                    </tr>
                </thead>
                <tbody>
                    <tr v-if="loading"><td colspan="6" class="px-5 py-8 text-center" style="color:var(--muted)">Loading…</td></tr>
                    <tr v-else-if="!rows.length"><td colspan="6" class="px-5 py-8 text-center" style="color:var(--muted)">No restaurants.</td></tr>
                    <tr v-for="r in rows" :key="r.id" class="border-t cursor-pointer hover:bg-black/[.015]"
                        :style="{ borderColor: 'var(--line)', opacity: r.status === 'ARCHIVED' ? 0.6 : 1 }"
                        @click="router.push({ name: 'admin.restaurants.show', params: { id: r.id } })">
                        <td class="px-5 py-3">
                            <div class="flex items-center gap-3">
                                <span class="grid place-items-center text-white font-semibold flex-shrink-0"
                                    style="width:38px;height:38px;border-radius:9px;font-family:var(--font-display)"
                                    :style="{ background: avatarColor(r) }">{{ initial(r) }}</span>
                                <div>
                                    <div class="font-medium" style="color:var(--ink)">{{ r.name_en || r.name_ar }}</div>
                                    <div class="mono text-xs" style="color:var(--muted)">/r/{{ r.slug }}</div>
                                </div>
                            </div>
                        </td>
                        <td class="px-3 py-3"><StatusBadge :value="r.status" /></td>
                        <td class="px-3 py-3"><span class="badge" :class="subBadge(r.subscription_status)">{{ subLabel(r) }}</span></td>
                        <td class="px-3 py-3 font-medium" style="color:var(--ink)">{{ r.menu_items_count ?? '—' }}</td>
                        <td class="px-3 py-3" style="color:var(--body)">{{ fmtDate(r.created_at) }}</td>
                        <td class="px-5 py-3 text-end whitespace-nowrap" @click.stop>
                            <RouterLink :to="{ name: 'admin.restaurants.show', params: { id: r.id } }" class="btn btn-ghost" style="padding:5px 11px;font-size:12px">QR</RouterLink>
                            <RouterLink :to="{ name: 'admin.restaurants.edit', params: { id: r.id } }" class="btn btn-ghost ms-2" style="padding:5px 11px;font-size:12px">Edit</RouterLink>
                        </td>
                    </tr>
                </tbody>
            </table>
        </div>
    </div>
</template>
