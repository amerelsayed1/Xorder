// Shared display helpers for the CB-09 purchasing and inventory pages.
// Formatting only: nothing here ever feeds a request body.

import { formatMinor } from '../../../lib/money.js'
import { currencyLabel } from '../../../lib/currency.js'
import { formatMilli } from '../../../lib/quantity.js'

// The till's five statuses, as badge classes from theme.css.
const STATUS_BADGE = {
    draft: 'badge-gray',
    sent: 'badge-amber',
    partially_received: 'badge-amber',
    received: 'badge-green',
    cancelled: 'badge-red',
}
export const statusBadge = (status) => STATUS_BADGE[status] || 'badge-gray'
export const STATUSES = Object.keys(STATUS_BADGE)

// Dates in the UI language, but always with Latin digits, like every amount
// and reference on these pages.
export function fmtDate(iso, locale, { time = false } = {}) {
    if (!iso) return ''
    const d = new Date(iso)
    if (Number.isNaN(d.getTime())) return ''
    const tag = locale === 'ar' ? 'ar-EG-u-nu-latn' : 'en-GB'
    return new Intl.DateTimeFormat(tag, time ? { dateStyle: 'medium', timeStyle: 'short' } : { dateStyle: 'medium' }).format(d)
}

/** "591.25 EGP" / "591.25 ج.م" from minor units and the document's own exponent. */
export function money(minor, exponent, currency, locale) {
    return formatMinor(minor ?? 0, exponent ?? 2, currencyLabel(currency, locale))
}

/** "12.5 kg" — always rendered inside an LTR span by the caller. */
export const qty = (milli, unitCode) => `${formatMilli(milli)} ${unitCode || ''}`.trim()

// ---- CB-09 slice c: supplier invoices and payments

// An invoice's state is derived by the server from its live allocations.
const INVOICE_BADGE = { open: 'badge-amber', overdue: 'badge-red', settled: 'badge-green', voided: 'badge-gray' }
export const invoiceBadge = (state) => INVOICE_BADGE[state] || 'badge-gray'
export const INVOICE_STATES = Object.keys(INVOICE_BADGE)

// The till's own lists, in its order (supplier_invoice.dart, migration 31).
export const PAYMENT_METHODS = ['cash', 'bank_transfer', 'cheque', 'card', 'other']
export const INVOICE_VOID_REASONS = ['entered_twice', 'wrong_supplier', 'wrong_amount', 'credit_note', 'goods_returned', 'other']
export const PAYMENT_VOID_REASONS = ['wrong_amount', 'wrong_invoice', 'wrong_supplier', 'cheque_bounced', 'entered_twice', 'other']
// Closing a part delivery short (D11). The till has no list for this yet.
export const CLOSE_REASONS = ['supplier_cannot_supply', 'no_longer_needed', 'refused_on_delivery', 'other']

/** Today in the browser's calendar, "2026-09-13" (a form default only). */
export function todayLocal() {
    const d = new Date()
    d.setMinutes(d.getMinutes() - d.getTimezoneOffset())
    return d.toISOString().slice(0, 10)
}

/** "2026-03-01" + 30 → "2026-03-31", on the calendar (UTC), never on a clock. */
export function addDays(ymd, days) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(ymd || '')) return ''
    const d = new Date(`${ymd}T00:00:00Z`)
    d.setUTCDate(d.getUTCDate() + (Number(days) || 0))
    return d.toISOString().slice(0, 10)
}

/** A plain "Y-m-d" as a date in the UI language, with Latin digits. */
export const fmtDay = (ymd, locale) => (ymd ? fmtDate(`${ymd}T12:00:00`, locale) : '')
