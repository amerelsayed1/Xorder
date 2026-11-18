import { ref, onMounted, onBeforeUnmount } from 'vue'

// Guest paging (docs/features/guest-paging, stage S3): the diner's order-number
// page. The 40-character token on the receipt is the only credential; the
// public endpoints answer 404 for an unknown or expired token and 403 when the
// restaurant does not hold the feature.
const BASE = import.meta.env.VITE_API_URL || ''
const POLL_MS = 5000
const MAX_BACKOFF_MS = 30000

/**
 * Poll the order's pickup state.
 *
 * - Sends the last ETag, so an unchanged order is a 304 with no body.
 * - Pauses while the tab is hidden and refreshes the moment it is visible again.
 * - Backs off after errors and 429s, keeps showing the last known state, and
 *   stops for good on a terminal state, an unknown token or a disabled feature.
 *
 * @param {string} token  the 40-character tracking token
 * @param {{ onBecameReady?: (order: object) => void }} [hooks]
 */
export function useOrderTracking(token, hooks = {}) {
    const order = ref(null)
    // loading | live | notfound | unavailable
    const phase = ref('loading')
    // The last poll failed; whatever is on screen may be out of date.
    const stale = ref(false)
    const acking = ref(false)

    const url = `${BASE}/api/public/orders/track/${token}`
    const baseHeaders = { Accept: 'application/json' }

    let etag = null
    let timer = null
    let failures = 0
    let stopped = false
    let inflight = false
    let followed = false

    const isTerminal = (o) => o && (o.status === 'PICKED_UP' || o.order_status === 'CANCELLED')

    function apply(next) {
        const prev = order.value?.status
        order.value = next
        phase.value = 'live'
        stale.value = false
        if (next.status === 'READY' && prev && prev !== 'READY') hooks.onBecameReady?.(next)
        if (isTerminal(next)) stopped = true
    }

    // Tell the board the diner is following on their phone. Once, best effort.
    function follow() {
        if (followed) return
        followed = true
        fetch(`${url}/follow`, { method: 'POST', headers: baseHeaders }).catch(() => {})
    }

    function schedule(ms) {
        clearTimeout(timer)
        // A hidden tab does not poll; the visibility handler resumes it.
        if (stopped || document.hidden) return
        timer = setTimeout(poll, ms)
    }

    async function poll() {
        if (stopped || inflight) return
        inflight = true
        let next = POLL_MS
        try {
            const res = await fetch(url, {
                headers: etag ? { ...baseHeaders, 'If-None-Match': etag } : baseHeaders,
                cache: 'no-store',
            })
            if (res.status === 304) {
                failures = 0
                stale.value = false
            } else if (res.ok) {
                etag = res.headers.get('ETag')
                const body = await res.json()
                failures = 0
                apply(body.data)
                follow()
            } else if (res.status === 404) {
                phase.value = 'notfound'
                stopped = true
            } else if (res.status === 403) {
                phase.value = 'unavailable'
                stopped = true
            } else {
                throw new Error(`http ${res.status}`)
            }
        } catch {
            failures++
            stale.value = true
            next = Math.min(POLL_MS * 2 ** Math.min(failures, 3), MAX_BACKOFF_MS)
        } finally {
            inflight = false
            schedule(next)
        }
    }

    /** "On my way": only accepted once the order is READY (422 otherwise). */
    async function acknowledge() {
        if (acking.value) return
        acking.value = true
        try {
            const res = await fetch(`${url}/ack`, { method: 'POST', headers: baseHeaders })
            if (res.ok) {
                apply((await res.json()).data)
            } else {
                // Not ready any more, or a stale view: drop the ETag and re-read.
                etag = null
                await poll()
            }
        } catch {
            // The button stays; the diner can tap again.
        } finally {
            acking.value = false
        }
    }

    function onVisibility() {
        if (document.hidden) {
            clearTimeout(timer)
        } else if (!stopped) {
            poll()
        }
    }

    onMounted(() => {
        document.addEventListener('visibilitychange', onVisibility)
        poll()
    })
    onBeforeUnmount(() => {
        stopped = true
        clearTimeout(timer)
        document.removeEventListener('visibilitychange', onVisibility)
    })

    return { order, phase, stale, acking, acknowledge }
}
