<script setup>
import { ref, computed, onMounted } from 'vue'
import { RouterLink } from 'vue-router'
import { useI18n } from 'vue-i18n'
import api from '@xorder/api-client/api.js'
import { useAuth } from '@xorder/api-client/auth.js'
import { currencyLabel } from '../../lib/currency.js'
import { pickLocalized } from '@xorder/ui/localize.js'
import Icon from '@xorder/ui/Icon.vue'

const { t, locale } = useI18n()
const auth = useAuth()
const cur = computed(() => currencyLabel(auth.restaurant?.currency, locale.value, auth.restaurant?.currency_symbol))
const stats = ref(null)
const qr = ref(null)
const items = ref([])
const copied = ref(false)

onMounted(async () => {
    const [s, q, it] = await Promise.all([
        api.get('api/dashboard/stats'),
        api.get('api/dashboard/qr'),
        api.get('api/dashboard/items'),
    ])
    stats.value = s.data.data
    qr.value = q.data.data
    items.value = it.data.data
})

// Featured items first; fall back to the newest items so the card is never empty.
const featured = computed(() => {
    const f = items.value.filter(i => i.is_featured)
    return (f.length ? f : items.value).slice(0, 5)
})
// Setup guide: steps we can detect from stats/auth data, plus a final
// non-trackable "print your QR" step. The card hides once every detectable
// step is done.
const setupSteps = computed(() => stats.value ? [
    { key: 'category', labelKey: 'dashboard.step_category', to: { name: 'dashboard.categories' }, done: stats.value.total_categories > 0 },
    { key: 'item', labelKey: 'dashboard.step_item', to: { name: 'dashboard.items' }, done: stats.value.total_items > 0 },
    { key: 'logo', labelKey: 'dashboard.step_logo', to: { name: 'dashboard.profile' }, done: !!auth.restaurant?.logo_url },
    { key: 'qr', labelKey: 'dashboard.step_qr', to: { name: 'dashboard.qr' }, done: null },
] : [])
const setupComplete = computed(() => setupSteps.value.filter(s => s.done !== null).every(s => s.done))
const itemName = (it) => pickLocalized(it, 'name', locale.value)
const itemAltName = (it) => locale.value === 'ar' ? (it.name_en || '') : (it.name_ar || '')

function copyUrl() {
    if (!stats.value) return
    navigator.clipboard?.writeText(stats.value.public_url)
    copied.value = true
    setTimeout(() => (copied.value = false), 1600)
}
</script>

<template>
    <div v-if="stats" class="space-y-6">
        <!-- Header -->
        <div class="flex flex-wrap items-start justify-between gap-3">
            <div>
                <h1 class="page-title">{{ t('nav.dashboard') }}</h1>
                <p class="page-sub">{{ t('dashboard.subtitle') }}</p>
            </div>
            <div class="flex items-center gap-2">
                <a :href="stats.public_url" target="_blank" class="btn btn-ghost"><Icon name="external" :size="16" />{{ t('dashboard.view_menu') }}</a>
                <RouterLink v-if="!auth.isReadOnly" :to="{ name: 'dashboard.items' }" class="btn btn-accent"><Icon name="plus" :size="16" />{{ t('dashboard.add_item') }}</RouterLink>
            </div>
        </div>

        <!-- Setup guide (hidden once every detectable step is done) -->
        <div v-if="!setupComplete" class="card p-5">
            <h2 class="h-card">{{ t('dashboard.setup_guide') }}</h2>
            <p class="page-sub">{{ t('dashboard.setup_guide_sub') }}</p>
            <ul class="mt-3">
                <li v-for="step in setupSteps" :key="step.key" class="border-t first:border-t-0" style="border-color:var(--line)">
                    <RouterLink :to="step.to" class="flex items-center gap-3 py-2.5 group">
                        <span class="h-6 w-6 rounded-full grid place-items-center flex-shrink-0"
                            :style="step.done ? 'background:var(--green-soft);color:var(--green)' : 'border:1.5px solid var(--line);color:var(--muted)'">
                            <Icon v-if="step.done" name="check" :size="14" />
                        </span>
                        <span class="text-sm flex-1" :style="step.done ? 'color:var(--muted);text-decoration:line-through' : 'color:var(--ink)'">{{ t(step.labelKey) }}</span>
                        <Icon name="chevronDown" :size="14" class="rtl:rotate-90 -rotate-90" style="color:var(--muted)" />
                    </RouterLink>
                </li>
            </ul>
        </div>

        <!-- Stat cards -->
        <div class="grid grid-cols-2 lg:grid-cols-3 xl:grid-cols-6 gap-4">
            <div class="stat flex items-center gap-3.5">
                <span class="stat-ico"><Icon name="categories" :size="20" /></span>
                <div>
                    <div class="stat-num" style="font-size:26px">{{ stats.total_categories }}</div>
                    <div class="stat-label">{{ t('stats.total_categories') }}</div>
                </div>
            </div>
            <div class="stat flex items-center gap-3.5">
                <span class="stat-ico"><Icon name="items" :size="20" /></span>
                <div>
                    <div class="stat-num" style="font-size:26px">{{ stats.total_items }}</div>
                    <div class="stat-label">{{ t('stats.total_items') }}</div>
                </div>
            </div>
            <div class="stat flex items-center gap-3.5">
                <span class="stat-ico" style="background:var(--green-soft);color:var(--green)"><Icon name="check" :size="20" /></span>
                <div>
                    <div class="stat-num" style="font-size:26px;color:var(--green)">{{ stats.available_items }}</div>
                    <div class="stat-label">{{ t('stats.available_items') }}</div>
                </div>
            </div>
            <div class="stat flex items-center gap-3.5">
                <span class="stat-ico" style="background:var(--amber-soft);color:var(--amber)"><Icon name="close" :size="20" /></span>
                <div>
                    <div class="stat-num" style="font-size:26px;color:var(--amber)">{{ stats.unavailable_items }}</div>
                    <div class="stat-label">{{ t('stats.unavailable_items') }}</div>
                </div>
            </div>
            <RouterLink :to="{ name: 'dashboard.orders' }" class="stat flex items-center gap-3.5">
                <span class="stat-ico" style="background:var(--accent-soft);color:var(--accent)"><i class="pi pi-shopping-bag" style="font-size:19px" /></span>
                <div>
                    <div class="stat-num" style="font-size:26px;color:var(--accent)">{{ stats.new_orders ?? 0 }}</div>
                    <div class="stat-label">{{ t('stats.new_orders') }}</div>
                </div>
            </RouterLink>
            <div class="stat flex items-center gap-3.5">
                <span class="stat-ico"><i class="pi pi-eye" style="font-size:19px" /></span>
                <div>
                    <div class="stat-num" style="font-size:26px">{{ stats.views_today ?? 0 }}</div>
                    <div class="stat-label">{{ t('stats.views_today') }}</div>
                </div>
            </div>
        </div>

        <!-- Main grid: 2/3 content · 1/3 QR + actions -->
        <div class="grid gap-6 lg:grid-cols-3 items-start">
            <!-- Left (wider) -->
            <div class="lg:col-span-2 space-y-6">
                <!-- Public URL -->
                <div class="card p-5">
                    <h2 class="h-card mb-3 flex items-center gap-2"><Icon name="link" :size="17" style="color:var(--muted)" />{{ t('restaurant.public_url') }}</h2>
                    <div class="flex items-center gap-3">
                        <div class="url-chip flex-1 min-w-0">{{ stats.public_url }}</div>
                        <button @click="copyUrl" class="btn btn-ghost">
                            <Icon :name="copied ? 'check' : 'copy'" :size="16" />{{ copied ? t('common.copied') : t('common.copy') }}
                        </button>
                    </div>
                </div>

                <!-- Featured items -->
                <div class="card p-5">
                    <div class="flex items-center justify-between mb-1">
                        <h2 class="h-card flex items-center gap-2"><Icon name="star" :size="16" :fill="true" style="color:var(--accent)" />{{ t('dashboard.featured_items') }}</h2>
                        <RouterLink :to="{ name: 'dashboard.items' }" class="text-sm flex items-center gap-1" style="color:var(--accent)">{{ t('common.view_all') }}<Icon name="chevronDown" :size="14" style="transform:rotate(-90deg)" /></RouterLink>
                    </div>
                    <ul v-if="featured.length">
                        <li v-for="it in featured" :key="it.id" class="flex items-center gap-3 py-2.5 border-t first:border-t-0" style="border-color:var(--line)">
                            <img v-if="it.image_url" :src="it.image_url" class="h-11 w-11 rounded-lg object-cover flex-shrink-0" />
                            <div v-else class="h-11 w-11 rounded-lg grid place-items-center flex-shrink-0" style="background:var(--accent-soft);color:var(--accent)"><Icon name="items" :size="18" /></div>
                            <div class="min-w-0 flex-1">
                                <div class="font-medium truncate" style="color:var(--ink)">{{ itemName(it) }}</div>
                                <div v-if="itemAltName(it)" class="text-xs truncate" style="color:var(--muted)" :dir="locale === 'ar' ? 'ltr' : 'rtl'">{{ itemAltName(it) }}</div>
                            </div>
                            <span v-if="!it.is_available" class="badge badge-amber">{{ t('common.unavailable') }}</span>
                            <span class="price whitespace-nowrap">{{ it.discounted_price || it.price }} {{ cur }}</span>
                        </li>
                    </ul>
                    <p v-else class="text-sm py-6 text-center" style="color:var(--muted)">{{ t('common.none') }}</p>
                </div>
            </div>

            <!-- Right (narrower): QR + quick actions -->
            <div class="space-y-6">
                <div v-if="qr" class="qr-card flex flex-col items-center justify-center">
                    <h2 class="text-base font-semibold" style="font-family:var(--font-display)">{{ t('dashboard.qr_title') }}</h2>
                    <p class="text-xs mt-1" style="color:rgba(255,255,255,.55)">{{ t('dashboard.qr_help') }}</p>
                    <div class="bg-white p-2.5 rounded-xl mt-4">
                        <div v-html="qr.svg" class="qrbox h-32 w-32"></div>
                    </div>
                    <div class="flex gap-2 mt-4">
                        <a href="/api/dashboard/qr/download" target="_blank" class="btn btn-ghost btn-sm"><Icon name="download" :size="15" />PNG</a>
                        <RouterLink :to="{ name: 'dashboard.qr' }" class="btn btn-dark btn-sm">{{ t('common.open') }}</RouterLink>
                    </div>
                </div>

                <div class="card p-5">
                    <h2 class="h-card mb-3">{{ t('stats.quick_actions') }}</h2>
                    <div class="flex flex-col gap-2">
                        <RouterLink :to="{ name: 'dashboard.categories' }" class="btn btn-ghost justify-start"><Icon name="categories" :size="16" />{{ t('nav.categories') }}</RouterLink>
                        <RouterLink :to="{ name: 'dashboard.items' }" class="btn btn-ghost justify-start"><Icon name="items" :size="16" />{{ t('nav.items') }}</RouterLink>
                        <RouterLink :to="{ name: 'dashboard.profile' }" class="btn btn-ghost justify-start"><Icon name="store" :size="16" />{{ t('nav.profile') }}</RouterLink>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <!-- Loading skeleton -->
    <div v-else class="space-y-6">
        <div class="h-8 w-48 rounded-lg" style="background:var(--line)"></div>
        <div class="grid grid-cols-2 lg:grid-cols-4 gap-4">
            <div v-for="n in 4" :key="n" class="stat" style="height:74px"></div>
        </div>
        <div class="grid gap-6 lg:grid-cols-3">
            <div class="lg:col-span-2 card" style="height:320px"></div>
            <div class="card" style="height:320px"></div>
        </div>
    </div>
</template>
