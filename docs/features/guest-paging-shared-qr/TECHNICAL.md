# One shared QR, client types the slip number: technical plan (guest-paging-shared-qr)

Status: **built 2026-11-18 (stages C1 to C3, uncommitted); P0 (the real print check) still open** · Spec: `FEATURE.md` (same folder) · Verified against monorepo `e3dba8e8` and `origin/main` `8d5a85b9`
Repos touched: cloud API, menu app, dashboard (`apps/xorder-cloud`). **POS: none** (unless the print check, AC-12, fails). **No migration, no new table.**
This replaces the PIN-pairing plan written earlier the same day. That design was built (cloud half, PR 16; a join page on a local branch) and is **superseded**: nothing from it needs merging.

## 1. Facts this plan rests on
| Fact | Source |
|---|---|
| The number on a till slip is the invoice number `{branch code}-{year}-{6 digits}`, platform-allocated, +1 per order per branch and year, stored on the order | `InvoiceSequenceService.php:11-12,26-46`, `PosOrderResource.php:35` |
| A cloud-flavor till posts each sale to `POST pos/orders`, which creates a cloud order with that invoice number; only the cloud flavor syncs sales | `routes/api.php:856-858`, `PosOrderService.php`, `deployment.dart:70` (POS analysis) |
| An order becomes "paged" by getting `pickup_token`, `pickup_status`, `pickup_display_ref`; `GuestPagingService::isEligible` decides which orders qualify (flag on, paged type, not a seated table round) | `GuestPagingService.php:32-55`, `PublicOrderController.php:160-166` |
| The order-number page and its API already read an order by its token and do the ready alert and "On my way" | `PublicOrderTrackingController.php`, `TrackingApp.vue` |
| The short daily order number (XORD-036) is **not** in this tree: unmerged commit `09b47ec6` on the old repo's `feat/day-order-number`, built for the offline server | `git log pos-src/feat/day-order-number`, `docs/features/shift-order-number/FEATURE.md` |
| **UNVERIFIED:** the slip a cloud till prints may show the invoice number only after the sale syncs (a "queued" receipt state exists) | `receipt_data.dart:170`, `receipt_dialog.dart:90-103` |

## 2. Reuse
`GuestPagingService` (`isEligible`, `generateToken`) · `PublicOrderTrackingController` and the order-number page, unchanged · `Digits::latin` · `PublicImageUrl::relative` · `QrCodeService` for the standing QR · the join-page chunk, styles, strings and entry switch already written on `feat/guest-paging-shared-qr-join-page` (the number box replaces the code display) · `MenuShellController`'s `noindex` for `/menu/p` (same branch) · the named-limiter pattern in `routes/api.php`.

## 3. Design in one paragraph
The join page (`/menu/p`) shows a number box. The client types what is at the end of the invoice number on their slip. The page calls one public endpoint; the cloud looks through this restaurant's paged POS orders of the last 12 hours for one whose invoice number ends with that number (or equals the full number typed). A match gets a tracking token (if it has none), and the phone goes to `/menu/o/{token}`.

## 4. Stages
**C1: lookup (cloud).** New `PagerLookupService::find(Restaurant, string)`: normalize the input (fold Arabic-Indic digits, trim; digits only means "tail", anything else is the full invoice number compared case-insensitively and ignoring spaces and dashes); candidates are this restaurant's orders with `channel = pos`, `invoice_number` not null, created in the window (config `platform.guest_paging.lookup_window_hours`, default 12), capped at a safe number; filter in PHP: tail digits equal as integers (so `42` equals `000042` and not `1042`), and `isEligible`. Zero matches: `not_found`; two or more: `ambiguous`; one: bind it. Binding sets `pickup_token`, `pickup_status = PREPARING` and `pickup_display_ref` (the number without leading zeros) when the order has none, inside a short transaction under a row lock, and is idempotent. Two public routes under `public/restaurants/{slug}/pager-lookup`: `GET` returns the restaurant's name, language and brand (so the page opens in the right language before anything is typed), and `POST {number}` returns `200 found` with `tracking_token`, `404 not_found`, or `409 ambiguous`. Both require the restaurant to be visible and to hold `guest_paging` (403 otherwise). A named limiter keyed per address, generous for a shared counter Wi-Fi. Tests: AC-1 to AC-9 (tail, leading zeros, full number, Arabic digits, wrong restaurant, outside the window, non-paged type, an order that already has a token, two branches, repeat lookup, feature off, rate limit).

**C2: join page (menu app).** Rework `JoinApp.vue` and replace `usePagerSession.js` with `usePagerLookup.js`: on load `GET` the info (language and brand; no words until known); a numeric-keyboard box and one button; on `found` go to `/menu/o/{token}`; on `not_found` say "we can't find that number yet; if you just paid, wait a few seconds" with the button as retry and a few automatic retries; on `ambiguous` ask for the full number as printed and switch the box to text. English and Arabic strings (the pairing strings are replaced), the restaurant's language like the order-number page, `noindex`. Check: `pnpm build` and a person on a phone (AC-1, AC-10, AC-11). No JavaScript test framework exists.

**C3: dashboard Counter QR.** Route `GET dashboard/pager-qr` (SVG and PNG download) for `https://{slug}.xorder.io/menu/p`, `settings.view` plus `feature:guest_paging`; a small page in the web app with print guidance; English and Arabic. Test: right restaurant only (cross-tenant 404).

**C4: docs.** FEATURE (done), TECHNICAL (as built), API, DATABASE ("no change"), TEST_PLAN, TEST_REPORT, CHANGELOG; inventory row; supersede the PIN docs.

**P0: a real print check (a person, before relying on any of this).** Take a sale on a real cloud-flavor till, online and with the cloud unreachable, and look at the slip: is the invoice number on it at the moment of sale? If yes, nothing else. If it appears only later, the POS needs a small change to show the number (or the daily order number from XORD-036 must land): a separate item, and then this feature waits for it.

## 5. Verification
Cloud: `cd apps/xorder-cloud/apps/api && php artisan test --filter Pager` then the full suite and `./vendor/bin/pint --test` (throwaway `APP_KEY` and `JWT_SECRET` needed locally). Front-end: `cd apps/xorder-cloud && pnpm build`. The join page is checked in the browser pane against a local mock of the lookup endpoint. Not provable by tests: the printed slip, a rush, the phone alert.

## 6. Compatibility and rollout
Nothing existing changes shape. One new public endpoint and one new route's page; the order-number page and its API are untouched. No migration, no POS release. Order of delivery: cloud (C1), then menu (C2) and dashboard (C3). Rollback: `./deploy.sh --rollback` restores the previous code (nothing was added to the database).

## 7. Venue models
**Café and quick-service counter, food truck with signal:** helped. **Restaurant with table service:** not for dine-in. **Cloud kitchen:** not applicable. **Offline-flavor tills:** their sales never reach the cloud, so they cannot use it. The moving-truck model is a known gap, not touched.

## 8. Risks
- **The slip may not show the invoice number in time** (P0): the main unknown; it can force a POS change.
- **A long printed number is harder to type** than a short one; typing only the last digits is the mitigation, and a short daily number (XORD-036) is the proper fix.
- **Guessing:** sequential numbers can be tried; only status and number are visible, and the lookup is rate-limited and windowed.
- **Two branches with the same tail:** the page asks for the full number.
- **A lookup before the sale reaches the cloud** finds nothing; the page retries.

## 9. Approvals needed before building
1. A new branch from `origin/development`; no commit or push until you say so; nothing reaching `main` without `/release-check`.
2. **No migration and no POS change are involved.** One new public endpoint and one new authenticated dashboard route.
3. **Close PR 16** (the superseded PIN design), and drop the unmerged join-page branch.
4. A person to run P0 on a real till.

## 10. Open questions (defaults chosen)
- Window of 12 hours; the number is the digits at the end of the invoice number; the full number is also accepted.
- A single branch needs nothing more; a multi-branch restaurant may be asked for the full number.

## As built (2026-11-18)
Matches the plan, with these small differences:
- The lookup is two calls on one path: `GET …/pager-lookup` (restaurant name, language and brand) and `POST …/pager-lookup` (`PagerLookupService`).
- The join page retries a "not found yet" lookup by itself up to 6 times, 5 seconds apart, so a sale still on its way to the cloud is found without a tap.
- The Counter QR lives under Settings, in the same group as Branches and Dining areas, behind `feature:guest_paging` and `settings.view`.
- `MenuShellController` also sends `X-Robots-Tag: noindex` for `/menu/p`.
Not done: P0 (a person checks a real slip), and a look at the Counter QR page in a browser.
