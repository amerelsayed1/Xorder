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
