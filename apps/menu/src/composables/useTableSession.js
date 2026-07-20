import { ref } from 'vue'
import { createTableSession } from '../api.js'

/**
 * Detects a table QR entry (URL path .../t/{TOKEN}), opens a table menu
 * session, and exposes the table context for the banner. When present, the
 * session token is carried on the order so the backend binds it to the table.
 */
export function useTableSession(language = 'ar') {
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

    async function init() {
        if (!token) return
        try {
            const { data: ctx } = await createTableSession(token, language)
            sessionToken.value = ctx.session_token
            tableLabel.value = ctx.table?.label || ''
            area.value = ctx.area
            branch.value = ctx.branch
            billRequests.value = !!ctx.bill_requests
            internalReviews.value = !!ctx.internal_reviews
            hasTable.value = true
        } catch (e) {
            // Invalid / disabled table / disabled branch (ERR-001/002).
            tableError.value = e.response?.data?.message || ''
        }
    }

    init()

    return { hasTable, sessionToken, tableLabel, area, branch, billRequests, internalReviews, tableError }
}
