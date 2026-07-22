<script setup>
import { ref, onMounted } from 'vue'
import { useRouter, RouterLink } from 'vue-router'
import { useI18n } from 'vue-i18n'
import api from '@xorder/api-client/api.js'
import { localizedInitial, pickLocalized } from '@xorder/ui/localize.js'
import Icon from '@xorder/ui/Icon.vue'
import StatusBadge from '@xorder/ui/StatusBadge.vue'

const router = useRouter()
const { t, locale } = useI18n()
const loading = ref(true)
const total = ref(0)
const byStatus = ref({ ACTIVE: 0, SUSPENDED: 0, ARCHIVED: 0 })
const recent = ref([])

onMounted(async () => {
    try {
        const all = await api.get('api/admin/restaurants')
        total.value = all.data.meta?.total ?? all.data.data.length
        recent.value = all.data.data.slice(0, 6)
        const results = await Promise.all(
            ['ACTIVE', 'SUSPENDED', 'ARCHIVED'].map(s =>
                api.get('api/admin/restaurants', { params: { status: s } })
                    .then(r => [s, r.data.meta?.total ?? r.data.data.length])),
        )
        byStatus.value = Object.fromEntries(results)
    } finally {
        loading.value = false
    }
})

const palette = ['#3d4a7a', '#1f7a3d', '#b8431f', '#a9711a', '#6b748c', '#2f3a63']
const avatarColor = (r) => palette[r.id % palette.length]
const restaurantName = (r) => pickLocalized(r, 'name', locale.value)
const initial = (r) => localizedInitial(r, 'name', locale.value)
const fmtDate = (d) => d ? new Date(d).toLocaleDateString(locale.value, { month: 'short', day: 'numeric' }) : ''
</script>

<template>
    <div v-if="!loading" class="space-y-6">
        <!-- Header -->
        <div class="flex flex-wrap items-start justify-between gap-3">
            <div>
                <h1 class="page-title">{{ t('admin.overview') }}</h1>
                <p class="page-sub">{{ t('admin.restaurants_subtitle') }}</p>
            </div>
            <RouterLink :to="{ name: 'admin.restaurants.create' }" class="btn btn-accent"><Icon name="plus" :size="16" />{{ t('admin.create_restaurant') }}</RouterLink>
        </div>

        <!-- Stat cards -->
        <div class="grid grid-cols-2 lg:grid-cols-4 gap-4">
            <div class="stat flex items-center gap-3.5">
                <span class="stat-ico"><Icon name="building" :size="20" /></span>
                <div>
                    <div class="stat-num" style="font-size:26px">{{ total }}</div>
                    <div class="stat-label">{{ t('admin.total_restaurants') }}</div>
                </div>
            </div>
            <div class="stat flex items-center gap-3.5">
                <span class="stat-ico" style="background:var(--green-soft);color:var(--green)"><Icon name="check" :size="20" /></span>
                <div>
                    <div class="stat-num" style="font-size:26px;color:var(--green)">{{ byStatus.ACTIVE }}</div>
                    <div class="stat-label">{{ t('common.active') }}</div>
                </div>
            </div>
            <div class="stat flex items-center gap-3.5">
                <span class="stat-ico" style="background:var(--red-soft);color:var(--red)"><Icon name="close" :size="20" /></span>
                <div>
                    <div class="stat-num" style="font-size:26px;color:var(--red)">{{ byStatus.SUSPENDED }}</div>
                    <div class="stat-label">{{ t('common.suspended') }}</div>
                </div>
            </div>
            <div class="stat flex items-center gap-3.5">
                <span class="stat-ico" style="background:var(--gray-soft);color:var(--gray)"><Icon name="categories" :size="20" /></span>
                <div>
                    <div class="stat-num" style="font-size:26px;color:var(--gray)">{{ byStatus.ARCHIVED }}</div>
                    <div class="stat-label">{{ t('common.archived') }}</div>
                </div>
            </div>
        </div>

        <!-- Recent + quick actions -->
        <div class="grid gap-6 lg:grid-cols-3 items-start">
            <!-- Recent restaurants -->
            <div class="lg:col-span-2 card p-5">
                <div class="flex items-center justify-between mb-1">
                    <h2 class="h-card flex items-center gap-2"><Icon name="building" :size="16" style="color:var(--muted)" />{{ t('admin.recent_restaurants') }}</h2>
                    <RouterLink :to="{ name: 'admin.restaurants' }" class="text-sm flex items-center gap-1" style="color:var(--accent)">{{ t('common.view_all') }}<Icon name="chevronDown" :size="14" style="transform:rotate(-90deg)" /></RouterLink>
                </div>
                <ul v-if="recent.length">
                    <li v-for="r in recent" :key="r.id"
                        class="flex items-center gap-3 py-2.5 border-t first:border-t-0 cursor-pointer rounded-lg hover:bg-black/[.02]"
                        style="border-color:var(--line)"
                        @click="router.push({ name: 'admin.restaurants.show', params: { id: r.id } })">
                        <span class="grid place-items-center text-white font-semibold flex-shrink-0"
                            style="width:38px;height:38px;border-radius:9px;font-family:var(--font-display)"
                            :style="{ background: avatarColor(r) }">{{ initial(r) }}</span>
                        <div class="min-w-0 flex-1">
                            <div class="font-medium truncate" style="color:var(--ink)">{{ restaurantName(r) }}</div>
                        </div>
                        <span class="text-xs hidden sm:block" style="color:var(--muted)">{{ t('admin.item_count', { count: r.menu_items_count ?? 0 }) }}</span>
                        <StatusBadge :value="r.status" />
                        <span class="text-xs hidden sm:block" style="color:var(--muted)">{{ fmtDate(r.created_at) }}</span>
                    </li>
                </ul>
                <p v-else class="text-sm py-6 text-center" style="color:var(--muted)">{{ t('admin.no_restaurants') }}</p>
            </div>

            <!-- Quick actions -->
            <div class="card p-5">
                <h2 class="h-card mb-3">{{ t('stats.quick_actions') }}</h2>
                <div class="flex flex-col gap-2">
                    <RouterLink :to="{ name: 'admin.restaurants.create' }" class="btn btn-accent justify-start"><Icon name="plus" :size="16" />{{ t('admin.create_restaurant') }}</RouterLink>
                    <RouterLink :to="{ name: 'admin.restaurants' }" class="btn btn-ghost justify-start"><Icon name="building" :size="16" />{{ t('admin.manage_restaurants') }}</RouterLink>
                </div>
            </div>
        </div>
    </div>

    <!-- Loading skeleton -->
    <div v-else class="space-y-6">
        <div class="h-8 w-44 rounded-lg" style="background:var(--line)"></div>
        <div class="grid grid-cols-2 lg:grid-cols-4 gap-4">
            <div v-for="n in 4" :key="n" class="stat" style="height:74px"></div>
        </div>
        <div class="grid gap-6 lg:grid-cols-3">
            <div class="lg:col-span-2 card" style="height:300px"></div>
            <div class="card" style="height:300px"></div>
        </div>
    </div>
</template>
