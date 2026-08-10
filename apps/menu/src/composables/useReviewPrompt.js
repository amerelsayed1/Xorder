import { getOrderStatus } from '../api.js'

// A system order earns a private-feedback invite only once it is CLOSED
// (COMPLETED) by the restaurant — and only when the diner comes back / rescans,
// never right after checkout. We stash the just-placed order id in localStorage
// and re-check its status on the next visit: a completed order pops the prompt
// exactly once (the record is dropped as soon as we show it, so a reload won't
// nag), a cancelled order is discarded, and one still open waits for a later
// visit. WhatsApp checkouts record no order, so they never reach this at all.

// Self-expire a record whose order never closes, so it can't linger forever.
const MAX_AGE_MS = 7 * 24 * 60 * 60 * 1000

export function useReviewPrompt(slug) {
    const key = `xorder-pending-review:${slug}`

    function read() {
        try {
            const rec = JSON.parse(localStorage.getItem(key) || 'null')
            return rec && typeof rec.id === 'number' ? rec : null
        } catch {
            return null
        }
    }

    function clear() {
        try {
            localStorage.removeItem(key)
        } catch {
            /* private mode — feature just degrades to not prompting */
        }
    }

    // Remember a freshly placed system order as awaiting a feedback invite.
    function remember(id) {
        try {
            localStorage.setItem(key, JSON.stringify({ id, ts: Date.now() }))
        } catch {
            /* private mode / storage full — no prompt on return, that's fine */
        }
    }

    // On return/rescan: resolve the stashed order's status. Returns its id when
    // it's closed (and clears the record so it's a one-time prompt), else null.
    async function resolveClosedOrder() {
        const rec = read()
        if (!rec) return null
        if (Date.now() - (rec.ts || 0) > MAX_AGE_MS) {
            clear()
            return null
        }
        try {
            const res = await getOrderStatus(slug, rec.id)
            const status = res?.data?.status
            if (status === 'COMPLETED') {
                clear()
                return rec.id
            }
            // A cancelled order is never reviewed; a new one keeps waiting.
            if (status === 'CANCELLED') clear()
        } catch (e) {
            // 404 means the order is gone and will never resolve — stop tracking
            // it. Any other (transient) failure keeps the record for next time.
            if (e?.response?.status === 404) clear()
        }
        return null
    }

    return { remember, clear, resolveClosedOrder }
}
