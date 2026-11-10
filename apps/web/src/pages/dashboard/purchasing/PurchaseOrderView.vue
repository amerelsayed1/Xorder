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
        <button type="button" class="back" @click="router.push({ name: 'dashboard.purchasing.orders' })">
            <Icon name="chevronDown" :size="16" class="rotate-90 rtl:-rotate-90" />{{ t('purchasing.orders_title') }}
        </button>

        <ErrorState v-if="failed" :message="t('common.error')" @retry="load" />

        <div v-else-if="loading || !order" class="space-y-5">
            <div class="card p-5 space-y-3">
                <Skeleton w="40%" h="28px" /><Skeleton w="60%" h="14px" />
                <Skeleton w="100%" h="56px" />
            </div>
            <Skeleton w="100%" h="220px" rounded="15px" />
        </div>

        <template v-else>
            <!-- Document header: number, status, parties, dates, and the actions the status allows -->
            <header class="card doc-head">
                <div class="flex flex-wrap items-start justify-between gap-4">
                    <div class="min-w-0 space-y-1.5">
                        <h1 class="page-title doc-title flex flex-wrap items-center gap-x-3 gap-y-2">
                            <span class="mono" dir="ltr">{{ order.reference || t('purchasing.draft_ref', { id: order.id }) }}</span>
                            <span class="badge" :class="statusBadge(order.status)">{{ t('purchasing.status.' + order.status) }}</span>
                        </h1>
                        <p class="doc-sub">
                            {{ order.supplier_name }}<span v-if="supplierRetired"> {{ t('purchasing.retired_suffix') }}</span>
                            · {{ nameOf(order.branch) }}
                        </p>
                    </div>
                    <div v-if="canWrite" class="actions">
                        <RouterLink v-if="order.is_editable" :to="{ name: 'dashboard.purchasing.orders.edit', params: { id: order.id } }" class="btn btn-ghost">
                            <Icon name="edit" :size="16" />{{ t('purchasing.edit_order') }}
                        </RouterLink>
                        <RouterLink v-if="canInvoice" :to="{ name: 'dashboard.purchasing.invoices.create', query: { purchase_order_id: order.id } }" class="btn btn-ghost">{{ t('purchasing.record_invoice') }}</RouterLink>
                        <button v-if="order.can_close_short" type="button" class="btn btn-ghost" :disabled="busy" @click="closeErrors = {}; showClose = true">{{ t('purchasing.close_short') }}</button>
                        <button v-if="order.is_editable" type="button" class="btn btn-accent" :disabled="busy || !order.lines.length || supplierRetired" @click="transition('send')">{{ t('purchasing.send') }}</button>
                        <button v-if="order.is_open" type="button" class="btn btn-accent" :disabled="busy" @click="openReceive">{{ t('purchasing.receive') }}</button>
                        <div v-if="canCancel" class="actions-danger">
                            <button type="button" class="btn btn-danger" :disabled="busy" @click="transition('cancel')">{{ t('purchasing.cancel_order') }}</button>
                        </div>
                    </div>
                </div>

                <dl class="doc-meta">
                    <div><dt>{{ t('purchasing.created_on') }}</dt><dd>{{ fmtDate(order.created_at, locale) }}</dd></div>
                    <div><dt>{{ t('purchasing.ordered_on') }}</dt><dd>{{ fmtDate(order.ordered_at, locale, { time: true }) || '—' }}</dd></div>
                    <div><dt>{{ t('purchasing.expected_on') }}</dt><dd>{{ fmtDate(order.expected_at, locale) || '—' }}</dd></div>
                    <div><dt>{{ t('purchasing.received_value') }}</dt><dd class="mono"><span>{{ show(order.received_value_minor) }}</span></dd></div>
                    <div v-if="order.notes" class="span-all"><dt>{{ t('purchasing.notes') }}</dt><dd class="meta-note">{{ order.notes }}</dd></div>
                </dl>
            </header>

            <div v-if="order.is_editable && supplierRetired" class="note note-amber" role="status"><i class="pi pi-exclamation-triangle" aria-hidden="true" /><span>{{ t('purchasing.supplier_retired_note') }}</span></div>
            <div v-if="order.status === 'partially_received'" class="note note-amber" role="status"><i class="pi pi-clock" aria-hidden="true" /><span>{{ t('purchasing.part_delivery_note') }}</span></div>
            <div v-if="order.closed_short" class="note note-gray" role="status">
                <i class="pi pi-info-circle" aria-hidden="true" />
                <span>
                    {{ t('purchasing.closed_short_note', { date: fmtDate(order.closed_short_at, locale), reason: t('purchasing.close_reasons.' + order.close_reason) }) }}
                    <span v-if="order.close_note"> {{ order.close_note }}</span>
                </span>
            </div>

            <!-- Line items, then the totals block -->
            <section class="card overflow-hidden">
                <div v-if="!order.lines.length" class="empty">
                    <div class="empty-ico"><i class="pi pi-list" aria-hidden="true" /></div>
                    <p class="empty-text">{{ t('purchasing.no_lines_yet') }}</p>
                </div>
                <div v-else class="dtable-wrap">
                    <table class="dtable">
                        <thead>
                            <tr>
                                <th>{{ t('purchasing.line_description') }}</th>
                                <th class="num">{{ t('purchasing.ordered') }}</th>
                                <th class="num">{{ t('purchasing.received') }}</th>
                                <th class="num">{{ order.closed_short ? t('purchasing.not_coming') : t('purchasing.outstanding') }}</th>
                                <th class="num">{{ t('purchasing.unit_cost') }}</th>
                                <th class="num">{{ t('purchasing.tax_rate') }}</th>
                                <th class="num">{{ t('purchasing.line_total') }}</th>
                            </tr>
                        </thead>
                        <tbody>
                            <tr v-for="l in order.lines" :key="l.id">
                                <td>
                                    <div class="primary">{{ l.description }}</div>
                                    <div class="sub">
                                        <span v-if="l.sku" class="mono" dir="ltr">{{ l.sku }} · </span>
                                        <span v-if="!l.stock_item_id">{{ t('purchasing.not_counted') }}</span>
                                        <span v-else-if="l.stock_item && !l.stock_item.is_active">{{ nameOf(l.stock_item) }} {{ t('purchasing.retired_suffix') }}</span>
                                    </div>
                                </td>
                                <td class="num"><span class="mono" dir="ltr">{{ qty(l.ordered_milli, l.unit_code) }}</span></td>
                                <td class="num">
                                    <span class="mono" dir="ltr">{{ qty(l.received_milli, l.unit_code) }}</span>
                                    <div v-if="l.received_milli > l.ordered_milli" class="over">{{ t('purchasing.over_received') }}</div>
                                </td>
                                <td class="num"><span class="mono" dir="ltr">{{ qty(order.closed_short ? l.not_coming_milli : l.outstanding_milli, l.unit_code) }}</span></td>
                                <td class="num"><span class="mono">{{ show(l.unit_cost_minor) }}</span></td>
                                <td class="num"><span class="mono" dir="ltr">{{ bpToPercent(l.tax_rate_bp) }}%</span></td>
                                <td class="num strong"><span class="mono">{{ show(l.line_total_minor) }}</span></td>
                            </tr>
                        </tbody>
                    </table>
                </div>
                <div class="totals-wrap">
                    <div class="totals">
                        <div class="totals-row"><span>{{ t('purchasing.subtotal') }}</span><span class="mono">{{ show(order.totals.subtotal_minor) }}</span></div>
                        <div class="totals-row"><span>{{ t('purchasing.tax') }}</span><span class="mono">{{ show(order.totals.tax_minor) }}</span></div>
                        <div class="totals-row totals-grand"><span>{{ t('purchasing.total') }}</span><span class="mono">{{ show(order.totals.total_minor) }}</span></div>
                    </div>
                </div>
            </section>

            <div class="flex flex-wrap items-center justify-between gap-3">
                <p v-if="order.is_open" class="text-sm" style="color:var(--body)">{{ t('purchasing.cost_from_order') }}</p>
                <RouterLink v-if="canInvoice" :to="{ name: 'dashboard.purchasing.invoices', query: { purchase_order_id: order.id } }" class="list-link">{{ t('purchasing.view_invoices') }}</RouterLink>
            </div>
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
                <p class="text-sm" style="color:var(--body)">{{ t('purchasing.receive_hint') }}</p>
                <FormError :errors="recvErrors" field="lines" />
                <div class="space-y-3">
                    <div v-for="(l, i) in recv.lines" :key="l.id" class="grid grid-cols-1 sm:grid-cols-[1fr_9rem] gap-2 items-start border-t pt-3 first:border-t-0 first:pt-0" style="border-color:var(--line)">
                        <div>
                            <div class="font-medium text-sm" style="color:var(--ink)">{{ l.description }}</div>
                            <div class="text-xs" style="color:var(--body)">
                                {{ t('purchasing.ordered') }} <span class="mono" dir="ltr">{{ qty(l.ordered, l.unit_code) }}</span>
                                · {{ t('purchasing.received') }} <span class="mono" dir="ltr">{{ qty(l.got, l.unit_code) }}</span>
                                <span v-if="!l.stock_item_id"> · {{ t('purchasing.not_counted') }}</span>
                            </div>
                        </div>
                        <label class="block">
                            <span class="sr-only">{{ t('purchasing.quantity') }}</span>
                            <div class="flex items-center gap-2" dir="ltr">
                                <input v-model="l.quantity" class="input mono" inputmode="decimal" data-en-digits placeholder="0" autocomplete="off" />
                                <span class="mono text-xs" style="color:var(--body)">{{ l.unit_code }}</span>
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

<style scoped>
/* Presentation only: theme variables and the PrimeVue primary scale; no new hex values. */
.back { display: inline-flex; align-items: center; gap: 6px; min-height: 36px; font-size: 14.5px; font-weight: 500; color: var(--body); }
.back:hover { color: var(--p-primary-700); }
.badge-amber { color: var(--p-primary-800); }
.badge-gray { color: var(--body); }
.badge-red { color: var(--red); }
.doc-head { padding: 20px; }
.doc-title { font-family: var(--font-display); font-weight: 700; font-size: 26px; line-height: 1.2; color: var(--ink); }
.doc-sub { font-size: 15px; color: var(--body); }
.doc-sub a { color: var(--p-primary-700); font-weight: 500; }
.doc-sub a:hover { text-decoration: underline; }
.doc-meta { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 16px 20px; margin: 18px 0 0; padding-top: 18px; border-top: 1px solid var(--line); }
@media (min-width: 640px) { .doc-meta { grid-template-columns: repeat(4, minmax(0, 1fr)); } }
.doc-meta dt { font-size: 13.5px; color: var(--body); }
.doc-meta dd { margin: 2px 0 0; font-size: 15px; font-weight: 500; color: var(--ink); overflow-wrap: anywhere; }
.doc-meta .span-all { grid-column: 1 / -1; }
.doc-meta .span-2 { grid-column: span 2 / span 2; }
.doc-meta .meta-note { font-weight: 400; color: var(--body); white-space: pre-line; }
.actions { display: flex; flex-wrap: wrap; align-items: center; gap: 8px; }
.actions .btn { min-height: 44px; }
.actions-danger { margin-inline-start: 4px; padding-inline-start: 12px; border-inline-start: 1px solid var(--line); }
.actions-danger:first-child { margin: 0; padding: 0; border: 0; }
.btn-danger { background: var(--card); color: var(--red); border-color: var(--line); }
.btn-danger:hover:not(:disabled) { border-color: var(--red); background: var(--red-soft); }
@media (max-width: 639px) { .actions { width: 100%; } .actions > .btn { flex: 1 1 auto; justify-content: center; } }
.note { display: flex; align-items: flex-start; gap: 10px; padding: 12px 14px; border-radius: 12px; font-size: 14.5px; line-height: 1.5; }
.note > i { margin-top: 3px; flex: none; }
.note-amber { background: var(--amber-soft); color: var(--p-primary-800); }
.note-gray { background: var(--gray-soft); color: var(--ink); }
.dtable-wrap { overflow-x: auto; }
.dtable { width: 100%; min-width: 640px; border-collapse: collapse; font-size: 15px; }
.dtable th { padding: 12px 16px; font-size: 13px; font-weight: 600; color: var(--body); background: var(--page); text-align: start; white-space: nowrap; }
.dtable td { padding: 14px 16px; border-top: 1px solid var(--line); color: var(--body); vertical-align: middle; }
.dtable .num { text-align: end; white-space: nowrap; }
.dtable td.num { color: var(--ink); }
.dtable .strong { font-weight: 600; color: var(--ink); }
.dtable .primary { color: var(--ink); font-weight: 500; }
.dtable .nowrap { white-space: nowrap; }
.dtable tbody tr.row-link { cursor: pointer; transition: background .15s; }
.dtable tbody tr.row-link:hover { background: var(--page); }
.dtable tbody tr.row-link:focus-visible { outline: 2px solid var(--accent); outline-offset: -2px; }
.dtable .sub { display: block; margin-top: 2px; font-size: 13px; color: var(--body); }
.totals-wrap { display: flex; justify-content: flex-end; padding: 16px 20px 20px; border-top: 1px solid var(--line); background: var(--page); }
.totals { width: 100%; max-width: 340px; }
.totals-row { display: flex; justify-content: space-between; gap: 12px; padding: 5px 0; font-size: 15px; color: var(--body); }
.totals-row .mono { color: var(--ink); }
.totals-grand { align-items: baseline; margin-top: 8px; padding-top: 12px; border-top: 1px solid var(--line); font-family: var(--font-display); font-weight: 700; font-size: 17px; color: var(--ink); }
.totals-grand .mono { font-size: 26px; line-height: 1.1; }
.empty { padding: 40px 20px; text-align: center; }
.empty-ico { width: 48px; height: 48px; margin: 0 auto 12px; border-radius: 50%; display: grid; place-items: center; background: var(--accent-soft); color: var(--p-primary-700); font-size: 20px; }
.empty-text { margin-top: 4px; font-size: 14.5px; color: var(--body); }
.list-link { font-size: 14.5px; font-weight: 500; color: var(--p-primary-700); }
.list-link:hover { text-decoration: underline; }
.over { margin-top: 2px; font-size: 13px; font-weight: 600; color: var(--p-primary-800); }
</style>
