# Two POS apps on shared modules — technical plan

Status: **approved 2026-11-08** (owner: "Approve as suggested"; O1 no, O2 yes, O3 yes) · 2026-11-08 · Specification: [FEATURE.md](FEATURE.md) (decisions D0–D9) · Verified against: xorder-pos `3052a53` (`development`), xorder-cloud `c2191fb` (`development`)

Paths are relative to `apps/xorder-pos/` unless they start with `apps/xorder-cloud/`.

**Progress (2026-11-08):**
- **Stage 6:** done, on xorder-cloud `feat/licence-one-mode` `30b1529`. Not merged, not pushed.
- **Stage 0:** done 2026-11-08 (owner: "make all changes directly on development branch, merge everything first"). The dropdown work was committed on `fix/xord-044-046-parked-check-versions` (`96e49dd`) and merged (`fb02cf1`); `fix/installer-iss-section-tag` merged (`d54d5de`). **From here the stages land on `development` directly**, not on `feat/pos-split-apps`.
- **Stage 1:** done, `feat/pos-split-apps` `36a78f3`; merged into `development` at `0f3ea08` (one conflict: the new `pos_dropdown_field_test.dart` followed its directory into `packages/xorder_pos/test/core/`).
- **Stage 2:** done, commit `789db8c` on `feat/pos-split-apps-stage2`, merged into `development` at `d36611c`. As built, with the D10 layout:
  - `packages/xorder_pos/lib/pos_main.dart`: `runPos({required DeploymentMode mode})` holds the old `main()` body; `lib/main.dart` is gone. `bootFor(...)` is the pure BR-8 rule: a saved `config.json` in the other mode yields `TerminalBoot(otherAppMode: …)` with no config.
  - `apps/xorder_pos_offline/` and `apps/xorder_pos_cloud/`: `pubspec.yaml` (`resolution: workspace`, depends on `xorder_pos`), `lib/main.dart` (one line each), `windows/` and `macos/` moved from the package (offline) and copied (cloud), renamed: `BINARY_NAME` `xorder_pos_offline` / `xorder_pos_cloud`, `ProductName`/`FileDescription`/window title "XOrder POS - Offline" / "- Cloud", bundle ids `io.xorder.pos.offline` / `io.xorder.pos.cloud`. The mark is copied into each app's `assets/icons/` because Flutter keys a `../` asset by that path, not the bare one the shared code asks for; the fonts are declared with `../../packages/xorder_pos/assets/fonts/` paths, which works because code asks by family name. `android/ ios/ linux/ web/` removed from the package (O3). `flutter_launcher_icons.yaml` moved into each app.
  - `appModeProvider` (`Provider<DeploymentMode?>`, null in the shared package) and `appTitleProvider` in `providers.dart`; `DeploymentController` starts an unconfigured till in the app's mode; `licenceServiceProvider` builds the verifier with `singleModeOnly`.
  - Licence rules: `LicenseVerifier.singleModeOnly` / `evaluateClaims(singleModeOnly:)`; new `LicenseState.modeAmbiguous` + `LicenceCoversBothModes` (D9, judged before coverage); `LicenceModeNotCovered(fixedApp: true)` names the other app (BR-2). Strings `licenceForOtherApp`, `licenceCoversBothModes`, `wrongAppTitle`, `wrongAppBody`, `databaseSetUpByOtherApp` in en and ar. `DeploymentMode.productName` / `.other` on the enum (D8: English only).
  - Wizard: `SetupDraft.appMode`; `asksSetupType` is false with it; `setMode` refuses the other mode; `_coveredMode` never moves off the app's mode; a child joining a main device whose site licence names the other mode is refused (`databaseSetUpByOtherApp`).
  - Router: `PosRoutes.wrongApp` + `WrongAppScreen`; the redirect sends everything there while `otherAppMode` is set, the wizard included.
  - Scripts and CI: `scripts/check.sh` analyses both apps after the shared suites; `scripts/package_macos.sh [offline|cloud]`; the Windows workflow and `installer/xorder-pos.iss` build the **offline** app until stage 5 adds the matrix.
  - Tests: `test/features/fixed_app_mode_test.dart` (per app: no mode step, other mode refused and named, both-modes refused, empty claim accepted; verifier on its own), `test/features/wrong_app_boot_test.dart` (`bootFor` and the router), `licence_decides_mode_test.dart` "covering both" cases rewritten as refusals per app. `test/support/fakes.dart` takes `appMode:`; `FakeLicenceService(singleModeOnly:)`.
  - **Not done / not verified:** `integration_test/` boots as the cloud app (`runPos(mode: cloud)`) but its wizard walk still expects a setup-type step (`sale_to_settle_test.dart:505`) — needs a real platform and database, not run. The PostgreSQL test for a database set up by the other app (plan: "a PostgreSQL test where a database whose site licence says `cloud` is refused by the offline wiring") is covered only at the controller level through the child path, not as a `integration`-tagged suite. Windows build not run (CI only).
- **Stage 3:** done 2026-11-08 on `development` (the owner asked for stages to land there directly). One commit, `0d97785`. (While the work was in progress an outside commit, `d974e75`, captured most of the tree under a recycled message plus stray font copies under `apps/*/packages/`; on the owner's "Fold it" it was soft-reset and folded into `0d97785`, which carries no font copies. `/apps/*/packages/` is git-ignored; what wrote them there is UNVERIFIED.) Verified: analyse clean in all four members; unit shared 2590 (2 skipped), offline 855, cloud 117 (1 skipped); PostgreSQL shared 1136, offline 6, cloud 107; both apps build on macOS. As built:
  - **Seams in the shared package.** `lib/app/sales_sync.dart` (`SalesSync`; `cloudSyncProvider` is now `Provider<SalesSync?>`, null by default); `lib/domain/models/sync_outcome.dart` (`SyncOutcome`, `DrainReport` lifted out of the cloud code); `lib/domain/services/syncing_orders_repository.dart` (the decorator the orders binding wraps, lifted out of the drain); `lib/app/bootstrap_seeding.dart` (`BootstrapSeeding`, `bootstrapSeedingProvider`, used by the wizard's menu download); `platformBranchSalesProvider` in `branch_sales_providers.dart` (`BranchSalesSource?`, null by default; `branchSalesSourceProvider` falls through to it for a per-till cloud terminal); `provisioningRepositoryProvider` keeps the branch-PostgreSQL path (`branchProvisioningRepository(ref, config)`, public so the cloud override can fall through for a child); `lib/features/admin_mode/back_office_contract.dart` (`BackOffice`, `NoBackOffice`, and the enums lifted from `management_screen.dart`: `ManagementPane`, `BackOfficeTab`, `ManagementDestination`, `ManagementBarEntry/Menu`, `PurchasingTab`), bound by `backOfficeProvider`; `lib/core/config/app_version.dart` (`posAppVersion`); `etaProblemText` moved to `app/labels.dart`.
  - **Shared Admin Mode** (`lib/features/admin_mode/`): `admin_session`, `admin_shortcut`, `supervisor_override`, `admin_messages`, `users_overview` — used by the till's own screens (payment, refund, cash, shift, history), so not back office.
  - **Moved to `apps/xorder_pos_cloud/`:** `lib/data/cloud/{outbox_drain, cloud_sync, bootstrap_seeder, bootstrap_bundle, cloud_provisioning_repository, branch_sales_api, logo_sync}.dart`, `lib/features/cloud_back_office_screen.dart`, `tool/parse_real_bootstrap.dart`, `integration_test/` (it walks a cloud install; boots with `cloudOverrides()`), 17 test files. `lib/wiring.dart`: `cloudOverrides()` binds the sync loop (the old provider body, verbatim), cloud provisioning, the platform branch-sales source, bootstrap seeding and `CloudBackOffice` (the signpost, no bar menus). Shared keeps `cloud_api.dart` (licence renewal in both apps) and `device_token_vault.dart` (restored before the first frame by `runPos`).
  - **Moved to `apps/xorder_pos_offline/`:** `lib/features/admin/` (application + presentation; 59 files, 30 of them `*_pane.dart`), 63 test files, `test/support/back_office.dart`. `lib/wiring.dart`: `offlineOverrides()` binds `OfflineBackOffice` (the management screen + `managementBarFor`). `test/support/offline_harness.dart` (`offlineTestOverrides` = fakes + offline bindings) for the two suites that pump the whole app (`settings_bar_test`, `admin_entry_test`). `capability_labels_test` reads `admin_repositories.dart` through `../../packages/xorder_pos/`.
  - **`packages/xorder_pos_test_support/`** (new member, dev dependency of all three): `fakes`, `fonts` (with a `packages/xorder_pos/` fallback for app-run tests), `pg_fixture` (tag now hashed from the **workspace root**, so every member shares one test database per checkout; `tool/drop_test_databases.dart` matches), `staff`, `lan_tls_fixtures`, `secret_store_contract`, `fake_business_days`, `in_memory_customers`.
  - **`runPos(mode:, overrides:)`**; each `main.dart` passes its app's overrides.
  - **Deleted or trimmed:** `management_sync_pane.dart` lost its cloud branch (`_syncNow`, `_cloud`, `_HeldSyncItems`, `_HeldRow`; the offline app only ever shows `_OfflineTill`; `SyncProblem`/`syncProblemOf`/`syncProblemLabel` stay for the home pane). Its test lost 11 cases: "a cloud till" (4), "held sync items (D1/D2/D13)" (6) and "cloud: Arabic words, the count left to right, nothing overflows" (1). Declared tests: 4676 before → 4668 after = 4676 − 11 + 3 (`package_boundaries_test`).
  - **`test/package_boundaries_test.dart`** (AC-2): shared `lib/` imports neither app; neither app's pubspec names the other; `lib/data/cloud` holds only `cloud_api` and `device_token_vault`; no `lib/features/admin`. Mutation-checked: a probe import of `xorder_pos_cloud` in shared `lib/` fails it.
  - **`scripts/check.sh`** runs analyse + unit + PostgreSQL suites for every member (`check_member`), then drops the one shared test database. CI/installer unchanged from stage 2 (offline app).
  - **Verified:** `flutter analyze` clean in all four members. Unit/widget: shared 2590 passed + 2 skipped; offline 855; cloud 117 + 1 skipped. PostgreSQL suites and `flutter build macos --debug` of both apps: results in the stage-3 commit message.
  - **UNVERIFIED / left for stage 4:** Windows build (CI only). `integration_test` not run (needs a platform). The home pane (`back_office_home.dart`) still reads `cloudSyncProvider` (always null offline) and `syncProblemOf`; the remaining per-mode checks are stage 4's table. `CloudBackOffice` ignores `destination` and `onReconfigure` (the cloud app has no Terminal pane; reconfiguration is the wizard, as before for a claimed tenant).
- **Rename and font clean-up (owner, 2026-11-08: "change this xorder_pos to shared_moduel"; "you duplicate for fonts"):** supersedes O2. `packages/xorder_pos` is `packages/shared_module`, package `shared_module`; 426 Dart files import `package:shared_module/`. The branch database is still named `xorder_pos` (not a package name; unchanged). Fonts and the mark are declared **once**, in `packages/shared_module/pubspec.yaml`; the apps declare none. `PosFonts.ui`/`.mono` are `packages/shared_module/IBM Plex …` (how Flutter names a dependency's fonts) and the four `Image.asset` logo calls pass `package: 'shared_module'`; the logo copies in `apps/*/assets/` are deleted. With no `../` asset paths left, `flutter test` has nothing to mirror into `apps/*/packages/` — the likely source of the stray font copies (inferred, not proved). Also: the Windows workflow's install smoke test looked for `xorder_pos.exe`, renamed in stage 2 to `xorder_pos_offline.exe`; fixed.
- **Stage 4:** done, `a30cfae` (branched from `7fa0d06`), merged into `development` at `c9c54ab`. The wizard's mode step is gone entirely (`SetupStep.setupType`, `_SetupTypePane`, `setMode`, `asksSetupType`, `licensedModes`, `_coveredMode`, `_judgeOnCoveredMode`, `_modeChangedNotice`) along with 11 strings only it used; a licence is judged against the app's mode and never moves the draft. The three back-office repositories gated on `mode != offline` moved into the offline app's wiring; the staff pane's cloud checks and the dead cloud-sync bits of the home and sync panes are removed; the cloud wiring's own mode checks are removed. Kept as per-mode rules in shared code: the PostgreSQL repositories' outbox/invoice rules, the payment/receipt/history labels, the setup steps per path, `posCloudApiProvider`. `cloud_sync`/`outbox_drain` keep a cheap offline guard. §4's line numbers predate this and are not rewritten; the commit message has the as-built table. **AC-5** added: `apps/xorder_pos_offline/test/features/offline_never_sends_money_test.dart` (3 tests; a tripwire `PosCloudApi` fails on any sales/shift/cash/refund/customer/heartbeat/bootstrap call through setup, a paid sale and 31 minutes of clock; checked to fail when a `SalesSync` is bound; uses the fake orders repository, so the PostgreSQL write path is not covered). 13 tests deleted (mode-step tests and the offline sync pane's `syncProblemOf` group), listed in the commit.
- **Stage 5:** done, `18a9f9d`, merged into `development` (fast-forward). `installer/xorder-pos.iss` takes `/DFlavor=Offline|Cloud`; new AppIds Offline `{541470B8-9655-4C8B-B613-BDE215C517D6}`, Cloud `{CFE3951B-E0DC-4C64-908C-5BCAB02681F5}`; the old `{6B0C8F3E-…}` is only detected. `InitializeSetup` refuses (en + ar) when the other app's or the old app's uninstall key is present, in HKLM/HKCU and both registry views, and installs nothing. The workflow is a matrix over both apps with a new "refuses beside the other app" step and a `release` job publishing both. Also fixed a stage-2 bug: `/DAppDir` pointed at a folder no build writes to. **UNVERIFIED by execution:** no `iscc`/`wine` here; the first manual workflow run is the first compile. Windows checks a person must run: clean install of each; each over the other (refused, nothing changed); each over the old "XOrder POS" (refused); uninstall old, install Offline, existing database reused (risk: a service left by a failed old uninstall); same app over itself (allowed).
- **Stage 7:** done (workspace docs, no commit): `docs/architecture/repo-map.md`, `.claude/rules/pos-flutter.md`, this folder's API/DATABASE/TEST_PLAN/TEST_REPORT/CHANGELOG, the inventory row. In the POS repo: a superseded note at the top of `docs/pos/08-deployment-modes.md`, the `DeploymentMode` doc comment, and `CLAUDE.md`'s mode line.
- **Not done:** `apps/xorder_pos_cloud/integration_test/` walks a wizard from 2026-08 (setup type → language → connection with platform and database fields), not today's cloud path (licence → pairing code → connecting → hardware → summary). It was stale long before this feature and has not run; rewriting it needs a live platform to check against. `scripts/harness/verify.sh` still recommends the pre-workspace `flutter test` command.

## 1. Re-verified facts the plan rests on

| Claim | Evidence (on `3052a53`) | Consequence for the plan |
|---|---|---|
| One package, `xorder_pos`; 346 of 351 test files import `package:xorder_pos/...` | `pubspec.yaml:1`; `test/` | Keep the shared package's **name** `xorder_pos`, so no import in `lib/` or `test/` changes when it moves |
| Size: core 19.9k lines, domain 18.5k, data 35.9k, app 6.6k, features 60.9k; tests 116.5k | `git ls-tree` line counts | A full split into many packages would touch most files; the plan moves code in large blocks instead |
| Back office is `lib/features/admin` (60 panes, 32k lines), used outside itself only by `app/app.dart`, `app/providers.dart`, `app/router.dart` | `git grep features/admin` | It moves to an offline-only package with three seams |
| Cloud-only code is in `lib/data/cloud/` (`outbox_drain`, `cloud_sync`, `bootstrap_seeder`, `bootstrap_bundle`, `cloud_provisioning_repository`, `device_token_vault`, `branch_sales_api`, `logo_sync`) | `lib/data/cloud/` | It moves to a cloud-only package. `cloud_api.dart` **stays shared**: the offline app renews its licence through it (`online_licence_service.dart`, `licence_check_gate.dart`) |
| `data/cloud` is imported from shared code by `providers.dart`, `branch_sales_providers.dart`, `till_status_bar.dart`, `setup_controller.dart`, `management_sync_pane.dart`, `about_dialog.dart`, `main.dart` | `git grep data/cloud` | These are the seams of stage 3 |
| 65 mode checks outside the definitions | `git grep` table in section 4 | Each one gets a disposition; most stay as they are |
| The branch database records the mode: the published site licence row carries `mode` | `providers.dart:2350-2361` | An app can see that a database was set up by the other app and refuse it (BR-8) |
| The Windows config folder follows `ProductName` (`getApplicationSupportDirectory`), which is "XOrder POS" today | `windows/runner/Runner.rc:92-98`; `data/config/terminal_config_store.dart:33` | A renamed app looks in a new folder, so it finds no `config.json` from today's app (O1) |
| The installer keeps the database in `%ProgramData%\XOrder POS\pgdata`, and uninstall removes only the service ("The database stays") | `installer/provision.ps1:45-49, 300-306`; `xorder-pos.iss:42, 133, 163-173` | Both apps keep this folder and service name, so uninstalling today's app and installing a new one keeps the data (AC-9) |
| Installer `AppId` `{6B0C8F3E-…}`, "Never change" | `installer/xorder-pos.iss:45-46` | D6 gives each app a new id; the old id is used only to detect today's app |
| CI builds one app on Windows, by hand | `.github/workflows/windows-installer.yml:70-200` | A matrix over the two apps |
| Android, iOS, Linux and web folders exist; Android is "designed for rather than shipped" | `docs/pos/08-postgres-lan.md:445`; last touched 2026-08/09 | O3 |
| The cloud accepts `modes` as an array with `min:1` | `StoreLicenceRequest.php:60-61`, `RenewLicenceRequest.php:109-110`, `RestaurantProvisioningService.php:215` | Stage 6 |

No discrepancy with FEATURE.md was found, with one refinement: FEATURE section 5 lists the `core → domain` cycle as a blocker. It blocks only a split of `core` and `domain` into separate packages, and this plan does not split them (section 2). It is left as it is.

## 2. Target layout

**Amended 2026-11-08 (owner, D10):** three packages, not five. The mode-only code lives *inside* each app package instead of in two separate libraries. The earlier layout (`xorder_pos_cloud` and `xorder_pos_back_office` as libraries beside two thin `apps/`) is superseded; the owner's words: "xorder_pos_cloud -> back office will be on cloud; xorder_pos_offline -> this will contain back office".

```
xorder-pos/
  pubspec.yaml                 workspace root only (Dart pub workspace; no code)
  packages/
    shared_module/             SHARED. Today's lib/ minus the two blocks below, with its test/.
                               Package `shared_module` (renamed from `xorder_pos` on the
                               owner's word, 2026-11-08, superseding O2). Declares the
                               fonts and the mark; the apps declare none.
    xorder_pos_test_support/   Fakes, fonts, the PostgreSQL fixture: a dev dependency of the
                               three members above and below (added in stage 3, because the
                               apps' tests need the same harness as the shared package's).
  apps/
    xorder_pos_cloud/          "XOrder POS - Cloud". main.dart, wiring, windows/, macos/,
                               plus lib/data/cloud/* (except cloud_api.dart) and their tests.
                               The back office is the xorder.io dashboard (CB-07); no admin panes.
                               depends on shared_module
    xorder_pos_offline/        "XOrder POS - Offline". main.dart, wiring, windows/, macos/,
                               plus lib/features/admin/* (the back office) and their tests.
                               depends on shared_module
  installer/ scripts/          stay at the root; bin/ and tool/ live in packages/shared_module
```

Why this shape and not one package per layer:
- **What has to differ** between the apps is the cloud sync code, the back office, the wiring and the name. Splitting `core`, `domain`, `data` and `features` into separate packages would rename the imports in 354 files that use `package:xorder_pos/` today, and change every relative import that crosses the new boundaries, without making the apps any more separate.
- **Keeping the name `xorder_pos`** means `git mv` alone moves the shared code and its tests, and history follows the files.
- **Why the mode-only code sits in the app and not in a library of its own (D10):** nothing else will ever depend on it (no third app, no tool), so a separate package adds a `pubspec` and a boundary with one consumer. Folding it into the app keeps the count at three packages and the rule simple: whatever is in `apps/xorder_pos_cloud/lib` is cloud-only, whatever is in `apps/xorder_pos_offline/lib` is offline-only.
- **The dependency rule** is enforced by `pubspec.yaml`: the shared package depends on neither app, and no app depends on the other (AC-2). Because the mode-only code is inside each app, "the offline app has no path to cloud sync" and "the cloud app has no path to the back office" follow from the graph alone.
- **Datastores (owner, 2026-11-08, stated in chat; planned in `pos-cloud-single-till-sqlite`, not here):** the cloud app is to use SQLite on every till and the offline app keeps PostgreSQL. This plan leaves `lib/data/postgres/` in the shared package and both apps on PostgreSQL (BR-3). When the SQLite work starts, `lib/data/postgres/` moves into `apps/xorder_pos_offline/` and the SQLite datastore is written inside `apps/xorder_pos_cloud/`, so the graph enforces the split the same way. Doing that move now would widen this refactor for no behaviour gain.

## 3. Stages

Each POS stage is one commit on `feat/pos-split-apps` (branched from `development`), and must pass `scripts/check.sh` (analyze, unit, PostgreSQL) before the next one starts. Rolling back a stage means reverting its commit.

### Stage 0: clear the way (no code)
- Merge the POS work in flight before stage 1. Moving every file conflicts with any open POS branch:
  - the uncommitted dropdown work in the main checkout (`fix/xord-044-046-parked-check-versions`: `installer/xorder-pos.iss`, five admin panes, `pos_widgets.dart`, `pos_dropdown_field_test.dart`);
  - `fix/installer-iss-section-tag`.
- No other POS branch is started until stage 3 is merged.
- Record a baseline `scripts/check.sh` on the starting commit: the test counts to compare against.

### Stage 1: workspace, one member, no behaviour change
- **Change:**
  - Root `pubspec.yaml` becomes the workspace root.
  - `git mv` `lib/`, `test/`, `integration_test/`, `assets/`, the platform folders and the package's `pubspec.yaml` into `packages/xorder_pos/`, which gets `resolution: workspace`.
  - Point `scripts/check.sh`, `tool/`, `bin/` (or move `bin/` into the package, whichever keeps `dart run bin/pos_migrate.dart` working), `.github/workflows/windows-installer.yml` and `installer/xorder-pos.iss` (`..\build`, `..\windows` paths) at the new folder.
- **Tests:** the same counts as the stage 0 baseline in `scripts/check.sh`. Building `pos_migrate.exe` and the installer is checked by the CI workflow, which the owner starts by hand (UNVERIFIED until it runs).
- **Risk:** path breakage only; no Dart code changes.

### Stage 2: two app shells with a fixed mode
- **Change:**
  - `packages/xorder_pos/lib/pos_main.dart` gets today's `main()` body as `runPos({required DeploymentMode mode, required String appTitle})`.
  - Each app's new `lib/main.dart` (under `apps/xorder_pos_offline/` and `apps/xorder_pos_cloud/`) calls it. Each app has its own `windows/` and `macos/` folders, copied from today's and renamed:
    - `BINARY_NAME` is `xorder_pos_offline` / `xorder_pos_cloud`;
    - `ProductName` and `FileDescription` are "XOrder POS - Offline" / "XOrder POS - Cloud";
    - the macOS bundle id and name change the same way.
  - The shared package loses its platform folders.
  - A new `appModeProvider` (overridden by each app's `main`) is the one place the mode comes from:
    - `deploymentProvider` takes its `mode` from it;
    - the setup wizard drops the mode step (`SetupStep` and its labels in `labels.dart:33-39`);
    - a saved `config.json`, or a branch database whose site licence names the other mode, is refused with a message naming the right app (BR-8).
  - **Licences (D9, BR-2):**
    - setup and renewal accept only a licence whose `modes` is exactly the app's mode;
    - a licence for the other mode names the other app;
    - a licence for both modes is refused with "ask for it to be reissued for one mode".
    - `licence_decides_mode_test.dart` is rewritten. Its "covering both" tests (lines 102, 173) become refusal tests, run once per mode.
- **Tests:**
  - **Licence rules:** licence-refusal unit tests per mode, covering own mode, other mode and both.
  - **Setup and database:** a setup widget test per mode showing no mode step; a PostgreSQL test where a database whose site licence says `cloud` is refused by the offline wiring, and the other way round.
  - **Regression:** everything else unchanged.
- **Risk:** medium. The wizard's step order changes (BR-1). `DeploymentConfig.unconfigured` defaults to cloud, which the router already works around (`router.dart:284-291`). That default now comes from the app's mode.

### Stage 3: seams, and the mode-only code moves into its app
- **Change:**
  - `git mv lib/data/cloud/* → apps/xorder_pos_cloud/lib/data/cloud/`, except `cloud_api.dart`.
  - `git mv lib/features/admin → apps/xorder_pos_offline/lib/features/admin/`, except what shared code needs. `admin_session.dart` is used by `providers.dart:83`; whether it is back-office-only is checked during the move and recorded.
  - Their tests move with them.
  - The shared package gets interfaces for what it used to reach directly:
    - sales sync: what `till_status_bar`, `branch_sales_providers` and the shift close need to know (pending count, drain now, last outcome);
    - provisioning: `ProvisioningRepository` already exists in `domain/` and gets a cloud implementation;
    - bootstrap seeding: used by `setup_controller.dart`;
    - a back-office route builder for `router.dart`.
    Each has a default that does nothing in the shared package (today's `Unconfigured…` pattern, `data/unconfigured/`).
  - `providers.dart` keeps the declarations. The cloud-only and back-office providers move into each app's wiring, as `ProviderScope` overrides listed in `apps/<app>/lib/wiring.dart`. The 177 providers are not rewritten; only those that construct a moved class change.
  - Every test that constructed a moved class goes to that class's package. Tests that pumped the whole app use the matching app's override list.
- **Tests:**
  - **New: `test/package_boundaries_test.dart`** (AC-2). It reads every `import` under `packages/xorder_pos/lib` and fails on `xorder_pos_cloud` or `xorder_pos_offline`. It also reads both apps' `pubspec.yaml` files and fails if either app depends on the other.
  - Full `check.sh` with the same counts as stage 2, now spread over three packages (`xorder_pos`, `xorder_pos_cloud`, `xorder_pos_offline`).
  - `outbox_drain_test` (AC-4) runs in `apps/xorder_pos_cloud`. As built, `provisional_invoice_test` stayed in `packages/shared_module/test/data/`: it tests the shared repository, not the drain.
- **Risk:** the largest stage. Mostly import and wiring churn; no business rule moves, and the 65 mode checks are not touched yet. A mutation run of the boundary test (add a forbidden import, see it fail) proves the test works.

### Stage 4: the mode checks
Each line in section 4 gets the disposition listed there. The rule is simple: a check that **chooses between the two apps** is removed or moves into that app's wiring. A check that is **a per-mode rule inside shared code** stays, reading the one fixed mode.
- **Tests:**
  - **The rules that stay:** the existing tests for them keep passing unchanged (`postgres_orders_repository`, `shift`, `refunds`, `cash_movements`, `supplier_invoices`, `sync_queue`).
  - **The checks that are removed:** they lose their "other mode" tests, replaced by a test in the app that compiles them in.
  - **AC-5:** an offline flow test with a cloud API fake that fails on any `pos/orders` call.

### Stage 5: two installers and CI
- **Change:**
  - `installer/xorder-pos.iss` takes `/DFlavor=Offline|Cloud`, which sets the app name, the exe, a **new `AppId` per app (D6)**, `OutputBaseFilename` (`XOrder-POS-Offline-Setup-<v>`) and the icon. `ProgramData\XOrder POS`, `pgdata` and the `XOrderPOS-PostgreSQL` service stay shared: one app per machine (D3) makes that safe, and it keeps the branch database across the switch.
  - **`InitializeSetup` refuses (D5)** when the other app's uninstall key, or today's `{6B0C8F3E-…}` key, is present. It names that app and asks for it to be uninstalled first, and installs nothing.
  - The workflow builds the two apps as a matrix. Each job runs its own install, check, upgrade and check-again smoke test, and uploads two artifacts.
- **Tests:**
  - **CI:** the workflow's install smoke test for each app (AC-8).
  - **A person, on Windows:** each installer on a clean machine; each installer on a machine with the other app, which must refuse (AC-10); and today's app uninstalled, then the matching new app installed and pointed at the existing database (AC-9, together with O1).
  - **Not covered:** no automated test reaches Inno Setup's `[Code]` section.

### Stage 6: cloud, one mode per licence (D1, independent of stages 1–5)
- **Repo:** xorder-cloud, branch `feat/licence-one-mode` from `development`.
- **Change:**
  - `StoreLicenceRequest` and `RenewLicenceRequest`: `modes` becomes exactly one mode (planned as `array|size:1`; as built, a closure rule that folds legacy values into offline — see "As built").
  - `RestaurantProvisioningService.php:215` writes one mode (planned; as built, `30b1529` leaves it untouched and validates `licence.modes` in `StoreRestaurantRequest` instead).
  - The Super Admin forms (`RestaurantForm.vue:486`, `LicencesList.vue`) offer a choice of one instead of checkboxes.
  - Renewing a licence that holds both modes shows the choice empty, so the Super Admin must pick one.
  - Response shapes stay the same: `modes` is still an array, now always of one value.
- **Tests:**
  - **Automated:** PHPUnit for both requests, with one mode accepted, both refused, an unknown value refused, and renewal of a "both" licence required to choose (AC-7); the full suite; `pnpm --filter @xorder/web build`.
  - **A person:** the form in the browser (there is no JS test framework).
- **As built (`30b1529`):**
  - **The rule:** one closure rule, `StoreLicenceRequest::oneModeRule()`, used by `StoreLicenceRequest`, `RenewLicenceRequest` and `StoreRestaurantRequest` (`licence.modes`). It counts distinct modes with `branch_server` and `standalone` folded into `offline`, so `['offline','standalone']` is still one mode.
  - **Renewal:** `RenewLicenceRequest::withValidator` refuses a renewal that leaves `modes` out when the licence being renewed covers two modes.
  - **Messages:** `xorder.validation.licence_one_mode` and `licence_one_mode_renewal`, in en and ar.
  - **The forms:** the three pickers became radio buttons (`RestaurantForm.vue`, `pos/LicenceForm.vue`, `pos/LicenceDetails.vue`). The renewal form shows no choice for a "both" licence, and keeps a legacy one-mode value as signed.
  - **Tests:** 5 new and 3 updated, in `PosLicenceTest`, `TenantCreationTest` and `LicenceRenewalUpgradeTest`. Disabling the rule fails 3 tests; disabling the renewal check fails 1.
  - **Results:** licence tests 83/83; full suite `php -d memory_limit=2G vendor/bin/phpunit` 1191/1191; `pnpm --filter @xorder/web build` succeeds.
  - **Not done:** the forms were not opened in a browser.
- **Rollout:**
  - Safe in either order with the POS. Old single-app tills accept one-mode licences already (`licence_decides_mode_test.dart:135`).
  - Reaches `main` only after `/release-check`, and the owner pushes.
  - No migration.

### Stage 7: knowledge
- `docs/architecture/repo-map.md`, `apps/xorder-pos/CLAUDE.md` (layout and commands), and a superseded note on `docs/pos/08-deployment-modes.md` ("a configuration choice, not a second product", `deployment.dart:5`).
- The other five files of this folder, via `/project-documentation feature pos-split-apps`.
- An inventory row, and an update to the QA tracker if any finding moves.

## 4. The 65 mode checks, one by one

Key:
- **R** — remove: it is the choice of app.
- **W** — moves into that app's wiring.
- **K** — keep: a per-mode rule in shared code, reading the fixed mode.
- **G** — guard inside cloud-only code: kept as a cheap assertion, or removed.

| Line | What it decides | Fate |
|---|---|---|
| `app/labels.dart:33-39` | mode names and blurbs for the wizard's mode step | R (the names stay for About) |
| `app/labels.dart:92, 119` | account step wording per mode | K |
| `app/providers.dart:675` | cloud provisioning vs PostgreSQL claim | W |
| `app/providers.dart:735, 1292` | outbox drain and sync wiring | W |
| `app/providers.dart:1560, 3172, 3494` | back-office repositories (logo, catalog admin, financial accounts admin) exist only offline | W (offline wiring) |
| `app/providers.dart:2360` | parse the site licence's mode | K (used for the BR-8 refusal) |
| `app/providers.dart:3412, 3725` | `syncsToPlatform` / `offline` flags passed to repositories | K |
| `app/router.dart:291` | cloud back-office signpost | W (the cloud app's route builder returns the signpost) |
| `app/branch_sales_providers.dart:38, 63` | branch-wide sales from the cloud | W (cloud) |
| `data/backup/backup_service.dart:419` | warn before backup while sales are unsent | K |
| `data/cloud/cloud_sync.dart:185`, `outbox_drain.dart:319` | cloud code refusing to run offline | G |
| `data/postgres/local_bootstrap.dart:343` | seed from cloud bundle | K (fed by the fixed mode) |
| `data/postgres/postgres_{cash_movements:167, shift:78, 373, supplier_invoices:826, 1009}` | outbox client ids only on cloud | K |
| `data/postgres/postgres_orders_repository.dart:226, 434, 457, 489` | XORD-058 invoice number, pending count, platform number | K |
| `data/postgres/postgres_refunds_repository.dart:222` | refund outbox row | K |
| `data/postgres/postgres_sync_queue_repository.dart:72, 84` | empty queue offline | K |
| `data/postgres/postgres_catalog_admin_repository.dart:37` | comment only | — |
| `features/admin/presentation/management_staff_pane.dart:153, 196` | staff editing only offline | R (the pane is offline-only after stage 3) |
| `features/history/{order_detail_pane:101, order_history_screen:689}` | provisional label | K |
| `features/licensing/domain/license.dart:59` | default `modes = {cloud}` | K, plus the D9 check |
| `features/payment/payment_screen.dart:112, 121` | cloud-only payment hints | K |
| `features/receipt/receipt_dialog.dart:78` | `cloudBacked` slip | K |
| `features/settings/about_dialog.dart:74` | About text per mode | K (and the app name) |
| `features/setup/application/setup_controller.dart:308, 407, 434, 874, 1153, 2015, 2027, 2133, 2185` | wizard: mode switch (407, 434) and per-mode steps | R for 407 and 434; K for the rest |
| `features/setup/domain/setup_state.dart:214, 272, 337, 597` | step list per mode | K |
| `features/setup/presentation/setup_panes.dart:305, 318` | the mode picker | R |
| `features/setup/presentation/setup_panes.dart:500, 880, 1429, 1915, 1956, 1972, 2003, 2117` | per-mode panes and wording | K |
| `features/admin/presentation/management_menu_pane.dart:140` | not a deployment mode (`MenuPaneMode`) | — |

Expected result:
- **Removed or moved into an app's wiring:** about 20 lines.
- **Kept:** about 40. They read one fixed value instead of a stored choice.
- **Unchanged:** the 10 definitions in `deployment.dart`.

The table was read from the line text and the surrounding lines in this session; each "K" is confirmed again while editing in stage 4, and any change of fate is recorded here.

## 5. Impact and compatibility

| Area | Effect |
|---|---|
| API and contract | None. No route, payload or response shape changes. Stage 6 narrows what the Super Admin may submit. |
| Schema and migrations | None. Both apps run the same migrations through `pos_migrate` (BR-3). |
| Money, orders, tenancy | None. `TicketEngine`, totals, refunds, shift and outbox payloads are shared code that does not move between apps. AC-3 and AC-4 are proven by the same tests running in their new packages. |
| Permissions | None in the POS. The cloud Super Admin may no longer issue a "both" licence (stage 6). |
| Existing installs | Test machines only (no restaurant runs the POS, 2026-11-06). Today's app is uninstalled by hand (D5, D6). The branch database stays; `config.json` does not follow (O1). |
| Child tablets and second tills | A child installs the same app as its main device. A mismatch is refused, because the database's site licence names the mode (stage 2). |
| Localization | No new strings beyond the refusal messages (en and ar); the app names are English only (D8). |
| Deploy order | Stage 6 (cloud) can ship at any time. The POS apps replace the single installer at the next POS release, from a green `check.sh`, a tag and the workflow. |

## 6. Domain lens

No venue model changes behaviour; each installs one app:
- **Cafés and restaurants:** either app, depending on whether they want the dashboard.
- **Food trucks with poor signal:** either. A cloud till keeps selling on its local database (the reason behind D9).
- **Cloud kitchens:** the cloud app.

The split adds no assumption about tables, addresses or connectivity. The known gaps (KDS, aggregators, tips) are not touched.

## 7. Verification commands

- **POS, every stage:**
  - `cd apps/xorder-pos && scripts/check.sh`, which stage 1 changes to walk every workspace package;
  - one package alone: `cd packages/<pkg> && flutter test`;
  - PostgreSQL suites alone: `POS_PG_HOST=127.0.0.1 POS_PG_PORT=5432 POS_PG_USER=$USER POS_PG_PASSWORD=postgres flutter test --tags integration --concurrency=1`.
- **POS builds:** `cd apps/<app> && flutter build macos --debug` locally. Windows builds run only in CI.
- **Cloud, stage 6:** `cd apps/xorder-cloud/apps/api && php artisan test`; `cd apps/xorder-cloud && pnpm --filter @xorder/web build`.
- **Harness:** `bash scripts/harness/verify.sh`.

## 8. Approvals needed

1. **The plan itself:** stages 0–7 as written.
2. **Stage 0:** holding other POS work, and merging the in-flight dropdown and installer-tag work first. That work belongs to other sessions; whoever owns it commits it.
3. **Commits:** one commit per stage on `feat/pos-split-apps`, plus a merge into POS `development` at the end. Nothing is pushed.
4. **Stage 6:** the cloud licence change on `feat/licence-one-mode`. It narrows a Super Admin input and reaches `main` only through `/release-check` and the owner's push.
5. **Deletions:** the root platform folders move, and the Android, iOS, Linux and web folders are dropped if O3 says so.

## 9. Questions answered by the owner (2026-11-08, "Approve as suggested")

- **O1, config on test machines:** after the switch, should a new app read today's `%APPDATA%\XOrder\XOrder POS\config.json` once, so a test till skips setup? Suggested: **no**. Setup runs again and joins the existing database, there are no restaurants yet, and it saves a migration path nobody will need.
- **O2, the shared package's name:** keep `xorder_pos`? Suggested: **yes**, it avoids changing 354 files that import `package:xorder_pos/`. Renaming it later is a mechanical change of its own.
- **O3, Android, iOS, Linux and web folders:** these are scaffolding nobody ships. Suggested: **don't carry them into either app**. They stay in git history and `flutter create --platforms=android` regenerates them when a handheld app is built.
