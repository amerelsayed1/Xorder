// Quantities are INTEGER THOUSANDTHS ("milli"), exactly as money is integer
// minor units, and for the same reason (CB-09). 12.5 kg is 12500.
//
// This file mirrors the till's Quantity (xorder-pos lib/core/money/quantity.dart):
// `parseQuantity` is Quantity.tryParse, `formatMilli` is Quantity.format, and
// `costAt` / `percentBp` / `orderTotals` are the three rounding points of a
// purchase order. There is no float anywhere: typed input is split on the
// point and each half read as digits, and the arithmetic runs on BigInt, so
// 0.1 + 0.2 never becomes 0.30000000000000004 on the way to a cost price.
//
// Everything a person SEES as a total here is a preview. The server computes
// the real figure with the same integer arithmetic and is authoritative.

import { toEnDigits } from '@xorder/ui/enDigits.js'

export const MILLI = 1000

/**
 * What somebody typed -> thousandths. Returns null for empty input and NaN
 * for anything that isn't a plain decimal with at most three places, so a
 * caller can tell "not filled in" from "not a number".
 *
 * Like the till: '.5' is 500; '1.' and '1.2345' are refused (more than three
 * decimals is somebody typing something this cannot hold; it is refused, not
 * truncated). Arabic-Indic digits and the Arabic decimal separator fold first.
 */
export function parseQuantity(value, { allowNegative = false } = {}) {
    let raw = toEnDigits(value == null ? '' : String(value)).replace(/٫/g, '.').trim()
    if (raw === '') return null
    let negative = false
    if (raw.startsWith('-')) {
        if (!allowNegative) return NaN
        negative = true
        raw = raw.slice(1)
    }
    const m = /^(\d*)(?:[.,](\d{1,3}))?$/.exec(raw)
    if (!m || (m[1] === '' && m[2] === undefined)) return NaN
    const whole = m[1] === '' ? 0 : Number(m[1])
    const frac = m[2] === undefined ? 0 : Number(m[2].padEnd(3, '0'))
    const milli = whole * MILLI + frac
    if (!Number.isSafeInteger(milli)) return NaN
    return negative ? -milli : milli
}

/** 12500 -> "12.5", 2000 -> "2", -1500 -> "-1.5". Trailing zeroes dropped. */
export function formatMilli(milli) {
    if (milli == null || !Number.isFinite(Number(milli))) return ''
    const n = Math.trunc(Number(milli))
    const abs = Math.abs(n)
    const whole = Math.floor(abs / MILLI)
    const fraction = abs % MILLI
    const sign = n < 0 ? '-' : ''
    if (fraction === 0) return `${sign}${whole}`
    return `${sign}${whole}.${String(fraction).padStart(3, '0').replace(/0+$/, '')}`
}

/** A whole number of units? (The till's Quantity.isWhole.) */
export const isWholeMilli = (milli) => Number(milli) % MILLI === 0

// Half-up integer division; negatives round half AWAY from zero, as the
// till's roundHalfUp (lib/core/money/rounding.dart) and StockCosting.php do.
function roundHalfUp(numerator, denominator) {
    const n = BigInt(numerator)
    const d = BigInt(denominator)
    if (n >= 0n) return (n * 2n + d) / (d * 2n)
    return -((-n * 2n + d) / (d * 2n))
}

/** What `milli` thousandths cost at `unitCostMinor` each: the line's one rounding point. */
export function costAt(milli, unitCostMinor) {
    return Number(roundHalfUp(BigInt(milli) * BigInt(unitCostMinor), 1000n))
}

/** A basis-point rate applied to an amount, rounded half-up once. */
export function percentBp(minor, bp) {
    return Number(roundHalfUp(BigInt(minor) * BigInt(bp), 10000n))
}

/**
 * The tax ALREADY INSIDE a gross amount: the till's Money.taxWithinBp and
 * StockCosting::taxWithinBp, roundHalfUp(gross × bp, 10000 + bp). 1,140.00
 * holding 14% contains 140.00, not 159.60. For a supplier invoice typed as a
 * total and a rate (CB-09 slice c). Preview only; the server recomputes.
 */
export function taxWithinBp(grossMinor, bp) {
    return Number(roundHalfUp(BigInt(grossMinor) * BigInt(bp), 10000n + BigInt(bp)))
}

/**
 * An order's totals from its lines, tax rounded PER RATE (not per line, not
 * once at the end): the till's PurchaseOrder.totals and the server's
 * PurchaseOrderService::totals. Lines missing a number are skipped.
 *
 * @param {{quantity_milli:number, unit_cost_minor:number, tax_rate_bp?:number}[]} lines
 */
export function orderTotals(lines) {
    let subtotal = 0n
    const bases = new Map()
    for (const l of lines) {
        if (!Number.isSafeInteger(l.quantity_milli) || !Number.isSafeInteger(l.unit_cost_minor)) continue
        const amount = BigInt(costAt(l.quantity_milli, l.unit_cost_minor))
        subtotal += amount
        const bp = Number(l.tax_rate_bp) || 0
        if (bp > 0) bases.set(bp, (bases.get(bp) || 0n) + amount)
    }
    let tax = 0n
    for (const [bp, base] of bases) tax += BigInt(percentBp(base, bp))
    return { subtotal_minor: Number(subtotal), tax_minor: Number(tax), total_minor: Number(subtotal + tax) }
}
