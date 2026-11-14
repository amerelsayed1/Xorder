// Validate an email address. Empty is considered valid — presence is a
// separate (required/nullable) concern, mirroring phone.js's isValidMobile.
export function isValidEmail(value) {
    const v = String(value ?? '').trim()
    if (!v) return true
    // Pragmatic check: a local part, an "@", and a dotted domain with no spaces.
    return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v)
}

// Build a server-shaped errors object ({ field: [message] }) for any of the
// given { field: value } entries that hold an invalid address. Empty object when
// everything is fine, so callers can `if (Object.keys(errs).length) …`.
export function collectEmailErrors(fields, message) {
    const errors = {}
    for (const [field, value] of Object.entries(fields)) {
        if (!isValidEmail(value)) errors[field] = [message]
    }
    return errors
}
