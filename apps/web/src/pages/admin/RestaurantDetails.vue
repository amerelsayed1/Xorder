<script setup>
import { computed, ref, reactive, onMounted, watch } from 'vue'
import { useRoute, useRouter, RouterLink } from 'vue-router'
import { useI18n } from 'vue-i18n'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import { localizedInitial, pickLocalized } from '@xorder/ui/localize.js'
import Icon from '@xorder/ui/Icon.vue'
import { confirm } from '@xorder/ui/confirm.js'

const route = useRoute()
const router = useRouter()
const { t, locale } = useI18n()
const id = route.params.id
const deleting = ref(false)
const archiving = ref(false)
const r = ref(null)
const qr = ref(null)
const sub = reactive({ subscription_status: '', subscription_plan: '', subscription_start_date: '', subscription_end_date: '' })
const plans = ref([])
const msg = ref('')
const errMsg = ref('')
const resettingPw = ref(false)
const newPassword = ref('')
const pwCopied = ref(false)

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
async function loadPlans() {
    const { data } = await api.get('api/admin/plans', { params: { active_only: true } })
    plans.value = data.data
}
onMounted(() => { load(); loadPlans() })

// Active plan names, plus the restaurant's current value if it's a legacy /
// custom plan no longer in the catalog (so we never silently drop it) —
// flagged as such so the admin can tell it apart from catalog plans.
const planOptions = computed(() => {
    const names = plans.value.map(p => p.name)
    const options = names.map(name => ({ value: name, label: name }))
    if (sub.subscription_plan && !names.includes(sub.subscription_plan)) {
        options.unshift({ value: sub.subscription_plan, label: `${sub.subscription_plan} (${t('plan.legacy_suffix')})` })
    }
    return options
})

// Active subscriptions need dates for expiry alerts to work; default the
// start date to today when the admin flips the status and it's still empty.
watch(() => sub.subscription_status, (s) => {
    if (s === 'ACTIVE' && !sub.subscription_start_date) {
        sub.subscription_start_date = new Date().toISOString().slice(0, 10)
    }
})

async function setStatus(status) {
    await ensureCsrf()
    await api.patch(`api/admin/restaurants/${id}/status`, { status })
    msg.value = t('admin.status_updated', { status: t('status.' + status) })
    await load()
}
async function setOrdering(enabled) {
    if (r.value.ordering_enabled === enabled) return
    await ensureCsrf()
    await api.put(`api/admin/restaurants/${id}`, { ordering_enabled: enabled })
    msg.value = t('admin.ordering_updated')
    await load()
}
async function saveSubscription() {
    errMsg.value = ''
    try {
        await ensureCsrf()
        await api.patch(`api/admin/restaurants/${id}/subscription`, {
            ...sub,
            subscription_plan: sub.subscription_plan || null,
            subscription_start_date: sub.subscription_start_date || null,
            subscription_end_date: sub.subscription_end_date || null,
        })
        msg.value = t('admin.subscription_updated')
        await load()
    } catch (err) {
        const errors = err.response?.data?.errors
        errMsg.value = errors ? Object.values(errors).flat()[0] : (err.response?.data?.message || t('admin.subscription_save_failed'))
    }
}
function downloadQr() { window.open(`/api/admin/restaurants/${id}/qr/download`, '_blank') }
async function resetAdminPassword() {
    const ok = await confirm({
        title: t('admin.reset_password_title'),
        message: t('admin.reset_password_message'),
        confirmText: t('admin.reset_password'),
        cancelText: t('common.cancel'),
    })
    if (!ok) return
    resettingPw.value = true
    newPassword.value = ''
    pwCopied.value = false
    try {
        await ensureCsrf()
        const { data } = await api.post(`api/admin/restaurants/${id}/admin/reset-password`)
        newPassword.value = data.generated_password
        msg.value = data.message
    } catch (err) {
        alert(t('admin.reset_password_failed'))
    } finally {
        resettingPw.value = false
    }
}
async function copyPassword() {
    try {
        await navigator.clipboard.writeText(newPassword.value)
        pwCopied.value = true
        setTimeout(() => { pwCopied.value = false }, 2000)
    } catch { /* clipboard unavailable */ }
}
async function archiveRestaurant() {
    const name = restaurantName(r.value)
    const ok = await confirm({
        title: t('admin.archive_title', { name }),
        message: t('admin.archive_message'),
        confirmText: t('admin.archive_confirm'),
        cancelText: t('common.cancel'),
    })
    if (!ok) return
    archiving.value = true
    try {
        await ensureCsrf()
        await api.patch(`api/admin/restaurants/${id}/status`, { status: 'ARCHIVED' })
        msg.value = t('admin.status_updated', { status: t('status.ARCHIVED') })
        await load()
    } catch (err) {
        alert(t('admin.archive_failed'))
    } finally {
        archiving.value = false
    }
}
async function hardDeleteRestaurant() {
    const name = restaurantName(r.value)
    const ok = await confirm({
        title: t('admin.delete_title', { name }),
        message: t('admin.delete_message'),
        confirmText: t('admin.delete_confirm'),
        cancelText: t('common.cancel'),
        confirmationText: r.value.slug,
        confirmationLabel: t('admin.delete_confirmation_label', { slug: r.value.slug }),
        confirmationHint: t('admin.delete_confirmation_hint'),
        danger: true,
    })
    if (!ok) return
    deleting.value = true
    try {
        await ensureCsrf()
        await api.delete(`api/admin/restaurants/${id}`, { data: { confirmation: r.value.slug } })
        router.push({ name: 'admin.restaurants' })
    } catch (err) {
        alert(t('admin.delete_failed'))
        deleting.value = false
    }
}

const statuses = ['ACTIVE', 'SUSPENDED', 'ARCHIVED']
const subStatuses = ['TRIAL', 'ACTIVE', 'EXPIRED', 'SUSPENDED']
const backArrow = computed(() => locale.value === 'ar' ? '→' : '←')
const restaurantName = (x) => pickLocalized(x, 'name', locale.value)
const initial = (x) => localizedInitial(x, 'name', locale.value)
</script>

<template>
    <div v-if="r" class="space-y-6 max-w-3xl">
        <div class="flex items-center justify-between gap-3">
            <RouterLink :to="{ name: 'admin.restaurants' }" class="text-sm" style="color:var(--muted)">{{ backArrow }} {{ t('common.back') }}</RouterLink>
            <div class="flex flex-wrap justify-end items-center gap-2">
                <RouterLink :to="{ name: 'admin.restaurants.edit', params: { id } }" class="btn btn-ghost"><Icon name="edit" :size="16" />{{ t('admin.edit_details') }}</RouterLink>
                <button
                    v-if="r.status !== 'ARCHIVED'"
                    @click="archiveRestaurant"
                    :disabled="archiving"
                    class="btn btn-ghost"
                >{{ archiving ? t('admin.archiving') : t('common.archive') }}</button>
                <button
                    v-else
                    @click="hardDeleteRestaurant"
                    :disabled="deleting"
                    class="btn btn-ghost"
                    style="color:#c0392b;border-color:#f1c9c4"
                ><Icon name="trash" :size="16" />{{ deleting ? t('admin.deleting') : t('common.delete') }}</button>
            </div>
        </div>

        <div class="flex items-center gap-4">
            <span v-if="!r.logo_url" class="grid place-items-center text-white font-semibold"
                style="width:56px;height:56px;border-radius:13px;font-size:22px;font-family:var(--font-display);background:var(--accent)">{{ initial(r) }}</span>
            <img v-else :src="r.logo_url" class="h-14 w-14 rounded-xl object-cover" />
            <div>
                <h1 class="page-title">{{ restaurantName(r) }}</h1>
                <a :href="r.public_url" target="_blank" class="mono text-sm underline" style="color:var(--accent)">{{ r.public_url }}</a>
            </div>
        </div>

        <p v-if="msg" class="badge badge-green"><span class="dot"></span>{{ msg }}</p>
        <p v-if="errMsg" class="badge badge-red"><span class="dot"></span>{{ errMsg }}</p>

        <!-- Status -->
        <section class="card p-5">
            <h2 class="h-card mb-1">{{ t('admin.restaurant_status') }}</h2>
            <p class="page-sub mb-3">{{ t('admin.status_help') }}</p>
            <div class="segmented">
                <button v-for="s in statuses" :key="s" :class="{ active: r.status === s }" @click="setStatus(s)">{{ t('status.' + s) }}</button>
            </div>
        </section>

        <!-- Ordering -->
        <section class="card p-5">
            <h2 class="h-card mb-1">{{ t('admin.ordering_title') }}</h2>
            <p class="page-sub mb-3">{{ t('admin.ordering_help') }}</p>
            <div class="segmented">
                <button :class="{ active: r.ordering_enabled }" @click="setOrdering(true)">{{ t('admin.ordering_on') }}</button>
                <button :class="{ active: !r.ordering_enabled }" @click="setOrdering(false)">{{ t('admin.ordering_off') }}</button>
            </div>
        </section>

        <!-- Admin account -->
        <section class="card p-5">
            <h2 class="h-card mb-1">{{ t('admin.admin_account') }}</h2>
            <p class="page-sub mb-3">{{ t('admin.admin_account_help') }}</p>
            <div v-if="r.admin" class="space-y-3">
                <div class="flex items-center justify-between gap-3 flex-wrap">
                    <div>
                        <div class="font-medium" style="color:var(--ink)">{{ r.admin.name }}</div>
                        <div class="mono text-sm" style="color:var(--muted)">{{ r.admin.email }}</div>
                    </div>
                    <button @click="resetAdminPassword" :disabled="resettingPw" class="btn btn-ghost">
                        {{ resettingPw ? t('admin.resetting') : t('admin.reset_password') }}
                    </button>
                </div>
                <div v-if="newPassword" class="rounded-xl p-3" style="background:var(--accent-soft);border:1px solid var(--line)">
                    <div class="label mb-1.5">{{ t('admin.new_password_label') }} — {{ t('restaurant.generated_password_note') }}</div>
                    <div class="flex items-center gap-2">
                        <code class="url-chip flex-1">{{ newPassword }}</code>
                        <button @click="copyPassword" class="btn btn-ghost btn-sm">{{ pwCopied ? t('common.copied') : t('common.copy') }}</button>
                    </div>
                </div>
            </div>
            <p v-else class="page-sub">{{ t('admin.no_admin_account') }}</p>
        </section>

        <!-- Subscription -->
        <section class="card p-5">
            <h2 class="h-card mb-1">{{ t('restaurant.subscription') }}</h2>
            <p class="page-sub mb-3">{{ t('admin.subscription_dates_hint') }}</p>
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <label class="block"><span class="label">{{ t('restaurant.plan') }}</span>
                    <select v-model="sub.subscription_plan" class="input">
                        <option value="">{{ t('plan.none_option') }}</option>
                        <option v-for="opt in planOptions" :key="opt.value" :value="opt.value">{{ opt.label }}</option>
                    </select></label>
                <div class="block">
                    <span class="label">{{ t('common.status') }}</span>
                    <div class="segmented mt-1.5 flex-wrap">
                        <button v-for="s in subStatuses" :key="s" :class="{ active: sub.subscription_status === s }" @click="sub.subscription_status = s">{{ t('subscription_status.' + s) }}</button>
                    </div>
                </div>
                <label class="block"><span class="label">{{ t('admin.start_date') }}</span>
                    <input v-model="sub.subscription_start_date" type="date" class="input" /></label>
                <label class="block"><span class="label">{{ t('admin.end_date') }}</span>
                    <input v-model="sub.subscription_end_date" type="date" class="input" /></label>
            </div>
            <button @click="saveSubscription" class="btn btn-accent mt-4">{{ t('admin.save_subscription') }}</button>
        </section>

        <!-- QR -->
        <section class="card p-5">
            <h2 class="h-card mb-3">{{ t('nav.qr') }}</h2>
            <div class="flex items-center gap-5 flex-wrap">
                <div v-if="qr" v-html="qr.svg" class="qrbox h-40 w-40 p-2 rounded-xl" style="background:#fff;border:1px solid var(--line)"></div>
                <div class="flex flex-col gap-2">
                    <button @click="downloadQr" class="btn btn-ghost">{{ t('admin.download_png') }}</button>
                    <a :href="r.public_url" target="_blank" class="btn btn-dark">{{ t('dashboard.view_menu') }}</a>
                </div>
            </div>
        </section>
    </div>
</template>
