# One shared QR for guest paging — guest-paging-shared-qr

Status: proposed · 2026-11-18 · Source: the user's request, "it should be one QR code for all of this, not create new QR code for every order", then, asked how the page should find the client's order, "Cashier enters the client's code at the till" · Verified against: monorepo `e3dba8e8` (cloud and POS are one repo; paging backend and POS read from this tree) and `origin/main` `8d5a85b9` (the order-number page, built and deployed 2026-11-18)

Builds on `docs/features/guest-paging/` (S1 and S2 built, S3 deployed). It replaces that plan's per-order receipt QR (S6) with one standing QR plus a pairing code.

## 1. Summary
Every client scans the **same QR code** (printed once, on a poster or counter sign). The page that opens shows the client a **short code**. The cashier types that code into the POS when taking the order. From then on the client's page shows **their order number and its status**, and alerts them when the order is ready. No QR is printed per order.

## 2. Why
The first design printed a new QR on every receipt (S6). The owner does not want that: a QR per order means a printer change and a printed code for every sale. Most useful for **cafés, quick-service counters and food trucks** (pay first, wait nearby). Not for table service or cloud kitchens.

## 3. Goal and success
A client scans the standing QR, reads out a short code, and from then on sees their own order number and live status on their phone, with no QR printed per order. Success: a code can be paired to exactly one order; a wrong or expired code never blocks a sale; no client can see another client's order unless the code was entered for it.

## 4. Users, roles and permissions
| Who | Does | Permission |
|---|---|---|
| Client (anonymous) | Scans, gets a code, watches the status | none; holds a secret kept on their own phone |
| Cashier on the POS | Types the client's code when taking the order | the till session, as for any order (a new till permission: **UNVERIFIED**, not planned) |
| Owner / manager on the dashboard | Downloads the standing QR | `settings.view` (same as the restaurant QR today, `TenantCapability.php:78-80`) |
| Super admin | Turns `guest_paging` on per plan | existing plan form |

No permission is narrowed.

## 5. Today
- **Per-order token model:** an order gets a 40-character `pickup_token`, `pickup_status` and `pickup_display_ref` (`GuestPagingService.php`, migration `2026_11_02_000100_add_guest_paging_to_orders_table.php:40-65`). The public tracking endpoints are `GET/POST public/orders/track/{token}[/follow|/ack]` (`routes/api.php:977ff`, `PublicOrderTrackingController.php`). The order-number page at `/menu/o/{token}` (`apps/menu/src/tracking/TrackingApp.vue`) reads them. All of this is keyed by the per-order token and already works (verified live on the demo restaurant 2026-11-18).
- **QR-menu orders** already get a tracking link in the order response, no printing involved; unchanged by this feature.
- **No POS paging code exists:** a search of `apps/xorder-pos` for the token, the paging flag or a pickup event finds only order-type labels in the history screens. S5 to S7 were planned and never built.
- **The POS creates cloud orders** through `POST pos/orders`, `GET pos/orders/by-client-id/{uuid}` and `POST pos/orders/{order}/payments` (`routes/api.php:856-858`). The exact payload and the offline path are **UNVERIFIED**.
- **Contract drift:** the guest-paging docs name `POS-BE-033`/`034` for the paging contract, but `POS-BE-033` in the ledger is the waiter wire and the till's incoming feed (`apps/xorder-pos/docs/coordination/BACKEND_TO_POS.md:225`, `POS_TO_BACKEND.md:2278`). A new, free contract ID is needed before any POS work; which number is free is **UNVERIFIED**.
- `docs/FEATURE_INVENTORY.md` has no `guest-paging` row.

## 6. Scope
**In:** one standing QR per restaurant; a join page that issues a pairing code and then shows the order; the cloud pairing store and claim; the POS field for the code; the existing order-number UI reused after pairing; the dashboard download of the standing QR.
**Out:** a QR per order or on receipts; SMS or WhatsApp; web push to a closed page (S8); the prep-time report (S9); free-form messages from the cashier; changing QR-menu orders or table QRs; any hardware pager.

## 7. Behavior and business rules
- **BR-1** One standing QR per restaurant, separate from the menu QR (D3), opens a join page on the restaurant's own host (the path is decided in the plan, under `/menu/` so the existing server routing serves it).
- **BR-2** Opening the join page creates a **pairing session**: a short **code** (a human handle, unique among the restaurant's open sessions) and a long **secret** kept only on the client's phone. The code alone never lets anyone read an order.
- **BR-3** The page shows the code large, with "tell the cashier your code", and waits.
- **BR-4** When the cashier enters the code with an order, the cloud binds that session to that order. It succeeds only if the code is open and unexpired, belongs to the **same restaurant** as the till, the order is eligible for paging (`GuestPagingService::isEligible`), and neither the code nor the order is already bound. Repeating the same claim for the same order is harmless.
- **BR-5** After binding, the page shows the order number (`ref`) and the existing states (preparing, ready, picked up, cancelled) with the ready alert and "On my way" (the S3 page).
- **BR-6** An unclaimed code expires after a set time. A client who scans again within that time gets the same code back.
- **BR-7** An unknown, expired or already-used code at the till **never blocks the sale**. The order goes through unpaged, and the till says the code was not found.
- **BR-8** No personal data is stored: no name, phone, IP address or device fingerprint. A session holds the code, a hash of the secret, the restaurant, timestamps and, once bound, the order.
- **BR-9** Code creation and claim attempts are rate-limited; many clients share one venue Wi-Fi address, so the limits must allow a rush.
- **BR-10** The per-order receipt QR (guest-paging S6) is not built. Existing tracking links and the order-number page for QR-menu orders keep working.

## 8. Acceptance criteria
- **AC-1** Given the feature on, when a client opens the join page, then a session and a code are created and the code is shown. *(cloud feature test, menu build, a person on a phone)*
- **AC-2** Given an open code, when the till claims it for an eligible order of the same restaurant, then the session is bound and the client's page shows that order's number and status. *(cloud feature test)*
- **AC-3** Given a bound code, when it is claimed again for a different order, then it is refused. *(cloud feature test)*
- **AC-4** Given the same claim repeated for the same order, then it succeeds without changing anything. *(cloud feature test)*
- **AC-5** Given an unknown or expired code, when the till claims it, then the answer says "not found" and the order itself is not affected. *(cloud feature test, POS test)*
- **AC-6** Given a code of restaurant A, when a till of restaurant B claims it, then it is "not found" (cross-tenant). *(cloud feature test)*
- **AC-7** Given an order whose type is not paged, or a seated-table round, then the claim is refused. *(cloud feature test)*
- **AC-8** Given a bound session, when the order becomes READY, then the page shows Ready, rings and vibrates, and "On my way" works. *(reuses S3; a person on a phone)*
- **AC-9** Given a client who closes the page and scans again before the code expires, then they get the same code. *(cloud feature test)*
- **AC-10** Given two clients scanning at once, then their codes differ. *(cloud feature test, concurrency)*
- **AC-11** Given a session's secret that does not match, then reading it answers 404 (no information about other sessions). *(cloud feature test)*
- **AC-12** Given Arabic-Indic digits typed at the till, then they are read as the same code. *(POS test)*
- **AC-13** Given the join page in Arabic and English, then it opens in the restaurant's language, right-to-left where needed. *(build, a person)*
- **AC-14** Given the rate limits are exceeded, then the endpoints answer 429 and nothing is created. *(cloud feature test)*
- **AC-15** Given the feature off for a restaurant, then the join page and the claim answer as "not available". *(cloud feature test)*

## 9. Edge cases and failure modes
- **POS offline:** the claim needs the cloud. If the till is offline, the pairing is delayed until its outbox drains, or skipped. Which flavor does what is **UNVERIFIED** (cloud flavor talks to the cloud directly; the offline flavor syncs later). A food truck with weak signal is the hard case, on the client's phone too.
- **Wrong pairing:** a cashier who mistypes a code pairs the order to a stranger. The client sees a number that is not on their slip and can scan again. Whether staff can unlink a pairing is an open question.
- **Idempotency and retry:** the till may retry a claim after a timeout (same order, same result).
- **Tenant boundary:** the page's restaurant comes from its own host; the claim's restaurant from the till's credentials; they must match.
- **Lost phone data:** if the client clears the page's storage, they lose the secret and must scan again (a new code); the old session expires.
- **Digits:** the client sees ASCII digits; the till accepts Arabic-Indic digits too.
- **Code space and rush:** the code must stay short enough to say aloud, and a busy venue must not run out of free codes; expired and used codes return to the pool.
- **Plan and licence:** gated by the existing `guest_paging` flag; the POS side is gated by its own switch, off by default.
- **Large data:** old sessions must be pruned.

## 10. Impact
- **Cloud API** (`apps/xorder-cloud/apps/api`): a new public pair of endpoints (create or resume a session, read it by secret); a claim path for the till (a field on `POST pos/orders`, or a separate claim call: decided in the plan); a new table for sessions and a nullable link on orders; pruning; tests. Additive.
- **Menu app** (`apps/menu`): the join page, reusing the S3 order UI after pairing.
- **Dashboard** (`apps/web`): a place to download the standing QR (reusing `QrCodeService`).
- **POS** (`apps/xorder-pos`): a code field when taking an order, the cloud call, error handling, outbox behavior, Arabic digits; behind a switch, off by default.
- **Contract:** a new POS-BE item, **PROPOSED**, with its ID to be allocated (see section 5). Integrate only once it is READY.
- **Data:** one new table and one nullable column, additive; SQLite for tests and PostgreSQL in production, no engine-specific SQL.
- **Localization:** English and Arabic for the join page, the dashboard strings and the POS.
- **Documentation:** this folder (seven files), an inventory row, a coordination entry in both repos.
- **Deploy order:** cloud first (flag-gated, additive), then the menu app, then a POS release with its switch off.

## 11. Dependencies, known gaps, risks
- **Depends on:** guest paging S1 to S3 (live); the POS order-creation call; a free contract ID.
- **Known gaps:** no POS paging code at all; no web push yet (S8); the moving-truck model (`FOOD_SERVICE_DOMAIN.md:50`).
- **Risks:** a mistyped code pairs the wrong client; an offline till cannot pair; two apps and two deploy tracks; many clients behind one Wi-Fi address and the rate limits; the cashier's extra step during a rush.

## 12. How it will be tested
Cloud feature tests in `apps/api/tests/Feature` (SQLite): AC-1 to AC-7, AC-9 to AC-11, AC-14, AC-15. POS unit tests: AC-5 and AC-12, and the claim call against a fake. Front-end (no test framework): build plus a person on a phone for AC-1, AC-8 and AC-13. The full cloud suite and the POS analyzer and tests must stay green. Not provable by tests: the real till flow in a rush, offline behavior, the phone alert.

## 13. Decisions and open questions
**Decided (2026-11-18, by the user):**
- **D1** One standing QR for everyone, not a QR per order.
- **D2** The cashier types the client's code at the till. (Chosen over the client typing the number from the slip, and over the client typing a phone number.)
- **D3** The standing QR is a **separate QR for the counter** (a poster or window sign) that opens the join page directly. The menu QR and table QRs stay as they are.

**Still open:**
- **OQ-2** Code length and lifetime. Suggestion: 4 digits, unclaimed codes expire after 30 minutes.
- **OQ-3** One QR per restaurant or per branch? Suggestion: per restaurant.
- **OQ-4** Can staff unlink and re-pair a wrongly paired order? Suggestion: yes, from the dashboard.
- **OQ-5** What the offline till does (pair on sync, or skip)? Needs the POS flavors checked.
- **OQ-6** Should the cashier's code field be optional per order, or can paging be off at the till entirely? Suggestion: optional field plus a switch.
