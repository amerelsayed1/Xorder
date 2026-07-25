<script setup>
import { computed, ref, reactive, onMounted, watch } from 'vue'
import { useRoute, useRouter, RouterLink } from 'vue-router'
import { useI18n } from 'vue-i18n'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import { localizedInitial, pickLocalized } from '@xorder/ui/localize.js'
import Icon from '@xorder/ui/Icon.vue'
import { confirm } from '@xorder/ui/confirm.js'
import Skeleton from '@xorder/ui/Skeleton.vue'
import AuditLogList from '../../components/AuditLogList.vue'

const route = useRoute()
const router = useRouter()
const { t, locale } = useI18n()
const id = route.params.id
const loading = ref(true)
// 'notfound' when the restaurant 404s, 'error' for anything else, null when OK.
const loadError = ref(null)
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
// Admin-account inline editor (name / login username / email).
const editingAdmin = ref(false)
const savingAdmin = ref(false)
const adminForm = reactive({ name: '', username: '', email: '' })
const adminErrors = ref({})
const auditRows = ref([])
const auditLoading = ref(true)

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

// Load the page. The restaurant fetch gates the loading/error state; plans and
// audit are secondary and never blank the page if they fail.
async function loadAll() {
    loading.value = true
    loadError.value = null
    try {
        await load()
    } catch (err) {
        loadError.value = err.response?.status === 404 ? 'notfound' : 'error'
        return
    } finally {
        loading.value = false
    }
    loadPlans().catch(() => { /* plan list is optional */ })
    loadAudit()
}
async function loadPlans() {
    const { data } = await api.get('api/admin/plans', { params: { active_only: true } })
    plans.value = data.data
}
async function loadAudit() {
    auditLoading.value = true
    try {
        const { data } = await api.get('api/admin/audit-logs', { params: { restaurant_id: id, per_page: 8 } })
        auditRows.value = data.data
    } catch { /* audit is secondary — never fail the page over it */ } finally {
        auditLoading.value = false
    }
}
onMounted(loadAll)

// Member-since date for the stats strip.
const memberSince = computed(() => {
    if (!r.value?.created_at) return '—'
    return new Date(r.value.created_at).toLocaleDateString(locale.value, { year: 'numeric', month: 'short', day: 'numeric' })
})

// At-a-glance subscription health for the summary strip.
const daysLeft = computed(() => {
    if (!sub.subscription_end_date) return null
    const end = new Date(sub.subscription_end_date)
    return Math.ceil((end - new Date()) / 86400000)
})
const subBadgeClass = computed(() => ({
    ACTIVE: 'badge-green', TRIAL: 'badge-amber', EXPIRED: 'badge-red', SUSPENDED: 'badge-red',
}[sub.subscription_status] || 'badge-gray'))
const statusBadgeClass = computed(() => ({
    ACTIVE: 'badge-green', SUSPENDED: 'badge-red', ARCHIVED: 'badge-gray',
}[r.value?.status] || 'badge-gray'))
// Ordering is plan-gated: available_ordering_modes is what the plan entitles.
// Empty → the plan grants no ordering channel, so ordering is unavailable
// regardless of any raw toggle.
const orderingAvailable = computed(() => (r.value?.available_ordering_modes?.length || 0) > 0)

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
function startEditAdmin() {
    adminErrors.value = {}
    Object.assign(adminForm, {
        name: r.value.admin?.name || '',
        username: r.value.admin?.username || '',
        email: r.value.admin?.email || '',
    })
    editingAdmin.value = true
}
function cancelEditAdmin() {
    editingAdmin.value = false
    adminErrors.value = {}
}
async function saveAdmin() {
    savingAdmin.value = true
    adminErrors.value = {}
    errMsg.value = ''
    try {
        await ensureCsrf()
        await api.patch(`api/admin/restaurants/${id}/admin`, {
            name: adminForm.name,
            username: adminForm.username,
            email: adminForm.email || null,
        })
        msg.value = t('admin.account_updated')
        editingAdmin.value = false
        await load()
    } catch (err) {
        const errors = err.response?.data?.errors
        if (errors) adminErrors.value = errors
        else errMsg.value = err.response?.data?.message || t('admin.account_update_failed')
    } finally {
        savingAdmin.value = false
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

// Left side-menu sections. The identity header stays pinned above; only the
// selected section's cards render on the right.
const activeSection = ref('overview')
const sections = computed(() => [
    { key: 'overview', label: t('admin.section_overview'), icon: 'dashboard' },
    { key: 'client', label: t('admin.section_client'), icon: 'building' },
    { key: 'subscription', label: t('admin.section_subscription'), icon: 'star' },
    { key: 'qr', label: t('admin.section_qr'), icon: 'qr' },
    { key: 'activity', label: t('admin.section_activity'), icon: 'items' },
    { key: 'danger', label: t('admin.section_danger'), icon: 'trash' },
])

const backArrow = computed(() => locale.value === 'ar' ? '→' : '←')
const restaurantName = (x) => pickLocalized(x, 'name', locale.value)
const initial = (x) => localizedInitial(x, 'name', locale.value)
</script>

<template>
    <!-- Loading -->
    <div v-if="loading" class="space-y-6 max-w-3xl">
        <Skeleton w="100%" h="96px" rounded="14px" />
        <div class="grid grid-cols-2 sm:grid-cols-4 gap-4">
            <Skeleton v-for="n in 4" :key="n" w="100%" h="74px" rounded="14px" />
        </div>
        <Skeleton w="100%" h="120px" rounded="14px" />
        <Skeleton w="100%" h="200px" rounded="14px" />
    </div>

    <!-- Not found / load error -->
    <div v-else-if="loadError" class="max-w-3xl">
        <div class="card p-8 text-center space-y-3">
            <div class="grid place-items-center mx-auto" style="width:48px;height:48px;border-radius:12px;background:var(--gray-soft);color:var(--gray)">
                <Icon :name="loadError === 'notfound' ? 'building' : 'close'" :size="22" />
            </div>
            <h1 class="page-title">{{ loadError === 'notfound' ? t('admin.not_found_title') : t('admin.load_failed_title') }}</h1>
            <p class="page-sub">{{ loadError === 'notfound' ? t('admin.not_found_help') : t('admin.load_failed_help') }}</p>
            <div class="flex items-center justify-center gap-2 pt-1">
                <RouterLink :to="{ name: 'admin.restaurants' }" class="btn btn-ghost">{{ backArrow }} {{ t('common.back') }}</RouterLink>
                <button v-if="loadError !== 'notfound'" @click="loadAll" class="btn btn-accent">{{ t('common.retry') }}</button>
            </div>
        </div>
    </div>

    <div v-else-if="r" class="space-y-6 max-w-5xl">
        <div class="flex items-center justify-between gap-3">
            <RouterLink :to="{ name: 'admin.restaurants' }" class="text-sm" style="color:var(--muted)">{{ backArrow }} {{ t('common.back') }}</RouterLink>
            <RouterLink :to="{ name: 'admin.restaurants.edit', params: { id } }" class="btn btn-ghost"><Icon name="edit" :size="16" />{{ t('admin.edit_details') }}</RouterLink>
        </div>

        <!-- Identity + at-a-glance health -->
        <div class="card p-5 space-y-4">
            <div class="flex items-center gap-4">
                <span v-if="!r.logo_url" class="grid place-items-center text-white font-semibold flex-shrink-0"
                    style="width:56px;height:56px;border-radius:13px;font-size:22px;font-family:var(--font-display);background:var(--accent)">{{ initial(r) }}</span>
                <img v-else :src="r.logo_url" class="h-14 w-14 rounded-xl object-cover flex-shrink-0" />
                <div class="min-w-0">
                    <h1 class="page-title truncate">{{ restaurantName(r) }}</h1>
                    <a :href="r.public_url" target="_blank" class="mono text-sm underline" style="color:var(--accent)">{{ r.public_url }}</a>
                </div>
            </div>
            <div class="flex flex-wrap items-center gap-2 pt-1">
                <span class="badge" :class="statusBadgeClass"><span class="dot"></span>{{ t('status.' + r.status) }}</span>
                <span class="badge" :class="subBadgeClass">{{ t('subscription_status.' + sub.subscription_status) }}</span>
                <span v-if="sub.subscription_plan" class="badge badge-gray">{{ sub.subscription_plan }}</span>
                <span v-if="daysLeft !== null" class="badge" :class="daysLeft <= 7 ? 'badge-red' : 'badge-gray'">
                    {{ daysLeft >= 0 ? t('admin.days_left', { n: daysLeft }) : t('admin.expired_ago', { n: -daysLeft }) }}
                </span>
                <span class="badge" :class="orderingAvailable ? 'badge-green' : 'badge-gray'">
                    {{ t('admin.ordering_title') }}: {{ orderingAvailable ? t('admin.ordering_on') : t('admin.ordering_unavailable') }}
                </span>
            </div>
        </div>

        <!-- At-a-glance business snapshot -->
        <div class="grid grid-cols-2 sm:grid-cols-4 gap-4">
            <div class="stat">
                <div class="stat-label">{{ t('admin.stat_items') }}</div>
                <div class="stat-num">{{ r.menu_items_count ?? 0 }}</div>
            </div>
            <div class="stat">
                <div class="stat-label">{{ t('admin.stat_categories') }}</div>
                <div class="stat-num">{{ r.categories_count ?? 0 }}</div>
            </div>
            <div class="stat">
                <div class="stat-label">{{ t('admin.stat_features') }}</div>
                <div class="stat-num" style="color:var(--accent)">{{ r.features?.length ?? 0 }}</div>
            </div>
            <div class="stat">
                <div class="stat-label">{{ t('admin.member_since') }}</div>
                <div class="stat-num" style="font-size:16px">{{ memberSince }}</div>
            </div>
        </div>

        <p v-if="msg" class="badge badge-green"><span class="dot"></span>{{ msg }}</p>
        <p v-if="errMsg" class="badge badge-red"><span class="dot"></span>{{ errMsg }}</p>

        <!-- Side menu + section content -->
        <div class="detail-shell">
            <!-- Left side menu -->
            <aside class="detail-nav">
                <button
                    v-for="s in sections"
                    :key="s.key"
                    type="button"
                    class="detail-nav-item"
                    :class="{ active: activeSection === s.key, danger: s.key === 'danger' }"
                    @click="activeSection = s.key"
                >
                    <Icon :name="s.icon" :size="18" />
                    <span>{{ s.label }}</span>
                </button>
            </aside>

            <!-- Section content -->
            <div class="detail-content space-y-6">
                <!-- Overview: restaurant status -->
                <template v-if="activeSection === 'overview'">
                    <section class="card p-5">
                        <h2 class="h-card mb-1">{{ t('admin.restaurant_status') }}</h2>
                        <p class="page-sub mb-3">{{ t('admin.status_help') }}</p>
                        <div class="segmented">
                            <button v-for="s in statuses" :key="s" :class="{ active: r.status === s }" @click="setStatus(s)">{{ t('status.' + s) }}</button>
                        </div>
                    </section>
                </template>

                <!-- Client info: admin account -->
                <template v-else-if="activeSection === 'client'">
                    <section class="card p-5">
                        <h2 class="h-card mb-1">{{ t('admin.admin_account') }}</h2>
                        <p class="page-sub mb-3">{{ t('admin.admin_account_help') }}</p>
                        <div v-if="r.admin" class="space-y-3">
                            <!-- Read-only view -->
                            <template v-if="!editingAdmin">
                                <div class="flex items-center justify-between gap-3 flex-wrap">
                                    <div>
                                        <div class="font-medium" style="color:var(--ink)">{{ r.admin.name }}</div>
                                        <div class="mono text-sm" style="color:var(--muted)">@{{ r.admin.username }}</div>
                                        <div v-if="r.admin.email" class="mono text-sm" style="color:var(--muted)">{{ r.admin.email }}</div>
                                    </div>
                                    <div class="flex items-center gap-2 flex-wrap">
                                        <button @click="startEditAdmin" class="btn btn-ghost"><Icon name="edit" :size="16" />{{ t('admin.edit_account') }}</button>
                                        <button @click="resetAdminPassword" :disabled="resettingPw" class="btn btn-ghost">
                                            {{ resettingPw ? t('admin.resetting') : t('admin.reset_password') }}
                                        </button>
                                    </div>
                                </div>
                                <div v-if="newPassword" class="rounded-xl p-3" style="background:var(--accent-soft);border:1px solid var(--line)">
                                    <div class="label mb-1.5">{{ t('admin.new_password_label') }} — {{ t('restaurant.generated_password_note') }}</div>
                                    <div class="flex items-center gap-2">
                                        <code class="url-chip flex-1">{{ newPassword }}</code>
                                        <button @click="copyPassword" class="btn btn-ghost btn-sm">{{ pwCopied ? t('common.copied') : t('common.copy') }}</button>
                                    </div>
                                </div>
                            </template>

                            <!-- Inline edit form -->
                            <template v-else>
                                <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                                    <label class="block"><span class="label">{{ t('restaurant.admin_name') }}</span>
                                        <input v-model="adminForm.name" class="input" />
                                        <span v-if="adminErrors.name" class="block text-xs mt-1" style="color:var(--red)">{{ adminErrors.name[0] }}</span>
                                    </label>
                                    <label class="block" dir="ltr"><span class="label">{{ t('restaurant.admin_username') }}</span>
                                        <input v-model="adminForm.username" type="text" autocapitalize="none" spellcheck="false" class="input" />
                                        <span class="block text-xs mt-1" style="color:var(--muted)">{{ t('restaurant.admin_username_hint') }}</span>
                                        <span v-if="adminErrors.username" class="block text-xs mt-1" style="color:var(--red)">{{ adminErrors.username[0] }}</span>
                                    </label>
                                </div>
                                <label class="block"><span class="label">{{ t('restaurant.admin_email') }}</span>
                                    <input v-model="adminForm.email" type="email" dir="ltr" class="input" />
                                    <span v-if="adminErrors.email" class="block text-xs mt-1" style="color:var(--red)">{{ adminErrors.email[0] }}</span>
                                </label>
                                <div class="flex items-center gap-2">
                                    <button @click="saveAdmin" :disabled="savingAdmin" class="btn btn-accent">
                                        {{ savingAdmin ? t('common.saving') : t('common.save') }}
                                    </button>
                                    <button @click="cancelEditAdmin" :disabled="savingAdmin" class="btn btn-ghost">{{ t('common.cancel') }}</button>
                                </div>
                            </template>
                        </div>
                        <p v-else class="page-sub">{{ t('admin.no_admin_account') }}</p>
                    </section>
                </template>

                <!-- Subscription -->
                <template v-else-if="activeSection === 'subscription'">
                    <section class="card p-5">
                        <h2 class="h-card mb-1">{{ t('restaurant.subscription') }}</h2>
                        <p class="page-sub mb-3">{{ t('admin.subscription_dates_hint') }}</p>
                        <div class="space-y-4">
                            <label class="block"><span class="label">{{ t('restaurant.plan') }}</span>
                                <select v-model="sub.subscription_plan" class="input max-w-xs">
                                    <option value="">{{ t('plan.none_option') }}</option>
                                    <option v-for="opt in planOptions" :key="opt.value" :value="opt.value">{{ opt.label }}</option>
                                </select></label>
                            <div class="block">
                                <span class="label">{{ t('common.status') }}</span>
                                <div class="segmented mt-1.5 flex-wrap">
                                    <button v-for="s in subStatuses" :key="s" :class="{ active: sub.subscription_status === s }" @click="sub.subscription_status = s">{{ t('subscription_status.' + s) }}</button>
                                </div>
                            </div>
                            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                                <label class="block"><span class="label">{{ t('admin.start_date') }}</span>
                                    <input v-model="sub.subscription_start_date" type="date" class="input" /></label>
                                <label class="block"><span class="label">{{ t('admin.end_date') }}</span>
                                    <input v-model="sub.subscription_end_date" type="date" class="input" /></label>
                            </div>
                        </div>
                        <button @click="saveSubscription" class="btn btn-accent mt-4">{{ t('admin.save_subscription') }}</button>
                    </section>
                </template>

                <!-- QR -->
                <template v-else-if="activeSection === 'qr'">
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
                </template>

                <!-- Activity / audit trail for this restaurant -->
                <template v-else-if="activeSection === 'activity'">
                    <section class="card p-5">
                        <div class="flex items-center justify-between gap-3 mb-1">
                            <h2 class="h-card">{{ t('audit.recent_title') }}</h2>
                            <RouterLink :to="{ name: 'admin.audit', query: { restaurant_id: id } }" class="text-sm" style="color:var(--accent)">
                                {{ t('audit.view_all') }} {{ backArrow === '←' ? '→' : '←' }}
                            </RouterLink>
                        </div>
                        <p class="page-sub mb-2">{{ t('audit.recent_sub') }}</p>
                        <AuditLogList :rows="auditRows" :loading="auditLoading" :show-tenant="false" />
                    </section>
                </template>

                <!-- Danger zone -->
                <template v-else-if="activeSection === 'danger'">
                    <section class="card p-5" style="border-color:#f1c9c4">
                        <h2 class="h-card mb-1" style="color:#c0392b">{{ t('admin.danger_zone') }}</h2>
                        <p class="page-sub mb-3">{{ t('admin.danger_zone_help') }}</p>
                        <div class="flex flex-wrap gap-2">
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
                    </section>
                </template>
            </div>
        </div>
    </div>
</template>

<style scoped>
.detail-shell {
    display: grid;
    grid-template-columns: 220px minmax(0, 1fr);
    gap: 24px;
    align-items: start;
}
.detail-nav {
    display: flex;
    flex-direction: column;
    gap: 4px;
    position: sticky;
    top: 16px;
}
.detail-nav-item {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 10px 12px;
    border-radius: 10px;
    border: 1px solid transparent;
    background: transparent;
    color: var(--muted);
    font-size: 14px;
    font-weight: 500;
    text-align: start;
    cursor: pointer;
    transition: background .15s ease, color .15s ease;
}
.detail-nav-item:hover { background: var(--gray-soft); color: var(--ink); }
.detail-nav-item.active {
    background: var(--accent-soft);
    color: var(--accent);
    border-color: var(--line);
    font-weight: 600;
}
.detail-nav-item.danger.active { background: #fdecea; color: #c0392b; border-color: #f1c9c4; }
.detail-nav-item.danger:hover { color: #c0392b; }

@media (max-width: 640px) {
    .detail-shell { grid-template-columns: 1fr; gap: 16px; }
    .detail-nav {
        position: static;
        flex-direction: row;
        flex-wrap: wrap;
        gap: 6px;
    }
    .detail-nav-item { flex: 0 0 auto; }
    .detail-nav-item span { display: inline; }
}
</style>
