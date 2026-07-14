// Funnel events for the guest menu, pushed to window.dataLayer (GTM/GA4
// style) when a tag manager is installed — console-logged in dev otherwise.
// Mirrors apps/landing/src/lib/analytics.js.
//
// Canonical event names:
//   menu_viewed        { slug }
//   menu_add_to_cart   { slug, kind }
//   menu_order_submitted { slug, total, items }

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
        /* analytics must never break the menu */
    }
}
