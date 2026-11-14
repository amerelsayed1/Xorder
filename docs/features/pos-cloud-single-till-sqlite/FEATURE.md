# Single-till cloud POS on SQLite — pos-cloud-single-till-sqlite

Status: **built 2026-11-09 (stages 0–6 committed, not pushed); see TECHNICAL.md › Progress** · 2026-11-03 · Source: the owner's request, quoted below · Verified against: xorder-pos `c67c754` (branch `fix/dropdown-consistency`, uncommitted work present, unrelated), xorder-cloud `775bf0f` (not touched by this feature)

> Owner, 2026-11-03: "xorder pos in case of cloud I was thing to use sqlite instead od postgres? what you think?"
> After the assessment recommended SQLite **only for single-till cloud venues, kept alongside PostgreSQL**, the owner replied: "Yes, write it up".

Paths below are relative to `apps/xorder-pos/` unless they start with `docs/` (workspace) or say otherwise.

## 1. Summary

A cloud-mode till whose licence allows exactly one terminal keeps its local data in an embedded SQLite file instead of a local PostgreSQL server. Every other till is unchanged: offline mode and any multi-terminal licence stay on PostgreSQL. The switch happens behind the existing repository interfaces, so the selling screens, the `TicketEngine` and the cloud API do not change.

## 2. Why

- **Who is hurt:** an installer or owner setting up a single cloud till, and the venue when that local database server fails.
- **Today every cloud till runs a PostgreSQL server of its own** (`lib/core/config/deployment.dart:12-16`). For one till that server is pure overhead: a service, ports, two login roles, migrations run by a separate tool, and `pg_dump` for backup.
- **Windows already hides most of this.** The installer bundles PostgreSQL and registers it as the `XOrderPOS-PostgreSQL` service (`installer/xorder-pos.iss:14-19, 42, 117`; `installer/provision.ps1`). The friction there is a heavier install and one more thing that can break, not manual setup.
- **macOS has no installer.** The only install record used a host PostgreSQL (`postgresql@16`, `docs/pos/10-offline-install-runbook.md` §0), and the only installer workflow is `.github/workflows/windows-installer.yml`.
- **Venue models helped:** café (one counter till, pay first) and food truck (one laptop, unreliable power and signal). These are the venues most likely to hold a one-terminal licence. **Not helped:** restaurants with several tills or tablets, and cloud kitchens with several stations; they need the shared PostgreSQL.

## 3. Goal and success

- A one-terminal cloud licence installs, sets up and sells with **no PostgreSQL installed or running** on the machine.
- The same basket gives the **same totals, invoice numbers, receipt and outbox payload** on a SQLite till as on a PostgreSQL till (parity tests).
- A sale committed while offline survives a power cut and reaches the platform exactly once when the network returns.
- Nothing changes for offline mode or multi-terminal licences (their existing test suites stay green).

## 4. Users, roles and permissions

- **Installer or technician:** runs setup. No new permission.
- **Staff at the till:** unchanged. On a cloud till, staff, PIN hashes and capabilities come from the platform bundle (`lib/data/cloud/bootstrap_seeder.dart`, staff upsert per `docs/pos/adr/ADR-002-data-authority.md` line 33).
- **No permission identifier is added, removed or narrowed.** Authorization stays in `lib/domain/services/authorization.dart`.
- **What changes underneath:** today the till's database login role cannot read password hashes or write `pos_staff` directly; administrative work uses a second, admin connection (`docs/pos/adr/ADR-006b-staff-auth-and-db-roles-design.md` lines 26-28; `lib/data/postgres/local_bootstrap.dart:304-310`). SQLite has no login roles. See BR-10 and open question Q4.

## 5. Today

| What | Where | State |
|---|---|---|
| Two modes, `cloud` and `offline`; cloud keeps a local PostgreSQL and syncs it | `lib/core/config/deployment.dart:12-29` | exists |
| Children (tablets, extra desktops) use the main device's PostgreSQL over the LAN | `lib/core/config/deployment.dart:106-133` | exists; SQLite cannot serve this |
| A one-terminal licence forces the database host to `localhost` | `lib/features/setup/application/setup_controller.dart:1488` | exists; natural gate for this feature |
| A one-terminal licence cannot register a second terminal | `lib/features/setup/application/setup_controller.dart:1989-1992`; `setup_state.dart:246-253` | exists; so a SQLite till never needs a child |
| Single datastore seam: one `PosDatabase` (connection pool, `runTx`, `execute`) | `lib/app/providers.dart:2630` (`posDatabaseProvider`), `:2729` (admin); `lib/data/postgres/pos_database.dart:282-437` | exists |
| 43 `Postgres…` repository bindings in the DI file | `lib/app/providers.dart` (count of `Postgres…(` constructors) | exists |
| 40 repository contracts the UI depends on | `lib/domain/repositories/repositories.dart` (31), `admin_repositories.dart` (9) | exists; unchanged by this feature |
| Back-office writers already disabled on a cloud till: catalog admin, business logo, financial-accounts admin | `lib/app/providers.dart:1381, 2993, 3315` | exists |
| PostgreSQL layer: 47 files, about 23,400 lines; 63 migrations in 4,978 lines | `lib/data/postgres/`, `lib/data/postgres/migrations.dart` | exists |
| `package:postgres` imported directly by 30 files, 4 of them outside `lib/data/postgres` | `lib/data/eta/eta_filer.dart`, `lib/data/cloud/{outbox_drain,logo_sync,bootstrap_seeder}.dart` | exists; these must also move behind the seam |
| PostgreSQL-specific SQL in use | row locks `FOR UPDATE` (12 files), `jsonb` (16), `ON CONFLICT` (22), `timestamptz` (3), advisory lock for migrations (`migrations.dart:4952`), a `plpgsql` function (1), `SECURITY DEFINER` auth functions (ADR-006b D3) | exists; each needs a SQLite equivalent |
| Invoice numbers come from a counter table, not a `SEQUENCE` | `lib/data/postgres/migrations.dart:34-36, 144` (`pos_invoice_sequences`), `:2597-2603` (`pos_purchase_sequences`) | exists; portable |
| Outbox drain idempotency key is the order's `client_transaction_id` | `lib/data/cloud/outbox_drain.dart:52, 112-148` | exists; datastore-independent |
| Bootstrap seed is one transaction and never touches orders, outbox or shifts | `bootstrap_seeder.dart:53-104` (per ADR-002 line 32) | exists |
| Backup is `pg_dump -Fc` / `pg_restore` | `lib/data/backup/pg_archive.dart:159-171` | exists; needs a SQLite path |
| Tests: 81 of 106 data-layer test files are tagged `integration` and need a real PostgreSQL | `test/data/`, `dart_test.yaml:1-8` | exists; no SQLite equivalent |
| Any SQLite dependency | `pubspec.yaml` | **missing**; nothing under `lib/` uses SQLite (repo `CLAUDE.md`) |
| macOS installer | `.github/workflows/` | **missing** |

**UNVERIFIED:**
- Which of the repositories still bound on a cloud till are actually reached there: stock items and levels, suppliers, purchase orders, receiving, supplier invoices, reports, units, ETA queue.
- Whether Egyptian Tax Authority (ETA) e-invoicing runs on a cloud till (`lib/data/eta/eta_filer.dart` imports `package:postgres`).
- How often Windows tills actually fail on the bundled PostgreSQL service. No field data was found.

## 6. Scope

**In:**
- Cloud mode, main device, licence `max_terminals = 1`: an embedded SQLite file as the only local datastore.
- SQLite implementations of every repository a cloud till binds (final list depends on Q2).
- A SQLite schema and migration list for those tables.
- The seeder, the outbox drain, logo sync and any other `package:postgres` caller on the cloud-till path, moved behind the datastore seam.
- Setup wizard path for this case that builds the SQLite file with no PostgreSQL step.
- Backup and restore of the SQLite file.
- Windows install type for this case without the PostgreSQL component (depends on Q1).

**Out:**
- Offline mode, at any terminal count. It stays on PostgreSQL.
- Multi-terminal cloud licences, children and tablets.
- The offline back-office writers already disabled on cloud tills.
- Any cloud API, contract or `xorder-cloud` change.
- Replacing or removing PostgreSQL anywhere.
- Turning an existing PostgreSQL cloud till into a SQLite one. Suggestion only; see Q3.

## 7. Behavior and business rules

- **BR-1.** The datastore is chosen from mode, terminal role and licence only: `cloud` + main device + `max_terminals = 1` uses SQLite. Every other combination uses PostgreSQL exactly as today.
- **BR-2.** The choice lives in `lib/app/providers.dart`. The repository contracts in `lib/domain/repositories/`, the `TicketEngine` and every widget are unchanged.
- **BR-3.** Money stays integer minor units end to end, stored as SQLite `INTEGER`. Rounding stays half-up, once, at the tax line (`lib/core/money/`). No `REAL` column holds money.
- **BR-4.** The outbox drain keeps the same idempotency key (`client_transaction_id`), order and retry policy. The platform sees a SQLite till exactly as it sees a PostgreSQL till.
- **BR-5.** The bootstrap seed keeps its rules: one transaction, platform-authored rows replaced, orders, outbox and shifts never touched.
- **BR-6.** Invoice and order numbers are taken from the counter row inside the same write transaction as the order. One till means one writer, so there are no gaps or duplicates from concurrency.
- **BR-7.** A sale is confirmed to the cashier only after its transaction is committed to disk (write-ahead log, synchronous commit).
- **BR-8.** The datastore is fixed at setup. A till never switches datastore silently, not on a licence change, not on an update.
- **BR-9.** The existing refusal stays: with no datastore configured, the till takes no money.
- **BR-10.** A SQLite till must not make staff secrets easier to read than today. The current guarantee is that the till's login cannot read password hashes (ADR-006b). The SQLite design must state its equivalent before it is built (Q4).
- **BR-11.** An offline sale is never lost on licence growth. If the licence goes from one terminal to more, every unsent outbox row is either delivered or carried into the new datastore before the till sells again (Q3).

## 8. Acceptance criteria

- **AC-1.** Given a one-terminal cloud licence on a machine with no PostgreSQL, when setup completes, then the till reaches the selling screen and a test sale commits.
- **AC-2.** Given an offline licence or a multi-terminal cloud licence, when setup runs, then PostgreSQL is used exactly as today.
- **AC-3.** Given the same seeded catalog and the same basket, when it is sold on a SQLite till and a PostgreSQL till, then subtotal, service, VAT, total, invoice number and the outbox payload are identical.
- **AC-4.** Given a sale committed while offline, when the process is killed and restarted, then the sale, its payments and its outbox row are present and unchanged.
- **AC-5.** Given unsent outbox rows, when the network returns, then each order reaches the platform once. Given a resend after a lost response, the platform replays and no duplicate is created.
- **AC-6.** Given a new platform bundle, when it is applied and fails halfway, then the catalog is unchanged and orders, shifts and outbox are untouched.
- **AC-7.** Given an open shift with cash movements and refunds, when the shift is closed, then the X/Z figures match the PostgreSQL implementation for the same events.
- **AC-8.** Given a SQLite till, when a backup is taken and restored, then the restored file opens and holds every committed sale. A file that does not read back is refused, as with `pg_dump` today.
- **AC-9.** Given a SQLite till whose licence is raised to more than one terminal, when the till next starts, then it follows the path decided in Q3 and loses no unsent sale.
- **AC-10.** Given the staff rows from the bundle, when someone reads the SQLite file outside the app, then the protection decided in Q4 holds. This needs a person to check the chosen mechanism.
- **AC-11.** Given Arabic product, staff and customer names, when they are stored, searched and printed, then they round-trip unchanged and search finds them as it does on PostgreSQL.

## 9. Edge cases and failure modes

- **Power loss mid-write:** the write-ahead log must leave either the whole sale or none of it (AC-4).
- **Disk full, file locked or quarantined** by antivirus or a sync tool such as OneDrive: the till must say so and refuse to take money, not crash or lose a sale.
- **Two app instances** opening the same file: one must be refused.
- **Retries and idempotency:** unchanged keys (BR-4).
- **Tenant boundary:** one file holds one restaurant and branch, as the local PostgreSQL does today. Every query keeps its `restaurant_id` filter.
- **Concurrency:** PostgreSQL row locks become SQLite write transactions started immediately. A single writer is assumed. Background jobs (outbox drain, print queue, bundle apply) must not hold the write lock long enough to block a sale.
- **Search:** SQLite `LIKE` ignores case only for ASCII letters, while the PostgreSQL code uses `ILIKE` (1 repository file). Arabic has no case, but Latin customer names must still match.
- **Digits:** Eastern Arabic digits in input are normalised before storage, as today. UNVERIFIED where that normalisation lives.
- **Dates:** `timestamptz` columns become UTC values. Business-day and shift boundaries must be computed exactly as today.
- **JSON columns** (`jsonb` in 16 files) become JSON text. Queries that index into JSON must be checked one by one.
- **Library version:** `ON CONFLICT … DO UPDATE` and `RETURNING` need SQLite 3.35 or later. The bundled native library must be pinned.
- **Very large data:** years of orders in one file. The design must cover file growth and history queries.
- **Licence limits:** BR-11 and Q3. A one-terminal licence already cannot add a second terminal.
- **Reinstall and uninstall:** the file must survive both, as the PostgreSQL data does today (`installer/xorder-pos.iss:21-25`).

## 10. Impact

- **Repos and apps:** `xorder-pos` only. `xorder-cloud` is not touched.
- **API and contract:** none. No `POS-BE-xxx` item changes, and the till depends only on items already `READY`.
- **Data and migrations:** a new SQLite schema and migration list, kept in step with the 63 PostgreSQL migrations for every table a cloud till uses. Every future migration on those tables must be written twice. No change to any existing PostgreSQL migration.
- **Dependencies:** a new SQLite package and a bundled native library. **Needs owner approval** under the workspace rule on new tools.
- **Code:** a datastore seam above `PosDatabase`; SQLite repositories for the cloud-till set; `eta_filer`, `outbox_drain`, `logo_sync` and `bootstrap_seeder` moved off direct `package:postgres` use; a SQLite backup path beside `pg_archive.dart`.
- **Installer:** a Windows install type for a one-terminal cloud till without the PostgreSQL component. macOS packaging is out of scope until Q1 is answered.
- **Permissions:** none added or narrowed. The database-role protection is replaced by whatever Q4 decides.
- **Localization:** new setup and error strings in English and Arabic (`lib/core/l10n/app_strings.dart`).
- **Documentation:** a new ADR; updates to `docs/pos/08-postgres-lan.md` (its "PostgreSQL in every mode" verdict), the repo `CLAUDE.md` fact "Primary datastore is PostgreSQL", `docs/FEATURE_INVENTORY.md`, and this folder's other six files via `/project-documentation feature pos-cloud-single-till-sqlite`.
- **Deploy order:** POS release only. Existing tills are unaffected because BR-8 forbids switching an installed till.

## 11. Dependencies, known gaps, risks

- **Two datastores for good.** This is the largest cost. Every change to a cloud-till table or repository is written and tested twice, and the two can drift. Suggestion for the plan: a shared SQL dialect or query layer, decided before the first repository is ported.
- **Security model weakens without a decision.** ADR-006b relies on database roles and `SECURITY DEFINER` functions. SQLite gives the app the whole file (Q4).
- **The PostgreSQL suite is red at HEAD** (XORD-029). Parity tests need a green baseline first.
- **Concurrent POS work adds migrations,** for example XORD-036 (migration 63, uncommitted). Each new migration on a cloud-till table lands in both lists.
- **The cloud back office is not settled.** Most `CB-xx` items in `apps/xorder-pos/docs/coordination/BACKOFFICE_TO_CLOUD.md` are `PROPOSED`. Which local admin a cloud till keeps decides the repository list (Q2).
- **The Windows motive is weaker than assumed.** PostgreSQL is already bundled and silent there (Q1, Q7).
- **Domain gaps:** none of tips, aggregators, KDS, recipes, loyalty or multi-brand is involved. The food-truck location gap in `docs/domain/FOOD_SERVICE_DOMAIN.md` §3 is unaffected.
- **Reverses part of an owner decision.** `docs/pos/08-postgres-lan.md` (lines 10-14) states PostgreSQL in every mode. This feature changes that for one case and needs a recorded decision.

## 12. How it will be tested

| AC | Test |
|---|---|
| AC-1 | Integration test: setup with a one-terminal cloud licence and no `POS_PG_HOST`, then a sale through the UI |
| AC-2 | Existing setup and provider tests stay green, plus a provider test per mode, role and terminal count |
| AC-3 | Parity suite: the same fixtures and baskets run against both repository implementations, results compared field by field |
| AC-4 | Data test that kills the process or closes the file mid-sequence and reopens it; plus a person pulling power on a real laptop once |
| AC-5 | Existing outbox drain tests run against the SQLite queue, including replay and `IDEMPOTENCY_PAYLOAD_MISMATCH` |
| AC-6 | Seeder test with a forced failure inside the transaction |
| AC-7 | Shift close parity test against the existing `postgres_shift_test.dart` scenarios |
| AC-8 | Backup and restore data test, including a truncated file |
| AC-9 | Test for the Q3 path once decided |
| AC-10 | Needs a person to check the chosen protection |
| AC-11 | Data test with Arabic and mixed Latin names through insert, search and receipt rendering |

## 13. Decisions and open questions

**Decided:**
- 2026-11-03, owner, in chat: describe "single-till cloud on SQLite", kept beside PostgreSQL. Bundling PostgreSQL silently was offered as the alternative and not chosen.
- 2026-11-03, assumption, not yet confirmed: offline mode and multi-terminal cloud stay on PostgreSQL. This follows the recommendation the owner accepted.
- 2026-11-08, owner, in chat: **"Every cloud till on SQLite"** — the cloud app (`pos-split-apps` D10/D11) is to use SQLite on every till, not only one-terminal licences, and the offline app keeps PostgreSQL. This widens the scope of this feature and **contradicts the 2026-11-03 assumption above and BR-1**. Not yet reflected in sections 1-12. Before `/implement`, the owner must settle **Q8** below.

- **2026-11-08, owner, in chat (answers to Q8, Q4, Q6, Q1):**
  - **Q8 → "Each till alone, sync via cloud".** Every cloud till has its own SQLite file, including several tills in one venue. Tills do not see each other's open tables, parked checks or drawers; only finished orders, shifts, refunds and customers meet in the cloud. The setup and the floor must say so. Cloud children (tablets on the main device's PostgreSQL) no longer exist in the cloud app. This supersedes BR-1 and the 2026-11-03 assumption: the datastore follows the app, not the terminal count.
  - **Q4 → encrypt the file with SQLCipher**, key in the existing secret store (Windows DPAPI, macOS Keychain).
  - **Q6 → `sqlite3` (FFI) with the SQLCipher native library.** New dependency approved by the owner in this answer.
  - **Q1 → Windows and macOS together.** The Windows Cloud installer flavor drops the PostgreSQL component.
  - Q3 (licence growth) no longer arises: more terminals simply means more independent SQLite tills.
  - **Plan approved, encryption build `sqlite3mc`** (SQLite3MultipleCiphers in SQLCipher-compatible mode), owner, 2026-11-08: "Approve, use sqlite3mc".

**Q8 (added 2026-11-08, answered above). Multi-till cloud venues on SQLite:** with no shared PostgreSQL on the LAN, several cloud tills can coordinate only through the cloud API, which today has no endpoints for tables, parked checks, live floor state or cross-till X/Z (`BACKEND_TO_POS.md`: only orders, shifts, cash movements, refunds, customers, bootstrap, licence, terminals). Options: (a) the cloud app is single-till only until those contracts exist; (b) new `POS-BE-xxx` items for table and parked-check state via the cloud, with the till blind to other tills while offline; (c) keep the 2026-11-03 rule (multi-till cloud stays on LAN PostgreSQL). Recommended: (a) now, (b) as its own feature.

**Open** (each with the recommended answer first; ideas beyond the request are marked as suggestions):
- **Q1. Which platforms first?** Recommended: decide after counting real Windows failures of the bundled service. If there are few, start with macOS, where no installer exists. Alternative: Windows and macOS together.
- **Q2. Which repositories does a cloud till really need?** Recommended: confirm by tracing the cloud-till screens (selling, payment, refund, shift, cash, history, settings, print queue, parked tickets, outbox) and port only those. Stock, purchasing and reports stay offline-only unless a trace shows them in use.
- **Q3. What happens when a one-terminal licence grows?** Recommended: a one-way migration into a new PostgreSQL, allowed only when the outbox is empty and no shift is open. Alternative: refuse and require a fresh install, after the outbox drains.
- **Q4. How are staff secrets protected in the file?** Suggestion: encrypt the file with SQLCipher and keep the key in the existing DPAPI store (`lib/data/config/windows_dpapi_secret_store.dart`) or the macOS Keychain. Alternative: accept that the file is readable by the logged-in user and record the risk.
- **Q5. Does ETA e-invoicing run on a cloud till?** If yes, `eta_filer.dart` is in scope.
- **Q6. Which SQLite library?** Suggestion: compare plain FFI bindings with a typed layer such as drift during planning. Either needs approval as a new dependency.
- **Q7. What is the main motive?** Install friction, low-end hardware, or fewer moving parts. If it is only install friction, a macOS installer that bundles PostgreSQL as Windows does may be cheaper. Suggestion only.

Next: `/implement pos-cloud-single-till-sqlite`. That will need approval for: the new SQLite dependency, the new migration list, the installer change, the ADR that changes the PostgreSQL-in-every-mode decision, and the change to how order, payment and outbox repositories are bound, which is order and payment integrity work.
