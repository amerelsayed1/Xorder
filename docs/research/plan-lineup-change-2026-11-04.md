# Production plan lineup change, 2026-11-04

Owner's request (2026-11-04): apply the four-plan lineup from `reports/Restaurant SaaS plan pricing MENA.md` to the existing production plans, and move the existing clients to Business. Applied through the super-admin portal (https://admin.xorder.io), not by migration.

## Before (read from the admin API at about 09:00 Cairo time)

| id | Name | Features | Limits | Active | Recommended | Sort |
|---|---|---|---|---|---|---|
| 4 | المحترف | qr_menu, internal_reviews, product_analytics, multi_branch, pos, purchasing | all unlimited (null) | yes | yes | 0 |
| 1 | باقة البداية | qr_menu | all unlimited | yes | no | 1 |
| 2 | باقة المتقدمة | qr_menu, whatsapp_ordering, pickup, delivery | all unlimited | yes | no | 2 |
| 3 | باقة الاحتراف | qr_menu, whatsapp_ordering, system_ordering, customer_tracking, table_management, bill_requests, internal_reviews, product_analytics, dine_in, pickup, delivery, multi_branch | all unlimited | yes | no | 3 |

All prices null (shown as "contact us"), currency EGP.

| Restaurant | Plan | Status | Subscription dates | Ordering mode | Branches / items / categories | POS licence |
|---|---|---|---|---|---|---|
| 16 demo (Good Cafe) | باقة الاحتراف (moved from المحترف at 07:52 Cairo, before this change) | ACTIVE | 2026-09-27 to 2026-12-31 | whatsapp | 1 / 46 / 9 | #6 active, max 1 terminal, expires 2027-11-03 |
| 17 cocoffe | باقة الاحتراف | TRIAL | 2026-07-28 to 2026-11-30 | system | 1 / 253 / 27 | none |

Both restaurants' features were exactly plan 3's list above.

## Planned after

| id | New name | Features | Branches / items / categories / staff / terminals | Recommended |
|---|---|---|---|---|
| 1 | منيو | qr_menu | 1 / 150 / 20 / 2 / 0 | no |
| 2 | واتساب | qr_menu, whatsapp_ordering, pickup, delivery | 1 / 300 / 40 / 3 / 0 | no |
| 3 | المطعم | qr_menu, system_ordering, dine_in, table_management, bill_requests, pickup, delivery, customer_tracking, internal_reviews, product_analytics, pos | 1 / 1,000 / 100 / 10 / 1 | yes |
| 4 | الأعمال | everything in المطعم plus multi_branch, purchasing | 3 / 3,000 / 300 / 30 / 3 | no |

Prices stay null: not part of this change.

Expected effects: both restaurants move to الأعمال. cocoffe keeps system ordering and gains pos and purchasing. demo regains pos and purchasing, keeps tables, and its menu checkout switches from WhatsApp to system orders because Business has no WhatsApp ordering. demo's POS licence (max 1 terminal) still caps its tills, since a licence cap wins over the plan cap.

## Applied

Done on 2026-11-04 through the admin API the portal's own forms call (`PUT api/admin/plans/{id}`, `PATCH api/admin/restaurants/{id}/subscription`), signed in as the super admin in Chrome. Every call returned HTTP 200.

1. Plans updated exactly as in "Planned after", in the order 4, 3, 1, 2. One difference: the server rejects a terminal limit of 0 (minimum 1), so منيو and واتساب keep it empty (unlimited). Neither has the pos feature, so they cannot pair a till anyway.
2. cocoffe (17) moved to الأعمال with status TRIAL and dates 2026-07-28 to 2026-11-30 resent unchanged. Features now: qr_menu, system_ordering, customer_tracking, table_management, bill_requests, internal_reviews, product_analytics, dine_in, pickup, delivery, multi_branch, pos, purchasing. Ordering mode stays system.
3. demo (16) moved to الأعمال with status ACTIVE and dates 2026-09-27 to 2026-12-31 resent unchanged. Same 13 features. Ordering mode changed from whatsapp to system, so the public menu checkout now sends orders to the dashboard instead of opening WhatsApp.

## Checked after

- demo dashboard sidebar (https://demo.xorder.io/admin, signed in as the owner): Tables, the live tables-and-orders board, inventory, purchasing and suppliers now appear.
- demo POS licence #6 still active, max 1 terminal, expires 2027-11-03.
- Public pricing data (`api/public/landing-content`, `data.pricing.plans`) lists منيو, واتساب, المطعم, الأعمال in that order, with no prices.

## Not checked

- cocoffe's dashboard and public menu were not opened (no session for that restaurant).
- How many staff accounts each restaurant has (the admin users endpoint only lists platform users), so the new staff caps (30 on الأعمال) were not compared with real counts.
- demo's desktop POS was not opened after the change.

## To reverse

Put each plan back to the "Before" table with the same endpoint (names, feature_keys, null limits, plan 4 recommended, sort 0-3), then move demo and cocoffe back to "باقة الاحتراف" via the Subscription endpoint with their status and dates. demo was on "المحترف" until 07:52 Cairo time the same morning.
