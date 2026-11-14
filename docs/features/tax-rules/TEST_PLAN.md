# Test plan

Verified against: xorder-pos `a6f5fe5` (+ uncommitted work), xorder-cloud `06bc8e3` (+ uncommitted work, none in tax files) · Updated 2026-10-26

## Test environments
POS: `flutter test` (no database; PostgreSQL-tagged suites self-skip). PostgreSQL suites: `POS_PG_HOST/PORT/USER/PASSWORD`, `--tags integration --concurrency=1`, local throwaway database. Cloud: PHPUnit on SQLite (not run for this change).

## Unit tests
| Criterion | Test |
|---|---|
| BR-2 (group beats `vatBp`) | `test/features/tax_groups_wiring_test.dart` › "what a ticket is taxed at" (3 tests) |
| tax maths, rounding per rate | `test/domain/tax_lines_test.dart`, `test/domain/tax_mode_test.dart`, `test/domain/ticket_totals_golden_test.dart` (existing, unchanged) |

## Integration and API tests
| Criterion | Test (PostgreSQL) |
|---|---|
| AC-1, AC-2, BR-3 | `test/data/postgres_catalog_admin_test.dart` › money rules: "setting VAT to 0 reaches the rate the ticket charges (XORD-027)", "any other rate moves the default group with it", "only the default group moves; the other named rates stay", "with no default group it still saves, as before" |
| over 100% | same › "a rate over 100% is refused with a message, not a constraint error" |
| AC-5 | same › "the audit event records the group rate before and after" |
| existing | "what is saved is what the ticket then prices with", "a manager without settings.manage cannot change the rates" |
Cloud: `tests/Feature/Pos/PosOrdersTest.php:94` (existing). **Gap:** no cloud test for an inclusive rule or the `money` block shape.

## Flutter/Vue UI tests
| Criterion | Test |
|---|---|
| AC-3, BR-4 | `test/features/money_panes_ownership_test.dart` › "the VAT box shows the rate the till charges…", "with no default group the box shows the single rate, as before" |
| AC-6 | same › "typing 0 over a 14% group saves 0 and re-reads the groups" |
| AC-4 | `test/features/cart_totals_alignment_test.dart` › "the VAT row names the rate actually applied (XORD-027)" (3) |
| existing | "saving a rate does not reset tax-inclusive mode" |
Vue: no JavaScript test framework; the dashboard rule screen is untested.

## Security and tenancy
Permission refusal covered by the existing PostgreSQL test (settings.manage). The UPDATE is scoped by `restaurant_id` (code reading; no cross-tenant test: the suite has one restaurant per run).

## Order/pricing/payment invariants
Total = net + service + VAT (exclusive) or net + service (inclusive): `tax_mode_test`. Golden totals unchanged.

## Regression and manual QA
Manual (needs a person, not done): offline till, set VAT 0 in Management › Taxes, ring a dine-in sale, check the cart row, the receipt and the order's saved totals; repeat with 15 and 12.5; reopen the pane. A till whose box and group disagree.

## Test data/fixtures
`pg_fixture.dart` shared database; groups inserted directly; `fakeRepositoryOverrides()` for widget tests.
