# Test report: financial accounts (XORD-015, stage 1)

Run 2026-10-26 on macOS, PHP 8.3.19, PHPUnit 12.5.30, Flutter (stable on this machine), a local PostgreSQL 16 server. Revisions: xorder-cloud `06bc8e3`, xorder-pos `a6f5fe5`, **both working trees dirty** (other sessions' uncommitted work is in every run below; the "before" numbers are the same trees before my first edit). Planned tests: `TEST_PLAN.md`. Nothing here ran against production or any real database.

## Environment notes
- `php artisan test` on this machine exhausts PHP's default 128 MB (`Allowed memory size of 134217728 bytes exhausted … Premature end of PHP process`), because it runs PHPUnit in a child process that ignores `php -d memory_limit`. All cloud runs below call PHPUnit directly with a higher limit and the same `phpunit.xml`: `php -d memory_limit=2G vendor/bin/phpunit`. This is an environment setting, not a code change.
- POS PostgreSQL suites ran against this checkout's own throwaway database `xorder_pos_test_47ecbf8e`, or against scratch databases created for the comparison run and dropped afterwards (see "Cleanup").

## Results

| Suite | Command | Before my edits | After |
| --- | --- | --- | --- |
| Cloud API (SQLite) | `cd apps/xorder-cloud/apps/api && php -d memory_limit=2G vendor/bin/phpunit --no-progress` | `{"result":"passed","tests":1124,"passed":1124,"assertions":5404}` exit 0 | `{"result":"passed","tests":1148,"passed":1148,"assertions":5590}` exit 0 |
| Cloud, the new file | `… vendor/bin/phpunit --filter FinancialAccountsTest` | n/a | `OK (24 tests, 184 assertions)` |
| Dashboard build | `cd apps/xorder-cloud && pnpm build` | not run | `Tasks: 3 successful, 3 total`, exit 0 (re-run after the last panel edit). **No JS test framework exists; none was added** |
| POS static analysis | `cd apps/xorder-pos && flutter analyze` | 2 issues, both in `test/features/till_status_bar_test.dart` (not mine; gone by the end, another session fixed them) | `No issues found!` |
| POS unit and widget | `flutter test` | `+3268 ~79: All tests passed!` | `+3313 ~80: All tests passed!` (the difference includes other sessions' new tests) |
| POS new tests, no database | `flutter test test/domain/financial_accounts_test.dart test/data/financial_accounts_bundle_test.dart test/features/management_accounts_pane_test.dart` | n/a | domain `+17`, bundle `+10`, pane `+15`, all passed |
| POS PostgreSQL, accounts | `POS_PG_HOST=127.0.0.1 POS_PG_PORT=5432 POS_PG_USER=$USER POS_PG_PASSWORD=postgres flutter test --tags integration --concurrency=1 test/data/financial_accounts_test.dart` | n/a | `+25: All tests passed!` |
| POS PostgreSQL, related | same flags, `test/data/{financial_accounts,till_grants_enforced,admin_grants_enforced,grants_cover_usage,tender_types_schema,cloud_tenders}_test.dart` | n/a | `+92: All tests passed!` (the existing payment-method and grant suites included) |

New tests: cloud 24; POS 17 + 10 + 25 + 15 = 67; plus grant probes added to `till_grants_test`, `till_grants_enforced_test`, `admin_grants_enforced_test`.

## Acceptance criteria
Stage 1 only. The mapping and the exact tests are in `TEST_PLAN.md`. AC-1, AC-3, AC-5, AC-6, AC-7, AC-8 (new POS with an old cloud) are proved by tests that ran; AC-2 and AC-4 are proved **partly** (the default chooser, not a payment); AC-9 is not applicable until stage 2; **AC-15 (Arabic wording, RTL on screen) and the dashboard layout need a person**; AC-10 to AC-14 are stage 2 and were not written.

## Mutation checks (rule broken on purpose, the test failed, the file was restored and diffed)
1. Pane offers *Add* on a cloud till → `management_accounts_pane_test` "a cloud till is told these are the platform's…" failed.
2. Write routes gated by `settings.update` instead of `finance.accounts` → two `FinancialAccountsTest` tests failed (`Expected response status code [403] but received 201`).
3. A branch's own account allowed as the business-wide default → `…a_branch_default_can_use_that_branchs_own_account…` failed.
4. Account-number pattern reverted to ASCII digits → `test_an_account_number_is_refused_in_any_script_and_in_the_name_too` failed.
5. Branch-delete guard removed → `test_a_branch_that_has_an_account_cannot_be_deleted_and_says_why` failed.

## The full POS PostgreSQL suite fails at the committed revision (not caused by this work)
`flutter test --tags integration --concurrency=1` (all suites) was run twice more, each on a fresh database (a copy at a new path gets a new database):

| Tree | Result | Error kinds |
| --- | --- | --- |
| Pristine `git archive` of `xorder-pos` HEAD `a6f5fe5` (none of the uncommitted work) | `+677 ~1 -436: Some tests failed.` | `pos_combo_options_product_id_fkey` ×239, `pos_orders_voided_by_fkey` ×149, `pos_orders_business_day_fk` ×22, `pos_orders_served_by_fkey` ×21, `pos_orders_shift_id_fkey` ×3, 1 missing database, 1 late-initialisation |
| Working tree with XORD-015 (and everything else uncommitted) | `+743 ~1 -456: Some tests failed.` | the same kinds; nothing that is not also at HEAD apart from 20 tests that exist only in uncommitted work (order-types migration, bulk tables, category and VAT tests) |

Every failing test at HEAD also fails in the working tree (set difference empty). The accounts suites (`financial_accounts_test`, `till_grants_enforced_test`, `admin_grants_enforced_test`, `cloud_tenders_test`) show **no errors** inside the full run; `tender_types_schema_test` fails 19 of 19 at HEAD and in the working tree with the same `pos_orders_business_day_fk` error. The cause is the suites' own `DELETE FROM pos_restaurants` cleanup meeting foreign keys it cannot cascade over once an earlier suite leaves rows behind; whether that is the PostgreSQL version, the fixture or a real schema ordering problem is **not known**. Filed as **XORD-029**; needs `/bug-investigation`. Until then a full `scripts/check.sh` PostgreSQL pass cannot be claimed for this change; the accounts suites above were run on their own.

Also: while diagnosing this, this checkout's throwaway database `xorder_pos_test_47ecbf8e` was left holding test rows from my first full run (slugs `cb`, `print-probe`, `park-probe`, created minutes earlier). They were cleared with `TRUNCATE pos_restaurants CASCADE` after confirming they were test data; the schema and `schema_migrations` (at 60) were untouched.

## Cleanup
The two comparison runs created `xorder_pos_test_6656d927` and `xorder_pos_test_9aaba772` and four `xorder_test_backup_*` roles. They were dropped (`DROP DATABASE … WITH (FORCE)`, `DROP ROLE`), and the scratch copies of the POS tree were deleted. The server now holds only the two databases that existed before.

## Not run / not verified
- The dashboard Accounts tab in a browser (light and dark, narrow width, RTL), the Finance › Accounts pane on a running till, an offline-till session against a real branch server.
- An **old POS build** against the new cloud bundle (argued by reading: `BootstrapTenderType` reads per field and `money` is stored verbatim).
- The cloud migrations on **PostgreSQL**: only `CREATE TABLE` with ordinary foreign keys and one ordinary unique index, reviewed by reading; the cloud suite is SQLite. A rolled-back temporary-table repro on PostgreSQL 16 confirmed that deleting a restaurant cascades cleanly past the accounts' branch foreign key. Production's PostgreSQL version is unknown.
- Real concurrency (two administrators at once) on either side.
- Arabic wording: strings exist in both languages and are checked for presence, but **my Arabic is a proposal the owner has not read**.
- Stage 2 (account on a payment or refund, the cashier override, transfers, movements) is not built, so none of its criteria are tested.
