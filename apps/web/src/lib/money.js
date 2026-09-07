// Integer money and integer rates — converted at the UI edge, nowhere else.
//
// The POS wire is integer-only. A rate is BASIS POINTS (1400 = 14.00%) and an
// amount is MINOR UNITS (11400 = 114.00 EGP). Humans type "14.5" and "114.00",
// so every screen that authors POS money converts here.
//
// The parse is deliberately STRING-based rather than `parseFloat(x) * 100`.
// The float route puts 14.55% at 1454.9999999999998, and one truncation later
// at 1454 — a tax rate that is quietly wrong on every ticket a till prints.
// Reading the integer and fraction digits separately makes 14.5 -> 1450 true
// by construction, with no binary rounding anywhere in the path.

import { toEnDigits } from '@xorder/ui/enDigits.js'

// Percent is stored scaled by 100 (basis points), so a percent field always
// has exactly two decimal places of precision.
export const RATE_PLACES = 2

// Currencies whose minor unit is a thousandth, not a hundredth. MUST mirror
// CurrencyEnum::exponent() on the backend (apps/api/app/Enums/CurrencyEnum.php)
// — these three-decimal currencies are the whole reason POS money is integer
// minor units, and assuming 100 anywhere is a bug for a Kuwaiti tenant.
const THREE_DECIMAL = ['KWD', 'BHD', 'OMR', 'JOD']

/** ISO 4217 minor-unit exponent for a currency code. */
export function currencyExponent(code) {
    return THREE_DECIMAL.includes(String(code || '').toUpperCase()) ? 3 : 2
}

/**
 * "14.5" -> 1450 at places=2. Returns null for empty input and NaN for
 * anything that isn't a plain decimal, so a caller can tell "not filled in"
 * from "not a number". Half-up rounding on the first dropped digit; the whole
 * computation is over digit strings and integers.
 */
export function decimalToScaledInt(value, places) {
    const raw = toEnDigits(value == null ? '' : String(value)).trim()
    if (raw === '') return null
    const m = /^(\d*)(?:[.,](\d*))?$/.exec(raw)
    if (!m || (m[1] === '' && !m[2])) return NaN
    // One extra digit is kept purely to decide the rounding direction.
    const frac = ((m[2] || '') + '0'.repeat(places + 1)).slice(0, places + 1)
    // Concatenated digits parsed as an integer — exact well past any money
    // value a restaurant will ever type.
    const scaled = Number((m[1] || '0') + frac.slice(0, places))
    return frac.charCodeAt(places) - 48 >= 5 ? scaled + 1 : scaled
}

/**
 * 1450 -> "14.50", or "14.5" with `trim` (what a percent input should show, so
 * an owner who typed 14 sees 14 again and not 14.00).
 */
export function scaledIntToDecimal(scaled, places, { trim = false } = {}) {
    if (scaled == null || !Number.isFinite(Number(scaled))) return ''
    const n = Math.trunc(Number(scaled))
    const digits = String(Math.abs(n)).padStart(places + 1, '0')
    const int = places ? digits.slice(0, -places) : digits
    let frac = places ? digits.slice(-places) : ''
    if (trim) frac = frac.replace(/0+$/, '')
    return (n < 0 ? '-' : '') + int + (frac ? `.${frac}` : '')
}

/** Basis points <-> the percent string a human types. */
export const bpToPercent = (bp) => scaledIntToDecimal(bp, RATE_PLACES, { trim: true })
export const percentToBp = (value) => decimalToScaledInt(value, RATE_PLACES)

/** Minor units <-> the major-unit amount a human types, per currency. */
export const minorToAmount = (minor, exponent) => scaledIntToDecimal(minor, exponent)
export const amountToMinor = (value, exponent) => decimalToScaledInt(value, exponent)

/**
 * A minor-unit value with its currency token, for read-only hints and table
 * cells. Formatting only — nothing here ever feeds a request body.
 */
export function formatMinor(minor, exponent, token) {
    const amount = scaledIntToDecimal(minor, exponent)
    return token ? `${amount} ${token}` : amount
}

/**
 * `minor * bp / 10000`, rounded half-up on integers. The same shape the
 * TicketEngine uses, so the worked example a screen shows an owner matches
 * what the till will actually print.
 */
export function applyBp(minor, bp) {
    return Math.round((minor * bp) / 10000)
}
