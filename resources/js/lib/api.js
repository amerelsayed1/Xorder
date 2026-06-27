import axios from 'axios'

// Same-origin Sanctum SPA client. Cookies carry the session; the XSRF-TOKEN
// cookie is echoed back automatically on mutating requests.
const api = axios.create({
    baseURL: '/',
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
