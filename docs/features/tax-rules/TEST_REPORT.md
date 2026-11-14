# Test execution report

Feature: `tax-rules` (slice: XORD-027, offline VAT rate) · Run 2026-10-26 · Verified against: xorder-pos `a6f5fe5` (+ uncommitted work from other sessions in the same tree), xorder-cloud not exercised.

## Date and environment
macOS (Darwin 25.6.0), Flutter from `/Users/amerelsayed/developement/flutter`. PostgreSQL 17.2 (Homebrew) on `127.0.0.1:5432`, login role, checkout-specific throwaway database `xorder_pos_test_<hash>` created by `test/data/pg_fixture.dart`. No real or production database was touched. The working tree held other sessions' uncommitted edits (128 entries), including in three files this change edited; results below therefore describe the mixed tree.

## Commands executed
1. `flutter analyze lib/features/sale/widgets/cart_panel.dart lib/features/admin/presentation/management_taxes_pane.dart lib/data/postgres/postgres_catalog_admin_repository.dart test/features/money_panes_ownership_test.dart test/features/tax_groups_wiring_test.dart test/features/cart_totals_alignment_test.dart test/data/postgres_catalog_admin_test.dart`
2. `flutter test test/features/money_panes_ownership_test.dart test/features/tax_groups_wiring_test.dart test/features/cart_totals_alignment_test.dart`
3. `POS_PG_HOST=127.0.0.1 POS_PG_PORT=5432 POS_PG_USER=$USER POS_PG_PASSWORD=… flutter test --concurrency=1 --tags integration test/data/postgres_catalog_admin_test.dart`
4. Mutation checks (temporary edits in a scratch copy, files restored and re-verified by grep): old pane seeding + old cart label → tests 2; repository UPDATE neutralised → test 3 (`--plain-name "money rules"`); group invalidation removed → `--plain-name "typing 0 over"`.
5. `flutter analyze` (whole repo), then `flutter test` (whole suite, no `POS_PG_HOST`).
6. `python3 scripts/harness/check-citations.py`, `python3 scripts/harness/check-docs.py`, `bash scripts/harness/verify.sh`.

## Results (passed / failed / blocked / not run)
| Run | Result |
|---|---|
| 1 targeted analyze | No issues found |
| 2 widget/provider tests | **31 passed** (10 new: 3 pane, 3 ticket-rate, 3 cart label, plus the existing ones in those files) |
| 3 PostgreSQL catalog-admin suite | **51 passed** (6 new "money rules" tests) |
| 4 mutations | each made the intended tests fail: pane seeding (box showed 14, expected 0), cart label (3 failures), UPDATE neutralised (4 failures, `Expected: [0] Actual: [1400]`), invalidation removed (1 failure, re-read count) |
| 5 whole-repo `flutter analyze` | **No issues found** (an earlier run reported 2 errors in `test/features/back_office_shell_test.dart`, another session's in-progress file; gone by this run) |
| 5 whole-suite `flutter test` | **+3259 passed, ~79 skipped (the PostgreSQL-tagged suites), 0 failed** |
| 6 harness | structure OK; citation check 655 resolve, 2 problems in `docs/features/customers/XORD-001-STAGE1-CLOUD-BRIEF.md` (not this feature); `check-docs.py` complaints are about `back-office-navigation`, `customers`, `financial-accounts`, `global-status-bar` (not this feature) |
Not run: the rest of the PostgreSQL-tagged suites (only the one changed suite was run); cloud PHPUnit (no cloud code changed); any running app, printer or real-font check.

## Evidence and logs (redacted)
The failing assertions from the mutation runs: `Expected: [0] Actual: [1400]`, `Expected: [1500] Actual: [1400]`, `Expected: {'Reduced': 500, 'VAT': 0} Actual: {'Reduced': 500, 'VAT': 1400}`, `Expected: a value greater than <1> Actual: <1>`. Raw output is in the session's scratchpad, not kept in the repo.

## Known gaps and release risks
- No test sells at the register after saving the box: the chain is proven in pieces (repository writes the group; ticket is taxed at the group; pane re-reads groups).
- No cross-tenant test for the new UPDATE (one restaurant per run); scoped by `restaurant_id` by code reading.
- The setup review screen still prints a fixed "VAT 14%"; the service row label still rounds fractions.
- Tills where the box and the group already disagree are not repaired.
- Manual check on a real offline till and a printed receipt is still owed (TEST_PLAN, "Regression and manual QA").
- Documentation status: `drafted`, not independently validated.
