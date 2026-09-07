<script setup>
import { ref, reactive, computed, onMounted } from 'vue'
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
        // Prefill a renewal as "another year from where this one ends" — the
        // overwhelmingly common case. A licence sold outright reports no
        // expiry at all, so there is nothing to count from: start from today
        // rather than from an Invalid Date.
        const from = licence.value.expires_at ? new Date(licence.value.expires_at) : new Date()
        renewForm.issued_at = from.toISOString().slice(0, 10)
        renewForm.expires_at = new Date(from.getTime() + 365 * 864e5).toISOString().slice(0, 10)
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
        // A renewal is a NEW row — the old one is superseded, not edited.
        if (!data.activation_key) router.push({ name: 'admin.licences.show', params: { id: data.data.id } }).then(load)
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

function finishRenewal() {
    const id = renewed.value.data.id
    renewed.value = null
    acknowledged.value = false
    router.push({ name: 'admin.licences.show', params: { id } }).then(load)
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
                    <span class="badge" :class="badge(licence.state)">{{ t('licence.state.' + licence.state) }}</span>
                </div>
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
                <div><span class="label">{{ t('licence.key_tail') }}</span><span class="mono" style="color:var(--ink)">…{{ licence.key_last_four }}</span></div>
                <div><span class="label">{{ t('licence.max_offline_days') }}</span><span style="color:var(--ink)">{{ licence.max_offline_days ?? t('licence.unlimited') }}</span></div>
                <div><span class="label">{{ t('licence.activated_at') }}</span><span style="color:var(--ink)">{{ licence.activated_at ? dateOf(licence.activated_at) : t('licence.never_activated') }}</span></div>
                <div v-if="licence.notes" class="sm:col-span-2"><span class="label">{{ t('licence.notes') }}</span><span style="color:var(--body)">{{ licence.notes }}</span></div>
                <div v-if="licence.revoked_reason" class="sm:col-span-2"><span class="label">{{ t('licence.revoked_reason') }}</span><span style="color:var(--body)">{{ licence.revoked_reason }}</span></div>
            </div>

            <div class="flex flex-wrap gap-3">
                <button v-if="isLive" class="btn btn-accent" :disabled="busy" @click="renewing = true">{{ t('licence.renew') }}</button>
                <button class="btn btn-ghost" @click="download"><Icon name="download" :size="15" />{{ t('licence.download') }}</button>
                <button v-if="isLive" class="btn btn-ghost" style="color:var(--red)" :disabled="busy" @click="revoke">{{ t('licence.revoke') }}</button>
                <button v-if="isDeletable" class="btn btn-ghost" style="color:var(--red)" :disabled="busy" @click="destroyLicence">{{ t('licence.delete') }}</button>
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
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                    <label class="block">
                        <span class="label">{{ t('licence.issued_at') }}</span>
                        <input v-model="renewForm.issued_at" type="date" class="input" />
                        <FormError :errors="renewErrors" field="issued_at" />
                    </label>
                    <label class="block">
                        <span class="label">{{ t('licence.expires_at') }}</span>
                        <input v-model="renewForm.expires_at" type="date" class="input" />
                        <FormError :errors="renewErrors" field="expires_at" />
                    </label>
                </div>

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
