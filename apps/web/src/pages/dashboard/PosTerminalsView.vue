<script setup>
import { ref, reactive, computed, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import api from '@xorder/api-client/api.js'
import { withMinDuration } from '../../lib/minLoading.js'
import { pickLocalized } from '@xorder/ui/localize.js'
import Icon from '@xorder/ui/Icon.vue'
import Modal from '@xorder/ui/Modal.vue'
import ErrorState from '@xorder/ui/ErrorState.vue'
import FormError from '@xorder/ui/FormError.vue'
import { confirm } from '@xorder/ui/confirm.js'
import { alert } from '@xorder/ui/alert.js'
import { useAuth } from '@xorder/api-client/auth.js'
import SettingsHeader from './settings/SettingsHeader.vue'

const { t, locale } = useI18n()
const auth = useAuth()

// The route already requires pos.provision, so everyone here may provision;
// the only remaining reason to hide the write controls is a lapsed
// subscription (the server stacks subscription.writable on every write).
const canWrite = computed(() => !auth.isReadOnly)

const rows = ref([])
const branches = ref([])
const loading = ref(true)
const failed = ref(false)

async function load() {
    loading.value = true
    failed.value = false
    try {
        const [list, br] = await withMinDuration(Promise.all([
            api.get('api/dashboard/pos/terminals'),
            // Branch names resolve ids in the table. An installer account may
            // hold pos.provision without branches.list — degrade to "#id"
            // instead of failing the whole page.
            branches.value.length ? Promise.resolve(null) : api.get('api/dashboard/branches').catch(() => null),
        ]))
        rows.value = list.data.data
        if (br) branches.value = br.data.data
    } catch (err) {
        failed.value = true
    } finally {
        loading.value = false
    }
}
onMounted(load)

const branchName = (id) => {
    const b = branches.value.find((x) => x.id === id)
    return b ? pickLocalized(b, 'name', locale.value) : `#${id}`
}

const stateCls = (s) => ({ provisioned: '', active: 'set-chip-green', revoked: 'set-chip-red' }[s] ?? '')

// A till reports its own sync policy on every heartbeat, and the server stores
// whatever string it sends (max:20) rather than an enum — older builds sent
// "automatic". Translate the two we know and echo anything else verbatim, so an
// unexpected value reads as data instead of leaking a missing i18n key.
const SYNC_POLICIES = ['dynamic', 'manual']
const syncLabel = (p) => {
    const value = p || 'dynamic'
    return SYNC_POLICIES.includes(value) ? t('pos_terminals.sync.' + value) : value
}

// Same compact relative time as OrdersView — "what just happened", not a calendar.
function relTime(iso) {
    if (!iso) return ''
    const d = new Date(iso)
    const diffMin = Math.round((d.getTime() - Date.now()) / 60000)
    const rtf = new Intl.RelativeTimeFormat(locale.value, { numeric: 'auto' })
    if (Math.abs(diffMin) < 60) return rtf.format(diffMin, 'minute')
    if (Math.abs(diffMin) < 60 * 24) return rtf.format(Math.round(diffMin / 60), 'hour')
    return d.toLocaleString(locale.value, { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' })
}

// ------------------------------------------------------------------ create
const creating = ref(false)
const form = reactive({ name: '', branch_id: '', sync_policy: 'dynamic' })
const errors = ref({})
const saving = ref(false)

function openCreate() {
    form.name = ''
    form.branch_id = branches.value.length === 1 ? branches.value[0].id : ''
    form.sync_policy = 'dynamic'
    errors.value = {}
    creating.value = true
}

async function submit() {
    errors.value = {}
    saving.value = true
    try {
        const { data } = await api.post('api/dashboard/pos/terminals', {
            name: form.name,
            branch_id: Number(form.branch_id),
            sync_policy: form.sync_policy,
            deployment_mode: 'cloud',
        })
        creating.value = false
        rows.value.unshift(data.data)
        // A terminal without a pairing code is a row nobody can claim —
        // offer the code immediately rather than making the user find the
        // "New code" action.
        await issueCode(data.data)
    } catch (err) {
        errors.value = err.response?.data?.errors || {}
        // The seat limit is not a field error — it arrives as the POS-BE-019
        // envelope ({code, message, details}) with no `errors` key at all, so
        // reading only `errors` left the form sitting there saying nothing
        // while the plan quietly refused. Show the server's message, which
        // carries the actual numbers.
        if (!Object.keys(errors.value).length) {
            alert(err.response?.data?.message || t('common.error'))
        }
    } finally {
        saving.value = false
    }
}

// ------------------------------------------------------------ pairing code
// The plaintext appears in ONE response and never again — the server keeps
// only the HMAC, exactly like a licence activation key. Hence the locked
// modal with an explicit acknowledgement, same discipline as LicenceForm.
const pairing = ref(null) // { terminal, code, hours }
const acknowledged = ref(false)
const copied = ref(false)

async function issueCode(terminal) {
    try {
        const { data } = await api.post(`api/dashboard/pos/terminals/${terminal.id}/pairing-code`)
        acknowledged.value = false
        copied.value = false
        pairing.value = { terminal, code: data.pairing_code, hours: data.expires_in_hours ?? 24 }
    } catch (err) {
        alert(err.response?.data?.message || t('common.error'))
    }
}

async function regenerate(terminal) {
    const ok = await confirm({
        title: t('pos_terminals.new_code_title'),
        message: t('pos_terminals.new_code_message'),
        confirmText: t('pos_terminals.new_code'),
        cancelText: t('common.cancel'),
    })
    if (!ok) return
    await issueCode(terminal)
}

async function copyCode() {
    await navigator.clipboard.writeText(pairing.value.code)
    copied.value = true
}

function closePairing() {
    pairing.value = null
}

// ---------------------------------------------------------------- revoke
async function revoke(terminal) {
    const ok = await confirm({
        title: t('pos_terminals.revoke_title'),
        message: t('pos_terminals.revoke_message'),
        confirmText: t('pos_terminals.revoke'),
        cancelText: t('common.cancel'),
        danger: true,
    })
    if (!ok) return
    try {
        await api.post(`api/dashboard/pos/terminals/${terminal.id}/revoke`)
        // In place, not a refetch: the server's post-revoke state is exactly
        // one thing, and swapping the table for skeletons over a one-row
        // change reads as a page reload.
        rows.value = rows.value.map((x) =>
            x.id === terminal.id ? { ...x, state: 'revoked' } : x)
    } catch (err) {
        alert(err.response?.data?.message || t('common.error'))
    }
}

// ---------------------------------------------------------------- delete
// Cleanup for revoked, never-used leftovers — the server refuses anything
// still active (revoke first) or holding sales/shift history (the record
// anchors the money and stays). Same split as licences: owner decision.
async function destroyTerminal(terminal) {
    const ok = await confirm({
        title: t('pos_terminals.delete_title'),
        message: t('pos_terminals.delete_message', { name: terminal.name }),
        confirmText: t('pos_terminals.delete'),
        cancelText: t('common.cancel'),
        danger: true,
    })
    if (!ok) return
    try {
        await api.delete(`api/dashboard/pos/terminals/${terminal.id}`)
        rows.value = rows.value.filter((x) => x.id !== terminal.id)
    } catch (err) {
        alert(err.response?.data?.message || t('common.error'))
    }
}
</script>

<template>
    <SettingsHeader :title="t('nav.pos_terminals')" :desc="t('pos_terminals.subtitle')">
        <template #actions>
            <button v-if="canWrite" type="button" class="set-btn-primary" @click="openCreate">
                <Icon name="plus" :size="15" />{{ t('pos_terminals.add') }}
            </button>
        </template>
    </SettingsHeader>

    <ErrorState v-if="failed" :message="t('common.error')" @retry="load" />

    <div v-else-if="loading" class="set-stack">
        <div v-for="n in 2" :key="n" class="set-skel" style="height: 84px"></div>
    </div>

    <div v-else-if="!rows.length" class="set-card">
        <div class="set-empty">
            <span class="set-empty-title">{{ t('pos_terminals.none') }}</span>
            <span class="set-empty-hint">{{ t('pos_terminals.subtitle') }}</span>
        </div>
    </div>

    <div v-else class="set-stack">
        <div v-for="r in rows" :key="r.id" class="set-row">
            <div class="set-row-id" style="min-width: 190px">
                <div class="set-row-name">
                    <strong>{{ r.name }}</strong>
                    <span class="set-chip" :class="stateCls(r.state)">
                        <span class="dot"></span>{{ t('pos_terminals.state.' + r.state) }}
                    </span>
                </div>
                <!-- The terminal id is what the till reports and what support
                     asks for, so it stays visible rather than living in a
                     tooltip. Latin in an RTL row, hence dir + start alignment. -->
                <span class="set-row-sub" dir="ltr" style="text-align: start">{{ r.terminal_id }}</span>
            </div>

            <div class="set-facts">
                <div class="set-fact">
                    <span class="set-fact-label">{{ t('pos_terminals.branch') }}</span>
                    <span class="set-fact-value">{{ branchName(r.branch_id) }}</span>
                </div>
                <div class="set-fact">
                    <span class="set-fact-label">{{ t('pos_terminals.sync_policy') }}</span>
                    <span class="set-fact-value">{{ syncLabel(r.sync_policy) }}</span>
                </div>
                <div class="set-fact">
                    <span class="set-fact-label">{{ t('pos_terminals.version') }}</span>
                    <span class="set-fact-value">
                        <template v-if="r.app_version">{{ r.platform ? r.platform + ' ' : '' }}{{ r.app_version }}</template>
                        <template v-else>—</template>
                    </span>
                </div>
                <div class="set-fact">
                    <span class="set-fact-label">{{ t('pos_terminals.pending') }}</span>
                    <span class="set-fact-value" :title="r.oldest_pending_at ? relTime(r.oldest_pending_at) : ''">
                        {{ r.pending_count > 0 ? r.pending_count : '—' }}
                    </span>
                </div>
                <div v-if="r.state === 'active' && r.last_seen_at" class="set-fact">
                    <span class="set-fact-label">{{ t('pos_terminals.last_seen') }}</span>
                    <span class="set-fact-value">{{ relTime(r.last_seen_at) }}</span>
                </div>
            </div>

            <div class="set-row-actions">
                <!-- A code only claims an unclaimed terminal; once active or
                     revoked the action is meaningless. -->
                <button v-if="canWrite && r.state === 'provisioned'" type="button" class="set-btn" @click="regenerate(r)">
                    <Icon name="refresh" :size="14" />{{ t('pos_terminals.new_code') }}
                </button>
                <button v-if="canWrite && r.state !== 'revoked'" type="button" class="set-icon-danger"
                    :title="t('pos_terminals.revoke')" :aria-label="t('pos_terminals.revoke')" @click="revoke(r)">
                    <Icon name="trash" :size="16" />
                </button>
                <button v-if="canWrite && r.state === 'revoked'" type="button" class="set-btn set-btn-danger" @click="destroyTerminal(r)">
                    {{ t('pos_terminals.delete') }}
                </button>
            </div>
        </div>
    </div>

    <!-- Add terminal -->
    <Modal v-if="creating" :title="t('pos_terminals.add')" :subtitle="t('pos_terminals.add_subtitle')" @close="creating = false">
        <form @submit.prevent="submit" class="space-y-4">
            <label class="block">
                <span class="label">{{ t('common.name') }}</span>
                <input v-model="form.name" type="text" maxlength="60" class="input" :placeholder="t('pos_terminals.name_placeholder')" />
                <FormError :errors="errors" field="name" />
            </label>

            <label class="block">
                <span class="label">{{ t('pos_terminals.branch') }}</span>
                <select v-model="form.branch_id" class="input">
                    <option value="" disabled>{{ t('pos_terminals.pick_branch') }}</option>
                    <option v-for="b in branches" :key="b.id" :value="b.id">{{ pickLocalized(b, 'name', locale) }}</option>
                </select>
                <FormError :errors="errors" field="branch_id" />
            </label>

            <label class="block">
                <span class="label">{{ t('pos_terminals.sync_policy') }}</span>
                <select v-model="form.sync_policy" class="input">
                    <option value="dynamic">{{ t('pos_terminals.sync.dynamic') }}</option>
                    <option value="manual">{{ t('pos_terminals.sync.manual') }}</option>
                </select>
                <p class="text-xs mt-1" style="color:var(--muted)">{{ t('pos_terminals.sync_hint') }}</p>
                <FormError :errors="errors" field="sync_policy" />
            </label>

            <div class="flex gap-3 pt-1">
                <button type="submit" class="btn btn-accent" :disabled="saving || !form.name || !form.branch_id">{{ t('common.create') }}</button>
                <button type="button" class="btn btn-ghost" @click="creating = false">{{ t('common.cancel') }}</button>
            </div>
        </form>
    </Modal>

    <!--
        The code is shown ONCE. The server keeps only an HMAC, so there is
        no "show it again" — closing this without entering it on the till
        means generating a new code. Hence the explicit acknowledgement
        rather than a dismissable sheet (same discipline as LicenceForm).
    -->
    <Modal v-if="pairing" :title="t('pos_terminals.pairing_title')" :subtitle="t('pos_terminals.pairing_subtitle', { name: pairing.terminal.name })" @close="() => {}">
        <div class="space-y-5">
            <div class="rounded-lg border p-4" style="border-color:var(--amber);background:var(--amber-soft)">
                <p class="text-sm" style="color:var(--ink)">{{ t('pos_terminals.code_once_warning', { hours: pairing.hours }) }}</p>
            </div>

            <div>
                <span class="label">{{ t('pos_terminals.pairing_code') }}</span>
                <div class="flex items-center gap-2">
                    <code class="mono flex-1 rounded-lg border px-3 py-2.5 text-center" dir="ltr" style="border-color:var(--line);font-size:22px;letter-spacing:.14em;color:var(--ink)">{{ pairing.code }}</code>
                    <button type="button" class="btn btn-ghost" @click="copyCode">
                        <Icon :name="copied ? 'check' : 'copy'" :size="15" />{{ copied ? t('common.copied') : t('common.copy') }}
                    </button>
                </div>
            </div>

            <label class="flex items-start gap-2 text-sm cursor-pointer" style="color:var(--ink)">
                <input type="checkbox" v-model="acknowledged" class="h-4 w-4 mt-0.5" />
                <span>{{ t('pos_terminals.code_acknowledge') }}</span>
            </label>

            <button type="button" class="btn btn-accent w-full" :disabled="!acknowledged" @click="closePairing">{{ t('common.done') }}</button>
        </div>
    </Modal>
</template>
