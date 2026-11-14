<script setup>
import { ref, onMounted, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRouter } from 'vue-router'
import api from '@xorder/api-client/api.js'
import ListSkeleton from '@xorder/ui/ListSkeleton.vue'
import ErrorState from '@xorder/ui/ErrorState.vue'
import Icon from '@xorder/ui/Icon.vue'
import { withMinDuration } from '../../lib/minLoading.js'

const { t } = useI18n()
const router = useRouter()

const rows = ref([])
const loading = ref(true)
const error = ref(false)
const search = ref('')
let searchTimer

async function load() {
    loading.value = true
    error.value = false
    try {
        const { data } = await withMinDuration(api.get('api/dashboard/customers', { params: { search: search.value || undefined } }))
        rows.value = data.data
    } catch (err) {
        error.value = true
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
        <div class="flex flex-wrap items-end justify-between gap-4">
            <div class="min-w-0">
                <h1 class="page-title">{{ t('nav.customers') }}</h1>
                <p class="page-sub" style="color:var(--body)">{{ t('customer.subtitle', { count: rows.length }) }}</p>
            </div>
            <div class="relative search-box">
                <span class="search-ico"><Icon name="search" :size="17" /></span>
                <input v-model="search" type="search" :placeholder="t('customer.search_ph')" :aria-label="t('customer.search_ph')" class="input" style="margin-top:0;padding-inline-start:38px;min-height:44px" data-en-digits />
            </div>
        </div>

        <div class="card overflow-hidden">
            <ListSkeleton v-if="loading" />
            <ErrorState v-else-if="error" @retry="load" />
            <div v-else-if="!rows.length" class="px-5 py-12 text-center" style="color:var(--body)">
                <i class="pi pi-users block mb-2" style="font-size:26px" aria-hidden="true"></i>
                {{ t('customer.none') }}
            </div>
            <ul v-else>
                <li v-for="c in rows" :key="c.id" class="cust-item">
                    <button type="button" class="cust-row" @click="openCustomer(c)">
                        <span class="cust-avatar" aria-hidden="true">{{ (c.name || '؟').charAt(0).toUpperCase() }}</span>
                        <span class="flex-1 min-w-0">
                            <span class="cust-name block truncate">{{ c.name || t('customer.no_name') }}</span>
                            <span v-if="c.phone" class="cust-phone block truncate"><bdi dir="ltr">{{ c.phone }}</bdi></span>
                        </span>
                        <span class="cust-counts">
                            <span class="cust-orders">{{ t('customer.orders_n', { n: c.orders_count }) }}</span>
                            <span v-if="c.addresses_count" class="cust-addr">{{ t('customer.addresses_n', { n: c.addresses_count }) }}</span>
                        </span>
                        <Icon name="chevronDown" :size="16" class="-rotate-90 rtl:rotate-90 flex-none" style="color:var(--body)" />
                    </button>
                </li>
            </ul>
        </div>
    </div>
</template>

<style scoped>
/* Colours come only from the shared theme variables and the PrimeVue primary
   scale; nothing here introduces a new hex value. */
.search-box { flex: 1 1 240px; max-width: 340px; }
.search-ico { position: absolute; top: 50%; transform: translateY(-50%); inset-inline-start: 12px;
    color: var(--body); pointer-events: none; display: flex; }
.cust-item + .cust-item { border-top: 1px solid var(--line); }
.cust-row { display: flex; align-items: center; gap: 14px; width: 100%; min-height: 64px; padding: 10px 20px; text-align: start;
    background: transparent; border: 0; cursor: pointer; font-family: inherit; transition: background .15s; }
.cust-row:hover { background: var(--page); }
.cust-row:hover .cust-name { color: var(--p-primary-700); }
.cust-row:focus-visible { outline: 2px solid var(--accent); outline-offset: -2px; }
.cust-avatar { width: 44px; height: 44px; border-radius: 50%; flex: none; display: grid; place-items: center;
    background: var(--accent-soft); color: var(--p-primary-700); font-weight: 700; font-size: 16px; }
.cust-name { font-size: 16px; font-weight: 600; color: var(--ink); }
.cust-phone { font-size: 14px; color: var(--body); margin-top: 1px; }
.cust-counts { display: flex; flex-direction: column; align-items: flex-end; text-align: end; flex: none; font-size: 14px; color: var(--body); }
.cust-orders { font-weight: 600; color: var(--ink); }
.cust-addr { font-size: 13px; }
@media (max-width: 480px) {
    .cust-row { padding-inline: 14px; gap: 10px; }
}
</style>
