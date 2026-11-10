<script setup>
import { ref, reactive, computed, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import api from '@xorder/api-client/api.js'
import { withMinDuration } from '../../lib/minLoading.js'
import { useCaps } from '../../lib/useCaps.js'
import { currencyLabel } from '../../lib/currency.js'
import {
    currencyExponent, bpToPercent, percentToBp,
    minorToAmount, amountToMinor, formatMinor, applyBp,
} from '../../lib/money.js'
import { pickLocalized } from '@xorder/ui/localize.js'
import { useAuth } from '@xorder/api-client/auth.js'
import Icon from '@xorder/ui/Icon.vue'
import Modal from '@xorder/ui/Modal.vue'
import ErrorState from '@xorder/ui/ErrorState.vue'
import SettingsHeader from './settings/SettingsHeader.vue'
import FormError from '@xorder/ui/FormError.vue'
import { confirm } from '@xorder/ui/confirm.js'
import { alert } from '@xorder/ui/alert.js'

const { t, locale } = useI18n()
const auth = useAuth()
// The route opens on settings.view; every write additionally needs
// settings.update, which is exactly what the server stacks on these endpoints.
const { canUpdate } = useCaps('settings')

// The restaurant's currency decides how many decimals an amount field has —
// a Kuwaiti tenant types three, everyone else types two.
const exponent = computed(() => currencyExponent(auth.restaurant?.currency))
const token = computed(() => currencyLabel(auth.restaurant?.currency, locale.value, auth.restaurant?.currency_symbol))
// The worked example every hint is phrased against: 100 major units.
const sample = computed(() => 100 * 10 ** exponent.value)
const money = (minor) => formatMinor(minor, exponent.value, token.value)
// Arabic separates a list with ، not a comma.
const listSep = computed(() => (locale.value === 'ar' ? '، ' : ', '))
const joinList = (parts) => parts.join(listSep.value)

// The order types a till offers as tabs. Free text on the POS wire (the branch's
// own list is the gate), so this is the vocabulary, not a server enum.
const ORDER_TYPES = ['dine_in', 'takeaway', 'delivery', 'drive_thru']
const TENDER_KINDS = ['cash', 'card', 'wallet', 'external', 'other']

const taxes = ref([])
const charges = ref([])
const tenders = ref([])
// Only used to name ids in the scope pickers. Loaded best-effort: a
// settings-only account may hold settings.view without branches.view or
// menu.view, and that must degrade to "#id", not fail the page.
const branches = ref([])
const categories = ref([])
const loading = ref(true)
const failed = ref(false)

async function load() {
    loading.value = true
    failed.value = false
    try {
        const [tx, ch, td, br, cat] = await withMinDuration(Promise.all([
            api.get('api/dashboard/tax-rules'),
            api.get('api/dashboard/charges'),
            api.get('api/dashboard/tender-types'),
            api.get('api/dashboard/branches').catch(() => null),
            api.get('api/dashboard/categories').catch(() => null),
        ]))
        taxes.value = tx.data.data
        charges.value = ch.data.data
        tenders.value = td.data.data
        if (br) branches.value = br.data.data
        if (cat) categories.value = cat.data.data
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
const categoryName = (id) => {
    const c = categories.value.find((x) => x.id === id)
    return c ? pickLocalized(c, 'name', locale.value) : `#${id}`
}

// One-line "where does this apply" for a list row. An empty/absent applies_to
// is "everything" on the server, so it must read that way here too.
function scopeSummary(row) {
    const a = row.applies_to || {}
    const parts = []
    if (a.order_types?.length) parts.push(joinList(a.order_types.map((x) => t(`order_type.${x}`))))
    if (a.branch_ids?.length) parts.push(joinList(a.branch_ids.map(branchName)))
    if (a.category_ids?.length) parts.push(joinList(a.category_ids.map(categoryName)))
    if (a.item_ids?.length) parts.push(t('pos_money.applies_items_n', { n: a.item_ids.length }))
    return parts.length ? parts.join(' · ') : t('pos_money.applies_all')
}

// ------------------------------------------------------------------ scopes
// A scope form holds only the lists this screen can edit; `extra` carries any
// other applies_to key the record already had (item_ids, authored elsewhere)
// so saving from here never silently narrows or widens a live rule.
function blankScope() {
    return { order_types: [], branch_ids: [], category_ids: [], extra: {} }
}

function hydrateScope(target, appliesTo) {
    const a = appliesTo && typeof appliesTo === 'object' && !Array.isArray(appliesTo) ? appliesTo : {}
    const { order_types, branch_ids, category_ids, ...extra } = a
    target.order_types = [...(order_types || [])]
    target.branch_ids = [...(branch_ids || [])]
    target.category_ids = [...(category_ids || [])]
    target.extra = extra
}

function scopePayload(scope, { categories: withCategories = true } = {}) {
    const out = { ...scope.extra }
    if (scope.order_types.length) out.order_types = scope.order_types
    if (scope.branch_ids.length) out.branch_ids = scope.branch_ids
    if (withCategories && scope.category_ids.length) out.category_ids = scope.category_ids
    // Nothing ticked and nothing preserved → null, which the server reads as
    // "applies to everything".
    return Object.keys(out).length ? out : null
}

function toggleIn(list, value) {
    const i = list.indexOf(value)
    if (i === -1) list.push(value)
    else list.splice(i, 1)
}

// ---------------------------------------------------------------- tax rules
const taxModal = ref(false)
const editingTax = ref(null)
const taxErrors = ref({})
const taxSaving = ref(false)
const taxForm = reactive({ name: '', rate: '', mode: 'exclusive', sort_order: 0, scope: blankScope() })

function openTax(row = null) {
    editingTax.value = row
    taxErrors.value = {}
    taxForm.name = row?.name || ''
    taxForm.rate = row ? bpToPercent(row.rate_bp) : ''
    taxForm.mode = row?.mode || 'exclusive'
    taxForm.sort_order = row?.sort_order ?? 0
    hydrateScope(taxForm.scope, row?.applies_to)
    taxModal.value = true
}

// The rate as the server will store it — recomputed from the typed string on
// every keystroke, so the hint below the field is the real stored value and
// never a re-rendered float.
const taxBp = computed(() => percentToBp(taxForm.rate))
const taxBpValid = computed(() => Number.isInteger(taxBp.value) && taxBp.value >= 0 && taxBp.value <= 10000)

// The worked example, in integers, matching what the till will print.
const taxHint = computed(() => {
    if (!taxBpValid.value) return ''
    const bp = taxBp.value
    const base = sample.value
    if (taxForm.mode === 'inclusive') {
        // Tax already contained in a displayed price: P * bp / (10000 + bp).
        const inside = Math.round((base * bp) / (10000 + bp))
        return t('pos_money.hint_inclusive', { rate: bpToPercent(bp), base: money(base), tax: money(inside) })
    }
    return t('pos_money.hint_exclusive', { rate: bpToPercent(bp), base: money(base), total: money(base + applyBp(base, bp)) })
})

async function saveTax() {
    if (taxSaving.value) return
    taxErrors.value = {}
    taxSaving.value = true
    try {
        const payload = {
            name: taxForm.name,
            rate_bp: taxBp.value,
            mode: taxForm.mode,
            applies_to: scopePayload(taxForm.scope),
            sort_order: Number(taxForm.sort_order) || 0,
        }
        const { data } = editingTax.value
            ? await api.put(`api/dashboard/tax-rules/${editingTax.value.id}`, payload)
            : await api.post('api/dashboard/tax-rules', payload)
        // In place, not a refetch: the response IS the stored record.
        if (editingTax.value) taxes.value = taxes.value.map((x) => (x.id === data.data.id ? data.data : x))
        else taxes.value.push(data.data)
        taxModal.value = false
    } catch (err) {
        taxErrors.value = err.response?.data?.errors || {}
        if (!Object.keys(taxErrors.value).length) alert(err.response?.data?.message || t('common.error'))
    } finally {
        taxSaving.value = false
    }
}

async function destroyTax(row) {
    const ok = await confirm({
        title: t('pos_money.delete_tax_title'),
        message: t('pos_money.delete_message', { name: row.name }),
        confirmText: t('common.delete'),
        cancelText: t('common.cancel'),
        danger: true,
    })
    if (!ok) return
    try {
        await api.delete(`api/dashboard/tax-rules/${row.id}`)
        taxes.value = taxes.value.filter((x) => x.id !== row.id)
    } catch (err) {
        alert(err.response?.data?.message || t('common.error'))
    }
}

// ------------------------------------------------------------------ charges
const chargeModal = ref(false)
const editingCharge = ref(null)
const chargeErrors = ref({})
const chargeSaving = ref(false)
const chargeForm = reactive({ name: '', kind: 'percent', rate: '', amount: '', taxable: true, sort_order: 0, scope: blankScope() })

function openCharge(row = null) {
    editingCharge.value = row
    chargeErrors.value = {}
    chargeForm.name = row?.name || ''
    chargeForm.kind = row?.kind || 'percent'
    chargeForm.rate = row?.rate_bp != null ? bpToPercent(row.rate_bp) : ''
    chargeForm.amount = row?.amount_minor != null ? minorToAmount(row.amount_minor, exponent.value) : ''
    chargeForm.taxable = row ? !!row.taxable : true
    chargeForm.sort_order = row?.sort_order ?? 0
    hydrateScope(chargeForm.scope, row?.applies_to)
    chargeModal.value = true
}

const chargeBp = computed(() => percentToBp(chargeForm.rate))
const chargeMinor = computed(() => amountToMinor(chargeForm.amount, exponent.value))
const chargeValueValid = computed(() => (chargeForm.kind === 'percent'
    ? Number.isInteger(chargeBp.value) && chargeBp.value >= 0 && chargeBp.value <= 10000
    : Number.isInteger(chargeMinor.value) && chargeMinor.value >= 0))

const chargeHint = computed(() => {
    if (!chargeValueValid.value) return ''
    if (chargeForm.kind === 'percent') {
        return t('pos_money.hint_charge_percent', {
            rate: bpToPercent(chargeBp.value),
            base: money(sample.value),
            amount: money(applyBp(sample.value, chargeBp.value)),
        })
    }
    return t('pos_money.hint_charge_fixed', { amount: money(chargeMinor.value) })
})

async function saveCharge() {
    if (chargeSaving.value) return
    chargeErrors.value = {}
    chargeSaving.value = true
    try {
        // Exactly one of rate_bp / amount_minor per the declared kind — the
        // other must be absent, not null: the server marks it `prohibited_if`.
        const payload = {
            name: chargeForm.name,
            kind: chargeForm.kind,
            ...(chargeForm.kind === 'percent' ? { rate_bp: chargeBp.value } : { amount_minor: chargeMinor.value }),
            taxable: chargeForm.taxable,
            // Charges scope by order type and branch only; no category list.
            applies_to: scopePayload(chargeForm.scope, { categories: false }),
            sort_order: Number(chargeForm.sort_order) || 0,
        }
        const { data } = editingCharge.value
            ? await api.put(`api/dashboard/charges/${editingCharge.value.id}`, payload)
            : await api.post('api/dashboard/charges', payload)
        if (editingCharge.value) charges.value = charges.value.map((x) => (x.id === data.data.id ? data.data : x))
        else charges.value.push(data.data)
        chargeModal.value = false
    } catch (err) {
        chargeErrors.value = err.response?.data?.errors || {}
        if (!Object.keys(chargeErrors.value).length) alert(err.response?.data?.message || t('common.error'))
    } finally {
        chargeSaving.value = false
    }
}

async function destroyCharge(row) {
    const ok = await confirm({
        title: t('pos_money.delete_charge_title'),
        message: t('pos_money.delete_message', { name: row.name }),
        confirmText: t('common.delete'),
        cancelText: t('common.cancel'),
        danger: true,
    })
    if (!ok) return
    try {
        await api.delete(`api/dashboard/charges/${row.id}`)
        charges.value = charges.value.filter((x) => x.id !== row.id)
    } catch (err) {
        alert(err.response?.data?.message || t('common.error'))
    }
}

// ------------------------------------------------------------ tender types
const tenderModal = ref(false)
const editingTender = ref(null)
const tenderErrors = ref({})
const tenderSaving = ref(false)
const tenderForm = reactive({ name: '', kind: 'cash', is_active: true, sort_order: 0 })

function openTender(row = null) {
    editingTender.value = row
    tenderErrors.value = {}
    tenderForm.name = row?.name || ''
    tenderForm.kind = row?.kind || 'cash'
    tenderForm.is_active = row ? !!row.is_active : true
    tenderForm.sort_order = row?.sort_order ?? 0
    tenderModal.value = true
}

async function saveTender() {
    if (tenderSaving.value) return
    tenderErrors.value = {}
    tenderSaving.value = true
    try {
        const payload = {
            name: tenderForm.name,
            kind: tenderForm.kind,
            is_active: tenderForm.is_active,
            sort_order: Number(tenderForm.sort_order) || 0,
        }
        const { data } = editingTender.value
            ? await api.put(`api/dashboard/tender-types/${editingTender.value.id}`, payload)
            : await api.post('api/dashboard/tender-types', payload)
        if (editingTender.value) tenders.value = tenders.value.map((x) => (x.id === data.data.id ? data.data : x))
        else tenders.value.push(data.data)
        tenderModal.value = false
    } catch (err) {
        tenderErrors.value = err.response?.data?.errors || {}
        if (!Object.keys(tenderErrors.value).length) alert(err.response?.data?.message || t('common.error'))
    } finally {
        tenderSaving.value = false
    }
}

// DELETE on a tender type deactivates rather than removing the row — a payment
// method that has taken money anchors those order_payments and cannot go away.
// The server answers with the updated record, so the row stays in the table
// switched off, and the copy says so instead of promising a deletion.
async function deactivateTender(row) {
    const ok = await confirm({
        title: t('pos_money.deactivate_title'),
        message: t('pos_money.deactivate_message', { name: row.name }),
        confirmText: t('pos_money.deactivate'),
        cancelText: t('common.cancel'),
        danger: true,
    })
    if (!ok) return
    try {
        const { data } = await api.delete(`api/dashboard/tender-types/${row.id}`)
        const updated = data?.data || { ...row, is_active: false }
        tenders.value = tenders.value.map((x) => (x.id === row.id ? updated : x))
    } catch (err) {
        alert(err.response?.data?.message || t('common.error'))
    }
}

async function reactivateTender(row) {
    try {
        const { data } = await api.put(`api/dashboard/tender-types/${row.id}`, {
            name: row.name, kind: row.kind, is_active: true, sort_order: row.sort_order ?? 0,
        })
        tenders.value = tenders.value.map((x) => (x.id === row.id ? data.data : x))
    } catch (err) {
        alert(err.response?.data?.message || t('common.error'))
    }
}
</script>

<template>
    <div class="set-stack-lg">
        <SettingsHeader :title="t('nav.pos_money')" :desc="t('pos_money.subtitle')" />

        <!-- These rules are not a dashboard preference: they are what the till
             charges a customer. Say that once, at the top, rather than repeating
             a warning on every save. -->
        <div class="set-banner">
            <i class="pi pi-info-circle" aria-hidden="true"></i>
            <span>{{ t('pos_money.sync_note') }}</span>
        </div>

        <p v-if="!canUpdate" class="set-desc">{{ t('pos_money.read_only') }}</p>

        <ErrorState v-if="failed" :message="t('common.error')" @retry="load" />

        <template v-else>
            <!-- ------------------------------------------------ tax rules -->
            <section class="set-card">
                <div class="set-card-head">
                    <div class="set-card-head-text">
                        <span class="set-card-title">{{ t('pos_money.taxes') }}</span>
                        <span class="set-card-desc">{{ t('pos_money.taxes_hint') }}</span>
                    </div>
                    <button v-if="canUpdate" type="button" class="set-btn-primary set-btn-sm" style="margin-inline-start:auto" @click="openTax()">
                        <Icon name="plus" :size="14" />{{ t('pos_money.add_tax') }}
                    </button>
                </div>

                <div v-if="loading" class="set-card-body">
                    <div v-for="n in 2" :key="n" class="set-skel" style="height: 56px"></div>
                </div>
                <div v-else-if="!taxes.length" class="set-empty">
                    <span class="set-empty-title">{{ t('pos_money.taxes_none') }}</span>
                    <span class="set-empty-hint">{{ t('pos_money.taxes_empty_hint') }}</span>
                </div>
                <div v-else class="set-list">
                    <div v-for="r in taxes" :key="r.id" class="set-list-row">
                        <div class="set-row-id">
                            <div class="set-row-name">
                                <strong>{{ r.name }}</strong>
                                <span class="set-chip set-chip-accent mono" dir="ltr">{{ bpToPercent(r.rate_bp) }}%</span>
                                <span class="set-chip">{{ t('pos_money.mode_' + r.mode) }}</span>
                            </div>
                            <span class="set-fact-label">{{ scopeSummary(r) }}</span>
                        </div>
                        <div class="set-row-actions">
                            <button v-if="canUpdate" type="button" class="set-btn set-btn-sm" @click="openTax(r)">{{ t('common.edit') }}</button>
                            <button v-if="canUpdate" type="button" class="set-icon-danger" :title="t('common.delete')" :aria-label="t('common.delete')" @click="destroyTax(r)">
                                <Icon name="trash" :size="16" />
                            </button>
                        </div>
                    </div>
                </div>
            </section>

            <!-- -------------------------------------------------- charges -->
            <section class="set-card">
                <div class="set-card-head">
                    <div class="set-card-head-text">
                        <span class="set-card-title">{{ t('pos_money.charges') }}</span>
                        <span class="set-card-desc">{{ t('pos_money.charges_hint') }}</span>
                    </div>
                    <button v-if="canUpdate" type="button" class="set-btn-primary set-btn-sm" style="margin-inline-start:auto" @click="openCharge()">
                        <Icon name="plus" :size="14" />{{ t('pos_money.add_charge') }}
                    </button>
                </div>

                <div v-if="loading" class="set-card-body">
                    <div v-for="n in 2" :key="n" class="set-skel" style="height: 56px"></div>
                </div>
                <div v-else-if="!charges.length" class="set-empty">
                    <span class="set-empty-title">{{ t('pos_money.charges_none') }}</span>
                    <span class="set-empty-hint">{{ t('pos_money.charges_empty_hint') }}</span>
                </div>
                <div v-else class="set-list">
                    <div v-for="r in charges" :key="r.id" class="set-list-row">
                        <div class="set-row-id">
                            <div class="set-row-name">
                                <strong>{{ r.name }}</strong>
                                <span class="set-chip set-chip-accent mono" dir="ltr">
                                    <template v-if="r.kind === 'percent'">{{ bpToPercent(r.rate_bp) }}%</template>
                                    <template v-else>{{ money(r.amount_minor) }}</template>
                                </span>
                                <!-- Only worth a chip when true: "not taxable" is
                                     the ordinary case and does not need saying. -->
                                <span v-if="r.taxable" class="set-chip set-chip-green">{{ t('pos_money.taxable') }}</span>
                            </div>
                            <span class="set-fact-label">{{ scopeSummary(r) }}</span>
                        </div>
                        <div class="set-row-actions">
                            <button v-if="canUpdate" type="button" class="set-btn set-btn-sm" @click="openCharge(r)">{{ t('common.edit') }}</button>
                            <button v-if="canUpdate" type="button" class="set-icon-danger" :title="t('common.delete')" :aria-label="t('common.delete')" @click="destroyCharge(r)">
                                <Icon name="trash" :size="16" />
                            </button>
                        </div>
                    </div>
                </div>
            </section>

            <!-- --------------------------------------------- tender types -->
            <section class="set-card">
                <div class="set-card-head">
                    <div class="set-card-head-text">
                        <span class="set-card-title">{{ t('pos_money.tenders') }}</span>
                        <span class="set-card-desc">{{ t('pos_money.tenders_hint') }}</span>
                    </div>
                    <button v-if="canUpdate" type="button" class="set-btn-primary set-btn-sm" style="margin-inline-start:auto" @click="openTender()">
                        <Icon name="plus" :size="14" />{{ t('pos_money.add_tender') }}
                    </button>
                </div>

                <div v-if="loading" class="set-card-body">
                    <div v-for="n in 2" :key="n" class="set-skel" style="height: 56px"></div>
                </div>
                <div v-else-if="!tenders.length" class="set-empty">
                    <span class="set-empty-title">{{ t('pos_money.tenders_none') }}</span>
                    <span class="set-empty-hint">{{ t('pos_money.tenders_empty_hint') }}</span>
                </div>
                <div v-else class="set-list">
                    <div v-for="r in tenders" :key="r.id" class="set-list-row">
                        <div class="set-row-id">
                            <div class="set-row-name">
                                <strong>{{ r.name }}</strong>
                                <span class="set-chip">{{ t('pos_money.tender_kind.' + r.kind) }}</span>
                                <span class="set-chip" :class="r.is_active ? 'set-chip-green' : ''">
                                    <span class="dot"></span>{{ r.is_active ? t('common.active') : t('common.inactive') }}
                                </span>
                            </div>
                        </div>
                        <div class="set-row-actions">
                            <button v-if="canUpdate" type="button" class="set-btn set-btn-sm" @click="openTender(r)">{{ t('common.edit') }}</button>
                            <!-- A tender is never deleted — bills already point at it. -->
                            <button v-if="canUpdate && r.is_active" type="button" class="set-btn set-btn-sm" @click="deactivateTender(r)">{{ t('pos_money.deactivate') }}</button>
                            <button v-else-if="canUpdate" type="button" class="set-btn set-btn-sm" @click="reactivateTender(r)">{{ t('pos_money.reactivate') }}</button>
                        </div>
                    </div>
                    <p class="set-list-foot">{{ t('pos_money.tenders_never_deleted') }}</p>
                </div>
            </section>
        </template>

        <!-- ============================================ tax rule editor -->
        <Modal v-if="taxModal" :title="editingTax ? t('pos_money.edit_tax') : t('pos_money.add_tax')" @close="taxModal = false">
            <form @submit.prevent="saveTax" class="space-y-4">
                <label class="block">
                    <span class="label">{{ t('common.name') }}</span>
                    <input v-model="taxForm.name" class="input" maxlength="120" :placeholder="t('pos_money.tax_name_placeholder')" />
                    <FormError :errors="taxErrors" field="name" />
                </label>

                <!-- The field is a percentage because that is what an owner
                     knows; rate_bp is derived from the typed string, never from
                     a float, so 14.5 is stored as exactly 1450. -->
                <label class="block">
                    <span class="label">{{ t('pos_money.rate_percent') }}</span>
                    <input v-model="taxForm.rate" class="input" dir="ltr" inputmode="decimal" data-en-digits placeholder="14" />
                    <FormError :errors="taxErrors" field="rate_bp" />
                </label>

                <label class="block">
                    <span class="label">{{ t('pos_money.mode') }}</span>
                    <select v-model="taxForm.mode" class="input">
                        <option value="exclusive">{{ t('pos_money.mode_exclusive') }}</option>
                        <option value="inclusive">{{ t('pos_money.mode_inclusive') }}</option>
                    </select>
                    <FormError :errors="taxErrors" field="mode" />
                </label>

                <p v-if="taxHint" class="rounded-lg p-3 text-sm" style="background:var(--accent-soft);color:var(--ink)">{{ taxHint }}</p>

                <div class="set-group">
                    <span class="set-group-title">{{ t('pos_money.applies_to') }}</span>
                    <p class="set-help">{{ t('pos_money.applies_hint') }}</p>

                    <p class="set-help">{{ t('pos_money.applies_order_types') }}</p>
                    <div class="set-check-wrap">
                        <label v-for="tp in ORDER_TYPES" :key="tp" class="set-check">
                            <input type="checkbox" :checked="taxForm.scope.order_types.includes(tp)" @change="toggleIn(taxForm.scope.order_types, tp)" />
                            {{ t('order_type.' + tp) }}
                        </label>
                    </div>

                    <template v-if="branches.length > 1">
                        <p class="set-help">{{ t('pos_money.applies_branches') }}</p>
                        <div class="set-check-wrap">
                            <label v-for="b in branches" :key="b.id" class="set-check">
                                <input type="checkbox" :checked="taxForm.scope.branch_ids.includes(b.id)" @change="toggleIn(taxForm.scope.branch_ids, b.id)" />
                                {{ branchName(b.id) }}
                            </label>
                        </div>
                    </template>

                    <template v-if="categories.length">
                        <p class="set-help">{{ t('pos_money.applies_categories') }}</p>
                        <div class="set-check-wrap">
                            <label v-for="c in categories" :key="c.id" class="set-check">
                                <input type="checkbox" :checked="taxForm.scope.category_ids.includes(c.id)" @change="toggleIn(taxForm.scope.category_ids, c.id)" />
                                {{ categoryName(c.id) }}
                            </label>
                        </div>
                    </template>

                    <!-- Item-level scoping isn't authored here, but a rule that
                         already has one must keep it — saying so beats silently
                         re-saving a narrower rule than the owner can see. -->
                    <p v-if="taxForm.scope.extra.item_ids?.length" class="set-help">
                        {{ t('pos_money.applies_items_kept', { n: taxForm.scope.extra.item_ids.length }) }}
                    </p>
                    <FormError :errors="taxErrors" field="applies_to" />
                </div>

                <label class="block">
                    <span class="label">{{ t('pos_money.sort_order') }}</span>
                    <input v-model="taxForm.sort_order" class="input" dir="ltr" inputmode="numeric" data-en-digits />
                    <FormError :errors="taxErrors" field="sort_order" />
                </label>

                <div class="set-form-actions">
                    <button type="submit" class="btn btn-accent" :disabled="taxSaving || !taxForm.name || !taxBpValid">{{ taxSaving ? t('common.saving') : t('common.save') }}</button>
                    <button type="button" class="btn btn-ghost" @click="taxModal = false">{{ t('common.cancel') }}</button>
                </div>
            </form>
        </Modal>

        <!-- ============================================== charge editor -->
        <Modal v-if="chargeModal" :title="editingCharge ? t('pos_money.edit_charge') : t('pos_money.add_charge')" @close="chargeModal = false">
            <form @submit.prevent="saveCharge" class="space-y-4">
                <label class="block">
                    <span class="label">{{ t('common.name') }}</span>
                    <input v-model="chargeForm.name" class="input" maxlength="120" :placeholder="t('pos_money.charge_name_placeholder')" />
                    <FormError :errors="chargeErrors" field="name" />
                </label>

                <label class="block">
                    <span class="label">{{ t('pos_money.kind') }}</span>
                    <select v-model="chargeForm.kind" class="input">
                        <option value="percent">{{ t('pos_money.kind_percent') }}</option>
                        <option value="fixed">{{ t('pos_money.kind_fixed') }}</option>
                    </select>
                    <FormError :errors="chargeErrors" field="kind" />
                </label>

                <label v-if="chargeForm.kind === 'percent'" class="block">
                    <span class="label">{{ t('pos_money.rate_percent') }}</span>
                    <input v-model="chargeForm.rate" class="input" dir="ltr" inputmode="decimal" data-en-digits placeholder="12" />
                    <FormError :errors="chargeErrors" field="rate_bp" />
                </label>
                <label v-else class="block">
                    <span class="label">{{ t('pos_money.amount_in', { currency: token }) }}</span>
                    <input v-model="chargeForm.amount" class="input" dir="ltr" inputmode="decimal" data-en-digits :placeholder="minorToAmount(0, exponent)" />
                    <FormError :errors="chargeErrors" field="amount_minor" />
                </label>

                <p v-if="chargeHint" class="rounded-lg p-3 text-sm" style="background:var(--accent-soft);color:var(--ink)">{{ chargeHint }}</p>

                <div class="block">
                    <label class="flex items-center gap-2 text-sm" style="color:var(--body)">
                        <button type="button" class="switch" :class="{ on: chargeForm.taxable }" @click="chargeForm.taxable = !chargeForm.taxable"></button>
                        {{ t('pos_money.taxable') }}
                    </label>
                    <p class="set-help">{{ t('pos_money.taxable_hint') }}</p>
                    <FormError :errors="chargeErrors" field="taxable" />
                </div>

                <div class="set-group">
                    <span class="set-group-title">{{ t('pos_money.applies_to') }}</span>
                    <p class="set-help">{{ t('pos_money.applies_hint') }}</p>

                    <p class="set-help">{{ t('pos_money.applies_order_types') }}</p>
                    <div class="set-check-wrap">
                        <label v-for="tp in ORDER_TYPES" :key="tp" class="set-check">
                            <input type="checkbox" :checked="chargeForm.scope.order_types.includes(tp)" @change="toggleIn(chargeForm.scope.order_types, tp)" />
                            {{ t('order_type.' + tp) }}
                        </label>
                    </div>

                    <template v-if="branches.length > 1">
                        <p class="set-help">{{ t('pos_money.applies_branches') }}</p>
                        <div class="set-check-wrap">
                            <label v-for="b in branches" :key="b.id" class="set-check">
                                <input type="checkbox" :checked="chargeForm.scope.branch_ids.includes(b.id)" @change="toggleIn(chargeForm.scope.branch_ids, b.id)" />
                                {{ branchName(b.id) }}
                            </label>
                        </div>
                    </template>
                    <FormError :errors="chargeErrors" field="applies_to" />
                </div>

                <label class="block">
                    <span class="label">{{ t('pos_money.sort_order') }}</span>
                    <input v-model="chargeForm.sort_order" class="input" dir="ltr" inputmode="numeric" data-en-digits />
                    <FormError :errors="chargeErrors" field="sort_order" />
                </label>

                <div class="set-form-actions">
                    <button type="submit" class="btn btn-accent" :disabled="chargeSaving || !chargeForm.name || !chargeValueValid">{{ chargeSaving ? t('common.saving') : t('common.save') }}</button>
                    <button type="button" class="btn btn-ghost" @click="chargeModal = false">{{ t('common.cancel') }}</button>
                </div>
            </form>
        </Modal>

        <!-- ========================================= tender type editor -->
        <Modal v-if="tenderModal" :title="editingTender ? t('pos_money.edit_tender') : t('pos_money.add_tender')" @close="tenderModal = false">
            <form @submit.prevent="saveTender" class="space-y-4">
                <label class="block">
                    <span class="label">{{ t('common.name') }}</span>
                    <input v-model="tenderForm.name" class="input" maxlength="120" :placeholder="t('pos_money.tender_name_placeholder')" />
                    <FormError :errors="tenderErrors" field="name" />
                </label>

                <label class="block">
                    <span class="label">{{ t('pos_money.kind') }}</span>
                    <select v-model="tenderForm.kind" class="input">
                        <option v-for="k in TENDER_KINDS" :key="k" :value="k">{{ t('pos_money.tender_kind.' + k) }}</option>
                    </select>
                    <p class="set-help">{{ t('pos_money.tender_kind_hint') }}</p>
                    <FormError :errors="tenderErrors" field="kind" />
                </label>

                <div class="block">
                    <label class="flex items-center gap-2 text-sm" style="color:var(--body)">
                        <button type="button" class="switch" :class="{ on: tenderForm.is_active }" @click="tenderForm.is_active = !tenderForm.is_active"></button>
                        {{ t('common.active') }}
                    </label>
                    <p class="set-help">{{ t('pos_money.tender_active_hint') }}</p>
                    <FormError :errors="tenderErrors" field="is_active" />
                </div>

                <label class="block">
                    <span class="label">{{ t('pos_money.sort_order') }}</span>
                    <input v-model="tenderForm.sort_order" class="input" dir="ltr" inputmode="numeric" data-en-digits />
                    <FormError :errors="tenderErrors" field="sort_order" />
                </label>

                <div class="set-form-actions">
                    <button type="submit" class="btn btn-accent" :disabled="tenderSaving || !tenderForm.name">{{ tenderSaving ? t('common.saving') : t('common.save') }}</button>
                    <button type="button" class="btn btn-ghost" @click="tenderModal = false">{{ t('common.cancel') }}</button>
                </div>
            </form>
        </Modal>
    </div>
</template>
