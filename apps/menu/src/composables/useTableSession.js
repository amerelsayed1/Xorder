import { ref, computed } from 'vue'
import { createTableSession, getTableContext } from '../api.js'

/**
 * Resolve the diner's current position. Rejects if the browser has no
 * geolocation, or the user denies / it times out — the caller treats any
 * failure as "no proof of presence" and blocks (no spoofable fallback).
 */
function currentPosition() {
    return new Promise((resolve, reject) => {
        if (!navigator.geolocation) {
            reject(new Error('unsupported'))
            return
        }
        navigator.geolocation.getCurrentPosition(
            (pos) => resolve({
                latitude: pos.coords.latitude,
                longitude: pos.coords.longitude,
                // Fix uncertainty (metres); the backend widens the fence by it so
                // a fuzzy-but-inside mobile GPS reading isn't wrongly rejected.
                accuracy: pos.coords.accuracy,
            }),
            (err) => reject(err),
            { enableHighAccuracy: true, timeout: 15000, maximumAge: 0 },
        )
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
                    coords = await currentPosition()
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
