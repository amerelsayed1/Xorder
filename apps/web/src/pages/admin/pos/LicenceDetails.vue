<script setup>
import { ref, reactive, computed, onMounted, watch } from 'vue'
import { useRoute, useRouter, RouterLink } from 'vue-router'
import { useI18n } from 'vue-i18n'
import api from '@xorder/api-client/api.js'
import Icon from '@xorder/ui/Icon.vue'
import Modal from '@xorder/ui/Modal.vue'
import FormError from '@xorder/ui/FormError.vue'
import ListSkeleton from '@xorder/ui/ListSkeleton.vue'
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
})

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
        const { data } = await api.post(`api/admin/pos/licences/${licence.value.id}/renew`, {
            issued_at: renewForm.issued_at,
            expires_at: renewForm.expires_at,
            rotate_key: renewForm.rotate_key,
        })
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
</script>

<template>
    <div class="max-w-3xl space-y-5">
        <RouterLink :to="{ name: 'admin.licences' }" class="text-sm" style="color:var(--muted)">{{ backArrow }} {{ t('common.back') }}</RouterLink>

        <ListSkeleton v-if="loading" :rows="4" />
        <ErrorState v-else-if="failed" :message="t('common.error')" @retry="load" />

        <template v-else-if="licence">
            <div class="flex items-start justify-between gap-3">
                <div>
                    <h1 class="page-title mono">{{ licence.licence_ref }}</h1>
                    <p class="page-sub">{{ licence.client_name }}</p>
                </div>
                <div class="flex items-center gap-2">
                    <span class="badge" :class="licence.kind === 'offline' ? 'badge-gray' : 'badge-green'">{{ t('licence.kind.' + licence.kind) }}</span>
                    <!-- A held licence shows the dashboard status, not its dates' "Active". -->
                    <span v-if="isHeld && isLive" class="badge badge-red">{{ t('licence.op_status.' + licence.status) }}</span>
                    <span v-else class="badge" :class="badge(licence.state)">{{ t('licence.state.' + licence.state) }}</span>
                </div>
            </div>

            <!-- Where the till gets its verdict decides whether the status below
                 reaches it at all — said before the buttons, not after. -->
            <div class="card p-6 space-y-4 text-sm">
                <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
                    <div><span class="label">{{ t('licence.enforcement_label') }}</span><span style="color:var(--ink)">{{ t('licence.enforcement.' + (licence.enforcement || 'online')) }}</span></div>
                    <div><span class="label">{{ t('licence.op_status_label') }}</span><span style="color:var(--ink)">{{ t('licence.op_status.' + (licence.status || 'active')) }}</span></div>
                    <div>
                        <span class="label">{{ t('licence.verdict_label') }}</span>
                        <span class="badge" :class="verdictBadge(licence.verdict)">{{ t('licence.verdict.' + (licence.verdict || 'unknown')) }}</span>
                    </div>
                    <div v-if="licence.suspended_at"><span class="label">{{ t('licence.suspended_at') }}</span><span style="color:var(--ink)">{{ dateOf(licence.suspended_at) }}</span></div>
                    <div v-if="licence.suspended_reason" class="sm:col-span-2"><span class="label">{{ t('licence.status_reason') }}</span><span style="color:var(--body)">{{ licence.suspended_reason }}</span></div>
                </div>
                <p class="text-xs" style="color:var(--muted)">{{ t(licence.enforcement === 'offline' ? 'licence.enforcement_offline_hint' : 'licence.enforcement_online_hint') }}</p>
            </div>

            <!-- An offline customer exists only here. There is no tenant page
                 to click through to, and that is the design, not a gap. -->
            <div v-if="licence.kind === 'offline'" class="card p-6 grid grid-cols-1 sm:grid-cols-2 gap-4 text-sm">
                <div><span class="label">{{ t('licence.customer_name') }}</span><span style="color:var(--ink)">{{ licence.customer_name }}</span></div>
                <div><span class="label">{{ t('licence.customer_slug') }}</span><span class="mono" dir="ltr" style="color:var(--ink)">{{ licence.customer_slug }}</span></div>
                <div v-if="licence.contact_name"><span class="label">{{ t('licence.contact_name') }}</span><span style="color:var(--ink)">{{ licence.contact_name }}</span></div>
                <div v-if="licence.contact_phone"><span class="label">{{ t('licence.contact_phone') }}</span><span class="mono" dir="ltr" style="color:var(--ink)">{{ licence.contact_phone }}</span></div>
                <div v-if="licence.contact_email" class="sm:col-span-2"><span class="label">{{ t('licence.contact_email') }}</span><span class="mono" dir="ltr" style="color:var(--ink)">{{ licence.contact_email }}</span></div>
                <p class="sm:col-span-2 text-xs" style="color:var(--muted)">{{ t('licence.offline_no_tenant') }}</p>
            </div>

            <div class="card p-6 grid grid-cols-1 sm:grid-cols-2 gap-4 text-sm">
                <div><span class="label">{{ t('licence.issued_at') }}</span><span style="color:var(--ink)">{{ dateOf(licence.issued_at) }}</span></div>
                <div><span class="label">{{ t('licence.expires_at') }}</span><span style="color:var(--ink)">{{ licence.lifetime ? t('licence.lifetime_short') : dateOf(licence.expires_at) }}</span></div>
                <div v-if="!licence.lifetime"><span class="label">{{ t('licence.grace_ends') }}</span><span style="color:var(--ink)">{{ dateOf(licence.grace_ends_at) }}</span></div>
                <div><span class="label">{{ t('licence.terminals') }}</span><span style="color:var(--ink)">{{ licence.max_terminals }}</span></div>
                <div><span class="label">{{ t('licence.max_users') }}</span><span style="color:var(--ink)">{{ licence.max_users ?? t('licence.unlimited') }}</span></div>
                <div><span class="label">{{ t('licence.modes') }}</span><span style="color:var(--ink)">{{ licence.modes.map((m) => t('licence.mode.' + m)).join(' · ') }}</span></div>
                <div>
                    <span class="label">{{ t('licence.key_tail') }}</span>
                    <span class="flex items-center gap-2 flex-wrap">
                        <span class="mono" style="color:var(--ink)">…{{ licence.key_last_four }}</span>
                        <button v-if="licence.key_available" type="button" class="btn btn-ghost" style="padding:2px 8px;font-size:12px" :disabled="keyBusy" @click="copyKey">
                            <Icon :name="keyCopied ? 'check' : 'copy'" :size="13" />{{ keyCopied ? t('common.copied') : t('licence.copy_key') }}
                        </button>
                        <span v-else class="text-xs" style="color:var(--muted)" :title="t('licence.key_not_kept')">{{ t('licence.key_not_kept_short') }}</span>
                    </span>
                </div>
                <div><span class="label">{{ t('licence.max_offline_days') }}</span><span style="color:var(--ink)">{{ licence.max_offline_days ?? t('licence.unlimited') }}</span></div>
                <div><span class="label">{{ t('licence.activated_at') }}</span><span style="color:var(--ink)">{{ licence.activated_at ? dateOf(licence.activated_at) : t('licence.never_activated') }}</span></div>
                <div v-if="licence.notes" class="sm:col-span-2"><span class="label">{{ t('licence.notes') }}</span><span style="color:var(--body)">{{ licence.notes }}</span></div>
                <div v-if="licence.revoked_reason" class="sm:col-span-2"><span class="label">{{ t('licence.revoked_reason') }}</span><span style="color:var(--body)">{{ licence.revoked_reason }}</span></div>
            </div>

            <div class="flex flex-wrap gap-3">
                <button v-if="isLive" class="btn btn-accent" :disabled="busy" @click="renewing = true">{{ t('licence.renew') }}</button>
                <button class="btn btn-ghost" @click="download"><Icon name="download" :size="15" />{{ t('licence.download') }}</button>
                <!-- Only where a till will hear it: a signed-file licence never asks. -->
                <template v-if="isLive && licence.enforcement !== 'offline'">
                    <button v-if="isHeld" class="btn btn-ghost" :disabled="busy" @click="resume">{{ t('licence.resume') }}</button>
                    <template v-else>
                        <button class="btn btn-ghost" style="color:var(--amber)" :disabled="busy" @click="openHold('suspend')">{{ t('licence.suspend') }}</button>
                        <button class="btn btn-ghost" style="color:var(--amber)" :disabled="busy" @click="openHold('expire')">{{ t('licence.force_expire') }}</button>
                    </template>
                </template>
                <button v-if="isLive" class="btn btn-ghost" style="color:var(--red)" :disabled="busy" @click="revoke">{{ t('licence.revoke') }}</button>
                <button v-if="isDeletable" class="btn btn-ghost" style="color:var(--red)" :disabled="busy" @click="destroyLicence">{{ t('licence.delete') }}</button>
            </div>

            <div class="card">
                <div class="px-6 pt-5 pb-3">
                    <h2 class="h-card">{{ t('licence.tills_title') }}</h2>
                    <p class="text-xs mt-1" style="color:var(--muted)">{{ t('licence.tills_subtitle') }}</p>
                </div>
                <p v-if="licence.kind === 'offline'" class="px-6 pb-5 text-sm" style="color:var(--muted)">{{ t('licence.tills_offline') }}</p>
                <div v-else-if="tillsLoading" class="px-6 pb-5"><ListSkeleton :rows="2" /></div>
                <div v-else-if="tillsFailed" class="px-6 pb-5"><ErrorState :message="t('common.error')" @retry="loadTills" /></div>
                <p v-else-if="!tills.length" class="px-6 pb-5 text-sm" style="color:var(--muted)">{{ t('licence.tills_none') }}</p>
                <div v-else class="overflow-x-auto">
                    <table class="w-full text-sm" style="min-width:720px">
                        <thead>
                            <tr style="color:var(--muted)">
                                <th class="px-6 py-2 font-medium text-start" style="font-size:11px;text-transform:uppercase">{{ t('common.name') }}</th>
                                <th class="px-3 py-2 font-medium text-start" style="font-size:11px;text-transform:uppercase">{{ t('pos_terminals.branch') }}</th>
                                <th class="px-3 py-2 font-medium text-center" style="font-size:11px;text-transform:uppercase">{{ t('common.status') }}</th>
                                <th class="px-3 py-2 font-medium text-center" style="font-size:11px;text-transform:uppercase">{{ t('licence.deployment_mode') }}</th>
                                <th class="px-3 py-2 font-medium text-center" style="font-size:11px;text-transform:uppercase">{{ t('pos_terminals.last_seen') }}</th>
                                <th class="px-3 py-2 font-medium text-center" style="font-size:11px;text-transform:uppercase">{{ t('licence.last_check') }}</th>
                                <th class="px-3 py-2 font-medium text-center" style="font-size:11px;text-transform:uppercase">{{ t('licence.reported_expiry') }}</th>
                                <th class="px-3 py-2 font-medium text-center" style="font-size:11px;text-transform:uppercase">{{ t('pos_terminals.version') }}</th>
                            </tr>
                        </thead>
                        <tbody>
                            <tr v-for="x in tills" :key="x.id" class="border-t" :style="{ borderColor: 'var(--line)', opacity: x.state === 'revoked' ? 0.6 : 1 }">
                                <td class="px-6 py-2.5 text-start" style="color:var(--ink)">{{ x.name }}</td>
                                <td class="px-3 py-2.5 text-start" style="color:var(--body)">{{ termName(x.branch) }}</td>
                                <td class="px-3 py-2.5 text-center">
                                    <span class="badge" :class="{ active: 'badge-green', revoked: 'badge-red' }[x.state] || 'badge-gray'">{{ t('pos_terminals.state.' + x.state) }}</span>
                                </td>
                                <td class="px-3 py-2.5 text-center" style="color:var(--body)">{{ x.deployment_mode ? t('licence.mode.' + x.deployment_mode) : '—' }}</td>
                                <td class="px-3 py-2.5 text-center" style="color:var(--body)">{{ stamp(x.last_seen_at) || '—' }}</td>
                                <td class="px-3 py-2.5 text-center" style="color:var(--body)">{{ stamp(x.last_licence_check_at) || t('licence.never_checked') }}</td>
                                <td class="px-3 py-2.5 text-center" style="color:var(--body)">{{ x.reported_licence_expires_at ? dateOf(x.reported_licence_expires_at) : '—' }}</td>
                                <td class="px-3 py-2.5 text-center mono" style="color:var(--muted)">{{ x.app_version || '—' }}</td>
                            </tr>
                        </tbody>
                    </table>
                </div>
            </div>

            <!-- The claims exactly as the till will read them, so an operator can
                 see what was signed without base64-decoding anything by hand. -->
            <details class="card p-6">
                <summary class="label cursor-pointer" style="margin:0">{{ t('licence.claims') }}</summary>
                <pre class="mono mt-3 overflow-x-auto text-xs" style="color:var(--body)">{{ JSON.stringify(claims, null, 2) }}</pre>
            </details>
        </template>

        <Modal v-if="renewing" :title="t('licence.renew')" :subtitle="t('licence.renew_subtitle')" @close="renewing = false">
            <form @submit.prevent="submitRenewal" class="space-y-4">
                <fieldset class="space-y-2">
                    <legend class="label">{{ t('licence.renew_start') }}</legend>
                    <label class="flex items-start gap-2 text-sm cursor-pointer" style="color:var(--ink)">
                        <input type="radio" name="renew_start" class="mt-0.5" :checked="startMode === 'today'" @change="applyStart('today')" />
                        <span>
                            {{ t('licence.renew_start_today') }}
                            <span class="block text-xs" style="color:var(--muted)">{{ t('licence.renew_start_today_hint') }}</span>
                        </span>
                    </label>
                    <label v-if="currentEnd" class="flex items-start gap-2 text-sm cursor-pointer" style="color:var(--ink)">
                        <input type="radio" name="renew_start" class="mt-0.5" :checked="startMode === 'after_current'" @change="applyStart('after_current')" />
                        <span>
                            {{ t('licence.renew_start_after_current', { date: dayLabel(currentEnd) }) }}
                            <span class="block text-xs" style="color:var(--muted)">{{ t('licence.renew_start_after_current_hint') }}</span>
                        </span>
                    </label>
                </fieldset>

                <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                    <label class="block">
                        <span class="label">{{ t('licence.issued_at') }}</span>
                        <input v-model="renewForm.issued_at" type="date" class="input" />
                        <FormError :errors="renewErrors" field="issued_at" />
                    </label>
                    <label class="block">
                        <span class="label">{{ t('licence.expires_at') }}</span>
                        <input v-model="renewForm.expires_at" type="date" class="input" @input="expiresTouched = true" />
                        <FormError :errors="renewErrors" field="expires_at" />
                    </label>
                </div>

                <p v-if="startsInFuture" class="rounded-lg p-3 text-sm" style="background:var(--amber-soft);color:var(--amber)">
                    {{ t('licence.renew_starts_future', { date: dayLabel(renewForm.issued_at) }) }}
                </p>

                <label class="flex items-start gap-2 text-sm cursor-pointer" style="color:var(--ink)">
                    <input type="checkbox" v-model="renewForm.rotate_key" class="h-4 w-4 mt-0.5" />
                    <span>
                        {{ t('licence.rotate_key') }}
                        <span class="block text-xs" style="color:var(--muted)">{{ t('licence.rotate_key_hint') }}</span>
                    </span>
                </label>

                <p class="text-xs" style="color:var(--muted)">{{ t('licence.renew_hint') }}</p>

                <div class="flex gap-3">
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
                    <span class="block text-xs mt-1" style="color:var(--muted)">{{ t('licence.reason_hint') }}</span>
                    <FormError :errors="holdErrors" field="reason" />
                </label>
                <div class="flex gap-3">
                    <button type="submit" class="btn btn-accent" :disabled="busy">{{ t(holding === 'suspend' ? 'licence.suspend' : 'licence.force_expire') }}</button>
                    <button type="button" class="btn btn-ghost" @click="holding = null">{{ t('common.cancel') }}</button>
                </div>
            </form>
        </Modal>

        <!-- Only reached when the key was rotated: there is no way to show an
             unchanged key, because the server holds only its HMAC. -->
        <Modal v-if="renewed?.activation_key" :title="t('licence.issued_title')" :subtitle="t('licence.issued_subtitle')" @close="() => {}">
            <div class="space-y-5">
                <div class="rounded-lg border p-4" style="border-color:var(--amber);background:var(--amber-soft)">
                    <p class="text-sm" style="color:var(--ink)">{{ t('licence.key_once_warning') }}</p>
                </div>
                <div>
                    <span class="label">{{ t('licence.activation_key') }}</span>
                    <div class="flex items-center gap-2">
                        <code class="mono flex-1 rounded-lg border px-3 py-2.5" style="border-color:var(--line);font-size:16px;letter-spacing:.08em;color:var(--ink)">{{ renewed.activation_key }}</code>
                        <button type="button" class="btn btn-ghost" @click="copyRenewedKey"><Icon name="copy" :size="15" />{{ t('common.copy') }}</button>
                    </div>
                </div>
                <label class="flex items-start gap-2 text-sm cursor-pointer" style="color:var(--ink)">
                    <input type="checkbox" v-model="acknowledged" class="h-4 w-4 mt-0.5" />
                    <span>{{ t('licence.key_acknowledge') }}</span>
                </label>
                <button type="button" class="btn btn-accent w-full" :disabled="!acknowledged" @click="finishRenewal">{{ t('common.done') }}</button>
            </div>
        </Modal>
    </div>
</template>

<style scoped>
/*
    The fact rows on this page are `<span class="label">` followed by a value
    span, and `.label` is inline in the theme — it is written for forms, where
    the block-level input beneath it does the wrapping. Here nothing does, so
    every row rendered as "Starts06/09/2026". Scoped rather than fixed in
    theme.css: that class is used inline on purpose elsewhere.
*/
.label {
    display: block;
    margin-bottom: 2px;
}
</style>
