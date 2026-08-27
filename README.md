# XOrder POS — desktop point of sale

Offline-first POS for **Windows** and **macOS**, built in Flutter as a module of
[XOrder](https://xorder.io). Desktop-first: three-pane selling screen, keyboard
driven, designed for a cashier working at speed rather than a phone layout
stretched across a monitor.

## Run it

```bash
flutter pub get
flutter run -d macos     # or: flutter run -d windows
flutter test
flutter analyze
```

The till reads everything — menu, floor, staff, its own identity — from a
**PostgreSQL branch server**. Point it at one with `bin/pos_migrate.dart` before
first run; see *Preparing a branch database* below. With no database configured
it starts empty and refuses to take money, on purpose.

## Where things are

| Path | What |
|---|---|
| `lib/core/money/` | Integer minor units, half-up rounding, currency exponents |
| `lib/core/ui/` | Design tokens, Material theme, shared widgets |
| `lib/domain/models/` | Catalog, ticket, table — plain Dart, no Flutter |
| `lib/domain/services/ticket_engine.dart` | **Every ticket mutation and money rule.** Pure, unit-tested |
| `lib/domain/repositories/` | Repository contracts the UI depends on |
| `lib/data/fakes/` | Test doubles. **Not bound by the app** — injected by tests that want them |
| `lib/data/unconfigured/` | What the till binds before it has a database: empty, never invented |
| `lib/features/` | `setup · start · lock · floor · sale · payment · receipt · licensing` |
| `lib/core/config/deployment.dart` | Cloud / branch-server / islanded modes + sync policy |
| `lib/data/postgres/` | PostgreSQL datastore — pool, migrations, orders repository |
| `lib/app/` | Providers (Riverpod), router (go_router), theme wiring |
| `bin/pos_migrate.dart` | Install-time command that creates the branch schema and grants the till role |
| `integration_test/` | End-to-end suite: the assembled app, driven through the UI, against a real database |

## Documentation

| Doc | What |
|---|---|
| `docs/pos/01-existing-system-analysis.md` | What the XOrder backend already offers |
| `docs/pos/02-pos-requirements.md` | POS requirements (POS-Rxxx) |
| `docs/pos/03-offline-strategy.md` | Local persistence, sync queue, conflicts |
| `docs/pos/04-flutter-pos-architecture.md` | Layering, state, DI, ports |
| `docs/pos/05-data-contracts.md` | Expected wire shapes |
| `docs/pos/06-implementation-plan.md` | Phased plan |
| `docs/pos/07-design-system.md` | Tokens and screen specs from the design handoff |
| `docs/pos/08-deployment-modes.md` | Cloud vs branch server vs islanded — and when on-prem is worth it |
| `docs/pos/09-licensing.md` | Licence format, expiry policy, renewal |
| `docs/coordination/POS_TO_BACKEND.md` | Backend requests raised by this app (`POS-BE-xxx`) |
| `docs/coordination/BACKEND_TO_POS.md` | The backend's replies |

## Design language, in two rules

1. **Border radius is 0. Everywhere.** No exceptions.
2. **No shadows.** Elevation is a border — `1px` resting, `2px` emphasised.

Every number renders in mono. Colours, type and dimensions are transcribed from
the design handoff into `lib/core/ui/tokens.dart`; that file is the single place
they live.

> **Font gap:** Archivo, IBM Plex Mono and Tajawal are vendored in the web repo as
> `.woff2`, which Flutter cannot load. The families are named and the platform
> substitutes until `.ttf`/`.otf` files are added to `assets/fonts/`. Layout is
> specified in logical pixels and does not depend on the substitution.

## Money

Integer **minor units** end to end — never a `double`. Rounding is **half-up,
applied once at the tax line**, matching the server's `decimal:2` cast. Service
12% (dine-in only); VAT 14% on `subtotal + service`.

Those two rates are **read-only device config and provisional**. The server must
become the author of tax — `POS-BE-013`. Any receipt produced from device config
says so on the slip.

## Backend status — read this before wiring anything up

Every backend contract this app needs is **`PROPOSED`**. Nothing is `READY`.

The till therefore talks to the branch server's PostgreSQL directly rather than
over HTTP — see *Where the till's data comes from*. It used to bind every
repository to a `Fake` instead, which is why a first run showed a restaurant
nobody owns. The UI depends only on the interfaces in
`lib/domain/repositories/`, so swapping in an `Api…` implementation as each
contract reaches `READY` is a one-line change in `lib/app/providers.dart` with no
widget changes.

The blocking request is **`POS-BE-006`** (authenticated, server-priced order
creation) together with **`POS-BE-007`** (idempotency). Until they land, the till
can price and settle a ticket locally but has nowhere authoritative to send it.

## Deployment modes

On-premises is a **configuration choice, not a second product**. All three modes
speak the same API against the same schema; only `base_url` and how often the
platform hears from the till differ.

| Mode | Shape |
|---|---|
| **Cloud** | Terminals → the hosted platform |
| **Branch server** | A box in the branch runs the same `docker-compose.yml`; tills use it over the LAN, and it forwards upstream |
| **Islanded** | No server. One till, local database, periodic check-in |

Every mode is **offline-first** — there is no online-required variant, because a
desktop till always has a disk. What varies is when the queue drains:
`SyncPolicy.automatic` or `SyncPolicy.manual`, asked as a separate question in the
wizard. The heartbeat that keeps a till visible to Super Admin is automatic under
both.

Chosen in the setup wizard. The honest reason to pick a branch server is
**multi-till consistency during an outage**, which the per-terminal queue cannot
provide — not "offline support", which it already does. Full reasoning and the
costs in `docs/pos/08-deployment-modes.md`.

## Licensing

Ed25519-signed licence file, verified **entirely offline**. Renewal lives in
`Settings → Licence`: key re-entry, offline `.xlic` import, or automatic refresh
in cloud mode.

The governing rule is **never brick a till mid-service**. An expired licence
blocks the *next* shift; it never interrupts an open one, and **cash-up, reprint
and export are never gated in any state**.

This is commercial hygiene, not security — the verification key ships in the
binary. Real enforcement stays server-side. See `docs/pos/09-licensing.md`.

## Keyboard

`F2` search · `F3` repeat line · `F4` park / send round · `F6` discount ·
`F7` split · `F9` pay · `F10` drawer · `Esc` void or close · `Enter` confirm.

## Not built yet

Local outbound queue (the datastore itself now exists — see below) · printing and ESC/POS · cash drawer and scanner
ports · refunds · open-tickets sheet ·
discounts and price override · the tablet and handheld shells
(the breakpoints exist; only the wide shell is finished).

**Arabic is not wired.** The wizard offers العربية and the choice is recorded,
but `MaterialApp` has no `locale:` and there is no `Directionality` in `lib/` —
so the interface stays English and left-to-right whichever is picked. The menu
carries `name_ar` throughout and the domain models already select on locale, so
the data half is done; the shell is not.

**Sign-in happens at the drawer, not at the door.** Opening a shift asks for a
PIN and records who gave it, so the person answerable for the cash is on the
record. `SessionRepository.current()` still returns the branch's first active
member of staff for the top bar, so the *displayed* name is not necessarily the
person holding the till — but the shift, and therefore the money, is attributed
correctly. A dedicated sign-in screen is still `POS-BE-024`.

## Shifts and the drawer

A shift is opened before the till will sell, and closed by counting the drawer.

* **Opening** asks for a PIN and the cash already in the drawer. The float is not
  optional and not assumed: every variance at cash-up is measured from it, so a
  guess there is a discrepancy later.
* **A restart resumes.** The drawer never closed, so neither did the shift —
  the start screen offers *Resume SHIFT #0001* rather than asking for a second
  opening float against the same cash.
* **Every sale is stamped** with the shift it was rung up in, which is what lets
  the Z report total anything at all.
* **Closing** shows the Z report — sales, gross, a line per tender — works out
  what should be in the drawer, and asks what actually is. The variance is shown
  live, before anything is committed, so a miscount is caught while the notes are
  still in someone's hand.
* **Only cash counts against the drawer.** Card and wallet takings are on the
  report but not in the expected total; counting them would manufacture a
  shortfall on every shift.
* **A variance is recorded, never refused.** Refusing to close would leave the
  till unusable and the discrepancy unrecorded, which is the opposite of what
  anyone wants at 1am. It is stored on the shift with who counted it.

Two rules are held by the database rather than by code: a partial unique index
allows **one open shift per terminal**, and a check constraint makes a shift
either open or closed but never half-closed. A second cash-up cannot overwrite
the first.

Licensing and deployment are built, but a **real** licence server, a native file
picker and hardware fingerprinting are not — the wizard runs on a development
issuer that self-signs. Persistence is in-memory: the setup wizard currently
re-runs on each launch until the local database lands.

**PostgreSQL is the primary datastore**, hosted on the branch server and shared
by every till on the LAN (`docs/pos/08-postgres-lan.md`). `lib/data/postgres/`
holds the pool, the advisory-locked migration list and
`PostgresOrdersRepository`, which enforces idempotency, per-branch invoice
sequencing and split tender with database constraints and row locks rather than
client-side hope. Nothing outside that directory imports the driver:
`ordersRepositoryProvider` is the one swap point, so an `ApiOrdersRepository` can
replace it when `POS-BE-006` lands without touching `domain/` or `features/`.

Only the money path goes over SQL. Heartbeat, licence refresh and provisioning
still speak HTTP to the same branch box, which runs the full `apps/api` stack.

The connection is configured in the setup wizard: database name, port, user and
password, alongside the server address. The **password is never written to device
config** — `DeploymentConfig.toJson()` deliberately omits it and it is handed to
`MutablePosDbCredentials` at the end of setup, so it lives in memory only and the
operator retypes it after a reinstall. *Test connection* probes the database
itself and says which of DNS, TCP, auth, TLS or database-name failed, because
sending an installer to open a firewall port when the password is wrong wastes a
site visit.

Two things this does **not** yet have: durable credential storage
(`flutter_secure_storage` — Keychain / DPAPI — is the intended home) and a local
write-ahead, so a till cannot sell while the branch server is down. That is the
accepted cost recorded in `08-postgres-lan.md`, and the unbuilt outbound queue is
what would fix it.

### Where the till's data comes from

**Everything the till shows is read from the branch database.** The menu, the
floor plan, the branches, the staff and the terminal's own identity are rows in
PostgreSQL — see migration 2 in `lib/data/postgres/migrations.dart`.

That is a recent and deliberate change. Every repository used to resolve to a
`Fake…` implementation, and because nothing distinguished a release build from a
debug one, a real restaurant installing the till opened it to a menu of kofta and
hawawshi, a floor of sixteen tables with bills already open on them, and a
cashier called Rana A. — while the money path wrote real rows to a real database.
Convincing and wrong is the worst combination a point of sale can have.

Before setup finishes there is no database to read, so the bindings in
`lib/data/unconfigured/` take over. They return **nothing** rather than
something: an empty menu is the honest answer to "what does this restaurant
sell" before anyone has said. The exception is taking money —
`UnconfiguredOrdersRepository` refuses out loud, because the binding it replaced
recorded the sale in memory and printed `QUEUED OFFLINE — WILL SYNC` on the
customer's receipt for a sale written precisely nowhere.

Three things are still not real, and are still worth knowing about:

| | Why | What it does now |
|---|---|---|
| Licence | Needs a licence server and an Ed25519 key pair | Any non-empty key activates for a year |
| Hardware | Needs USB and network transports behind a platform channel | Discovers nothing, rather than inventing two printers |
| Arabic | The RTL shell is unbuilt — `MaterialApp` has no `locale:` and there is no `Directionality` anywhere | Picking العربية changes a highlight and one summary row; the interface stays English |

### Preparing a branch database

The schema is created by `bin/pos_migrate.dart`, run once when the branch box is
installed and again after an update. It is a **separate command with an admin
credential**, not something the till does at boot: the till connects as
`pos_till`, and a role that could `CREATE TABLE` could also `DROP` one — on a
machine that sits in a public room.

```bash
POS_PG_PASSWORD=… dart run bin/pos_migrate.dart --host 192.168.1.20 \
  --user postgres --create-database --grant-to pos_till
```

Pure Dart, so it runs on a headless server with no Flutter engine. `--status`
reports what is applied and changes nothing; `--help` lists the rest. Re-running
is safe — the migration list is advisory-locked and recorded in
`schema_migrations`, so six tills coming back after an update cannot race it.

Then seed the restaurant. This creates **no menu** — a starter menu would be
somebody else's food, which is the whole problem the section above exists to
describe:

```bash
POS_PG_PASSWORD=… dart run bin/pos_migrate.dart --host 192.168.1.20 \
  --user postgres --seed --restaurant "Amer's Kitchen" --slug amer --pin 1234
```

It prints a single-use setup code; type it at the wizard's *Sign in* step. Run it
again with a different `--terminal` for each additional till.

The menu is yours to insert. Categories first, then products, then any option
groups:

```sql
INSERT INTO pos_categories (restaurant_id, name_en, name_ar, slug, sort_order)
  VALUES (1, 'Grills', 'مشويات', 'grills', 1);

INSERT INTO pos_products (restaurant_id, category_id, name_en, name_ar, price_minor, sku)
  VALUES (1, 1, 'Kofta Plate', 'كفتة', 24500, 'GRL-002');

-- price_minor is PIASTRES. 24500 is 245.00 EGP. There is no decimal anywhere in
-- the money path, on purpose — see the Money section above.

INSERT INTO pos_dining_tables (restaurant_id, branch_id, label, seats, sort_order)
  VALUES (1, 1, 'T1', 4, 1);
```

An option group is a row in `pos_modifier_groups`, its choices are rows in
`pos_modifiers`, and `pos_product_modifier_groups` attaches a group to a product.
A group with `is_required = true` blocks *Add to ticket* until the cashier picks
something.

`--grant-to` gives the till role exactly what the write path uses. Note that
`SELECT` and `INSERT` alone are **not** enough, and a till granted only those
fails on its first sale: `pos_invoice_sequences` needs `UPDATE` for the
`SELECT … FOR UPDATE` that serialises invoice numbering, and the `bigserial`
keys need `USAGE` on their sequences. Still no `DELETE` and no DDL anywhere, so
a recovered till credential can add to history but never rewrite it.

### Tests

`flutter test` runs everything that needs no database — engine, money, widgets,
wizard — and stays green with no PostgreSQL anywhere, because the suites that
need one self-skip when `POS_PG_HOST` is unset.

Point them at a database to run the rest:

```bash
POS_PG_HOST=127.0.0.1 POS_PG_USER=pos_till POS_PG_PASSWORD=… flutter test
```

Each suite creates and owns its own `xorder_pos_<suite>` database. That is not
tidiness: two suites truncating one database produced a duplicate invoice number
from a test artefact rather than a real race, and a flaky money test is worse
than no test because people learn to ignore it.

The end-to-end suite in `integration_test/` is separate, and needs a real
desktop device:

```bash
POS_PG_HOST=127.0.0.1 POS_PG_USER=pos_till POS_PG_PASSWORD=… \
  flutter test integration_test -d macos
```

It boots the assembled app with no provider overrides and drives it the way a
person does — walking first-run setup, typing the database password into the
wizard's own field, opening a shift, seating a table, selling, taking cash — and
then checks the branch ledger against the receipt on screen. See
`integration_test/README.md` for why it needs a device and what it deliberately
does not cover.

Terminal provisioning is built against `FakeProvisioningRepository`: the wizard
offers both paths — claim a dashboard-issued pairing code, or set the till up by
hand — but no dashboard screen issues a real code and no endpoint redeems one
yet. Both halves are `POS-BE-023`. Offline cashier sign-in by PIN
(`SessionRepository.verifyPin`) still has no credential behind it; that is
`POS-BE-024`.
