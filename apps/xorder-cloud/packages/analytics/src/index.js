// Firebase Analytics (GA4) + Performance Monitoring — shared across the web,
// landing, and menu apps.
//
// Reads the public config injected by /firebase-config.js
// (window.__FIREBASE_CONFIG__ — the same object push notifications use). The
// GA4 stream is keyed by `measurementId`; without it, everything here is a safe
// no-op, so the apps run fine when analytics isn't configured.
//
// The firebase SDK is loaded with dynamic import() so it lands in its own chunk
// and never bloats an app's initial bundle (this matters most for the menu app).
// Events are also mirrored to window.dataLayer for GTM/gtag compatibility, so
// the existing landing-page event convention keeps working unchanged.

let analyticsPromise = null
let performancePromise = null
let appPromise = null
let appLabel = 'app'

// Optional "not yet" gate for the analytics SDK — see initAnalytics({ until }).
// null means "load as soon as someone asks", which is what the dashboard and
// landing page want.
let startGate = null

function readConfig() {
    return (typeof window !== 'undefined' && window.__FIREBASE_CONFIG__) || {}
}

// Local/dev hosts. Performance Monitoring has no "test property" equivalent, so
// traces from a laptop would land in the same dashboard as real diners' — skip
// them rather than skew the percentiles.
function isLocalHost() {
    if (typeof window === 'undefined') return true
    const h = window.location.hostname
    return h === 'localhost' || h === '127.0.0.1' || h === '::1' || h.endsWith('.localhost') || h.endsWith('.local')
}

// One Firebase app per page, shared by analytics, performance, and push.
// Resolves to null if the SDK can't load. Memoised.
function ensureApp() {
    if (appPromise) return appPromise
    appPromise = (async () => {
        try {
            const { initializeApp, getApps } = await import('firebase/app')
            return getApps().length ? getApps()[0] : initializeApp(readConfig())
        } catch {
            return null
        }
    })()
    return appPromise
}

// Resolves to the Firebase Analytics instance, or null if it can't be used
// (no config, unsupported browser, or the SDK failed to load). Memoised.
function ensureAnalytics() {
    if (analyticsPromise) return analyticsPromise
    const cfg = readConfig()
    if (!cfg.measurementId) return Promise.resolve(null)

    analyticsPromise = (async () => {
        try {
            // Hold everything — the dynamic import, gtag.js, the first event —
            // behind the caller's gate. track() calls made while it is closed
            // simply chain onto this promise and fire the moment it opens, so
            // deferring costs coverage only for a visitor who leaves before the
            // gate; gtag.js is ~146 KiB, so those events would not have been
            // delivered by then anyway.
            if (startGate) await Promise.resolve(startGate).catch(() => {})

            const [app, { getAnalytics, isSupported }] = await Promise.all([
                ensureApp(),
                import('firebase/analytics'),
            ])
            if (!app) return null
            if (!(await isSupported().catch(() => false))) return null
            return getAnalytics(app)
        } catch {
            return null
        }
    })()

    return analyticsPromise
}

/**
 * Start analytics for the current app. `name` (e.g. 'web', 'landing', 'menu')
 * is attached to every event as an `app` param so a single GA4 property can
 * tell the three front-ends apart. Fire-and-forget; safe to call once at boot.
 *
 * `until` is an optional promise that holds the SDK back until it resolves.
 * GA4 means gtag.js — ~146 KiB transferred — and on the menu app that lands on
 * a diner's phone on mobile data mid-page-load. Pass a promise that resolves
 * after the load event and the page is quiet, and the bytes stop competing with
 * the menu's own images and API call.
 *
 * Call this BEFORE anything can call track(): the first track() starts the SDK
 * on its own, and a gate registered after that has nothing left to hold back.
 */
export function initAnalytics(name, { until } = {}) {
    if (name) appLabel = name
    if (until) startGate = until
    ensureAnalytics()
}

/**
 * Start Firebase Performance Monitoring. Fire-and-forget; safe to call once at
 * boot, and a no-op without a config or on a local host.
 *
 * Automatic instrumentation covers what we actually care about: the page-load
 * trace (TTFB, FCP, DOM-interactive, load), and a trace per outgoing
 * fetch/XHR — so a slow `/api/menu` shows up as a network trace without any
 * per-call wiring. Those are derived from the browser's Performance timeline,
 * which is why starting late (after mount, at an idle moment) still captures
 * the full page load. The one metric that does suffer from a late start is
 * first-input delay, which needs its listener attached before the user's first
 * tap — an acceptable trade for not competing with the app's own chunks.
 *
 * Cost — start it and the page pays for two extra third-party origins before it
 * will record anything:
 *   firebaseinstallations.googleapis.com  (installation id + auth token)
 *   firebaseremoteconfig.googleapis.com/...fireperf:fetch  (sampling config)
 * plus the SDK's own chunks. There is no setting that avoids them:
 * PerformanceController._init() in @firebase/performance calls
 * getInitializationPromise() -> getIidPromise() -> getConfig() unconditionally,
 * and `dataCollectionEnabled` / `instrumentationEnabled` are only consulted
 * later, when a finished trace is about to be dispatched. So those flags
 * suppress the reporting, not the requests. The remote config is cached in
 * localStorage for its TTL, which helps an app people return to and does
 * nothing for a first-time visitor.
 *
 * That is why this is NOT started on the menu app (see apps/menu/src/main.js).
 * It is worth it where a session is long and mostly warm — the dashboard — and
 * not where every load is a cold first visit that we are trying to make fast.
 */
export function initPerformance() {
    if (performancePromise) return performancePromise
    const cfg = readConfig()
    if (!cfg.projectId || !cfg.appId || isLocalHost()) return Promise.resolve(null)

    performancePromise = (async () => {
        try {
            const [app, { getPerformance }] = await Promise.all([
                ensureApp(),
                import('firebase/performance'),
            ])
            return app ? getPerformance(app) : null
        } catch {
            return null
        }
    })()

    return performancePromise
}

/**
 * Time an async operation as a custom performance trace, for the things
 * automatic instrumentation can't see — a multi-request flow, or work that
 * happens after the response lands (e.g. rendering a 300-item menu).
 *
 * Returns whatever `fn` returns and rethrows its errors unchanged: the trace is
 * pure observation, so an unconfigured or failed Performance SDK just means the
 * work runs untimed.
 *
 *   const menu = await measure('menu_load', () => api.get('/menu'))
 */
export async function measure(name, fn) {
    let t = null
    try {
        const perf = await initPerformance()
        if (perf) {
            const { trace } = await import('firebase/performance')
            t = trace(perf, name)
            t.start()
        }
    } catch {
        /* monitoring must never break the page */
    }
    try {
        return await fn()
    } finally {
        try {
            t?.stop()
        } catch {
            /* a failed stop must not mask the real result */
        }
    }
}

/**
 * Log a GA4 event. Never throws — analytics must not be able to break the page.
 * Mirrors to window.dataLayer first so a tag manager (if ever added) still sees
 * the event even when the firebase SDK is absent.
 */
export function track(event, params = {}) {
    const enriched = { app: appLabel, ...params }
    try {
        if (typeof window !== 'undefined' && Array.isArray(window.dataLayer)) {
            window.dataLayer.push({ event, ...enriched })
        }
    } catch {
        /* dataLayer push must never break the page */
    }
    ensureAnalytics()
        .then(async (analytics) => {
            if (!analytics) return
            const { logEvent } = await import('firebase/analytics')
            logEvent(analytics, event, enriched)
        })
        .catch(() => {
            /* analytics must never break the page */
        })
}

/**
 * Record a page view. GA4's enhanced measurement only counts the first load of
 * a single-page app, so SPA route changes have to be reported by hand.
 */
export function trackPageView(path, title) {
    track('page_view', {
        page_path: path,
        page_location: typeof window !== 'undefined' ? window.location.href : path,
        page_title: title ?? (typeof document !== 'undefined' ? document.title : undefined),
    })
}
