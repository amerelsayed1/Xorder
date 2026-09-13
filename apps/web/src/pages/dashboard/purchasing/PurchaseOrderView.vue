<script setup>
import { ref, reactive, computed, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute, useRouter } from 'vue-router'
import api from '@xorder/api-client/api.js'
import { useAuth } from '@xorder/api-client/auth.js'
import { withMinDuration } from '../../../lib/minLoading.js'
import { pickLocalized } from '@xorder/ui/localize.js'
import { bpToPercent } from '../../../lib/money.js'
import { parseQuantity, formatMilli } from '../../../lib/quantity.js'
import Skeleton from '@xorder/ui/Skeleton.vue'
import ErrorState from '@xorder/ui/ErrorState.vue'
import Dialog from '@xorder/ui/Dialog.vue'
import FormError from '@xorder/ui/FormError.vue'
import Icon from '@xorder/ui/Icon.vue'
import { confirm } from '@xorder/ui/confirm.js'
import { alert } from '@xorder/ui/alert.js'
import { statusBadge, fmtDate, money, qty, CLOSE_REASONS } from './format.js'
import ReasonDialog from './ReasonDialog.vue'

// CB-09 slice b. One purchase order: its lines, what arrived, and the
// actions its status allows (edit a draft, send, cancel, receive goods).
//
// The buttons follow the flags the server returned, but the server re-checks
// every transition under a lock on the order row: a page left open while
// someone else booked a delivery in gets a 409 on Cancel, never a cancelled
// order with goods in the kitchen. That refusal is shown, then the order is
// reloaded so the page stops lying.
const { t, locale } = useI18n()
const route = useRoute()
const router = useRouter()
const auth = useAuth()
const canWrite = computed(() => auth.can('purchase.manage') && !auth.isReadOnly)

const order = ref(null)
const units = ref([])
const loading = ref(true)
const failed = ref(false)
const busy = ref(false)

async function load() {
    loading.value = true
    failed.value = false
    try {
        const [o, lk] = await withMinDuration(Promise.all([
            api.get(`api/dashboard/purchase-orders/${route.params.id}`),
            units.value.length ? Promise.resolve(null) : api.get('api/dashboard/purchasing/lookups'),
        ]))
        order.value = o.data.data
        if (lk) units.value = lk.data.data.units
    } catch {
        failed.value = true
    } finally {
        loading.value = false
    }
}
onMounted(load)

const nameOf = (s) => (s ? (pickLocalized(s, 'name', locale.value) || s.name_en || s.name_ar || `#${s.id}`) : '')
const show = (minor) => money(minor, order.value?.exponent, order.value?.currency, locale.value)
const unitOf = (code) => units.value.find((u) => u.code === code)
const received = computed(() => (order.value?.lines || []).some((l) => l.received_milli > 0))
const canCancel = computed(() => order.value?.can_cancel && !received.value)
const supplierRetired = computed(() => order.value?.supplier && !order.value.supplier.is_active)

async function transition(kind) {
    const copy = kind === 'send'
        ? { title: t('purchasing.send_title'), message: t('purchasing.send_message'), confirmText: t('purchasing.send'), cancelText: t('common.cancel') }
        : { title: t('purchasing.cancel_title'), message: t('purchasing.cancel_message'), confirmText: t('purchasing.cancel_order'), cancelText: t('purchasing.keep_order') }
    if (!(await confirm(copy))) return
    busy.value = true
    try {
        const { data } = await api.post(`api/dashboard/purchase-orders/${order.value.id}/${kind}`)
        order.value = data.data
    } catch (err) {
        alert(err.response?.data?.message || t('common.error'))
        if (err.response?.status === 409) load()
    } finally {
        busy.value = false
    }
}

// ------------------------------------------------------------- close short
// CB-09 D11. A part delivery whose rest is not coming is closed short: it
// becomes `received`, marked closed short, and the rest is recorded as not
// coming. Stock already booked in is never touched. The server allows it only
// on a part-received order, re-checked under the order lock.
const showClose = ref(false)
const closeErrors = ref({})

async function submitClose({ reason, note }) {
    busy.value = true
    closeErrors.value = {}
    try {
        const { data } = await api.post(`api/dashboard/purchase-orders/${order.value.id}/close`, { reason, note })
        order.value = data.data
        showClose.value = false
    } catch (err) {
        closeErrors.value = err.response?.data?.errors || {}
        if (err.response?.status === 409) { showClose.value = false; alert(err.response.data.message); load() }
        else if (!Object.keys(closeErrors.value).length) alert(err.response?.data?.message || t('common.error'))
    } finally {
        busy.value = false
    }
}
const canInvoice = computed(() => order.value && order.value.status !== 'draft')

// ----------------------------------------------------------------- receive
const showReceive = ref(false)
const recvErrors = ref({})
const recv = reactive({ lines: [], occurred_at: '', note: '' })

function localNow() {
    const d = new Date()
    d.setMinutes(d.getMinutes() - d.getTimezoneOffset())
    return d.toISOString().slice(0, 16)
}

// Every line prefilled with what is still owed (the till's receive dialog
// does the same); a person corrects what actually came.
function openReceive() {
    recvErrors.value = {}
    recv.lines = order.value.lines.map((l) => ({
        id: l.id, description: l.description, unit_code: l.unit_code, stock_item_id: l.stock_item_id,
        ordered: l.ordered_milli, got: l.received_milli, outstanding: l.outstanding_milli,
        quantity: l.outstanding_milli > 0 ? formatMilli(l.outstanding_milli) : '',
    }))
    recv.occurred_at = localNow()
    recv.note = ''
    showReceive.value = true
}

async function submitReceive() {
    if (busy.value) return
    const e = {}
    const lines = recv.lines.map((l, i) => {
        const milli = l.quantity === '' ? 0 : parseQuantity(l.quantity)
        const unit = unitOf(l.unit_code)
        if (!Number.isSafeInteger(milli) || milli < 0) e[`lines.${i}.quantity_milli`] = [t('purchasing.quantity_invalid')]
        else if (unit && !unit.allows_fraction && milli % 1000 !== 0) e[`lines.${i}.quantity_milli`] = [t('purchasing.whole_only_hint')]
        return { line_id: l.id, quantity_milli: milli }
    })
    recvErrors.value = e
    if (Object.keys(e).length) return

    busy.value = true
    try {
        const { data } = await api.post(`api/dashboard/purchase-orders/${order.value.id}/receipts`, {
            lines,
            occurred_at: recv.occurred_at ? new Date(recv.occurred_at).toISOString() : null,
            note: recv.note || null,
        })
        order.value = data.data
        showReceive.value = false
    } catch (err) {
        recvErrors.value = err.response?.data?.errors || {}
        if (!Object.keys(recvErrors.value).length || recvErrors.value.lines) alert(err.response?.data?.message || t('common.error'))
        if (err.response?.status === 409) { showReceive.value = false; load() }
    } finally {
        busy.value = false
    }
}
</script>

<template>
    <div class="space-y-5">
        <button type="button" class="flex items-center gap-1.5 text-sm" style="color:var(--muted)" @click="router.push({ name: 'dashboard.purchasing.orders' })">
            <Icon name="chevronDown" :size="16" class="rotate-90 rtl:-rotate-90" />{{ t('purchasing.orders_title') }}
        </button>

        <ErrorState v-if="failed" :message="t('common.error')" @retry="load" />

        <div v-else-if="loading || !order" class="card p-5 space-y-3">
            <Skeleton w="40%" h="22px" /><Skeleton w="60%" h="14px" /><Skeleton w="100%" h="120px" />
        </div>

        <template v-else>
            <div class="flex flex-wrap items-start justify-between gap-3">
                <div class="space-y-1">
                    <h1 class="page-title flex flex-wrap items-center gap-2">
                        <span class="mono" dir="ltr">{{ order.reference || t('purchasing.draft_ref', { id: order.id }) }}</span>
                        <span class="badge" :class="statusBadge(order.status)">{{ t('purchasing.status.' + order.status) }}</span>
                    </h1>
                    <p class="page-sub">
                        {{ order.supplier_name }}<span v-if="supplierRetired"> {{ t('purchasing.retired_suffix') }}</span>
                        · {{ nameOf(order.branch) }}
                    </p>
                </div>
                <div v-if="canWrite" class="flex flex-wrap gap-2">
                    <RouterLink v-if="order.is_editable" :to="{ name: 'dashboard.purchasing.orders.edit', params: { id: order.id } }" class="btn btn-ghost">
                        <Icon name="edit" :size="16" />{{ t('purchasing.edit_order') }}
                    </RouterLink>
                    <button v-if="canCancel" type="button" class="btn btn-ghost" :disabled="busy" @click="transition('cancel')">{{ t('purchasing.cancel_order') }}</button>
                    <button v-if="order.is_editable" type="button" class="btn btn-accent" :disabled="busy || !order.lines.length || supplierRetired" @click="transition('send')">{{ t('purchasing.send') }}</button>
                    <button v-if="order.can_close_short" type="button" class="btn btn-ghost" :disabled="busy" @click="closeErrors = {}; showClose = true">{{ t('purchasing.close_short') }}</button>
                    <RouterLink v-if="canInvoice" :to="{ name: 'dashboard.purchasing.invoices.create', query: { purchase_order_id: order.id } }" class="btn btn-ghost">{{ t('purchasing.record_invoice') }}</RouterLink>
                    <button v-if="order.is_open" type="button" class="btn btn-accent" :disabled="busy" @click="openReceive">{{ t('purchasing.receive') }}</button>
                </div>
            </div>
            <RouterLink v-if="canInvoice" :to="{ name: 'dashboard.purchasing.invoices', query: { purchase_order_id: order.id } }" class="text-sm underline" style="color:var(--muted)">{{ t('purchasing.view_invoices') }}</RouterLink>

            <div v-if="order.is_editable && supplierRetired" class="card p-3 text-sm" style="background:var(--amber-soft);color:var(--ink)">{{ t('purchasing.supplier_retired_note') }}</div>
            <div v-if="order.status === 'partially_received'" class="card p-3 text-sm" style="background:var(--amber-soft);color:var(--ink)">{{ t('purchasing.part_delivery_note') }}</div>
            <div v-if="order.closed_short" class="card p-3 text-sm" style="background:var(--gray-soft);color:var(--ink)">
                {{ t('purchasing.closed_short_note', { date: fmtDate(order.closed_short_at, locale), reason: t('purchasing.close_reasons.' + order.close_reason) }) }}
                <span v-if="order.close_note"> {{ order.close_note }}</span>
            </div>

            <div class="card p-5 grid grid-cols-2 sm:grid-cols-4 gap-4 text-sm">
                <div><div style="color:var(--muted)">{{ t('purchasing.created_on') }}</div><div style="color:var(--ink)">{{ fmtDate(order.created_at, locale) }}</div></div>
                <div><div style="color:var(--muted)">{{ t('purchasing.ordered_on') }}</div><div style="color:var(--ink)">{{ fmtDate(order.ordered_at, locale, { time: true }) || '—' }}</div></div>
                <div><div style="color:var(--muted)">{{ t('purchasing.expected_on') }}</div><div style="color:var(--ink)">{{ fmtDate(order.expected_at, locale) || '—' }}</div></div>
                <div><div style="color:var(--muted)">{{ t('purchasing.received_value') }}</div><div class="mono" dir="ltr" style="color:var(--ink)">{{ show(order.received_value_minor) }}</div></div>
                <div v-if="order.notes" class="col-span-2 sm:col-span-4"><div style="color:var(--muted)">{{ t('purchasing.notes') }}</div><div class="whitespace-pre-line" style="color:var(--body)">{{ order.notes }}</div></div>
            </div>

            <div class="card overflow-hidden">
                <div v-if="!order.lines.length" class="p-8 text-center text-sm" style="color:var(--muted)">{{ t('purchasing.no_lines_yet') }}</div>
                <div v-else class="overflow-x-auto">
                    <table class="w-full text-sm">
                        <thead>
                            <tr style="color:var(--muted)">
                                <th class="px-4 py-3 text-start font-medium">{{ t('purchasing.line_description') }}</th>
                                <th class="px-4 py-3 text-end font-medium">{{ t('purchasing.ordered') }}</th>
                                <th class="px-4 py-3 text-end font-medium">{{ t('purchasing.received') }}</th>
                                <th class="px-4 py-3 text-end font-medium">{{ order.closed_short ? t('purchasing.not_coming') : t('purchasing.outstanding') }}</th>
                                <th class="px-4 py-3 text-end font-medium">{{ t('purchasing.unit_cost') }}</th>
                                <th class="px-4 py-3 text-end font-medium">{{ t('purchasing.tax_rate') }}</th>
                                <th class="px-4 py-3 text-end font-medium">{{ t('purchasing.line_total') }}</th>
                            </tr>
                        </thead>
                        <tbody>
                            <tr v-for="l in order.lines" :key="l.id" class="border-t" style="border-color:var(--line)">
                                <td class="px-4 py-3" style="color:var(--ink)">
                                    <div class="font-medium">{{ l.description }}</div>
                                    <div class="text-xs" style="color:var(--muted)">
                                        <span v-if="l.sku" class="mono" dir="ltr">{{ l.sku }} · </span>
                                        <span v-if="!l.stock_item_id">{{ t('purchasing.not_counted') }}</span>
                                        <span v-else-if="l.stock_item && !l.stock_item.is_active">{{ nameOf(l.stock_item) }} {{ t('purchasing.retired_suffix') }}</span>
                                    </div>
                                </td>
                                <td class="px-4 py-3 text-end"><span class="mono" dir="ltr">{{ qty(l.ordered_milli, l.unit_code) }}</span></td>
                                <td class="px-4 py-3 text-end">
                                    <span class="mono" dir="ltr">{{ qty(l.received_milli, l.unit_code) }}</span>
                                    <div v-if="l.received_milli > l.ordered_milli" class="text-xs" style="color:var(--amber)">{{ t('purchasing.over_received') }}</div>
                                </td>
                                <td class="px-4 py-3 text-end"><span class="mono" dir="ltr">{{ qty(order.closed_short ? l.not_coming_milli : l.outstanding_milli, l.unit_code) }}</span></td>
                                <td class="px-4 py-3 text-end"><span class="mono" dir="ltr">{{ show(l.unit_cost_minor) }}</span></td>
                                <td class="px-4 py-3 text-end"><span class="mono" dir="ltr">{{ bpToPercent(l.tax_rate_bp) }}%</span></td>
                                <td class="px-4 py-3 text-end"><span class="mono" dir="ltr">{{ show(l.line_total_minor) }}</span></td>
                            </tr>
                        </tbody>
                    </table>
                </div>
                <div class="border-t px-4 py-3 space-y-1 text-sm" style="border-color:var(--line)">
                    <div class="flex justify-between gap-3"><span style="color:var(--muted)">{{ t('purchasing.subtotal') }}</span><span class="mono" dir="ltr">{{ show(order.totals.subtotal_minor) }}</span></div>
                    <div class="flex justify-between gap-3"><span style="color:var(--muted)">{{ t('purchasing.tax') }}</span><span class="mono" dir="ltr">{{ show(order.totals.tax_minor) }}</span></div>
                    <div class="flex justify-between gap-3 font-semibold" style="color:var(--ink)"><span>{{ t('purchasing.total') }}</span><span class="mono" dir="ltr">{{ show(order.totals.total_minor) }}</span></div>
                </div>
            </div>
            <p v-if="order.is_open" class="text-xs" style="color:var(--muted)">{{ t('purchasing.cost_from_order') }}</p>
        </template>

        <ReasonDialog
            v-if="showClose"
            :title="t('purchasing.close_short_title')"
            :subtitle="order?.reference || ''"
            :message="t('purchasing.close_short_message')"
            :reasons="CLOSE_REASONS"
            label-prefix="purchasing.close_reasons"
            :confirm-text="t('purchasing.close_short')"
            :busy="busy"
            :errors="closeErrors"
            @submit="submitClose"
            @close="showClose = false"
        />

        <Dialog v-if="showReceive" :title="t('purchasing.receive_title')" :subtitle="order?.reference || ''" @close="showReceive = false">
            <form class="space-y-4" @submit.prevent="submitReceive">
                <p class="text-sm" style="color:var(--muted)">{{ t('purchasing.receive_hint') }}</p>
                <FormError :errors="recvErrors" field="lines" />
                <div class="space-y-3">
                    <div v-for="(l, i) in recv.lines" :key="l.id" class="grid grid-cols-1 sm:grid-cols-[1fr_9rem] gap-2 items-start border-t pt-3 first:border-t-0 first:pt-0" style="border-color:var(--line)">
                        <div>
                            <div class="font-medium text-sm" style="color:var(--ink)">{{ l.description }}</div>
                            <div class="text-xs" style="color:var(--muted)">
                                {{ t('purchasing.ordered') }} <span class="mono" dir="ltr">{{ qty(l.ordered, l.unit_code) }}</span>
                                · {{ t('purchasing.received') }} <span class="mono" dir="ltr">{{ qty(l.got, l.unit_code) }}</span>
                                <span v-if="!l.stock_item_id"> · {{ t('purchasing.not_counted') }}</span>
                            </div>
                        </div>
                        <label class="block">
                            <span class="sr-only">{{ t('purchasing.quantity') }}</span>
                            <div class="flex items-center gap-2" dir="ltr">
                                <input v-model="l.quantity" class="input mono" inputmode="decimal" data-en-digits placeholder="0" autocomplete="off" />
                                <span class="mono text-xs" style="color:var(--muted)">{{ l.unit_code }}</span>
                            </div>
                            <FormError :errors="recvErrors" :field="`lines.${i}.quantity_milli`" />
                        </label>
                    </div>
                </div>
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                    <label class="block"><span class="label">{{ t('purchasing.occurred_at') }}</span>
                        <input v-model="recv.occurred_at" type="datetime-local" class="input" dir="ltr" />
                        <FormError :errors="recvErrors" field="occurred_at" /></label>
                    <label class="block"><span class="label">{{ t('purchasing.receive_note') }}</span>
                        <input v-model="recv.note" class="input" maxlength="1000" />
                        <FormError :errors="recvErrors" field="note" /></label>
                </div>
                <div class="flex justify-end gap-2 pt-2">
                    <button type="button" class="btn btn-ghost" :disabled="busy" @click="showReceive = false">{{ t('common.cancel') }}</button>
                    <button type="submit" class="btn btn-accent" :disabled="busy">
                        <Icon v-if="busy" name="loading" :size="16" class="animate-spin" />
                        {{ t('purchasing.book_in') }}
                    </button>
                </div>
            </form>
        </Dialog>
    </div>
</template>
