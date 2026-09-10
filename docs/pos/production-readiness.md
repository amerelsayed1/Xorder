# Production readiness — what stops a restaurant taking money on this

Audited 9 September 2026 against `main` @ `15d7be7`. Every claim below was checked in
source; the `file:line` is the evidence, not a citation of the docs. Where a commit
message named a gap, the gap was re-verified rather than copied.

Ranked by the only order that matters: what makes trading unlawful, then what loses
money quietly, then what stops the doors opening, then what stops the business being
run.

---

## Ship blockers

### 1. Nothing prints. The button says it did.

**Missing.** There is no print path in the product at all. `HardwarePorts` exposes
exactly two methods — `discoverPrinters()` and `testPrint(String printerName)`
(`lib/domain/repositories/repositories.dart:793-799`) — and `hardwarePortsProvider`
is read from two places, both inside the setup wizard
(`lib/features/setup/presentation/setup_panes.dart:1296`, `:1331`). No migration
creates a print queue (no `pos_print*` table in `lib/data/postgres/migrations.dart`).
`ReceiptPaper` is a Flutter widget rendering a paper-coloured preview on screen
(`lib/features/receipt/receipt_paper.dart:17-26`).

The settle dialog's second button is labelled *Print and new* and its `onPressed`
shows a toast and closes: `lib/features/receipt/receipt_dialog.dart:110-121`. The
toast reads **"Receipt queued for the default printer."**
(`lib/core/l10n/app_strings.dart:2423`, AR `:5214`). Nothing is queued. Nothing is
printed. The drawer is not kicked at settlement either — `DrawerOpenFlow`
(`lib/features/cash/presentation/cash_dialogs.dart:336-396`) records a cash movement
and sends no bytes to hardware.

Only network ESC/POS on TCP 9100 is implemented, and USB is explicitly out of scope
(`lib/data/hardware/network_printer_ports.dart:19-21`, `lib/app/providers.dart:588`).

**Cost.** No customer copy, therefore no paper carrying the ETA QR — which is the
customer-facing half of the e-receipt obligation, so this is a legal blocker before it
is an operational one. The drawer does not open on a cash sale. And the till tells the
cashier it printed, so the first person to discover otherwise is a customer.

**Acceptance.** `HardwarePorts` gains `printReceipt(ReceiptData, {String printerName})`
and `kickDrawer(...)`; a fake socket receives ESC/POS bytes containing the total, the
QR payload when present, a cut and a drawer-kick sequence; settling a cash sale calls
both; a settle with no printer configured shows a *not printed* message and never
`receiptQueuedToast`; the reprint dialog goes down the same path.

**Size: M** — the byte-building and the socket already exist for `testPrint`; the work
is the receipt renderer, the settlement wiring, and honest failure states in EN and AR.
**L if USB is in scope** — that is a platform channel per OS, which is a different job.

### 2. The e-seal and the submission client do not exist. Nothing has ever been filed.

**Missing.** `eta_signer.dart` is an interface and a refusal, by design
(`lib/domain/services/eta_signer.dart:82-117`). `UnconfiguredEtaSigner` is never
instantiated or bound — there is no signer provider anywhere in
`lib/app/providers.dart`. The queue's four verdict writers —
`markSigned`, `markAccepted`, `markRejected`, `markAttempted`
(`lib/data/postgres/postgres_eta_queue_repository.dart:180-224`) — have **zero callers
in `lib/`**; the only callers are test doubles. There is no HTTP client to ETA
anywhere in the data layer. The E-receipts pane is read-only: 263 lines with no
`onPressed` and no button
(`lib/features/admin/presentation/management_eta_pane.dart`).

Everything upstream is real and tested: canonical serialization, the receipt builder,
the chained queue with a `FOR UPDATE` head lock, the QR painter, the deadline summary.
Every row it writes is `'pending'` and stays `'pending'` for ever.

**Cost.** The restaurant cannot file. It cannot trade lawfully. This is the blocker.

**Acceptance.** A signer binding exists and `isConfigured` is surfaced on the
E-receipts pane (the string `etaQueueNoSeal` is already written in both languages,
`app_strings.dart:1956`/`:4751`, and is used by nothing — check it renders). A drain
worker signs a `pending` row, submits it, and moves it to `accepted` with a
`submission_uuid` and `long_id`, or to `rejected` with the authority's message, or
leaves the status alone on a network failure while incrementing `attempts`. A rejected
row is visible on the pane with its reason. Against a stub endpoint: 3 receipts in,
3 accepted, chain intact, `previous_uuid` matching.

**Size: L** — and it cannot start until the signing arrangement is decided (open
question 1). The client itself is small; the seal integration is not.

### 3. Nothing catches up a receipt that was missed.

**Missing.** The whole filing design rests on a reconciler — "an order with no row in
`pos_eta_receipts` is a *query*", `lib/data/eta/filing_orders_repository.dart:14-20`
and again at `:101`. It does not exist. `enqueue` has exactly one call site,
`filing_orders_repository.dart:88`. So an order that failed to queue, or one rung up
before the receipt profile was completed, is never revisited.

Worse, the alarm is disconnected: `FilingOrdersRepository.onProblem` is optional
(`:32`, `:48`) and `providers.dart:255-268` does not pass it. Both
`ProfileIncomplete` and `FilingFailed` are therefore raised into `null`. A restaurant
whose activity code is one digit short files nothing and is told nothing.

**Cost.** Silent non-filing, discovered by the authority rather than by the
restaurant. Same failure shape as `pos_tax_groups`: a correct domain with no wire.

**Acceptance.** A reconciler selects settled orders in the branch with no
`pos_eta_receipts` row and enqueues them, oldest first, idempotently (the uuid unique
index is the guard). `onProblem` is wired to something the operator sees. Test: settle
with a blank profile → no row, no alarm; complete the profile, run the reconciler →
one row; run it twice → still one row.

**Size: S** — one query, one loop, one provider wire.

### 4. Refunds are never filed.

**Missing.** `EtaReceiptType.refund` (`lib/domain/services/eta_receipt.dart:26`) has
no callers. `EtaQueueRepository.enqueue` takes `refundId`
(`lib/domain/repositories/repositories.dart:59-67`) and every call site passes
`receiptType: EtaReceiptType.sale` with no refund id
(`filing_orders_repository.dart:92`). `lib/data/postgres/postgres_refunds_repository.dart`
never touches the queue. `pos_eta_receipts.refund_id` is always null.

**Cost.** Worse than the sale path, which at least queues: refund data never reaches
`pos_eta_receipts` at all, so no reconciler can ever catch it up. Every refund is an
unfiled credit note, and the filed sales overstate turnover by the refunded amount.

**Acceptance.** Issuing a refund enqueues a `receiptType: 'r'` document carrying
`referenceOldUUID` naming the sale's uuid; a refund against an unfiled sale is
refused or deferred rather than filed with a dangling reference; the reconciler in
item 3 covers refunds too.

**Size: M** — the document shape exists; the reference chain and the "what if the sale
is not accepted yet" rule are the work.

### 5. The QR never reaches paper.

**Missing.** `ReceiptData.etaQrPayload` (`lib/features/receipt/receipt_data.dart:88`)
is null in every production path — the only assignment in the repo is a test
(`test/features/receipt_profile_ui_test.dart:330`). `pos_eta_receipts.qr_payload`
(`migrations.dart:2089`) is written by nothing. `ReceiptQr` is correct and deliberately
refuses to invent a payload (`lib/features/receipt/receipt_qr.dart:14-18`).

**Cost.** The customer's copy carries no verifiable code. Legal.

**Acceptance.** Acceptance stores the authority's QR payload on the row; a reprint of
an accepted sale renders it; an unaccepted sale prints no square.

**Size: S**, but strictly after items 1 and 2 — there is nothing to print it on and
nothing to get the payload from.

### 6. A zero-rated product still cannot be marked zero-rated.

**Missing.** `pos_products.tax_group_id` (`migrations.dart:1677`) and
`pos_categories.tax_group_id` (`:2410`) are read on every catalogue load —
`COALESCE(p.tax_group_id, c.tax_group_id)`,
`lib/data/postgres/postgres_catalog_repository.dart:73` — and written by no statement
in `lib/`. The product insert (`postgres_catalog_admin_repository.dart:383-390`) and
update (`:306-325`) both omit the column; so do the category writes. There is no rate
picker in the Menu pane — `taxGroup` appears in `lib/features/admin/presentation/`
only in the Tax pane and its dialog.

The Tax pane can now author named rates (`management_taxes_pane.dart:244-281`) and
`taxGroupsProvider` loads them, so the arithmetic is finally live. Nothing can point a
product at one except hand-written SQL.

**Cost.** The exact bug the last commit fixed, one step downstream: bottled water a
restaurant sells zero-rated is charged 14%. Money taken from customers, and a return
filed on the wrong base.

**Acceptance.** The product dialog has a tax-group picker defaulting to *inherit from
category*; the category dialog has one defaulting to *use the standard rate*; saving
a product with no group chosen does not clear an existing assignment; a ticket
containing a product in a 0% group shows zero tax on that line and the correct tax on
the others.

**Size: S** — two dialogs, two columns in existing SQL, EN and AR labels.

### 7. Saving a VAT rate silently switches a tax-inclusive restaurant to exclusive.

**Missing / wrong.** `management_taxes_pane.dart:126-129` builds
`TaxConfig(serviceBp: …, vatBp: …, serviceDineInOnly: …)`. `taxMode` is not passed, so
it falls to its default `TaxMode.exclusive` (`lib/domain/models/ticket.dart:384`).
`saveMoneyConfig` then overwrites the entire payload —
`SET payload = @payload::jsonb`, `postgres_catalog_admin_repository.dart:540-545` —
with `MoneyConfigCodec.fromTaxConfig`, which emits `'tax_mode': config.taxMode.wire`
(`lib/data/postgres/money_config_codec.dart:72`). And no screen anywhere sets the mode
in the first place: the pane has two rate fields and a dine-in switch.

**Cost.** A restaurant on inclusive pricing loses the mode the moment a manager
touches the VAT box, after which 14% is *added* to prices that already contain it —
"the single most expensive mistake available in that file", per the commit that
introduced the mode. Egypt prices exclusive so the blast radius today is small; it is
total for the first Gulf customer, and today there is no way to configure them at all.

**Acceptance.** The Tax pane carries an inclusive/exclusive control; saving rates on a
restaurant configured inclusive leaves `tax_mode` inclusive; a golden asserts an
inclusive ticket's **total** as well as its tax.

**Size: S** — one field and one preserved value. Small, and the wrong way round is
expensive.

### 8. A supplier paid from the till drawer does not reduce the drawer.

**Verified as reported.** `pos_supplier_payments.cash_movement_id`
(`migrations.dart:2822`) is selected at
`postgres_supplier_invoices_repository.dart:54` and written by nothing. The dialog
says so on screen (`supplier_payment_dialog.dart:166`), which is honest and does not
make the drawer balance.

Note the surrounding machinery is sound: `ShiftSummary` computes expected cash from
float plus cash taken plus pay-ins less pay-outs, reading `pos_cash_movements` and
`pos_refunds` directly (`lib/data/postgres/postgres_shift_repository.dart:191-231`).
The hole is only that a back-office payment writes no movement.

**Cost.** Hand the dairy man 2,000 from the till and the shift shows a 2,000 shortage
that reads as theft. The cashier is accused, or the count stops being trusted, which
is worse.

**Acceptance.** A supplier payment made in cash offers *pay from the till drawer* when
a shift is open on this terminal; taking it writes a `payOut` cash movement in the
same transaction and stores its id; the Z report's expected cash falls by the amount;
voiding the payment voids the movement; a payment made with no open shift still
refuses, and says why.

**Size: M** — cross-aggregate write, needs a shift and a terminal in a screen that has
neither today.

### 9. A crash loses the live ticket, and the button that says "Park" does not park.

**Verified, and worse than reported.** `TicketController`
(`lib/app/providers.dart:995-1123`) holds the live ticket in memory and every mutation
is `state = TicketEngine…`; `build()` (`:997`) starts a fresh uuid and reads no store.
Parked tickets *are* durable — `pos_parked_tickets` (migration 7,
`migrations.dart:648`), write-through `park()` at `providers.dart:663`, hydration on
boot at `:645-658` — but `park()` is called from exactly one place, the *go to floor*
callback (`lib/app/router.dart:165-175`), and returns early when `tableId == null`.

So: a takeaway or delivery ticket can **never** be persisted. And the control the
operator is told to use does not persist anything — F4 is bound to `_sendRound`
(`lib/features/sale/sale_screen.dart:542-544`), and the button labelled `s.parkKey`
on an unseated ticket calls `onSendRound` (`cart_panel.dart:382`, `:386`).
`sendRound` is a pure in-memory stage flip (`ticket_engine.dart:453`) that writes no
row despite the name.

The class doc at `providers.dart:611-618` still claims parked tickets are in memory and
lost on restart. It is false and eleven lines above the code that disproves it.

**Cost.** Power cut on a Cairo evening: the kitchen has cooked, the ticket is gone, and
there is no record that anyone ordered. The sales figures and the food that left the
kitchen disagree, and nobody can reconstruct which.

**Acceptance.** F4 and the Park button park any non-empty ticket, seated or not
(unseated tickets get a durable row keyed on something other than `table_id`);
restarting the app offers the parked tickets back, including unseated ones; a test
kills and rebuilds the container and finds the ticket. Fix the stale comment in the
same change.

**Size: M** — the store, codec and hydration exist; the schema needs a key for an
unseated ticket, and the resume UI needs somewhere to list them.

### 10. There is no way to install or update this on a Windows machine.

**Missing.** `scripts/package_macos.sh` is the only packaging script in the repo.
`windows/` is the unmodified Flutter desktop template — `windows/runner/Runner.rc:92`
still reads `VALUE "CompanyName", "com.example"`. There is no Inno Setup script, no
WiX project, no MSIX config in `pubspec.yaml`, no `.ps1`/`.bat`, and no `.github`
directory, so no CI and no release. Nothing bundles or installs PostgreSQL. There is
no updater: the only version notion is `const posAppVersion = '1.0.0'` kept in step
with `pubspec.yaml` by hand (`lib/data/cloud/cloud_provisioning_repository.dart:21`),
and it is only ever reported outward at provisioning and heartbeat
(`lib/data/cloud/cloud_api.dart:80`, `lib/data/cloud/cloud_sync.dart:173`). Schema
changes need a human running `bin/pos_migrate.dart`, because the app boots as
`pos_till`, which holds no DDL.

`docs/pos/10-offline-install-runbook.md` is a macOS runbook and honest about it.
`docs/pos/10-setup-architecture.md` names two files that do not exist —
`lib/core/config/terminal_role.dart` (`:648`) and
`lib/data/network/postgres_host_scanner.dart` (`:684`) — and claims secrets live in the
Windows Credential Manager via DPAPI (`:759-764`), which
`lib/data/config/file_secret_store.dart:9-31` contradicts by explicit owner decision.

**Cost.** The product is sold for Windows and cannot be handed to a restaurant.
Everything above is undeliverable without this.

**Acceptance.** One signed installer artefact produced by a scripted build that a
technician can run on a clean Windows machine: app installed and branded, PostgreSQL
present, database created and migrated, first-run wizard reachable. A second run of
the same installer upgrades in place and runs pending migrations without losing data.
CI produces the artefact on a tag.

**Size: L** — packaging, PostgreSQL provisioning, migration-on-upgrade and a build
pipeline, none of which exist in any form.

### 11. There is no backup, and no restore.

**Missing.** `pg_dump` and `pg_restore` appear nowhere in the repository — not in
`lib/`, `bin/`, `tool/` or `scripts/`. Every hit for *backup* or *restore* in `lib/` is
either credential rehydration at boot (`lib/main.dart:52`, `:60`), catalogue
soft-delete ("archive/restore a product"), or a price-override revert.
`PosCapability.backupManage` (`lib/domain/models/permissions.dart:94`) is grantable,
risk-classified critical (`:243`), held only by Owner, deliberately excluded from
supervisor override (`:134`) — and honoured by no screen; its sole non-test reference
is a checkbox label (`lib/features/admin/presentation/admin_messages.dart:49`).
`lib/core/ui/widgets/permission_gate.dart:20-21` uses *"Restore database"* as its
worked example of a control that must be hidden — a button that was never built.
`docs/pos/10-setup-architecture.md:646` claims backups are the main device's "real
second job".

**Cost.** One failed SSD is the entire trading history, the catalogue, the staff, the
unfiled receipt queue and the audit trail. Unrecoverable in the strongest sense.

**Acceptance.** A scheduled `pg_dump -Fc` to a configured destination, gated on
`backup.manage`, with the last successful run visible and stale-backup warning; a
restore path that a technician can run and that a test exercises end to end (dump,
drop, restore, catalogue and last shift intact). Until the restore is tested it is not
a backup.

**Size: M** — a process wrapper, a destination setting, a schedule, and one pane. The
honest work is testing the restore.

**Status (2026-09-11): built, restore tested end to end.** Owner's decision: local
disk plus a USB drive.

- **Taking a copy.** `pg_dump -Fc` runs at every day close and on demand, as a
  read-only `pos_backup` account (a `pg_read_all_data` member whose password is kept
  on the till). Every copy is read back **in full** before it counts: a dump missing its
  last few bytes still passes `pg_restore --list` (measured), so a list alone does not
  prove anything. A copy that fails is recorded as *Not a backup* and not kept.
- **Records and housekeeping.** Each attempt is written to the append-only
  `pos_backups` table (migration 37). The folder keeps the newest 14 copies.
- **Getting a copy off the machine.** *Copy to…* puts a copy on a USB drive and checks
  the copy's checksum against the original's.
- **Restoring.** *Restore from a file…* brings one back. A restore runs as the
  database owner with `--no-owner --single-transaction`, and is refused while a shift
  or trading day is open.
- **Warnings.** The start screen warns when there is no verified copy, or the newest is
  two days old.

**Tests.** `test/data/pg_archive_restore_test.dart` restores as `pos_admin` (not a
superuser) onto a blank database and compares every table's rows, every sequence and
every grant `pos_till` holds. It also proves that a half-read file is refused before
anything is touched, and that a restore failing at its very end leaves the database it
found.

**Still open.**
- The installer (item 10) must create `pos_backup`; until then it is the runbook's
  "The backup account".
- A restore needs `pos_admin` to own the tables, which is true for wizard-built
  databases but not for ones built by `postgres` with `pos_migrate`.
- Recovering onto a *replacement* machine restores the data but not that machine's
  terminal registration, which the wizard created fresh. That flow is not designed yet.

---

## Not blockers — and why each can wait

Read this half. It is what stops someone building a dashboard while filing is broken.

- **Dashboard pane.** A number nobody acts on. Every actionable figure already has a
  pane or a dialog.
- **Reports pane, and `reports.view` with nothing behind it** (`permissions.dart:93`;
  only use is a label at `admin_messages.dart:48`). The Z report at shift close
  (`shift_dialogs.dart:502`) and order history answer the daily questions. A reporting
  suite is resented, not fatal. **But** either build it or take the capability out of
  the role editor — a permission an owner can grant that does nothing is a promise.
- **Terminals pane, and `terminal.manage`** (`permissions.dart:28`, labelled at
  `admin_messages.dart:30`, enforced nowhere in `lib/`). Same shape as above.
  Terminals are provisioned by the setup wizard; nobody adds one mid-service.
- **Settings pane.** Ten keys in `SettingKey`
  (`lib/domain/models/pos_settings.dart:65-79`) and no screen writes any. Safe: every
  key has the SRS default baked into `DayPolicy`, `CashPolicy` and `RefundPolicy`, and
  those defaults are the behaviour a restaurant expects. The writer already exists
  (`postgres_settings_repository.dart:52`) with grants
  (`local_bootstrap.dart:630`). Two notes for whoever builds it: blind close and the
  pay-out ceiling are the only keys a restaurant will actually ask for, and
  `SettingsRepository.save` has **no** `Authorization.check` — add one before a screen
  calls it, or a cashier's connection can rewrite the refund policy.
- **Inventory pane / stock on hand.** `pos_stock_movements` is write-only
  (`postgres_receiving_repository.dart:150`) and `StockCosting.issue`
  (`lib/domain/services/stock_costing.dart:116`) has **no caller** — selling never
  reduces stock, so on-hand only ever rises. Waiting is correct precisely because
  nothing displays it. Do not build the pane before the issue path: a stock figure on
  screen that only goes up is worse than no figure.
  `pos_products.is_stocked` and `stock_unit` (`migrations.dart:2695`, `:2702`) are
  unread, waiting for the same work.
- **Customers, Expenses, Accounting Lite.** No schema, no half-built claim to trip
  over. Cleanly absent.
- **Sales Management pane.** Order history exists at the till
  (`lib/features/history/presentation/order_history_screen.dart`), which is where a
  manager needs it.
- **Combos, per-branch prices, discounts.** `pos_combos`, `pos_combo_groups`,
  `pos_combo_options`, `pos_product_prices`, `pos_discounts` and
  `pos_discount_targets` all have a read path and no writer, so the till reads empty
  and prices correctly. Half-built, and inert.
- **`pos_cash_drawers`** (`migrations.dart:1440`) — the only fully orphaned table;
  `pos_cash_movements.drawer_id` (`:1504`) is always null. One drawer per till is the
  reality; drop it or leave it, but do not build for it.
- **`requiresCustomer` on order types** — saved and read by nothing
  (`lib/domain/models/order_type_config.dart:40`); the hint on screen says so, which
  is the right handling.
- **`pos_order_taxes`, `pos_order_line_items`, `pos_order_line_events`** are
  write-only. Correct: they exist so a filing and a line-level audit can be
  reconstructed later, not so a screen can read them today.
- **Secrets in a plaintext file** (`file_secret_store.dart:9-31`) — an explicit owner
  decision, 4 September 2026. Not a gap. But three places still tell an installer to
  look in the OS keychain (`lib/app/providers.dart:1499`,
  `lib/data/config/pos_db_secret_store.dart:3`, and the operator-facing string at
  `app_strings.dart:2858` naming the Credential Manager). Correct those or an installer
  will spend an afternoon in the wrong dialog.
- **Stale docs.** `docs/pos/10-setup-architecture.md` names `terminal_role.dart` and
  `postgres_host_scanner.dart`, neither of which exists. Documentation debt, not code.

---

## Sequencing

Two things gate everything and neither is code: **the ETA signing arrangement**
(question 1) and **the Windows install decision** (question 4). Get answers this week.

**Lane A — compliance.** Serial where it has to be.
`3 (reconciler)` and `4 (refund filing)` need nothing from anyone and can start today.
`2 (seal + client)` starts when question 1 is answered. `5 (QR to paper)` needs both
`2` and `1`. Do not start `5` early; there is nothing to print and no payload.

**Lane B — printing.** `1` is independent of every other item and of every open
question except the USB decision (question 3). Start it in parallel with Lane A on day
one; it is on the critical path for `5`.

**Lane C — money, all small, all mutually independent.** `6` (tax-group pickers) and
`7` (preserve `tax_mode`) touch two different files and can be done by one person in
the same week. Do `7` first: it is the smaller change and the more expensive bug.

**Lane D — durability.** `9` (ticket survival) then `8` (supplier cash to drawer).
`8` is second because it needs an open shift on the terminal, and `9` is where the
ticket/terminal/shift plumbing gets touched anyway.

**Lane E — deliverability.** `10` (Windows install) is long and blocks shipping
anything, so it starts on day one alongside Lanes A and B. `11` (backup) splits: the
`pg_dump` wrapper and the restore test need nothing from `10` and can run in parallel;
the destination setting and the scheduling belong in the installer's first-run
checklist, so that half lands after `10`.

**Parallel at once:** Lane B (`1`), Lane C (`7`, `6`), Lane E (`10`, `11` first half),
and Lane A's `3` and `4`. That is four streams with no shared files.
**Blocked on answers:** `2`, and therefore `5`.

**Two house rules to budget for, not discover.** Every operator-facing string needs an
English *and* an Arabic member of `AppStrings` or it does not compile — that is real
time on items 1, 6, 7, 8, 9 and 11, and it is where the schedule slips. And nobody runs
`dart format`: the repo was formatted with an older formatter and it rewrites about 185
unrelated files. Database suites run against real PostgreSQL with
`POS_PG_HOST=localhost POS_PG_USER=amerelsayed`; the `pos_till`-credential suites run
as `pos_till`.

---

## Open questions for the owner

Decisions that cannot be read out of the code. Items 2 and 5 cannot start without 1.

1. **Do ETA sandbox credentials and a registered e-seal exist yet, and which signing
   arrangement are we building against** — the taxpayer's own token, ETA's integration
   toolkit run as a local service beside the branch server, or a service provider
   signing on our behalf (`signatureType` `S`)? This decides whether item 2 is a small
   local-service client or an HSM integration, and it is the difference between weeks.
2. **Is the POS device serial registered with the authority?** The chain currently
   keys on the terminal id as a stand-in, and the code says so
   (`lib/app/providers.dart:262-267`). It must be the registered serial before the
   first real submission, and changing it later breaks the chain.
3. **Which receipt printers do we support and sell?** Only network ESC/POS exists.
   Most Egyptian restaurants already own USB printers, and USB is a platform channel
   per OS. This is the difference between item 1 being M and L.
4. **Windows: what is the deployment?** One till with local PostgreSQL, or a LAN with
   a main device? Do we ship a bundled PostgreSQL or require a technician to install
   it? Who runs `bin/pos_migrate.dart` at a restaurant, and how does version 1.1 reach
   a machine — an update channel, or a technician with a USB stick?
5. **Where do backups go, and who owns testing the restore?** Local disk, a second
   machine on the LAN, or cloud. Until somebody has restored one, item 11 is not done.
   *Answered 2026-09-11: local disk plus a USB drive. The restore is exercised by
   `pg_archive_restore_test.dart` on every database-suite run.*
6. **Is cloud a deployment we sell today, or a direction of travel?** It decides
   whether the platform-owned code paths — the bootstrap seeder, the outbox drain, the
   gated panes — are a live surface to maintain and test, or weight we are carrying.
7. **Is inventory in scope before launch?** Moving-average costing is on record
   (owner, 9 September 2026) and receiving writes the ledger, but selling does not
   reduce stock. If inventory is in scope, the sale-side issue path is the first piece
   and the pane is the last. If not, say so and we leave the ledger write-only.
8. **Any customer outside Egypt in the next two quarters?** If no, item 7 shrinks to
   *preserve the stored mode on save* and the inclusive/exclusive control waits. If
   yes, it needs the control and a golden suite.
