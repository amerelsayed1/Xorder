# POS offline

The till on its own branch database, with no cloud. Everything here is also the base a cloud till runs on.

## Done

### Tills can't overwrite, underpay or wrongly void a check
**Status:** done (POS `development`) · **Group:** [G6](README.md#features-grouped) · **Repo:** xorder-pos · **Closes:** XORD-044, XORD-045, XORD-046

- Every parked check (table or held) has a version; a save only lands over the version the till last saw (migration 63). Paying or voiding checks the version and lets go of the parked row in the same transaction. Tills re-read the floor every 5 seconds.
- Tests: `floor_two_tills_test`, `parked_tickets_schema_test`, `payment_check_changed_test`, `provisional_invoice_test`; mutation runs fail them.

### The whole test suite is green (XORD-029)
**Status:** done · **Group:** [G9](README.md#features-grouped) · each test file starts on a fresh schema; old-migration replays use `PgFixture.replay`.

### "Business", not "restaurant"
**Status:** done (commit `5386c26`) · **Group:** [G8](README.md#features-grouped) · migration 64 renames the table, every `restaurant_id` column, constraints, indexes, triggers and function bodies in place; screens say "business" / المنشأة. Cloud wire fields keep their names.

## Next

### Small fixes from today's tests
**Status:** ready · **Group:** [G7](README.md#features-grouped) · **Repo:** xorder-pos · **Approval:** none beyond the go

| ID | Change | Proved by |
|---|---|---|
| XORD-059 (P3) | "حاول مرة أخرى" after a failed database open clears every failure cached by the first attempt, so the sale screen opens without a restart | widget test: failed boot → retry → sale screen opens |
| XORD-054 (P3) | Setup names the real cause when the admin account cannot create the till's database user | unit test on the error classification |
| XORD-056 (P3) | ⌘⇧S on the welcome screen — confirm with a real keyboard | a person |

### Waiter app stage 2 — rounds as records
**Status:** ready · **Group:** [G6](README.md#features-grouped) · **Repo:** xorder-pos · **Approval:** the migration (65) · **Spec:** [`waiter-app` WS2](../features/waiter-app/TECHNICAL.md)

Sending a round saves the ticket and a `pos_ticket_rounds` row (round number, `sent_at`, `sent_by`, device, unique `client_round_id`) in one transaction; the ticket records `opened_by`; a resent round is a no-op. Tests: engine unit tests; PostgreSQL test for the single transaction and the idempotent resend.

### Waiter app stage 3 — kitchen tickets
**Status:** ready after stage 2 · **Group:** [G6](README.md#features-grouped) · **Approval:** which kitchen printer gets which categories · **Spec:** [`waiter-app` WS3](../features/waiter-app/TECHNICAL.md)

Each sent round queues a docket per kitchen printer (Arabic and English); voiding sent food queues a void docket. Tests: docket content and routing, print-queue PostgreSQL test; **the paper is checked by a person**.

Later waiter stages (branch service, waiter role and clock-in, device licence limit, handheld app) are in the same TECHNICAL.md.

## Rules to keep

- (G7) **Upgrading a till:** run the new build's `dart run bin/pos_migrate.dart` (admin account) before starting the new till — the new binary cannot open an un-migrated database and the old one cannot open a migrated one. All tills of a branch upgrade together.
- **First version:** no compatibility code for older tills; migrations stay numbered and additive.

## Waiting on the owner

- (G7) **Restore the offline till on this Mac** (`aziz_db`): its `config.json` and licence are backed up in the session scratchpad; restoring also needs its database password re-entered once.
