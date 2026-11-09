<script setup>
// XORD-015, stage 1: the business's cash, bank and wallet accounts, and which
// one each payment method pays into (per branch). Nothing is posted to an
// account yet — there are no balances here, only where money is going to go.
//
// Reads ride on settings.view; every write needs finance.accounts, which the
// server enforces. Hiding the controls is a courtesy, not the boundary.
import { ref, reactive, computed, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import { useAuth } from '@xorder/api-client/auth.js'
import { pickLocalized } from '@xorder/ui/localize.js'
import { withMinDuration } from '../../../lib/minLoading.js'
import Icon from '@xorder/ui/Icon.vue'
import Modal from '@xorder/ui/Modal.vue'
import ErrorState from '@xorder/ui/ErrorState.vue'
import { alert } from '@xorder/ui/alert.js'

const props = defineProps({
    // The payment methods from the Methods tab (already loaded there).
    methods: { type: Array, default: () => [] },
})
const emit = defineEmits(['count'])

const { t, locale } = useI18n()
const auth = useAuth()
const canManage = computed(() => !auth.isReadOnly && auth.can('finance.accounts'))

const KINDS = ['cash', 'bank', 'wallet']

const accounts = ref([])
const defaults = ref([])
const branches = ref([])
const loading = ref(true)
const failed = ref(false)

async function load() {
    loading.value = true
    failed.value = false
    try {
        const [acc, def, br] = await withMinDuration(Promise.all([
            api.get('api/dashboard/financial-accounts'),
            api.get('api/dashboard/tender-account-defaults'),
            // A settings-only account may not hold branches.view: degrade to
            // "no branch choices", never fail the tab.
            api.get('api/dashboard/branches').catch(() => null),
        ]))
        accounts.value = acc.data.data
        defaults.value = def.data.data
        branches.value = br ? br.data.data : []
        emit('count', accounts.value.filter(a => a.is_active).length)
    } catch (err) {
        failed.value = true
    } finally {
        loading.value = false
    }
}
onMounted(load)

const branchName = (id) => {
    const b = branches.value.find(x => x.id === id)
    return b ? pickLocalized(b, 'name', locale.value) : `#${id}`
}
const activeMethods = computed(() => props.methods.filter(m => m.is_active))
const activeAccounts = computed(() => accounts.value.filter(a => a.is_active))
const multiBranch = computed(() => branches.value.length > 1)
// Tying an account to a branch only means something with more than one branch:
// on a single-branch business a "branch" account could never be chosen as a
// default (the business-wide choice takes shared accounts only). A tied
// account that already exists keeps its choice visible so it can be changed.
const showBranchChoice = computed(() => multiBranch.value || form.branch_id !== null)

// An error the form has no field for (is_active, sort_order, a 403) must still
// be seen, not dropped: show the first one that no field already shows.
const FIELD_KEYS = ['name', 'kind', 'branch_id', 'reference_label']
const otherError = computed(() => {
    const entry = Object.entries(errors.value).find(([key]) => !FIELD_KEYS.includes(key))
    return entry ? [].concat(entry[1])[0] : ''
})

function problem(err) {
    const errors = err.response?.data?.errors
    if (errors) return Object.values(errors).flat()[0]
    return err.response?.data?.message || t('common.save_failed')
}

// --- Add / edit modal ------------------------------------------------------
const showModal = ref(false)
const saving = ref(false)
const errors = ref({})
const form = reactive({ id: null, name: '', kind: 'cash', branch_id: null, reference_label: '', sort_order: 0, is_active: true })

function openCreate() {
    Object.assign(form, { id: null, name: '', kind: 'cash', branch_id: null, reference_label: '', sort_order: accounts.value.length, is_active: true })
    errors.value = {}
    showModal.value = true
}
function openEdit(account) {
    Object.assign(form, {
        id: account.id, name: account.name, kind: account.kind, branch_id: account.branch_id,
        reference_label: account.reference_label || '', sort_order: account.sort_order ?? 0, is_active: account.is_active,
    })
    errors.value = {}
    showModal.value = true
}
function payload(over = {}) {
    return {
        name: form.name.trim(), kind: form.kind, branch_id: form.branch_id || null,
        reference_label: form.reference_label.trim() || null, sort_order: Number(form.sort_order) || 0,
        is_active: form.is_active, ...over,
    }
}
async function save() {
    if (saving.value || !form.name.trim()) return
    saving.value = true
    try {
        await ensureCsrf()
        const { data } = form.id
            ? await api.put(`api/dashboard/financial-accounts/${form.id}`, payload())
            : await api.post('api/dashboard/financial-accounts', payload())
        const at = accounts.value.findIndex(a => a.id === data.data.id)
        if (at >= 0) accounts.value[at] = data.data
        else accounts.value.push(data.data)
        emit('count', accounts.value.filter(a => a.is_active).length)
        showModal.value = false
        showToast(t('financial_accounts.saved_toast', { name: data.data.name }))
    } catch (err) {
        errors.value = err.response?.data?.errors || { general: [problem(err)] }
    } finally {
        saving.value = false
    }
}

const busyId = ref(null)
async function setActive(account, on) {
    if (busyId.value) return
    busyId.value = account.id
    try {
        await ensureCsrf()
        const { data } = await api.put(`api/dashboard/financial-accounts/${account.id}`, {
            name: account.name, kind: account.kind, branch_id: account.branch_id,
            reference_label: account.reference_label, sort_order: account.sort_order ?? 0, is_active: on,
        })
        Object.assign(account, data.data)
        emit('count', accounts.value.filter(a => a.is_active).length)
        showToast(t(on ? 'financial_accounts.enabled_toast' : 'financial_accounts.disabled_toast', { name: account.name }))
    } catch (err) {
        alert(problem(err))
    } finally {
        busyId.value = null
    }
}

// --- Where each payment method pays in -------------------------------------
const currentDefault = (methodId, branchId) =>
    defaults.value.find(d => d.tender_type_id === methodId && (d.branch_id ?? null) === branchId)?.financial_account_id ?? ''

// Which account kinds a payment method may pay into: cash into a cash account,
// a card into a bank, and `external` (a card taken on the bank's own terminal —
// the till reads it as a card) into a bank too; `other` has no natural type, so
// any account will do. The same table as the till's `AccountRules.kindsFor` and
// the server's `FinancialAccount::KINDS_FOR_TENDER`, which refuses a mismatch.
// A wallet method (InstaPay and the like) pays into a wallet account, as on an
// offline till.
const KINDS_FOR_TENDER = { cash: ['cash'], card: ['bank'], wallet: ['wallet'], external: ['bank'], other: null }
const fits = (methodKind, accountKind) => {
    const allowed = KINDS_FOR_TENDER[methodKind]
    return !allowed || allowed.includes(accountKind)
}
const neededKinds = (method) => KINDS_FOR_TENDER[method.kind] ?? null

// A business-wide default must be a shared account; a branch default may use a
// shared account or that branch's own. The server enforces the same rule, and
// the kind rule above, on every save.
const fallbackChoices = (method) =>
    activeAccounts.value.filter(a => a.branch_id === null && fits(method.kind, a.kind))
const branchChoices = (method, branchId) =>
    activeAccounts.value.filter(a => (a.branch_id === null || a.branch_id === branchId) && fits(method.kind, a.kind))

// A pairing saved before the rule is kept and marked, never cleared: it stays
// selectable-by-name until somebody picks a fitting account or none.
const savedAccount = (method, branchId) => {
    const id = currentDefault(method.id, branchId)
    return id === '' ? null : accounts.value.find(a => a.id === id) ?? null
}
const mismatched = (method, branchId) => {
    const a = savedAccount(method, branchId)
    return !!a && !fits(method.kind, a.kind)
}
const noneFitHint = (method, choices) => {
    const kinds = neededKinds(method)
    if (!kinds || choices.length) return ''
    return t('financial_accounts.none_fit', { kind: kinds.map(k => t(`financial_accounts.kind.${k}`)).join(' / ').toLowerCase() })
}

async function setDefault(method, branchId, value) {
    const accountId = value === '' ? null : Number(value)
    try {
        await ensureCsrf()
        const { data } = await api.put('api/dashboard/tender-account-defaults', {
            tender_type_id: method.id, branch_id: branchId, financial_account_id: accountId,
        })
        defaults.value = defaults.value.filter(d => !(d.tender_type_id === method.id && (d.branch_id ?? null) === branchId))
        if (data.data) defaults.value.push(data.data)
        showToast(t('financial_accounts.default_toast', { name: method.name }))
    } catch (err) {
        alert(problem(err))
        // Put the select back to what the server still holds.
        defaults.value = [...defaults.value]
    }
}

const toast = ref('')
let toastTimer = null
function showToast(message) {
    toast.value = message
    clearTimeout(toastTimer)
    toastTimer = setTimeout(() => { toast.value = '' }, 3200)
}
</script>

<template>
    <div class="fa">
        <ErrorState v-if="failed" @retry="load" />
        <div v-else-if="loading" class="card fa-skel" aria-hidden="true">
            <div v-for="n in 3" :key="n" class="set-skel" style="height: 56px"></div>
        </div>
        <template v-else>
            <p v-if="!canManage" class="fa-note">{{ t('financial_accounts.read_only') }}</p>

            <!-- The accounts themselves -->
            <section class="fa-block">
                <div class="fa-head">
                    <div>
                        <h2 class="fa-title">{{ t('financial_accounts.title') }}</h2>
                        <p class="fa-desc">{{ t('financial_accounts.desc') }}</p>
                    </div>
                    <button v-if="canManage" type="button" class="btn btn-accent" @click="openCreate">
                        <Icon name="plus" :size="16" />{{ t('financial_accounts.add') }}
                    </button>
                </div>

                <div v-if="!accounts.length" class="card set-empty">
                    <span class="set-empty-title">{{ t('financial_accounts.none') }}</span>
                    <span class="set-empty-hint">{{ t('financial_accounts.none_hint') }}</span>
                </div>
                <div v-else class="card fa-list">
                    <div v-for="a in accounts" :key="a.id" class="fa-row">
                        <div class="fa-tile" :class="a.is_active ? 'k-' + a.kind : 'off'" aria-hidden="true">{{ t(`financial_accounts.kind.${a.kind}`)[0] }}</div>
                        <div class="fa-main">
                            <div class="fa-name" :class="{ dim: !a.is_active }">{{ a.name }}</div>
                            <div class="fa-meta">
                                {{ t(`financial_accounts.kind.${a.kind}`) }}
                                · {{ a.branch_id ? branchName(a.branch_id) : t('financial_accounts.all_branches') }}
                                <template v-if="a.reference_label"> · <span class="mono" dir="ltr">{{ a.reference_label }}</span></template>
                                <span v-if="!a.is_active" class="set-chip"><span class="dot"></span>{{ t('common.inactive') }}</span>
                            </div>
                        </div>
                        <template v-if="canManage">
                            <button type="button" class="btn btn-ghost" @click="openEdit(a)">{{ t('common.edit') }}</button>
                            <button type="button" class="btn btn-ghost" :disabled="busyId === a.id" @click="setActive(a, !a.is_active)">
                                {{ a.is_active ? t('financial_accounts.disable') : t('financial_accounts.enable') }}
                            </button>
                        </template>
                    </div>
                </div>
            </section>

            <!-- Where each payment method pays in -->
            <section class="fa-block">
                <div class="fa-head">
                    <div>
                        <h2 class="fa-title">{{ t('financial_accounts.defaults_title') }}</h2>
                        <p class="fa-desc">{{ t('financial_accounts.defaults_desc') }}</p>
                    </div>
                </div>

                <div v-if="!activeMethods.length" class="card set-empty">
                    <span class="set-empty-hint">{{ t('financial_accounts.no_methods') }}</span>
                </div>
                <div v-else class="card fa-list">
                    <div v-for="m in activeMethods" :key="m.id" class="fa-map">
                        <div class="fa-map-name">{{ m.name }}</div>
                        <label class="fa-map-field">
                            <span class="fa-map-label">{{ multiBranch ? t('financial_accounts.default_all') : t('financial_accounts.default_one') }}</span>
                            <select
                                class="input"
                                :value="currentDefault(m.id, null)"
                                :disabled="!canManage"
                                @change="setDefault(m, null, $event.target.value)"
                            >
                                <option value="">{{ t('financial_accounts.no_account') }}</option>
                                <option v-if="mismatched(m, null)" :value="savedAccount(m, null).id">{{ savedAccount(m, null).name }} · {{ t('financial_accounts.not_matching') }}</option>
                                <option v-for="a in fallbackChoices(m)" :key="a.id" :value="a.id">{{ a.name }}</option>
                            </select>
                            <span v-if="mismatched(m, null)" class="fa-err" role="alert">{{ t('financial_accounts.not_matching') }}</span>
                            <span v-else-if="noneFitHint(m, fallbackChoices(m))" class="fa-map-label">{{ noneFitHint(m, fallbackChoices(m)) }}</span>
                        </label>
                        <template v-if="multiBranch">
                            <label v-for="b in branches" :key="b.id" class="fa-map-field">
                                <span class="fa-map-label">{{ branchName(b.id) }}</span>
                                <select
                                    class="input"
                                    :value="currentDefault(m.id, b.id)"
                                    :disabled="!canManage"
                                    @change="setDefault(m, b.id, $event.target.value)"
                                >
                                    <option value="">{{ t('financial_accounts.same_as_all') }}</option>
                                    <option v-if="mismatched(m, b.id)" :value="savedAccount(m, b.id).id">{{ savedAccount(m, b.id).name }} · {{ t('financial_accounts.not_matching') }}</option>
                                    <option v-for="a in branchChoices(m, b.id)" :key="a.id" :value="a.id">{{ a.name }}</option>
                                </select>
                                <span v-if="mismatched(m, b.id)" class="fa-err" role="alert">{{ t('financial_accounts.not_matching') }}</span>
                            </label>
                        </template>
                    </div>
                </div>
                <p class="fa-note">{{ t('financial_accounts.nothing_posted') }}</p>
            </section>
        </template>

        <!-- Add / edit: the shared slide-over, like the rest of the dashboard -->
        <Modal v-if="showModal" :title="form.id ? t('financial_accounts.edit') : t('financial_accounts.add')" @close="showModal = false">
            <div class="fa-modal-body">
                <label class="fa-field">
                    <span class="fa-label">{{ t('financial_accounts.name') }} <span class="fa-req">*</span></span>
                    <input v-model="form.name" class="input" maxlength="120" :placeholder="t('financial_accounts.name_placeholder')" />
                    <span v-if="errors.name" class="fa-err" role="alert">{{ errors.name[0] }}</span>
                </label>
                <div class="fa-field">
                    <span class="fa-label">{{ t('financial_accounts.type') }}</span>
                    <div class="fa-seg" role="group">
                        <button v-for="k in KINDS" :key="k" type="button" class="fa-seg-btn" :class="{ on: form.kind === k }" :aria-pressed="form.kind === k" @click="form.kind = k">
                            {{ t(`financial_accounts.kind.${k}`) }}
                        </button>
                    </div>
                    <span v-if="errors.kind" class="fa-err" role="alert">{{ errors.kind[0] }}</span>
                </div>
                <label v-if="showBranchChoice" class="fa-field">
                    <span class="fa-label">{{ t('financial_accounts.branch') }}</span>
                    <select v-model="form.branch_id" class="input">
                        <option :value="null">{{ t('financial_accounts.all_branches') }}</option>
                        <option v-for="b in branches" :key="b.id" :value="b.id">{{ branchName(b.id) }}</option>
                    </select>
                    <span class="fa-hint">{{ t('financial_accounts.branch_hint') }}</span>
                    <span v-if="errors.branch_id" class="fa-err" role="alert">{{ errors.branch_id[0] }}</span>
                </label>
                <label class="fa-field">
                    <span class="fa-label">{{ t('financial_accounts.reference') }}</span>
                    <input v-model="form.reference_label" class="input mono" dir="ltr" maxlength="40" :placeholder="t('financial_accounts.reference_placeholder')" />
                    <span class="fa-hint">{{ t('financial_accounts.reference_hint') }}</span>
                    <span v-if="errors.reference_label" class="fa-err" role="alert">{{ errors.reference_label[0] }}</span>
                </label>
                <p v-if="otherError || errors.general" class="fa-err" role="alert">{{ otherError || errors.general[0] }}</p>
            </div>
            <div class="fa-modal-foot">
                <button type="button" class="btn btn-accent" :disabled="saving || !form.name.trim()" @click="save">
                    {{ saving ? t('common.saving') : t('common.save') }}
                </button>
                <button type="button" class="btn btn-ghost" @click="showModal = false">{{ t('common.cancel') }}</button>
            </div>
        </Modal>

        <div v-if="toast" class="fa-toast" role="status" aria-live="polite">{{ toast }}</div>
    </div>
</template>

<style scoped>
/* Colours come from the shared theme variables; logical properties keep RTL right. */
.fa { display: flex; flex-direction: column; gap: 22px; }
.fa-block { display: flex; flex-direction: column; gap: 12px; }
.fa-head { display: flex; align-items: flex-start; justify-content: space-between; gap: 12px; flex-wrap: wrap; }
.fa-title { margin: 0; font-size: 17px; font-weight: 700; color: var(--ink); }
.fa-desc, .fa-note { margin: 4px 0 0; font-size: 13.5px; color: var(--body); }
.fa-skel { padding: 14px 18px; display: flex; flex-direction: column; gap: 10px; }
.mono { font-family: var(--font-mono); font-variant-numeric: tabular-nums; }

.fa-list { overflow: hidden; }
.fa-row { display: flex; align-items: center; gap: 12px; padding: 12px 16px; border-bottom: 1px solid var(--line); flex-wrap: wrap; }
.fa-row:last-child, .fa-map:last-child { border-bottom: 0; }
.fa-tile {
    flex: none; width: 36px; height: 36px; border-radius: 10px; display: grid; place-items: center;
    font-weight: 700; background: var(--gray-soft); color: var(--body);
}
/* Theme variables only, so every theme keeps working. */
.fa-tile.k-cash { background: var(--amber-soft); color: var(--amber); }
.fa-tile.k-bank { background: var(--accent-soft); color: var(--accent-dark); }
.fa-tile.k-wallet { background: var(--green-soft); color: var(--green); }
.fa-tile.off { opacity: .5; }
.fa-main { flex: 1 1 200px; min-width: 0; }
.fa-name { font-weight: 600; color: var(--ink); overflow-wrap: anywhere; }
.fa-name.dim { color: var(--body); }
.fa-meta { font-size: 13px; color: var(--body); display: flex; flex-wrap: wrap; gap: 4px; align-items: center; }

.fa-map { display: flex; flex-wrap: wrap; align-items: flex-end; gap: 12px 16px; padding: 14px 16px; border-bottom: 1px solid var(--line); }
.fa-map-name { flex: 1 1 100%; font-weight: 600; color: var(--ink); }
.fa-map-field { display: flex; flex-direction: column; gap: 4px; flex: 1 1 200px; min-width: 0; }
.fa-map-label { font-size: 12.5px; color: var(--body); font-weight: 600; }

.fa-modal-body { display: flex; flex-direction: column; gap: 14px; }
.fa-modal-foot { margin-top: 20px; display: flex; gap: 8px; }
.fa-field { display: flex; flex-direction: column; gap: 6px; }
.fa-label { font-size: 13px; font-weight: 600; color: var(--ink); }
.fa-req { color: var(--red); }
.fa-hint { font-size: 12.5px; color: var(--body); }
.fa-err { margin: 0; font-size: 12.5px; color: var(--red); }
.fa-seg { display: flex; gap: 6px; flex-wrap: wrap; }
.fa-seg-btn {
    min-height: 40px; padding: 8px 14px; border-radius: 10px; border: 1px solid var(--line);
    background: transparent; color: var(--body); font: inherit; cursor: pointer;
}
.fa-seg-btn.on { border-color: var(--accent); color: var(--ink); font-weight: 700; box-shadow: inset 0 0 0 1px var(--accent); }
.fa-seg-btn:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }

.fa-toast {
    position: fixed; inset-block-end: 20px; inset-inline: 0; margin-inline: auto; width: max-content; max-width: calc(100% - 32px);
    background: var(--ink); color: var(--card); padding: 10px 16px; border-radius: 10px; z-index: 70; font-size: 14px;
}
</style>
