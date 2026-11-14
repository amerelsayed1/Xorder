# Manual test — POS cloud till against the local cloud (2026-11-07)

**Scope:** set up a new cloud-mode till on this Mac against the local Docker cloud (`http://localhost:8080`), sign in, ring up a dine-in sale, take payment, and check that the sale reaches the cloud. Nothing touched production.

**Builds:** POS debug build from `apps/xorder-pos` branch `fix/xord-044-046-parked-check-versions` (`effdffb`; the business rename is not in it), plus another session's uncommitted dropdown files in that checkout. Cloud: local Docker stack built from `apps/xorder-cloud` working tree (branch `feat/finance-accounts-and-platform-updates-2026-10-26`, with another session's uncommitted work).

**Driven by:** Claude, through the macOS app with computer control.

## Test data created (local only)

| What | Where | Note |
|---|---|---|
| Cloud licence `LIC-2026-0029` | local cloud, tenant `demo` (id 21) | 1 year, 2 terminals; issued with `LicenceIssuer::issue` |
| Terminal 170 "Manual test till" | local cloud, branch 8 | `PosProvisioningService::provision`, pairing code issued |
| Staff user 57 `manualtest` | local cloud, cashier role 39 | test PIN through `PosPin::make`; config version bumped as `PosPinController` does |
| PostgreSQL role `pos_till_cloudtest`, database `xorder_cloudtest_db` | local PostgreSQL | the owner's `pos_till` role and `aziz_db` were not touched |
| Cloud order 117 | local cloud | the sale from this test |

The test values (licence key, pairing code, PIN, database password) are kept in the session scratchpad, not here. The previous offline till's `config.json` and `licence.xlic` (on `aziz_db`) are backed up in the session scratchpad; restoring them also needs its database password re-entered.

## Results

| # | Step | Result | Evidence |
|---|---|---|---|
| 1 | Open setup on an unconfigured till | PASS, by 12 logo taps; ⌘⇧S / Ctrl⇧S did nothing (see F3) | wizard appeared |
| 2 | Activate the cloud licence | PASS | "مرخَّص · Demo Restaurant · جهازان"; wizard drops the mode step (6 → 5 steps); `POST /api/pos/licence/activate` 200 |
| 3 | Pair with a setup code | PASS | "Manual test till · الفرع الرئيسي"; `POST /api/pos/terminals/claim` 200 |
| 4 | Create the local database | PASS after creating the till role by hand (see F1) | "63 migrations, 137 items saved"; `GET /api/pos/bootstrap` 200 |
| 5 | Start screen synced | PASS | status pill "تمت المزامنة · 0 في الانتظار" |
| 6 | New staff reaches the till | PASS after pressing the sync pill (see F2) | `pos_users` gained `manualtest` 5 s after the press, config version 92 → 93 |
| 7 | Sign in with PIN | PASS | "Manual Test Cashier"; stored PIN verified against `PosPin` (PBKDF2-SHA256, 120000) |
| 8 | Open shift with a 200 float | PASS | shift #0001 |
| 9 | Floor shows the cloud's tables | PASS | T1–T5, free |
| 10 | Seat T3, add 2 items, send round | PASS | Cherry Cola 85 + Mojito 100; toast "تم إرسال الجولة إلى المطبخ" |
| 11 | Take cash payment | PASS | receipt `BR8-2026-000001`, 185.00 EGP, VAT 0 % (cloud tax config) |
| 12 | Sale reaches the cloud | PASS | cloud order 117, `source=pos`, `channel=pos`, total 185.00, COMPLETED, same `client_transaction_id` (`1fba5376…`); till outbox 0 pending |
| 13 | Table freed after payment | PASS | T3 free on the floor |
| 14 | Item with options | PASS | "عرض شاي كو" opens its options dialog (an earlier "nothing happened" was the tester closing it with a second tap) |

Not checked: the sale on the cloud dashboard screen (it needs the tenant admin's password; the database row was checked instead), receipt printing (no printer), shift close and Z report, refund, void, the two-till cases of XORD-044/045/046 (covered by automated tests, not by hand here).

## Findings (logged 2026-11-07 as XORD-054 to XORD-057: F1–F4 in order)

- **F1 — Misleading database error in setup.** With a till user name that does not exist yet and an admin account without CREATEROLE (`pos_admin` here), the wizard says the admin "cannot create tables in" the database, and that it is not a password problem. The database was owned by `pos_admin`, which could create tables; the failing step was creating the role. Expected: name the real cause ("this account cannot create the till's database user; ask for one or use an account with CREATEROLE"). Severity: P3.
- **F2 — New staff reach a till only on the next sync, up to 4 hours later.** By design (owner decision 2026-09-27: idle sync every 4 h), but a cashier added in the dashboard cannot sign in until someone presses the sync pill or makes a sale; restarting the app did not help. Worth a line in the dashboard ("tills pick this up on their next sync — press sync on the till to get it now"), or a heartbeat soon after a staff change. Severity: P3, product question.
- **F3 — Setup shortcut did not open the wizard.** ⌘⇧S and Ctrl⇧S on the welcome screen did nothing in this test; 12 logo taps did. The key events were synthetic (computer control), so this may not happen on a real keyboard. UNVERIFIED — needs a person to press the keys.
- **F4 — A branch without a code gets an invented one.** Branch 8 has an empty code on the cloud; the till numbered the sale `BR8-…`. Harmless here, but a real branch should have a code before tills register. Severity: P4.
- **Observation:** the status bar shows the cloud cashier as "بلا دور" (no role) although the user has the cloud cashier role; the till holds the permissions directly (`pos.operate` etc.), so nothing is blocked. Possibly confusing to staff.

## Re-test — XORD-058 provisional receipt (2026-11-07, 11:03)

Build: `refactor/business-naming` + `fix/xord-058-provisional-receipt` (uncommitted), debug, from the session worktree.

| # | Step | Result | Evidence |
|---|---|---|---|
| 1 | Start the new build on the test till's database | Refused until migrated: "relation pos_businesses does not exist" — expected, the till role cannot change the schema | after `dart run bin/pos_migrate.dart --database xorder_cloudtest_db --user pos_admin --grant-to pos_till_cloudtest --cloud-till`: version 64, 1 business and 5 orders kept, no `restaurant_id` column left |
| 2 | Retry, then open a sale | FAIL until restart: red error screen "pos_businesses does not exist" — a failure cached from the first boot survived "try again" | after quitting and reopening the app the sale screen loads (see F5) |
| 3 | Cloud sale at T2, Cherry Cola 85, cash | PASS | receipt "رقم الطلب: مبدئية" (provisional), not a `BR8-…` number |
| 4 | Sale reaches the cloud | PASS | till outbox: delivered, cloud order 122, `server_invoice_number` `BR8-2026-000013` (the till's own row number is `BR8-2026-000006`, not printed) |
| 5 | Till order history | PASS | lists `BR8-2026-000013` and `BR8-2026-000008` — the cloud's numbers |

Also seen: a macOS Keychain prompt blocked the first launch of the new binary (the owner answered it); the disk filled up (339 MB free) and 21.2 GB of Docker build cache was pruned with the owner's go.

- **F5 (logged as XORD-059) — "Try again" on the database error screen does not clear cached failures.** After a boot that failed (here: schema older than the binary), retrying reached the start screen, but the sale screen still showed the old error until the app was restarted. Severity: P3, proposed; to log in the tracker.
