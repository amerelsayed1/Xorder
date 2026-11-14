# Changelog — finance-account-kind-per-method

## 2026-10-26 — built (uncommitted; POS on `feat/pos-optional-seats-and-floor-2026-10-26`, cloud on `feat/finance-accounts-and-platform-updates-2026-10-26`)
**POS**
- `domain/models/financial_account.dart`: `AccountRules.kindsFor(TenderKind)` and `fits(...)` (cash→cash, card→bank, wallet→wallet, account/voucher/other→any); `defaultProblem` takes the method's kind; new `AccountProblem.accountKindMismatch`.
- `data/postgres/postgres_financial_accounts_admin_repository.dart`: `setDefault` reads the method's kind and refuses a mismatch; clearing is always allowed; the seeder is untouched (it inserts the platform's rows without validating, verified).
- `features/admin/presentation/management_accounts_pane.dart`: only fitting accounts are offered per method; a saved mismatch is kept and marked ("Does not match this method", also in a cloud till's read-only line); a hint names the missing kind.
- Strings (en/ar): `refusalAccountKindMismatch`, `accountsNotMatching`, `accountsNoMatchingKind`; `admin_messages.dart` maps the new reason.
**Cloud**
- `app/Models/FinancialAccount.php`: `KINDS_FOR_TENDER` (cash→cash, card→bank, external→bank, other→any), `kindsForTender()`, `fitsTender()`.
- `SetTenderAccountDefaultRequest`: refuses a mismatch with `xorder.validation.account_kind_mismatch` (en/ar). **A request that used to succeed is now a 422** (the one contract change). No migration.
- Dashboard `FinancialAccountsPanel.vue` and `packages/ui/src/i18n/index.js`: the same filter, marker and hint.
**Tests**
- POS: new `test/domain/account_kind_rules_test.dart`; extended `test/features/management_accounts_pane_test.dart` (+5) and `test/data/financial_accounts_test.dart` (+2, PostgreSQL); `test/domain/financial_accounts_test.dart` and the older pane/PostgreSQL cases that paired mismatched kinds were given a fitting account.
- Cloud: `Pos/FinancialAccountsTest` +4 (matrix, table, legacy mismatch kept, both languages); one older case given a second bank.

## 2026-10-26 — the platform gains a `wallet` payment-method kind (D-6)
- Owner: same behavior on both sides. Cloud: `StoreTenderTypeRequest` accepts `wallet` (`UpdateTenderTypeRequest` extends it); `FinancialAccount::KINDS_FOR_TENDER` gains `wallet => ['wallet']`; dashboard `PaymentMethodsView.vue`, `PosMoneyView.vue` and `FinancialAccountsPanel.vue` list and pair it; labels `E-wallet` / `محفظة إلكترونية` in `packages/ui/src/i18n/index.js`. POS: `PlatformTenderKind.wallet` → `TenderKind.wallet` (`tender_method.dart`).
- Tests: cloud `FinancialAccountsTest` 29 (matrix and table now include wallet; a wallet method can be created and pairs with a wallet account; an unknown kind is still refused); POS `account_kind_rules_test` (platform table), `cloud_bootstrap_test` (a wallet kind parses and maps to the till's wallet), `branch_sales_api_test` (a wallet payment reads back as a wallet).
- Rollout: cloud first, POS after (`API.md`). Not run: the POS PostgreSQL seeder test for a wallet method; not viewed: the dashboard form.
