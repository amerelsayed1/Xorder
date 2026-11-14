import { isValidPhoneNumber } from 'libphonenumber-js'

// Arabic-Indic (٠-٩) and Persian (۰-۹) digits → Latin (0-9).
export function toLatinDigits(s) {
    return (s || '')
        .replace(/[٠-٩]/g, d => '٠١٢٣٤٥٦٧٨٩'.indexOf(d))
        .replace(/[۰-۹]/g, d => '۰۱۲۳۴۵۶۷۸۹'.indexOf(d))
}

// Validate a phone number against its country's own rules. International
// "+CC..." input is honored regardless of `country`; local input is parsed
// against `country` (default Egypt). Empty is considered valid — presence is a
// separate (required/nullable) concern.
export function isValidMobile(value, country = 'EG') {
    const v = toLatinDigits(String(value ?? '')).trim()
    if (!v) return true
    try {
        return isValidPhoneNumber(v, country)
    } catch {
        return false
    }
}

// Build a server-shaped errors object ({ field: [message] }) for any of the
// given { field: value } entries that hold an invalid number. Empty object when
// everything is fine, so callers can `if (Object.keys(errs).length) …`.
export function collectPhoneErrors(fields, message, country = 'EG') {
    const errors = {}
    for (const [field, value] of Object.entries(fields)) {
        if (!isValidMobile(value, country)) errors[field] = [message]
    }
    return errors
}
