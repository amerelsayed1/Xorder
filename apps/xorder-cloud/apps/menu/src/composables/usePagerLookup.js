import { ref, onMounted, onBeforeUnmount } from 'vue'

// Guest paging, shared QR (docs/features/guest-paging-shared-qr): the join page
// behind the restaurant's one standing QR. The client types the number printed on
// their slip; the cloud finds that order of the last few hours and the phone moves
// to its order-number page (/menu/o/{token}). No account, nothing stored.
const BASE = import.meta.env.VITE_API_URL || ''
const INFO_RETRY_MS = 3000
// A sale can still be on its way to the cloud: keep looking for a short while.
const AUTO_RETRY_MS = 5000
const AUTO_RETRIES = 6

// Slug normally comes from the subdomain (acme.xorder.io -> "acme"); on a bare
// host (localhost / IP) fall back to ?r=<slug>, exactly as the menu does.
function restaurantSlug() {
    const sub = window.location.hostname.split('.')[0]
    const bareHost = sub === 'localhost' || /^\d+$/.test(sub)
    return (bareHost && new URLSearchParams(window.location.search).get('r')) || sub
}

export function usePagerLookup() {
    const base = `${BASE}/api/public/restaurants/${restaurantSlug()}/pager-lookup`
    const headers = { Accept: 'application/json' }

    // loading | ready | found (redirecting) | unavailable
    const phase = ref('loading')
    const restaurant = ref(null)
    // '' | not_found | ambiguous | invalid | busy | error
    const problem = ref('')
    const busy = ref(false)
    // The restaurant details could not be loaded yet (no network).
    const stale = ref(false)

    let timer = null
    let retriesLeft = 0
    let stopped = false

    async function loadInfo() {
        try {
            const res = await fetch(base, { headers, cache: 'no-store' })
            if (res.status === 403 || res.status === 404) {
                phase.value = 'unavailable'
                return
            }
            if (!res.ok) throw new Error(`http ${res.status}`)
            restaurant.value = (await res.json()).data.restaurant
            stale.value = false
            phase.value = 'ready'
        } catch {
            stale.value = true
            if (!stopped) timer = setTimeout(loadInfo, INFO_RETRY_MS)
        }
    }

    /**
     * Look the number up. `auto` marks the silent retries after "not found yet".
     */
    async function submit(number, { auto = false } = {}) {
        const typed = String(number || '').trim()
        clearTimeout(timer)
        if (!auto) retriesLeft = AUTO_RETRIES
        if (typed === '') {
            problem.value = 'invalid'
            return
        }

        busy.value = true
        if (!auto) problem.value = ''
        try {
            const res = await fetch(base, {
                method: 'POST',
                headers: { ...headers, 'Content-Type': 'application/json' },
                body: JSON.stringify({ number: typed }),
                cache: 'no-store',
            })
            const body = await res.json().catch(() => null)

            if (res.ok && body?.data?.tracking_token) {
                phase.value = 'found'
                problem.value = ''
                stopped = true
                window.location.replace(`/menu/o/${body.data.tracking_token}`)
            } else if (res.status === 404) {
                problem.value = 'not_found'
                if (retriesLeft-- > 0 && !stopped) timer = setTimeout(() => submit(typed, { auto: true }), AUTO_RETRY_MS)
            } else if (res.status === 409) {
                problem.value = 'ambiguous'
            } else if (res.status === 422) {
                problem.value = 'invalid'
            } else if (res.status === 429) {
                problem.value = 'busy'
            } else if (res.status === 403) {
                phase.value = 'unavailable'
            } else {
                problem.value = 'error'
            }
        } catch {
            problem.value = 'error'
        } finally {
            busy.value = false
        }
    }

    onMounted(loadInfo)
    onBeforeUnmount(() => {
        stopped = true
        clearTimeout(timer)
    })

    return { phase, restaurant, problem, busy, stale, submit }
}
