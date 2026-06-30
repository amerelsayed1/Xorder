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
