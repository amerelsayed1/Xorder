<script setup>
import { computed, ref, reactive, onMounted, watch } from 'vue'
import { useRoute, useRouter, RouterLink } from 'vue-router'
import { useI18n } from 'vue-i18n'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import { useAuth } from '@xorder/api-client/auth.js'
import { localizedInitial, pickLocalized } from '@xorder/ui/localize.js'
import Icon from '@xorder/ui/Icon.vue'
import { confirm } from '@xorder/ui/confirm.js'
import { alert } from '@xorder/ui/alert.js'
import Skeleton from '@xorder/ui/Skeleton.vue'
import FormError from '@xorder/ui/FormError.vue'
import ActivityFilesPanel from '../../components/ActivityFilesPanel.vue'
import { isValidEmail } from '../../lib/email.js'
import { asPreview } from '../../lib/host.js'

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

// Load the page. The restaurant fetch gates the loading/error state; the plan
// list is secondary and never blanks the page if it fails. (The activity tab
// loads its own files panel on demand.)
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
}
async function loadPlans() {
    const { data } = await api.get('api/admin/plans', { params: { active_only: true } })
    plans.value = data.data
}
// Hand off to the full audit screen with this tenant and day pre-filtered,
// rather than duplicating the filter UI on a summary tab.
function openDay(date) {
    router.push({ name: 'admin.audit', query: { restaurant_id: id, from: date, to: date } })
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
    adminErrors.value = {}
    errMsg.value = ''
    if (!isValidEmail(adminForm.email)) {
        adminErrors.value = { email: [t('restaurant.email_invalid')] }
        return
    }
    savingAdmin.value = true
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
// Fetch through the authed api client (the API is JWT-Bearer, so a bare
// window.open sends no Authorization header and 401s), then save the blob.
async function downloadQr() {
    try {
        const res = await api.get(`api/admin/restaurants/${id}/qr/download`, { responseType: 'blob' })
        const blobUrl = URL.createObjectURL(res.data)
        const a = document.createElement('a')
        a.href = blobUrl; a.download = `qr-${r.value?.slug || id}.png`; a.click()
        URL.revokeObjectURL(blobUrl)
    } catch (err) { alert(err.response?.data?.message || t('admin.download_failed')) }
}
// Every table this restaurant has, as one JSON file: the table rows plus the
// URL each QR encodes and the PNG inline, so support can hand a floor's codes
// to a print shop without signing in as the restaurant.
const exportingTables = ref(false)
async function exportTablesJson() {
    if (exportingTables.value) return
    exportingTables.value = true
    try {
        const { data } = await api.get(`api/admin/restaurants/${id}/tables/export`)
        if (!data.count) {
            alert({ title: t('common.notice'), message: t('admin.export_tables_none'), variant: 'info' })
            return
        }
        const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' })
        const blobUrl = URL.createObjectURL(blob)
        const a = document.createElement('a')
        a.href = blobUrl; a.download = `tables-${r.value?.slug || id}.json`; a.click()
        URL.revokeObjectURL(blobUrl)
    } catch (err) { alert(err.response?.data?.message || t('admin.download_failed')) }
    finally { exportingTables.value = false }
}
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

// ---------------------------------------------------------------- POS section
// The fleet endpoint is can:pos_fleet.view (SUPER_ADMIN-only by default), a
// narrower gate than this page's restaurants.view — mirror it client-side so
// other platform roles see the plan-derived status but not a table the API
// would 403. POS access itself is DERIVED from the plan (the backend re-syncs
// features from the plan on every change), so nothing here is toggleable.
const auth = useAuth()
const canViewFleet = computed(() => auth.can('pos_fleet.view'))
// Creating a terminal is a separate, narrower gate than reading the fleet:
// a tenant is created with its licence and NO terminal, so every terminal that
// exists is one deliberate act by someone holding this.
const canManageFleet = computed(() => auth.can('pos_fleet.manage'))
// The licence read lives behind licences.manage, a different gate again —
// mirror it so a role that holds only pos_fleet.view sees the terminals it can
// see instead of a card that 403s.
const canViewLicence = computed(() => auth.can('licences.manage'))
const posIncluded = computed(() => (r.value?.features || []).includes('pos'))
// The plan record behind the subscription's plan name, for max_terminals.
const posPlan = computed(() => plans.value.find((pl) => pl.name === sub.subscription_plan) || null)
const posTerminals = ref([])
const posLoading = ref(false)
const posFailed = ref(false)
const posLoaded = ref(false)
// A seat is held by any terminal that is not REVOKED — the exact rule the
// server enforces when one is created (PosProvisioningService::seats, the
// `occupied` count). Stated the same way on both sides deliberately: this
// number decides whether the next terminal can be created, so a dashboard
// that computed it its own way could show "1 of 2" next to a Create button
// the server refuses.
// Owner decision, 2026-09-05: a provisioned row spends its seat immediately,
// so the list can never be longer than the plan allows. Revoking frees the
// seat at once. One predicate feeds both the per-row column and the total, so
// the table and the count cannot drift.
const posHoldsSeat = (term) => term.state !== 'revoked'
const posClaimed = computed(() => posTerminals.value.filter(posHoldsSeat).length)
const posMax = computed(() => posPlan.value?.max_terminals ?? null)
// Over-limit is reachable without anyone cheating — a plan can be lowered
// under tills that already paired — and those tills keep trading, because
// cutting off a working till is how a POS bricks a restaurant. What the
// server refuses is the NEXT device to pair. This line is where the overage
// becomes visible so an owner knows to revoke one.
const posOver = computed(() => posMax.value != null && posClaimed.value > posMax.value)
const posAtLimit = computed(() => posMax.value != null && posClaimed.value === posMax.value)

// The tenant's licence, issued with the tenant itself. Read from the licence
// index rather than the restaurant payload: it is the same record the licences
// screen shows, so the two can never disagree about what a client was sold.
const posLicence = ref(null)
const posLicenceFailed = ref(false)

async function loadPosLicence() {
    posLicenceFailed.value = false
    try {
        const { data } = await api.get('api/admin/pos/licences', {
            params: { restaurant_id: id, per_page: 1 },
        })
        // Newest first from the API — a renewal supersedes rather than edits,
        // so the first row is the current one.
        posLicence.value = (data.data || [])[0] || null
    } catch (err) {
        posLicenceFailed.value = true
    }
}

// ---- create terminal -------------------------------------------------------
// The other half of the tenant/terminal split. A client legitimately sits at
// zero terminals for as long as nobody has installed a till, so this form is
// the ONLY thing that brings one into existence from the platform side.
const posBranches = computed(() => r.value?.branches || [])
const creatingTerminal = ref(false)
const terminalForm = reactive({ name: '', branch_id: '' })
const terminalErrors = ref({})
// Plaintext pairing code, shown once. Held in memory only — a reload loses it,
// which is correct: the server keeps an HMAC and cannot show it again.
const pairing = ref(null)

function openTerminalForm() {
    terminalErrors.value = {}
    terminalForm.name = ''
    terminalForm.branch_id = posBranches.value[0]?.id ?? ''
    creatingTerminal.value = true
}

const savingTerminal = ref(false)
async function submitTerminal() {
    savingTerminal.value = true
    terminalErrors.value = {}
    errMsg.value = ''
    try {
        await ensureCsrf()
        const { data } = await api.post(`api/admin/restaurants/${id}/terminals`, {
            name: terminalForm.name,
            branch_id: terminalForm.branch_id,
        })
        // Prepend: the list is newest-first, and the row the operator just
        // created must be the one they are looking at.
        posTerminals.value = [data.data, ...posTerminals.value]
        posLoaded.value = true
        creatingTerminal.value = false
        msg.value = t('admin.pos_terminal_created')
    } catch (err) {
        terminalErrors.value = err.response?.data?.errors || {}
        // A seat-limit refusal is the POS-BE-019 envelope, not field errors —
        // prefer the server's message because it names the actual numbers.
        if (!Object.keys(terminalErrors.value).length) {
            errMsg.value = err.response?.data?.message || t('admin.pos_terminal_create_failed')
        }
    } finally {
        savingTerminal.value = false
    }
}

// Revoke stops FUTURE trade and frees the terminal's seat immediately; it
// never touches what the till already sold.
async function revokeTerminal(term) {
    const ok = await confirm({
        title: t('pos_terminals.revoke_title'),
        message: t('pos_terminals.revoke_message'),
        confirmText: t('pos_terminals.revoke'),
        cancelText: t('common.cancel'),
        danger: true,
    })
    if (!ok) return
    errMsg.value = ''
    try {
        await ensureCsrf()
        await api.post(`api/admin/restaurants/${id}/terminals/${term.id}/revoke`)
        // In place, not a refetch: the post-revoke state is exactly one thing,
        // and swapping the table for skeletons over a one-row change reads as
        // a page reload.
        posTerminals.value = posTerminals.value.map((x) =>
            x.id === term.id ? { ...x, state: 'revoked' } : x)
        // The seat is free again, so the Create button must come back.
        msg.value = t('pos_terminals.revoked')
    } catch (err) {
        errMsg.value = err.response?.data?.message || t('common.error')
    }
}

// Cleanup for revoked, never-used leftovers. The server refuses anything still
// active (revoke first) or holding sales/shift history — a till that ever
// traded is a record, not clutter.
async function deleteTerminal(term) {
    const ok = await confirm({
        title: t('pos_terminals.delete_title'),
        message: t('pos_terminals.delete_message', { name: term.name }),
        confirmText: t('pos_terminals.delete'),
        cancelText: t('common.cancel'),
        danger: true,
    })
    if (!ok) return
    errMsg.value = ''
    try {
        await ensureCsrf()
        await api.delete(`api/admin/restaurants/${id}/terminals/${term.id}`)
        posTerminals.value = posTerminals.value.filter((x) => x.id !== term.id)
        msg.value = t('pos_terminals.deleted')
    } catch (err) {
        errMsg.value = err.response?.data?.message || t('common.error')
    }
}

async function issuePairingCode(term) {
    errMsg.value = ''
    try {
        await ensureCsrf()
        const { data } = await api.post(`api/admin/restaurants/${id}/terminals/${term.id}/pairing-code`)
        pairing.value = { name: term.name, code: data.pairing_code, hours: data.expires_in_hours }
    } catch (err) {
        errMsg.value = err.response?.data?.message || t('admin.pos_pairing_code_failed')
    }
}

async function loadPosTerminals() {
    if (!canViewFleet.value || posLoading.value) return
    posLoading.value = true
    posFailed.value = false
    try {
        // The fleet endpoint paginates at 50. Reading only the first page
        // made the seat line silently wrong for any restaurant with more
        // terminals than that — and a seat count that quietly under-reports
        // is worse than no seat count, because nobody goes looking for it.
        const all = []
        let page = 1
        let lastPage = 1
        do {
            const { data } = await api.get('api/admin/pos/terminals', {
                params: { restaurant_id: id, page },
            })
            all.push(...(data.data || []))
            lastPage = data.meta?.last_page ?? 1
            page += 1
            // A restaurant with more than 20 pages of tills is a support
            // conversation, not a render — stop rather than hammer the API.
        } while (page <= lastPage && page <= 20)
        posTerminals.value = all
        posLoaded.value = true
    } catch (err) {
        posFailed.value = true
    } finally {
        posLoading.value = false
    }
}
// The resource now carries the branch it eager-loads; the id remains the
// honest fallback for a payload from an older API build.
const posBranchName = (term) => {
    const b = term.branch
    if (!b) return `#${term.branch_id}`
    return (locale.value === 'ar' ? b.name_ar || b.name_en : b.name_en || b.name_ar) || `#${term.branch_id}`
}

const posStateCls = (st) => ({ provisioned: 'badge-gray', active: 'badge-green', revoked: 'badge-red' }[st] || 'badge-gray')
function posRelTime(iso) {
    if (!iso) return '—'
    const d = new Date(iso)
    const diffMin = Math.round((d.getTime() - Date.now()) / 60000)
    const rtf = new Intl.RelativeTimeFormat(locale.value, { numeric: 'auto' })
    if (Math.abs(diffMin) < 60) return rtf.format(diffMin, 'minute')
    if (Math.abs(diffMin) < 60 * 24) return rtf.format(Math.round(diffMin / 60), 'hour')
    return d.toLocaleString(locale.value, { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' })
}

// Left side-menu sections. The identity header stays pinned above; only the
// selected section's cards render on the right.
const activeSection = ref('overview')
// Lazy — the fleet is fetched the first time the POS section is opened, like
// the activity panel. This watch must sit BELOW activeSection's declaration:
// a watch() call runs immediately during setup, and referencing a const that
// is declared further down the file is a temporal-dead-zone crash that blanks
// the whole page in the production bundle.
watch(activeSection, (section) => {
    if (section !== 'pos' || posLoaded.value) return
    loadPosTerminals()
    if (canViewLicence.value) loadPosLicence()
})
const sections = computed(() => [
    { key: 'overview', label: t('admin.section_overview'), icon: 'dashboard' },
    { key: 'client', label: t('admin.section_client'), icon: 'building' },
    { key: 'subscription', label: t('admin.section_subscription'), icon: 'star' },
    { key: 'qr', label: t('admin.section_qr'), icon: 'qr' },
    { key: 'pos', label: t('admin.section_pos'), icon: 'receipt' },
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
                    <a :href="asPreview(r.public_url)" target="_blank" class="mono text-sm underline" style="color:var(--accent)">{{ r.public_url }}</a>
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
                                    <label class="block"><span class="label">{{ t('restaurant.admin_username') }}</span>
                                        <input v-model="adminForm.username" type="text" autocapitalize="none" spellcheck="false" class="input" dir="ltr" />
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
                            <label class="block"><span class="block label">{{ t('restaurant.plan') }}</span>
                                <select v-model="sub.subscription_plan" class="input max-w-xs">
                                    <option value="">{{ t('plan.none_option') }}</option>
                                    <option v-for="opt in planOptions" :key="opt.value" :value="opt.value">{{ opt.label }}</option>
                                </select></label>
                            <div class="block">
                                <span class="block label">{{ t('common.status') }}</span>
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
                                <button @click="exportTablesJson" :disabled="exportingTables" class="btn btn-ghost">
                                    <Icon v-if="exportingTables" name="loading" :size="16" class="animate-spin" />
                                    {{ t('admin.export_tables_json') }}
                                </button>
                                <a :href="asPreview(r.public_url)" target="_blank" class="btn btn-dark">{{ t('dashboard.view_menu') }}</a>
                            </div>
                        </div>
                    </section>
                </template>

                <!-- POS: plan-derived access, the tenant's licence, and its
                     terminals. A tenant is created with its licence and NO
                     terminal, so "no terminals yet" is an ordinary empty state
                     with a create button — never an error. -->
                <template v-else-if="activeSection === 'pos'">
                    <section class="card p-5">
                        <h2 class="h-card mb-1">{{ t('admin.pos_status_title') }}</h2>
                        <p class="page-sub mb-3">{{ t('admin.pos_plan_hint') }}</p>
                        <div class="flex flex-wrap items-center gap-3">
                            <span class="badge" :class="posIncluded ? 'badge-green' : 'badge-gray'"><span class="dot"></span>
                                {{ !sub.subscription_plan ? t('admin.pos_plan_none')
                                    : (posIncluded ? t('admin.pos_plan_included', { plan: sub.subscription_plan })
                                        : t('admin.pos_plan_not_included', { plan: sub.subscription_plan })) }}
                            </span>
                            <RouterLink :to="{ name: 'admin.plans' }" class="text-sm" style="color:var(--accent)">{{ t('admin.pos_edit_plan') }}</RouterLink>
                        </div>
                    </section>

                    <!-- Licence — issued with the tenant, in the same
                         transaction. It belongs to the CLIENT, not to any
                         terminal, so it renders whether or not a till exists. -->
                    <section v-if="canViewLicence" class="card p-5">
                        <h2 class="h-card mb-1">{{ t('admin.pos_licence_title') }}</h2>
                        <p class="page-sub mb-3">{{ t('admin.pos_licence_help') }}</p>

                        <p v-if="posLicenceFailed" class="text-sm" style="color:var(--muted)">{{ t('admin.pos_licence_failed') }}</p>
                        <p v-else-if="!posLicence" class="text-sm" style="color:var(--muted)">{{ t('admin.pos_licence_none') }}</p>
                        <div v-else class="grid grid-cols-2 sm:grid-cols-4 gap-4">
                            <div>
                                <div class="label">{{ t('licence.ref') }}</div>
                                <div class="mono text-sm" style="color:var(--ink)">{{ posLicence.licence_ref }}</div>
                            </div>
                            <div>
                                <div class="label">{{ t('common.status') }}</div>
                                <span class="badge" :class="posLicence.state === 'active' ? 'badge-green' : 'badge-amber'">
                                    {{ t('licence.state.' + posLicence.state) }}
                                </span>
                            </div>
                            <div>
                                <div class="label">{{ t('licence.expires') }}</div>
                                <div class="text-sm" style="color:var(--body)">{{ posLicence.expires_at?.slice(0, 10) }}</div>
                            </div>
                            <div>
                                <!-- Seats SOLD. Nothing here created a till. -->
                                <div class="label">{{ t('licence.max_terminals') }}</div>
                                <div class="text-sm" style="color:var(--body)">{{ posLicence.max_terminals ?? t('licence.unlimited') }}</div>
                            </div>
                        </div>

                        <div v-if="posLicence" class="mt-4">
                            <RouterLink :to="{ name: 'admin.licences.show', params: { id: posLicence.id } }" class="text-sm" style="color:var(--accent)">
                                {{ t('admin.pos_licence_open') }}
                            </RouterLink>
                        </div>
                    </section>

                    <section v-if="canViewFleet" class="card p-5">
                        <h2 class="h-card mb-1">{{ t('admin.pos_terminals_title') }}</h2>
                        <p class="page-sub mb-3">{{ t('admin.pos_terminals_help') }}</p>

                        <p v-if="posLoaded" class="text-sm mb-1"
                            :style="{ color: posOver ? 'var(--red)' : (posAtLimit ? 'var(--amber)' : 'var(--body)'), fontWeight: posOver ? 600 : 400 }">
                            <span class="label">{{ t('admin.pos_seats_label') }}:</span>
                            {{ t('admin.pos_seats', { claimed: posClaimed, max: posMax ?? '∞' }) }}
                            <span v-if="posOver"> — {{ t('admin.pos_seats_over') }}</span>
                        </p>
                        <p v-if="posLoaded" class="text-xs mb-3" style="color:var(--muted)">{{ t('admin.pos_seats_note') }}</p>

                        <div v-if="posLoading" class="space-y-2">
                            <Skeleton v-for="n in 3" :key="n" w="100%" h="40px" rounded="10px" />
                        </div>
                        <div v-else-if="posFailed" class="flex items-center gap-3">
                            <p class="text-sm" style="color:var(--muted)">{{ t('admin.pos_terminals_failed') }}</p>
                            <button @click="loadPosTerminals" class="btn btn-ghost btn-sm">{{ t('common.retry') }}</button>
                        </div>
                        <!-- Zero terminals is a valid, expected state for a
                             newly created client — say so, and offer the one
                             action that changes it. -->
                        <div v-else-if="!posTerminals.length">
                            <p class="text-sm" style="color:var(--muted)">{{ t('admin.pos_no_terminals') }}</p>
                            <p class="text-xs mt-1" style="color:var(--muted)">{{ t('admin.pos_no_terminals_hint') }}</p>
                        </div>
                        <div v-else class="overflow-x-auto">
                            <table class="w-full text-sm" style="min-width:640px">
                                <thead>
                                    <tr style="color:var(--muted)">
                                        <th class="py-2 pe-3 font-medium text-start" style="font-size:11px;text-transform:uppercase">{{ t('common.name') }}</th>
                                        <th class="py-2 px-3 font-medium text-start" style="font-size:11px;text-transform:uppercase">{{ t('pos_terminals.branch') }}</th>
                                        <th class="py-2 px-3 font-medium text-start" style="font-size:11px;text-transform:uppercase">{{ t('common.status') }}</th>
                                        <th class="py-2 px-3 font-medium text-start" style="font-size:11px;text-transform:uppercase">{{ t('pos_terminals.last_seen') }}</th>
                                        <th class="py-2 px-3 font-medium text-start" style="font-size:11px;text-transform:uppercase">{{ t('pos_terminals.version') }}</th>
                                        <th class="py-2 px-3 font-medium text-center" style="font-size:11px;text-transform:uppercase">{{ t('admin.pos_seat') }}</th>
                                        <th class="py-2 px-3 font-medium text-center" style="font-size:11px;text-transform:uppercase">{{ t('pos_terminals.pending') }}</th>
                                        <th v-if="canManageFleet" class="py-2 ps-3"></th>
                                    </tr>
                                </thead>
                                <tbody>
                                    <tr v-for="term in posTerminals" :key="term.id" class="border-t" style="border-color:var(--line)">
                                        <td class="py-2.5 pe-3">
                                            <div style="color:var(--ink)">{{ term.name }}</div>
                                            <div class="mono text-xs" style="color:var(--muted)">{{ term.terminal_id }}</div>
                                        </td>
                                        <td class="py-2.5 px-3" style="color:var(--body)">{{ posBranchName(term) }}</td>
                                        <td class="py-2.5 px-3"><span class="badge" :class="posStateCls(term.state)">{{ t('pos_terminals.state.' + term.state) }}</span></td>
                                        <td class="py-2.5 px-3" style="color:var(--body)">{{ posRelTime(term.last_seen_at) }}</td>
                                        <td class="py-2.5 px-3" style="color:var(--body)">{{ term.app_version || '—' }}</td>
                                        <td class="py-2.5 px-3 text-center">
                                            <span v-if="posHoldsSeat(term)" :title="t('admin.pos_seat_held')" style="color:var(--ink)">1</span>
                                            <span v-else :title="t('admin.pos_seat_none')" style="color:var(--muted)">&mdash;</span>
                                        </td>
                                        <td class="py-2.5 px-3 text-center">
                                            <span v-if="term.pending_count > 0" class="badge badge-amber">{{ term.pending_count }}</span>
                                            <span v-else style="color:var(--muted)">—</span>
                                        </td>
                                        <td v-if="canManageFleet" class="py-2.5 ps-3 text-end">
                                            <div class="flex gap-1 justify-end">
                                                <!-- Revoked is the only state a
                                                     terminal can be deleted from,
                                                     so the two actions never show
                                                     together. -->
                                                <template v-if="term.state !== 'revoked'">
                                                    <button @click="issuePairingCode(term)" class="btn btn-ghost btn-sm">
                                                        {{ t('admin.pos_pairing_code_issue') }}
                                                    </button>
                                                    <button @click="revokeTerminal(term)" class="btn btn-ghost btn-sm" style="color:var(--red)">
                                                        {{ t('pos_terminals.revoke') }}
                                                    </button>
                                                </template>
                                                <button v-else @click="deleteTerminal(term)" class="btn btn-ghost btn-sm" style="color:var(--red)">
                                                    {{ t('pos_terminals.delete') }}
                                                </button>
                                            </div>
                                        </td>
                                    </tr>
                                </tbody>
                            </table>
                        </div>

                        <!-- Pairing code: plaintext in one response and never
                             again, so it stays on screen until dismissed. -->
                        <div v-if="pairing" class="card p-4 mt-4" style="border-color:var(--green);background:var(--green-soft)">
                            <p class="font-medium" style="color:var(--green)">{{ t('admin.pos_pairing_code_title', { name: pairing.name }) }}</p>
                            <p class="mono text-2xl mt-1" style="color:var(--ink)">{{ pairing.code }}</p>
                            <p class="text-sm mt-1" style="color:var(--green)">{{ t('admin.pos_pairing_code_note', { hours: pairing.hours }) }}</p>
                            <button @click="pairing = null" class="btn btn-ghost btn-sm mt-2">{{ t('common.done') }}</button>
                        </div>

                        <!-- Create terminal — the only path from the platform
                             side, and deliberately not part of tenant creation. -->
                        <div v-if="canManageFleet" class="mt-4">
                            <p v-if="!posBranches.length" class="text-sm" style="color:var(--amber)">{{ t('admin.pos_terminal_needs_branch') }}</p>
                            <p v-else-if="posAtLimit || posOver" class="text-sm" style="color:var(--amber)">
                                {{ t('admin.pos_seats_full', { max: posMax }) }}
                            </p>
                            <button v-else-if="!creatingTerminal" @click="openTerminalForm" class="btn btn-dark btn-sm">
                                {{ t('admin.pos_create_terminal') }}
                            </button>

                            <form v-else @submit.prevent="submitTerminal" class="space-y-3 pt-1">
                                <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                                    <label class="block"><span class="label">{{ t('admin.pos_terminal_name') }}</span>
                                        <input v-model="terminalForm.name" class="input" :placeholder="t('admin.pos_terminal_name_placeholder')" required />
                                        <FormError :errors="terminalErrors" field="name" /></label>
                                    <label class="block"><span class="label">{{ t('admin.pos_terminal_branch') }}</span>
                                        <select v-model="terminalForm.branch_id" class="input" required>
                                            <option v-for="b in posBranches" :key="b.id" :value="b.id">
                                                {{ (locale === 'ar' ? b.name_ar || b.name_en : b.name_en || b.name_ar) || ('#' + b.id) }}
                                            </option>
                                        </select>
                                        <FormError :errors="terminalErrors" field="branch_id" /></label>
                                </div>
                                <div class="flex gap-2">
                                    <button type="submit" class="btn btn-dark btn-sm" :disabled="savingTerminal">{{ t('admin.pos_create_terminal') }}</button>
                                    <button type="button" @click="creatingTerminal = false" class="btn btn-ghost btn-sm">{{ t('common.cancel') }}</button>
                                </div>
                            </form>
                        </div>

                        <div class="mt-4">
                            <RouterLink :to="{ name: 'admin.licences' }" class="text-sm" style="color:var(--accent)">{{ t('admin.pos_licences_link') }}</RouterLink>
                        </div>
                    </section>
                </template>

                <!-- Activity / audit trail for this restaurant -->
                <template v-else-if="activeSection === 'activity'">
                    <!-- Files first: the trail IS a file per day, so the tab
                         leads with them. Counts and downloads are scoped to
                         this restaurant. -->
                    <ActivityFilesPanel :restaurant-id="id" start-open @select="openDay" />

                    <div class="flex justify-end">
                        <RouterLink :to="{ name: 'admin.audit', query: { restaurant_id: id } }" class="text-sm" style="color:var(--accent)">
                            {{ t('audit.view_all') }} {{ backArrow === '←' ? '→' : '←' }}
                        </RouterLink>
                    </div>
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
