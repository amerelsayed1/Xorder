// Firebase Analytics (GA4) — shared across the web, landing, and menu apps.
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
let appLabel = 'app'

function readConfig() {
    return (typeof window !== 'undefined' && window.__FIREBASE_CONFIG__) || {}
}

/** True once a GA4 measurement id is present in the injected config. */
export function analyticsConfigured() {
    return Boolean(readConfig().measurementId)
}

// Resolves to the Firebase Analytics instance, or null if it can't be used
// (no config, unsupported browser, or the SDK failed to load). Memoised.
function ensureAnalytics() {
    if (analyticsPromise) return analyticsPromise
    const cfg = readConfig()
    if (!cfg.measurementId) return Promise.resolve(null)

    analyticsPromise = (async () => {
        try {
            const [{ initializeApp, getApps }, { getAnalytics, isSupported }] = await Promise.all([
                import('firebase/app'),
                import('firebase/analytics'),
            ])
            if (!(await isSupported().catch(() => false))) return null
            // Reuse the app already initialised by push messaging if present.
            const app = getApps().length ? getApps()[0] : initializeApp(cfg)
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
 */
export function initAnalytics(name) {
    if (name) appLabel = name
    ensureAnalytics()
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
