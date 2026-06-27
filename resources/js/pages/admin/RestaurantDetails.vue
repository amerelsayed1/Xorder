<script setup>
import { ref, reactive, onMounted } from 'vue'
import { useRoute, RouterLink } from 'vue-router'
import api, { ensureCsrf } from '../../lib/api'

const route = useRoute()
const id = route.params.id
const r = ref(null)
const qr = ref(null)
const sub = reactive({ subscription_status: '', subscription_plan: '', subscription_start_date: '', subscription_end_date: '' })
const msg = ref('')

async function load() {
    const { data } = await api.get(`api/admin/restaurants/${id}`)
    r.value = data.data
    Object.assign(sub, {
        subscription_status: r.value.subscription_status,
        subscription_plan: r.value.subscription_plan || '',
        subscription_start_date: r.value.subscription_start_date || '',
        subscription_end_date: r.value.subscription_end_date || '',
    })
    const q = await api.get(`api/admin/restaurants/${id}/qr`)
    qr.value = q.data.data
}
onMounted(load)

async function setStatus(status) {
    await ensureCsrf()
    await api.patch(`api/admin/restaurants/${id}/status`, { status })
    msg.value = `Status set to ${status}`
    await load()
}
async function saveSubscription() {
    await ensureCsrf()
    await api.patch(`api/admin/restaurants/${id}/subscription`, {
        ...sub,
        subscription_plan: sub.subscription_plan || null,
        subscription_start_date: sub.subscription_start_date || null,
        subscription_end_date: sub.subscription_end_date || null,
    })
    msg.value = 'Subscription updated'
    await load()
}
function downloadQr() { window.open(`/api/admin/restaurants/${id}/qr/download`, '_blank') }

const statuses = ['ACTIVE', 'SUSPENDED', 'ARCHIVED']
const subStatuses = ['TRIAL', 'ACTIVE', 'EXPIRED', 'SUSPENDED']
const initial = (x) => (x.name_en || x.name_ar || '?').trim().charAt(0).toUpperCase()
</script>

<template>
    <div v-if="r" class="space-y-6 max-w-3xl">
        <div class="flex items-center justify-between gap-3">
            <RouterLink :to="{ name: 'admin.restaurants' }" class="text-sm" style="color:var(--muted)">← Back</RouterLink>
            <RouterLink :to="{ name: 'admin.restaurants.edit', params: { id } }" class="btn btn-ghost">Edit details</RouterLink>
        </div>

        <div class="flex items-center gap-4">
            <span v-if="!r.logo_url" class="grid place-items-center text-white font-semibold"
                style="width:56px;height:56px;border-radius:13px;font-size:22px;font-family:var(--font-display);background:var(--accent)">{{ initial(r) }}</span>
            <img v-else :src="r.logo_url" class="h-14 w-14 rounded-xl object-cover" />
            <div>
                <h1 class="page-title">{{ r.name_en || r.name_ar }}</h1>
                <a :href="r.public_url" target="_blank" class="mono text-sm underline" style="color:var(--accent)">{{ r.public_url }}</a>
            </div>
        </div>

        <p v-if="msg" class="badge badge-green"><span class="dot"></span>{{ msg }}</p>

        <!-- Status -->
        <section class="card p-5">
            <h2 class="h-card mb-1">Restaurant status</h2>
            <p class="page-sub mb-3">Suspended & archived menus show “This menu is currently unavailable.”</p>
            <div class="segmented">
                <button v-for="s in statuses" :key="s" :class="{ active: r.status === s }" @click="setStatus(s)">{{ s.charAt(0) + s.slice(1).toLowerCase() }}</button>
            </div>
        </section>

        <!-- Subscription -->
        <section class="card p-5">
            <h2 class="h-card mb-3">Subscription</h2>
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <label class="block"><span class="label">Plan</span>
                    <input v-model="sub.subscription_plan" class="input" placeholder="e.g. Pro" /></label>
                <div class="block">
                    <span class="label">Status</span>
                    <div class="segmented mt-1.5 flex-wrap">
                        <button v-for="s in subStatuses" :key="s" :class="{ active: sub.subscription_status === s }" @click="sub.subscription_status = s">{{ s.charAt(0) + s.slice(1).toLowerCase() }}</button>
                    </div>
                </div>
                <label class="block"><span class="label">Start date</span>
                    <input v-model="sub.subscription_start_date" type="date" class="input" /></label>
                <label class="block"><span class="label">End date</span>
                    <input v-model="sub.subscription_end_date" type="date" class="input" /></label>
            </div>
            <button @click="saveSubscription" class="btn btn-accent mt-4">Save subscription</button>
        </section>

        <!-- QR -->
        <section class="card p-5">
            <h2 class="h-card mb-3">QR Code</h2>
            <div class="flex items-center gap-5 flex-wrap">
                <div v-if="qr" v-html="qr.svg" class="qrbox h-40 w-40 p-2 rounded-xl" style="background:#fff;border:1px solid var(--line)"></div>
                <div class="flex flex-col gap-2">
                    <button @click="downloadQr" class="btn btn-ghost">Download PNG</button>
                    <a :href="r.public_url" target="_blank" class="btn btn-dark">View menu</a>
                </div>
            </div>
        </section>
    </div>
</template>
