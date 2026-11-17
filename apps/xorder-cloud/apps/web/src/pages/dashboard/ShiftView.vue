<script setup>
import { ref, computed, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute, useRouter } from 'vue-router'
import api from '@xorder/api-client/api.js'
import { useAuth } from '@xorder/api-client/auth.js'
import { withMinDuration } from '../../lib/minLoading.js'
import { currencyExponent, amountToMinor } from '../../lib/money.js'
import { pickLocalized } from '@xorder/ui/localize.js'
import { toEnDigits } from '@xorder/ui/enDigits.js'
import Skeleton from '@xorder/ui/Skeleton.vue'
import ErrorState from '@xorder/ui/ErrorState.vue'
import Icon from '@xorder/ui/Icon.vue'
import Dialog from '@xorder/ui/Dialog.vue'
import FormError from '@xorder/ui/FormError.vue'
import { alert } from '@xorder/ui/alert.js'
import { toast } from '@xorder/ui/toast.js'
import { fmtDate, money } from './purchasing/format.js'

// dashboard-shift-details. One till shift as the back office sees it: the
// same figures the till's report key prints (the server computes them), its
// orders and cash movements. A shift whose till was revoked before closing
// it can be force-closed here with a count and a reason; the server
// re-checks both conditions under a lock on the shift row.
const { t, locale } = useI18n()
const route = useRoute()
const router = useRouter()
const auth = useAuth()
const canClose = computed(() => auth.can('pos.shift_close') && !auth.isReadOnly)
const canOrders = computed(() => auth.can('orders.view'))

const shift = ref(null)
const loading = ref(true)
const failed = ref(false)

async function load() {
    loading.value = true
    failed.value = false
    try {
        const { data } = await withMinDuration(api.get(`api/dashboard/pos/shifts/${route.params.id}`))
        shift.value = data.data
    } catch {
        failed.value = true
    } finally {
        loading.value = false
    }
}
onMounted(load)

const currency = computed(() => auth.restaurant?.currency)
const exponent = computed(() => currencyExponent(currency.value))
const show = (minor) => money(minor, exponent.value, currency.value, locale.value)
const when = (iso) => fmtDate(iso, locale.value, { time: true })
const branchName = computed(() => pickLocalized(shift.value?.branch, 'name', locale.value) || shift.value?.branch?.name_en || '')
const summary = computed(() => shift.value?.summary || {})
const isOpen = computed(() => shift.value?.status === 'open')
const variance = computed(() => shift.value?.variance_minor ?? null)

// --- Force close -------------------------------------------------------------
const showClose = ref(false)
const counted = ref('')
const reason = ref('')
const errors = ref({})
const busy = ref(false)

function openClose() {
    counted.value = ''
    reason.value = ''
    errors.value = {}
    showClose.value = true
}

// A count copied from the page ("4,995.00") or typed with grouping ("4 995",
// Arabic "٤٬٩٩٥") is a normal way to write cash. Drop the grouping before
// parsing: a comma is grouping when a point is also there, or when every
// comma is followed by exactly three digits ("4,995"); otherwise a lone comma
// stays the decimal separator ("12,50"), as amountToMinor reads it.
function cleanAmount(raw) {
    let s = toEnDigits(String(raw ?? '')).replace(/[\s٬ ]/g, '').replace(/٫/g, '.')
    if (s.includes('.') || /^\d{1,3}(,\d{3})+$/.test(s)) s = s.replace(/,/g, '')
    return s
}

async function submitClose() {
    const e = {}
    const amount = cleanAmount(counted.value)
    const minor = amount === '' ? null : amountToMinor(amount, exponent.value)
    if (minor === null || Number.isNaN(minor) || minor < 0) e.counted_cash_minor = [t('shift.counted_required')]
    if (reason.value.trim().length < 3) e.reason = [t('shift.reason_required')]
    errors.value = e
    if (Object.keys(e).length) return

    busy.value = true
    try {
        const { data } = await api.post(`api/dashboard/pos/shifts/${shift.value.id}/force-close`, {
            counted_cash_minor: minor,
            reason: reason.value.trim(),
        })
        shift.value = data.data
        showClose.value = false
        toast(data.message)
    } catch (err) {
        errors.value = err.response?.data?.errors || {}
        if (!Object.keys(errors.value).length) {
            // Closed or un-revoked meanwhile: say so and show the current state.
            showClose.value = false
            alert(err.response?.data?.message || t('common.error'))
            load()
        }
    } finally {
        busy.value = false
    }
}
</script>

<template>
    <div class="space-y-5">
        <button type="button" class="back" @click="router.push({ name: 'dashboard.home' })">
            <Icon name="chevronDown" :size="16" class="rotate-90 rtl:-rotate-90" />{{ t('shift.back') }}
        </button>

        <ErrorState v-if="failed" :message="t('common.error')" @retry="load" />

        <div v-else-if="loading || !shift" class="space-y-5">
            <div class="card p-5 space-y-3">
                <Skeleton w="40%" h="28px" /><Skeleton w="60%" h="14px" />
                <Skeleton w="100%" h="56px" />
            </div>
            <Skeleton w="100%" h="220px" rounded="15px" />
        </div>

        <template v-else>
            <header class="card doc-head">
                <div class="flex flex-wrap items-start justify-between gap-4">
                    <div class="min-w-0 space-y-1.5">
                        <h1 class="page-title doc-title flex flex-wrap items-center gap-x-3 gap-y-2">
                            <span>{{ t('shift.title') }}</span>
                            <span class="mono" dir="ltr">#{{ shift.id }}</span>
                            <span class="badge" :class="isOpen ? 'badge-green' : 'badge-gray'">{{ isOpen ? t('shift.status_open') : t('shift.status_closed') }}</span>
                        </h1>
                        <p class="doc-sub">
                            {{ shift.terminal?.name || t('shift.unknown') }}<span v-if="shift.terminal?.revoked" class="revoked"> ({{ t('shift.till_revoked') }})</span>
                            <span v-if="branchName"> · {{ branchName }}</span>
                        </p>
                    </div>
                    <div v-if="canClose && shift.can_force_close" class="actions">
                        <button type="button" class="btn btn-danger" @click="openClose">{{ t('shift.force_close') }}</button>
                    </div>
                </div>

                <dl class="doc-meta">
                    <div><dt>{{ t('shift.opened') }}</dt><dd>{{ when(shift.opened_at) }}</dd></div>
                    <div><dt>{{ t('shift.opened_by') }}</dt><dd>{{ shift.opened_by || t('shift.unknown') }}</dd></div>
                    <template v-if="!isOpen">
                        <div><dt>{{ t('shift.closed') }}</dt><dd>{{ when(shift.closed_at) }}</dd></div>
                        <div><dt>{{ t('shift.closed_by') }}</dt><dd>{{ shift.closed_by || t('shift.unknown') }}</dd></div>
                    </template>
                </dl>
            </header>

            <div v-if="shift.can_force_close" class="note note-amber" role="status">
                <i class="pi pi-exclamation-triangle" aria-hidden="true" /><span>{{ t('shift.revoked_note') }}</span>
            </div>
            <div v-else-if="shift.closed_via === 'dashboard'" class="note note-gray" role="status">
                <i class="pi pi-info-circle" aria-hidden="true" /><span>{{ t('shift.closed_via_dashboard') }}</span>
            </div>

            <!-- The drawer: how expected cash is made up, then the count. -->
            <section class="card kv-card">
                <h2 class="h-card mb-2">{{ t('shift.money') }}</h2>
                <div class="kv-row"><span>{{ t('shift.sales') }}</span><span class="mono">{{ show(summary.sales_minor) }}</span></div>
                <div class="kv-row"><span>{{ t('shift.orders') }}</span><span class="mono">{{ summary.orders_count ?? 0 }}</span></div>
                <div class="kv-row"><span>{{ t('shift.opening_float') }}</span><span class="mono">{{ show(shift.opening_float_minor) }}</span></div>
                <div class="kv-row"><span>{{ t('shift.cash_in') }}</span><span class="mono">{{ show(summary.cash_in_minor) }}</span></div>
                <div class="kv-row"><span>{{ t('shift.cash_out') }}</span><span class="mono">{{ show(summary.cash_out_minor) }}</span></div>
                <div class="kv-row"><span>{{ t('shift.refunds') }}</span><span class="mono">{{ show(summary.refunds_minor) }}</span></div>
                <div class="kv-row"><span>{{ t('shift.cash_refunds') }}</span><span class="mono">{{ show(summary.cash_refunds_minor) }}</span></div>
                <div class="kv-row kv-strong"><span>{{ t('shift.expected_cash') }}</span><span class="mono">{{ show(shift.expected_cash_minor) }}</span></div>
                <template v-if="!isOpen && shift.counted_cash_minor !== null">
                    <div class="kv-row"><span>{{ t('shift.counted_cash') }}</span><span class="mono">{{ show(shift.counted_cash_minor) }}</span></div>
                    <div class="kv-row kv-strong">
                        <span>{{ t('shift.variance') }}</span>
                        <span class="mono" :class="variance === 0 ? 'tone-green' : 'tone-warn'" dir="ltr">{{ variance > 0 ? '+' : '' }}{{ show(variance) }}</span>
                    </div>
                    <div v-if="shift.variance_reason" class="kv-row"><span>{{ t('shift.reason') }}</span><span class="reason-text">{{ shift.variance_reason }}</span></div>
                </template>
            </section>

            <section class="card overflow-hidden">
                <h2 class="section-title">{{ t('shift.by_tender') }}</h2>
                <p v-if="!summary.sales_by_tender?.length" class="px-5 pb-5 text-sm" style="color:var(--body)">{{ t('shift.no_orders') }}</p>
                <ul v-else>
                    <li v-for="row in summary.sales_by_tender" :key="row.tender_type_id ?? 'none'" class="line-row">
                        <span class="primary">{{ row.name || t('shift.no_tender') }}</span>
                        <span>{{ t('shift.payments_n', { n: row.payments }) }}</span>
                        <span class="line-amount mono">{{ show(row.amount_minor) }}</span>
                    </li>
                </ul>
            </section>

            <section class="card overflow-hidden">
                <h2 class="section-title">{{ t('shift.orders') }}</h2>
                <p v-if="!shift.orders.length" class="px-5 pb-5 text-sm" style="color:var(--body)">{{ t('shift.no_orders') }}</p>
                <ul v-else>
                    <li v-for="o in shift.orders" :key="o.id" class="line-row">
                        <RouterLink v-if="canOrders" :to="{ name: 'dashboard.orders', query: { order: o.id } }" class="mono" dir="ltr">{{ o.invoice_number || o.code }}</RouterLink>
                        <span v-else class="mono" dir="ltr">{{ o.invoice_number || o.code }}</span>
                        <span>{{ when(o.created_at) }}</span>
                        <span class="badge badge-gray">{{ t('orders.status.' + o.status) }}</span>
                        <span class="line-amount mono">{{ show(o.total_minor) }}</span>
                    </li>
                </ul>
            </section>

            <section class="card overflow-hidden">
                <h2 class="section-title">{{ t('shift.movements') }}</h2>
                <p v-if="!shift.cash_movements.length" class="px-5 pb-5 text-sm" style="color:var(--body)">{{ t('shift.no_movements') }}</p>
                <ul v-else>
                    <li v-for="m in shift.cash_movements" :key="m.id" class="line-row">
                        <span class="badge" :class="m.direction === 'in' ? 'badge-green' : 'badge-gray'">{{ m.direction === 'in' ? t('shift.direction_in') : t('shift.direction_out') }}</span>
                        <span>{{ when(m.occurred_at) }}</span>
                        <span v-if="m.reason">{{ m.reason }}</span>
                        <span class="line-amount mono">{{ show(m.amount_minor) }}</span>
                    </li>
                </ul>
            </section>
        </template>

        <Dialog v-if="showClose" :title="t('shift.force_close_title')" :subtitle="shift?.terminal?.name || ''" @close="showClose = false">
            <form class="space-y-4" @submit.prevent="submitClose">
                <p class="text-sm" style="color:var(--body)">{{ t('shift.force_close_message') }}</p>
                <p class="text-sm">{{ t('shift.expected_cash') }}: <span class="mono" style="color:var(--ink);font-weight:600">{{ show(shift.expected_cash_minor) }}</span></p>
                <label class="block">
                    <span class="label">{{ t('shift.counted_label') }}</span>
                    <input v-model="counted" type="text" inputmode="decimal" dir="ltr" class="input mono" autocomplete="off" />
                    <FormError :errors="errors" field="counted_cash_minor" />
                </label>
                <label class="block">
                    <span class="label">{{ t('shift.reason_label') }}</span>
                    <textarea v-model="reason" class="input" rows="2" maxlength="500" :placeholder="t('shift.reason_placeholder')"></textarea>
                    <FormError :errors="errors" field="reason" />
                </label>
                <div class="dialog-actions">
                    <button type="button" class="btn btn-ghost" :disabled="busy" @click="showClose = false">{{ t('common.cancel') }}</button>
                    <button type="submit" class="btn btn-accent" :disabled="busy">
                        <Icon v-if="busy" name="loading" :size="16" class="animate-spin" />
                        {{ t('shift.force_close') }}
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
.badge-green { color: var(--green); background: var(--green-soft); }
.badge-gray { color: var(--body); }
.doc-head { padding: 20px; }
.doc-title { font-family: var(--font-display); font-weight: 700; font-size: 26px; line-height: 1.2; color: var(--ink); }
.doc-sub { font-size: 15px; color: var(--body); }
.revoked { color: var(--red); }
.doc-meta { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 16px 20px; margin: 18px 0 0; padding-top: 18px; border-top: 1px solid var(--line); }
@media (min-width: 640px) { .doc-meta { grid-template-columns: repeat(4, minmax(0, 1fr)); } }
.doc-meta dt { font-size: 13.5px; color: var(--body); }
.doc-meta dd { margin: 2px 0 0; font-size: 15px; font-weight: 500; color: var(--ink); overflow-wrap: anywhere; }
.actions { display: flex; flex-wrap: wrap; align-items: center; gap: 8px; }
.actions .btn { min-height: 44px; }
.btn-danger { background: var(--card); color: var(--red); border-color: var(--line); }
.btn-danger:hover:not(:disabled) { border-color: var(--red); background: var(--red-soft); }
@media (max-width: 639px) { .actions { width: 100%; } .actions > .btn { flex: 1 1 auto; justify-content: center; } }
.note { display: flex; align-items: flex-start; gap: 10px; padding: 12px 14px; border-radius: 12px; font-size: 14.5px; line-height: 1.5; }
.note > i { margin-top: 3px; flex: none; }
.note-amber { background: var(--amber-soft); color: var(--p-primary-800); }
.note-gray { background: var(--gray-soft); color: var(--ink); }
.kv-card { padding: 20px; }
.kv-row { display: flex; justify-content: space-between; gap: 12px; padding: 7px 0; font-size: 15px; color: var(--body); }
.kv-row + .kv-row { border-top: 1px solid var(--line); }
.kv-row .mono { color: var(--ink); font-weight: 600; }
.kv-strong > span:first-child { color: var(--ink); font-weight: 600; }
.reason-text { color: var(--ink); text-align: end; overflow-wrap: anywhere; }
.tone-green { color: var(--green) !important; }
.tone-warn { color: var(--p-primary-800) !important; }
.section-title { padding: 16px 20px 8px; font-family: var(--font-display); font-weight: 600; font-size: 16.5px; color: var(--ink); }
.line-row { display: flex; flex-wrap: wrap; align-items: center; gap: 6px 14px; min-height: 52px; padding: 10px 20px; border-top: 1px solid var(--line); font-size: 15px; color: var(--body); }
.line-row a { color: var(--p-primary-700); font-weight: 500; }
.line-row a:hover { text-decoration: underline; }
.line-row .primary { color: var(--ink); font-weight: 500; }
.line-amount { margin-inline-start: auto; font-weight: 600; color: var(--ink); }
.dialog-actions { display: flex; justify-content: flex-end; gap: 8px; padding-top: 8px; }
.dialog-actions .btn { min-height: 44px; }
</style>
