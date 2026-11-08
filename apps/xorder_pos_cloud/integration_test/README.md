# End-to-end tests

```bash
POS_PG_HOST=127.0.0.1 POS_PG_USER=pos_till POS_PG_PASSWORD=… \
POS_PLATFORM_URL=http://localhost:8080 \
POS_TENANT_SLUG=demo POS_TENANT_USER=… POS_TENANT_PASSWORD=… \
  flutter test integration_test -d macos \
  --dart-define=XORDER_PLATFORM=http://localhost:8080 \
  --dart-define=POS_E2E_REQUIRED=true
```

The wizard is walked the way an owner sets up a cloud till
(pos-cloud-sign-in-setup): sign in with the business address and the
**owner's** dashboard account (`POS_TENANT_USER` must be the
`RESTAURANT_ADMIN`, or the till refuses it), choose the branch, take the till.
There is no licence key and no platform field: the platform is the build's
(`XORDER_PLATFORM`), and the licence arrives in the bootstrap bundle, so the
tenant must hold a live **cloud** licence on that platform.

For local convenience the suite skips itself when the database or the platform
address is absent. The documented command sets `POS_E2E_REQUIRED`, turning
that situation into a failure so CI and release runs cannot pass without
executing E2E coverage.

## What this is for

Everything under the UI already has a suite. `ticket_engine_test` proves the
arithmetic, `postgres_test` proves the SQL, `postgres_wiring_test` proves the
provider graph resolves to PostgreSQL once a terminal is provisioned. What none
of them can prove is that a person who walks up to a new machine ends up with a
sale in the ledger — because each one starts halfway in, with a container
already built or a ticket already assembled.

This suite starts where an installer does: an unconfigured machine, a real
password typed into the wizard's own field, and a real database on the other
side. The seams it covers exist only when the whole thing is assembled — wizard
to router, router to till, till to database.

`TillDriver` never reads a provider or calls a controller, deliberately. A test
that reached for `setupProvider` to skip the boring parts would re-cover what
the widget tests already cover and still miss the wiring it was written to
catch.

## Why it needs a device

`-d macos` is not optional. Under the headless `flutter test` harness the test
body runs in a fake-async zone, where a PostgreSQL round trip never completes
and `pumpAndSettle` reports quiet while a write is still in flight. On a real
device the clock and the socket are both real, which is the only honest way to
test a till that talks to a server.

For the same reason the driver waits on **outcomes** rather than sleeping:
neither a query nor a `Future.delayed` schedules a frame, so `pumpAndSettle`
alone would sail straight past both. `waitForText('LICENSED')` says what it is
waiting for and fails saying what never arrived.

## The database

Each run creates and owns `xorder_pos_e2e`, migrates it with `PosMigrator`, and
truncates between tests. Migrating in `setUp` mirrors production: the schema is
an install-time act performed with an admin credential — `bin/pos_migrate.dart`
— and the till has no rights to create the tables it needs. A test that let the
app migrate itself would be testing a deployment nobody runs.

## What it does not cover

* **Only the wide desktop shell.** The window is pinned to 1440×900. The tablet
  and handheld breakpoints exist but are unfinished, so there is nothing yet to
  drive.
* **Only the pairing-code path** through setup. Manual registration has widget
  coverage in `test/features/setup_wizard_test.dart`.
* **No hosted-platform round trip.** Offline setup and the local sale ledger are
  assembled here; request construction and outbox behavior have lower-level
  tests. A platform test service is still needed for the complete
  queued-sale → reconnect → delivered journey.
