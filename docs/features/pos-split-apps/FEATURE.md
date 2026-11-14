# Two POS apps, offline and cloud, on shared modules — pos-split-apps

Status: **approved; stages 0–3, 5, 6 built** (see TECHNICAL.md Progress) · 2026-11-08 · Verified against: xorder-pos `3052a53` (`development`), xorder-cloud `c2191fb` (`development`)

> Owner, 2026-11-08: "inside the xorder-pos is should have to apps one offline and one for cloud … I'm planning to make it sperated and have shared modules got it ?"

Paths are relative to `apps/xorder-pos/` unless they start with `apps/xorder-cloud/` or `docs/`.

## 1. Summary

The `xorder-pos` repository builds **two desktop apps** instead of one:
- **XOrder POS - Offline**: sales stay in the building, and the full back office is on the till.
- **XOrder POS - Cloud**: sales sync to xorder.io, and the dashboard is the back office.

Everything the two share lives once, in shared Dart packages in the same repository:
- the money and tax rules (`TicketEngine`);
- the selling screens;
- the branch database.

Each app contains only the parts of its own mode. A licence covers one mode, and each app accepts only its own.

## 2. Why

- **Today one app is both products.** It decides the mode at run time (`lib/core/config/deployment.dart:12-29`). Offline and cloud behaviour sit side by side behind 75 run-time checks in 26 files (section 5). Each check is a place where one mode's rule can leak into the other. XORD-058 was one: a cloud till printed the offline till's local invoice number.
- **The owner sells them as two things.** A licence will be offline-only or cloud-only (decision D1). Shipping two installers with clear names matches what a business bought.
- **An earlier design chose the opposite.** `docs/pos/08-deployment-modes.md` §1 recommended "not as a separate product … a configuration choice, not a second codebase", and `deployment.dart:5` repeats it. That recommendation still holds against *two codebases*. This feature keeps **one codebase** and splits only the **apps**, so the reasoning in §3 of that doc (one schema, one contract, no fork) is preserved.
- **Venue models:** every model is served by one of the two apps, and nothing changes for any of them at the till (section 9).

## 3. Goal and success

- Two installers built from one repository, one per mode.
- Each app passes the tests of the behaviour it ships. Together they cover every test that passes on today's single app (`scripts/check.sh` 2026-11-08: unit 3544 passed, PostgreSQL 1247 passed).
- The money, receipt, history and sync rules exist in exactly one place. No file is copied between the apps.
- The cloud app contains no back-office code, and the offline app contains no cloud sync code. Both are checked by the package dependency graph, not by reading code.
- The POS ↔ cloud contract is unchanged.

## 4. Users, roles and permissions

- **Installer or technician:** installs the app that matches the business's licence. No new permission.
- **Staff at the till:** unchanged. Same sign-in, same PIN, same capabilities (`lib/domain/services/authorization.dart`).
- **Super Admin:** issues a licence for one mode only (D1). That is a cloud change (section 10).
- **No permission identifier is added, removed or narrowed.**

## 5. Today

| What | Where | State |
|---|---|---|
| One app, one package `xorder_pos` | `pubspec.yaml:1`; `lib/main.dart` | exists |
| Mode chosen at run time: `cloud` / `offline` | `lib/core/config/deployment.dart:12-29`; `syncsSalesToPlatform` `:69` | exists |
| Licence carries `modes[]` and may cover both; with both, the wizard asks the operator | `lib/features/licensing/domain/license.dart:59`; `test/features/licence_decides_mode_test.dart` ("a licence covering both leaves the choice with the operator") | exists; **D1 removes "both"** |
| Cloud issues `modes` as an array, `min:1`, either or both values | `apps/xorder-cloud/apps/api/app/Http/Requests/Admin/StoreLicenceRequest.php:60-61`, `RenewLicenceRequest.php:109-110`, `RestaurantProvisioningService.php:215`; Super Admin form `apps/xorder-cloud/apps/web/src/pages/admin/RestaurantForm.vue:486` | exists |
| A cloud till has no back office, only a signpost to the dashboard (CB-07, owner 2026-09-27) | `lib/features/admin/presentation/cloud_back_office_screen.dart:12-26`; chosen at `lib/app/router.dart:291` | exists; **D2 keeps it** |
| Layers `core → domain → data → features`, wiring in `app/` | `lib/` | exists, with crossings below |
| One Windows installer, "XOrder POS", one `AppId` | `installer/xorder-pos.iss:40-55`; `.github/workflows/windows-installer.yml:76` | exists; **D4 renames** |
| Command-line tools | `bin/pos_migrate.dart`, `bin/pos_licence.dart` | exist |
| Tests import `package:xorder_pos/...` | 346 of 351 test files | exists |

**Mode checks by file** (`grep` for `DeploymentMode.cloud|offline`, `syncsSalesToPlatform`, `.mode.*` on `3052a53`; 75 lines, of which 10 are the definitions):

| File | Lines | What they decide (summary) |
|---|---|---|
| `core/config/deployment.dart` | 10 | the definitions |
| `features/setup/presentation/setup_panes.dart` | 9 | the wizard's mode step and cloud/offline panes |
| `app/providers.dart` | 9 | which repositories, sync and licence services are wired |
| `features/setup/application/setup_controller.dart` | 8 | setup flow per mode |
| `app/labels.dart` | 6 | mode names on screen |
| `features/setup/domain/setup_state.dart` | 4 | setup state per mode |
| `data/postgres/postgres_orders_repository.dart` | 4 | invoice number printed, pending count (XORD-058) |
| `features/payment/payment_screen.dart`, `features/admin/presentation/management_staff_pane.dart`, `data/postgres/postgres_sync_queue_repository.dart`, `…/postgres_supplier_invoices_repository.dart`, `…/postgres_shift_repository.dart`, `app/branch_sales_providers.dart` | 2 each | per-mode rules inside shared code |
| `features/{settings/about_dialog, receipt/receipt_dialog, history/order_history_screen, history/order_detail_pane, licensing/domain/license}.dart`, `data/postgres/{refunds, catalog_admin, cash_movements}_repository`, `data/postgres/local_bootstrap.dart`, `data/cloud/{outbox_drain, cloud_sync}.dart`, `data/backup/backup_service.dart`, `app/router.dart` | 1 each | same |

What each line decides, one by one, is **UNVERIFIED**; the summaries come from the file names and the lines already read in this session. The full per-line table belongs in `/implement plan`.

**Imports that block a package split today** (counted on `3052a53`):

| Crossing | Files | Why it blocks |
|---|---|---|
| `features → app` (mostly `app/providers.dart`, 66; `app/labels.dart`, 18) | 75 | shared screens reach into the one app's wiring; the provider declarations must move into a shared package and each app supply its implementations |
| `features → data` | 13 | screens import concrete classes: `setup_controller.dart` (PostgreSQL bootstrap, cloud seeder), `admin_session.dart`, `management_sync_pane.dart` (`CloudSync`), `licence_check_gate.dart` and `online_licence_service.dart` (`CloudApi`), `receipt_printing.dart` (printer ports), others |
| `core → domain` | 3 | `core/ui/widgets/{permission_gate, reason_picker, destructive_confirm_dialog}.dart`; a cycle with `domain → core` (37 files) |
| `domain` uses Flutter | 0 | good: `domain` is already pure Dart |

## 6. Scope

**In:**
- A Dart workspace in `xorder-pos`, with shared packages and two app packages.
- Each of the 75 mode checks either becomes a choice made once by the app or is removed.
- Two entry points and two router and provider wirings.
- Two installers named per D4, and CI that builds both.
- `check.sh` running every package's tests.
- `bin/` tools kept working.
- Docs: repo map and `CLAUDE.md`.
- The cloud change for D1: a licence covers exactly one mode.

**Out:**
- Two repositories, or copying code between the apps.
- Any change to the database schema or migrations. Both apps run the same migrations (BR-3).
- Any change to the POS ↔ cloud API contract.
- New features in either app.
- SQLite for single-till cloud venues. That is `docs/features/pos-cloud-single-till-sqlite`; this split makes it easier later (section 11), but it is not part of this feature.
- macOS installers beyond what exists today: there is no macOS installer workflow (`.github/workflows/` has only `windows-installer.yml`).

## 7. Behavior and business rules

- **BR-1, one mode per app.** The offline app only ever runs offline, and the cloud app only ever runs cloud. Neither has a mode step in setup or a mode switch anywhere.
- **BR-2, one mode per licence (D1).**
  - The Super Admin issues a licence for cloud or for offline, never both.
  - Each app accepts a licence only if it covers that app's mode, and refuses any other with a message naming the right app.
  - Both apps refuse a licence signed for both modes, with a message that the Super Admin must reissue it for one mode (D9).
- **BR-3, one schema.** Both apps run the same migrations (`data/postgres/migrations.dart`), and `pos_migrate` behaves as today. Migrations stay numbered and additive (POS first version, 2026-11-07).
- **BR-4, one rulebook.** These live once, in shared packages, and both apps use them unchanged:
  - `TicketEngine`, refunds, tax and service charges;
  - receipt layout, history, shifts, the business day, floor and parked checks, authorization.
- **BR-5, back office (D2).**
  - The offline app has today's full back office.
  - The cloud app keeps today's signpost to the dashboard (`cloud_back_office_screen.dart`, CB-07) and contains no back-office panes.
- **BR-6, cloud-only code stays in the cloud app.** The outbox drain, cloud sync, bootstrap seeding, device token and cloud invoice numbering (XORD-058) are not compiled into the offline app.
- **BR-7, offline-only code stays in the offline app.** The local back office, local invoice numbering and LAN multi-till setup are not compiled into the cloud app. Offline licence renewal still reaches the platform (`deployment.dart:18-24`).
- **BR-8, one app per machine (D3).**
  - Installing one app where the other is installed is refused, with a message to uninstall the other app first (D5). The other app and its data are never removed by the installer.
  - A branch database is set up by one app's mode and is not opened by the other.
- **BR-9, names (D4).**
  - The apps are named **XOrder POS - Cloud** and **XOrder POS - Offline**: installer, window title, Start menu and About box. The names are English only, in the Arabic interface too (D8); the Arabic strings already write "XOrder POS" in Latin (`lib/core/l10n/app_strings.dart:9963`).
  - Each has a new installer id; neither reuses today's "XOrder POS" id (D6). A machine with today's app uninstalls it by hand first.
- **BR-10, behaviour preserved.** Apart from BR-1, BR-2 and BR-8 (the mode choice and the "both" licence go away), every screen, total, receipt, outbox payload and refusal is what today's app does in the same mode.

## 8. Acceptance criteria

- **AC-1:** *Given* the repository, *when* `scripts/check.sh` runs, *then* it analyses and tests every shared package and both apps, and passes.
- **AC-2:** *Given* each app's dependency graph, *when* it is listed (`dart pub deps`, or an import-lint test), *then*:
  - the offline app has no path to the cloud-sync package;
  - the cloud app has no path to the back-office panes;
  - no shared package depends on either app.
- **AC-3:** *Given* the same basket on each app, *when* it is paid, *then* the totals, VAT, service and receipt lines equal today's app in that mode. Proven by the existing `TicketEngine`, receipt and payment tests running against the shared packages, and by a parity test per app.
- **AC-4:** *Given* the cloud app, *when* a sale is paid, *then* the outbox payload is byte-for-byte what today's cloud mode sends, including `customer_id` (G2) and the provisional invoice (XORD-058). Proven by `outbox_drain_test` and `provisional_invoice_test`, run in the cloud app's package.
- **AC-5:** *Given* the offline app, *when* it is set up and sells, *then* it numbers its own invoices, shows the full back office and never calls a sales endpoint. Proven by an offline flow test with a cloud API fake that fails on any `pos/orders` call.
- **AC-6:** *Given* setup in either app, *then* there is no mode step. *Given* a licence for the other mode, *then* setup refuses it and names the right app. *Given* a licence signed for both modes, *then* each app refuses it and asks for it to be reissued for one mode (D9). Proven by `licence_decides_mode_test`, rewritten per app.
- **AC-7:** *Given* the Super Admin issuing or renewing a licence, *when* both modes are submitted, *then* the cloud refuses with a validation error. Proven by cloud PHPUnit on `StoreLicenceRequest` and `RenewLicenceRequest`, and a Super Admin form check by a person.
- **AC-8:** *Given* CI, *when* the installer workflow runs, *then* it produces two Windows installers named per BR-9, each with its own id. A person installs each on a clean Windows machine.
- **AC-9:** *Given* an existing branch database set up by today's app, *when* the matching new app starts after `pos_migrate`, *then* it opens it with no data change. Proven by a PostgreSQL test that migrates a database written by `3052a53` and reads it with each app's repositories.
- **AC-10:** *Given* the matching app installed where the other one is, *then* the installer refuses, names the installed app and asks for it to be uninstalled first, and changes nothing on the machine (D5). A person checks this on Windows.

## 9. Edge cases and failure modes

- **Venue models.** None changes behaviour at the till; each simply installs one app:

  | Venue | App |
  |---|---|
  | Café, one counter till | Cloud, or Offline with poor signal |
  | Restaurant with several tills | Offline over a LAN database, or Cloud |
  | Food truck, unreliable power and signal | Offline is likely; Cloud absorbs outages through the outbox as today |
  | Cloud kitchen | Cloud, with the dashboard as back office |

  Does a venue that changes its mind (offline → cloud) need a data move? Today the mode is fixed at setup too, so this is not new. Out of scope (D7): a separate feature if it is ever wanted.
- **Existing "both" licences.** Licences are signed and cannot be re-signed (`deployment.dart:42-45`). Any that exist are refused by both apps and must be reissued for one mode (D9). How many exist is UNVERIFIED (production not read).
- **Legacy mode values.** `branch_server` and `standalone` still parse as offline (`deployment.dart:46-49`); the offline app keeps that.
- **Offline and retry, idempotency.** Unchanged: the outbox code moves package, it is not rewritten (AC-4).
- **Tenant boundary.** Unchanged: the cloud scopes by device token, and the till by `business_id`.
- **Arabic and RTL, digits.** `app_strings.dart` moves into a shared UI package. The app names are not translated (D8): Arabic screens show the English names.
- **Plan and licence limits.** `max_terminals` and `max_users` are unchanged, read the same way by both apps.
- **Very large change.** The work moves most of the code (≈142,000 lines in `lib`, 351 test files), so it must land in stages that each pass `check.sh` (section 12). A half-moved tree must never reach `development`.
- **Other sessions' work.** Branches open against today's layout (for example `fix/dropdown-consistency`) will conflict with the moves. They should be merged before stage 1, or rebased after it (section 11).

## 10. Impact

| Area | Change |
|---|---|
| xorder-pos | Workspace `pubspec.yaml`, new `packages/*` and `apps/*`; every file moves; imports rewritten; `providers.dart` split into shared declarations plus per-app wiring; `router.dart` per app; `check.sh`, installer script and CI workflow per app; `bin/` tools in a package |
| xorder-cloud | **D1 only:** `modes` limited to one value in `StoreLicenceRequest`, `RenewLicenceRequest`, `RestaurantProvisioningService`; the Super Admin forms (`RestaurantForm.vue`, `pos/LicenceForm.vue`, `pos/LicenceDetails.vue`) offer one choice; PHPUnit tests. No route or response shape changes |
| API and contract | none. `modes` stays an array, now always of one value |
| Data and migrations | none in either repo |
| Permissions | none |
| Localization | app names in English only, not translated (D8) |
| Documentation | `docs/architecture/repo-map.md`, `apps/xorder-pos/CLAUDE.md`, `docs/pos/08-deployment-modes.md` (the decision changes from "one app" to "one codebase, two apps"), `.claude/rules/pos-flutter.md` paths, the feature inventory's POS paths |
| Deploy order | the cloud D1 change can ship any time (it only narrows what the Super Admin may issue); the POS apps replace today's single installer at the next POS release |

## 11. Dependencies, known gaps, risks

- **Depends on:** other sessions' open POS work being merged first, or planned around:
  - `fix/dropdown-consistency`;
  - whatever is uncommitted in the main checkout: `installer/xorder-pos.iss` and several admin panes are modified there today.
- **Helps later:** `pos-cloud-single-till-sqlite` becomes a separate storage package used only by the cloud app.
- **Risk, high: a long-running move.** A refactor that touches every file conflicts with all parallel work. Mitigation: stages small enough to merge within a day, and parallel POS work frozen during stages 1 and 2.
- **Risk, medium: hidden coupling.** 75 files import the app's wiring. Turning `providers.dart` (3957 lines, 177 providers) into shared declarations plus per-app overrides is the hardest step.
- **Risk, medium: lost tests.** A test left in the wrong package stops running without anyone noticing. Mitigation: AC-1 counts tests per package and compares the total with today's 3544 + 1247.
- **Risk, low: the Windows installer id.** Both apps get new ids (D6), so a machine with today's "XOrder POS" would end up with two entries unless it is uninstalled first. Only test machines have it (no restaurant runs today's POS, 2026-11-06); the release notes say to uninstall it.
- **Known gap:** there is no macOS installer for either app.

## 12. How it will be tested

| AC | Test | Kind |
|---|---|---|
| AC-1 | `scripts/check.sh` over the workspace; test counts per package vs 3544 / 1247 | automated |
| AC-2 | import-boundary test (dependency graph) | automated, new |
| AC-3 | existing engine, receipt and payment suites in the shared packages; one parity test per app | automated |
| AC-4 | `outbox_drain_test`, `provisional_invoice_test` (PostgreSQL) in the cloud app | automated |
| AC-5 | offline flow test with a failing cloud fake | automated, new |
| AC-6 | `licence_decides_mode_test`, rewritten per app | automated |
| AC-7 | cloud PHPUnit for both requests; Super Admin form | automated + person |
| AC-8 | CI artifacts; install on clean Windows | person |
| AC-9 | PostgreSQL migration test from a `3052a53` database | automated, new |
| AC-10 | install over the other app on Windows | person |

**Suggested stages for `/implement plan`** (each passes `check.sh` and is merged before the next):
1. **Workspace and core.** Move `domain` and `core` into shared packages and break the 3-file `core → domain` cycle. Imports only.
2. **Data.** Move `data/postgres` into a shared package, and the cloud and offline pieces into their own.
3. **Wiring.** Move the provider declarations into a shared package so that screens no longer import `app/`. Replace the 13 `features → data` imports with interfaces.
4. **Mode checks.** Make each of the 75 a choice of the app, or remove it.
5. **Two apps.** Two `main.dart` files, routers and wirings; setup without a mode step; two installers and CI.
6. **Cloud D1.** One mode per licence.

## 13. Decisions and open questions

**Decided (owner, 2026-11-08):**
- **D0:** two apps in the one `xorder-pos` repository, sharing modules ("make it sperated and have shared modules").
- **D1:** a licence is offline only or cloud only ("No it can be offline only or cloud only").
- **D2:** the back office is offline only; for cloud it is the dashboard ("back office should be for offline only , and clould it will be dashboard"). This matches today's CB-07.
- **D3:** one app per machine.
- **D4:** names "XOrder POS - Cloud" and "XOrder POS - Offline", with a spaced hyphen (owner, 2026-11-08, refined the same day).
- **D5 (Q2):** an installer refuses when the other app is installed and asks for it to be uninstalled first ("Refuse, explain").
- **D6 (Q3):** both apps get new installer ids ("Both get new ids").
- **D7 (Q4):** moving a business between offline and cloud is out of scope.
- **D8 (Q5):** no Arabic names; the apps are named in English only ("no need for arabic names for the app make it english only"). This replaces an earlier answer the same day ("سحابي / اوف لاين").
- **D9 (Q1):** an app refuses a licence that was signed for both modes; the Super Admin reissues it for one mode ("Refuse it"). Reason agreed the same day: no licence needs both, because a cloud till already keeps selling on its branch database when the internet drops.
- **D10 (later the same day):** three packages, not five. The shared library `xorder_pos` plus two app packages, `xorder_pos_cloud` (sync code inside it; the back office is the dashboard) and `xorder_pos_offline` (the back office inside it). No separate `xorder_pos_back_office` or cloud-sync library ("xorder_pos_cloud -> back office will be on cloud; xorder_pos_offline -> this will contain back office"). TECHNICAL.md section 2 is amended.
- **D11 (stated, not yet planned):** the cloud app is to run every till on SQLite and the offline app keeps PostgreSQL ("Every cloud till on SQLite"). Out of scope here (section 6 stands); it widens `pos-cloud-single-till-sqlite` from one-terminal licences to every cloud till, which is recorded there as an open point because multi-till cloud venues would then coordinate only through the cloud API.

**Open:**
- **Q6, suggestion (not asked for):** split the repository's tests the same way, so a cloud-only change runs only the shared and cloud suites. That would be faster CI, but it is not required.
