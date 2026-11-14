# Test report — pos-cloud-sign-in-setup

Date: 2026-11-08 · Environment: macOS, Flutter 3.47.7, local PostgreSQL 127.0.0.1:5432 · Source: xorder-pos `development` `9f1b7d2` + uncommitted working tree.

## Commands and real results
`cd apps/xorder-pos && scripts/check.sh` (analyze + unit + PostgreSQL, every member). Exit 0, "All checks passed.", test databases dropped (1 of 1).

| Package | Analyze | Unit | PostgreSQL |
|---|---|---|---|
| packages/shared_module | No issues | +2582 ~2, all passed | +1136 ~1, all passed |
| packages/xorder_pos_test_support | No issues | — | — |
| apps/xorder_pos_offline | No issues | +852, all passed (same count as before the change: AC-11) | +6, all passed |
| apps/xorder_pos_cloud | No issues | +130, all passed (123 before + 7 new owner tests) | +107, all passed |

Targeted runs during the build (all passed at the end):
- `flutter test test/features/setup_wizard_test.dart`: +55
- `flutter test test/features/cloud_setup_collapsed_test.dart --timeout 60s`: +18
- `flutter test test/features/setup_persistence_test.dart`: +36
- `flutter test test/data/cloud_provisioning_owner_test.dart` (cloud app): +7

Failures met and fixed during the build (not hidden):
- The first licence check refused a till **resumed after a restart** ("a restart between the claim and Open the till"). This was an app bug, fixed in `_cloudLicenceRefusal`.
- The rewritten walk test hung, because it awaited the fakes' real delays inside a widget test. This was a test bug, fixed with a clock-pumping `settle` helper and a step guard.

## Not run
- **End to end** (`apps/xorder_pos_cloud/integration_test/sale_to_settle_test.dart`). A local API (`:8080`) and PostgreSQL were up. It was not run because it signs into and claims a terminal on the owner's local dev tenant, and because that tenant's licence likely names both modes (`feat/licence-one-mode` is not merged), which D4 refuses by design. Its driver was rewritten blind.
- **A person looking at the Arabic sign-in screen** (AC-12 layout).
- **PostgreSQL-only behaviour of the cloud API:** not touched; no backend change.

## Gaps
See `TEST_PLAN.md` § Gaps.
