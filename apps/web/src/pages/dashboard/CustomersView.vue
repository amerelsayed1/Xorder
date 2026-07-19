<script setup>
import { ref, onMounted, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRouter } from 'vue-router'
import api from '@xorder/api-client/api.js'
import ListSkeleton from '@xorder/ui/ListSkeleton.vue'
import Icon from '@xorder/ui/Icon.vue'
import { withMinDuration } from '../../lib/minLoading.js'

const { t } = useI18n()
const router = useRouter()

const rows = ref([])
const loading = ref(true)
const search = ref('')
let searchTimer

async function load() {
    loading.value = true
    try {
        const { data } = await withMinDuration(api.get('api/dashboard/customers', { params: { search: search.value || undefined } }))
        rows.value = data.data
    } finally { loading.value = false }
}
onMounted(load)
watch(search, () => { clearTimeout(searchTimer); searchTimer = setTimeout(load, 300) })

function openCustomer(c) {
    router.push({ name: 'dashboard.customer', params: { id: c.id } })
}
</script>

<template>
    <div class="space-y-5">
        <div class="flex items-start justify-between gap-3">
            <div>
                <h1 class="page-title">{{ t('nav.customers') }}</h1>
                <p class="page-sub">{{ t('customer.subtitle', { count: rows.length }) }}</p>
            </div>
        </div>

        <div class="relative" style="max-width:320px">
            <span class="absolute top-1/2 -translate-y-1/2" style="inset-inline-start:12px;color:var(--muted)"><Icon name="search" :size="17" /></span>
            <input v-model="search" :placeholder="t('customer.search_ph')" class="input" style="padding-inline-start:38px" />
        </div>

        <div class="card overflow-hidden">
            <ListSkeleton v-if="loading" />
            <div v-else-if="!rows.length" class="p-8 text-center" style="color:var(--muted)">{{ t('customer.none') }}</div>
            <ul v-else>
                <li v-for="c in rows" :key="c.id" class="flex items-center gap-3 px-5 py-3 border-t first:border-t-0 cursor-pointer hover:bg-black/[.02]" style="border-color:var(--line)" @click="openCustomer(c)">
                    <div class="h-11 w-11 rounded-full grid place-items-center flex-shrink-0 font-bold" style="background:var(--accent-soft);color:var(--accent)">{{ (c.name || '؟').charAt(0).toUpperCase() }}</div>
                    <div class="flex-1 min-w-0">
                        <div class="font-medium" style="color:var(--ink)">{{ c.name || t('customer.no_name') }}</div>
                    </div>
                    <div class="text-xs text-end" style="color:var(--muted)">
                        <div>{{ t('customer.orders_n', { n: c.orders_count }) }}</div>
                        <div v-if="c.addresses_count">{{ t('customer.addresses_n', { n: c.addresses_count }) }}</div>
                    </div>
                    <Icon name="chevronDown" :size="16" class="-rotate-90 rtl:rotate-90" style="color:var(--muted)" />
                </li>
            </ul>
        </div>
    </div>
</template>
