# Shared QR, client types the slip number: test report

## 2026-11-18
Branch `feat/guest-paging-slip-number`, uncommitted. Environment: local machine, PHPUnit on SQLite in-memory with throwaway `APP_KEY` and `JWT_SECRET`; no production access.

| Command | Result |
|---|---|
| `php artisan test tests/Feature/Pos/PagerLookupTest.php tests/Feature/PagerQrTest.php tests/Feature/MenuShellTest.php` | 30 passed |
| `php artisan test` (full suite) | **1337 passed**, 7187 assertions (1320 before this work) |
| `./vendor/bin/pint --test` | passed |
| `pnpm build` | menu, landing and web apps built |

| Criterion | Proven by |
|---|---|
| AC-1 the number at the end of the invoice finds the order (`1`, `01`, `000001`, the full number in any case) | `PagerLookupTest::test_the_number_at_the_end_of_the_invoice_number_finds_the_order`, `test_a_short_number_means_that_number_exactly` |
| AC-2 Arabic-Indic digits | `test_arabic_indic_digits_find_the_same_order` |
| AC-3 unknown number, another restaurant's order | `test_an_unknown_number_is_not_found_and_so_is_another_restaurants_order` |
| AC-4 outside the 12-hour window, a non-paged type | `test_only_recent_paged_orders_can_be_found` |
| AC-5, AC-7 a till order is made pageable once, the order-number page reads it, a repeat lookup changes nothing, an existing token is kept | `test_a_till_order_is_made_pageable_once_…`, `test_an_order_that_already_has_a_token_keeps_it` |
| AC-6 two branches with the same number | `test_two_branches_with_the_same_number_are_ambiguous_…` |
| AC-8 feature off, unknown restaurant | `test_it_is_not_available_without_the_feature_…` |
| AC-9 rate limit | `test_lookups_are_rate_limited_per_address` |
| Info call shape, validation | `test_the_info_call_…`, `test_a_missing_number_is_a_validation_error` |
| Dashboard QR: right restaurant only, feature and login required, PNG name, `noindex` on `/menu/p` | `PagerQrTest` (5 tests), `MenuShellTest::test_order_tracking_links_are_not_indexable_but_the_menu_is` |

**Checked in the browser pane against a local mock of the lookup endpoint (phone-sized window):** the number box in Arabic and right-to-left on an English phone; a wrong number; an ambiguous number (keyboard switches to full text, the full number then goes through); a sale that arrives late (the page kept looking by itself and moved to the order-number page on the third try); the correct number moving to the order-number page; the rate-limit message; the feature-off screen; and an unreachable server ("Reconnecting…", recovering by itself). No console errors other than the failures I simulated.

**Not verified:**
- **AC-12: the printed slip.** Whether a cloud-flavor till's slip shows the invoice number at the moment of sale (online and offline) has not been checked on a real till. This is the main open item.
- The Counter QR page in a browser (the dashboard needs the API and a login; only the build was checked).
- AC-10 and AC-11 on a real phone; PostgreSQL behavior and index use for the lookup query (the suite runs on SQLite).
There is no JavaScript test framework in the repo.
