// Fetches the public landing content managed from the super-admin dashboard.
// In dev, requests are proxied to the Laravel API (see vite.config.js). In prod,
// set VITE_API_URL to the API origin (e.g. https://api.tryorder.net).
const BASE = import.meta.env.VITE_API_URL || ''

export async function fetchLandingContent() {
    const res = await fetch(`${BASE}/api/public/landing-content`, {
        headers: { Accept: 'application/json' },
    })
    if (!res.ok) throw new Error(`Failed to load landing content (${res.status})`)
    const json = await res.json()
    return json.data
}

/**
 * Submit a landing-page demo-request lead. Resolves on success; throws an
 * Error whose `.fields` holds per-field validation messages on a 422.
 */
export async function postLead(payload) {
    const res = await fetch(`${BASE}/api/public/leads`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        body: JSON.stringify(payload),
    })
    if (res.status === 201) return
    if (res.status === 422) {
        const body = await res.json().catch(() => ({}))
        const err = new Error('validation')
        err.fields = body.errors || {}
        throw err
    }
    throw new Error(`Failed to submit lead (${res.status})`)
}
