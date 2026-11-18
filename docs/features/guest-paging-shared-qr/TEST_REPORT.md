# One shared QR for guest paging: test report

## Cloud half, 2026-11-18
Branch `feat/guest-paging-shared-qr-cloud`, uncommitted. Environment: local machine, PHPUnit on SQLite in-memory with throwaway `APP_KEY` and `JWT_SECRET`; no production access.

| Command | Result |
|---|---|
| `php artisan test tests/Feature/PagerSessionTest.php tests/Feature/Pos/PosPagerTest.php` | 21 passed, 284 assertions |
| `php artisan test` (full suite) | **1341 passed**, 7230 assertions (1320 before this work) |
| `./vendor/bin/pint --test` | passed (after `pint` fixed formatting in my new files and the import order in `routes/api.php`) |
| `php artisan route:list --path=pager` | the 3 new routes are registered |

| Criterion | Proven by |
|---|---|
| AC-1 session, code, secret once, only the hash stored | `PagerSessionTest::test_scanning_opens_a_session_…` |
| AC-2 code typed with the order pairs the phone; the order-number page reads it | `PosPagerTest::test_a_code_typed_with_the_order_pairs_the_phone_to_it` |
| AC-3 one order per code | `test_a_code_pairs_one_order_only` |
| AC-4 replay pairs once, code outside the idempotency hash | `test_a_replay_is_still_a_replay_and_pairs_once` |
| AC-5 a wrong or expired code never blocks the sale | `test_a_wrong_or_expired_code_never_blocks_the_sale` |
| AC-6 another restaurant's code is not found | `test_a_code_of_another_restaurant_is_not_found`, `test_one_restaurants_secret_means_nothing_to_another_restaurant` |
| AC-7 non-paged order types are refused | `test_an_order_that_is_not_paged_is_not_paired` |
| AC-9 scanning again returns the same code | `test_scanning_again_with_the_same_secret_…` |
| AC-10 different codes for different clients | `test_clients_get_different_codes` |
| AC-11 secret mismatch is a 404 | `test_a_session_is_readable_only_with_its_own_secret` |
| AC-12 Arabic-Indic digits (server half) | `test_arabic_indic_digits_in_the_order_are_read_as_the_same_code` |
| AC-14 rate limit | `test_starting_sessions_is_rate_limited_per_address` |
| AC-15 feature off | `test_it_is_not_available_…`, `test_nothing_pairs_when_the_restaurant_does_not_have_the_feature` |
| Regression: an order without a code, the bootstrap key | `test_an_order_without_a_code_has_no_pager_in_its_answer`, `test_the_bootstrap_says_whether_paging_is_on` |
| Prune only removes dead sessions | `test_the_prune_job_removes_only_dead_sessions` |

**Not built, so not tested:** AC-8 (ready alert on the phone), AC-13 (the join page in Arabic and English), AC-12's till half. These need the menu page and the POS.
**Not verified:** PostgreSQL behavior (the suite runs on SQLite; the migration was reviewed by reading); that `invoice_number` is the number printed on the slip; concurrency under a real rush (the code retries on a collision and binds under a row lock, but a load test was not run).
There is no JavaScript test framework in the repo; the POS has no tests for this yet.
