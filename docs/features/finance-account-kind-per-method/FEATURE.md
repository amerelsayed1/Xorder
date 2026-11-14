# A payment method only offers accounts of its own type — finance-account-kind-per-method

Status: proposed · 2026-10-26 · Source: the owner, 2026-10-26, with a screenshot of the Accounts page: "This wrong behavior every account should be have related type not appear related to all types" · Verified against: xorder-pos `a6f5fe5` + 148+ uncommitted files, xorder-cloud `06bc8e3` + 154 uncommitted files (neither is this feature's) · Amends XORD-015 (`docs/features/financial-accounts/`)

## 1. Summary
On the back office's Accounts page, "where each payment method is deposited" lists **every** account for **every** payment method, so Cash can be pointed at a bank and Card at a cash drawer. Each account has a type (cash, bank, wallet), so each payment method will offer only the accounts of its related type, and a mismatched pairing can no longer be saved.

## 2. Why
It is a way to make a mistake that looks valid: a card payment mapped to the till drawer, or cash to a bank, would mis-state where money is when stage 2 starts posting payments to accounts. Hurts every venue that sets up accounts; most visible in a restaurant with a drawer, a bank and wallets.

## 3. Goal and success
Choosing the account for a payment method shows only accounts that make sense for it, in the POS (offline) and the cloud dashboard, and neither can store a wrong pairing.

## 4. Users, roles and permissions
No new permission. Whoever may change defaults today (`finance.accounts` on the platform; the equivalent till capability offline, administrator on a till that authors its own accounts) keeps that and nothing more.

## 5. Today (verified in source)
| Fact | Where |
|---|---|
| Account kinds: `cash`, `bank`, `wallet`. | POS `lib/domain/models/financial_account.dart:13`; cloud `FinancialAccount::KINDS` (`app/Models/FinancialAccount.php:22`) |
| POS payment-method kinds: `cash, card, wallet, account, voucher, other`. | `lib/domain/models/tender_method.dart:20` |
| Cloud payment-method kinds: `cash, card, external, other` (no `wallet`). The till maps `external` to its `card` kind. | `StoreTenderTypeRequest.php:19`; `tender_method.dart:44-86` |
| The POS pane gives every method **all active accounts**: `_DefaultsRow(accounts: [for a in accounts if a.isActive])`. | `lib/features/admin/presentation/management_accounts_pane.dart:224-238` |
| The POS repository validates a default only on active, same restaurant and branch (`AccountRules.defaultProblem`); nothing on kind. | `postgres_financial_accounts_admin_repository.dart:283-290`, `financial_account.dart` (`AccountRules`) |
| The cloud request validates the same three things, not kind. | `SetTenderAccountDefaultRequest.php:55-77` |
| The cloud dashboard offers all accounts per method. | `apps/web/src/pages/dashboard/settings/FinancialAccountsPanel.vue:255-275` (the selects) |
| On a cloud-connected till accounts and defaults are authored on the platform and shown read-only. | `FEATURE.md` of `financial-accounts` BR-12; `accountsComeFromPlatform` |
| **The earlier spec says "accounts do not depend on tender kind".** This feature reverses that, by the owner. | `docs/features/financial-accounts/FEATURE.md:98` |
| No payment reads a default yet (stage 1 only). | XORD-015 |
| Tests that cover defaults today: cloud `FinancialAccountsTest`; POS `data/financial_accounts_test` (needs PostgreSQL). | `docs/qa/XORDER_QA_FINDINGS.md` XORD-015 |

## 6. Scope
**In:** the allowed-kind rule; the POS Accounts pane; the POS offline repository; the cloud API validation; the cloud dashboard select; a marker for an already-saved mismatch; localised messages; tests; docs.
**Out:** posting payments to accounts (stage 2); changing account kinds or payment-method kinds; creating a `wallet` kind on the platform; any change to existing saved data; the bootstrap bundle's shape.

## 7. Behavior and business rules
- **BR-1** The rule (decided 2026-10-26):

| Payment method kind | Offers accounts of kind |
|---|---|
| POS `cash` · cloud `cash` | `cash` |
| POS `card` · cloud `card` | `bank` |
| POS `wallet` · cloud `wallet` | `wallet` |
| cloud `external` (a card taken on the bank's own terminal; the till already reads it as `card`) | `bank` |
| POS `account`, `voucher`, `other` · cloud `other` | **every** active account, as today (no natural type) |

- **BR-2** Also "no account" stays a choice for every method (it clears the default).
- **BR-3** The rule is enforced where the default is **saved**: the POS repository and the cloud API refuse a mismatched account with a clear reason; hiding in the screen alone is not enough.
- **BR-4** A default already saved against the wrong type is **kept**, shown marked as not matching, and can be replaced only by a matching account or "no account". Nothing is deleted or changed silently.
- **BR-5** All existing rules stand: active, same restaurant, shared or the same branch (BR-3/BR-4 of `financial-accounts`); another restaurant's ids are refused; a disabled account is not offered.
- **BR-6** The rule is one table in each codebase (POS `AccountRules`, cloud `FinancialAccount`), kept in step by tests on both sides, like the existing rules. **Cloud and on-premise behave the same** (owner, 2026-10-26): the same pairing is offered and the same pairing is refused, whether the account is authored on the platform or on an offline till, and a cloud till shows the platform's defaults with the same filter and the same mismatch marker (read-only).
- **BR-7** The two sides may name kinds differently (`external` exists only on the platform and is read by the till as `card`), but they **behave the same**: cash→cash, card and external→bank, **wallet→wallet on both** (the platform gained a `wallet` payment-method kind, D-6).

## 8. Acceptance criteria
- **AC-1** Given a restaurant with a drawer (cash), a bank and a wallet account, when the POS pane shows Cash, Card and Wallet, then Cash offers the drawer only, Card the bank only, Wallet the wallet only. *POS widget test.*
- **AC-2** Given On account, Voucher or Other (POS) or Other (cloud), then every active account is offered. *POS widget and cloud/Vue check.*
- **AC-2a** Given a cloud method of kind External, then only bank accounts are offered and only a bank account is accepted — on the dashboard, in the API, and in a cloud till's read-only view. *Cloud PHPUnit, POS widget with a cloud till, Vue check.*
- **AC-2b** The pairing table is identical in the POS and the cloud: a test on each side asserts the same cases (every method kind × account kind). *POS unit test and cloud PHPUnit.*
- **AC-3** When the POS repository is asked to save Card → a cash account, then it refuses with the new reason and saves nothing; a matching account saves. *POS repository test (PostgreSQL) and a pure `AccountRules` unit test.*
- **AC-4** When the cloud API is asked to set Card → a cash account, then 422 with a clear message and nothing stored; a matching account stores; another restaurant's account is still 404/422. *Cloud PHPUnit.*
- **AC-5** Given a default already saved as Card → drawer, then the screen shows it marked as not matching, offers the bank accounts and "no account", and the stored row is unchanged until the person changes it. *POS widget test; cloud check.*
- **AC-6** Arabic and English show the marker and the refusal. *Widget tests in both languages.*
- **AC-7** A disabled account, a branch account of another branch and a business-wide default still follow the old rules. *Existing tests pass.*
- **AC-8** The cloud dashboard select shows the same lists as AC-1/AC-2. *Needs a person: the web app has no test framework.*

## 9. Edge cases and failure modes
- A restaurant with no account of the needed type: the method offers only "no account" (and the page should say there is no matching account rather than show an empty select; wording to be settled in the plan).
- A cloud method of kind `external` is a card on the till (`tender_method.dart:86`), so it offers bank accounts on the platform as well: the dashboard and a cloud till agree.
- An account whose kind is edited after being chosen: it can become a mismatch; BR-4 covers it, and the edit itself is allowed (**decision open**, §13).
- Offline/outbox: no payment reads defaults, so retry and sync are unaffected. The bundle may carry a mismatched default authored before this change; the seeder must keep it (**UNVERIFIED** that it does not validate).
- Tenant boundary and idempotency: unchanged; the new check reads only the same restaurant's rows.

## 10. Impact
- **POS:** `financial_account.dart` (the rule and a new `AccountProblem`), `management_accounts_pane.dart`, `postgres_financial_accounts_admin_repository.dart`, `admin_messages.dart`, two strings (en/ar), tests.
- **Cloud API:** a rule in `FinancialAccount`/`SetTenderAccountDefaultRequest`, a message in the lang files, tests. This is a **validation tightening**: a request that was valid becomes 422.
- **Cloud web:** `FinancialAccountsPanel.vue` filters the select and marks a mismatch.
- **Schema/migrations:** none. **Bundle/contract:** shape unchanged; defaults still flow as they are.
- **Deploy order:** the platform and the till deploy independently and neither depends on the other; an old POS still sends its own local saves and is unaffected, an old dashboard cached in a browser could post a mismatch and gets the 422.
- **Docs:** `financial-accounts` line 98 and XORD-015's note, inventory row, this folder.

## 11. Dependencies, known gaps, risks
- ~~The platform has no `wallet` kind.~~ It has one now (D-6): the dashboard's payment-method form, the API validation, the bundle value and the POS's `PlatformTenderKind` carry it. An older POS build reads an unknown kind as an ordinary non-cash method until it is updated.
- The cloud API change reaches `xorder-cloud` `main` (production); it needs the release check and the owner's push.
- Both repos carry many uncommitted files; these edits will mix with them.
- Domain lens (`FOOD_SERVICE_DOMAIN.md`): a café's single drawer and bank, a restaurant's drawer/bank/wallets, a food truck's cash and wallet, a cloud kitchen's bank only — all gain; none assumes tables or addresses.

## 12. How it will be tested
POS: pure `AccountRules` tests (every method kind × account kind), a pane widget test in both languages, the repository test in `financial_accounts_test` (PostgreSQL; **not run** without `POS_PG_*` — reported as such). Cloud: PHPUnit on SQLite (`FinancialAccountsTest` extended; PostgreSQL behaviour is not exercised, though nothing here is PostgreSQL-specific). Vue: no framework; a person checks AC-8.

## 13. Decisions and open questions
**Decided by the owner, 2026-10-26**
- **D-1** Cash → cash accounts; Card → bank accounts; Wallet → wallet accounts. Methods with no natural type (On account, Voucher, Other; cloud Other) keep offering every account.
- **D-2** The rule is enforced **on save** in the POS repository and the cloud API, as well as hidden in the screens.
- **D-3** A default already saved against the wrong type is **kept and marked**, never cleared automatically.
- **D-4** **Cloud and on-premise behave the same.** One rule over both vocabularies; a cloud method of kind **External offers bank accounts**, like Card, because that is how the till already reads it. (This replaces D-1's earlier note that External offers every account.)
- **D-5** ~~Wallets stay a till-only kind for now.~~ Superseded by D-6.
- **D-6 (2026-10-26)** The owner: "I want it to not be same but I want same behavior on both" — so the **platform gains a `wallet` payment-method kind** and a wallet method pairs with wallet accounts on both sides. Additive; see `API.md` for the rollout order (cloud first).

**Still open (defaults taken)**
- **Q-1** Editing an account's kind after it is a default of a method it no longer fits: allowed, and the default shows as a mismatch (BR-4). Alternative: refuse the edit. Default: allow.
- **Q-2** Wording for "no account of this type exists yet". Default: a short hint under the method naming the needed type.
