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
