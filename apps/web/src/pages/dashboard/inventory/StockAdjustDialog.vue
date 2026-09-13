<script setup>
import { ref, computed, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import api from '@xorder/api-client/api.js'
import { pickLocalized } from '@xorder/ui/localize.js'
import FormError from '@xorder/ui/FormError.vue'
import ReasonDialog from '../purchasing/ReasonDialog.vue'
import { parseQuantity, formatMilli, costAt } from '../../../lib/quantity.js'
import { amountToMinor, minorToAmount } from '../../../lib/money.js'
import { money, qty } from '../purchasing/format.js'

// CB-09 slice d. One dialog for every stock entry that is not a delivery:
// opening stock, waste, adding, taking off, and a count. Each is posted as
// ONE new movement with a reason; nothing already recorded is edited.
//
// Everything shown here before saving is a PREVIEW (integers only, through
// lib/quantity.js): the server reads the position under a lock on the level
// row and is authoritative. A count in particular is posted as the counted
// quantity, and the server takes the difference from what is recorded at
// that moment, not from the figure this page loaded.
const props = defineProps({
    opening: { type: Boolean, default: false },
    branches: { type: Array, required: true },
    items: { type: Array, required: true },
    units: { type: Array, required: true },
    exponent: { type: Number, default: 2 },
    currency: { type: String, default: null },
    branchId: { type: [Number, String], default: '' },
    stockItemId: { type: [Number, String], default: '' },
})
const emit = defineEmits(['saved', 'close'])
const { t, locale } = useI18n()

// Reason codes per entry, the server's StockAdjustmentReason::forKind.
const REASONS = {
    opening: ['opening_balance'],
    waste: ['expired', 'spoiled', 'damaged', 'preparation_error', 'other'],
    up: ['found', 'entry_error', 'other'],
    down: ['missing', 'internal_use', 'entry_error', 'other'],
    count: ['stock_count'],
}
const MODES = ['waste', 'up', 'down', 'count']

const mode = ref(props.opening ? 'opening' : 'waste')
const activeBranches = computed(() => props.branches.filter((b) => b.is_active !== false || b.id === Number(props.branchId)))
const branch = ref(props.branchId ? Number(props.branchId) : (activeBranches.value.length === 1 ? activeBranches.value[0].id : ''))
const itemId = ref(props.stockItemId ? Number(props.stockItemId) : '')
const quantity = ref('')
const unitCost = ref('')
const errors = ref({})
const general = ref('')
const busy = ref(false)

const nameOf = (s) => (s ? (pickLocalized(s, 'name', locale.value) || s.name_en || s.name_ar || `#${s.id}`) : '')
// A retired item can still be written off; it is offered only when preset.
const itemOptions = computed(() => props.items
    .filter((i) => i.is_active || i.id === itemId.value)
    .slice()
    .sort((a, b) => nameOf(a).localeCompare(nameOf(b), locale.value)))
const item = computed(() => props.items.find((i) => i.id === itemId.value) || null)
const unit = computed(() => (item.value ? props.units.find((u) => u.code === item.value.unit_code) : null))
const unitLabel = computed(() => (unit.value ? (pickLocalized(unit.value, 'name', locale.value) || unit.value.code) : (item.value?.unit_code || '')))

// The position at this branch, read fresh for the chosen branch.
const levels = ref({})
const levelLoading = ref(false)
async function loadLevels(id) {
    if (!id || levels.value[id]) return
    levelLoading.value = true
    try {
        const res = await api.get('api/dashboard/stock-levels', { params: { branch_id: id } })
        levels.value = { ...levels.value, [id]: res.data.data }
    } catch {
        levels.value = { ...levels.value, [id]: [] }
    } finally {
        levelLoading.value = false
    }
}
watch(branch, loadLevels, { immediate: true })
const level = computed(() => (levels.value[branch.value] || []).find((l) => l.stock_item_id === itemId.value) || null)
const held = computed(() => level.value?.quantity_milli ?? level.value?.received_milli ?? 0)
const average = computed(() => level.value?.average_cost_minor ?? 0)
const hasHistory = computed(() => !!level.value)

const milli = computed(() => parseQuantity(quantity.value))
const milliOk = computed(() => Number.isSafeInteger(milli.value))
const delta = computed(() => {
    if (!milliOk.value) return null
    switch (mode.value) {
    case 'opening': case 'up': return milli.value
    case 'waste': case 'down': return -milli.value
    case 'count': return milli.value - held.value
    default: return null
    }
})
const goesIn = computed(() => delta.value !== null && delta.value > 0)
const showCost = computed(() => mode.value === 'opening' || mode.value === 'up' || (mode.value === 'count' && goesIn.value))
const costRequired = computed(() => mode.value === 'opening' || (!hasHistory.value && showCost.value))
const costMinor = computed(() => amountToMinor(unitCost.value, props.exponent))
const reasons = computed(() => REASONS[mode.value])
const cost = (minor) => money(minor, props.exponent, props.currency, locale.value)
const signed = (m) => (m > 0 ? '+' : '') + formatMilli(m) + ' ' + (item.value?.unit_code || '')

watch(mode, () => { errors.value = {}; general.value = '' })

async function submit({ reason, note }) {
    general.value = ''
    const e = {}
    const qtyField = mode.value === 'count' ? 'counted_milli' : 'quantity_milli'
    if (!branch.value) e.branch_id = [t('purchasing.adj_choose_branch')]
    if (!item.value) e.stock_item_id = [t('purchasing.adj_choose_item')]
    if (!milliOk.value || milli.value < 0 || (mode.value !== 'count' && milli.value === 0)) e[qtyField] = [t('purchasing.adj_enter_quantity')]
    else if (unit.value && !unit.value.allows_fraction && milli.value % 1000 !== 0) e[qtyField] = [t('purchasing.adj_whole_only')]
    if (showCost.value) {
        if (Number.isNaN(costMinor.value)) e.unit_cost_minor = [t('purchasing.adj_invalid_amount')]
        else if (costRequired.value && costMinor.value === null) e.unit_cost_minor = [t('purchasing.adj_enter_cost')]
    }
    errors.value = e
    if (Object.keys(e).length) return

    const body = {
        branch_id: branch.value,
        stock_item_id: item.value.id,
        // The unit this page showed: the server refuses it rather than
        // booking the number in a unit the item was changed to since.
        unit_code: item.value.unit_code,
        reason,
        note,
    }
    if (mode.value === 'opening') Object.assign(body, { kind: 'opening', quantity_milli: milli.value })
    if (mode.value === 'waste') Object.assign(body, { kind: 'waste', quantity_milli: milli.value })
    if (mode.value === 'up') Object.assign(body, { kind: 'adjustment', quantity_milli: milli.value })
    if (mode.value === 'down') Object.assign(body, { kind: 'adjustment', quantity_milli: -milli.value })
    if (mode.value === 'count') Object.assign(body, { kind: 'count', counted_milli: milli.value })
    if (showCost.value && costMinor.value !== null) body.unit_cost_minor = costMinor.value

    busy.value = true
    try {
        const res = await api.post('api/dashboard/stock-adjustments', body)
        emit('saved', res.data.data)
    } catch (err) {
        const raw = err.response?.data?.errors || {}
        errors.value = raw
        // A refusal about the position (held in another unit, an opening
        // already recorded) names no field: say it in the dialog.
        if (!Object.keys(raw).length || !['branch_id', 'stock_item_id', 'quantity_milli', 'counted_milli', 'unit_cost_minor', 'reason', 'note'].some((k) => raw[k])) {
            general.value = err.response?.data?.message || t('common.error')
        }
        // The position may have moved under us: re-read it for the preview.
        const b = branch.value
        levels.value = { ...levels.value, [b]: undefined }
        loadLevels(b)
    } finally {
        busy.value = false
    }
}
</script>

<template>
    <ReasonDialog
        :title="opening ? t('purchasing.adj_opening_title') : t('purchasing.adj_title')"
        :message="opening ? t('purchasing.adj_opening_hint') : t('purchasing.adj_message')"
        :reasons="reasons"
        label-prefix="purchasing.stock_reasons"
        :confirm-text="t('purchasing.adj_record')"
        :busy="busy"
        :errors="errors"
        @submit="submit"
        @close="emit('close')"
    >
        <div class="space-y-4">
            <div v-if="!opening" class="flex flex-wrap gap-2" role="group" :aria-label="t('purchasing.kind')">
                <button
                    v-for="m in MODES"
                    :key="m"
                    type="button"
                    class="btn btn-sm"
                    :class="mode === m ? 'btn-accent' : 'btn-ghost'"
                    :aria-pressed="mode === m"
                    @click="mode = m"
                >{{ t('purchasing.adj_modes.' + m) }}</button>
            </div>

            <div class="grid gap-3 sm:grid-cols-2">
                <label v-if="activeBranches.length > 1 || !branch" class="block">
                    <span class="label">{{ t('purchasing.branch') }}</span>
                    <select v-model="branch" class="input">
                        <option value="" disabled>{{ t('purchasing.adj_choose_branch') }}</option>
                        <option v-for="b in activeBranches" :key="b.id" :value="b.id">{{ nameOf(b) }}</option>
                    </select>
                    <FormError :errors="errors" field="branch_id" />
                </label>
                <label class="block">
                    <span class="label">{{ t('purchasing.item') }}</span>
                    <select v-model="itemId" class="input">
                        <option value="" disabled>{{ t('purchasing.adj_choose_item') }}</option>
                        <option v-for="i in itemOptions" :key="i.id" :value="i.id">{{ nameOf(i) }}{{ i.is_active ? '' : ' ' + t('purchasing.retired_suffix') }}</option>
                    </select>
                    <FormError :errors="errors" field="stock_item_id" />
                </label>
            </div>

            <p v-if="item && branch && !levelLoading" class="text-sm" style="color:var(--muted)">
                <template v-if="hasHistory">
                    {{ t('purchasing.adj_recorded_now') }}:
                    <span class="mono" dir="ltr" style="color:var(--ink)">{{ qty(held, item.unit_code) }}</span>
                    · {{ t('purchasing.adj_at_average') }}
                    <span class="mono" dir="ltr" style="color:var(--ink)">{{ cost(average) }}</span>
                </template>
                <template v-else>{{ t('purchasing.adj_nothing_here') }}</template>
            </p>

            <div class="grid gap-3 sm:grid-cols-2">
                <label class="block">
                    <span class="label">{{ mode === 'count' ? t('purchasing.adj_counted_in', { unit: unitLabel }) : t('purchasing.adj_quantity_in', { unit: unitLabel }) }}</span>
                    <input v-model="quantity" class="input mono" dir="ltr" inputmode="decimal" autocomplete="off" />
                    <FormError :errors="errors" :field="mode === 'count' ? 'counted_milli' : 'quantity_milli'" />
                </label>
                <label v-if="showCost" class="block">
                    <span class="label">{{ t('purchasing.adj_cost_per', { unit: unitLabel }) }}</span>
                    <input v-model="unitCost" class="input mono" dir="ltr" inputmode="decimal" autocomplete="off" :placeholder="costRequired ? '' : minorToAmount(average, exponent)" />
                    <p v-if="costRequired && mode !== 'opening'" class="text-xs mt-1" style="color:var(--muted)">{{ t('purchasing.adj_cost_required_hint') }}</p>
                    <p v-else-if="!costRequired" class="text-xs mt-1" style="color:var(--muted)">
                        {{ t('purchasing.adj_cost_default_hint') }}: <span class="mono" dir="ltr">{{ cost(average) }}</span>
                    </p>
                    <FormError :errors="errors" field="unit_cost_minor" />
                </label>
            </div>

            <div v-if="item && branch && delta !== null" class="card p-3 text-sm space-y-1" style="background:var(--page)">
                <div v-if="mode === 'count' && delta === 0" style="color:var(--muted)">{{ t('purchasing.adj_count_same') }}</div>
                <template v-else>
                    <div v-if="mode === 'count'" class="flex justify-between gap-3">
                        <span style="color:var(--muted)">{{ t('purchasing.adj_count_difference') }}</span>
                        <span class="mono" dir="ltr" style="color:var(--ink)">{{ signed(delta) }}</span>
                    </div>
                    <div v-if="delta < 0" class="flex justify-between gap-3">
                        <span style="color:var(--muted)">{{ t('purchasing.adj_leaves_at') }}</span>
                        <span class="mono" dir="ltr" style="color:var(--ink)">{{ cost(costAt(-delta, average)) }}</span>
                    </div>
                    <div class="flex justify-between gap-3">
                        <span style="color:var(--muted)">{{ t('purchasing.adj_after') }}</span>
                        <span class="mono" dir="ltr" style="color:var(--ink)">{{ qty(held + delta, item.unit_code) }}</span>
                    </div>
                    <div v-if="held + delta < 0" class="pt-1" style="color:var(--amber)">{{ t('purchasing.adj_goes_negative') }}</div>
                </template>
            </div>

            <p v-if="general" class="text-sm" style="color:var(--red)" role="alert">{{ general }}</p>
        </div>
    </ReasonDialog>
</template>
