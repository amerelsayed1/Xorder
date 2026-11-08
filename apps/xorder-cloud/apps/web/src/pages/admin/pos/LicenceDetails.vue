<script setup>
import { ref, reactive, computed, onMounted, watch } from 'vue'
import { useRoute, useRouter, RouterLink } from 'vue-router'
import { useI18n } from 'vue-i18n'
import api from '@xorder/api-client/api.js'
import Icon from '@xorder/ui/Icon.vue'
import Modal from '@xorder/ui/Modal.vue'
import FormError from '@xorder/ui/FormError.vue'
import ListSkeleton from '@xorder/ui/ListSkeleton.vue'
import Skeleton from '@xorder/ui/Skeleton.vue'
import ErrorState from '@xorder/ui/ErrorState.vue'
import { confirm } from '@xorder/ui/confirm.js'
import { alert } from '@xorder/ui/alert.js'
import { withMinDuration } from '../../../lib/minLoading.js'

const route = useRoute()
const router = useRouter()
const { t, locale } = useI18n()
const backArrow = computed(() => locale.value === 'ar' ? '→' : '←')

const licence = ref(null)
const claims = ref(null)
const loading = ref(true)
const failed = ref(false)
const busy = ref(false)

const renewing = ref(false)
const renewErrors = ref({})
const renewed = ref(null)
const acknowledged = ref(false)

const renewForm = reactive({
    issued_at: '',
    expires_at: '',
    // Default off: a six-till site should retype nothing at renewal. Only turn
    // it on when the old key must die — a leak, a departed installer.
    rotate_key: false,
    // Renewal is also how a licence is edited and upgraded: everything the
    // licence's kind lets an operator choose starts as the current value
    // (see prefillTerms) and can be changed here.
    lifetime: false,
    plan_id: '',
    features: [],
    modes: [],
    max_terminals: 1,
    max_users: '',
    max_offline_days: '',
    grace_days: 14,
    warn_days: 30,
    customer_name: '',
    contact_name: '',
    contact_email: '',
    contact_phone: '',
    notes: '',
    fingerprints: '',
})

// Cloud licences only: the plans a client can be moved between, and every
// feature a licence can carry. An offline licence has neither (it gets the
// whole product, offline tills only), so nothing is fetched for it.
const plans = ref([])
const isOffline = computed(() => licence.value?.kind === 'offline')
const MODES = ['cloud', 'offline']
const featureChoices = computed(() => {
    const all = new Set(licence.value?.features || [])
    for (const p of plans.value) for (const k of p.feature_keys || []) all.add(k)
    return [...all].sort()
})
// Choosing a plan fills the feature set from it, because that is what a plan is
// for; the boxes stay editable for a client who was sold something different.
function onPlanChange() {
    const plan = plans.value.find((p) => p.id === Number(renewForm.plan_id))
    if (plan) renewForm.features = [...(plan.feature_keys || [])]
}
function toggleIn(list, value, on) {
    const i = list.indexOf(value)
    if (on && i < 0) list.push(value)
    else if (!on && i >= 0) list.splice(i, 1)
}
// A licence covers one mode (owner, 2026-11-08). One signed for both before
// that rule shows no choice, so renewing it makes the operator pick; the
// legacy offline spellings count as offline.
const asMode = (m) => (m === 'branch_server' || m === 'standalone' ? 'offline' : m)
function oneMode(modes) {
    // Kept as signed when it is one mode, so a renewal that changes nothing
    // else does not rewrite `branch_server` as `offline`.
    const list = [...(modes || [])]
    return new Set(list.map(asMode)).size === 1 ? list : []
}
const fingerprintList = () => renewForm.fingerprints.split('\n').map((x) => x.trim()).filter(Boolean)

function prefillTerms(l) {
    Object.assign(renewForm, {
        lifetime: !!l.lifetime,
        plan_id: l.plan?.id ?? '',
        features: [...(l.features || [])],
        modes: oneMode(l.modes),
        max_terminals: l.max_terminals ?? 1,
        max_users: l.max_users ?? '',
        max_offline_days: l.max_offline_days ?? '',
        grace_days: l.grace_days ?? 14,
        warn_days: l.warn_days ?? 30,
        customer_name: l.customer_name || '',
        contact_name: l.contact_name || '',
        contact_email: l.contact_email || '',
        contact_phone: l.contact_phone || '',
        notes: l.notes || '',
        fingerprints: (l.fingerprints || []).join('\n'),
    })
}

// What this renewal would change, so an upgrade is a decision rather than a
// side effect of an open form. Commercial values only; contact details, notes
// and device lists are not echoed back.
const changes = computed(() => {
    const l = licence.value
    if (!l) return []
    const out = []
    const num = (v) => (v === '' || v === null || v === undefined ? null : Number(v))
    const same = (a, b) => JSON.stringify(a) === JSON.stringify(b)
    const add = (label, from, to) => out.push({ label, from: from ?? t('licence.unlimited'), to: to ?? t('licence.unlimited') })
    if (num(renewForm.max_terminals) !== l.max_terminals) add(t('licence.max_terminals'), l.max_terminals, num(renewForm.max_terminals))
    if (num(renewForm.max_users) !== (l.max_users ?? null)) add(t('licence.max_users'), l.max_users, num(renewForm.max_users))
    if (num(renewForm.max_offline_days) !== (l.max_offline_days ?? null)) add(t('licence.max_offline_days'), l.max_offline_days, num(renewForm.max_offline_days))
    if (num(renewForm.grace_days) !== l.grace_days) add(t('licence.grace_days'), l.grace_days, num(renewForm.grace_days))
    if (num(renewForm.warn_days) !== l.warn_days) add(t('licence.warn_days'), l.warn_days, num(renewForm.warn_days))
    if (renewForm.lifetime !== !!l.lifetime) add(t('licence.lifetime'), l.lifetime ? t('common.yes') : t('common.no'), renewForm.lifetime ? t('common.yes') : t('common.no'))
    if (!isOffline.value) {
        if (Number(renewForm.plan_id || 0) !== (l.plan?.id ?? 0)) {
            const to = plans.value.find((p) => p.id === Number(renewForm.plan_id))
            add(t('licence.plan'), l.plan?.name ?? t('licence.no_plan'), to?.name ?? t('licence.no_plan'))
        }
        const sort = (a) => [...a].sort()
        if (!same(sort(renewForm.features), sort(l.features || []))) add(t('licence.features'), (l.features || []).length, renewForm.features.length)
        if (!same(sort(renewForm.modes), sort(l.modes || []))) add(t('licence.modes'), (l.modes || []).join(', '), renewForm.modes.join(', '))
    }
    return out
})
const devicesChanged = computed(() => !same2(fingerprintList(), licence.value?.fingerprints || []))
const same2 = (a, b) => JSON.stringify([...a].sort()) === JSON.stringify([...b].sort())

const isLive = computed(() => licence.value && !licence.value.revoked_at && !licence.value.superseded_by_id)
const dateOf = (iso) => iso ? new Date(iso).toLocaleDateString(locale.value === 'ar' ? 'ar-EG' : 'en-GB') : '—'
// A bare YYYY-MM-DD read as a local day, so the label never slips a day.
const dayLabel = (ymd) => ymd ? new Date(ymd + 'T00:00:00').toLocaleDateString(locale.value === 'ar' ? 'ar-EG' : 'en-GB') : '—'

// When the new term starts. 'after_current' chains it to the day the current
// licence ends — right when that day is near, wrong when it is years away:
// renewing a licence that ran to 2029 produced one not valid until 2029, and
// the till refused it as "not yet valid" (S2-3, 16 Oct 2026). So it is the
// default only when the current term ends within 30 days; otherwise the
// renewal starts today. Typing any other date in the field leaves both radios
// clear ('custom') — the warning below reads the date, not the choice.
const startMode = ref('today')
const expiresTouched = ref(false)
const ymd = (d) => d.toISOString().slice(0, 10)
const plusYear = (from) => ymd(new Date(new Date(from + 'T00:00:00Z').getTime() + 365 * 864e5))
// A licence sold outright reports no expiry, so there is no day to chain to.
const currentEnd = computed(() => licence.value?.expires_at ? ymd(new Date(licence.value.expires_at)) : null)

function applyStart(mode) {
    startMode.value = mode
    const from = mode === 'after_current' && currentEnd.value ? currentEnd.value : ymd(new Date())
    renewForm.issued_at = from
    // Another year from the chosen start, unless the operator already set the end.
    if (!expiresTouched.value) renewForm.expires_at = plusYear(from)
}
watch(() => renewForm.issued_at, (v) => {
    startMode.value = v === ymd(new Date()) ? 'today' : (v && v === currentEnd.value ? 'after_current' : 'custom')
})
// More than a day out: the till will refuse the licence until that day.
const startsInFuture = computed(() => {
    if (!renewForm.issued_at) return false
    return new Date(renewForm.issued_at + 'T00:00:00').getTime() - Date.now() > 864e5
})

const badge = (s) => ({
    active: 'badge-green', expiring_soon: 'badge-amber', in_grace: 'badge-amber',
    expired: 'badge-red', revoked: 'badge-red',
}[s] || 'badge-gray')

async function load() {
    loading.value = true
    failed.value = false
    try {
        const { data } = await withMinDuration(api.get(`api/admin/pos/licences/${route.params.id}`))
        licence.value = data.data
        claims.value = data.claims
        // Prefill the renewal: chained to the current end only when that end
        // is within 30 days, otherwise from today (see startMode).
        expiresTouched.value = false
        const end = currentEnd.value ? new Date(currentEnd.value + 'T00:00:00').getTime() : null
        const endIsNear = end !== null && end - Date.now() <= 30 * 864e5
        applyStart(endIsNear ? 'after_current' : 'today')
        prefillTerms(licence.value)
        if (licence.value.kind === 'offline') loadActivations()
        if (licence.value.kind !== 'offline') {
            api.get('api/admin/plans', { params: { active_only: true } })
                .then(({ data: p }) => { plans.value = p.data || [] })
                .catch(() => { plans.value = [] })
        }
    } catch (err) {
        failed.value = true
    } finally {
        loading.value = false
    }
}
onMounted(load)

async function submitRenewal() {
    renewErrors.value = {}
    busy.value = true
    try {
        const blankToNull = (v) => (v === '' || v === null || v === undefined ? null : Number(v))
        const body = {
            issued_at: renewForm.issued_at,
            // A lifetime licence has no end to send.
            expires_at: renewForm.lifetime ? null : renewForm.expires_at,
            lifetime: renewForm.lifetime,
            rotate_key: renewForm.rotate_key,
            max_terminals: Number(renewForm.max_terminals),
            // Blank means "no limit", and it is sent as null so the server
            // CLEARS it instead of keeping the old number.
            max_users: blankToNull(renewForm.max_users),
            max_offline_days: blankToNull(renewForm.max_offline_days),
            grace_days: Number(renewForm.grace_days),
            warn_days: Number(renewForm.warn_days),
            contact_name: renewForm.contact_name || null,
            contact_email: renewForm.contact_email || null,
            contact_phone: renewForm.contact_phone || null,
            notes: renewForm.notes || null,
            fingerprints: fingerprintList(),
        }
        if (isOffline.value) {
            body.customer_name = renewForm.customer_name || null
        } else {
            body.plan_id = renewForm.plan_id === '' ? null : Number(renewForm.plan_id)
            body.features = renewForm.features
            // Left out when nothing is chosen: the server then says the
            // licence covers both modes and asks for one.
            if (renewForm.modes.length) body.modes = renewForm.modes
        }
        const { data } = await api.post(`api/admin/pos/licences/${licence.value.id}/renew`, body)
        renewing.value = false
        renewed.value = data
        // The server's own word on it: a term that has not started yet is one
        // the till will refuse until it does. Said again here, after the fact,
        // so a date typed past the form's warning still gets named.
        if (data.starts_in_future) alert(t('licence.renewed_starts_future', { date: dateOf(data.data.issued_at) }))
        // A renewal is a NEW row — the old one is superseded, not edited.
        if (!data.activation_key) router.push({ name: 'admin.licences.show', params: { id: data.data.id } }).then(() => { load(); loadTills() })
    } catch (err) {
        renewErrors.value = err.response?.data?.errors || {}
    } finally {
        busy.value = false
    }
}

// Delete is offered only once the licence no longer permits trade — the
// server enforces the same rule (LICENCE_STILL_ACTIVE). Owner decision,
// 2026-09-05: revoke stops trade, delete cleans the record up.
const isDeletable = computed(() => licence.value && ['revoked', 'superseded', 'expired'].includes(licence.value.state))

async function destroyLicence() {
    const ok = await confirm({
        title: t('licence.delete_title'),
        message: t('licence.delete_message', { ref: licence.value.licence_ref }),
        confirmText: t('licence.delete'),
        danger: true,
    })
    if (!ok) return
    try {
        await api.delete(`api/admin/pos/licences/${licence.value.id}`)
        router.push({ name: 'admin.licences' })
    } catch (err) {
        alert(err?.response?.data?.message || t('common.error'))
    }
}

async function revoke() {
    const ok = await confirm({
        title: t('licence.revoke_title'),
        message: t('licence.revoke_message'),
        confirmText: t('licence.revoke'),
        cancelText: t('common.cancel'),
        danger: true,
    })
    if (!ok) return
    busy.value = true
    try {
        await api.post(`api/admin/pos/licences/${licence.value.id}/revoke`, {})
        await load()
    } catch (err) {
        alert(t('common.error'))
    } finally {
        busy.value = false
    }
}

// R2 — the operator's status. Suspend and expire take an optional reason (a
// suspension's is shown on the till); resume is a plain confirm. All three are
// refused by the server on a revoked or superseded row, so they ride isLive.
const isHeld = computed(() => licence.value && ['suspended', 'expired'].includes(licence.value.status))
const holding = ref(null) // 'suspend' | 'expire' | null
const holdReason = ref('')
const holdErrors = ref({})

function openHold(action) {
    holding.value = action
    holdReason.value = ''
    holdErrors.value = {}
}

async function submitHold() {
    holdErrors.value = {}
    busy.value = true
    try {
        const { data } = await api.post(`api/admin/pos/licences/${licence.value.id}/${holding.value}`, {
            reason: holdReason.value || null,
        })
        licence.value = data.data
        holding.value = null
    } catch (err) {
        holdErrors.value = err.response?.data?.errors || {}
        if (!err.response?.data?.errors) alert(err?.response?.data?.message || t('common.error'))
    } finally {
        busy.value = false
    }
}

async function resume() {
    const ok = await confirm({
        title: t('licence.resume_title'),
        message: t('licence.resume_message'),
        confirmText: t('licence.resume'),
        cancelText: t('common.cancel'),
    })
    if (!ok) return
    busy.value = true
    try {
        const { data } = await api.post(`api/admin/pos/licences/${licence.value.id}/resume`, {})
        licence.value = data.data
    } catch (err) {
        alert(err?.response?.data?.message || t('common.error'))
    } finally {
        busy.value = false
    }
}

const verdictBadge = (v) => ({
    valid: 'badge-green', expiring_soon: 'badge-amber', in_grace: 'badge-amber',
    expired: 'badge-red', suspended: 'badge-red',
}[v] || 'badge-gray')

// The tills behind this licence. Loaded on its own so a slow or failed list
// never hides the licence itself.
const tills = ref([])
const tillsLoading = ref(true)
const tillsFailed = ref(false)
const termName = (x) => x?.[locale.value === 'ar' ? 'name_ar' : 'name_en'] || x?.name_en || x?.name_ar || x?.code || '—'
const stamp = (iso) => iso ? new Date(iso).toLocaleString(locale.value === 'ar' ? 'ar-EG' : 'en-GB', { dateStyle: 'short', timeStyle: 'short' }) : null

async function loadTills() {
    tillsLoading.value = true
    tillsFailed.value = false
    try {
        const { data } = await withMinDuration(api.get(`api/admin/pos/licences/${route.params.id}/terminals`))
        tills.value = data.data
    } catch (err) {
        tillsFailed.value = true
    } finally {
        tillsLoading.value = false
    }
}
onMounted(loadTills)

// The devices that have used this licence's key. This is the whole picture for
// an offline customer, who has no tenant and no terminals on the platform: it is
// the only sign the key ever reached a machine, which one, and when it last
// came back. Loaded on its own, for the same reason as the tills.
const activations = ref([])
const activatedAt = ref(null)
const activationsLocked = ref(false)
const activationsLoading = ref(false)
const activationsFailed = ref(false)
// "1 of 1 devices": how many the licence covers and how many have used the key.
// Only held for a local licence; a cloud licence's tills share one key.
const seats = ref({ enforced: false, seats: 0, inUse: 0 })
const seatsFull = computed(() => seats.value.enforced && seats.value.inUse >= seats.value.seats)
// A device id is a long hash: enough of both ends to tell two apart at a glance.
const shortDevice = (fp) => (fp && fp.length > 18 ? `${fp.slice(0, 8)}…${fp.slice(-6)}` : fp)

// Free a seat: for a machine that died, was replaced or was reinstalled under a
// new id. The device keeps the licence file it has; only a NEW activation is
// affected, so this is bookkeeping and not a revocation.
async function releaseDevice(a) {
    const ok = await confirm({
        title: t('licence.release_title'),
        message: t('licence.release_message'),
        confirmText: t('licence.release'),
        cancelText: t('common.cancel'),
        danger: true,
    })
    if (!ok) return
    try {
        await api.delete(`api/admin/pos/licences/${licence.value.id}/activations/${a.id}`)
        await loadActivations()
    } catch (err) {
        alert(err.response?.data?.message || t('common.error'))
    }
}

async function loadActivations() {
    activationsLoading.value = true
    activationsFailed.value = false
    try {
        const { data } = await api.get(`api/admin/pos/licences/${route.params.id}/activations`)
        activations.value = data.data
        activatedAt.value = data.activated_at
        activationsLocked.value = data.locked
        seats.value = { enforced: data.seats_enforced, seats: data.seats, inUse: data.in_use }
    } catch (err) {
        activationsFailed.value = true
    } finally {
        activationsLoading.value = false
    }
}

async function download() {
    const { data } = await api.get(`api/admin/pos/licences/${licence.value.id}/download`, { responseType: 'blob' })
    const url = URL.createObjectURL(data)
    const a = document.createElement('a')
    a.href = url
    a.download = `${licence.value.licence_ref}.xlic`
    a.click()
    URL.revokeObjectURL(url)
}

async function copyRenewedKey() {
    await navigator.clipboard.writeText(renewed.value.activation_key)
}

// The key, again. It used to be shown once at issuance and never after; a
// key not written down at that moment was gone, and the way forward was a
// renewal with a new key. Super Admin can now copy it from here (16 Oct 2026)
// — the platform keeps it encrypted and audits every read. A licence issued
// before that answers 404, and the button says so instead of hiding.
const keyCopied = ref(false)
const keyBusy = ref(false)
async function copyKey() {
    if (keyBusy.value) return
    keyBusy.value = true
    try {
        const { data } = await api.get(`api/admin/pos/licences/${licence.value.id}/key`)
        await navigator.clipboard.writeText(data.activation_key)
        keyCopied.value = true
        setTimeout(() => { keyCopied.value = false }, 2000)
    } catch (err) {
        alert(err?.response?.data?.message || t('common.error'))
    } finally {
        keyBusy.value = false
    }
}

function finishRenewal() {
    const id = renewed.value.data.id
    renewed.value = null
    acknowledged.value = false
    router.push({ name: 'admin.licences.show', params: { id } }).then(() => { load(); loadTills() })
}

// Display-only: which tone the header facts and status card wear. A held online
// licence is red whatever its dates say, the same call the badge makes.
const tone = computed(() => {
    const l = licence.value
    if (!l) return 'gray'
    if (isHeld.value && isLive.value) return 'red'
    return { active: 'green', expiring_soon: 'amber', in_grace: 'amber', expired: 'red', revoked: 'red' }[l.state] || 'gray'
})
</script>

<template>
    <div class="max-w-4xl space-y-5">
        <RouterLink :to="{ name: 'admin.licences' }" class="back-link">{{ backArrow }} {{ t('common.back') }}</RouterLink>

        <div v-if="loading" class="space-y-5">
            <Skeleton w="45%" h="34px" rounded="10px" />
            <div class="grid grid-cols-2 lg:grid-cols-4 gap-4">
                <Skeleton v-for="n in 4" :key="n" w="100%" h="96px" rounded="15px" />
            </div>
            <Skeleton w="100%" h="48px" rounded="10px" />
            <Skeleton w="100%" h="150px" rounded="15px" />
            <Skeleton w="100%" h="200px" rounded="15px" />
        </div>
        <ErrorState v-else-if="failed" :message="t('common.error')" @retry="load" />

        <template v-else-if="licence">
            <div class="flex flex-wrap items-start justify-between gap-3">
                <div class="min-w-0">
                    <h1 class="page-title mono ref-title">{{ licence.licence_ref }}</h1>
                    <p class="page-sub" style="color:var(--body)">{{ licence.client_name }}</p>
                </div>
                <div class="flex flex-wrap items-center gap-2">
                    <span class="badge" :class="licence.kind === 'offline' ? 'badge-gray' : 'badge-green'">{{ t('licence.kind.' + licence.kind) }}</span>
                    <!-- A held licence shows the dashboard status, not its dates' "Active". -->
                    <span v-if="isHeld && isLive" class="badge badge-red state-badge">{{ t('licence.op_status.' + licence.status) }}</span>
                    <span v-else class="badge state-badge" :class="badge(licence.state)">{{ t('licence.state.' + licence.state) }}</span>
                </div>
            </div>

            <!-- At a glance: when it ends, how many tills, which key, whether it was ever installed -->
            <section class="grid grid-cols-2 lg:grid-cols-4 gap-4" :aria-label="t('licence.ref')">
                <div class="stat fact" :class="'fact-' + tone">
                    <div class="stat-label">{{ t('licence.expires_at') }}</div>
                    <div class="fact-num">{{ licence.lifetime ? t('licence.lifetime_short') : dateOf(licence.expires_at) }}</div>
                    <div v-if="!licence.lifetime" class="fact-sub">{{ t('licence.grace_ends') }}: {{ dateOf(licence.grace_ends_at) }}</div>
                </div>
                <div class="stat fact">
                    <div class="stat-label">{{ t('licence.terminals') }}</div>
                    <div class="fact-num">{{ licence.max_terminals }}</div>
                </div>
                <div class="stat fact">
                    <div class="stat-label">{{ t('licence.key_tail') }}</div>
                    <div class="fact-num mono" dir="ltr">…{{ licence.key_last_four }}</div>
                    <button v-if="licence.key_available" type="button" class="btn btn-ghost btn-sm key-btn" :disabled="keyBusy" @click="copyKey">
                        <Icon :name="keyCopied ? 'check' : 'copy'" :size="13" />{{ keyCopied ? t('common.copied') : t('licence.copy_key') }}
                    </button>
                    <div v-else class="fact-sub" :title="t('licence.key_not_kept')">{{ t('licence.key_not_kept_short') }}</div>
                </div>
                <div class="stat fact">
                    <div class="stat-label">{{ t('licence.activated_at') }}</div>
                    <div class="fact-num" :class="{ 'fact-dim': !licence.activated_at }">{{ licence.activated_at ? dateOf(licence.activated_at) : t('licence.never_activated') }}</div>
                </div>
            </section>

            <div class="flex flex-wrap gap-3 actions">
                <button v-if="isLive" class="btn btn-accent" :disabled="busy" @click="renewing = true">{{ t('licence.renew') }}</button>
                <button class="btn btn-ghost" @click="download"><Icon name="download" :size="15" />{{ t('licence.download') }}</button>
                <!-- Only where a till will hear it: a signed-file licence never asks. -->
                <template v-if="isLive && licence.enforcement !== 'offline'">
                    <button v-if="isHeld" class="btn btn-ghost" :disabled="busy" @click="resume">{{ t('licence.resume') }}</button>
                    <template v-else>
                        <button class="btn btn-ghost act-amber" :disabled="busy" @click="openHold('suspend')">{{ t('licence.suspend') }}</button>
                        <button class="btn btn-ghost act-amber" :disabled="busy" @click="openHold('expire')">{{ t('licence.force_expire') }}</button>
                    </template>
                </template>
                <button v-if="isLive" class="btn btn-ghost act-red" :disabled="busy" @click="revoke">{{ t('licence.revoke') }}</button>
                <button v-if="isDeletable" class="btn btn-ghost act-red" :disabled="busy" @click="destroyLicence">{{ t('licence.delete') }}</button>
            </div>

            <!-- Where the till gets its verdict decides whether the status below
                 reaches it at all, so it sits with the status, before the terms. -->
            <section class="card p-5 space-y-4 edge" :class="'edge-' + tone">
                <h2 class="h-card">{{ t('licence.sec_status') }}</h2>
                <dl class="kv grid grid-cols-1 sm:grid-cols-3 gap-4">
                    <div><dt>{{ t('licence.enforcement_label') }}</dt><dd>{{ t('licence.enforcement.' + (licence.enforcement || 'online')) }}</dd></div>
                    <div><dt>{{ t('licence.op_status_label') }}</dt><dd>{{ t('licence.op_status.' + (licence.status || 'active')) }}</dd></div>
                    <div>
                        <dt>{{ t('licence.verdict_label') }}</dt>
                        <dd><span class="badge" :class="verdictBadge(licence.verdict)">{{ t('licence.verdict.' + (licence.verdict || 'unknown')) }}</span></dd>
                    </div>
                    <div v-if="licence.suspended_at"><dt>{{ t('licence.suspended_at') }}</dt><dd>{{ dateOf(licence.suspended_at) }}</dd></div>
                    <div v-if="licence.suspended_reason" class="sm:col-span-2"><dt>{{ t('licence.status_reason') }}</dt><dd class="plain">{{ licence.suspended_reason }}</dd></div>
                    <div v-if="licence.revoked_reason" class="sm:col-span-3"><dt>{{ t('licence.revoked_reason') }}</dt><dd class="plain">{{ licence.revoked_reason }}</dd></div>
                </dl>
                <p class="text-sm hint">{{ t(licence.enforcement === 'offline' ? 'licence.enforcement_offline_hint' : 'licence.enforcement_online_hint') }}</p>
            </section>

            <section class="card">
                <div class="px-5 pt-5 pb-3">
                    <h2 class="h-card">{{ t('licence.tills_title') }}</h2>
                    <p class="text-sm mt-1" style="color:var(--body)">{{ t(licence.kind === 'offline' ? 'licence.activations_subtitle' : 'licence.tills_subtitle') }}</p>
                </div>

                <!-- An offline customer's tills never reach the platform, but the
                     key does: each device that used it is recorded here. -->
                <template v-if="licence.kind === 'offline'">
                    <div v-if="activationsLoading" class="pb-3"><ListSkeleton :rows="2" /></div>
                    <div v-else-if="activationsFailed" class="px-5 pb-5"><ErrorState :message="t('common.error')" @retry="loadActivations" /></div>
                    <div v-else-if="!activations.length" class="px-5 pb-5 text-sm" style="color:var(--body)" data-test="activations-empty">
                        <p v-if="seats.enforced" class="font-semibold" style="color:var(--ink)">{{ t('licence.devices_used', { used: seats.inUse, seats: seats.seats }) }}</p>
                        <p v-if="activatedAt">{{ t('licence.activated_unrecorded', { date: dateOf(activatedAt) }) }}</p>
                        <p v-else>{{ t('licence.activations_none') }}</p>
                    </div>
                    <div v-else class="overflow-x-auto" data-test="activations">
                        <p v-if="seats.enforced" class="px-5 pb-3 text-sm font-semibold" style="color:var(--ink)" data-test="seats-used">
                            {{ t('licence.devices_used', { used: seats.inUse, seats: seats.seats }) }}
                        </p>
                        <p v-if="seatsFull" class="px-5 pb-3 text-sm" style="color:var(--body)" data-test="seats-full">{{ t('licence.seats_full_hint') }}</p>
                        <table class="w-full text-sm tills" style="min-width:560px">
                            <thead>
                                <tr>
                                    <th class="px-5 py-2.5 text-start">{{ t('licence.device') }}</th>
                                    <th class="px-3 py-2.5 text-center">{{ t('licence.first_seen') }}</th>
                                    <th class="px-3 py-2.5 text-center">{{ t('licence.last_seen') }}</th>
                                    <th class="px-3 py-2.5 text-center">{{ t('licence.times_used') }}</th>
                                    <th v-if="activationsLocked" class="px-3 py-2.5 text-center">{{ t('licence.locked_list') }}</th>
                                    <th class="px-3 py-2.5"><span class="sr-only">{{ t('licence.release') }}</span></th>
                                </tr>
                            </thead>
                            <tbody>
                                <tr v-for="a in activations" :key="a.fingerprint" class="till-row">
                                    <td class="px-5 py-3 text-start" style="color:var(--ink)">
                                        <bdi v-if="a.reported" dir="ltr" class="mono" :title="a.fingerprint">{{ shortDevice(a.fingerprint) }}</bdi>
                                        <span v-else style="color:var(--body)">{{ t('licence.device_unknown') }}</span>
                                    </td>
                                    <td class="px-3 py-3 text-center whitespace-nowrap" style="color:var(--body)">{{ stamp(a.first_seen_at) || '—' }}</td>
                                    <td class="px-3 py-3 text-center whitespace-nowrap" style="color:var(--body)">{{ stamp(a.last_seen_at) || '—' }}</td>
                                    <td class="px-3 py-3 text-center mono" style="color:var(--body)">{{ a.times }}</td>
                                    <td v-if="activationsLocked" class="px-3 py-3 text-center">
                                        <span class="badge" :class="a.pinned ? 'badge-green' : 'badge-red'">{{ a.pinned ? t('licence.on_locked_list') : t('licence.not_on_locked_list') }}</span>
                                    </td>
                                    <td class="px-3 py-3 text-end">
                                        <button class="btn btn-ghost btn-sm" data-test="release-device" @click="releaseDevice(a)">{{ t('licence.release') }}</button>
                                    </td>
                                </tr>
                            </tbody>
                        </table>
                    </div>
                </template>
                <div v-else-if="tillsLoading" class="pb-3"><ListSkeleton :rows="2" /></div>
                <div v-else-if="tillsFailed" class="px-5 pb-5"><ErrorState :message="t('common.error')" @retry="loadTills" /></div>
                <p v-else-if="!tills.length" class="px-5 pb-5 text-sm" style="color:var(--body)">{{ t('licence.tills_none') }}</p>
                <div v-else class="overflow-x-auto">
                    <table class="w-full text-sm tills" style="min-width:760px">
                        <thead>
                            <tr>
                                <th class="px-5 py-2.5 text-start">{{ t('common.name') }}</th>
                                <th class="px-3 py-2.5 text-start">{{ t('pos_terminals.branch') }}</th>
                                <th class="px-3 py-2.5 text-center">{{ t('common.status') }}</th>
                                <th class="px-3 py-2.5 text-center">{{ t('licence.deployment_mode') }}</th>
                                <th class="px-3 py-2.5 text-center">{{ t('pos_terminals.last_seen') }}</th>
                                <th class="px-3 py-2.5 text-center">{{ t('licence.last_check') }}</th>
                                <th class="px-3 py-2.5 text-center">{{ t('licence.reported_expiry') }}</th>
                                <th class="px-3 py-2.5 text-center">{{ t('pos_terminals.version') }}</th>
                            </tr>
                        </thead>
                        <tbody>
                            <tr v-for="x in tills" :key="x.id" class="till-row">
                                <td class="px-5 py-3 text-start font-semibold" style="color:var(--ink)">{{ x.name }}</td>
                                <td class="px-3 py-3 text-start" style="color:var(--body)">{{ termName(x.branch) }}</td>
                                <td class="px-3 py-3 text-center">
                                    <span class="badge" :class="{ active: 'badge-green', revoked: 'badge-red' }[x.state] || 'badge-gray'">{{ t('pos_terminals.state.' + x.state) }}</span>
                                </td>
                                <td class="px-3 py-3 text-center" style="color:var(--body)">{{ x.deployment_mode ? t('licence.mode.' + x.deployment_mode) : '—' }}</td>
                                <td class="px-3 py-3 text-center whitespace-nowrap" style="color:var(--body)">{{ stamp(x.last_seen_at) || '—' }}</td>
                                <td class="px-3 py-3 text-center whitespace-nowrap" style="color:var(--body)">{{ stamp(x.last_licence_check_at) || t('licence.never_checked') }}</td>
                                <td class="px-3 py-3 text-center whitespace-nowrap" style="color:var(--body)">{{ x.reported_licence_expires_at ? dateOf(x.reported_licence_expires_at) : '—' }}</td>
                                <td class="px-3 py-3 text-center mono" style="color:var(--body)">{{ x.app_version || '—' }}</td>
                            </tr>
                        </tbody>
                    </table>
                </div>
            </section>

            <!-- An offline customer exists only here. There is no tenant page
                 to click through to, and that is the design, not a gap. -->
            <section v-if="licence.kind === 'offline'" class="card p-5 space-y-4">
                <h2 class="h-card">{{ t('licence.sec_customer') }}</h2>
                <dl class="kv grid grid-cols-1 sm:grid-cols-2 gap-4">
                    <div><dt>{{ t('licence.customer_name') }}</dt><dd>{{ licence.customer_name }}</dd></div>
                    <div><dt>{{ t('licence.customer_slug') }}</dt><dd class="mono" dir="ltr">{{ licence.customer_slug }}</dd></div>
                    <div v-if="licence.contact_name"><dt>{{ t('licence.contact_name') }}</dt><dd>{{ licence.contact_name }}</dd></div>
                    <div v-if="licence.contact_phone"><dt>{{ t('licence.contact_phone') }}</dt><dd class="mono" dir="ltr">{{ licence.contact_phone }}</dd></div>
                    <div v-if="licence.contact_email" class="sm:col-span-2"><dt>{{ t('licence.contact_email') }}</dt><dd class="mono" dir="ltr">{{ licence.contact_email }}</dd></div>
                </dl>
                <p class="text-sm hint">{{ t('licence.offline_no_tenant') }}</p>
            </section>

            <section class="card p-5 space-y-4">
                <h2 class="h-card">{{ t('licence.sec_terms') }}</h2>
                <dl class="kv grid grid-cols-1 sm:grid-cols-2 gap-4">
                    <div><dt>{{ t('licence.issued_at') }}</dt><dd>{{ dateOf(licence.issued_at) }}</dd></div>
                    <div><dt>{{ t('licence.max_users') }}</dt><dd>{{ licence.max_users ?? t('licence.unlimited') }}</dd></div>
                    <div><dt>{{ t('licence.max_offline_days') }}</dt><dd>{{ licence.max_offline_days ?? t('licence.unlimited') }}</dd></div>
                    <div>
                        <dt>{{ t('licence.modes') }}</dt>
                        <dd class="flex flex-wrap gap-1.5">
                            <span v-for="m in licence.modes" :key="m" class="lic-chip">{{ t('licence.mode.' + m) }}</span>
                        </dd>
                    </div>
                    <div v-if="licence.notes" class="sm:col-span-2"><dt>{{ t('licence.notes') }}</dt><dd class="plain">{{ licence.notes }}</dd></div>
                </dl>
            </section>

            <!-- The claims exactly as the till will read them, so an operator can
                 see what was signed without base64-decoding anything by hand. -->
            <details class="card claims">
                <summary class="px-5 py-4 cursor-pointer select-none flex items-center justify-between gap-3">
                    <span class="h-card">{{ t('licence.claims') }}</span>
                    <Icon name="chevronDown" :size="16" class="chev" style="color:var(--body)" />
                </summary>
                <pre class="mono mx-5 mb-5 p-4 overflow-x-auto text-xs claims-pre" dir="ltr">{{ JSON.stringify(claims, null, 2) }}</pre>
            </details>
        </template>

        <Modal v-if="renewing" :title="t('licence.renew')" :subtitle="t('licence.renew_subtitle')" @close="renewing = false">
            <form @submit.prevent="submitRenewal" class="space-y-4">
                <fieldset class="space-y-2">
                    <legend class="label">{{ t('licence.renew_start') }}</legend>
                    <label class="opt text-sm cursor-pointer">
                        <input type="radio" name="renew_start" class="mt-0.5" :checked="startMode === 'today'" @change="applyStart('today')" />
                        <span>
                            {{ t('licence.renew_start_today') }}
                            <span class="block text-xs opt-hint">{{ t('licence.renew_start_today_hint') }}</span>
                        </span>
                    </label>
                    <label v-if="currentEnd" class="opt text-sm cursor-pointer">
                        <input type="radio" name="renew_start" class="mt-0.5" :checked="startMode === 'after_current'" @change="applyStart('after_current')" />
                        <span>
                            {{ t('licence.renew_start_after_current', { date: dayLabel(currentEnd) }) }}
                            <span class="block text-xs opt-hint">{{ t('licence.renew_start_after_current_hint') }}</span>
                        </span>
                    </label>
                </fieldset>

                <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                    <label class="block">
                        <span class="label">{{ t('licence.issued_at') }}</span>
                        <input v-model="renewForm.issued_at" type="date" class="input" />
                        <FormError :errors="renewErrors" field="issued_at" />
                    </label>
                    <label v-if="!renewForm.lifetime" class="block">
                        <span class="label">{{ t('licence.expires_at') }}</span>
                        <input v-model="renewForm.expires_at" type="date" class="input" @input="expiresTouched = true" />
                        <FormError :errors="renewErrors" field="expires_at" />
                    </label>
                </div>

                <!-- Renewal is also how a licence is edited and upgraded. The old
                     licence is kept exactly as it was; this signs the new terms. -->
                <fieldset class="space-y-4 terms" data-test="renew-terms">
                    <legend class="label">{{ t('licence.renew_terms') }}</legend>
                    <p class="text-sm" style="color:var(--body)">{{ t('licence.renew_terms_hint') }}</p>

                    <label class="opt text-sm cursor-pointer">
                        <input type="checkbox" v-model="renewForm.lifetime" class="h-4 w-4 mt-0.5" data-test="renew-lifetime" />
                        <span>{{ t('licence.lifetime') }}<span class="block text-xs opt-hint">{{ t('licence.lifetime_hint') }}</span></span>
                    </label>

                    <label v-if="isOffline" class="block">
                        <span class="label">{{ t('licence.customer_name') }}</span>
                        <input v-model="renewForm.customer_name" class="input" maxlength="255" data-test="renew-customer-name" />
                        <FormError :errors="renewErrors" field="customer_name" />
                    </label>

                    <template v-if="!isOffline">
                        <label class="block">
                            <span class="label">{{ t('licence.plan') }}</span>
                            <select v-model="renewForm.plan_id" class="input" data-test="renew-plan" @change="onPlanChange">
                                <option value="">{{ t('licence.no_plan') }}</option>
                                <option v-for="p in plans" :key="p.id" :value="p.id">{{ p.name }}</option>
                            </select>
                            <FormError :errors="renewErrors" field="plan_id" />
                        </label>

                        <fieldset class="space-y-2">
                            <legend class="label">{{ t('licence.features') }}</legend>
                            <div class="grid grid-cols-2 sm:grid-cols-3 gap-2">
                                <label v-for="f in featureChoices" :key="f" class="flex items-center gap-2 text-sm">
                                    <input type="checkbox" class="h-4 w-4" :checked="renewForm.features.includes(f)"
                                        :data-test="'renew-feature-' + f" @change="toggleIn(renewForm.features, f, $event.target.checked)" />
                                    <span class="mono">{{ f }}</span>
                                </label>
                            </div>
                            <FormError :errors="renewErrors" field="features" />
                        </fieldset>

                        <fieldset class="space-y-2">
                            <legend class="label">{{ t('licence.modes') }}</legend>
                            <div class="flex flex-wrap gap-4">
                                <label v-for="m in MODES" :key="m" class="flex items-center gap-2 text-sm">
                                    <input type="radio" name="renew-mode" class="h-4 w-4" :checked="renewForm.modes.map(asMode).includes(m)"
                                        :data-test="'renew-mode-' + m" @change="renewForm.modes = [m]" />
                                    {{ t('licence.mode.' + m) }}
                                </label>
                            </div>
                            <FormError :errors="renewErrors" field="modes" />
                        </fieldset>
                    </template>
                    <p v-else class="text-sm" style="color:var(--body)">{{ t('licence.offline_all_features') }}</p>

                    <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                        <label class="block">
                            <span class="label">{{ t('licence.max_terminals') }}</span>
                            <input v-model="renewForm.max_terminals" type="number" min="1" max="1000" class="input" dir="ltr" data-test="renew-max-terminals" />
                            <FormError :errors="renewErrors" field="max_terminals" />
                        </label>
                        <label class="block">
                            <span class="label">{{ t('licence.max_users') }}</span>
                            <input v-model="renewForm.max_users" type="number" min="1" max="1000" class="input" dir="ltr" data-test="renew-max-users" />
                            <span class="block text-xs opt-hint">{{ t('licence.max_users_hint') }}</span>
                            <FormError :errors="renewErrors" field="max_users" />
                        </label>
                        <label class="block">
                            <span class="label">{{ t('licence.max_offline_days') }}</span>
                            <input v-model="renewForm.max_offline_days" type="number" min="1" max="365" class="input" dir="ltr" data-test="renew-max-offline-days" />
                            <FormError :errors="renewErrors" field="max_offline_days" />
                        </label>
                        <label class="block">
                            <span class="label">{{ t('licence.grace_days') }}</span>
                            <input v-model="renewForm.grace_days" type="number" min="0" max="365" class="input" dir="ltr" />
                            <FormError :errors="renewErrors" field="grace_days" />
                        </label>
                        <label class="block">
                            <span class="label">{{ t('licence.warn_days') }}</span>
                            <input v-model="renewForm.warn_days" type="number" min="0" max="365" class="input" dir="ltr" />
                            <FormError :errors="renewErrors" field="warn_days" />
                        </label>
                    </div>

                    <label class="block">
                        <span class="label">{{ t('licence.fingerprints') }}</span>
                        <textarea v-model="renewForm.fingerprints" rows="2" class="input mono" dir="ltr" data-test="renew-fingerprints"></textarea>
                        <span class="block text-xs opt-hint">{{ t('licence.fingerprints_hint') }}</span>
                        <FormError :errors="renewErrors" field="fingerprints" />
                    </label>
                    <p v-if="devicesChanged" class="warn-box text-sm" data-test="renew-devices-warning">{{ t('licence.fingerprints_changed') }}</p>

                    <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                        <label class="block">
                            <span class="label">{{ t('licence.contact_name') }}</span>
                            <input v-model="renewForm.contact_name" class="input" maxlength="255" />
                        </label>
                        <label class="block">
                            <span class="label">{{ t('licence.contact_email') }}</span>
                            <input v-model="renewForm.contact_email" type="email" class="input" dir="ltr" />
                            <FormError :errors="renewErrors" field="contact_email" />
                        </label>
                        <label class="block">
                            <span class="label">{{ t('licence.contact_phone') }}</span>
                            <input v-model="renewForm.contact_phone" class="input" dir="ltr" inputmode="tel" />
                        </label>
                    </div>
                    <label class="block">
                        <span class="label">{{ t('licence.notes') }}</span>
                        <textarea v-model="renewForm.notes" rows="2" class="input" maxlength="2000"></textarea>
                        <span class="block text-xs opt-hint">{{ t('licence.notes_hint') }}</span>
                    </label>
                </fieldset>

                <div class="changes-box" data-test="renew-changes">
                    <p class="label">{{ t('licence.renew_changes') }}</p>
                    <p v-if="!changes.length" class="text-sm" style="color:var(--body)">{{ t('licence.renew_no_changes') }}</p>
                    <ul v-else class="text-sm space-y-1">
                        <li v-for="c in changes" :key="c.label"><strong>{{ c.label }}</strong>: <span class="mono">{{ c.from }}</span> → <span class="mono">{{ c.to }}</span></li>
                    </ul>
                </div>

                <p v-if="startsInFuture" class="warn-box text-sm">
                    {{ t('licence.renew_starts_future', { date: dayLabel(renewForm.issued_at) }) }}
                </p>

                <label class="opt text-sm cursor-pointer">
                    <input type="checkbox" v-model="renewForm.rotate_key" class="h-4 w-4 mt-0.5" />
                    <span>
                        {{ t('licence.rotate_key') }}
                        <span class="block text-xs opt-hint">{{ t('licence.rotate_key_hint') }}</span>
                    </span>
                </label>

                <p class="text-sm" style="color:var(--body)">{{ t('licence.renew_hint') }}</p>

                <div class="flex flex-wrap gap-3">
                    <button type="submit" class="btn btn-accent" :disabled="busy">{{ t('licence.renew') }}</button>
                    <button type="button" class="btn btn-ghost" @click="renewing = false">{{ t('common.cancel') }}</button>
                </div>
            </form>
        </Modal>

        <Modal v-if="holding" :title="t(holding === 'suspend' ? 'licence.suspend_title' : 'licence.expire_title')"
            :subtitle="t(holding === 'suspend' ? 'licence.suspend_subtitle' : 'licence.expire_subtitle')" @close="holding = null">
            <form @submit.prevent="submitHold" class="space-y-4">
                <label class="block">
                    <span class="label">{{ t('licence.status_reason') }}</span>
                    <input v-model="holdReason" class="input" maxlength="255" />
                    <span class="block text-sm mt-1" style="color:var(--body)">{{ t('licence.reason_hint') }}</span>
                    <FormError :errors="holdErrors" field="reason" />
                </label>
                <div class="flex flex-wrap gap-3">
                    <button type="submit" class="btn btn-accent" :disabled="busy">{{ t(holding === 'suspend' ? 'licence.suspend' : 'licence.force_expire') }}</button>
                    <button type="button" class="btn btn-ghost" @click="holding = null">{{ t('common.cancel') }}</button>
                </div>
            </form>
        </Modal>

        <!-- Only reached when the key was rotated: there is no way to show an
             unchanged key, because the server holds only its HMAC. -->
        <Modal v-if="renewed?.activation_key" :title="t('licence.issued_title')" :subtitle="t('licence.issued_subtitle')" @close="() => {}">
            <div class="space-y-5">
                <div class="warn-box">
                    <p class="text-sm" style="color:var(--ink)">{{ t('licence.key_once_warning') }}</p>
                </div>
                <div>
                    <span class="label">{{ t('licence.activation_key') }}</span>
                    <div class="flex flex-wrap items-stretch gap-2 mt-1.5">
                        <code class="mono key-box" dir="ltr">{{ renewed.activation_key }}</code>
                        <button type="button" class="btn btn-ghost" @click="copyRenewedKey"><Icon name="copy" :size="15" />{{ t('common.copy') }}</button>
                    </div>
                </div>
                <label class="opt text-sm cursor-pointer">
                    <input type="checkbox" v-model="acknowledged" class="h-4 w-4 mt-0.5" />
                    <span>{{ t('licence.key_acknowledge') }}</span>
                </label>
                <button type="button" class="btn btn-accent w-full" :disabled="!acknowledged" @click="finishRenewal">{{ t('common.done') }}</button>
            </div>
        </Modal>
    </div>
</template>

<style scoped>
/* Colours come from the shared theme variables and the PrimeVue primary scale. */
.back-link { display: inline-flex; align-items: center; min-height: 44px; font-size: 14px; font-weight: 500; color: var(--body); }
.back-link:hover { color: var(--ink); }
.ref-title { word-break: break-all; }

/* Modal labels are block-level here (the theme's .label is inline, written for forms) */
.label { display: block; margin-bottom: 2px; }

/* Badge text on tinted fills: the theme's amber and gray text sit near 4:1 */
.badge-amber { color: var(--p-primary-800); }
.badge-gray { color: var(--body); }
.state-badge { font-size: 14px; padding: 6px 14px; }

/* Headline facts */
.fact { display: flex; flex-direction: column; gap: 4px; min-width: 0; padding: 16px 18px; }
.fact .stat-label { color: var(--body); }
.fact-num { font-family: var(--font-display); font-weight: 700; font-size: 22px; line-height: 1.2; color: var(--ink); overflow-wrap: anywhere; }
.fact-dim { color: var(--body); font-weight: 600; font-size: 17px; }
.fact-sub { font-size: 13.5px; color: var(--body); }
.fact-amber { background: var(--amber-soft); }
.fact-amber .fact-num, .fact-amber .stat-label, .fact-amber .fact-sub { color: var(--p-primary-800); }
.fact-red { background: var(--red-soft); }
.fact-red .fact-num { color: var(--red); }
.key-btn { align-self: flex-start; min-height: 36px; }

/* Actions */
.actions .btn { min-height: 44px; }
.act-amber { color: var(--p-primary-800); }
.act-red { color: var(--red); }

/* Status card carries the licence's tone on its leading edge */
.edge { border-inline-start: 4px solid var(--line); }
.edge-green { border-inline-start-color: var(--green); }
.edge-amber { border-inline-start-color: var(--accent); }
.edge-red { border-inline-start-color: var(--red); }

/* Label / value pairs */
.kv dt { font-size: 13.5px; font-weight: 500; color: var(--body); margin-bottom: 3px; }
.kv dd { margin: 0; font-size: 15px; font-weight: 500; color: var(--ink); overflow-wrap: anywhere; }
/* A value that must read left to right (an identifier, a phone, an email) still
   sits on the SAME edge as its label. `dir="ltr"` on the <dd> makes the box
   left-aligned, so in an Arabic page the labels were on the right and these
   values on the left. The text stays LTR; only the alignment follows the page. */
[dir="rtl"] .kv dd[dir="ltr"] { text-align: right; }
.kv dd.plain { font-weight: 400; color: var(--body); }
.hint { color: var(--body); padding-top: 12px; border-top: 1px solid var(--line); }
.lic-chip { font-size: 12.5px; font-weight: 600; padding: 3px 10px; border-radius: 999px; white-space: nowrap;
    background: var(--accent-soft); color: var(--p-primary-800); }

/* Tills table */
.tills th { font-size: 12px; font-weight: 600; letter-spacing: .04em; text-transform: uppercase; color: var(--body);
    background: var(--page); white-space: nowrap; }
.till-row { border-top: 1px solid var(--line); transition: background .15s; }
.till-row:hover { background: var(--page); }

/* Claims */
.claims summary { list-style: none; }
.claims summary::-webkit-details-marker { display: none; }
.claims .chev { transition: transform .2s ease; flex: none; }
.claims[open] .chev { transform: rotate(180deg); }
.claims-pre { background: var(--page); border-radius: 10px; color: var(--body); }

/* Modals */
.opt { display: flex; align-items: flex-start; gap: 10px; padding: 12px 14px; border: 1px solid var(--line);
    border-radius: 12px; color: var(--ink); background: var(--card); }
.opt:hover { border-color: var(--muted); }
.opt:has(input:checked) { border-color: var(--accent); background: var(--accent-soft); }
.opt-hint { color: var(--body); margin-top: 2px; }
.terms { border: 1px solid var(--line); border-radius: 12px; padding: 14px; }
.changes-box { padding: 12px 14px; border-radius: 12px; background: var(--accent-soft); border: 1px solid var(--line); }
.warn-box { padding: 12px 14px; border-radius: 12px; background: var(--amber-soft); border: 1px solid var(--accent);
    color: var(--p-primary-800); }
.key-box { flex: 1 1 220px; min-width: 0; display: flex; align-items: center; padding: 10px 14px; border-radius: 10px;
    border: 1px solid var(--line); background: var(--page); font-size: 16px; letter-spacing: .08em; color: var(--ink);
    overflow-wrap: anywhere; }
</style>
