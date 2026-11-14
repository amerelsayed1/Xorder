# Technical plan — finance-account-kind-per-method
Status: **plan, awaiting approval** · 2026-10-26 · Spec: `FEATURE.md` · Repos: `apps/xorder-pos`, `apps/xorder-cloud` (api + web) · Sources: pos `a6f5fe5` + uncommitted tree, cloud `06bc8e3` + 154 uncommitted files (neither is this feature's)

## Re-verified against the working trees
- POS: `AccountRules.defaultProblem(account, {branchId})` checks active and branch only (`financial_account.dart`); `setDefault` selects `1` from `pos_tender_types` and then calls it (`postgres_financial_accounts_admin_repository.dart:225-290`); `_DefaultsRow` builds chips from `accounts` filtered only by branch (`management_accounts_pane.dart:359-465`) and, read-only (cloud), prints `label: currentName`.
- Cloud: `SetTenderAccountDefaultRequest::after` checks active and branch only; `FinancialAccount::KINDS = ['cash','bank','wallet']`; payment-method kinds are `cash,card,external,other` (`StoreTenderTypeRequest.php:19`); lang keys `xorder.validation.account_*` in `lang/{en,ar}/xorder.php`; the dashboard selects use `fallbackChoices` / `branchChoices` with no kind filter (`FinancialAccountsPanel.vue:160-161,260,273`); tests in `tests/Feature/Pos/FinancialAccountsTest.php`.
- The till already reads a platform `external` as `card` (`tender_method.dart:86`), so on a cloud till every method arrives as a till kind and the POS rule needs no platform special case. No discrepancy with `FEATURE.md`.
- **UNVERIFIED:** that the bootstrap seeder writes platform defaults without validating them (stage 1 of `financial-accounts` says it copies rows). It must keep legacy mismatches, so I will read it before editing and add a test that a mismatched default arrives intact.

## The rule, once per codebase (BR-1, BR-6)
| Method kind | Allowed account kinds | null = all |
|---|---|---|
| POS `cash` | `cash` | |
| POS `card` | `bank` | |
| POS `wallet` | `wallet` | |
| POS `account`, `voucher`, `other` | | all |
| Cloud `cash` / `card` / `external` / `other` | `cash` / `bank` / `bank` / all | |

POS: `AccountRules.kindsFor(TenderKind)` and `fits(TenderKind, AccountKind)` (pure Dart, no Flutter). Cloud: `FinancialAccount::kindsForTender(string $kind): ?array` and `fitsTender(...)`. A test on each side asserts the same table row by row (AC-2b).

## Stages
| # | Repo and files | Change | Proof | Rollback |
|---|---|---|---|---|
| 0 | both | Baselines: POS `flutter analyze` and the accounts suites; cloud `php artisan test --filter FinancialAccounts` | recorded output | — |
| 1 | POS `financial_account.dart`, `app_strings.dart` (en/ar), `admin_messages.dart` | `kindsFor`, `fits`, new `AccountProblem.accountKindMismatch`, `defaultProblem` takes the method's kind; message `refusalAccountKindMismatch` | `test/domain/account_rules_test.dart`: every method kind × account kind (18 pairs) | revert the three files |
| 2 | POS `postgres_financial_accounts_admin_repository.dart` | `setDefault` reads the method's `kind`, refuses a mismatch with the new reason, saves nothing; clearing ("no account") always allowed; reading and the seeder untouched | extend `data/financial_accounts_test` (PostgreSQL: **not run here** without `POS_PG_*`, reported as such) plus a fake-repository test of the refusal | revert the file |
| 3 | POS `management_accounts_pane.dart` | `_DefaultsRow` filters chips by `AccountRules.fits(method.kind, account.kind)`; a saved default that no longer fits is shown with a "not matching" marker (also in the read-only cloud-till text) and the only choices are matching accounts or "no account"; a method with no account of the needed type shows a hint | `test/features/accounts_kind_filter_test.dart`: Cash/Card/Wallet lists, other kinds all, mismatch marker, read-only cloud till, Arabic and English, 1024×700 | revert the file |
| 4 | cloud `FinancialAccount.php`, `SetTenderAccountDefaultRequest.php`, `lang/{en,ar}/xorder.php` | the rule; 422 `financial_account_id` with `account_kind_mismatch`; the method is read inside the caller's restaurant (the id is already validated against it) | `Pos/FinancialAccountsTest`: card→cash account 422, card→bank 200, external→bank 200, external→wallet 422, other→any 200, cash→bank 422, another restaurant's account still refused, clearing still 200, a legacy mismatch is **not** touched by reading it; a table test equal to the POS table | `git checkout` the three files (no migration) |
| 5 | cloud web `FinancialAccountsPanel.vue`, its locale files | `accountKindsFor(method.kind)` filters `fallbackChoices` and `branchChoices` per method; marker for a legacy mismatch; hint when none match | `pnpm build`; **a person looks** (no JS test framework) | revert the files |
| 6 | docs | `financial-accounts` line 98 and XORD-015 note amended; inventory row; TEST_PLAN, TEST_REPORT, CHANGELOG; tracker | — | — |

Stages 1–3 (POS) and 4–5 (cloud) are independent of each other and can land in either order. Existing tests that pair mismatched kinds (for example a card default pointed at a drawer) will fail on purpose; each is listed in the report and given a matching account, not deleted.

## Verification commands
`cd apps/xorder-pos && flutter analyze && flutter test test/domain/account_rules_test.dart test/features/accounts_kind_filter_test.dart` (then the full suite; `scripts/check.sh` for PostgreSQL if a server is available); `cd apps/xorder-cloud/apps/api && php artisan test --filter FinancialAccounts` (SQLite `:memory:`; nothing here is PostgreSQL-specific, but PostgreSQL is not exercised); `cd apps/xorder-cloud && pnpm build`.

## Impact, rollout, risks
- No migration, no schema change, no bundle shape change. The only contract change is a new 422 reason on an existing endpoint (`PUT tender-account-defaults`) for a request that used to succeed.
- **Rollout:** cloud and POS deploy independently. An old dashboard cached in a browser can post a mismatch and gets the 422 with a readable message. An old POS build is unaffected (a cloud till is read-only; an offline till has its own repository). New POS builds and the platform enforce the same table.
- Legacy mismatches already stored stay stored and are marked (D-3); nothing is cleared.
- Risks: the cloud change reaches `xorder-cloud` `main` (production deploy on push; the owner pushes after `/release-check`); the PostgreSQL repository test and the Vue panel are not machine-checked here; both repos hold many uncommitted files, so edits mix with unfinished work and I will not revert or commit any of it.
- Domain lens: café, restaurant, food truck and cloud kitchen all gain; the wallet difference between platform and till (D-5) is the one known asymmetry.

## Approvals needed
1. Your go on this plan.
2. **The cloud API validation tightening** (stage 4), because it turns a request that used to succeed into a 422 — explicitly, as the contract change. No push, merge or deploy from me; `/release-check` before you push.
Open defaults (FEATURE.md §13): Q-1 editing an account's kind is allowed and shows as a mismatch; Q-2 a short hint when no account of the needed type exists.
