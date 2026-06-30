import axios from 'axios'

// Sanctum SPA client. Cookies carry the session; the XSRF-TOKEN cookie is
// echoed back automatically on mutating requests.
//
// Decoupled deploy: set VITE_API_URL to the API origin (e.g.
// https://api.tryorder.net). The SPA and API must share a parent domain so the
// session cookie is sent cross-subdomain (API sets SESSION_DOMAIN=.tryorder.net).
// In dev, leave VITE_API_URL unset — requests stay same-origin and Vite proxies
// /api and /sanctum to the Laravel server (see vite.config.js).
const api = axios.create({
    baseURL: import.meta.env.VITE_API_URL || '/',
    withCredentials: true,
    withXSRFToken: true,
    headers: { Accept: 'application/json' },
})

let csrfReady = false

/** Prime the CSRF cookie once before the first stateful request. */
export async function ensureCsrf() {
    if (csrfReady) return
    await api.get('sanctum/csrf-cookie')
    csrfReady = true
}

api.interceptors.request.use((config) => {
    config.headers = config.headers ?? {}
    config.headers['X-Locale'] = localStorage.getItem('locale') || document.documentElement.lang || 'en'
    return config
})

// On hard 401s, drop the local session so guards redirect to /login.
api.interceptors.response.use(
    (r) => r,
    (error) => {
        if (error.response?.status === 401) {
            csrfReady = false
        }
        return Promise.reject(error)
    },
)

export default api
