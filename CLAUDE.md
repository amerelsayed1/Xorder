# CLAUDE.md — XOrder POS

Offline-first **desktop point of sale** for Windows and macOS, built in Flutter as a
module of [XOrder](https://xorder.io). Desktop-first: a keyboard-driven three-pane
selling screen for a cashier at speed. It is a **client of the XOrder backend**
(`apps/api` in the sibling `xorder-cloud` repo, remote `amerelsayed1/Xorder-Menu`); this
repo's remote is `amerelsayed1/xorder-pos`.

This file is loaded every session — keep it tight. Depth lives in `README.md` (run +
design language) and the numbered docs in `docs/pos/`. Read those only when you need it.

## Workspace layout (pos-split-apps, stages 1–3 done)

The repository is a Dart pub workspace: the root `pubspec.yaml` lists the members and holds
the one `pubspec.lock`. **One codebase, two apps, one mode each** (plan: the workspace's
`docs/features/pos-split-apps/TECHNICAL.md`):

| Member | What |
|---|---|
| `packages/shared_module/` | The shared till (package `shared_module`; the database it creates is still called `xorder_pos`): every `lib/`, `test/`, `bin/`, `tool/` path below is inside it. No app, no mode of its own |
| `apps/xorder_pos_offline/` | **XOrder POS - Offline**: `main.dart` + `wiring.dart`, `windows/`, `macos/`, and the back office (`lib/features/admin/`, 60 panes) with its tests |
| `apps/xorder_pos_cloud/` | **XOrder POS - Cloud**: `main.dart` + `wiring.dart`, platforms, the cloud sync (`lib/data/cloud/`: outbox drain, `cloud_sync`, bootstrap, provisioning), the encrypted SQLite datastore (`lib/data/local/`), the dashboard signpost, `integration_test/` |
| `packages/xorder_pos_test_support/` | Fakes, fonts, the PostgreSQL fixture — a dev dependency of every member's tests |

The apps fix the mode in `runPos(mode:, overrides:)` and bind their own code over shared
providers (`cloudSyncProvider`, `provisioningRepositoryProvider`, `bootstrapSeedingProvider`,
`platformBranchSalesProvider`, `backOfficeProvider`). `test/package_boundaries_test.dart`
fails if the shared package imports either app or the apps import each other.

## Repo map (`lib/` is layered; UI never reaches past a repository interface)

| Path | What |
|---|---|
| `lib/core/money/` | Integer **minor units**, half-up rounding, currency exponents |
| `lib/core/ui/` | Design tokens (`tokens.dart`), Material theme, shared widgets |
| `lib/core/config/` | Deployment mode (`cloud` · `offline`, one per app) + sync policy |
| `lib/core/security/` | Terminal fingerprint, PIN hashing |
| `lib/domain/models/` | Catalog, ticket, table — **plain Dart, no Flutter** |
| `lib/domain/services/ticket_engine.dart` | **Every ticket mutation and money rule.** Pure, unit-tested |
| `lib/domain/repositories/` | The contracts the UI depends on — the seam |
| `lib/data/postgres/` | PostgreSQL datastore: pool, migrations, repository implementations |
| `lib/data/cloud/` | Only `cloud_api` (both apps: licence renewal) and `device_token_vault`; the sync, drain, bootstrap and provisioning are the cloud app's |
| `lib/features/admin_mode/` | Shared Admin Mode: the door (`admin_session`, shortcut), supervisor override, admin messages, and `back_office_contract` (pane/tab enums, `BackOffice`) |
| `lib/data/fakes/` | Test doubles. **Not bound by the app** — injected only by tests |
| `lib/data/unconfigured/` | What the till binds before it has a database: empty, never invented |
| `lib/features/` | `setup · start · lock · floor · sale · payment · receipt · refund · shift · cash · history · home · settings · licensing · admin_mode` (the back office itself is `apps/xorder_pos_offline/lib/features/admin/`) |
| `lib/app/providers.dart` | **Riverpod DI — the one place implementations are chosen.** Swapping datastore/transport touches this file, nothing in `domain/` or `features/` |
| `lib/app/router.dart` | go_router (the desktop shell swaps whole screens) |
| `bin/pos_migrate.dart` | Install-time: creates the branch schema + grants the till role |
| `bin/pos_licence.dart` | Licence tooling |
| `docs/pos/` | Numbered design + implementation docs (`01…19`, `production-readiness`) |
| `docs/coordination/` | Backend contract negotiation (`POS-BE-xxx`, `CB-xx`) |
| `apps/xorder_pos_cloud/integration_test/` | The assembled cloud app driven through the UI against a real database |

## Commands

```bash
flutter pub get                                   # anywhere in the workspace; resolves it all
cd apps/xorder_pos_offline && flutter run -d macos  # or apps/xorder_pos_cloud; or -d windows
cd packages/shared_module && flutter test            # the shared suites; each app has its own test/
flutter analyze                                   # in any member; flutter_lints; keep clean
scripts/check.sh                                  # THE verification: every member, PostgreSQL included, then the cloud-till suites on SQLite (not run in CI)
cd packages/shared_module && dart bin/pos_migrate.dart  # prepare a branch PostgreSQL before first run
```

## Load-bearing facts (trust THIS over older prose in README/docs)

- **Money is integer minor units end-to-end — never a `double`.** Rounding is **half-up,
  applied once at the tax line**, matching the server's `decimal:2` cast. See `lib/core/money/`.
- **Tax is provisional device config, not yet server-authored.** Service **12%** (dine-in
  only); VAT **14%** on `subtotal + service`. Read-only on the device; the server is meant
  to become the author of tax — contract `POS-BE-013`. Any receipt from device config says
  so on the slip.
- **The `TicketEngine` is pure and holds every money/ticket rule.** No Flutter imports; it
  is unit-tested without a widget tree. Money logic goes here, not in widgets.
- **The DI seam is `lib/app/providers.dart`.** The UI depends only on the interfaces in
  `lib/domain/repositories/`. The app **binds real `Postgres…` and `Cloud…` repositories**
  there — the `Fake` implementations are for tests only (an early build bound fakes app-wide,
  which is why a first run once showed a restaurant nobody owns; that is fixed). Swapping a
  repository to an `Api…`/HTTP implementation as a contract reaches `READY` is a one-line
  change here.
- **Two engines, one set of repositories** (pos-cloud-single-till-sqlite, 2026-11-08). The
  **Offline** app keeps **PostgreSQL** on the branch server, reached directly with the pure Dart
  `postgres` package and shared by every till on the LAN. The **Cloud** app keeps each till's data
  in **one encrypted SQLite file** (`package:sqlite3`, SQLite3MultipleCiphers in SQLCipher mode; key
  in the OS secret store; `apps/xorder_pos_cloud/lib/data/local/cloud_datastore.dart`), every
  cloud till on its own. Repositories are written once in PostgreSQL SQL against the seam in
  `lib/data/sql/` (`SqlDatabase`, `Sql.named`, `row_reads.dart`); `lib/data/sqlite/` translates the
  PostgreSQL forms they use and holds the generated schema (`tool/gen_sqlite_schema.dart`) and
  hand-written triggers. **A new PostgreSQL migration on a table a cloud till uses needs a
  `sqliteUpgrades` entry** (a test fails until it has one). The outbound sync queue is the
  `pos_outbox` table in either engine; nothing under `lib/` imports `sqflite`.
- **Contract status lives in `docs/coordination/BACKEND_TO_POS.md` — read its table, not this
  file.** At last check `POS-BE-006/007/008/009/013/023/024` (orders, idempotency, invoice
  sequence, shifts, money config, provisioning, PIN) are `READY`; branch-server, upstream-sync
  and setup contracts are `APPROVED`. Integrate against `READY` items only; keep local/fake
  implementations for the rest.
- **Two deployment modes, one API + schema:** `cloud` · `offline` (`lib/core/config/deployment.dart`;
  legacy wire values `branch_server`/`standalone` parse to `offline`). **Cloud and offline setup are both built** (the licence decides which the wizard offers). Every mode is
  offline-first; a desktop till always has a disk. Decisions: `docs/pos/adr/`, roadmap: `docs/pos/20-implementation-roadmap.md`.
- **Unconfigured, it refuses to take money, on purpose.** No database → logo-only welcome
  screen; **Ctrl+Shift+S** (⌘+Shift+S on macOS) opens the setup wizard.
- **Design language, two rules:** border-radius is **0 everywhere**; **no shadows** —
  elevation is a border (`1px` resting, `2px` emphasised). Numbers render in mono. Colours,
  type and dimensions are transcribed into `lib/core/ui/tokens.dart` — the single source.
  Font gap: Archivo/IBM Plex Mono/Tajawal are named but the platform substitutes until
  `.ttf`/`.otf` files are added to `assets/fonts/`; layout does not depend on the substitution.
- **State/routing:** Riverpod (so the engine is testable without a widget tree) + go_router
  (the desktop shell swaps whole screens rather than pushing a mobile stack).
- **Licensing is offline:** Ed25519 signatures (public key in the binary, private key stays
  on the licence server). Cashier PIN is **PBKDF2-HMAC-SHA256**; SHA-256 for the terminal
  fingerprint.

## Testing

- `flutter test` stays **green with no database**: suites tagged `integration` self-skip when
  `POS_PG_HOST` is unset (declared in `dart_test.yaml`).
- `apps/xorder_pos_cloud/integration_test/` runs the assembled cloud app through the UI
  against a **real** PostgreSQL — point it at one to exercise the datastore.
- Every member has suites: `packages/shared_module/test` (shared), `apps/*/test` (the code each
  app owns). Test support (`fakeRepositoryOverrides`, `loadPosFonts`, `PgFixture`) is
  `package:xorder_pos_test_support/…`. All PostgreSQL suites share one database per
  checkout, named from the workspace root.
- **Verification runs locally, not in CI.** Run `scripts/check.sh` before pushing; it needs a
  local PostgreSQL (defaults to `127.0.0.1:5432` as `$USER`; override with `POS_PG_*`).
- **CI only builds and install-tests the Windows installer, and only when started by hand**
  (`gh workflow run windows-installer.yml --ref <ref>`). A release is a green
  `scripts/check.sh`, then a tag, then a manual run on that tag.

## Token hygiene

- Don't read `pubspec.lock` whole, or the long import block at the top of
  `lib/app/providers.dart` — `grep` for the name you need.
- Search tools already skip `build/`, `.dart_tool/`, platform folders (`android/`, `ios/`,
  `windows/`, `macos/`, `linux/`, `web/`) — they're excluded in `analysis_options.yaml`.
- Prefer this map over re-globbing; open the numbered `docs/pos/` docs for design/spec depth
  and `docs/coordination/` for the live contract state instead of re-deriving them from code.
