<script setup>
import { ref, reactive, computed, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute, useRouter } from 'vue-router'
import api from '@xorder/api-client/api.js'
import { withMinDuration } from '../../../lib/minLoading.js'
import { pickLocalized } from '@xorder/ui/localize.js'
import { amountToMinor, minorToAmount, percentToBp, bpToPercent } from '../../../lib/money.js'
import { parseQuantity, formatMilli, costAt, orderTotals } from '../../../lib/quantity.js'
import ListSkeleton from '@xorder/ui/ListSkeleton.vue'
import ErrorState from '@xorder/ui/ErrorState.vue'
import FormError from '@xorder/ui/FormError.vue'
import Icon from '@xorder/ui/Icon.vue'
import { alert } from '@xorder/ui/alert.js'
import { money } from './format.js'

// CB-09 slice b. Create or edit a purchase-order DRAFT. The whole draft is
// written at once (PUT replaces the lines), as the till's editor does.
//
// Nothing here uses a float. Quantities are parsed to integer thousandths by
// lib/quantity.js, amounts to minor units and rates to basis points by
// lib/money.js (digit strings, not parseFloat), and the preview totals run
// on BigInt with the server's rounding points. The server recomputes and is
// authoritative; the preview only saves a round trip.
//
// Retired suppliers, units and stock items are not offered, except where
// this draft already carries them (the server applies the same rule).
const { t, locale } = useI18n()
const route = useRoute()
const router = useRouter()

const isEdit = computed(() => !!route.params.id)
const lookups = ref({ branches: [], suppliers: [], units: [], stock_items: [], exponent: 2, currency: null })
const original = ref(null)
const loading = ref(true)
const failed = ref(false)
const saving = ref(false)
const errors = ref({})

let seq = 0
const blankLine = () => ({ key: ++seq, stock_item_id: '', description: '', sku: '', quantity: '', unit_code: 'ea', unit_cost: '', tax_rate: '' })
const form = reactive({ branch_id: '', supplier_id: '', expected_at: '', notes: '', lines: [] })

const exponent = computed(() => original.value?.exponent ?? lookups.value.exponent ?? 2)
const currency = computed(() => original.value?.currency ?? lookups.value.currency)

async function load() {
    loading.value = true
    failed.value = false
    try {
        const [lk, po] = await withMinDuration(Promise.all([
            api.get('api/dashboard/purchasing/lookups'),
            isEdit.value ? api.get(`api/dashboard/purchase-orders/${route.params.id}`) : Promise.resolve(null),
        ]))
        lookups.value = lk.data.data
        if (po) {
            const o = po.data.data
            // Only a draft is editable; anything else is shown, not edited.
            if (!o.is_editable) {
                router.replace({ name: 'dashboard.purchasing.order', params: { id: o.id } })
                return
            }
            original.value = o
            Object.assign(form, {
                branch_id: o.branch_id, supplier_id: o.supplier_id,
                expected_at: o.expected_at || '', notes: o.notes || '',
                lines: o.lines.map((l) => ({
                    key: ++seq,
                    stock_item_id: l.stock_item_id ?? '',
                    description: l.description || '',
                    sku: l.sku || '',
                    quantity: formatMilli(l.ordered_milli),
                    unit_code: l.unit_code,
                    unit_cost: minorToAmount(l.unit_cost_minor, o.exponent),
                    tax_rate: l.tax_rate_bp ? bpToPercent(l.tax_rate_bp) : '',
                })),
            })
        } else {
            const active = lookups.value.branches.filter((b) => b.is_active)
            if (active.length === 1) form.branch_id = active[0].id
            form.lines = [blankLine()]
        }
    } catch {
        failed.value = true
    } finally {
        loading.value = false
    }
}
onMounted(load)

const nameOf = (s) => (s ? (pickLocalized(s, 'name', locale.value) || s.name_en || s.name_ar || `#${s.id}`) : '')
const keptItems = computed(() => new Set((original.value?.lines || []).map((l) => l.stock_item_id).filter(Boolean)))
const keptUnits = computed(() => new Set((original.value?.lines || []).map((l) => l.unit_code)))
const branchOptions = computed(() => lookups.value.branches.filter((b) => b.is_active || b.id === original.value?.branch_id))
const supplierOptions = computed(() => lookups.value.suppliers.filter((s) => s.is_active || s.id === original.value?.supplier_id))
const itemOptions = computed(() => lookups.value.stock_items.filter((i) => i.is_active || keptItems.value.has(i.id)))
const unitOptions = computed(() => lookups.value.units.filter((u) => u.is_active || keptUnits.value.has(u.code)))
const itemOf = (id) => lookups.value.stock_items.find((i) => i.id === Number(id))
const unitOf = (code) => lookups.value.units.find((u) => u.code === code)
const retired = (x) => (x && !x.is_active ? ' ' + t('purchasing.retired_suffix') : '')
const supplierRetired = computed(() => {
    const s = lookups.value.suppliers.find((x) => x.id === Number(form.supplier_id))
    return s && !s.is_active
})

// A stock-item line is measured in the item's unit, always (the server
// forces it; the select just shows it locked).
function lineUnit(l) {
    return l.stock_item_id ? (itemOf(l.stock_item_id)?.unit_code || l.unit_code) : l.unit_code
}
function onItemChange(l) {
    if (l.stock_item_id) l.unit_code = lineUnit(l)
}

function parsed(l) {
    return {
        milli: parseQuantity(l.quantity),
        cost: amountToMinor(l.unit_cost, exponent.value),
        bp: l.tax_rate === '' || l.tax_rate == null ? 0 : percentToBp(l.tax_rate),
        unit: unitOf(lineUnit(l)),
    }
}
const valid = (n) => Number.isSafeInteger(n) && n >= 0

function lineTotal(l) {
    const p = parsed(l)
    return valid(p.milli) && p.milli > 0 && valid(p.cost) ? costAt(p.milli, p.cost) : null
}
const preview = computed(() => orderTotals(form.lines.map((l) => {
    const p = parsed(l)
    return { quantity_milli: valid(p.milli) && p.milli > 0 ? p.milli : NaN, unit_cost_minor: valid(p.cost) ? p.cost : NaN, tax_rate_bp: valid(p.bp) ? p.bp : 0 }
})))
const show = (minor) => money(minor, exponent.value, currency.value, locale.value)

function addLine() { form.lines.push(blankLine()) }
function removeLine(i) { form.lines.splice(i, 1) }

function validate() {
    const e = {}
    if (!form.branch_id) e.branch_id = [t('purchasing.pick_branch')]
    if (!form.supplier_id) e.supplier_id = [t('purchasing.pick_supplier')]
    form.lines.forEach((l, i) => {
        const p = parsed(l)
        if (!valid(p.milli) || p.milli <= 0) e[`lines.${i}.quantity_milli`] = [t('purchasing.quantity_invalid')]
        else if (p.unit && !p.unit.allows_fraction && p.milli % 1000 !== 0) e[`lines.${i}.quantity_milli`] = [t('purchasing.whole_only_hint')]
        if (!valid(p.cost)) e[`lines.${i}.unit_cost_minor`] = [t('purchasing.amount_invalid')]
        if (!valid(p.bp) || p.bp > 10000) e[`lines.${i}.tax_rate_bp`] = [t('purchasing.rate_invalid')]
        if (!l.stock_item_id && !l.description.trim()) e[`lines.${i}.description`] = [t('purchasing.line_description_hint')]
    })
    return e
}

function payload() {
    return {
        branch_id: Number(form.branch_id),
        supplier_id: Number(form.supplier_id),
        expected_at: form.expected_at || null,
        notes: form.notes || null,
        lines: form.lines.map((l) => {
            const p = parsed(l)
            return {
                stock_item_id: l.stock_item_id ? Number(l.stock_item_id) : null,
                description: l.description.trim() || null,
                sku: l.sku.trim() || null,
                unit_code: lineUnit(l),
                quantity_milli: p.milli,
                unit_cost_minor: p.cost,
                tax_rate_bp: p.bp,
            }
        }),
    }
}

async function save() {
    if (saving.value) return
    errors.value = validate()
    if (Object.keys(errors.value).length) return
    saving.value = true
    try {
        const { data } = isEdit.value
            ? await api.put(`api/dashboard/purchase-orders/${route.params.id}`, payload())
            : await api.post('api/dashboard/purchase-orders', payload())
        router.push({ name: 'dashboard.purchasing.order', params: { id: data.data.id } })
    } catch (err) {
        errors.value = err.response?.data?.errors || {}
        if (!Object.keys(errors.value).length) alert(err.response?.data?.message || t('common.error'))
    } finally {
        saving.value = false
    }
}

function back() {
    if (isEdit.value) router.push({ name: 'dashboard.purchasing.order', params: { id: route.params.id } })
    else router.push({ name: 'dashboard.purchasing.orders' })
}
</script>

<template>
    <div class="space-y-5">
        <button type="button" class="back" @click="back">
            <Icon name="chevronDown" :size="16" class="rotate-90 rtl:-rotate-90" />{{ t('purchasing.orders_title') }}
        </button>

        <div>
            <h1 class="page-title">{{ isEdit ? t('purchasing.edit_order') : t('purchasing.new_order') }}</h1>
            <p v-if="isEdit && original" class="page-sub" style="color:var(--body)"><span class="mono" dir="ltr">{{ t('purchasing.draft_ref', { id: original.id }) }}</span></p>
        </div>

        <ErrorState v-if="failed" :message="t('common.error')" @retry="load" />
        <div v-else-if="loading" class="card"><ListSkeleton /></div>

        <form v-else class="space-y-5" @submit.prevent="save">
            <div class="card p-5 space-y-4">
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                    <label class="block"><span class="label">{{ t('purchasing.supplier') }}</span>
                        <select v-model="form.supplier_id" class="input">
                            <option value="" disabled>{{ t('purchasing.pick_supplier') }}</option>
                            <option v-for="s in supplierOptions" :key="s.id" :value="s.id">{{ nameOf(s) }}{{ retired(s) }}</option>
                        </select>
                        <span v-if="supplierRetired" class="text-xs" style="color:var(--p-primary-800)">{{ t('purchasing.supplier_retired_note') }}</span>
                        <FormError :errors="errors" field="supplier_id" /></label>
                    <label class="block"><span class="label">{{ t('purchasing.branch') }}</span>
                        <select v-model="form.branch_id" class="input">
                            <option value="" disabled>{{ t('purchasing.pick_branch') }}</option>
                            <option v-for="b in branchOptions" :key="b.id" :value="b.id">{{ nameOf(b) }}</option>
                        </select>
                        <FormError :errors="errors" field="branch_id" /></label>
                    <label class="block"><span class="label">{{ t('purchasing.expected_at') }}</span>
                        <input v-model="form.expected_at" type="date" class="input" dir="ltr" />
                        <FormError :errors="errors" field="expected_at" /></label>
                </div>
                <label class="block"><span class="label">{{ t('purchasing.notes') }}</span>
                    <textarea v-model="form.notes" class="input" rows="2" maxlength="2000"></textarea>
                    <FormError :errors="errors" field="notes" /></label>
            </div>

            <div class="card p-5 space-y-3">
                <div class="flex items-center justify-between gap-3">
                    <h2 class="card-title">{{ t('purchasing.lines') }}</h2>
                    <button type="button" class="btn btn-ghost btn-sm" @click="addLine"><Icon name="plus" :size="15" />{{ t('purchasing.add_line') }}</button>
                </div>
                <FormError :errors="errors" field="lines" />
                <p v-if="!form.lines.length" class="text-sm" style="color:var(--body)">{{ t('purchasing.no_lines_yet') }}</p>

                <div v-for="(l, i) in form.lines" :key="l.key" class="line-box space-y-3">
                    <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                        <label class="block"><span class="label">{{ t('purchasing.line_stock_item') }}</span>
                            <select v-model="l.stock_item_id" class="input" @change="onItemChange(l)">
                                <option value="">{{ t('purchasing.line_not_stocked') }}</option>
                                <option v-for="it in itemOptions" :key="it.id" :value="it.id">{{ nameOf(it) }}{{ retired(it) }}</option>
                            </select>
                            <FormError :errors="errors" :field="`lines.${i}.stock_item_id`" /></label>
                        <label class="block"><span class="label">{{ t('purchasing.line_description') }}</span>
                            <input v-model="l.description" class="input" maxlength="200" :placeholder="l.stock_item_id ? nameOf(itemOf(l.stock_item_id)) : ''" />
                            <span v-if="l.stock_item_id" class="text-xs" style="color:var(--body)">{{ t('purchasing.line_description_hint') }}</span>
                            <FormError :errors="errors" :field="`lines.${i}.description`" /></label>
                    </div>
                    <div class="grid grid-cols-2 sm:grid-cols-5 gap-3 items-start">
                        <label class="block"><span class="label">{{ t('purchasing.quantity') }}</span>
                            <input v-model="l.quantity" class="input mono" dir="ltr" inputmode="decimal" data-en-digits autocomplete="off" />
                            <FormError :errors="errors" :field="`lines.${i}.quantity_milli`" /></label>
                        <label class="block"><span class="label">{{ t('purchasing.unit') }}</span>
                            <select v-if="!l.stock_item_id" v-model="l.unit_code" class="input mono" dir="ltr">
                                <option v-for="u in unitOptions" :key="u.code" :value="u.code">{{ u.code }}{{ retired(u) }}</option>
                            </select>
                            <input v-else class="input mono" dir="ltr" :value="lineUnit(l)" disabled />
                            <FormError :errors="errors" :field="`lines.${i}.unit_code`" /></label>
                        <label class="block"><span class="label">{{ t('purchasing.unit_cost') }}</span>
                            <input v-model="l.unit_cost" class="input mono" dir="ltr" inputmode="decimal" data-en-digits autocomplete="off" />
                            <FormError :errors="errors" :field="`lines.${i}.unit_cost_minor`" /></label>
                        <label class="block"><span class="label">{{ t('purchasing.tax_rate') }}</span>
                            <input v-model="l.tax_rate" class="input mono" dir="ltr" inputmode="decimal" data-en-digits placeholder="0" autocomplete="off" />
                            <FormError :errors="errors" :field="`lines.${i}.tax_rate_bp`" /></label>
                        <div class="block">
                            <span class="label">{{ t('purchasing.line_total') }}</span>
                            <div class="flex items-center justify-between gap-2 py-2">
                                <span class="mono line-total">{{ lineTotal(l) == null ? '—' : show(lineTotal(l)) }}</span>
                                <button type="button" class="icon-btn" :title="t('purchasing.remove_line')" :aria-label="t('purchasing.remove_line')" @click="removeLine(i)"><Icon name="close" :size="16" /></button>
                            </div>
                        </div>
                    </div>
                </div>

                <div class="totals-wrap form-totals">
                    <div class="totals">
                        <div class="totals-row"><span>{{ t('purchasing.subtotal') }}</span><span class="mono">{{ show(preview.subtotal_minor) }}</span></div>
                        <div class="totals-row"><span>{{ t('purchasing.tax') }}</span><span class="mono">{{ show(preview.tax_minor) }}</span></div>
                        <div class="totals-row totals-grand"><span>{{ t('purchasing.total') }}</span><span class="mono">{{ show(preview.total_minor) }}</span></div>
                        <p class="totals-note">{{ t('purchasing.preview_note') }}</p>
                    </div>
                </div>
            </div>

            <div class="form-actions">
                <button type="button" class="btn btn-ghost" :disabled="saving" @click="back">{{ t('common.cancel') }}</button>
                <button type="submit" class="btn btn-accent" :disabled="saving">
                    <Icon v-if="saving" name="loading" :size="16" class="animate-spin" />
                    {{ saving ? t('common.saving') : t('purchasing.save_draft') }}
                </button>
            </div>
        </form>
    </div>
</template>

<style scoped>
/* Presentation only: theme variables and the PrimeVue primary scale; no new hex values. */
.back { display: inline-flex; align-items: center; gap: 6px; min-height: 36px; font-size: 14.5px; font-weight: 500; color: var(--body); }
.back:hover { color: var(--p-primary-700); }
.totals-wrap { display: flex; justify-content: flex-end; padding: 16px 20px 20px; border-top: 1px solid var(--line); background: var(--page); }
.totals { width: 100%; max-width: 340px; }
.totals-row { display: flex; justify-content: space-between; gap: 12px; padding: 5px 0; font-size: 15px; color: var(--body); }
.totals-row .mono { color: var(--ink); }
.totals-grand { align-items: baseline; margin-top: 8px; padding-top: 12px; border-top: 1px solid var(--line); font-family: var(--font-display); font-weight: 700; font-size: 17px; color: var(--ink); }
.totals-grand .mono { font-size: 26px; line-height: 1.1; }
.line-box { border: 1px solid var(--line); border-radius: 12px; padding: 14px; background: var(--page); }
.form-totals { border: 1px solid var(--line); border-radius: 12px; }
.totals-note { margin-top: 8px; font-size: 13.5px; color: var(--body); }
.form-actions { position: sticky; bottom: 0; z-index: 5; display: flex; justify-content: flex-end; gap: 8px; padding: 12px 16px; background: var(--card); border: 1px solid var(--line); border-radius: 15px; }
.form-actions .btn { min-height: 44px; }
@media (max-width: 639px) { .form-actions .btn { flex: 1 1 auto; justify-content: center; } }
.line-total { color: var(--ink); font-weight: 600; }
.card-title { font-family: var(--font-display); font-weight: 600; font-size: 16.5px; color: var(--ink); }
</style>
