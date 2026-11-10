<script setup>
import { ref, computed, onMounted, watch } from 'vue'
import { useRouter, RouterLink } from 'vue-router'
import { useI18n } from 'vue-i18n'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import { localizedInitial, pickLocalized } from '@xorder/ui/localize.js'
import StatusBadge from '@xorder/ui/StatusBadge.vue'
import Icon from '@xorder/ui/Icon.vue'
import Skeleton from '@xorder/ui/Skeleton.vue'
import { confirm } from '@xorder/ui/confirm.js'
import { alert } from '@xorder/ui/alert.js'

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

// Display-only helpers for the "Ends" column (same maths as RestaurantDetails).
const daysLeft = (r) => r.subscription_end_date
    ? Math.ceil((new Date(r.subscription_end_date) - new Date()) / 86400000)
    : null
const daysTone = (n) => (n < 0 || n <= 7 ? 'badge-red' : n <= 30 ? 'badge-amber' : 'badge-gray')
</script>

<template>
    <div class="space-y-5">
        <!-- Header -->
        <div class="flex flex-wrap items-start justify-between gap-3">
            <div>
                <h1 class="page-title">{{ t('nav.restaurants') }}</h1>
                <p class="page-sub" style="color:var(--body)">{{ t('admin.restaurants_subtitle') }}</p>
            </div>
            <RouterLink :to="{ name: 'admin.restaurants.create' }" class="btn btn-accent cta"><Icon name="plus" :size="16" />{{ t('admin.create_restaurant') }}</RouterLink>
        </div>

        <!-- Toolbar: search + status filter with counts -->
        <div class="flex flex-wrap items-center gap-3">
            <div class="search">
                <Icon name="search" :size="16" class="search-ico" aria-hidden="true" />
                <input v-model="search" type="search" :placeholder="t('admin.search_restaurants')" :aria-label="t('admin.search_restaurants')" class="input search-input" />
            </div>
            <div class="segmented seg overflow-x-auto" role="group" :aria-label="t('common.status')">
                <button v-for="[val, label] in filters" :key="val" type="button" :class="{ active: status === val }" :aria-pressed="status === val" @click="status = val">
                    {{ label }}<span v-if="countFor(val) != null" class="seg-count">{{ countFor(val) }}</span>
                </button>
            </div>
        </div>

        <!-- List -->
        <div class="card list-card">
            <div class="list-scroll">
                <div class="list-inner">
                    <div class="r-grid r-head" aria-hidden="true">
                        <span class="c-idx">#</span>
                        <span class="c-name">{{ t('admin.restaurant') }}</span>
                        <span class="c-status">{{ t('common.status') }}</span>
                        <span class="c-sub">{{ t('restaurant.subscription') }}</span>
                        <span class="c-ends">{{ t('admin.end_date') }}</span>
                        <span class="c-items">{{ t('nav.items') }}</span>
                        <span class="c-created">{{ t('admin.created') }}</span>
                        <span class="c-act">{{ t('common.actions') }}</span>
                    </div>

                    <!-- Loading: skeleton rows that mirror the final row -->
                    <div v-if="loading" aria-hidden="true">
                        <div v-for="n in 6" :key="n" class="r-grid r-row">
                            <span class="c-idx"><Skeleton w="18px" h="12px" /></span>
                            <span class="c-name flex items-center gap-3"><Skeleton w="38px" h="38px" rounded="50%" /><Skeleton w="55%" h="13px" /></span>
                            <span class="c-status"><Skeleton w="72px" h="22px" rounded="999px" /></span>
                            <span class="c-sub"><Skeleton w="110px" h="22px" rounded="999px" /></span>
                            <span class="c-ends"><Skeleton w="90px" h="13px" /></span>
                            <span class="c-items"><Skeleton w="26px" h="13px" /></span>
                            <span class="c-created"><Skeleton w="80px" h="13px" /></span>
                            <span class="c-act"><Skeleton w="150px" h="30px" rounded="9px" /></span>
                        </div>
                    </div>

                    <!-- Empty -->
                    <div v-else-if="!rows.length" class="empty">
                        <span class="empty-ico"><Icon name="building" :size="22" /></span>
                        <p>{{ t('admin.no_restaurants') }}</p>
                        <RouterLink :to="{ name: 'admin.restaurants.create' }" class="btn btn-accent btn-sm"><Icon name="plus" :size="14" />{{ t('admin.create_restaurant') }}</RouterLink>
                    </div>

                    <ul v-else>
                        <li v-for="(r, idx) in rows" :key="r.id" class="r-grid r-row r-link" :class="{ 'is-archived': r.status === 'ARCHIVED' }"
                            @click="router.push({ name: 'admin.restaurants.show', params: { id: r.id } })">
                            <span class="c-idx num">{{ (meta?.from || 1) + idx }}</span>
                            <span class="c-name flex items-center gap-3 min-w-0">
                                <span class="initial">{{ initial(r) }}</span>
                                <span class="min-w-0">
                                    <RouterLink :to="{ name: 'admin.restaurants.show', params: { id: r.id } }" class="row-name block truncate" @click.stop>{{ restaurantName(r) }}</RouterLink>
                                    <span v-if="r.slug" class="slug mono block truncate">{{ r.slug }}</span>
                                </span>
                            </span>
                            <span class="c-status"><StatusBadge :value="r.status" /></span>
                            <span class="c-sub">
                                <span class="badge" :class="subBadge(r.subscription_status)">{{ subLabel(r) }}</span>
                                <span v-if="r.subscription_status !== 'ACTIVE' && r.subscription_plan" class="plan-line block truncate">{{ r.subscription_plan }}</span>
                            </span>
                            <span class="c-ends">
                                <template v-if="r.subscription_end_date">
                                    <span class="end-date block">{{ fmtDate(r.subscription_end_date) }}</span>
                                    <span class="badge" :class="daysTone(daysLeft(r))">
                                        {{ daysLeft(r) >= 0 ? t('admin.days_left', { n: daysLeft(r) }) : t('admin.expired_ago', { n: -daysLeft(r) }) }}
                                    </span>
                                </template>
                                <span v-else class="dash">—</span>
                            </span>
                            <span class="c-items num"><strong>{{ r.menu_items_count ?? '—' }}</strong><span class="only-sm"> {{ t('nav.items') }}</span></span>
                            <span class="c-created">{{ fmtDate(r.created_at) }}</span>
                            <span class="c-act" @click.stop>
                                <RouterLink :to="{ name: 'admin.restaurants.show', params: { id: r.id } }" class="btn btn-ghost btn-sm act">{{ t('nav.qr') }}</RouterLink>
                                <RouterLink :to="{ name: 'admin.restaurants.edit', params: { id: r.id } }" class="btn btn-ghost btn-sm act">{{ t('common.edit') }}</RouterLink>
                                <button
                                    v-if="r.status !== 'ARCHIVED'"
                                    type="button"
                                    @click="archiveRestaurant(r)"
                                    :disabled="archiving === r.id"
                                    class="btn btn-ghost btn-sm act"
                                >{{ archiving === r.id ? t('admin.archiving') : t('common.archive') }}</button>
                                <button
                                    v-else
                                    type="button"
                                    @click="hardDeleteRestaurant(r)"
                                    :disabled="deleting === r.id"
                                    class="icon-btn icon-btn-danger act-icon"
                                    :title="t('admin.delete_restaurant')"
                                    :aria-label="t('admin.delete_restaurant')"
                                ><Icon name="trash" :size="16" /></button>
                            </span>
                        </li>
                    </ul>
                </div>
            </div>
        </div>

        <div v-if="meta && meta.last_page > 1" class="flex flex-wrap items-center justify-between gap-3">
            <p class="text-sm" style="color:var(--body)">
                {{ t('common.showing_range', { from: meta.from, to: meta.to, total: meta.total }) }}
            </p>
            <div class="inline-flex items-center gap-2">
                <button class="btn btn-ghost btn-sm pager" :disabled="meta.current_page <= 1" @click="goToPage(meta.current_page - 1)">
                    {{ t('common.previous') }}
                </button>
                <span class="text-sm" style="color:var(--body)">{{ meta.current_page }} / {{ meta.last_page }}</span>
                <button class="btn btn-ghost btn-sm pager" :disabled="meta.current_page >= meta.last_page" @click="goToPage(meta.current_page + 1)">
                    {{ t('common.next') }}
                </button>
            </div>
        </div>
    </div>
</template>

<style scoped>
/* Colours come from theme variables only. Badge text is re-tinted for contrast
   on the soft backgrounds (the shared classes are too light on white). */
.badge.badge-amber { color: var(--p-primary-800); }
.badge.badge-gray { color: var(--body); }
.badge.badge-indigo { color: var(--p-primary-800); }

.cta { min-height: 44px; }

.search { position: relative; flex: 1 1 260px; max-width: 360px; }
.search-ico { position: absolute; inset-inline-start: 13px; top: 50%; transform: translateY(-50%); color: var(--body); pointer-events: none; }
.search-input { margin-top: 0; padding-inline-start: 38px; min-height: 44px; }
.seg button { color: var(--body); min-height: 38px; display: inline-flex; align-items: center; gap: 6px; white-space: nowrap; }
.seg button.active { color: var(--ink); }
.seg-count { font-size: 12.5px; font-weight: 600; background: var(--card); color: var(--body); border-radius: 20px; padding: 0 7px; line-height: 20px; }
.seg button.active .seg-count { background: var(--accent-soft); color: var(--p-primary-800); }

.list-card { overflow: hidden; }
.list-scroll { overflow-x: auto; }
.list-inner { min-width: 980px; }
.r-grid { display: grid; align-items: center; column-gap: 14px; padding: 0 20px;
    grid-template-columns: 30px minmax(0, 2.2fr) 112px minmax(0, 1.5fr) minmax(0, 1.2fr) 64px 118px auto; }
.r-head { padding-block: 11px; background: var(--page); border-bottom: 1px solid var(--line);
    font-size: 12.5px; font-weight: 600; color: var(--body); }
.r-row { padding-block: 12px; min-height: 64px; border-top: 1px solid var(--line); }
ul > .r-row:first-child { border-top: none; }
.r-link { cursor: pointer; transition: background .15s; }
.r-link:hover { background: var(--page); }
.r-link:hover .row-name { color: var(--p-primary-700); }
.c-act { display: flex; justify-content: flex-end; align-items: center; gap: 6px; }
.c-items, .c-idx { text-align: end; }
.c-items { color: var(--body); }
.c-items strong { color: var(--ink); }
.c-created { color: var(--body); font-size: 14px; }
.num { font-variant-numeric: tabular-nums; }
.c-idx { color: var(--body); font-size: 14px; }
.only-sm { display: none; }

.row-name { font-size: 15px; font-weight: 600; color: var(--ink); }
.slug { font-size: 12.5px; color: var(--body); }
.initial { width: 38px; height: 38px; border-radius: 50%; flex: none; display: grid; place-items: center;
    background: var(--accent-soft); color: var(--p-primary-700); font-weight: 700; font-size: 15px; font-family: var(--font-display); }
.is-archived .initial { background: var(--gray-soft); color: var(--body); }
.is-archived .row-name { color: var(--body); }
.plan-line { font-size: 12.5px; color: var(--body); margin-top: 3px; }
.end-date { font-size: 13.5px; color: var(--ink); margin-bottom: 3px; }
.dash { color: var(--body); }
.act { min-height: 34px; }
.act-icon { width: 34px; height: 34px; color: var(--red); }

.empty { display: flex; flex-direction: column; align-items: center; gap: 12px; padding: 48px 20px; text-align: center; color: var(--body); }
.empty-ico { width: 48px; height: 48px; border-radius: 14px; display: grid; place-items: center; background: var(--accent-soft); color: var(--p-primary-700); }

/* Phone: each restaurant becomes a stacked card-like row, no horizontal scroll. */
@media (max-width: 820px) {
    .list-inner { min-width: 0; }
    .r-head { display: none; }
    .r-grid { grid-template-columns: minmax(0, 1fr) auto auto; row-gap: 8px; padding: 14px 16px; align-items: start;
        grid-template-areas: "name name status" "sub ends ends" "items created created" "act act act"; }
    .r-row { min-height: 0; }
    .c-idx { display: none; }
    .c-name { grid-area: name; }
    .c-status { grid-area: status; }
    .c-sub { grid-area: sub; }
    .c-ends { grid-area: ends; text-align: end; }
    .c-items { grid-area: items; text-align: start; }
    .c-created { grid-area: created; text-align: end; }
    .c-act { grid-area: act; justify-content: flex-start; flex-wrap: wrap; gap: 8px; padding-top: 4px; }
    .only-sm { display: inline; }
    .act { min-height: 44px; }
    .act-icon { width: 44px; height: 44px; }
    .search { max-width: none; flex-basis: 100%; }
}
</style>
