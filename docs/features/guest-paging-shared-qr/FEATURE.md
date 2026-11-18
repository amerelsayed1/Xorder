# One shared QR for guest paging: the client types the number on their slip: guest-paging-shared-qr

Status: proposed (**revised 2026-11-18**; the first version used a PIN the cashier types, which the owner rejected) · Source: the user's request, "it should be one QR code for all of this, not create new QR code for every order", then "I think pin code will make it so bad", then "switch to the slip number" · Verified against: monorepo `e3dba8e8` (cloud and POS source) and `origin/main` `8d5a85b9` (the order-number page, live)

Builds on `docs/features/guest-paging/` (S1 and S2 built, S3 live). Replaces that plan's per-order receipt QR (S6).

## 1. Summary
Every client scans the **same QR code** (printed once, on a counter sign). The page asks them to **type the number on their slip**. It finds their order, shows their order number and its status, and alerts them when it is ready. The cashier does nothing extra: no QR per order and no code to type.

## 2. Why
A QR on every receipt needs a printer change and a printed code for each sale. A PIN the cashier types adds a step for both sides during a rush. How comparable products do it (researched 2026-11-18, vendor claims): [TokenPager](https://tokenpager.com) uses one standing QR and the guest types the token on their ticket, with no phone number; Pingloy's POS FAQ says the scan opens the order the receipt number names. Most useful for cafés, quick-service counters and food trucks (pay first, wait nearby).

## 3. Goal and success
A client scans the standing QR, types the number from their slip, and sees their order and its status, with no extra work at the till. Success: a typed number finds exactly the client's own order of today, a wrong or unknown number never shows anyone else's order, and the cashier's workflow is unchanged.

## 4. Users, roles and permissions
| Who | Does | Permission |
|---|---|---|
| Client (anonymous) | Scans, types the slip number, watches the status | none |
| Cashier | Nothing new. Marks Ready as planned for guest paging (dashboard now, till later) | existing |
| Owner / manager | Downloads the standing QR from the dashboard | `settings.view` (as the restaurant QR today, `TenantCapability.php:78-80`) |
| Super admin | Turns `guest_paging` on per plan | existing plan form |

No permission is narrowed.

## 5. Today
- **Per-order token model** (S1 and S2): an order can hold a 40-character `pickup_token`, `pickup_status` and `pickup_display_ref`; the public tracking API and the order-number page (`/menu/o/{token}`) read them (`GuestPagingService.php`, `routes/api.php:977ff`, `apps/menu/src/tracking/TrackingApp.vue`). Live and tested on the demo restaurant.
- **The number on a till slip is the invoice number**, `{branch code}-{year}-{6 digits}` such as `MAIN-2026-000042`, allocated by the platform for cloud tills (`InvoiceSequenceService.php:11-12`, sequenced per tenant, branch and period, +1 per order) and stored on the order (`PosOrderResource.php:35`).
- **No short daily order number exists in this tree.** `09b47ec6` ("order number shared by every till, restarting each trading day", XORD-036, `docs/features/shift-order-number/`) is on the old repo's branch `feat/day-order-number` and was never merged into `origin/main`. It targets the offline branch server; its QA note says cloud tills would need the cloud to allocate it as a separate item, and its sync payload is unchanged.
- **UNVERIFIED:** whether the slip a cloud-flavor till prints shows the invoice number at the moment of sale, or only after the sale has synced (the receipt code has a "queued" state, `receipt_data.dart:170`). **This must be checked on a real till and a real print before building.**
- No POS paging code exists (`apps/xorder-pos` has only order-type labels for "pickup").
- A QR-menu order already gets a tracking link in its own response; unchanged by this feature.
- `docs/FEATURE_INVENTORY.md` has no `guest-paging` row.

## 6. Scope
**In:** one standing QR per restaurant; a join page where the client types the slip number; a cloud lookup of today's paged POS order by that number; handing the phone the order's existing tracking token; the existing order-number page reused; the dashboard download of the standing QR.
**Out:** a QR per order or on receipts; any PIN or code for the cashier; any POS change (see decision D5); SMS or WhatsApp; web push to a closed page (S8); a short daily order number (XORD-036 stays a separate item); free-form messages; hardware pagers.

## 7. Behavior and business rules
- **BR-1** One standing QR per restaurant, separate from the menu QR (D3), opens the join page on the restaurant's own host (under `/menu/`, so the server already routes it).
- **BR-2** The client types the number from the slip. Digits alone mean "the order number at the end of the invoice number": `42` matches `MAIN-2026-000042`. Leading zeros and Arabic-Indic digits do not matter. The full invoice number as printed is also accepted.
- **BR-3** The cloud looks only at **this restaurant's POS orders of the last 12 hours** whose type is paged (`GuestPagingService::isEligible`). Anything else is "not found".
- **BR-4** One match: the order gets its tracking token and `PREPARING` state if it has none, and its display reference (the order number as the client typed it, without leading zeros). The phone goes to `/menu/o/{token}` (the existing page, which already alerts and has "On my way").
- **BR-5** No match yet (a sale still on its way to the cloud) says "not found yet": the page lets the client try again, and does so on its own for a short time.
- **BR-6** More than one match (two branches share a tail number) says "ambiguous": the page asks for the full number as printed.
- **BR-7** Several phones may follow one order (a family). There is no session and no code to free.
- **BR-8** Nothing personal is shown or stored: the page shows the order's status and number, as the order-number page does today.
- **BR-9** Lookups are rate-limited per address, with room for a busy counter's shared Wi-Fi.
- **BR-10** The per-order receipt QR (S6) is not built. Existing tracking links keep working.

## 8. Acceptance criteria
- **AC-1** Given a paged POS order of the last 12 hours, when the client types `42` (or `000042`, or the full `MAIN-2026-000042`), then the lookup returns that order's tracking token and the page goes to the order-number page. *(cloud feature test, a person on a phone)*
- **AC-2** Given Arabic-Indic digits, then the same order is found. *(cloud feature test)*
- **AC-3** Given a number that matches no order, or an order of another restaurant, then the answer is "not found" and reveals nothing about other restaurants. *(cloud feature test, cross-tenant)*
- **AC-4** Given an order older than the window, or of a type that is not paged, then it is not found. *(cloud feature test)*
- **AC-5** Given a found order without a token, then it gets one and starts `PREPARING`; given one that already has a token (a QR-menu order), the same token is returned. *(cloud feature test)*
- **AC-6** Given two orders with the same tail number in two branches, then the answer is "ambiguous", and the full invoice number finds the right one. *(cloud feature test)*
- **AC-7** Given the same lookup twice, then the same token comes back and nothing changes. *(cloud feature test)*
- **AC-8** Given the feature off, then the join page and the lookup answer "not available". *(cloud feature test)*
- **AC-9** Given the rate limit is exceeded, then the lookup answers 429. *(cloud feature test)*
- **AC-10** Given a found order, when it becomes READY, then the page shows Ready, rings and vibrates, and "On my way" works. *(reuses S3; a person on a phone)*
- **AC-11** Given the join page in Arabic and English, then it opens in the restaurant's language, right-to-left where needed. *(build, a person)*
- **AC-12** Given a real till sale, then the slip carries the number the client is asked to type, at the time it is handed over. *(a person, a real print: see section 5)*

## 9. Edge cases and failure modes
- **A client types the number before the sale reaches the cloud:** "not found yet", retry (BR-5). A cloud-flavor till drains within seconds when online and later when offline; an offline till's orders appear after it reconnects.
- **Guessing:** the numbers count up, so anyone can try numbers. The page shows only status and number, never a name, items or phone. A prankster could tap "On my way" on someone else's order; low harm, documented. Rate limit and the 12-hour window bound it.
- **Two branches, one restaurant:** the same tail number can exist in both (BR-6). A single-branch restaurant never sees this.
- **Day boundary:** the 12-hour window keeps a client who ordered just before midnight working.
- **High volume:** with the 12-hour window, a restaurant with more than a thousand orders in that time and one branch could still have a clash only if invoice numbers wrapped, which they do not (they count up for the year).
- **Arabic and RTL:** the page opens in the restaurant's language; the typed number accepts any digit style.
- **Offline-flavor restaurants:** their sales never reach the cloud, so this feature cannot find their orders. Cloud-flavor only.
- **Plan:** gated by the existing `guest_paging` flag.

## 10. Impact
- **Cloud API** (`apps/xorder-cloud/apps/api`): one new public endpoint, `POST public/restaurants/{slug}/pager-lookup`, reusing `GuestPagingService`; tests. **No migration, no new table.**
- **Menu app** (`apps/menu`): the join page becomes a number box (the first version showed a code); reuses the order-number page.
- **Dashboard** (`apps/web`): a "Counter QR" download.
- **POS:** **no change**, unless the print check in AC-12 fails (then the slip must show the number: a separate, small POS change).
- **Contract:** none (the POS-BE-035 proposal written for the PIN design is withdrawn).
- **Localization:** English and Arabic for the join page and the dashboard.
- **Documentation:** this folder; the PIN-design work (PR 16 and the join-page branch) is superseded.
- **Deploy order:** cloud, then the menu app and dashboard. No POS release.

## 11. Dependencies, known gaps, risks
- **Depends on:** guest paging S1 to S3 (live); the slip showing the invoice number (AC-12); the cloud having the sale (cloud flavor).
- **Known gaps:** the short daily order number (XORD-036) is unmerged; web push to a closed page is S8; the moving-truck model.
- **Risks:** the slip may not show the number in time (checked first); a long printed number is harder to type than a short one; guessing (low harm); two-branch clashes.

## 12. How it will be tested
Cloud feature tests (SQLite): AC-1 to AC-9. Front-end: `pnpm build` plus a person on a phone for AC-1, AC-10 and AC-11 (no JavaScript test framework exists). A person with a real till for AC-12. Not provable by tests: the printed slip, a real rush, the phone alert.

## 13. Decisions and open questions
**Decided (2026-11-18, by the user):**
- **D1** One standing QR for everyone, not a QR per order.
- **D3** The standing QR is a separate counter QR; the menu QR and table QRs stay as they are.
- **D4** The client links their phone by typing the number on their slip. **This replaces the earlier D2** (the cashier types a PIN), which the owner rejected after seeing how comparable products work.

**Decided as my default (2026-11-18, owner to confirm):**
- **D5** The number is the digits at the end of the invoice number already on the slip (`…000042` is "42"). It needs no POS change. A short daily order number (XORD-036) can replace it later without changing the page.

**Still open:**
- **OQ-1** Does the slip a cloud till prints show the invoice number at the moment of sale? (AC-12; decides whether any POS change is needed.)
- **OQ-2** Lookup window of 12 hours: right, or longer?
- **OQ-3** Should the page also let a client who typed a wrong number correct it more easily, for example by showing the last few numbers of the day? Suggestion only: not recommended (it would reveal other orders).
