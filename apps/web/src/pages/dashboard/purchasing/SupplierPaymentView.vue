<script setup>
import { ref, computed, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute, useRouter } from 'vue-router'
import api from '@xorder/api-client/api.js'
import { useAuth } from '@xorder/api-client/auth.js'
import { withMinDuration } from '../../../lib/minLoading.js'
import { pickLocalized } from '@xorder/ui/localize.js'
import Skeleton from '@xorder/ui/Skeleton.vue'
import ErrorState from '@xorder/ui/ErrorState.vue'
import Icon from '@xorder/ui/Icon.vue'
import { alert } from '@xorder/ui/alert.js'
import ReasonDialog from './ReasonDialog.vue'
import { PAYMENT_VOID_REASONS, fmtDay, fmtDate, money } from './format.js'

// CB-09 slice c. One supplier payment: where it went (invoices), what stayed
// on account, and the till pay-out it came out of, if any. Voiding keeps it on
// record and gives back whatever it paid on each invoice.
const { t, locale } = useI18n()
const route = useRoute()
const router = useRouter()
const auth = useAuth()
const canWrite = computed(() => auth.can('purchase.manage') && !auth.isReadOnly)

const payment = ref(null)
const loading = ref(true)
const failed = ref(false)
const busy = ref(false)
const showVoid = ref(false)
const voidErrors = ref({})

async function load() {
    loading.value = true
    failed.value = false
    try {
        const { data } = await withMinDuration(api.get(`api/dashboard/supplier-payments/${route.params.id}`))
        payment.value = data.data
    } catch {
        failed.value = true
    } finally {
        loading.value = false
    }
}
onMounted(load)

const nameOf = (s) => (s ? (pickLocalized(s, 'name', locale.value) || s.name_en || s.name_ar || `#${s.id}`) : '')
const show = (minor) => money(minor, payment.value?.exponent, payment.value?.currency, locale.value)

async function submitVoid({ reason, note }) {
    busy.value = true
    voidErrors.value = {}
    try {
        const { data } = await api.post(`api/dashboard/supplier-payments/${payment.value.id}/void`, { reason, note })
        payment.value = data.data
        showVoid.value = false
    } catch (err) {
        voidErrors.value = err.response?.data?.errors || {}
        if (err.response?.status === 409) { showVoid.value = false; alert(err.response.data.message); load() }
        else if (!Object.keys(voidErrors.value).length) alert(err.response?.data?.message || t('common.error'))
    } finally {
        busy.value = false
    }
}
</script>

<template>
    <div class="space-y-5">
        <button type="button" class="flex items-center gap-1.5 text-sm" style="color:var(--muted)" @click="router.push({ name: 'dashboard.purchasing.payments' })">
            <Icon name="chevronDown" :size="16" class="rotate-90 rtl:-rotate-90" />{{ t('purchasing.payments_title') }}
        </button>

        <ErrorState v-if="failed" :message="t('common.error')" @retry="load" />

        <div v-else-if="loading || !payment" class="card p-5 space-y-3">
            <Skeleton w="40%" h="22px" /><Skeleton w="60%" h="14px" /><Skeleton w="100%" h="120px" />
        </div>

        <template v-else>
            <div class="flex flex-wrap items-start justify-between gap-3">
                <div class="space-y-1">
                    <h1 class="page-title flex flex-wrap items-center gap-2">
                        <span>{{ t('purchasing.payment_ref', { id: payment.id }) }}</span>
                        <span v-if="payment.is_voided" class="badge badge-gray">{{ t('purchasing.voided') }}</span>
                    </h1>
                    <p class="page-sub">
                        <RouterLink :to="{ name: 'dashboard.purchasing.supplier', params: { id: payment.supplier_id } }" class="underline">{{ payment.supplier_name }}</RouterLink>
                        · {{ nameOf(payment.branch) }}
                    </p>
                </div>
                <button v-if="canWrite && payment.can_void" type="button" class="btn btn-ghost" :disabled="busy" @click="voidErrors = {}; showVoid = true">{{ t('purchasing.void_payment') }}</button>
            </div>

            <div v-if="payment.is_voided" class="card p-3 text-sm" style="background:var(--gray-soft);color:var(--ink)">
                {{ t('purchasing.voided_on', { date: fmtDate(payment.voided_at, locale) }) }}:
                {{ t('purchasing.payment_void_reasons.' + payment.void_reason) }}<span v-if="payment.void_note"> · {{ payment.void_note }}</span>
            </div>

            <div class="card p-5 grid grid-cols-2 sm:grid-cols-4 gap-4 text-sm">
                <div><div style="color:var(--muted)">{{ t('purchasing.paid_at') }}</div><div style="color:var(--ink)">{{ fmtDay(payment.paid_at, locale) }}</div></div>
                <div><div style="color:var(--muted)">{{ t('purchasing.method') }}</div><div style="color:var(--ink)">{{ t('purchasing.methods.' + payment.method) }}</div></div>
                <div><div style="color:var(--muted)">{{ t('purchasing.payment_reference') }}</div><div class="mono" dir="ltr" style="color:var(--ink)">{{ payment.reference || '—' }}</div></div>
                <div><div style="color:var(--muted)">{{ t('purchasing.amount') }}</div><div class="mono font-semibold" dir="ltr" style="color:var(--ink)">{{ show(payment.amount_minor) }}</div></div>
                <div><div style="color:var(--muted)">{{ t('purchasing.allocated') }}</div><div class="mono" dir="ltr" style="color:var(--ink)">{{ show(payment.allocated_minor) }}</div></div>
                <div><div style="color:var(--muted)">{{ t('purchasing.on_account') }}</div><div class="mono" dir="ltr" style="color:var(--ink)">{{ show(payment.on_account_minor) }}</div></div>
                <div v-if="payment.cash_movement" class="col-span-2">
                    <div style="color:var(--muted)">{{ t('purchasing.till_payout') }}</div>
                    <div style="color:var(--ink)">{{ fmtDate(payment.cash_movement.occurred_at, locale, { time: true }) }} · <span class="mono" dir="ltr">{{ show(payment.cash_movement.amount_minor) }}</span> · {{ payment.cash_movement.reason }}</div>
                </div>
                <div v-if="payment.note" class="col-span-2 sm:col-span-4"><div style="color:var(--muted)">{{ t('purchasing.notes') }}</div><div class="whitespace-pre-line" style="color:var(--body)">{{ payment.note }}</div></div>
            </div>

            <div class="card overflow-hidden">
                <div class="px-5 py-3 font-semibold" style="color:var(--ink)">{{ t('purchasing.allocations') }}</div>
                <div v-if="!payment.allocations || !payment.allocations.length" class="px-5 pb-5 text-sm" style="color:var(--muted)">{{ t('purchasing.on_account_hint') }}</div>
                <ul v-else>
                    <li v-for="a in payment.allocations" :key="a.id" class="flex flex-wrap items-center gap-3 px-5 py-3 border-t text-sm" style="border-color:var(--line)">
                        <RouterLink :to="{ name: 'dashboard.purchasing.invoice', params: { id: a.supplier_invoice_id } }" class="mono underline" dir="ltr">{{ a.invoice?.number || '#' + a.supplier_invoice_id }}</RouterLink>
                        <span v-if="a.invoice" style="color:var(--body)">{{ t('purchasing.due_at') }} {{ fmtDay(a.invoice.due_at, locale) }}</span>
                        <span class="ms-auto mono" dir="ltr" :style="payment.is_voided ? 'text-decoration:line-through' : ''">{{ show(a.amount_minor) }}</span>
                    </li>
                </ul>
            </div>
        </template>

        <ReasonDialog
            v-if="showVoid"
            :title="t('purchasing.void_payment_title')"
            :subtitle="payment ? t('purchasing.payment_ref', { id: payment.id }) : ''"
            :message="t('purchasing.void_payment_message')"
            :reasons="PAYMENT_VOID_REASONS"
            label-prefix="purchasing.payment_void_reasons"
            :confirm-text="t('purchasing.void_payment')"
            :busy="busy"
            :errors="voidErrors"
            @submit="submitVoid"
            @close="showVoid = false"
        />
    </div>
</template>
