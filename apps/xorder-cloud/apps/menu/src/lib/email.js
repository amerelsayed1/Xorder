// Validate an email address. Empty is considered valid — presence is a
// separate (required/optional) concern, mirroring phone.js.
export function isValidEmail(value) {
    const v = String(value ?? '').trim()
    if (!v) return true
    // Pragmatic check: a local part, an "@", and a dotted domain with no spaces.
    return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v)
}
