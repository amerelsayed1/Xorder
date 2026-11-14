# Test plan: financial accounts (XORD-015)

Planned tests live here; executed results only in `TEST_REPORT.md`. Stage 1 is built; stage 2 rows are **planned, not written**.

## Test environments
- **Cloud API:** PHPUnit on SQLite `:memory:` (`cd apps/xorder-cloud/apps/api && php -d memory_limit=2G vendor/bin/phpunit`). `php artisan test` runs PHPUnit in a child process that ignores `-d memory_limit` and exhausts PHP's default 128 MB on this suite; call PHPUnit directly with a higher limit (same `phpunit.xml`). SQLite cannot prove PostgreSQL locks, indexes or constraints.
- **Dashboard (Vue):** `pnpm build` only. There is **no JS test framework** in the repo and none was added. The Accounts tab was **not opened in a running browser**.
- **POS unit/widget:** `flutter test` (integration-tagged suites self-skip without `POS_PG_HOST`).
- **POS PostgreSQL:** `POS_PG_HOST=127.0.0.1 … flutter test --tags integration --concurrency=1 <paths>` against the checkout's own database `xorder_pos_test_<checkout>`.

## Acceptance-criteria matrix (stage 1)
Criterion text is in `FEATURE.md` section 8. **Proof** names the test that was run; "partial" says what it does not cover.

| AC | Stage | Proving test(s) | Coverage |
| --- | --- | --- | --- |
| AC-1 add an account (cloud and offline) | 1 | cloud `FinancialAccountsTest::test_the_owner_adds_an_account_and_the_server_sets_the_currency`, `…tied_to_one_of_the_restaurants_branches`, `…renamed_retied_switched_off_and_back_on`; POS `financial_accounts_test` "the owner adds one…", `management_accounts_pane_test` "adds one through the dialog" | full |
| AC-2 a branch's account is not offered at another branch | 1 | cloud `…a_branch_default_can_use_that_branchs_own_account_but_a_business_wide_one_cannot`; POS `financial_accounts_test` "each rule is a refusal…", `financial_accounts_test.dart` (domain) "a branch's own account serves that branch and no other", pane test "with several branches, each can have its own" | **partial**: offered at the *default* choice; "a user listing payment-method choices at the till" is stage 2 |
| AC-3 tenant isolation | 1 | cloud `…another_restaurant_cannot_see_edit_or_disable_an_account`, `…another_restaurants_branch_is_refused`, `…defaults_never_cross_the_tenant_boundary`; POS "another restaurant's branch and accounts are not reachable" | full (cloud 404/422; POS refusal). Multi-restaurant on one till database is a belt, not a deployment |
| AC-4 default saved and shown; a method with none still takes payments | 1 | cloud `…a_business_wide_default_is_set_replaced_and_cleared_as_one_row`; pane tests "sets where a payment method pays in, and clears it" | **partial**: "still takes payments" holds because no payment code was touched, and the existing payment suites pass; no new payment test |
| AC-5 a disabled account cannot be a default | 1 | cloud `…a_disabled_account_cannot_be_a_default_and_a_default_cannot_be_disabled`; POS "each rule is a refusal…" and "an account that is a default cannot be switched off or retied" | full for defaults; "or a transfer" is stage 2 |
| AC-6 a cloud till lists and cannot add | 1 | `management_accounts_pane_test` group "a cloud till" (3) | full |
| AC-7 an offline till stores locally and sends nothing | 1 | `financial_accounts_test` "an offline till authors accounts" (6), including "nothing is queued for the cloud" (the `pos_outbox` count does not move) | full. Shared by default; tied to a branch only with more than one branch |
| AC-8 old/new bundles | 1 | `financial_accounts_bundle_test` (absent versus empty), `financial_accounts_test` "an older platform that sends no accounts leaves the till's alone" | new POS + old cloud: full. **Old POS + new cloud: argued by reading, not run on an old build** |
| AC-9 history is never rewritten | 1 | n/a in stage 1: no payment or report reads an account | not applicable until stage 2 |
| AC-15 Arabic and RTL | 1 | pane test "in Arabic the screen is worded, mirrored and lays out"; `localisation_test` (every string present in both languages); cloud `test_an_account_number_is_refused_in_any_script…` (Arabic names and digits) | layout and presence only. **Arabic wording and the dashboard layout need a person** |
| AC-10 … AC-14 | 2 | **not written** | stage 2 |

## Other tests that guard this change
Cloud: `TenantRbacTest`, `UserCreationMatrixTest`, `PosDefaultTendersTest`, `PosProvisioningTest` (iterate every capability or assert the bundle shape). POS: `capability_labels_test` (every capability and audit action has wording), `grants_cover_usage_test`, `till_grants_test`, `till_grants_enforced_test`, `admin_grants_enforced_test`, `back_office_shell_test`, `settings_bar_test`, `cloud_purchasing_hidden_test`, `money_panes_ownership_test`.

## Mutation checks (rule broken on purpose, test must fail)
1. The pane offers *Add* on a cloud till → `management_accounts_pane_test` "a cloud till is told these are the platform's…" fails.
2. Write routes gated by `settings.update` instead of `finance.accounts` → two `FinancialAccountsTest` tests fail.
3. A branch's own account allowed as the business-wide default → `…a_branch_default_can_use_that_branchs_own_account…` fails.
4. The account-number pattern reverted to ASCII digits only → `test_an_account_number_is_refused_in_any_script_and_in_the_name_too` fails.
5. The branch-delete guard removed → `test_a_branch_that_has_an_account_cannot_be_deleted_and_says_why` fails.

## Needs a person
Arabic wording (`app_strings.dart`, `packages/ui/src/i18n/index.js`), the dashboard Accounts tab in a browser (light/dark, narrow width, RTL), the Finance › Accounts pane on a real till, an offline-till session against a real branch server.
