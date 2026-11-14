import { isValidPhoneNumber } from 'libphonenumber-js'

// Arabic-Indic (٠-٩) and Persian (۰-۹) digits → Latin (0-9).
export function toLatinDigits(s) {
    return (s || '')
        .replace(/[٠-٩]/g, d => '٠١٢٣٤٥٦٧٨٩'.indexOf(d))
        .replace(/[۰-۹]/g, d => '۰۱۲۳۴۵۶۷۸۹'.indexOf(d))
}

// Validate a phone number against its country's own rules. International
// "+CC..." input is honored regardless of `country`; local input is parsed
// against `country` (default Egypt).
export function isValidMobile(value, country = 'EG') {
    const v = toLatinDigits(String(value ?? '')).trim()
    if (!v) return false
    try {
        return isValidPhoneNumber(v, country)
    } catch {
        return false
    }
}
