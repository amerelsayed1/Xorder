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

The contracts the till needs are tracked in `docs/coordination/BACKEND_TO_POS.md`;
the table at its top is the source of truth, and this paragraph can go stale.
As of that table: the orders endpoint with server pricing and idempotency (`POS-BE-006`,
`-007`), the per-branch invoice sequence (`-008`), shifts and the terminal
registry (`-009`), money configuration (`-013`), provisioning with pairing-code
claim and the bootstrap bundle (`-023`) and the POS PIN (`-024`) are `READY`.
The branch-server and upstream-sync contracts (`-017`, `-018`, `-021`) and the
setup contracts (`-025` to `-027`) are `APPROVED`.

The till still talks to the branch server's PostgreSQL directly rather than over
HTTP for everything except the cloud path — see *Where the till's data comes
from*. It used to bind every repository to a `Fake` instead, which is why a
first run showed a restaurant nobody owns. The UI depends only on the interfaces
in `lib/domain/repositories/`, so swapping in an `Api…` implementation as a
contract reaches `READY` is a one-line change in `lib/app/providers.dart` with
no widget changes.

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

**Both paths are built.** An unconfigured terminal boots to a logo-only welcome
screen; **Ctrl+Shift+S** (or ⌘+Shift+S on macOS) opens the Setup Wizard — a chord
rather than a button, because an unconfigured till stands in a public room. It
starts with the licence, which says which modes the customer bought; the setup
type step offers Cloud and Offline, and dims one only when the *licence* does not
cover it.

* **Cloud** is short: slug and administrator credentials (or a pairing code),
  then **Connect** pulls the tenant's configuration and the terminal registers.
  The licence arrives again inside the bootstrap bundle and installs itself.
* **Offline** is the long path, because there is no platform to be told
  anything: deployment and database, the first administrator, branch, terminal,
  hardware, money rules and the menu. The wizard builds the branch database
  itself — create, migrate, grant — and discards the administrator password
  afterwards; only the till's is stored.

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

## Roles, permissions and the audit trail

A **role** carries a set of capabilities; a member of staff is on one, plus any
direct grants of their own. Four roles are seeded per restaurant — owner,
manager, supervisor, cashier — and a restaurant edits them freely, with two
rules the code holds: the owner role keeps every capability (or a restaurant can
reach a state where nobody is able to grant one back), and a cashier role holds
nothing from the back office.

Capability names live in `lib/domain/models/permissions.dart`, and
`PosCapability.canonical` maps the names the first build shipped onto them, so a
till on an older binary still reads a migrated database correctly.

**Every check goes through `Authorization`** — the widgets that grey a control
out and the repositories that refuse the write ask the same function, so a
screen can only ever be more restrictive than the data layer, never less. Three
outcomes, not a boolean: *allowed*, *denied*, and *needs a supervisor*, because
a greyed-out button and a PIN prompt are different screens. Overrides are
limited to things somebody can sensibly approve while standing at the till —
discounting, voiding, refunding, cash-up — never to restoring a database.

The **ledger** is `pos_audit_events`. It is append-only three times over: the
interface has no update or delete, the till's database role is granted only
`INSERT` and `SELECT`, and a trigger refuses `UPDATE`, `DELETE` and `TRUNCATE`
even from an admin connection. It carries no foreign keys, deliberately — an
audit row has to outlive the product or the person it describes — and every
administrative write commits it in the same transaction as the change.

`bin/pos_migrate.dart` grants **two** database roles: `--grant-to` for the till,
`--grant-admin-to` for the Management section. Both credentials end up on the
same disk, so this is not a wall; it is the difference between a password
sitting on a machine in a public room being able to reprice the menu and reset
PINs, and not.

**Management** is at `/management`, reached from the start screen and gated on a
PIN that holds `staff.manage`. Its refusals and audit labels are collected in
`lib/features/admin/presentation/admin_messages.dart` and its strings are in
`AppStrings`, English and Arabic.

## Not built yet

USB printer and scanner ports · the tablet and handheld shells (the
breakpoints exist; only the wide shell is finished) · the ETA e-seal and
submission client (everything else about e-receipts is built — see below).

Refunds, discounts, price override, catalogue administration, order history,
combos, per-branch pricing, the cash drawer and business day, menu import from
a spreadsheet and the permission model have all landed since this list was last
correct — and since then **combo authoring** (Management › Menu › Combos) and
**profit** (below). Arabic covers Management too: `AppStrings` is abstract, so a string
that exists in English and not in Arabic does not compile.

**The cloud path is built and verified end-to-end (2026-09-04).** A cloud
terminal claims against the hosted platform with a pairing code (or staff
credentials), holds an `xdt_` device token in the OS keystore, seeds its local
PostgreSQL from the `/api/pos/bootstrap` bundle (catalog, staff + PIN
verifiers, tables, money rules), and drains its durable outbox to
`POST /api/pos/orders` — server-priced, idempotent, with the authoritative
invoice number recorded back and rejections quarantined per error code, never
discarded. The sync loop (heartbeat → config-version refresh → drain) runs
automatically, after every settled sale, and from a tap on the sync pill.
See `lib/data/cloud/` and `docs/coordination/BACKEND_TO_POS.md`.

**Arabic is wired for the current shell.** The terminal locale is persisted,
`MaterialApp` applies it, and Flutter supplies RTL directionality. Thermal
receipt output remains Latin-only because ESC/POS Arabic code pages vary by
printer model.

**Sign-in is by name and PIN.** The lock screen asks for both: a PIN alone is
four digits that get shared and watched over a shoulder, and a till is shared, so
the person coming back to it is often not the one who locked it. Whoever signs in
becomes `signedInStaffProvider` — the name on the top bar and the receipt, and
the capabilities every check resolves against — and opening a shift records who
gave the PIN, so the person answerable for the cash is on the record. The PIN is
PBKDF2-HMAC-SHA256 (`POS-BE-024`), verified against the branch database, so it
works offline.

## Combos and profit

**Combos** are meals at one price, built from real menu items. Management ›
Menu › **Combos** creates and edits them — choices ("Choose a drink"), the items
in each, an optional upgrade price per item, min and max, category, SKU. A combo
is retired with a switch, never deleted: an order line names it. Offline tills
only; on a cloud till the platform authors the catalogue and the sync would
erase a local one.

**Profit** is on Reports › Items, under the list, and is the second sheet of that
page's Excel export. It reads what each stocked item cost when it was sold (the
moving average from purchasing, recorded on the sale's stock movement) against
what it sold for. It is deliberately modest about what it knows:

* only **stocked** items have a cost — a dish or a combo shows revenue and no
  cost, and the page says how much of the revenue it covers;
* a sale at a cost of **zero** counts as *not costed*, not free (the Stock pane
  shows the same thing as a dash and a "no cost" tag);
* a **refund** takes the revenue back and leaves the cost spent;
* on a **tax-inclusive** restaurant the tax is taken out of the revenue, order
  by order, from the tax each order recorded — exact for an order at one rate, an
  estimate where rates are mixed — and the column is headed "Amount, no tax"; the
  page says so.

An item with stock and no cost can be given its first cost from the **Stock
pane** ("Set cost"): recorded as an `opening` movement of quantity zero, audited,
and only for an item that has none — changing an existing cost is a revaluation,
which this does not do. Sales already made stay uncosted; it prices what is sold
from then on.

Design and the reasoning: `docs/pos/16-back-office-scope.md` (§3 and its
4 October update) and `docs/pos/14-progress.md` §6.

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

Database credentials are stored with `flutter_secure_storage` (Keychain on
macOS and the platform credential store on Windows). Cloud-mode sales are
recorded in a transactional PostgreSQL outbox, but no drain exists until the
platform order contract is finalized. A till still cannot sell while its own
PostgreSQL source of truth is unreachable.

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
| Licence | Production issuer/key rotation still needs deployment coordination | Calls the hosted activation API and verifies Ed25519 signatures locally |
| Hardware | USB transports still need platform channels | Discovers and tests network ESC/POS printers over TCP 9100 |
| Arabic receipts | ESC/POS Arabic code pages differ by printer | The app shell is RTL/localized; unsupported receipt glyphs are not emitted as mojibake |

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
again with a different `--terminal` for each additional till — and the same
`--staff-username`, because a restaurant has one owner. Pointed at a restaurant
whose owner is somebody else, `--seed` names them, creates nobody and exits 65.

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

For a **demo or a bring-up till** — where the point is to show the thing working,
not to sell anyone's food — there is a flag that writes ten placeholder products,
two option groups and eight tables:

```bash
POS_PG_PASSWORD=… dart run bin/pos_migrate.dart --host 192.168.1.20 \
  --user postgres --seed-catalogue --slug amer
```

Deliberately **not** part of `--seed`, for the reason above: a real install must
never quietly acquire fictional prices. It refuses to touch a restaurant that
already has products, so it cannot overwrite a real menu, and every item is
prefixed `DEMO-` so a stray one is obvious in a report.

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

No PostgreSQL to hand? A throwaway container is enough, and the fixture's
defaults (user `pos_till`, password `postgres`) match it:

```bash
docker run -d --rm --name xorder-pos-test-pg -p 127.0.0.1:5544:5432 \
  -e POSTGRES_USER=pos_till -e POSTGRES_PASSWORD=postgres postgres:16-alpine
POS_PG_HOST=127.0.0.1 POS_PG_PORT=5544 flutter test test/data/reports_test.dart
docker stop xorder-pos-test-pg
```

Two things a new database suite trips over: an option `RESTRICT`s deleting its
product, so a suite that wipes restaurants must `DELETE FROM pos_combos` first;
and the audit ledger is append-only, so a test that reads it must filter by
restaurant, because earlier tests' rows are still there.

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

Terminal provisioning has two real implementations: `CloudProvisioningRepository`
(claim a dashboard-issued pairing code, receive the bootstrap bundle — `POS-BE-023`)
and `PostgresProvisioningRepository` (register the terminal against the branch
database, offline). `FakeProvisioningRepository` is for tests.
