import axios from 'axios'

// Stateless JWT client. The access token is stored in localStorage and sent as
// an Authorization: Bearer header on every request. There is no session cookie
// and no CSRF handshake.
//
// Decoupled deploy: set VITE_API_URL to the API origin (e.g.
// https://api.tryorder.net). Because auth rides in a header (not a cookie), the
// SPA and API no longer need to share a parent domain.
// In dev, leave VITE_API_URL unset — requests stay same-origin and Vite proxies
// /api to the Laravel server (see vite.config.js).

const TOKEN_KEY = 'xorder_token'

export function getToken() {
    return localStorage.getItem(TOKEN_KEY)
}

/** Persist (or, with a falsy value, clear) the access token. */
export function setToken(token) {
    if (token) localStorage.setItem(TOKEN_KEY, token)
    else localStorage.removeItem(TOKEN_KEY)
}

export function clearToken() {
    localStorage.removeItem(TOKEN_KEY)
}

const api = axios.create({
    baseURL: import.meta.env.VITE_API_URL || '/',
    headers: { Accept: 'application/json' },
})

/**
 * Deprecated no-op, kept so existing call sites (`await ensureCsrf()`) keep
 * working after the move from Sanctum cookies to JWT. Bearer-token auth needs
 * no CSRF cookie to prime. Safe to delete the calls at leisure.
 */
export async function ensureCsrf() {}

api.interceptors.request.use((config) => {
    config.headers = config.headers ?? {}
    const token = getToken()
    if (token) config.headers['Authorization'] = `Bearer ${token}`
    config.headers['X-Locale'] = localStorage.getItem('locale') || document.documentElement.lang || 'en'
    return config
})

// On hard 401s, drop the stored token so route guards redirect to /login.
api.interceptors.response.use(
    (r) => r,
    (error) => {
        if (error.response?.status === 401) {
            clearToken()
        }
        // A subscription-blocked write (read-only dashboard): announce it so the
        // shell can show a single friendly notice, no matter which page fired it.
        if (error.response?.status === 403 && error.response?.data?.code === 'subscription_inactive'
            && typeof window !== 'undefined') {
            window.dispatchEvent(new CustomEvent('xorder:read-only-blocked'))
        }
        return Promise.reject(error)
    },
)

export default api
