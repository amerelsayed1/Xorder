# XOrder audit — full scope (till, owner dashboard, Super Admin, platform) — 16 Oct 2026

Audited as: Good Cafe (slug `demo`, production), debug till on macOS paired as
"الكاشير الامامي", owner `admin` and cashier-only `sara`. Evidence: the till's Run
console (`net →`/`net ←` lines), the till's local database `demo_cashier_db`, the
dashboards in Chrome, and the Super Admin audit log.

## Verdict
The core loop works end to end today: a till installs, pairs, sells, and the sale,
the shift and the money reach the owner's dashboard within seconds. It is not ready
to put in front of a paying restaurant: the platform writes cashier PIN hashes into
the audit log any Super Admin can read, no release build has ever carried the
production licence key, and an owner on the current plan is shown "no orders yet"
over a day with sales on it.

## Baseline
| Check | Result |
|---|---|
| Till analyser | clean |
| Till `scripts/check.sh` (unit, widget, PostgreSQL) | 3661 passed (05:20); 2601 unit/widget passed again after the last change (06:3x) |
| API `php artisan test` | 1010 passed |
| Dashboard `pnpm build` | built |
| Till `integration_test/` | cannot run: stale against the current wizard (see O11) |

## Findings

### S1-1 Cashier PIN salt and hash are written to the audit log
Who it hurts · every restaurant: anyone with `audit.view` (Super Admin, platform
staff) can take the salt+hash and recover a 4-digit PIN offline in seconds, then sign
in at the till as that cashier.
Where · `apps/api/app/Models/Concerns/Auditable.php:96-110` (diff audit),
`apps/api/app/Models/User.php:23` (`$auditExclude` lists only password,
remember_token, email_verified_at).
Evidence · admin.xorder.io/audit-logs, event "User سارة updated", 16 Oct 05:36:
`pos_pin_salt: — → EuDY…`, `pos_pin_hash: — → 3O3K…`; same for "المدير العام" at 04:56.
Why · The PIN controller force-fills `pos_pin_salt/hash`; the generic model observer
then logs every changed column not in the exclusion list. POS-BE-024 promised
"audited (action, never the PIN)"; the dedicated "POS PIN set" event honours that, the
diff event beside it does not.
Fix · api: add `pos_pin_salt`, `pos_pin_hash` to `User::$auditExclude` (and
`device_token_hash`, `previous_token_hash`, `fingerprint` on `PosTerminal` — logged
on claim, see event "Pos Terminal updated" 04:36); purge the existing lines from the
activity files.

### S1-2 No release build has ever been built with the production licence key
Who it hurts · the first real customer: a shipped till refuses every production
licence as "could not be verified".
Where · `xorder-pos/.github/workflows/windows-installer.yml:33`,
`scripts/package_macos.sh:47` require `XORDER_LICENSE_PUBLIC_KEY_B64`;
`gh variable list` shows only `XORDER_PG_SHA256`.
Evidence · repo variables listing (16 Oct); the debug build only reads production
licences since 78da21e/efd85ef via `issuer_public_key`, which release builds ignore
by design.
Fix · config: derive the public half of production's `LICENCE_SIGNING_KEY` and set
the two repository variables before the next installer build.

### S2-1 Owner's Orders page says "no orders yet" over a day with a POS sale
Who it hurts · owners on plans without `system_ordering` (Good Cafe's "المحترف").
Where · `apps/api/routes/api.php:446-452` gates `GET dashboard/orders` on
`feature:system_ordering`; `apps/web/src/pages/dashboard/OrdersView.vue:183` swallows
the 403 and renders the empty state.
Evidence · demo.xorder.io/admin shows "مبيعات اليوم 1 طلب · 330"; demo.xorder.io/admin/orders
shows "لا توجد طلبات بعد"; audit log has "POS order BR1-2026-000001 created" and
"Order ORD-52 … NEW → COMPLETED".
Why · Same class as the tables page (fixed in a7fe239): a feature gate rendered as
emptiness. POS sales are stored as orders but the list is behind the online-ordering
feature.
Fix · web: show the plan gate as a sentence; product: decide whether POS sales belong
behind `system_ordering` at all — the owner paid for the POS and cannot see its
orders.

### S2-2 Till keypad takes exactly 4 digits; dashboard accepts 4–6
Who it hurts · any cashier given a 5- or 6-digit PIN: they can never sign in.
Where · `xorder-pos/lib/core/security/pin_hash.dart:25` (`length = 4`);
`apps/api/app/Http/Requests/Dashboard/SetPosPinRequest.php:21` (`[0-9]{4,6}`).
Evidence · lock screen submits on the fourth digit (observed); contract POS-BE-024
says 4–6.
Fix · till: accept 4–6 with a confirm key, or api: enforce 4. One side must move.

### S2-3 Licence renewal silently starts when the old one ends
Who it hurts · Super Admin renewing to get a usable key now: the new licence is
"not yet valid" for years.
Evidence · renewing LIC-2026-0003 produced LIC-2029-0004 starting 14 Oct 2029; the
chain then needed LIC-2026-0005. Audit log 04:30–04:35.
Fix · web: offer "start today" on the renewal form, or warn when the start is in the future.

### S3-1 "Open drawer" demands supervisor approval from the owner, in a clipped dialog
Who it hurts · the manager working the till. Evidence · approval keypad with the 0
key half visible (screenshot 05:33). Fix · till: skip approval for a signed-in user
holding `pos.cash_movement`; fix the dialog height.

### S3-2 Lock screen requires a typed username on a keypad screen
Who it hurts · every cashier at every lock. Fix · till: user tiles or last-user memory.

### S3-3 Change due is a small line inside the receipt
Who it hurts · cashier handing back 170 on a 500 note (observed). Fix · till: show
change large for a few seconds after settlement.

### S3-4 Licence check sent three times at launch
Evidence · console 01:52: three identical `POST /api/pos/license/check` in one second
(one at 06:xx after restart). Fix · till: share one in-flight check.

### S3-5 Close-shift summary ignores parked tickets
Evidence · close dialog at 05:33 listed no mention of the 80.00 ticket parked.
Fix · till: warn and list.

### S4-1 Audit actor for a POS sale's order reads "Customer"
Evidence · "Order ORD-52 created — Customer". Fix · api: attribute to the terminal
and acting staff.

### S4-2 Item names ellipsised in the middle; English "SHIFT #0001" on an Arabic screen; "Service 0% / Tax 0%" lines on every ticket
Evidence · sale screen screenshots 05:32. Fix · till.

### S5-1 Unlabelled disabled button on the receipt dialog
Evidence · receipt dialog 05:32 (print with no printer). Fix · till: label or hide.

## Worked well
- Install → licence → pairing → database → menu: a clean path once the build knows
  the platform's key; every refusal now quotes the platform's reply.
- Sale → receipt → platform: `POST /api/pos/orders` 201 with the invoice number;
  dashboard home, current shift, cash in drawer and audit log all agree at 330.00.
- Cashier-only role: sign-in, shift, void of an unsent ticket allowed; drawer and
  refund gated behind approval.
- Change table (after today's fix): moves with lines intact, refuses a taken table,
  frees the old one.
- Parking, resume from the floor, search, keyboard shortcuts, close-shift arithmetic.

## Not covered
- Card tender, refund of a settled order, reprint, discount as owner: not driven today.
- Offline licence cache behaviour and device token rotation: not driven.
- Reports vs Z report reconciliation: no closed shift today (I did not close yours).
- End-to-end suite: stale, could not run (O11).
- Hunch without evidence: the three parked tickets on tables 1, 3, 5 include two from
  earlier test flows whose origin I did not trace.

## Suggested order of work
1. S1-1 audit-log PIN hash leak (api, one line + purge) — today.
2. S1-2 set the release key variables (config) — before any installer build.
3. S2-1 orders page plan gate and the product decision on POS orders' visibility.
4. S2-2 PIN length agreement.
5. Commit today's till fixes (catalogue, database name, locale, sync nudge, collect,
   change table) — all verified, all uncommitted.
6. S2-3 renewal start date; then the S3 cashier-clock items in order.
