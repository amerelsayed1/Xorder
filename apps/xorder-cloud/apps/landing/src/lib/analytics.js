// Landing-page analytics. `track()` now forwards to the shared @xorder/analytics
// module (Firebase GA4 + window.dataLayer mirror), so these events land in GA4
// with zero changes at the call sites. Still a safe no-op until /firebase-config.js
// carries a measurementId.
//
// Canonical event names (keep in sync with the brief):
//   landing_view_demo_clicked
//   landing_request_demo_clicked
//   landing_whatsapp_clicked
//   landing_lead_submitted
//   landing_package_cta_clicked

export { track } from '@xorder/analytics'
