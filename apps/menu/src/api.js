import axios from 'axios'

const BASE = import.meta.env.VITE_API_URL || ''

export async function fetchMenu(slug) {
    const { data } = await axios.get(`${BASE}/api/public/restaurants/${slug}/menu`, {
        headers: { Accept: 'application/json' },
    })
    return data
}
