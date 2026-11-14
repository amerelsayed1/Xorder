# Branch order number — test report
Date 2026-10-28 · Environment: macOS, local PostgreSQL 16 at 127.0.0.1:5432 (the fixture's own per-checkout test database, dropped by `scripts/check.sh` at the end of each run; none left), Flutter 3.47.7 · Tree: `xorder-pos` `c67c754` + uncommitted changes (this work, plus one unrelated test file `test/data/local_bootstrap_test.dart`). **Nothing was run against a real till database, and migration 63 was not applied to any real database.**

## Commands and real results
| Command | Result |
|---|---|
| `flutter analyze` (inside every `scripts/check.sh`) | No issues found |
| `scripts/check.sh` unit phase (all non-PostgreSQL tests), final tree | **3536 passed, 2 skipped, 0 failed** (run 3) |
| `flutter test test/data/day_order_number_test.dart --concurrency=1` (PostgreSQL) | 15 passed |
| `flutter test test/data/till_grants_enforced_test.dart test/data/customers_repository_test.dart --concurrency=1` | 35 passed |
| `flutter test test/data/pos_users_rename_test.dart --concurrency=1` | 2 passed (after the fix below) |
| `flutter test test/data/grants_cover_usage_test.dart test/data/till_grants_test.dart` | 26 passed |
| `flutter test test/features/receipt_document_test.dart test/features/order_history_test.dart` | all passed |
| Mutation check: grant on `pos_order_day_counters` removed from `local_bootstrap.dart` | the new `till_grants_enforced` case failed with `42501 permission denied for table pos_order_day_counters`; file restored |
| `scripts/check.sh test/data` on a **fresh** database, final tree (run 6) | 712 passed, **507 failed**, 1 skipped |
| Same command on an untouched checkout of `c67c754` in a separate worktree (baseline) | 695 passed, **507 failed** |
| Failing-test names, final tree vs baseline | **identical sets: no new failure, none fixed** |

## What this proves
AC-1 to AC-7 and AC-9 against a real PostgreSQL (`day_order_number_test.dart`, including 12 concurrent inserts from two terminals and the repository paths for sale, replay and void); the grant for the trigger as the till role (`till_grants_enforced_test.dart`, mutation-checked); the trigger order; AC-8 for receipt (en, ar, absent, reprint) and for the history list, "—" and the opened order (`receipt_document_test.dart`, `order_history_test.dart`).

## Found and fixed along the way
1. `test/data/grants_cover_usage_test.dart` read a trigger name in a comment of mine as a table: comment reworded.
2. `test/data/pos_users_rename_test.dart` pinned "migrating applies exactly [62]"; it failed once migration 63 existed. Now expects 62 and every later migration.
3. My new `till_grants_enforced` case left a business day and orders in the shared database, which made `customers_repository_test` and `supplier_invoices_schema_test` fail (64 tests) in a full fresh run; it now cleans up. `day_order_number_test.dart` touches only its own restaurant and removes it afterwards.

## Not proven / gaps (stated, not hidden)
- **The 507 failures on a fresh database are pre-existing** (QA XORD-029): identical set on untouched `c67c754`. They were not fixed. Because of them the *full* PostgreSQL phase of `scripts/check.sh` is red at the baseline, so "all green" cannot be claimed; only "no new failure" can. A first full run on a pre-existing (warm) database had passed all but one test (the grants-cover one, fixed afterwards); `check.sh` drops that database at the end, so that condition cannot be recreated. The full run (all directories, not only `test/data`) was last done in run 3, before fixes 2 and 3; after them only `test/data` was re-run.
- AC-10: the cloud payload is unchanged and **no new test pins it**.
- Cloud-mode branches with several tills: not covered, by decision. No test of a real two-till branch server on separate machines.
- Not seen by a person: printed receipt on paper (Arabic label «رقم الطلب اليومي», digits), sale screen after payment, history column at narrow widths and in RTL.
- PostgreSQL behaviour on a large live `pos_orders` (lock time, trigger cost) reviewed by reading only.
