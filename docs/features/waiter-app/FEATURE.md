# Waiter app (POS on a handheld) — waiter-app

Status: **WA1 built 2026-11-09 (uncommitted, xorder-pos `development`)**; rest proposed · first written 2026-11-06 · Source: the owner, "I'm planning to remove the table ordering to waiter application", and "POS app on a handheld" as the form of the waiter app · Verified against: xorder-cloud `775bf0f`, xorder-pos `c67c754` (+ unrelated uncommitted UI changes) · Companion: `docs/features/pos-incoming-cloud-orders/FEATURE.md`

## 1. Summary

Waiters take table orders on a phone or small tablet running the Xorder POS app with a waiter role. They seat a table, add items and rounds, send them to the kitchen, see "request bill" and "call waiter" from the table's QR, and hand the bill to the cashier or settle it if allowed. Diners no longer order from the table in branches that run the POS. This replaces table ordering from the QR menu for those branches.

## 2. Why

- **Who is hurt today:** restaurants. Table orders come from diners' phones with phone-written prices (`PublicOrderController.php:80-93`), land only in the cloud dashboard, and must be re-keyed into the till. A waiter has no device of their own: the POS runs on Windows/macOS only (`pubspec.yaml:2`).
- **Venue models:** restaurant (tables, rounds, splits, open checks) is the target. Café only if it has table service. Food truck and cloud kitchen are not applicable: no tables (domain handbook section 2).

## 3. Goal and success

- A waiter can take a full table order on a handheld at the table, and the kitchen receives it as a POS round.
- The table's check, rounds and total are the same on the handheld and the till at all times, with no double-seating.
- Prices, tax and totals come from the POS pricing rules, never typed on the handheld.
- Table bill/call-waiter requests reach the waiter on the handheld.

## 4. Users, roles and permissions

| Actor | Can | Permission |
|---|---|---|
| Waiter (handheld) | sign in with PIN, open/seat a table, add items/modifiers/notes, send rounds, move/merge tables (if allowed), see and clear table requests, print or send the bill to the cashier | existing POS permissions where they fit (`lib/domain/models/permissions.dart`: `pos.operate`, `order.item.delete_before_send`, `order.item.delete_after_send`, `discount.apply` …); a **waiter role** preset is new; whether a waiter may take payment is Q4 |
| Cashier (till) | everything today, plus see the waiter's tables live | existing |
| Manager | assign waiters to areas/tables (if Q5), approve voids | existing approval rules |

Plan gate: `pos` and `table_management` (`Feature.php`). The number of handhelds against the licence/plan terminal limit is Q6.

## 5. Today

| Area | Exists (evidence) | Missing |
|---|---|---|
| Platforms | POS described as "desktop point of sale for Windows and macOS" (`pubspec.yaml:2`); an `android/` Flutter project exists with the default id `com.example.xorder_pos` (`android/app/build.gradle.kts:19`) | a shipped Android build; signing; store/MDM distribution |
| Narrow layout | the design system keeps a narrow shell "for Android POS handhelds" (`docs/pos/07-design-system.md:115`); <700 px only where a cashier would use a handheld (`docs/pos/12-design-brief.md:102`) | a waiter-first flow; which screens fit — **UNVERIFIED** |
| Floor and open checks | `TableState` free/open/billAsked (`dining_table.dart:3-12`); open check = one parked ticket per table (`migrations.dart:640-660`); floor overlay is single-terminal: "a table is busy because THIS till parked a ticket on it… multi-till consistency is the branch server's whole reason to exist and is deliberately not faked here" (`floor_overlay.dart:5-9`) | shared table state across devices |
| Shared database | "any install whose terminals share one database" is assumed for branch reports (`docs/pos/17-sales-and-payments-plan.md:146-147`); POS connects directly to the branch PostgreSQL (workspace `CLAUDE.md`) | how a handheld on Wi-Fi reaches that database safely — **UNVERIFIED** (DB credentials on a phone is a risk) |
| Kitchen | `SENT_TO_KITCHEN` status (`order_record.dart:28-55`); printing state `?` (domain handbook section 3) | — |
| Staff sign-in | PIN sign-in (`docs/features/pos-pin`), staff from bootstrap with `pin` | — |
| Table requests | arrive only in the cloud today; routing to the POS is in the companion feature | — |

## 6. Scope

**In:** an Android handheld build of the POS with a waiter role; sign-in by PIN; floor with live state shared across till and handhelds; open/seat a table with guest count; add items, variants, modifiers, notes; send rounds to the kitchen; void/remove under existing rules; transfer/merge tables if the till supports it; table bill and call-waiter requests on the handheld; print the bill (Q7) or hand it to the cashier; retire diner table ordering for the branch once its waiters are live.

**Out:** any payment on the handheld (W4; card terminals are also an SRS non-goal), KDS, tips, diner ordering from the table.

## 7. Behavior and business rules

- **BR-1 One check per table, shared.** A table's open check is the same record on every device of the branch; two devices cannot seat or edit the same check into two versions (server-side lock in the branch database).
- **BR-2 POS pricing.** Items, modifiers, tax and service charge are priced by the POS pricing rules from the branch catalog; the handheld cannot type a price unless the user has `price.override`.
- **BR-3 Fired vs unfired.** Removing an unsent line is routine; voiding a sent line needs `order.item.delete_after_send` and a reason (domain handbook section 4).
- **BR-4 Rounds.** Each send is a kitchen round with its time and waiter; the check shows rounds in order.
- **BR-5 Provenance.** Every line, send, void and discount names the waiter who did it.
- **BR-6 Table requests.** A bill or call-waiter request from the table QR shows on the handheld of the table's waiter (or all, per Q5); clearing it on any device clears it everywhere.
- **BR-7 Settlement.** The bill is printed at the cashier's printer and settled only on the till (W4, W8).
- **BR-8 Offline.** Handhelds work against the branch server on the local network; losing the internet does not stop table service. If a handheld loses the branch Wi-Fi, its rounds queue on the device and are sent once on reconnect (W6).
- **BR-9 Clock-in.** A waiter clocks in and out with their PIN; every line and round carries the waiter; no cash is held by waiters (W9).

## 8. Acceptance criteria

- **AC-1** Given a waiter signed in on a handheld, when they open T3, add 2 items with a modifier and send, then the kitchen receives one round and the till shows T3 open with the same lines and total.
- **AC-2** Given T3 open on the till, when a waiter adds a round on the handheld, then the till shows it within a few seconds and the total matches.
- **AC-3** Given two devices opening a free T3 at the same moment, then only one check exists for T3.
- **AC-4** Given a waiter without `price.override`, then no price can be typed.
- **AC-5** Given a sent line, when a waiter without `order.item.delete_after_send` tries to void it, then it is refused or needs approval with a reason.
- **AC-6** Given a diner request from T3's QR, then the T3 waiter's handheld shows it and clearing it clears it on the till.
- **AC-7** Given the check is settled on the till, then T3 is free on every handheld.
- **AC-8** Given the internet is down but the branch network is up, then table service continues and syncs to the cloud later through the existing outbox (`outbox_drain.dart:45-59`).
- **AC-10** Given a handheld with no Wi-Fi, when the waiter sends a round, then it shows "queued"; when Wi-Fi returns, the kitchen receives it exactly once, and if the table was settled meanwhile the waiter sees it as failed.
- **AC-11** Given a waiter without a clock-in, then they cannot open a table; after clocking out, their open checks stay open on the till.
- **AC-12** Given a waiter taps "print bill" on T3, then the bill prints at the cashier's printer and no payment option exists on the handheld.
- **AC-13** Given the branch has used its plan's waiter-device limit, when another handheld registers, then it is refused with a clear message.
- **AC-9** Arabic and English, RTL and digits correct on a small screen (needs a person to look).

## 9. Edge cases and failure modes

Handheld loses Wi-Fi mid-send (round must be sent once, idempotently); battery dies with an unsent round (kept on the device or lost — Q8); two waiters on one table; table moved while a waiter is editing it; waiter shift vs cashier shift (does a waiter open a shift? Q9); lost or stolen handheld (revoke the device; no database password stored on it); many handhelds on weak restaurant Wi-Fi; small screen with long Arabic item names.

## 10. Impact

| Area | Change |
|---|---|
| POS | Android build and distribution; waiter role; handheld layouts for floor, menu, check; shared floor state replacing the single-terminal overlay (`floor_overlay.dart`) |
| Branch server | how handhelds connect (direct PostgreSQL vs a small local API on the branch server) — architecture decision in the plan |
| Cloud | waiter role in staff/roles if roles are cloud-managed; device registration and licence count for handhelds; table QR retired for ordering (companion feature) |
| Data | additive: waiter on lines/rounds, device id, shared check lock |
| Licensing | handhelds may count as terminals — **approval** if limits change (`docs/pos/09-licensing.md`) |
| Deploy order | POS handheld release and waiters trained per branch before that branch's diner table ordering is retired (companion feature D9) |

## 11. Dependencies, known gaps, risks

- **Depends on** multi-terminal table consistency in the branch server, which the code says does not exist yet (`floor_overlay.dart:5-9`) — the largest piece of this feature.
- **Depends on** kitchen printing (state `?`).
- **Risk:** database credentials on handhelds if they connect directly; Wi-Fi quality in restaurants; Android device fragmentation.
- **Known gaps:** card payment at the table, tips, KDS.

## 12. How it will be tested

POS unit tests for the shared-check lock and round sending (two-device race against a test PostgreSQL, databases dropped after the run); integration test extending `integration_test/sale_to_settle_test.dart` with a second device; a person runs a full table service on a real Android handheld and a till in Arabic and English, including Wi-Fi loss.

## 13. Decisions and open questions

**Decided (owner, 2026-11-06):**
- **W1** The waiter app is **the POS app on a handheld**; diners do **not** order from the table in POS branches; tables keep a **requests-only QR** (bill / call waiter).
- **W2** Devices: **both phones and tablets** — two layout sizes (about 6" and 7–10").
- **W3** Platforms: **Android and iOS** — adds Apple signing and App Store or MDM distribution.
- **W4** **The cashier settles**; waiters never take payment on the handheld (BR-7 is now: settlement only on the till).
- **W5** **All waiters see all tables**; each check shows who opened it; a table request goes to that check's waiter first, then to everyone.
- **W6** On Wi-Fi loss, the handheld **queues the round and sends it later**, automatically and once (idempotent client id per round). The waiter sees "queued, not yet in the kitchen" until it is delivered; the till does not show the round until it arrives.
- **W7** Licence: a **separate waiter-device limit** per plan, priced apart from full tills.
- **W8** The bill **prints at the cashier's printer** when the waiter taps "print bill".
- **W9** Waiters **clock in and out** with their PIN (attendance and per-waiter sales). No cash, float or cash-up for waiters; the till's shift owns all money.

- **W10** **Two separate POS apps (cloud and offline) with shared modules** — its own feature, to be described with `/develop-feature`.
- **W11** The waiter app works with **both** apps. Table-QR requests exist only with the cloud app (the offline app has no cloud); see `TECHNICAL.md` T12.
- **W12** XORD-044 (a second till overwrites a table's check) is **fixed first**, as stage WS1.
- Section 5 above is partly stale: kitchen dockets do not exist at all, and sending a round only changes memory (`TECHNICAL.md` section 0, T6).

**Effects of these decisions on the rules above:**
- BR-7: settlement happens only on the till (W4).
- BR-8: losing the branch Wi-Fi no longer blocks sending; rounds queue on the device (W6). A queued round that the server refuses on arrival (table closed or moved meanwhile) is shown to the waiter as failed, never silently dropped.
- Scope: iOS is now **in** (W3). Card payment on the handheld stays out.
- New edge cases from W6: a round queued for a table that was settled before it arrived; two queued rounds from two devices for the same table arriving out of order (order by device send time, shown as separate rounds); a device that stays offline past the end of the day.

**Open:**
- **Q3** Do handhelds talk straight to the branch database, or through a small service on the branch server? Technical; the plan will recommend one. Direct database access from phones would put database credentials on lost or stolen devices.
- **Q10** How many waiter devices each plan includes, and their price (W7). This is a commercial decision.
- **Q11** Per-waiter reports (W9): which figures (sales, covers, average check, voids) and who may see them.
- **Q12** How queued rounds are shown to the kitchen if they arrive late (W6): mark them "late" on the ticket?

Next: `/implement waiter-app` once Q3 is settled in its plan — needs approval for: the branch-server connection design, additive migrations, Android and iOS release channels (Apple account, signing, distribution), the new waiter-device licence limit, and the rollout per branch (waiters live before diner table ordering is retired, companion feature D9).
