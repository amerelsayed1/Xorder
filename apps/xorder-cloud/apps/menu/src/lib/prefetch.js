// Warms a code-split chunk ahead of the tap that will need it.
//
// Every overlay in the menu (item modal, cart, side menu, …) is loaded on
// demand so its code stays out of the first-load bundle — but a diner tapping
// an item should not wait on a network round-trip before anything appears.
// Fetching a loader while the browser is idle, once the grid is already
// painted and the diner is reading, keeps the cost off the critical path and
// still has the chunk resolved by the time they act on it.
//
// Each loader is warmed at most once; the module registry caches the result,
// so the real import() at open time resolves without another request.
const warmed = new WeakSet()

export function warm(load) {
    if (warmed.has(load)) return
    warmed.add(load)
    // Failures are ignored on purpose: this is speculative, and the import at
    // open time retries for real (and can surface the error there).
    const run = () => { load().catch(() => {}) }
    if (typeof requestIdleCallback === 'function') requestIdleCallback(run, { timeout: 3000 })
    else setTimeout(run, 1200)
}
