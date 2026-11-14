# Changelog — live-board-to-pos

## 2026-11-10 — implemented in the working tree (uncommitted, not pushed)
- **Cloud API:** `OrderStatus::PENDING`; WhatsApp checkout records a pending order (needs a phone number); `POST dashboard/orders/{id}/accept|reject` (idempotent, `orders.update`); `pending_orders` in `orders/new-count` and the list summary; dashboard order queue opens to `whatsapp_ordering` plans; PENDING excluded from stats, insights, reports and the pickup board; `live.view` capability removed (enum and gates) with data migration `2026_11_10_000100_remove_live_view_from_roles` (written, not run on any real database). No schema change (status is a string column).
- **Menu SPA:** WhatsApp-only checkout posts the order and shows "waiting for confirmation"; it no longer opens a `wa.me` message to the restaurant at checkout.
- **Dashboard SPA:** Pending tab, Accept and Reject on the order row, "Message on WhatsApp" button on decided WhatsApp orders; Live board page, nav entry, badge and translations removed; `/admin/live` redirects home; bill-request bell link goes home.
- **After review:** pulse/badge/toast count pending orders; insights and `orders_today` exclude them; the generic status route refuses a PENDING order; accept/reject are audited; old migration `2026_08_23_000400` no longer references the removed enum case.
- **Not done:** removing the dashboard table-floor, visit-finish and bill-request routes (AC-2); POS side and delivery ringing in both places (AC-3, AC-4).
