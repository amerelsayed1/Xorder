# Test execution report: two POS apps on shared modules

Verified against: 2026-11-08 · POS `development` `7fa0d06` · cloud `feat/licence-one-mode` `30b1529`. Paths are relative to `apps/xorder-pos/` unless they start with `apps/xorder-cloud/`.

## Date and environment
All results below were produced on 2026-11-08 by the sessions that built each stage, on the owner's macOS machine with a local PostgreSQL, and are copied from the commit messages and from TECHNICAL.md's Progress block. **The stage-7 documentation pass ran no Flutter, PHP or pnpm command**; it only read git. Raw command output was not kept in the repository; the numbers are as the commits record them.

## Commands executed (as recorded)
- POS: `scripts/check.sh` (every member: `flutter analyze`, `flutter test --exclude-tags integration`, `flutter test --tags integration --concurrency=1`); `flutter build macos --debug` per app.
- Stage 2 only: `flutter analyze`; `flutter test --exclude-tags integration`; `flutter build macos --debug` of `apps/xorder_pos_offline`.
- `49003bf`: `flutter analyze`; `flutter test --tags integration test/data/local_bootstrap_test.dart`.
- Cloud stage 6: licence tests; `php -d memory_limit=2G vendor/bin/phpunit`; `pnpm --filter @xorder/web build`.

## Results (passed / failed / blocked / not run)
| Commit / stage | Analyse | Unit and widget | PostgreSQL (`integration`) | Builds | Source |
| --- | --- | --- | --- | --- | --- |
| `3052a53` baseline (stage 0) | clean | 3544 passed, 2 skipped | 1247 passed, 1 skipped | — | FEATURE.md section 3; `36a78f3` message ("same as 3052a53") |
| `36a78f3` stage 1 (`packages/xorder_pos`) | clean | 3544 passed, 2 skipped | 1247 passed, 1 skipped | not run | commit message |
| `789db8c` stage 2 (two apps, fixed mode) | clean (shared + both apps) | 3563 passed, 3 skipped (`--exclude-tags integration`) | **not run** | macOS debug of offline app: "XOrder POS - Offline.app" (`io.xorder.pos.offline`); cloud app build not recorded; Windows not run | commit message |
| `49003bf` (XORD-035 bootstrap test rename) | clean | — | `local_bootstrap_test.dart`: 4 passed | — | commit message |
| `0d97785` stage 3 (mode-only code into its app) | clean, all four members | shared 2590 passed (2 skipped); offline 855; cloud 117 (1 skipped) | shared 1136; offline 6; cloud 107 ("1 skipped overall") | macOS debug: both apps build; Windows not run | commit message; TECHNICAL.md Progress |
| `7fa0d06` rename to `shared_module`, assets declared once | clean, all four members | shared 2590 (2 skipped); offline 855; cloud 123 | shared 1136 (1 skipped); offline 6; cloud 107 | macOS debug: both apps build; each bundle holds each IBM Plex file and the mark exactly once; `FontManifest` lists `packages/shared_module/IBM Plex Sans Arabic` and `packages/shared_module/IBM Plex Mono`; Windows not run | commit message |
| `30b1529` cloud stage 6 (one mode per licence) | — | licence tests 83/83; full suite 1191/1191 | n/a (SQLite) | `pnpm --filter @xorder/web build` succeeds | TECHNICAL.md stage 6 "As built" |

**Totals on `7fa0d06`** (sum of the recorded per-member numbers): unit 3568 passed (2 skipped); PostgreSQL 1249 passed (1 skipped). Baseline was 3544 / 1247. The sum is arithmetic on the recorded numbers, not a new run; the plan's test-count reconciliation (FEATURE.md section 11, "lost tests") is not recorded for `7fa0d06`.

## Not run
| Item | Why |
| --- | --- |
| Windows builds of either app | CI only, started by hand; not started for these commits |
| Windows installers (AC-8, AC-10) and AC-9 on a real machine | stage 5 not started; needs a person on Windows |
| `apps/xorder_pos_cloud/integration_test/` | needs a live platform and database; its wizard walk still expects a setup-type step (TEST_PLAN.md) |
| PostgreSQL suites at stage 2 | not run in that commit (recorded) |
| AC-5 offline flow test, AC-9 migration test, BR-8 PostgreSQL refusal test, per-app parity test (AC-3) | not written yet |
| Super Admin licence forms in a browser (AC-7, person part) | not done |
| Stage-7 pass itself | documentation only; no test command run |

Feature-level status: **partially verified**. Stages 1–3 and the rename are verified by `scripts/check.sh` and macOS builds as recorded; stages 4 and 5 are not started; stage 6 is verified on an unmerged cloud branch.

## Discrepancies in the recorded numbers
- **Cloud unit count:** 117 (1 skipped) at `0d97785`, 123 with no skip noted at `7fa0d06`. `7fa0d06` changes no test count by its message (it renames imports and assets); `git diff 0d97785 7fa0d06 -- apps/xorder_pos_cloud/test` adds or removes no `test(`/`testWidgets(` declaration and no `skip` (16 files, 92 lines changed each way, imports). So the +6 and the vanished skip are not explained by the code; one of the two recorded numbers is probably a miscount or came from a different run. UNVERIFIED until the cloud member is run again.
- **PostgreSQL skip:** `0d97785` says "1 skipped overall"; `7fa0d06` attributes the 1 skip to shared. Probably the same skip, recorded differently (UNVERIFIED).

## Evidence and logs (redacted)
Commit messages: `git -C apps/xorder-pos show -s 36a78f3 789db8c 49003bf 0d97785 7fa0d06`. Cloud: TECHNICAL.md stage 6 "As built" (`30b1529`). No secrets or customer data are involved.

## Known gaps and release risks
- Windows is the shipping platform and nothing about the split has been built or installed on it yet.
- `integration_test/` is known stale against the fixed-mode wizard.
- Until stage 5, the installer ships only the offline app.
- Stage 6 is unmerged; both new apps refuse "both" licences regardless (D9), so a "both" licence issued before stage 6 ships cannot be used with either new app.
