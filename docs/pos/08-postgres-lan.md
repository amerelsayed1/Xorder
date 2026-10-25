# 08 — PostgreSQL on the LAN (research)

**Status:** **decided and implemented 2026-08-26.** See the *Decision* box below.
The client code is `lib/data/postgres/`; the rest of this document is the
research it was built from and remains accurate.

> ## Decision — **owner, 2026-08-26**
>
> **Topology A, behind repository contracts. PostgreSQL is the primary
> datastore in every mode — on the till itself for a single-terminal plan, on a
> shared box for a multi-terminal one. SQLite is not the primary store.**
>
> This reverses the recommendation this document originally carried. It is the
> owner's call and it is implemented: `lib/data/postgres/`.
>
> **What goes over SQL, and what does not.** Only the money path talks to
> Postgres directly. A shared box still runs the whole `apps/api` stack, so
> the heartbeat that keeps a till visible to Super Admin (`POS-BE-022`),
> licence refresh, provisioning and the QR menu all still travel over HTTP to
> the same box, which forwards upstream. This is a hybrid, not an abandonment of
> the API.
>
> **The seam is kept deliberately thin.** `PostgresOrdersRepository` implements
> `OrdersRepository` and nothing outside `lib/data/postgres/` imports the driver.
> `ordersRepositoryProvider` is the single swap point: the day `POS-BE-006` is
> `READY`, an `ApiOrdersRepository` replaces it there and neither `lib/domain/`
> nor `lib/features/` changes.
>
> **What the database now enforces, rather than the client hoping:**
>
> | Guarantee | Mechanism |
> |---|---|
> | Idempotency (`POS-BE-007`) | `UNIQUE (restaurant_id, client_transaction_id)`; a replay returns the original id *and* the original invoice number |
> | Invoice sequencing (`POS-BE-008`) | `pos_invoice_sequences` row locked `FOR UPDATE` inside the insert transaction. A replay does not consume a number |
> | Split tender (`BE-A01`) | `pos_order_payments` rows, not columns on the order |
> | Money | `bigint` minor units with a stored exponent. Never `numeric`, never a float |
> | Atomicity | One transaction covers the sequence bump, the order, its lines and its payments |
> | Migrations | `pg_advisory_xact_lock` + `schema_migrations`, so six tills booting after an update cannot race |
>
> All six are verified against a real PostgreSQL in
> `test/data/postgres_integration_test.dart`, including eight concurrent
> settlements receiving eight distinct invoice numbers.
>
> ### Costs accepted with this decision
>
> Recorded because they are real, not to reopen the choice:
>
> 1. **Every till holds a database credential.** Bounded, not removed: the role
>    is `pos_till` with `SELECT`/`INSERT` on the POS tables and no `DELETE`, no
>    `UPDATE` on settled orders and no DDL (§7), and it is what the setup wizard
>    defaults to. One role per terminal makes a lost machine one
>    `ALTER ROLE … NOLOGIN`. The password is collected in the wizard, kept in
>    memory and **never** serialised into device config — a password in a config
>    file is a password that ends up in a support email.
> 2. **No local write-ahead means no selling when the branch box is down.** This
>    is the sharpest edge. The codebase rule is *a till never bricks*, and with
>    Postgres as the only store, a rebooting switch or a sleeping host stops
>    trade. The mitigation is operational — a dedicated always-on box, a static
>    IP, a UPS — plus the local outbound queue, still unbuilt, which would
>    restore the write-ahead without changing this decision.
> 3. **Pricing is local until `POS-BE-006`.** The till is the authority on what a
>    ticket costs. `TicketEngine` is pure and tested, so this is defensible, but
>    it is not auditable centrally the way a server-priced order is.
> 4. **Schema changes need every till on a compatible build.** The migration list
>    is append-only and advisory-locked, which makes the rollout safe; it does
>    not make a mixed-version fleet safe.

---

## 1. What this changes about the existing plan

`03-offline-strategy.md` assumes: SQLite on each till → sync queue → cloud API.

A LAN Postgres replaces the **middle** of that, not the ends:

```
  before   [till: SQLite] ──queue──▶ [cloud API]
  after    [till: SQLite] ──queue──▶ [LAN Postgres] ──▶ [cloud API]   (recommended)
  or       [till] ─────────direct SQL─────────────────▶ [LAN Postgres]  (simplest)
```

The rule from `03` — *durable before the UI moves on* — is the deciding factor. A
till that writes only to LAN Postgres is offline the moment the switch reboots,
the host machine sleeps, or someone unplugs the wrong cable. In a restaurant that
is not a rare event. **Keep the local SQLite write-ahead.** Postgres becomes the
branch-level source of truth that the queue drains into, and the cloud sync
becomes one job on the Postgres host instead of six tills each holding a queue.

---

## 2. Three topologies

### A. Direct SQL from every till

Each Flutter client opens a `Pool` to `postgres://…@192.168.1.10:5432/xorder_pos`.

- **For:** no server code at all. Transactions, sequences, `FOR UPDATE`, and
  `LISTEN/NOTIFY` are available directly. Fastest thing to stand up.
- **Against:** the DB password ships inside the app on every till. A cashier with
  file access has full SQL access to the branch's books — the OS store (DPAPI /
  Keychain, `lib/data/config/secret_store.dart`) raises the bar but does not remove it, because the app must be able to decrypt
  it to connect. Schema changes require every till to be on the same build. No
  offline selling unless SQLite stays.
- **Verdict:** fine for a single-site pilot behind a locked network. Not what a
  multi-tenant product ships.

### B. One machine is the server *and* a till

The host runs Postgres plus a small local HTTP service; satellites talk HTTP to
it, never SQL. The service can be a `shelf` server inside the same Flutter binary,
or a separate Dart/Laravel process.

- **For:** the DB password exists on exactly one machine. Satellites hold a token,
  which is revocable. Same request/response shape as the cloud API — the existing
  `Api…Repository` implementations point at `http://pos-host.local:8080` instead of
  the cloud, and `POS-BE-006`/`007` semantics are preserved end to end.
- **Against:** you are writing and operating a small server.
- **Verdict:** the right answer if satellites are tablets/phones, or if this ever
  leaves a controlled network.

### C. Postgres as the branch hub, tills stay SQLite-first (**recommended**)

Topology A or B for the wire, but the till keeps its local DB and queue exactly as
`03` specifies. Postgres is what the queue drains into.

- Nothing in `03` is thrown away — queue, backoff, dead-letter, status UI all still
  earn their keep.
- A till survives the host rebooting mid-service.
- Invoice numbering, cross-till table state and X/Z reports get a real shared
  transactional store, which SQLite-per-till cannot give you.

---

## 3. The Dart client

```yaml
dependencies:
  postgres: ^3.5.12
```

Pure Dart, no native plugin, no DLL to vendor (unlike `sqflite_common_ffi` on
Windows). Works on desktop and mobile. **Does not work on Flutter web** — no raw
sockets in a browser.

```dart
// Pool, not Connection: the UI, the sync worker and the printer job all want
// their own session, and reconnect-on-drop is handled for you.
final pool = Pool.withEndpoints(
  [Endpoint(
    host: host,              // from device config, see §9
    port: 5432,
    database: 'xorder_pos',
    username: 'pos_till',
    password: password,      // DPAPI / Keychain via SecretStore.forPlatform()
  )],
  settings: const PoolSettings(
    maxConnectionCount: 4,
    connectTimeout: Duration(seconds: 5),
    queryTimeout: Duration(seconds: 10),
    sslMode: SslMode.require,
  ),
);

await pool.runTx((s) async {
  await s.execute(
    r'INSERT INTO pos_orders (client_transaction_id, total_minor) VALUES ($1, $2)'
    r' ON CONFLICT (client_transaction_id) DO NOTHING',
    parameters: [id, totalMinor],
  );
});
```

Two details worth knowing:

- **Always use `$1` parameters.** Never interpolate. The extended query protocol
  is both the fast path and the injection-safe one.
- **`ON CONFLICT DO NOTHING` on `client_transaction_id` is the idempotency
  contract** from `03 §4`, enforced by a unique index instead of by a server
  team. This is the single biggest thing Postgres buys you here.

`Connection.openFromUrl('postgresql://…?sslmode=verify-full')` is the URL form;
`Pool.withUrl` accepts `max_connection_count`, `max_connection_age` and friends as
query parameters.

> **As built (ADR-006 slice C, 2026-10-25):** the app never uses `SslMode.require`
> — in this package it accepts *any* certificate. Off loopback it is `verifyFull`,
> either against the platform's roots or with a `SecurityContext` whose only trust
> anchor is the certificate the till was paired with
> (`lib/data/postgres/pos_tls.dart`); plaintext only under a technician's audited
> override. A refused handshake is an error, never a retry in the clear.

---

## 4. Platform gates that will bite before any SQL runs

### macOS — the app currently cannot open a socket at all

`macos/Runner/Release.entitlements` has only `com.apple.security.app-sandbox`, and
`DebugProfile.entitlements` has `network.server` but **not** `network.client`. A
sandboxed macOS app with no `network.client` entitlement gets its outbound
connections refused by the OS, not by Postgres. Add to **both** files:

```xml
<key>com.apple.security.network.client</key>
<true/>
```

Note this is also why `dio` calls to the cloud API have not been exercised yet —
the same entitlement gates them.

### macOS 15+ — local network permission

Connecting to a private-range address triggers the system Local Network prompt.
Denied once, it is silent afterwards and only recoverable through System Settings.
The app needs to detect the failure and say *"allow XOrder POS to access devices
on your local network"* rather than showing a generic connection error.

### Windows — firewall on the host

The first bind prompts on the **host**; satellites need no entitlement. See §6.

---

## 5. Getting Postgres onto the host machine

| Option | Good for | Cost |
|---|---|---|
| Official EDB installer | pilots, a shop with an IT person | manual, per-site |
| Docker Desktop | dev machines | heavy for a restaurant PC; licensing |
| **Portable binaries shipped with the app** | product install | most work up front, best experience |

The portable route is what "the POS installs its own database" means in practice:
ship the Postgres binary directory, run `initdb -D <appSupport>/pgdata -U pos -E UTF8`
on first launch, then `pg_ctl start` as a child process (or register a Windows
service so it survives logout). EDB publishes binaries-only zips for Windows and
macOS; the Node (`@embedded-postgres/*`) and Rust (`postgresql-embedded`)
ecosystems do exactly this and are worth reading as prior art. Budget ~150–300 MB
in the installer and a real chunk of work on lifecycle: start, stop on shutdown,
crash recovery, version upgrade (`pg_upgrade` across a major version is not free).

Do not run `initdb -A trust` on anything that listens beyond `localhost`.

---

## 6. Host configuration for LAN access

`postgresql.conf`:

```conf
listen_addresses = '192.168.1.10,127.0.0.1'   # the LAN IP, not '*'
port = 5432
password_encryption = scram-sha-256
ssl = on
ssl_cert_file = 'server.crt'
ssl_key_file  = 'server.key'
max_connections = 100
```

`listen_addresses` requires a **restart**; a reload is not enough.

`pg_hba.conf` — order matters, first match wins:

```conf
# TYPE  DATABASE     USER       ADDRESS           METHOD
local   all          pos_admin                    scram-sha-256
host    xorder_pos   pos_till   192.168.1.0/24    scram-sha-256
hostssl xorder_pos   pos_till   192.168.1.0/24    scram-sha-256
```

Never `0.0.0.0/0`. Never `trust` on a `host` line.

> **What the Windows installer writes (ADR-006 slice C).** With the *Let other tills
> on this network use this database* task, `installer/provision.ps1` makes a
> self-signed certificate (825 days; computer name, `.local`, FQDN and every private
> IPv4 as SANs) into `server.crt`/`server.key` in the data directory — key readable
> by the service account only — and writes `ssl = on`, `ssl_cert_file`,
> `ssl_key_file` and `ssl_min_protocol_version = 'TLSv1.2'`, plus **`hostssl`** lines
> for 10/8, 172.16/12 and 192.168/16 (`scram-sha-256`). The public half is copied to
> `%ProgramData%\XOrder POS\server-certificate.pem`, which is where Management ›
> Devices reads the fingerprint a child is paired against. No certificate, no LAN:
> the script leaves PostgreSQL on `localhost` rather than opening it in plaintext.
> A re-run keeps the certificate (and every till's pairing) until its last 60 days.
>
> A technician who needs plaintext tills accepted as well runs, elevated,
> `powershell -ExecutionPolicy Bypass -File "<app>\tools\provision.ps1" -AppDir "<app>" -Lan -LanTls Off`
> (`host` instead of `hostssl`; encrypted tills still work), and `-LanTls On` to take
> it back. **Pass `-Lan` every time** — a run without it closes the LAN. An upgrade of
> an install from before slice C carries plaintext acceptance over until `-LanTls On`,
> because every till it already had was set up unencrypted.

Windows firewall on the host, scoped to the subnet:

```powershell
New-NetFirewallRule -DisplayName "XOrder POS Postgres" -Direction Inbound -Protocol TCP -LocalPort 5432 -RemoteAddress 192.168.1.0/24 -Action Allow
```

Set a **static IP or DHCP reservation** for the host. A router that reissues
`.10` to a phone at 7pm on a Friday is a whole-branch outage.

---

## 7. Roles and the credential problem

Under topology A the client credential is recoverable by anyone with the machine.
Reduce what it can do:

```sql
CREATE ROLE pos_admin LOGIN PASSWORD '…';           -- migrations only, never shipped
CREATE ROLE pos_till  LOGIN PASSWORD '…';           -- what the app carries

REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT CONNECT ON DATABASE xorder_pos TO pos_till;
GRANT USAGE  ON SCHEMA public TO pos_till;
GRANT SELECT, INSERT ON pos_orders, pos_order_lines, pos_payments TO pos_till;
GRANT SELECT ON menu_items, categories, tax_rules TO pos_till;   -- read-only reference
-- deliberately NOT granted: DELETE anywhere, UPDATE on settled orders, DDL
```

Then: one role per terminal so a lost machine is one `ALTER ROLE … NOLOGIN`;
`sslmode=verify-full` with a pinned root cert so a laptop on the guest Wi-Fi
cannot MITM the connection (**built in slice C**: the child's setup step shows the
server certificate's SHA-256, the technician compares it with the main device and
confirms, and the till trusts exactly that certificate from then on — ADR-006); and treat the local DB password like the access
token in `03 §3` — Keychain/DPAPI, never in the `.db` and never in the repo.

None of this fixes the underlying issue, only bounds it. That is the argument for
topology B.

---

## 8. Things a shared Postgres solves that per-till SQLite cannot

**Invoice sequences (`POS-BE-008`), locally.** A branch-scoped `SEQUENCE` gives
gap-free-enough, collision-free numbering across six tills without a round trip to
the cloud:

```sql
CREATE SEQUENCE invoice_seq_branch_1 START 1;
SELECT nextval('invoice_seq_branch_1');
```

**Two tills opening the same table.** The classic POS race. Either pessimistic:

```sql
SELECT * FROM dining_tables WHERE id = $1 FOR UPDATE;   -- inside runTx
```

or optimistic, with a `version` column and `WHERE version = $2` on the update,
where zero affected rows means "someone else got there first" and the UI says so.
Optimistic is friendlier at a till — nobody is holding a lock while a cashier
thinks.

**Live floor state via `LISTEN/NOTIFY`.** Table goes occupied on till 1, the floor
plan on till 2 updates without polling. `Connection` exposes `channels` for this —
note it is on `Connection`, not `Pool`, so keep one dedicated long-lived
connection for subscriptions alongside the pool:

```sql
CREATE FUNCTION notify_table_change() RETURNS trigger AS $$
BEGIN PERFORM pg_notify('table_state', NEW.id::text); RETURN NEW; END;
$$ LANGUAGE plpgsql;
```

This is a genuinely good fit for a POS and is the strongest single argument for
Postgres over SQLite at the branch level. It also covers a kitchen display screen
later with no extra infrastructure.

**Migrations run once, not six times.** Six tills booting after an update will
race the migration list. Wrap it in an advisory lock:

```sql
SELECT pg_advisory_lock(727101);   -- any constant; released on commit/close
```

and version with a `schema_migrations` table rather than `PRAGMA user_version`.
Keep the ordered hand-written list from `03 §3` — the discipline transfers, only
the version store changes.

---

## 9. Finding the host

- **Config screen (do this first).** Host / port / database, a **Test connection**
  button that reports which of the four failure modes it hit — DNS, TCP refused,
  auth rejected, TLS rejected — and stores to device config. Boring and it always
  works. `lib/features/setup/` already exists for exactly this kind of thing.
- **mDNS (nice second).** `nsd` (discovery *and* registration), `flutter_nsd`
  (discovery only; on Windows it is a socket implementation, not an OS API, and
  triggers a network-access dialog on first launch), or `bonsoir`. Resolves
  `pos-host.local` so a router handing out a new IP is not an outage. Treat it as
  a convenience on top of manual config, never the only path — mDNS is the first
  thing a hardened corporate switch blocks.

---

## 10. Schema notes for this codebase

- **Money stays integer minor units.** `bigint`, never `numeric`, never `double
  precision`. The Dart type is `int` and the mapping is lossless.
- `client_transaction_id` → `uuid` with a `PRIMARY KEY`, which is what makes the
  `ON CONFLICT` idempotency in §3 work.
- Timestamps → `timestamptz`, always. `03 §1` calls out clock skew; a `timestamp`
  without a zone across a Windows till and a macOS till is how you get an X report
  that does not balance.
- `payload` → `jsonb` rather than `TEXT`. Same round-trip-safety property `03`
  wanted, plus it becomes queryable for the queue inspector.
- Prefer `bigint` over `serial` for ids so a future merge with cloud ids has room.

---

## 11. Backup

A single Postgres host holding a branch's takings with no backup is worse than
six SQLite files, because it fails all at once. Minimum: nightly `pg_dump -Fc` to
a second disk, and WAL archiving if the day's transactions matter more than the
day's. Test the restore before the first real service, not after the first loss.

---

## 12. What was actually done

Steps 1 and 4 below landed. Steps 2, 3 and 5 were overtaken by the decision — the
till writes to Postgres directly rather than draining a SQLite queue into it.



1. ~~**Add `com.apple.security.network.client` to both entitlements files.**~~
   **Done, 2026-08-26.** This was a real bug independent of Postgres: without it a
   sandboxed macOS build cannot open *any* outbound connection, so the `dio`
   calls to the cloud API would have failed the day `POS-BE-006` landed.
2. **Build the SQLite layer from `03` as written.** It is the durability floor and
   it is not wasted under any topology.
3. **Point the sync queue's drain target at LAN Postgres** behind the existing
   repository interfaces — topology C. One `Endpoint` in device config, no widget
   changes, exactly the swap `README` §*Backend status* describes.
4. **Take `LISTEN/NOTIFY` for floor state and the branch invoice sequence.** These
   are the two features that pay for the whole exercise.
5. **Decide A vs B before any non-desktop client exists.** The moment a tablet
   joins, direct SQL from the client stops being defensible and you are writing
   the local service anyway. Better to write it while there is one caller.

> ### Amendment — 2026-08-28: step 5 is deferred against a trigger, not taken
>
> **Owner decision:** Topology A stands for every client. No POS-specific local
> API tier is to be built, and Android is *designed for* rather than shipped.
>
> Step 5 above therefore remains open, but it is no longer open-ended. The
> trigger is recorded and named: **the first non-desktop client.** At that moment
> an Android till would have to hold the `pos_till` credential on a device that
> leaves the building, and A stops being defensible exactly as this step
> predicted.
>
> What makes deferring safe rather than merely convenient is that the answer is
> already a swap and not a rewrite. `ApiOrdersRepository` and its siblings are
> written against POS-BE-006/007/009 and substituted at the repository providers;
> nothing in `lib/domain/` or `lib/features/` changes. The main device serves them
> from the `apps/api` stack the Decision box already has it running.
>
> **The constraint that keeps this true, and it binds every future change:** no
> code outside `lib/data/postgres/` may import the PostgreSQL driver.
>
> Two consequences of §9 (*Finding the host*) are also promoted from
> nice-to-have to committed work: a two-pass /24 sweep on port 5432 as a *Find
> the main device* button, and the specific macOS 15+ local-network error message
> §4 records as needed and not built. mDNS stays rejected, for the reasons §9
> already gives.
>
> See `docs/pos/10-setup-architecture.md` §9–§11 and §21 Phase 6.

---

## 13. Open questions — resolved

- ~~Which machine is the host?~~ For a multi-terminal plan, a dedicated box
  running the same `apps/api` stack — `DeploymentConfig.databaseHost` points at
  it. A manager's till as host is rejected for the reason given: it sleeps, and
  sleep is a branch outage. On a one-terminal plan the host is the till itself
  and the wizard does not ask.
- ~~Does the LAN Postgres replace the cloud backend, or sit in front of it?~~
  **In cloud mode, in front** — `POS-BE-018` still owes the sync. In **offline**
  mode it replaces it for sales, and the licence check-in is what keeps the
  terminal visible to Super Admin instead (`POS-BE-022`). The separate
  `upstreamUrl` field is gone: it existed only for the withdrawn branch-server
  mode, and the mode now answers the same question on its own.
- ~~Desktops only, or is a tablet coming?~~ Moot. The answer was topology B or C
  either way once direct SQL was ruled out.
- ~~Ship Postgres inside the installer?~~ Not on the till — it never runs one. On
  the branch box it is `docker-compose.yml`, which already exists. The packaging
  question that remains is `POS-BE-017`, and it is the backend's.
  **Superseded 2026-09-11:** the owner chose an installer with PostgreSQL
  bundled. The Windows installer's "This machine keeps the database" type does it;
  see `18-windows-installer.md`.

---

## Sources

- [postgres — pub.dev](https://pub.dev/packages/postgres) · [API docs](https://pub.dev/documentation/postgres/latest/)
- [Drift: PostgreSQL support](https://drift.simonbinder.eu/platforms/postgres/)
- [Allow remote connections to PostgreSQL — pg_hba.conf and firewall](https://postgre-sql.github.io/postgresql-allow-remote-connections.html)
- [Configuring PostgreSQL listen_addresses](https://oneuptime.com/blog/post/2026-03-20-postgresql-listen-addresses-ipv4/view)
- [Portable PostgreSQL on Windows without installation (Pg18)](https://notepad.onghu.com/2025/portable-postgresql-on-windows-without-installation-pg18/)
- [postgresql-embedded (Rust, prior art for bundling)](https://github.com/theseus-rs/postgresql-embedded)
- [`@embedded-postgres/windows-x64`](https://www.npmjs.com/package/@embedded-postgres/windows-x64)
- [nsd — Flutter service discovery + registration](https://pub.dev/packages/nsd) · [flutter_nsd](https://pub.dev/packages/flutter_nsd) · [Bonsoir](https://bonsoir.skyost.eu/docs/)
- [Flutter local database landscape 2026](https://luci-studio.com/blog/the-flutter-local-database-landscape-in-2026-a-maintenance-first-guide-fe6d267c/)
