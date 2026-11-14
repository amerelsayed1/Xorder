# Test plan: two POS apps on shared modules

Verified against: 2026-11-08 · POS `development` `7fa0d06` · cloud `feat/licence-one-mode` `30b1529`. Paths are relative to `apps/xorder-pos/` unless they start with `apps/xorder-cloud/`. This is the plan and the mapping of acceptance criteria (FEATURE.md section 8 and 12) to tests, by stage (TECHNICAL.md section 3). Results live in `TEST_REPORT.md`; nothing here claims a test passed.

## Test environments
- **POS, every member:** `cd apps/xorder-pos && scripts/check.sh` from the repo root. It runs `flutter pub get`, then for `packages/shared_module`, `packages/xorder_pos_test_support` (analyse only, no tests), `apps/xorder_pos_offline`, `apps/xorder_pos_cloud`: `flutter analyze`, `flutter test --exclude-tags integration`, `flutter test --tags integration --concurrency=1`. Needs a local PostgreSQL (`POS_PG_*`, default `127.0.0.1:5432` as `$USER`). A path argument narrows the run to `shared_module`. Not run in CI.
- **One member, no database:** `cd packages/shared_module && flutter test` (or `apps/xorder_pos_offline`, `apps/xorder_pos_cloud`); `integration`-tagged suites self-skip without `POS_PG_HOST`.
- **Builds:** `cd apps/<app> && flutter build macos --debug` locally. Windows builds and the installer only in CI, started by hand (`gh workflow run windows-installer.yml --ref <ref>`).
- **End to end:** `apps/xorder_pos_cloud/integration_test/` (needs a real platform and database).
- **Cloud (stage 6):** `cd apps/xorder-cloud/apps/api && php artisan test` (SQLite `:memory:`); `cd apps/xorder-cloud && pnpm --filter @xorder/web build`.
- **Harness:** `bash scripts/harness/verify.sh` (workspace root).

## Baseline (stage 0)
Counts to compare against, recorded on `3052a53` and repeated on stage 1 (`36a78f3`): unit 3544 passed, 2 skipped; PostgreSQL 1247 passed, 1 skipped (FEATURE.md section 3; commit message of `36a78f3`).

## Acceptance criteria to tests
| AC | Test (path on `7fa0d06` where it exists) | Kind | Stage | Coverage state |
| --- | --- | --- | --- | --- |
| AC-1 | `scripts/check.sh` over all four members; per-member counts compared with the baseline | automated | 1–3, every stage | exists; totals per member recorded in TEST_REPORT |
| AC-2 | `packages/shared_module/test/package_boundaries_test.dart`: shared `lib/` imports neither app; neither app's pubspec names the other; shared `lib/data/cloud` holds only `cloud_api.dart` and `device_token_vault.dart`; no shared `lib/features/admin`; `lib/features/admin_mode` exists | automated, new | 3 | exists; mutation-checked per TECHNICAL.md stage 3 |
| AC-3 | existing `TicketEngine`, receipt and payment suites in `packages/shared_module/test/`; one parity test per app | automated | 3–4 | engine suites exist (shared); **per-app parity test not written** |
| AC-4 | `apps/xorder-pos/apps/xorder_pos_cloud/test/data/outbox_drain_test.dart`; `packages/shared_module/test/data/provisional_invoice_test.dart` (PostgreSQL, `integration`); `apps/xorder-pos/apps/xorder_pos_cloud/test/data/cloud_orders_wiring_test.dart` (the cloud orders binding with the cloud app's wiring) | automated | 3 | exists. Note: `provisional_invoice_test` stayed in the shared package (it exercises the shared PostgreSQL orders repository), not in the cloud app as TECHNICAL.md stage 3 planned |
| AC-5 | offline flow test with a cloud API fake that fails on any `pos/orders` call | automated, new | 4 | **not written** |
| AC-6 | `packages/shared_module/test/features/licence_decides_mode_test.dart` ("covering both" rewritten as refusals per app); `packages/shared_module/test/features/fixed_app_mode_test.dart` (no mode step, other mode refused and named, both refused, empty claim accepted); `packages/shared_module/test/features/wrong_app_boot_test.dart` (`bootFor` and the router, BR-8) | automated | 2 | exists |
| AC-6 / BR-8 (database) | PostgreSQL test: a database whose site licence says `cloud` is refused by the offline wiring, and the reverse | automated, new | 2 | **not written** as an `integration` suite; covered only at controller level through the child path (TECHNICAL.md stage 2 "Not done") |
| AC-7 | cloud PHPUnit: `PosLicenceTest`, `TenantCreationTest`, `LicenceRenewalUpgradeTest` (5 new, 3 updated on `30b1529`); Super Admin form in a browser | automated + person | 6 | automated exists on the branch; **browser check not done** |
| AC-8 | Windows installer workflow: two installers, own ids, install smoke test per app | CI + person | 5 | **stage 5 not started** (workflow builds the offline app only) |
| AC-9 | PostgreSQL test that migrates a database written by `3052a53` and reads it with each app's repositories | automated, new | 4/5 | **not written** |
| AC-10 | install one app where the other is installed, on Windows: refused, names the installed app, changes nothing | person | 5 | **not started** |

## Unit and widget tests by member (stage 3 layout)
- `packages/shared_module/test/`: the shared till's suites (core, domain, data, features, app, tool), including `package_boundaries_test.dart` and `tool/installer_consistency_test.dart`.
- `apps/xorder_pos_offline/test/`: the back office suites (moved with `lib/features/admin/`), `test/support/offline_harness.dart` (`offlineTestOverrides`) for `settings_bar_test` and `admin_entry_test`, which pump the whole app; `sync_pane_test` without its 11 cloud-till cases.
- `apps/xorder_pos_cloud/test/`: the cloud sync suites (moved with `lib/data/cloud/`), including `outbox_drain_test` and `cloud_orders_wiring_test`.
- `packages/xorder_pos_test_support/`: no tests of its own; analysed by `check.sh`.

## Regression and negative cases
- **Lost tests (FEATURE.md section 11 risk):** compare declared and run counts per member with the stage before. Stage 3 recorded 4676 declared before → 4668 after (−11 sync-pane cloud cases, +3 boundary tests).
- **Boundary mutation:** add a forbidden import of `xorder_pos_cloud` in shared `lib/`, expect `package_boundaries_test` to fail, revert.
- **Licence negatives (AC-6):** own mode accepted; other mode refused naming the other app; both modes refused (`modeAmbiguous`); legacy `branch_server`/`standalone` parse as offline.
- **Assets (`7fa0d06`):** each macOS bundle holds each IBM Plex file and the mark exactly once; `FontManifest` lists `packages/shared_module/...` families. Checked by hand on the build output, not by an automated test.

## Stage 4 and 5 additions (planned, TECHNICAL.md)
- Stage 4: the per-mode rules that stay (`postgres_orders_repository`, shift, refunds, cash movements, supplier invoices, sync queue) keep their tests unchanged; removed checks lose their "other mode" tests, replaced by a test in the app that compiles them; AC-5 flow test.
- Stage 5: workflow matrix with install, check, upgrade, check-again per app (AC-8); a person on Windows for AC-9 with O1 and AC-10. No automated test reaches Inno Setup's `[Code]` section.

## Not covered by any automated test
- Windows builds and installers (CI by hand, person on Windows).
- `apps/xorder-pos/apps/xorder_pos_cloud/integration_test/sale_to_settle_test.dart`: needs a real platform and database; its wizard walk still expected a setup-type step after stage 2 (TECHNICAL.md stage 2 "Not done"), and on `7fa0d06` it still does (`sale_to_settle_test.dart` around line 505: "Setup type (cloud is preselected) and language are confirmations", two `Continue` taps). Read, not run: it is expected to fail on that walk until it is updated.
- Super Admin licence forms (no JS test framework).
