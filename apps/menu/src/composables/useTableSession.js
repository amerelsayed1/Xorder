import { ref, computed } from 'vue'
import { createTableSession, getTableContext } from '../api.js'

// Longest we sample location before settling for the best fix so far, and the
// accuracy target to fall back on if the fence context doesn't supply one.
const MAX_WATCH_MS = 8000
const DEFAULT_TARGET_ACCURACY_M = 25

/**
 * Resolve the diner's best available position. A single getCurrentPosition
 * returns whatever fix the phone has ready — usually a coarse Wi-Fi/cell
 * estimate before the GNSS settles. Instead we watch for a few seconds and keep
 * the tightest (smallest-accuracy) reading, which makes the branch geofence test
 * far more reliable. Sampling stops as soon as accuracy reaches `targetAccuracy`
 * (derived per-fence from its size) or the window elapses — whichever is first —
 * and the best fix seen is returned.
 *
 * Rejects if the browser has no geolocation, or the user denies / nothing
 * arrives — the caller treats any failure as "no proof of presence" and blocks
 * (no spoofable fallback).
 */
function bestPosition(targetAccuracy = DEFAULT_TARGET_ACCURACY_M) {
    return new Promise((resolve, reject) => {
        if (!navigator.geolocation) {
            reject(new Error('unsupported'))
            return
        }

        let best = null
        let watchId = null
        let timer = null
        let settled = false

        const cleanup = () => {
            if (watchId !== null) navigator.geolocation.clearWatch(watchId)
            if (timer !== null) clearTimeout(timer)
        }
        // Settle with the best fix gathered so far (window elapsed or target met).
        const done = () => { if (settled) return; settled = true; cleanup(); best ? resolve(best) : reject(new Error('timeout')) }
        // Only surface an error if we never got a usable fix; a late error after
        // a good reading must not discard it.
        const fail = (err) => { if (settled) return; settled = true; cleanup(); reject(err) }

        watchId = navigator.geolocation.watchPosition(
            (pos) => {
                const fix = {
                    latitude: pos.coords.latitude,
                    longitude: pos.coords.longitude,
                    // Fix uncertainty (metres); the backend widens the fence by it
                    // so a fuzzy-but-inside reading isn't wrongly rejected. A
                    // tighter fix here means a tighter, more reliable check.
                    accuracy: pos.coords.accuracy,
                }
                if (best === null || fix.accuracy < best.accuracy) best = fix
                if (best.accuracy <= targetAccuracy) done()
            },
            (err) => { if (best === null) fail(err) },
            { enableHighAccuracy: true, timeout: MAX_WATCH_MS, maximumAge: 0 },
        )

        timer = setTimeout(done, MAX_WATCH_MS)
    })
}

/**
 * Detects a table QR entry (URL path .../t/{TOKEN}), opens a table menu
 * session, and exposes the table context for the banner. When present, the
 * session token is carried on the order so the backend binds it to the table.
 *
 * If the branch enforces a presence geofence, the diner's GPS is captured
 * first and sent to the session; the backend refuses a session opened from
 * outside the branch (or with no location at all).
 *
 * @param {string} language
 * @param {(key: string) => string} t  menu translator, for client-side messages
 */
export function useTableSession(language = 'ar', t = (k) => k) {
    const match = window.location.pathname.match(/\/t\/([A-Za-z0-9]+)/)
    const token = match ? match[1] : ''

    const hasTable = ref(false)
    const sessionToken = ref('')
    const tableLabel = ref('')
    const area = ref(null)
    const branch = ref(null)
    const billRequests = ref(false)
    const internalReviews = ref(false)
    const tableError = ref('')
    const locating = ref(false)

    // A table QR was scanned but no valid on-site session was established
    // (still resolving location, denied GPS, or outside the branch fence) —
    // the diner may browse the menu but ordering is disabled.
    const orderingBlocked = computed(() => !!token && (locating.value || !!tableError.value))

    function applyContext(ctx) {
        sessionToken.value = ctx.session_token
        tableLabel.value = ctx.table?.label || ''
        area.value = ctx.area
        branch.value = ctx.branch
        billRequests.value = !!ctx.bill_requests
        internalReviews.value = !!ctx.internal_reviews
        hasTable.value = true
    }

    async function init() {
        if (!token) return
        try {
            // Learn whether this branch fences its premises before deciding
            // whether to prompt the diner for location at all.
            const { data: ctx } = await getTableContext(token)

            let coords = null
            if (ctx.geofence_required) {
                locating.value = true
                try {
                    // Hold out for a fix precise enough for THIS fence's size
                    // (the backend sizes the target to the branch geometry).
                    coords = await bestPosition(ctx.location_target_accuracy_m || DEFAULT_TARGET_ACCURACY_M)
                } catch {
                    // No trustworthy location → fail closed, don't open a session.
                    tableError.value = t('loc_needed')
                    return
                } finally {
                    locating.value = false
                }
            }

            const { data: session } = await createTableSession(token, language, coords)
            applyContext(session)
        } catch (e) {
            // Invalid / disabled table / disabled branch, or out-of-area (422).
            tableError.value = e.response?.data?.message || t('error_generic')
        }
    }

    init()

    return { hasTable, sessionToken, tableLabel, area, branch, billRequests, internalReviews, tableError, locating, orderingBlocked }
}
