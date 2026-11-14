# Changelog: financial accounts (XORD-015)

## 2026-10-26 — stage 1 built (not committed, not deployed)
- **Cloud:** `financial_accounts` and `tender_account_defaults` tables; models `FinancialAccount`, `TenderAccountDefault`; `FinancialAccountController`, `TenderAccountDefaultController` and their requests; routes under the existing `feature:pos` group; capability `finance.accounts` (implies `settings.view`); both models hooked into `PosConfigVersion`; `money.financial_accounts` and `money.tender_account_defaults` added to the POS bootstrap bundle; validation messages in English and Arabic.
- **Dashboard:** the "Accounts" tab of Settings › Payment methods now lists, adds, edits and switches off accounts and picks where each payment method pays in (per branch when there is more than one). The "coming soon" placeholder and its strings are gone. Capability labels `Finance — Manage money accounts` (EN/AR).
- **POS:** migration 60 (two tables, owner gets `finance.accounts`); grants (till reads; cloud seeder writes; administrator authors; no `DELETE` on accounts); `BootstrapSeeder` seeds accounts and defaults; `PostgresFinancialAccountsRepository` (read) and `PostgresFinancialAccountsAdminRepository` (offline authoring, audited); `Finance › Accounts` pane (last in the Finance menu); `PosCapability.financeAccounts`; typed refusals `AccountRefused` and their wording in both languages.
- **Contract:** `POS-BE-032` added to `BACKEND_TO_POS.md` as **PROPOSED**.
- **Tests added:** cloud `FinancialAccountsTest` (24); POS `test/domain/financial_accounts_test` (17), `financial_accounts_bundle_test` (10), `test/data/financial_accounts_test` (PostgreSQL, 25), `management_accounts_pane_test` (15), plus grant probes in `till_grants_test`, `till_grants_enforced_test`, `admin_grants_enforced_test`. Existing lists updated: `grants_cover_usage_test`, `capability_labels_test`, `back_office_shell_test`, `settings_bar_test`.

### Differences from the plan (`TECHNICAL.md` section "As built")
1. Capability is `finance.accounts`, not `finance.manage`: `capaction.manage` already means "Manage suppliers, purchases & stock" in the role builder.
2. The default-account choice is in the Accounts pane, not in the payment-method dialog (that dialog already holds other uncommitted work).
3. `branch_key` replaces a partial unique index (the repo avoids engine-specific SQL).
4. The accounts repository reads its own branch list (`branches()`), not the shared branch provider (its fake raises a pending-timer failure in the pane-walking test).
5. A default now blocks switching its account off, and retying it to another branch.
6. After the independent review (see `TECHNICAL.md`): deleting a branch with an account is a 409; explicit nulls are 422; the account-number guard covers any script and the name; names are unique without regard to case; the cloud audit line for a default says what it did; the branch choice is offered only with more than one branch; the till dialog keeps typed input after a refusal; the Vue panel uses the shared `Modal`, theme colours and an RTL-safe toast and loads on first open.

### Not done
Stage 2 (account on a payment or refund, cashier override, transfers, movements, balances); account selector in the payment-method dialog; supplier payments and expenses choosing an account; the owner's map places Financial Accounts first in Finance (it is last, so no page moves); a browser check of the dashboard tab; an old-POS-build check.
