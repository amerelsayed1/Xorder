import axios from 'axios'

const BASE = import.meta.env.VITE_API_URL || ''

export async function fetchMenu(slug) {
    // Owner previews open the live menu with ?preview=1; forward it so the API
    // excludes the owner's own visit from the restaurant's view analytics.
    const isPreview = new URLSearchParams(window.location.search).has('preview')
    const { data } = await axios.get(`${BASE}/api/public/restaurants/${slug}/menu`, {
        headers: { Accept: 'application/json' },
        params: isPreview ? { preview: 1 } : undefined,
    })
    return data
}

/**
 * Record the order server-side before the WhatsApp handoff, so the
 * restaurant keeps history even if the customer never sends the message.
 */
export async function postOrder(slug, payload) {
    const { data } = await axios.post(`${BASE}/api/public/restaurants/${slug}/orders`, payload, {
        headers: { Accept: 'application/json' },
    })
    return data
}

/**
 * Save just the diner's contact details to the restaurant's customer directory.
 * Used at WhatsApp checkout, which records no order but still captures the
 * customer. Fire-and-forget; never blocks the WhatsApp handoff.
 */
export async function saveCustomer(slug, payload) {
    const { data } = await axios.post(`${BASE}/api/public/restaurants/${slug}/customers`, payload, {
        headers: { Accept: 'application/json' },
    })
    return data
}

/** Table context for a scanned QR (tells us whether a presence fence applies). */
export async function getTableContext(token) {
    const { data } = await axios.get(`${BASE}/api/public/tables/${token}`, {
        headers: { Accept: 'application/json' },
    })
    return data
}

/**
 * Open a table menu session from a scanned table QR token. When the branch
 * fences its premises, `coords` ({ latitude, longitude }) must be inside it or
 * the backend refuses the session (presence check).
 */
export async function createTableSession(token, language, coords = null) {
    const payload = { language }
    if (coords) {
        payload.latitude = coords.latitude
        payload.longitude = coords.longitude
    }
    const { data } = await axios.post(`${BASE}/api/public/tables/${token}/sessions`, payload, {
        headers: { Accept: 'application/json', 'X-Locale': language || 'ar' },
    })
    return data
}

/** Ask a staff member to bring the bill for the current table session. */
export async function createBillRequest(sessionToken, note) {
    const { data } = await axios.post(
        `${BASE}/api/public/sessions/${sessionToken}/bill-requests`,
        { note: note || undefined },
        { headers: { Accept: 'application/json' } },
    )
    return data
}

/** Poll a bill request's status by its opaque token. */
export async function getBillRequest(token) {
    const { data } = await axios.get(`${BASE}/api/public/bill-requests/${token}`, {
        headers: { Accept: 'application/json' },
    })
    return data
}

/** Cancel a bill request while it is still pending. */
export async function cancelBillRequest(token) {
    const { data } = await axios.patch(`${BASE}/api/public/bill-requests/${token}/cancel`, {}, {
        headers: { Accept: 'application/json' },
    })
    return data
}

/** Leave private feedback (rating + optional comment/contact) for the restaurant. */
export async function createReview(slug, payload, locale = 'ar') {
    const { data } = await axios.post(`${BASE}/api/public/restaurants/${slug}/reviews`, payload, {
        headers: { Accept: 'application/json', 'X-Locale': locale },
    })
    return data
}
