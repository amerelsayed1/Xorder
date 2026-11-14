# XORD-015 — "Add accounts" (bank, cash, wallet) is missing because financial accounts do not exist anywhere

Status: investigated · 2026-10-26 · Confidence: **confirmed** (absence, by search of both repos and both schemas); the *design* choices in section 6 are open · Verified against: `xorder-pos` a6f5fe5 and `xorder-cloud` 06bc8e3, **both working trees dirty** (POS 123 modified files, cloud many); the findings below were read from the working trees, not from the commits.

## 1. Symptom
Reported by the owner as "Still miss add accounts", clarified as: *Bank Accounts for example, Cash, Wallet, anything.* In Back Office (till) and on the cloud dashboard there is no place to add a money account (cash, bank, e-wallet) and no way to say which account a payment method pays into.

Expected (XORD-015, `docs/qa/XORDER_QA_FINDINGS.md:398`): Back Office manages financial destination accounts; each active payment method has a default destination account; each captured payment is recorded against it. Actual: nothing of the kind exists. "Still" matches the tracker: XORD-015 is "Not started; not investigated" (`XORDER_QA_FINDINGS.md:805`), and the XORD-022 navigation work deliberately did not build it (see 3c).

## 2. How it was reproduced
Not a runtime bug, so there is nothing to run. Absence was shown by search (the shell output is quoted from this session):

- `grep -rIli "financial_account|FinancialAccount|financialAccount|bank_account|BankAccount|ewallet|e_wallet|settlement_account"` over cloud `app/ database/ routes/ tests/`, web `src/`, and POS `lib/ test/ assets/` returned **no files**.
- Cloud migrations matching `payment|tender|treasury|settle|account|ledger`: only `create_order_payments_table`, `create_stock_ledger_tables` (stock, not money), `create_supplier_payments_tables`. No account table.
- No automated test was run; none exists for this.

## 3. Root cause
There is no financial-account concept in the product, in the data model, the API or either UI. It is a missing feature, not a regression. The pieces that look related are not accounts:

a. **Payment methods carry no destination.**
   - POS `pos_tender_types` (`xorder-pos/lib/data/postgres/migrations.dart:2188`): `code, name, kind (cash|card|wallet|account|voucher|other), requires_reference, opens_drawer, counts_as_cash, refund_allowed, is_active, sort_order`. No account column.
   - Cloud `tender_types` (`2026_09_02_000400_create_pos_money_config_tables.php:48`): `name, kind, is_active, sort_order`; `StoreTenderTypeRequest` allows `kind` in `cash,card,external,other`. No account column.
   - The tender `kind` is a classification (ETA code, cash-up treatment), not a place the money goes. A "wallet" tender is not an account.
b. **Payments record no destination.** POS `pos_order_payments` (`migrations.dart:100`) has `order_id, tender_type_id, label, amount_minor, reference, occurred_at`. Cloud `order_payments` (`2026_09_02_000700_create_order_payments_table.php`) has `tender_type_id, amount_minor, currency, ...`. Neither has an account or a movement row.
c. **The existing "treasury"/settlement screens are cash-drawer only, by an earlier decision.**
   - `management_settlements_pane.dart` states that Settlements is "a cash reconciliation, not the bank and wallet settlements Finance cut for having no accounting model to read them from".
   - `FinanceDrawersPane` (`management_finance_panes.dart:1300`) lists *open shifts'* expected cash. It is derived from shifts, not from an account you can add.
   - `docs/features/back-office-navigation/NAVIGATION_INVENTORY.md:94`: "**Financial Accounts: no pane** (XORD-015, not built)", and the XORD-022 notes say not to build a pane to fill a menu.
d. **`pos_cash_drawers` is a dead table.** It exists (`migrations.dart:1440`, with grants in `local_bootstrap.dart`) but nothing under `lib/` or `test/` reads or writes it (0 references outside migrations and grants). It is the nearest thing to a "cash account" and it has no UI or code.

Contributing condition: the two stacks disagree on tender kinds (POS has `wallet`, `account`, `voucher`; cloud has `external` and no `wallet`), so even the classification a wallet account would hang off is not the same on the two sides.

## 4. Evidence and alternatives ruled out
- "It exists under another name": searched `treasury`, `settlement`, `drawer`, `ledger`, `bank`, `wallet`. Only drawer/shift cash, supplier payments (money out to suppliers) and the stock ledger exist.
- "It is a permissions or visibility bug": the navigation inventory and the settlements docstring both state the pane was never built; there is no route, controller or Vue view to hide.
- "It is staff accounts or customer accounts": the owner named bank, cash and wallet.
- Not checked: any live POS or production database (not allowed and not needed to show absence).

## 5. Impact
- **Money integrity:** no per-account balance, no reconciliation of card and wallet takings, no proof of where a captured payment went; refunds cannot be traced to a source account. This is the finding's own P1 "Financial integrity".
- **Venue models:** cafés (cash plus card terminal plus wallet at the counter) and food trucks (cash plus mobile wallet, often one phone number) feel it daily; cloud kitchens (payouts from delivery aggregators, which are themselves a known gap in the domain handbook) cannot reconcile at all; restaurants lose bank-versus-drawer separation on split bills.
- **Data already wrong:** none, nothing was ever posted to an account. Historical payments cannot later be attributed to an account without a decision on backfill (section 9).
- **Security/tenancy:** none today. The new feature adds a tenant boundary (account belongs to a restaurant and optionally a branch), so it goes through `/security-audit`.

## 6. Fix options (narrowest first)
1. **Accounts + default mapping only (recommended first slice).** New `financial_accounts` (restaurant, optional branch, `kind` cash|bank|wallet, name, currency, `is_active`, optional external reference such as last four digits of an account number; no credentials) and a nullable `financial_account_id` on `tender_types`/`pos_tender_types`. Back Office pane "Finance › Accounts" (add, rename, disable) plus an account selector in the payment-method editor on cloud (`PaymentMethodsView.vue`) and on an offline till (`tender_type_dialog.dart`). On cloud the platform is the author and the bootstrap bundle carries accounts to the till, as it already does for tenders (see the `ManagementTendersPane` docstring). Nothing is posted yet. Trade-off: the screen answers "add accounts" but no movements exist, so reports do not change.
2. **Option 1 plus immutable movements.** An append-only `financial_movements` row per captured tender (order, payment, tender, account snapshot, amount, currency, staff, time), idempotent on the payment's `client_transaction_id`; refunds post compensating rows. Matches the XORD-015 acceptance criteria but touches payment capture and sync, so it is a payment-state change needing approval.
3. **Full ledger / double-entry.** Out of scope until the owner decides operational destination versus formal ledger (finding line 410).

Must NOT change: money in minor units; the backend stays authoritative for totals; the existing `tender_types` API response shape (add the new field additively); historical `order_payments` rows; the unique `(restaurant_id, client_transaction_id)` dedupe key. A disabled account cannot receive new payments; changing a default never rewrites earlier movements.

## 7. Tests the fix needs
- Cloud (SQLite): feature tests for account CRUD with tenant isolation (restaurant A cannot read or map restaurant B's account), a disabled account cannot be mapped, mapping appears in the POS bootstrap bundle, and the cloud/POS `kind` vocabulary agreement. Option 2: a payment posts exactly one movement, a retry posts none, a split posts one per tender, a refund posts a compensating row. These cannot prove PostgreSQL locking or constraint behaviour.
- POS: widget test for the Accounts pane and the tender dialog selector in EN/AR; repository tests in the `integration` tag (need `POS_PG_HOST`) for the migration and the payment write.
- Existing suites to run: `PosBootstrap*`, tender-type controller tests, `receipt_profile_ui_test`/`back_office_shell_test` (the Finance tab changes), `flutter analyze`.

## 8. Approvals the fix needs
- Cloud and POS migrations (additive, nullable). Not applied to any real database by Claude; the cloud one ships to production via `migrate --force` on a push to `main`, so `/release-check` and the owner's push.
- Option 2 only: payment/order-state change and a bootstrap contract change. Rollout order to be written down first: cloud deploys the additive field before the till reads it; the till tolerates the field being absent.

## 9. Open questions and what could not be verified
1. Which first slice does the owner want: option 1 only, or 1+2? (Recommendation: 1, then 2.)
2. Is an account per **restaurant** or per **branch**? A food truck has one; a chain has several. (Recommendation: restaurant-level with an optional branch.)
3. Can a cashier override the destination at payment time? (Finding says: Back Office default, override only with an elevated permission and audit log; owner has not confirmed.)
4. Does a formal general ledger exist anywhere? Not found in code; confirm with the owner.
5. Should existing payments be backfilled to a default account, or start from the go-live date? (Recommendation: start from the go-live date, never rewrite history.)
6. Cloud versus POS tender `kind` mismatch (`external` versus `wallet`/`account`/`voucher`): is it intended? UNVERIFIED which side wins.
7. Unrelated dirty files in both working trees were not inspected; the conclusions rely on grep over the working trees.

Route to `/security-audit` when implemented (tenant isolation, money integrity). Next step: `/develop-feature` to write the description from the answers to 1 to 5, then `/implement XORD-015`.
