<script setup>
import { ref, onMounted } from 'vue'
import { RouterLink } from 'vue-router'
import api from '../../lib/api'

const total = ref(null)
const byStatus = ref({ ACTIVE: 0, SUSPENDED: 0, ARCHIVED: 0 })

onMounted(async () => {
    const { data } = await api.get('api/admin/restaurants', { params: { per_page: 1 } })
    total.value = data.meta?.total ?? data.data?.length ?? 0
    for (const s of ['ACTIVE', 'SUSPENDED', 'ARCHIVED']) {
        const r = await api.get('api/admin/restaurants', { params: { status: s } })
        byStatus.value[s] = r.data.meta?.total ?? r.data.data.length
    }
})
</script>

<template>
    <div class="space-y-6">
        <div class="flex items-start justify-between gap-3">
            <div>
                <h1 class="page-title">Overview</h1>
                <p class="page-sub">Onboard and manage every tenant.</p>
            </div>
            <RouterLink :to="{ name: 'admin.restaurants.create' }" class="btn btn-accent">+ Create restaurant</RouterLink>
        </div>

        <div class="grid grid-cols-2 lg:grid-cols-4 gap-4">
            <div class="stat">
                <div class="stat-label">Total restaurants</div>
                <div class="stat-num">{{ total ?? '—' }}</div>
            </div>
            <div class="stat">
                <div class="stat-label">Active</div>
                <div class="stat-num" style="color:var(--green)">{{ byStatus.ACTIVE }}</div>
            </div>
            <div class="stat">
                <div class="stat-label">Suspended</div>
                <div class="stat-num" style="color:#c0392b">{{ byStatus.SUSPENDED }}</div>
            </div>
            <div class="stat">
                <div class="stat-label">Archived</div>
                <div class="stat-num" style="color:var(--muted)">{{ byStatus.ARCHIVED }}</div>
            </div>
        </div>

        <RouterLink :to="{ name: 'admin.restaurants' }" class="inline-block text-sm underline" style="color:var(--accent)">
            Manage all restaurants →
        </RouterLink>
    </div>
</template>
