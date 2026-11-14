// Funnel events for the guest menu. `track()` now forwards to the shared
// @xorder/analytics module (Firebase GA4 + window.dataLayer mirror), so these
// events land in GA4 with no changes at the call sites. Safe no-op until
// /firebase-config.js carries a measurementId. Mirrors apps/landing/src/lib/analytics.js.
//
// Canonical event names:
//   menu_viewed        { slug }
//   menu_add_to_cart   { slug, kind }
//   menu_order_submitted { slug, total, items }

export { track } from '@xorder/analytics'
