<script setup>
import { ref, computed, onMounted, watch } from 'vue'
import { useRouter, RouterLink } from 'vue-router'
import { useI18n } from 'vue-i18n'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import { localizedInitial, pickLocalized } from '@xorder/ui/localize.js'
import StatusBadge from '@xorder/ui/StatusBadge.vue'
import Icon from '@xorder/ui/Icon.vue'
import TableSkeleton from '@xorder/ui/TableSkeleton.vue'
import { confirm } from '@xorder/ui/confirm.js'

const router = useRouter()
const { t, locale } = useI18n()
const rows = ref([])
const loading = ref(true)
const search = ref('')
const status = ref('')
const page = ref(1)
const meta = ref(null)
const counts = ref({ ALL: 0, ACTIVE: 0, SUSPENDED: 0, ARCHIVED: 0 })

let timer
async function load() {
    loading.value = true
    try {
        const { data } = await api.get('api/admin/restaurants', {
            params: { search: search.value || undefined, status: status.value || undefined, page: page.value },
        })
        rows.value = data.data
        meta.value = data.meta || null
    } finally {
        loading.value = false
    }
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
watch([search, status], () => {
    clearTimeout(timer)
    timer = setTimeout(() => {
        page.value = 1
        load()
    }, 250)
})

const deleting = ref(null)
const archiving = ref(null)

async function archiveRestaurant(r) {
    const name = restaurantName(r)
    const ok = await confirm({
        title: t('admin.archive_title', { name }),
        message: t('admin.archive_message'),
        confirmText: t('admin.archive_confirm'),
        cancelText: t('common.cancel'),
    })
    if (!ok) return
    archiving.value = r.id
    try {
        await ensureCsrf()
        await api.patch(`api/admin/restaurants/${r.id}/status`, { status: 'ARCHIVED' })
        await Promise.all([load(), loadCounts()])
    } catch (err) {
        alert(t('admin.archive_failed'))
    } finally {
        archiving.value = null
    }
}

async function hardDeleteRestaurant(r) {
    const name = restaurantName(r)
    const ok = await confirm({
        title: t('admin.delete_title', { name }),
        message: t('admin.delete_message'),
        confirmText: t('admin.delete_confirm'),
        cancelText: t('common.cancel'),
        confirmationText: r.slug,
        confirmationLabel: t('admin.delete_confirmation_label', { slug: r.slug }),
        confirmationHint: t('admin.delete_confirmation_hint'),
        danger: true,
    })
    if (!ok) return
    deleting.value = r.id
    try {
        await ensureCsrf()
        await api.delete(`api/admin/restaurants/${r.id}`, { data: { confirmation: r.slug } })
        await Promise.all([load(), loadCounts()])
    } catch (err) {
        alert(t('admin.delete_failed'))
    } finally {
        deleting.value = null
    }
}

function goToPage(nextPage) {
    if (!meta.value || nextPage < 1 || nextPage > meta.value.last_page) return
    page.value = nextPage
    load()
}

const palette = ['#b8431f', '#1f7a3d', '#3d4a7a', '#a9711a', '#6b748c', '#9a3717']
const avatarColor = (r) => palette[r.id % palette.length]
const restaurantName = (r) => pickLocalized(r, 'name', locale.value)
const initial = (r) => localizedInitial(r, 'name', locale.value)
const fmtDate = (d) => d ? new Date(d).toLocaleDateString(locale.value, { year: 'numeric', month: 'short', day: 'numeric' }) : ''
const subBadge = (s) => ({ ACTIVE: 'badge-indigo', TRIAL: 'badge-amber', EXPIRED: 'badge-red', SUSPENDED: 'badge-gray' }[s] || 'badge-gray')
const subLabel = (r) => r.subscription_status === 'ACTIVE'
    ? `${r.subscription_plan || t('admin.default_plan')} · ${t('subscription_status.ACTIVE')}`
    : t('subscription_status.' + r.subscription_status)
const filters = computed(() => [
    ['', t('common.all')],
    ['ACTIVE', t('common.active')],
    ['SUSPENDED', t('common.suspended')],
    ['ARCHIVED', t('common.archived')],
])
const countFor = (k) => k === '' ? counts.value.ALL : counts.value[k]
</script>

<template>
    <div class="space-y-5">
        <div class="flex items-start justify-between gap-3">
            <div>
                <h1 class="page-title">{{ t('nav.restaurants') }}</h1>
                <p class="page-sub">{{ t('admin.restaurants_subtitle') }}</p>
            </div>
            <RouterLink :to="{ name: 'admin.restaurants.create' }" class="btn btn-accent"><Icon name="plus" :size="16" />{{ t('admin.create_restaurant') }}</RouterLink>
        </div>

        <!-- Toolbar -->
        <div class="flex flex-wrap items-center gap-3">
            <input v-model="search" :placeholder="t('admin.search_restaurants')" class="input" style="max-width:340px" />
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
                        <th class="px-5 py-3 font-medium" style="font-size:11px;letter-spacing:.06em;text-transform:uppercase">#</th>
                        <th class="px-5 py-3 font-medium" style="font-size:11px;letter-spacing:.06em;text-transform:uppercase">{{ t('admin.restaurant') }}</th>
                        <th class="px-3 py-3 font-medium" style="font-size:11px;text-transform:uppercase">{{ t('common.status') }}</th>
                        <th class="px-3 py-3 font-medium" style="font-size:11px;text-transform:uppercase">{{ t('restaurant.subscription') }}</th>
                        <th class="px-3 py-3 font-medium" style="font-size:11px;text-transform:uppercase">{{ t('nav.items') }}</th>
                        <th class="px-3 py-3 font-medium" style="font-size:11px;text-transform:uppercase">{{ t('admin.created') }}</th>
                        <th class="px-5 py-3 font-medium text-end" style="font-size:11px;text-transform:uppercase">{{ t('common.actions') }}</th>
                    </tr>
                </thead>
                <tbody>
                    <TableSkeleton v-if="loading" :cols="7" />
                    <tr v-else-if="!rows.length"><td colspan="7" class="px-5 py-8 text-center" style="color:var(--muted)">{{ t('admin.no_restaurants') }}</td></tr>
                    <tr v-for="(r, idx) in loading ? [] : rows" :key="r.id" class="border-t cursor-pointer hover:bg-black/[.015]"
                        :style="{ borderColor: 'var(--line)', opacity: r.status === 'ARCHIVED' ? 0.6 : 1 }"
                        @click="router.push({ name: 'admin.restaurants.show', params: { id: r.id } })">
                        <td class="px-5 py-3" style="color:var(--muted)">{{ (meta?.from || 1) + idx }}</td>
                        <td class="px-5 py-3">
                            <div class="flex items-center gap-3">
                                <span class="grid place-items-center text-white font-semibold flex-shrink-0"
                                    style="width:38px;height:38px;border-radius:9px;font-family:var(--font-display)"
                                    :style="{ background: avatarColor(r) }">{{ initial(r) }}</span>
                                <div>
                                    <div class="font-medium" style="color:var(--ink)">{{ restaurantName(r) }}</div>
                                </div>
                            </div>
                        </td>
                        <td class="px-3 py-3"><StatusBadge :value="r.status" /></td>
                        <td class="px-3 py-3"><span class="badge" :class="subBadge(r.subscription_status)">{{ subLabel(r) }}</span></td>
                        <td class="px-3 py-3 font-medium" style="color:var(--ink)">{{ r.menu_items_count ?? '—' }}</td>
                        <td class="px-3 py-3" style="color:var(--body)">{{ fmtDate(r.created_at) }}</td>
                        <td class="px-5 py-3 text-end whitespace-nowrap" @click.stop>
                            <div class="inline-flex items-center gap-2">
                                <RouterLink :to="{ name: 'admin.restaurants.show', params: { id: r.id } }" class="btn btn-ghost" style="padding:5px 11px;font-size:12px">{{ t('nav.qr') }}</RouterLink>
                                <RouterLink :to="{ name: 'admin.restaurants.edit', params: { id: r.id } }" class="btn btn-ghost" style="padding:5px 11px;font-size:12px">{{ t('common.edit') }}</RouterLink>
                                <button
                                    v-if="r.status !== 'ARCHIVED'"
                                    @click="archiveRestaurant(r)"
                                    :disabled="archiving === r.id"
                                    class="btn btn-ghost"
                                    style="padding:5px 11px;font-size:12px"
                                >{{ archiving === r.id ? t('admin.archiving') : t('common.archive') }}</button>
                                <button
                                    v-else
                                    @click="hardDeleteRestaurant(r)"
                                    :disabled="deleting === r.id"
                                    class="icon-btn icon-btn-danger"
                                    :title="t('admin.delete_restaurant')"
                                    :aria-label="t('admin.delete_restaurant')"
                                ><Icon name="trash" :size="16" /></button>
                            </div>
                        </td>
                    </tr>
                </tbody>
            </table>
        </div>

        <div v-if="meta && meta.last_page > 1" class="flex flex-wrap items-center justify-between gap-3">
            <p class="text-sm" style="color:var(--muted)">
                {{ t('common.showing_range', { from: meta.from, to: meta.to, total: meta.total }) }}
            </p>
            <div class="inline-flex items-center gap-2">
                <button class="btn btn-ghost btn-sm" :disabled="meta.current_page <= 1" @click="goToPage(meta.current_page - 1)">
                    {{ t('common.previous') }}
                </button>
                <span class="text-sm" style="color:var(--muted)">{{ meta.current_page }} / {{ meta.last_page }}</span>
                <button class="btn btn-ghost btn-sm" :disabled="meta.current_page >= meta.last_page" @click="goToPage(meta.current_page + 1)">
                    {{ t('common.next') }}
                </button>
            </div>
        </div>
    </div>
</template>
