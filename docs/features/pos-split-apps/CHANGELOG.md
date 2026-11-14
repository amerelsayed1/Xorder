# Feature changelog: two POS apps on shared modules

Commits on xorder-pos `development` from `3052a53` (the starting point the plan was verified against) to `7fa0d06`, oldest first (`git -C apps/xorder-pos log --oneline 3052a53..7fa0d06`), plus the cloud stage-6 commit. All dated 2026-11-08 (the day they landed on `development`; the two installer fixes were authored 2026-11-03 and merged that day). Nothing is pushed.

## 2026-11-08 — stage 0: clear the way (prerequisite work merged first)
These commits are not pos-split-apps code; they were merged before stage 1 so the file moves would not conflict with them (TECHNICAL.md stage 0).
- `07ebfec` fix(installer): keep a Pascal continuation line from reading as an Inno section tag (authored 2026-11-03).
- `3f25efd` fix(ci): delimit `$when` in the installer check so PowerShell parses it (authored 2026-11-03).
- `96e49dd` refactor(ui): one `FilterDropdown` for the history, shift and users filters (dropdown work from `fix/xord-044-046-parked-check-versions`).
- `fb02cf1` merge `fix/xord-044-046-parked-check-versions` into `development`.
- `d54d5de` merge `fix/installer-iss-section-tag` into `development`.
- Compatibility notes: none from this feature.
- Verification: baseline `scripts/check.sh` on `3052a53`: unit 3544 passed, PostgreSQL 1247 passed (FEATURE.md section 3).

## 2026-11-08 — stage 1: the till moves into `packages/xorder_pos` (`36a78f3`, merged at `0f3ea08`)
- Status: done. Behaviour unchanged.
- Changes: the repository becomes a Dart pub workspace whose one member is the till, moved with `git mv`; root `pubspec.yaml` lists members, one root `pubspec.lock`; `check.sh`, `package_macos.sh`, the Windows workflow, the `.iss` and `installer_consistency_test` point at the new folder. The merge resolved one conflict (`pos_dropdown_field_test.dart` followed its directory).
- Compatibility notes: path changes only; no Dart code change.
- Verification: `check.sh` analyse clean; unit 3544 passed, 2 skipped; PostgreSQL 1247 passed, 1 skipped (same as `3052a53`).

## 2026-11-08 — stage 2: two app packages with a fixed mode (`789db8c`, merged at `d36611c`)
- Status: done.
- Changes: `apps/xorder_pos_offline` and `apps/xorder_pos_cloud` with `main.dart`, `windows/`, `macos/`, names and bundle ids per D4; `runPos(mode:)` replaces `lib/main.dart`; `appModeProvider`; no mode step in the wizard (BR-1); other-mode and both-mode licences refused (BR-2, D9, `LicenseState.modeAmbiguous`); a `config.json` or site licence from the other app parks the till on `WrongAppScreen` (BR-8); `android/ ios/ linux/ web/` removed (O3); `check.sh` analyses both apps; `package_macos.sh offline|cloud`; the Windows workflow and installer build the offline app.
- Compatibility notes: wizard step order changes (BR-1); no API or schema change.
- Verification: analyse clean; unit 3563 passed, 3 skipped; macOS debug build of the offline app. Not run: PostgreSQL suites, `integration_test/`, Windows build.

## 2026-11-08 — test fix (`49003bf`)
- Changes: the XORD-035 bootstrap test follows the earlier business rename (`seedBusiness` / `pos_businesses`); it had broken `flutter analyze` on `development` after the stage-0 merge. Not split-specific; landed between stages 2 and 3.
- Verification: analyse clean; `local_bootstrap_test.dart` 4 passed (PostgreSQL).

## 2026-11-08 — stage 3: mode-only code moves into its app (`0d97785`)
- Status: done, directly on `development`.
- Changes: cloud sync code (`data/cloud` except `cloud_api.dart` and `device_token_vault.dart`), the cloud back-office signpost and `integration_test/` move to `apps/xorder_pos_cloud`; the back office (`features/admin`) moves to `apps/xorder_pos_offline`; each app gets `lib/wiring.dart`; seams with do-nothing defaults in the shared package (`SalesSync`, `BootstrapSeeding`, back-office contract, platform branch sales); Admin Mode's door moves to `features/admin_mode`; new member `packages/xorder_pos_test_support`; `package_boundaries_test` (AC-2); `check.sh` runs every member. `sync_pane_test` loses 11 cloud-till cases.
- Compatibility notes: no behaviour, API or schema change intended (BR-10); the 65 mode checks are untouched until stage 4.
- Verification: analyse clean in all four members; unit shared 2590 (2 skipped), offline 855, cloud 117 (1 skipped); PostgreSQL shared 1136, offline 6, cloud 107; both apps build on macOS. Not run: Windows build, `integration_test/`.

## 2026-11-08 — rename to `shared_module`; fonts and mark declared once (`7fa0d06`)
- Status: done, directly on `development`. Supersedes O2 (owner: "change this xorder_pos to shared_moduel").
- Changes: `packages/xorder_pos` → `packages/shared_module`, package `shared_module`; every `package:xorder_pos/` import, member dependency, workspace pubspec, `check.sh`, `package_macos.sh`, Windows workflow and installer script follow. Fonts and the mark are declared only by `shared_module`; `PosFonts` names `packages/shared_module/...` families; the logo `Image.asset` calls pass `package: 'shared_module'`; the apps' logo copies are deleted. The Windows workflow's smoke test now looks for `xorder_pos_offline.exe`.
- Compatibility notes: the branch database is still named `xorder_pos` (database name, not the package).
- Verification: analyse clean in all four; unit shared 2590 (2 skipped), offline 855, cloud 123; PostgreSQL shared 1136 (1 skipped), offline 6, cloud 107; both apps build on macOS with each font and the mark bundled once. Not run: Windows build.

## 2026-11-08 — stage 6 (cloud): a licence covers one mode (xorder-cloud `30b1529`, branch `feat/licence-one-mode`)
- Status: built; **not merged, not pushed**.
- Changes: `StoreLicenceRequest::oneModeRule()` on `StoreLicenceRequest`, `RenewLicenceRequest`, `StoreRestaurantRequest` (`licence.modes`); renewal of a two-mode licence must choose; messages in en and ar; Super Admin pickers become radio buttons. See API.md.
- Compatibility notes: narrows a Super Admin input; response shapes unchanged; no migration; reaches `main` only after `/release-check` and the owner's push.
- Verification: licence tests 83/83; full PHPUnit 1191/1191; web build succeeds. Not done: forms in a browser.

## 2026-11-08 — stage 7: knowledge (documentation only)
- Changes: `docs/architecture/repo-map.md` and `.claude/rules/pos-flutter.md` follow the `7fa0d06` layout; API, DATABASE, TEST_PLAN, TEST_REPORT and this CHANGELOG written; inventory row updated. `apps/xorder-pos/docs/pos/08-deployment-modes.md` (inside the POS repo) not edited; it still needs a superseded note.
- Verification: `bash scripts/harness/verify.sh`; no product test run.

## Not yet done
Stages 4 (mode checks) and 5 (two installers and CI).
