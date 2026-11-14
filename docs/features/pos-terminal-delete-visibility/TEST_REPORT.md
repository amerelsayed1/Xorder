# Test report — XORD-042

Date: 2026-11-03/04 · Environment: local macOS, PHP CLI, SQLite `:memory:` (phpunit.xml) · Repo: xorder-cloud at `775bf0f` plus uncommitted work (this change and 36 unrelated files)

| Command | Result |
|---|---|
| `php artisan test --filter 'money_history\|flag_agrees\|flag_costs\|does_not_carry_the_flag'` | passed: 4 tests, 26 assertions |
| Mutation: order clause removed from `withMoneyHistory`, same filter | failed as expected: `Sold` reported `false` instead of `true`; file then restored (byte-compared) |
| `php artisan test --filter 'tenant_terminal_list_says'` | passed: 1 test, 4 assertions |
| `pnpm --filter @xorder/web build` | built; only the existing chunk-size warning |
| `php artisan test` (full) | did not run: PHP CLI memory limit of 128 MB exhausted while loading routes, in the child process |
| `php -d memory_limit=-1 vendor/bin/phpunit` (full) | 1191 tests, 1189 passed, 2 failed |
| `php -d memory_limit=-1 vendor/bin/phpunit tests/Feature/GuestPagingTest.php` | same 2 failures alone |

The 2 failures are `GuestPagingTest::test_ready_stamps_once_and_replay_is_a_no_op` (expects `2026-11-02T10:00:00+00:00`, got the current time) and `test_follow_and_ack_stamp_once_and_ack_needs_ready`. That file is untracked work from another feature, does not mention terminals, and fails on its own. Not caused by this change; not investigated.

After review fixes (wording, a code comment):

| Command | Result |
|---|---|
| `php artisan test --filter 'PosProvisioningTest\|TenantCreationTest'` | passed: 52 tests, 304 assertions |
| `pnpm --filter @xorder/web build` | built |

## Criteria
| AC | Proof |
|---|---|
| AC-1 dashboard list carries the flag | `PosProvisioningTest::test_the_terminal_list_says_which_terminals_have_money_history` |
| AC-1 admin list carries the flag | `TenantCreationTest::test_the_tenant_terminal_list_says_which_terminals_have_money_history` |
| AC-2 flag equals the delete rule | the two tests above (order, float, close, count, empty shift, none) and `test_the_flag_agrees_with_what_delete_answers` |
| AC-3 constant queries | `test_the_flag_costs_the_same_queries_for_one_terminal_or_many` |
| AC-4 other responses unchanged | `test_provisioning_response_does_not_carry_the_flag` |
| AC-5 pages hide Delete, show the note | not testable: no JS test framework; build passes; **not seen in a browser** |
| AC-6 refusal titled "Not deleted" | same; **not seen** |

## Not covered
- PostgreSQL: the `EXISTS … OR EXISTS …` select returns a boolean there and 0/1 on SQLite; the resource casts to bool. Read, not run, on PostgreSQL.
- Both pages in English and Arabic, light and dark: not viewed.
