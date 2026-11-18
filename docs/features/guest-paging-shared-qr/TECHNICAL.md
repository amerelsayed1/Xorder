# One shared QR for guest paging: technical plan (guest-paging-shared-qr)

Status: **plan, awaiting approval** · 2026-11-18 · Spec: `FEATURE.md` (same folder) · Verified against monorepo `e3dba8e8` (cloud and POS source) and `origin/main` `8d5a85b9` (the order-number page)
Repos touched: cloud API, menu app, dashboard (`apps/xorder-cloud`) and the **cloud-flavor POS** (`apps/xorder-pos`). Nothing here is built.

## 1. What the investigation changed in the spec
| # | Spec said | Source says | Plan decision |
|---|---|---|---|
| 1 | The claim is "a field on `POST pos/orders`, or a separate call: decided in the plan" | The order request is protected against double sends by a hash of fixed fields only (`PosOrderService.php:580-602`: id, branch, type, lines, discount, payments). A new optional key is outside the hash. The till's drain has fixed event types and quarantines any record the server rejects with a 4xx (`outbox_drain.dart`, per the POS analysis) | **A field `pager_code` on `POST pos/orders`**, ignored if the code is bad, never a reason to reject the order. A separate claim call would need a new outbox event type |
| 2 | BR-7: "the till says the code was not found" | The sale commits locally first and reaches the cloud later, usually within seconds when online (nudge 2 s, floor 20 s) but possibly hours when offline. The cashier would get no immediate feedback | Add a small **peek call** `GET pos/pager/{code}` the till makes when the cashier types the code, non-blocking: a tick, or "not found, ask the client to scan again". If it cannot be reached, no check and the sale goes on |
| 3 | Offline behavior open (OQ-5) | Only the **cloud flavor** syncs sales (`DeploymentMode.syncsSalesToPlatform`, `deployment.dart:70`). The offline flavor has no sale sync at all (`postgres_orders_repository.dart:430-433`) | **The feature is cloud-flavor only.** A restaurant on the offline till cannot pair. The cloud-flavor till pairs when its sale drains |
| 4 | Contract ID to be allocated | `POS-BE-034` is the highest id mentioned in the ledgers | Use **POS-BE-035**, to be confirmed against both ledgers before it is written (**UNVERIFIED** that it is free) |
| 5 | After pairing, "the S3 page shows the order" | The S3 page reads an order by its tracking token | The paired session hands the order's token to the phone, and the phone goes to `/menu/o/{token}` (existing page, no change) |
| 6 | The client sees "the order number" | A cloud order's fallback reference is `ORD-{id}`, not the slip number. The till order carries `invoice_number` (`PosOrderResource.php:35`) | At pairing, the order's display reference is set from `invoice_number`. **UNVERIFIED** that this is the number printed on the slip: check in Stage C4 |
| 7 | The till gets the on/off state somehow | There is no feature-flag path to the till except `pos/bootstrap`; the till keeps switches in `pos_settings` (`pos_settings.dart:90,149`). Whether the cloud till's bootstrap writes there is **UNVERIFIED** | Additive key in `pos/bootstrap`; the till shows the field only when it is true |

## 2. Reuse
`GuestPagingService` (`isEligible`, `generateToken`, `transition`) · `PublicOrderTrackingController` and the S3 page · `PosOrderService::create` and `PosOrderResource` · `PosBootstrapService` (restaurant block) · `QrCodeService` for the standing QR · `FoldDigitsFormatter` and `foldDigits` (Arabic-Indic digits) in the POS · the till's `pos_settings` · `AppStrings` (en and ar, a missing translation is a compile error) · the existing named limiters and `BelongsToRestaurant`.

## 3. Design in one paragraph
A new table of **pairing sessions**. A phone scanning the standing QR creates (or resumes) a session and gets a short numeric **code** and a long **secret** it keeps. The cashier types the code; the till sends it as `pager_code` with the order; the cloud binds the session to that order in the same transaction as the order, frees the code, and the phone, polling with its secret, learns the order's token and moves to the existing order-number page.

## 4. Stages (order: cloud, then menu and dashboard, then POS)
**C1: schema (additive, written not run).** New table `pager_sessions`: `restaurant_id` (cascade), `code` string(8) nullable, `secret_hash` string(64) unique, `order_id` nullable (nullOnDelete, unique), `expires_at`, `bound_at` nullable, timestamps; unique `(restaurant_id, code)` (NULLs are not duplicates, so binding frees the code). One migration, new table only; no change to `orders`. Tests: migration runs, uniqueness, code freed on bind.

**C2: service.** `PagerSessionService`: `start` (resume by secret if still open, else new unique code; prunes expired unbound rows first; retries on a code collision), `peek(restaurant, code)`, `bind(order, code)` (same restaurant, open, unexpired, order eligible and not already bound; idempotent for the same order; never throws to the caller; returns a status: `paired | not_found | expired | already_used | not_eligible`), `state(secret)`. On bind: set the order's token and `PREPARING` if absent (as `PublicOrderController.php:160-166` does) and its display reference (decision 6). Tests: AC-2 to AC-4, AC-6, AC-7, AC-9, AC-10.

**C3: public endpoints.** Under `public/restaurants/{slug}/pager-sessions`: `POST` start or resume (secret in an `X-Pager-Secret` header, never in a URL) and `GET current` (state, the code while open, the order's token once bound). The restaurant is the one on the host; requires `guest_paging` and a visible restaurant. New named limiters, generous per address (shared Wi-Fi). The response also carries the restaurant's name, language settings, logo and colour (as the tracking payload does). Tests: AC-1, AC-11, AC-14, AC-15.

**C4: till endpoints (POS-BE-035, PROPOSED).** (a) `GET pos/pager/{code}` in the device-authenticated group (`routes/api.php:850`): 200 if open for the till's restaurant, else 404. (b) `POST pos/orders` accepts optional `pager_code` (digits, max 8), excluded from the idempotency hash, bound after the order is saved; the response gains an additive `pager` object with the status; a refused code never changes the order's own result. (c) `pos/bootstrap` gains `restaurant.guest_paging` (bool). Verify here that `invoice_number` is the slip number. Tests (cloud, SQLite): AC-2 to AC-7 through the till, replay of the same order with and without the code, response shape for old and new clients, cross-tenant code (AC-6).

**C5: prune.** A scheduled command that deletes expired unbound sessions and old bound ones (the scheduler container already runs `schedule:work`; where schedules are registered is **UNVERIFIED**). Test: it deletes only what it should.

**M1: menu app.** A join page at `/menu/p` (the server already serves any `/menu/*` path): starts or resumes a session, shows the code large with "tell the cashier your code", polls every 3 s, and on the bound state does `location.replace('/menu/o/{token}')`. The secret is kept in `localStorage` (best effort). Expired shows "scan again". Opens in the restaurant's language like the order-number page; English and Arabic strings; no text until the language is known. Check: `pnpm build` and a person on a phone (AC-1, AC-8, AC-13). No JavaScript test framework exists.

**D1: dashboard.** A "Counter QR" entry for the owner: shows the standing QR (SVG and PNG download) for `https://{slug}.xorder.io/menu/p`, with print guidance; `settings.view`, gated by `guest_paging`; English and Arabic. Test: the cloud route returns the QR for the right restaurant only (cross-tenant 404).

**P1: POS, cloud flavor only (separate repo track and release).** (1) `Ticket.pagerCode` plus a `TicketEngine` method, like `attachCustomer`. (2) A code field on the payment screen beside the customer chip, with `FoldDigitsFormatter` and length validation. (3) On entry, if paging is on and the till is online, call the peek endpoint (non-blocking): tick, or "not found, ask the client to scan again". (4) Store the code on the local order row (new column, SQLite upgrade entry; the PostgreSQL migration only if the shared code requires it, **UNVERIFIED**) so it survives a restart and a retried drain. (5) `OutboxDrain.buildOrderRequest` adds `pager_code` when present and treats the reply's `pager` status as information only. (6) Show the field only when bootstrap says `guest_paging` and `syncsSalesToPlatform`. (7) Strings in `AppStrings` (en, ar). Tests: unit tests for the engine method, digit folding, the request shape (`outbox_drain_test.dart`), and a fake for the peek call. `flutter analyze` and `flutter test` per package; the PostgreSQL suites need `scripts/check.sh` and a local server, and are reported as **not run** otherwise.

**Docs.** FEATURE (decisions), TECHNICAL (as built), API, DATABASE, TEST_PLAN, TEST_REPORT, CHANGELOG; inventory row; coordination entries for POS-BE-035 in both repos' ledgers; fix the old guest-paging docs that name POS-BE-033/034.

## 5. Verification
Cloud: `cd apps/xorder-cloud/apps/api && php artisan test --filter Pager` then the full suite and `./vendor/bin/pint --test` (throwaway `APP_KEY` and `JWT_SECRET` needed locally). Front-end: `cd apps/xorder-cloud && pnpm build`. POS: `cd apps/xorder-pos && flutter analyze && flutter test`, per package. Not provable by tests: the real till flow in a rush, a phone alert, a real print, PostgreSQL behavior on the SQLite suite.

## 6. Compatibility and rollout
Cloud first, all additive and behind the existing `guest_paging` flag: new table, new public endpoints, new till endpoints, an optional order field, an extra response object and a bootstrap key. An old till sends no `pager_code` and ignores the extra keys. A new till against an old server gets a 404 on the peek call and skips the check, and the order's unknown `pager_code` key is dropped by validation (to be proven by a test in C4). Order of delivery: cloud (C1 to C5), then menu (M1) and dashboard (D1), then the POS release (installer) with the field hidden unless the server says paging is on. Rollback per stage: cloud `./deploy.sh --rollback` (the new table stays, harmless); menu and dashboard the same; the POS ships the field behind the bootstrap key, so turning the plan feature off hides it.

## 7. Venue models
**Café and quick-service counter, and a food truck with signal:** helped. **Food truck with weak signal:** the client's phone needs data to get a code, and the till needs the cloud for the peek; sale and pairing still work later, but the client waits. **Restaurant with table service:** not for dine-in. **Cloud kitchen:** not applicable. **Offline-flavor tills:** cannot use it. Gaps leaned on: web push to a closed page (S8) and the moving-truck model.

## 8. Risks
- A mistyped code pairs the order with a stranger; the stranger sees a number that is not on their slip. There is no unlink in this plan (open question).
- Two apps and two release tracks; the POS is a Windows installer.
- A rush: many phones behind one Wi-Fi address and one extra step for the cashier.
- The slip number may not be `invoice_number` (decision 6).
- The cloud till's bootstrap may not store settings (decision 7).
- A 4-digit code can run short in a very busy venue (pool freed as soon as a code is bound).

## 9. Approvals needed before building
1. One additive migration (new table), written and tested on SQLite, not run on any real database.
2. New public endpoints and new till endpoints, and the additive `pager_code`, response object and bootstrap key: **POS-BE-035**, PROPOSED (the POS integrates only once it is READY).
3. A POS code change and a Windows installer release, separate from the cloud deploy.
4. A new branch from `origin/development`, no commit or push until you say so, and nothing reaching `xorder-cloud` `main` without `/release-check`.

## 10. Open questions (defaults chosen)
- Code length 4 digits, unclaimed codes valid 30 minutes. (A 5-digit option if a venue is very busy.)
- One standing QR per restaurant, not per branch.
- No unlink or re-pair in this plan; a wrong pairing is fixed by the client scanning again.
- The peek call is allowed to be skipped when the till is offline.
- Offline-flavor restaurants are out of scope.
