// Subscription dates as the restaurant sees them. End dates are calendar
// days (YYYY-MM-DD), and "today" must be the restaurant's own day, not the
// browser's: an owner travelling abroad still runs a Cairo restaurant.

/** Today's date (YYYY-MM-DD) in an IANA zone; the browser's day if the zone is unusable. */
export function todayIn(timezone) {
    try {
        // en-CA formats as YYYY-MM-DD.
        return new Intl.DateTimeFormat('en-CA', { timeZone: timezone || undefined, year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date())
    } catch {
        return new Intl.DateTimeFormat('en-CA', { year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date())
    }
}

/** Whole days from the restaurant's today to `endDate`: negative once past, null with no end date. */
export function daysUntil(endDate, timezone) {
    if (!endDate) return null
    const end = Date.parse(endDate + 'T00:00:00Z')
    const today = Date.parse(todayIn(timezone) + 'T00:00:00Z')
    if (Number.isNaN(end) || Number.isNaN(today)) return null
    return Math.round((end - today) / 86_400_000)
}

/** How close is "ending soon" for a paid plan (a trial always shows). */
export const ENDING_SOON_DAYS = 7
