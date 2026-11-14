// Client-side mirror of the API's WeeklyHours, so a section that is due to open
// at 07:00 opens at 07:00 for a diner already sitting with the page loaded,
// instead of looking shut until they reload. The API still sends the answer for
// the first paint — this only keeps it honest as the clock moves.
//
// Kept deliberately in step with app/Support/WeeklyHours.php: same day keys,
// same half-open interval, same midnight-crossing rule.

const DAYS = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat']

// The weekday and minute-of-day at a moment, in the restaurant's timezone —
// which is the only clock these windows are written against. Falls back to the
// device clock if the zone is missing or unknown to the browser.
function zonedNow(timezone, at = Date.now()) {
    const date = new Date(at)
    let parts
    try {
        parts = new Intl.DateTimeFormat('en-US', {
            timeZone: timezone || undefined,
            weekday: 'short', hour: '2-digit', minute: '2-digit', hour12: false,
        }).formatToParts(date)
    } catch {
        parts = null
    }
    if (!parts) {
        return { day: DAYS[date.getDay()], minutes: date.getHours() * 60 + date.getMinutes() }
    }
    const get = (type) => parts.find((p) => p.type === type)?.value || ''
    const day = get('weekday').slice(0, 3).toLowerCase()
    // 24-hour formatting renders midnight as "24" in some locales/engines.
    const hour = Number(get('hour')) % 24
    return { day, minutes: hour * 60 + Number(get('minute')) }
}

function toMinutes(time) {
    const m = /^(\d{1,2}):(\d{2})$/.exec(String(time ?? ''))
    if (!m) return null
    const h = Number(m[1])
    const min = Number(m[2])
    return h > 23 || min > 59 ? null : h * 60 + min
}

// Does one day's entry cover this minute? `spillover` asks the other question:
// did that day's window run past midnight into now. Only the tail of an
// overnight window can answer it — see the PHP for why unset/always days must
// not.
function covers(entry, minutes, spillover) {
    if (!entry) return !spillover
    if (entry.closed) return false
    if (entry.always) return !spillover

    const open = toMinutes(entry.open)
    const close = toMinutes(entry.close)
    if (open === null || close === null) return !spillover

    if (close > open) return spillover ? false : (minutes >= open && minutes < close)
    return spillover ? minutes < close : minutes >= open
}

function previousDay(day) {
    const i = DAYS.indexOf(day)
    return i === -1 ? day : DAYS[(i + 6) % 7]
}

/** Is a schedule open right now? An absent schedule never closes anything. */
export function isServingNow(schedule, timezone, at = Date.now()) {
    if (!schedule || !Object.keys(schedule).length) return true
    const { day, minutes } = zonedNow(timezone, at)
    return covers(schedule[day], minutes, false)
        || covers(schedule[previousDay(day)], minutes, true)
}

/** Today's window as { open, close }, or null when today is unrestricted. */
export function todaysWindow(schedule, timezone, at = Date.now()) {
    if (!schedule) return null
    const entry = schedule[zonedNow(timezone, at).day]
    if (!entry || entry.closed || entry.always) return null
    return toMinutes(entry.open) === null || toMinutes(entry.close) === null
        ? null
        : { open: entry.open, close: entry.close }
}
