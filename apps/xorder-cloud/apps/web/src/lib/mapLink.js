import api from '@xorder/api-client/api.js'

// Turns a pasted Google Maps location into { latitude, longitude }.
//
// Full map URLs and raw "lat,lng" strings carry the coordinates inline, so we
// parse them in the browser — instant, no round-trip. Mobile "share" short
// links (maps.app.goo.gl, goo.gl) carry nothing until their redirect is
// followed, which the browser can't do (opaque cross-origin redirects), so we
// hand those to the backend resolver.

function inRange(lat, lng) {
    return (
        Number.isFinite(lat) && Number.isFinite(lng)
        && lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180
        && !(lat === 0 && lng === 0) // null-island → almost always a mis-parse
    )
}

/**
 * Extract coordinates from a URL or free text without any network call.
 * @returns {{ latitude: number, longitude: number } | null }
 */
export function parseCoords(text) {
    if (!text) return null
    const decoded = (() => { try { return decodeURIComponent(text) } catch { return text } })()

    const patterns = [
        /!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)/,                                    // place pin in data param
        /@(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)/,                                     // /@lat,lng,17z
        /[?&](?:q|query|ll|destination|center|sll|daddr)=(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)/i,
        /(-?\d{1,2}(?:\.\d+)?),\s*(-?\d{1,3}(?:\.\d+)?)/,                              // bare "lat,lng"
    ]

    for (const re of patterns) {
        const m = decoded.match(re)
        if (m) {
            const lat = parseFloat(m[1])
            const lng = parseFloat(m[2])
            if (inRange(lat, lng)) return { latitude: lat, longitude: lng }
        }
    }
    return null
}

/**
 * Resolve a pasted location to coordinates: parse locally first, then fall back
 * to the backend for short share links.
 * @returns {Promise<{ latitude: number, longitude: number } | null>}
 */
export async function resolveMapLink(text) {
    const trimmed = (text || '').trim()
    if (!trimmed) return null

    const local = parseCoords(trimmed)
    if (local) return local

    try {
        const { data } = await api.post('api/dashboard/geo/resolve-map-link', { url: trimmed })
        const lat = Number(data?.data?.latitude)
        const lng = Number(data?.data?.longitude)
        return inRange(lat, lng) ? { latitude: lat, longitude: lng } : null
    } catch {
        return null
    }
}

/** Google Maps link for a stored coordinate pair (used for the preview link). */
export function mapsUrl(lat, lng) {
    return `https://www.google.com/maps/search/?api=1&query=${lat},${lng}`
}
