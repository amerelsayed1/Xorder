// Lightweight analytics hook for the landing page. Events are pushed to
// window.dataLayer (Google Tag Manager / GA4 style) when present, so a future
// tag manager picks them up with zero code changes here. In dev, or when no
// tag manager is installed, events are logged to the console for verification.
//
// Canonical event names (keep in sync with the brief):
//   landing_view_demo_clicked
//   landing_request_demo_clicked
//   landing_whatsapp_clicked
//   landing_lead_submitted
//   landing_package_cta_clicked

export function track(event, params = {}) {
    const payload = { event, ...params }
    try {
        if (typeof window !== 'undefined' && Array.isArray(window.dataLayer)) {
            window.dataLayer.push(payload)
        } else if (import.meta.env.DEV) {
            // eslint-disable-next-line no-console
            console.debug('[analytics]', payload)
        }
    } catch {
        /* analytics must never break the page */
    }
}
