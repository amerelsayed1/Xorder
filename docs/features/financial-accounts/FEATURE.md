# Financial accounts — financial-accounts (XORD-015)

Status: **stage 1 implemented 2026-10-26 (not committed, not deployed); stage 2 not started** · Source: the owner's request, "Still miss add accounts … Bank Accounts for example, Cash, Wallet anything" (2026-10-26), and `XORD-015` in `docs/qa/XORDER_QA_FINDINGS.md:398` · Verified against: xorder-cloud 06bc8e3, xorder-pos a6f5fe5 — **both working trees have uncommitted changes**. Root cause of the gap: `docs/harness/investigations/XORD-015-financial-accounts-missing.md`.

## 1. Summary
Let a business add the places its money lives — cash, bank accounts, e-wallets — each optionally tied to one branch. Every payment method points to a default account. In a second stage, each payment records which account received it (the cashier may choose a different one), and an admin can move money between accounts. Today none of this exists.

## 2. Why
The owner cannot find where to add accounts, and the product cannot say where a card, wallet or cash payment went. Hurts: **cafés** (cash, card terminal and wallet at one counter), **food trucks** (cash plus a mobile wallet, one account for the whole truck), **restaurants** (bank versus drawer on split bills), **cloud kitchens** (payouts arrive in a bank/wallet account, with no way to reconcile them; delivery-app integration is a known gap, so the matching stays manual).

## 3. Goal and success
- Stage 1: an authorized person adds, renames and disables accounts, links one to a branch, and sets each payment method's default account, on the cloud dashboard and on an offline till. Every active payment method either has a valid default or is plainly shown as "no account".
- Stage 2: for any payment taken after go-live, the account that received it is recorded and cannot be edited afterwards; an account's balance can be explained from its movements; an admin can transfer between accounts and each transfer is traceable.
- Success is shown by the acceptance criteria in section 8. No past payment changes.

## 4. Users, roles and permissions
| Who | May |
|---|---|
| Owner / authorized manager (Back Office) | Add, rename, disable accounts; set defaults; (stage 2) transfer between accounts |
| Cashier | (stage 2) choose a different active account at payment time **only with a specific permission** |
| Anyone else | Nothing; see no account figures unless they already have `reports.view` |

Existing identifiers: POS `settings.manage`, `reports.view`, `order.refund`, `cash.movement`, `admin.enter` (`xorder-pos/lib/domain/models/permissions.dart:61,134,83,97,164`); cloud `settings.view` / `settings.update` guard payment methods today (`routes/api.php:684-705`, router `meta.capability`, `router/index.js:185,189`). **New identifiers are proposed, not existing** (names are suggestions): one to manage accounts, one to override the account at payment time, one to transfer. Whether manage rides on `settings.manage`/`settings.update` or gets its own key is open (13). Adding a permission that narrows or widens access needs approval.

## 5. Today
- **No financial-account concept anywhere** (grep of cloud `app/ database/ routes/ tests/`, web `src/`, POS `lib/ test/ assets/` found nothing; see the investigation report).
- Payment methods: POS `pos_tender_types` (`xorder-pos/lib/data/postgres/migrations.dart:2188`, kinds cash/card/wallet/account/voucher/other); cloud `tender_types` (`2026_09_02_000400_create_pos_money_config_tables.php:48`, kinds cash/card/external/other; `StoreTenderTypeRequest.php:19`). **Neither has an account column.**
- Payments: POS `pos_order_payments` (`migrations.dart:100`), refunds `pos_refund_payments` (`migrations.dart:1213`), cloud `order_payments` (`2026_09_02_000700_create_order_payments_table.php`), `pos_refunds` tables. None records a destination.
- Authoring rule for payment methods: on a **cloud till the platform authors them** and the till seeds them from the bundle `money.tender_types` (`PosBootstrapService.php:130`, `bootstrap_seeder.dart:81`, `BACKOFFICE_TO_CLOUD.md:53`); on an **offline till they are authored on the till** (`management_tenders_pane.dart` docstring). The same split is the pattern for accounts.
- Finance screens: `FinanceDrawersPane` (`management_finance_panes.dart:1300`) is derived from open shifts; Settlements is a cash-up only and says bank/wallet settlements were left out for want of an accounting model (`management_settlements_pane.dart` docstring); the navigation plan lists "Financial Accounts: no pane" (`NAVIGATION_INVENTORY.md:94`).
- `pos_cash_drawers` (`migrations.dart:1440`) exists with grants but nothing in `lib/` or `test/` uses it. **UNVERIFIED** whether anything outside this repo (a seeder, a script) writes it.
- Money outflows already have their own method vocabulary: `SupplierPaymentMethod` (cash, bank_transfer, cheque, card, other) — "deliberately not the POS tender types" (`Enums/SupplierPaymentMethod.php`).
- Payments are idempotent by `client_transaction_id` unique per restaurant (`create_order_payments_table.php`; `StoreOrderPaymentRequest.php:18`). Contract: POS-BE-013 (money config) and POS-BE-009/010 are `READY` in `docs/coordination/BACKEND_TO_POS.md`; the cloud and POS copies of that file **differ** (`diff -q`), not compared line by line — **UNVERIFIED** which is current.

## 6. Scope
**In — stage 1**
- Accounts of kind cash, bank, wallet: name, kind, currency, active flag, optional branch, optional reference label (for example the last four digits; no credentials, no full account numbers).
- Add, rename, disable (never delete once used) on the cloud dashboard and on an offline till.
- Default account on each payment method; shown in the payment-method editor and list.
- Delivery to the till inside the existing bootstrap bundle, additive.
- Arabic and English labels.

**In — stage 2** (needs approval; see 10)
- Each new payment and refund records the account it went to / came from.
- Cashier override of the account at payment time, with a specific permission, audited.
- Admin transfer between two active accounts, recorded as a pair of movements.
- Append-only movements and a balance per account derived from them.

**Out**
- Rewriting or attributing any payment taken before go-live (owner decision).
- Card-terminal integration, delivery-app payouts, tips, double-entry accounting or a general ledger, tax filing.
- Supplier payments and expenses choosing a source account (listed as a follow-up; open question 9).
- Bank sync or reconciliation against a statement.
- Any change to existing totals, tax, rounding, cash-up (Z report) or the `counts_as_cash` rule.

## 7. Behavior and business rules
- BR-1 An account belongs to a restaurant; it may be tied to **one** branch or be shared (no branch). Tenant isolation applies to every read and write.
- BR-2 An account has a kind (cash, bank, wallet) and a currency; it can only receive payments in its own currency. The currency matches the restaurant's currency unless the owner decides otherwise (13).
- BR-3 A payment method has at most one default account. A default must be active, in the same restaurant, and either shared or tied to the branch that takes the payment.
- BR-4 A disabled account cannot be chosen as a default, cannot receive new payments or transfers, and cannot be deleted once any movement or default references it.
- BR-5 Changing a default or disabling an account never changes an earlier payment or movement.
- BR-6 (stage 2) Each payment/refund line stores the account id **and its name and kind at that moment**, as the till already snapshots `counts_as_cash` onto a payment.
- BR-7 (stage 2) A cashier may pick another active account only with the override permission; the original default and the chosen account are both recorded with who and when.
- BR-8 (stage 2) A refund posts a compensating movement to the **same account the original payment went to** (proposed; see 13), never a negative payment.
- BR-9 (stage 2) A transfer moves an amount between two active accounts of the same currency, needs a reason, names the actor, and is two linked movements created in one transaction; it cannot be edited or deleted, only reversed by a new transfer.
- BR-10 (stage 2) Movements are idempotent: the same payment or transfer id never posts twice.
- BR-11 The backend stays authoritative for money. Amounts are integer minor units. The till writes locally to keep selling offline and the cloud validates on receipt.
- BR-12 On a cloud-connected till, accounts and defaults are authored on the platform and the till cannot create its own (same rule as payment methods). On an offline / on-premise till they are authored on the till, belong to that location, and never reach the cloud (owner decision 2026-10-26). **As built:** an account is *shared* by default, and the choice to tie it to a branch is offered only when the business has more than one branch (or the account is already tied to one). On a single-location business every account already belongs to that location; a branch-tied account there could never be chosen as a default.
- BR-13 Existing behavior is preserved: a payment method with **no** default account keeps working exactly as today.

## 8. Acceptance criteria
| ID | Given / When / Then | Proof |
|---|---|---|
| AC-1 | Given a signed-in owner, when they add a bank account "CIB" (EGP) with no branch, then it appears in the accounts list, cloud and offline till alike. | Cloud feature test; POS widget + repository test |
| AC-2 | Given an account tied to branch B1, when a user of branch B2's till lists payment-method choices, then B1's account is not offered. | Cloud + POS tests |
| AC-3 | Given restaurant A, when it reads or edits restaurant B's account by id, then it gets 404/403 and nothing changes. | Cloud tenant-isolation test |
| AC-4 | Given a payment method "Card", when the owner sets a default account, then it is saved and shown (**on the Accounts tab / pane, not in the payment-method list**), and a method with no default shows "no account" and still takes payments. | Cloud + POS tests |
| AC-5 | Given a disabled account, when it is set as a default or chosen for a payment/transfer, then it is refused with a clear message. | Cloud + POS tests |
| AC-6 | Given a cloud-connected till, when its user opens the accounts pane, then it lists the platform's accounts and has no add/edit control, with the notice the payment-method pane uses. | POS widget test |
| AC-7 | Given an offline till, when the owner adds an account, then it is stored locally (shared by the location; tied to a branch only when there are several) and nothing is sent to the cloud. | POS repository test (needs `POS_PG_HOST`) |
| AC-8 | Given the bootstrap bundle from an older cloud with no accounts, when the till seeds, then it works and shows no accounts. Given a newer bundle on an older till, unknown fields are ignored. | POS bundle test; cloud bundle test |
| AC-9 | Given any earlier payment, when accounts or defaults change, then that payment's stored values and old reports are unchanged. | Regression test over stored rows |
| AC-10 (stage 2) | Given a card payment on a method with a default, when it is captured, then one movement exists for that account and amount; a retry with the same `client_transaction_id` adds none. | Cloud + POS tests |
| AC-11 (stage 2) | Given a split payment of 300 cash + 200 card, when captured, then two movements post, one per tender, each to its method's account. | Cloud + POS tests |
| AC-12 (stage 2) | Given a cashier without the override permission, when they try another account, then it is refused; with the permission it succeeds and both default and chosen accounts are audited. | Permission test |
| AC-13 (stage 2) | Given a refund of a card payment, when it is posted, then a compensating movement lands on the original account and the original movement is untouched. | Cloud + POS tests |
| AC-14 (stage 2) | Given an admin and two active accounts with the same currency, when they transfer 100, then the balances move by 100 in opposite directions in one transaction; a failure leaves both unchanged; a repeat with the same id posts once. | Cloud + POS tests |
| AC-15 | Given Arabic UI, when the accounts pane and payment-method editor are opened, then labels are Arabic, the layout is RTL, and Arabic-Indic digits display consistently with the rest of Finance. | Widget tests; **a person must look** |

## 9. Edge cases and failure modes
- **Offline / retry:** a payment captured offline posts its movement when the existing outbox drains; the same id never posts twice (BR-10). An account disabled on the cloud while a till is offline: the till's later payment to it is **accepted and flagged**, not dropped (the till must never stop selling); how it is flagged is open (13).
- **Food truck / cloud kitchen:** one shared account, no branch, must be enough; no table or address is assumed anywhere.
- **Concurrency:** two tills paying to the same account at once; the balance is derived from rows, so no read-modify-write counter.
- **Tenant boundary:** account ids from another restaurant or branch are rejected on every endpoint, including defaults and transfers.
- **Currency:** a restaurant that changes currency after accounts exist (open question 13).
- **Plan and licence limits:** none found for accounts today; whether a plan should cap them is **UNVERIFIED** (13).
- **Empty / large data:** no accounts at all is the normal start; a long movement history must paginate.
- **Mixed vocabulary:** cloud kind `external` has no till equivalent beyond `other`. ~~Accounts do not depend on tender kind.~~ **Superseded 2026-10-26 by the owner** (`docs/features/finance-account-kind-per-method/`): a payment method only offers, and only accepts as its default, accounts of its own kind — cash→cash, card and external→bank, wallet→wallet (offline till only), other kinds any.
- **Arabic:** names may be Arabic or English; names are unique per restaurant after trimming.

## 10. Impact
- **Apps:** cloud API (`Dashboard\…Controller`, requests, model, migration, bootstrap), cloud web (`PaymentMethodsView.vue` selector; new Accounts page), POS (Finance › Accounts pane, `tender_type_dialog.dart` selector, seeder/bundle, migration).
- **Contract:** additive field `financial_accounts` and `financial_account_id` inside `money` in the bundle (POS-BE-013 area). Only `READY` items are integrated; a new contract item is to be written in `docs/coordination/` of both repos. Older tills must ignore the new fields.
- **Data / migrations:** new account table; nullable default-account column on tender types (cloud and POS). Stage 2 adds an account reference on payments/refund payments and a movements table. All additive; **no real-database migration is run without approval.** Cloud tests run on SQLite and cannot prove PostgreSQL locks or constraints; those are reviewed by reading.
- **Permissions:** new capabilities (4) change roles; existing roles gain nothing unless granted.
- **Localization:** new `AppStrings` getters in EN/AR on the till; `vue-i18n` keys on the dashboard.
- **Docs:** `FEATURE_INVENTORY.md` row, `tender-types` and `pos-shifts` feature docs, contract ledger, QA tracker XORD-015 status.
- **Deploy order:** cloud first (additive columns and bundle field), then the POS release; the till must tolerate the field being absent. Stage 2 repeats this. A push to `xorder-cloud` `main` migrates production: not done by Claude, only after `/release-check`.

## 11. Dependencies, known gaps, risks
- Depends on: tender types (POS-BE-013), shifts and cash movements (POS-BE-009), refunds (POS-BE-010), the outbox drain, role/permission mapping (XORD-011, `tenant-roles`), back-office navigation (XORD-022 / "Finance › Financial Accounts").
- Leans on known gaps: **aggregator payouts** (cloud kitchens) and **card terminals** — accounts record where money went, not whether a processor settled it. No dependency on tips, loyalty, recipes or KDS.
- Risks: stage 2 changes payment capture and sync (payment-state change, needs approval); a cashier override widens a fraud surface that "a card-for-cash swap" already uses (`permissions.dart:88`), so it is audited and permission-gated; cloud and POS copies of the contract file already differ.

## 12. How it will be tested
- Cloud (SQLite): PHPUnit feature tests for AC-1…AC-5, AC-8, AC-9 and stage 2 AC-10…AC-14, including a two-restaurant isolation test.
- POS: widget tests for AC-6, AC-15 and the dialog selector; `integration`-tagged PostgreSQL tests for AC-7 and the payment write (need `POS_PG_HOST`; they have not run unless the report says so).
- Existing suites to keep green: `PosBootstrap*`, tender-type controller tests, refund and shift tests, `back_office_shell_test`, `flutter analyze`.
- Needs a person: Arabic wording and RTL layout (AC-15); stage 2 behaviour on a real till against a real cloud.

## 13. Decisions and open questions
**Decided (2026-10-26, by the owner in chat)**
1. Version 1 = accounts plus a default account per payment method.
2. An account is tied to the restaurant and may optionally be tied to a branch.
3. A cashier **can** pay into a different account than the default, and an admin **can** transfer between accounts. The owner's wording was unconditional; the permission gate on the cashier override is Claude's recommendation (see below).
4. Accounts start from go-live; no backfill or attribution of past payments.
5. Built as one feature in two stages (stage 1 accounts and defaults; stage 2 movements, override, transfers).
6. Offline / on-premise tills: accounts are local to that location, never sent to the cloud.

**Decided during implementation (2026-10-26, owner, in chat)**
7. A payment method's default account is **per branch**, with a business-wide fallback (mapping table), because accounts can belong to a branch and payment methods do not. This replaces the single "at most one default" in BR-3: a method has at most one default **per (method, branch)**; a business-wide default must be a shared account.
8. Stage 1 approved for building. Stage 2 (account on each payment, cashier override, transfers, movements) is **not** approved.

**Implementation notes that change the text above:** the capability is `finance.accounts` (not `finance.manage`); the default-account chooser is in Finance › Accounts and the dashboard Accounts tab, not in the payment-method dialog; as built, stage 1 has no balances and no payment reads an account. See `TECHNICAL.md` "As built".

**Still open (Claude's recommendation first)**
1. Cashier override: require a specific permission and an audit entry (recommended), or allow for every cashier?
2. Refund account: same account as the original payment (recommended), or a chosen one?
3. Manage accounts under the existing settings permission, or a new `finance` permission? (new, recommended, because Finance is read-only today.)
4. Currency: restrict accounts to the restaurant's currency in v1 (recommended) or allow others?
5. Late payment to an account disabled meanwhile: accept and flag (recommended)?
6. Plan/licence cap on the number of accounts: none (recommended) or per plan?
7. Link a cash account to a physical drawer (`pos_cash_drawers`) now, or leave that table alone?
8. Do the cloud kind `external` and the till kinds `wallet`/`account`/`voucher` need aligning first? **UNVERIFIED** which side is intended.
9. Should supplier payments and expenses name a source account (follow-up, suggestion only)?
10. Does a formal general ledger exist outside this repo? Not found in code.
11. Which `BACKEND_TO_POS.md` is current (the two copies differ)?

**Next: `/implement financial-accounts`** — it will need approved: (a) additive cloud and POS migrations; (b) a bundle contract addition written in `docs/coordination/` first; (c) new permissions (a change to roles); (d) for stage 2, a payment-state change (movement on capture and refund, idempotency); (e) a push to `xorder-cloud` `main` is yours, after `/release-check`. Also update the XORD-015 entry in `docs/qa/XORDER_QA_FINDINGS.md` (still "Not started") when work begins; nothing is ticked until a test proves it.
