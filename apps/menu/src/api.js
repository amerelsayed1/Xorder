import axios from 'axios'

const BASE = import.meta.env.VITE_API_URL || ''

export async function fetchMenu(slug) {
    const { data } = await axios.get(`${BASE}/api/public/restaurants/${slug}/menu`, {
        headers: { Accept: 'application/json' },
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

/** Open a table menu session from a scanned table QR token. */
export async function createTableSession(token, language) {
    const { data } = await axios.post(`${BASE}/api/public/tables/${token}/sessions`, { language }, {
        headers: { Accept: 'application/json' },
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
